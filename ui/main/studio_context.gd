class_name StudioContext
extends Node
## Shared state for the editor UI: the rig (output, universe, fixtures, cues),
## the current selection and the transport. Panels get a reference to this and
## listen to its signals instead of talking to each other directly.
##
## DMX protocol code stays in addons/lucky_dmx; this only wires it together.

signal fixtures_changed
signal selection_changed(fixture: DMXFixture)
## A fixture was moved or rotated on the stage (drag, gizmo or inspector).
signal fixture_moved(fixture: DMXFixture)
## Someone pressed F2 or double-clicked a fixture: the inspector focuses its name field.
signal rename_requested(fixture: DMXFixture)
## A structure piece (truss, corner box, base plate) was picked on the stage, or
## null when none is. The inspector shows its details.
signal piece_selection_changed(piece: StructurePiece)
## A piece was moved, turned or renamed from the inspector; the stage view
## collects the truss tubes again.
signal piece_moved(piece: StructurePiece)
signal transport_changed
signal blackout_changed(active: bool)
signal workspace_changed(workspace: Workspace)
signal cues_changed
## A look was applied, saved, renamed or deleted (the shelf listens).
signal looks_changed
## Editing a look started or ended (`look` is null when it ended).
signal look_editing_changed(look: Look)
signal song_changed(song: Song)
## The linked show should start: fired when a song starts playing from
## stopped or paused. The show player will listen to this once shows exist.
signal show_started(song: Song)

enum Workspace { STAGE, PROGRAM, LIVE }

const META_POSITION := &"stage_position" ## Vector3, the fixture's mounting point in the room
const META_BASIS := &"stage_basis" ## Basis; local -Y is where the beam points
## Your own name for a fixture ("Left wash"). The node name stays fixed
## ("Par 3") because recorded cues find fixtures by node path.
const META_LABEL := &"display_name"
const META_BODY := &"stage_body"
const META_PROFILE_LABEL := &"profile_label"

# The rig's nodes live in studio_context.tscn. Set the Art-Net target on the
# ArtNet node: 127.0.0.1 keeps packets on this computer until you have an
# interface; use the node's IP (or a broadcast address) for real lights.
@onready var output: ArtNetOutput = $ArtNet
@onready var universe: DMXUniverse = $Universe1
@onready var rig: Node = $Rig ## parent of every DMXFixture
@onready var cue_stack: CueStack = $Cues
@onready var library: SongLibrary = $Songs
@onready var looks: LookLibrary = $Looks ## the Looks shelf
@onready var music_player: AudioStreamPlayer = $Music
@onready var dj: DJSync = $DJSync ## follows the DJ software; off until a source is picked

var song: Song ## the song loaded on the timeline, or null

var selected: DMXFixture
var selected_piece: StructurePiece ## set by the stage view, never alongside `selected`
## The node holding every structure piece (the stage view sets it), so the
## inspector can tell what a piece is joined to.
var set_root: Node3D
## The truss tubes on stage (kept up to date by the stage view), for hanging
## fixtures from code.
var truss_pipes: Array[StageRoom.Pipe] = []
## The floor, wall and booth boxes fixtures stand on (also from the stage view),
## so the inspector can tell how a fixture is mounted.
var stage_surfaces: Array[StageRoom.Surface] = []
## The one undo history for the whole app (Ctrl+Z undo, Ctrl+R redo). Every
## edit goes through record() or one of the helpers below, so panels never
## keep their own.
var history := UndoRedo.new()

## Mirror mode for the stage (toolbar "Mirror"): fixtures and truss pieces are
## copied across a plane and kept in step. See StageSymmetry.
var symmetry := StageSymmetry.new()
## Opens on Stage so a first launch goes straight to building the rig.
var workspace: Workspace = Workspace.STAGE

# Transport
var bpm: float = 128.0
var playing: bool = false
var position_beats: float = 0.0
var length_beats: float = 256.0 ## 64 bars of 4/4 until a song sets the length
var song_title: String = ""
var show_name: String = "Untitled show"

var blackout: bool = false:
	set(value):
		blackout = value
		if universe:
			universe.blackout_held = value
		blackout_changed.emit(value)

var _counters: Dictionary = {} ## short name -> last number used

const HISTORY_STEPS := 300


func _ready() -> void:
	history.max_steps = HISTORY_STEPS
	library.songs_changed.connect(_on_library_changed)
	looks.looks_changed.connect(looks_changed.emit)

	music_player.finished.connect(_on_music_finished)
	dj.ctx = self
	library.songs_changed.connect(func() -> void:
		if dj.source and dj.matched == null:
			dj.rematch())


func _process(delta: float) -> void:
	if dj and dj.is_following():
		_follow_dj()
		return
	if not playing:
		return
	if song and music_player.playing:
		# The audio clock is the master: lights follow the music, not the frame rate.
		var t := music_player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
		position_beats = clampf(seconds_to_beats(t), 0.0, length_beats)
	else:
		position_beats += delta * bpm / 60.0
		if position_beats >= length_beats:
			position_beats = 0.0
	transport_changed.emit()


## While DJ sync is on, the DJ's deck is the clock: their play/pause is our
## play/pause and their playhead is our playhead. We play no audio.
func _follow_dj() -> void:
	var now_playing := dj.source.playing and song != null
	if now_playing and not playing:
		show_started.emit(song)
	var changed := now_playing != playing
	playing = now_playing
	if song:
		var beats := clampf(seconds_to_beats(dj.position_seconds()), 0.0, length_beats)
		changed = changed or not is_equal_approx(beats, position_beats)
		position_beats = beats
	if changed:
		transport_changed.emit()


# ---------------------------------------------------------------- fixtures

func fixtures() -> Array[DMXFixture]:
	var list: Array[DMXFixture] = []
	for child in rig.get_children():
		if child is DMXFixture:
			list.append(child)
	return list


func add_fixture(entry: FixtureCatalog.Entry, stage_position: Vector3, stage_basis: Basis = Basis.IDENTITY) -> DMXFixture:
	var xf := Transform3D(stage_basis, stage_position)
	if not symmetry.active() or symmetry.on_plane(xf):
		return _add_fixture_one(entry, stage_position, stage_basis)
	# Mirror mode: the twin goes down with it, as one undo step.
	var flip := symmetry.default_flip(xf)
	var twin_xf := symmetry.mirror_transform(xf, flip)
	begin_step("Add mirrored fixtures")
	var fx := _add_fixture_one(entry, stage_position, stage_basis)
	var twin := _add_fixture_one(entry, twin_xf.origin, twin_xf.basis)
	end_step()
	StageSymmetry.link(fx, twin, flip)
	select(fx)
	return fx


func _add_fixture_one(entry: FixtureCatalog.Entry, stage_position: Vector3, stage_basis: Basis) -> DMXFixture:
	var count := entry.profile.channels.size()
	var fx := DMXFixture.new()
	_counters[entry.short_name] = int(_counters.get(entry.short_name, 0)) + 1
	fx.name = "%s %d" % [entry.short_name, _counters[entry.short_name]]
	fx.profile = entry.profile
	fx.universe = universe
	fx.start_address = next_free_address(count)
	fx.set_meta(META_POSITION, stage_position)
	fx.set_meta(META_BASIS, stage_basis)
	fx.set_meta(META_BODY, entry.body)
	fx.set_meta(META_PROFILE_LABEL, entry.profile.fixture_name)
	rig.add_child(fx)
	fixtures_changed.emit()
	select(fx)
	var index := fx.get_index()
	record_added("Add fixture", fx, _attach_fixture.bind(fx, index), _detach_fixture.bind(fx))
	return fx


## Take a fixture off the stage. Undo puts it back where it was in the rig
## (same patch, look and name), so recorded cues still find it.
func remove_fixture(fx: DMXFixture) -> void:
	if fx == null or fx.get_parent() != rig:
		return
	var twin := StageSymmetry.partner_of(fx) if symmetry.active() else null
	if twin != null and twin.get_parent() == rig:
		var pair: Array = [fx, twin]
		pair.sort_custom(func(a: Node, b: Node) -> bool: return a.get_index() < b.get_index())
		var indices: Array = pair.map(func(n: Node) -> int: return n.get_index())
		record_removed_all("Remove mirrored fixtures", pair, attach_fixtures.bind(pair, indices), detach_fixtures.bind(pair))
		return
	record_removed("Remove fixture", fx, _attach_fixture.bind(fx, fx.get_index()), _detach_fixture.bind(fx))


func _attach_fixture(fx: Object, index: int) -> void:
	if not is_instance_valid(fx) or (fx as Node).get_parent() != null:
		return
	rig.add_child(fx as Node)
	rig.move_child(fx as Node, mini(index, rig.get_child_count() - 1))
	fixtures_changed.emit()
	select(fx as DMXFixture)


func _detach_fixture(fx: Object) -> void:
	if not is_instance_valid(fx) or (fx as Node).get_parent() != rig:
		return
	if selected == fx:
		select(null)
	rig.remove_child(fx as Node)
	_clear_universe()
	fixtures_changed.emit()


## For a group delete (StageView): take these fixtures off, or put them back
## at `indices` (their places in the rig, in rising order, as before removal).
func detach_fixtures(list: Array) -> void:
	for fx: Object in list:
		_detach_fixture(fx)


func attach_fixtures(list: Array, indices: Array) -> void:
	for i in list.size():
		_attach_fixture(list[i], int(indices[i]))


func select(fx: DMXFixture) -> void:
	if selected == fx:
		return
	selected = fx
	selection_changed.emit(fx)


func select_piece(piece: StructurePiece) -> void:
	if selected_piece == piece:
		return
	selected_piece = piece
	piece_selection_changed.emit(piece)


## Every structure piece on stage.
func structure_pieces() -> Array[StructurePiece]:
	var list: Array[StructurePiece] = []
	if set_root:
		for c in set_root.get_children():
			if c is StructurePiece and not c.is_queued_for_deletion():
				list.append(c)
	return list


## The name shown for a piece: your own name if you gave one, else its type.
static func piece_name(piece: StructurePiece) -> String:
	return String(piece.get_meta(META_LABEL, piece.display_name))


## Give a piece your own name. An empty name goes back to its type ("Truss 2 m").
func rename_piece(piece: StructurePiece, new_name: String) -> void:
	var clean := new_name.strip_edges()
	if clean == piece.display_name:
		clean = ""
	var old := String(piece.get_meta(META_LABEL, ""))
	if clean == old:
		return
	record("Rename structure piece", _apply_piece_label.bind(piece, clean), _apply_piece_label.bind(piece, old), true)


func _apply_piece_label(piece: Object, label: String) -> void:
	if not is_instance_valid(piece):
		return
	if label.is_empty():
		piece.remove_meta(META_LABEL)
	else:
		piece.set_meta(META_LABEL, label)
	piece_moved.emit(piece)


## Put a piece at `xform` (typed in the inspector), with undo. Quick repeated
## nudges merge into one step.
func place_piece(piece: StructurePiece, xform: Transform3D) -> void:
	var before := piece.global_transform
	if xform.is_equal_approx(before):
		return
	record("Move structure piece", _restore_piece.bind(piece, xform), _restore_piece.bind(piece, before),
		true, _merge_key(piece, "place"))


func _restore_piece(piece: Object, xform: Transform3D) -> void:
	if is_instance_valid(piece) and (piece as Node).is_inside_tree():
		(piece as StructurePiece).global_transform = xform
		piece_moved.emit(piece as StructurePiece)


func move_fixture(fx: DMXFixture, xform: Transform3D) -> void:
	fx.set_meta(META_POSITION, xform.origin)
	fx.set_meta(META_BASIS, xform.basis.orthonormalized())
	fixture_moved.emit(fx)
	var twin := StageSymmetry.partner_of(fx) if symmetry.active() else null
	if twin is DMXFixture:
		symmetry.suspended = true # the twin moving must not drag this one back
		move_fixture(twin as DMXFixture, symmetry.twin_transform(fx, xform))
		symmetry.suspended = false


## Remember a finished drag of `fx` from `before` to where it is now, so it
## can be undone. A click that didn't move it records nothing. With `merge`,
## quick repeated nudges (typing in the inspector's boxes, holding an arrow)
## become one step.
func record_move(fx: DMXFixture, before: Transform3D, action: String, merge := false) -> void:
	var after := fixture_transform(fx)
	if after.is_equal_approx(before):
		return
	var twin := StageSymmetry.partner_of(fx) if symmetry.active() else null
	if twin == null:
		record(action, _restore_placement.bind(fx, after), _restore_placement.bind(fx, before),
			false, _merge_key(fx, "place") if merge else "")
		return
	# Mirror mode: the twin's move is part of the same step.
	if merge:
		history.create_action("%s [%s]" % [action, _merge_key(fx, "place")], UndoRedo.MERGE_ENDS)
	else:
		history.create_action(action)
	history.add_do_method(_restore_placement.bind(fx, after))
	history.add_undo_method(_restore_placement.bind(fx, before))
	history.add_do_method(_restore_placement.bind(twin, symmetry.twin_transform(fx, after)))
	history.add_undo_method(_restore_placement.bind(twin, symmetry.twin_transform(fx, before)))
	history.commit_action(false)


func _restore_placement(fx: Object, xform: Transform3D) -> void:
	if is_instance_valid(fx) and (fx as Node).is_inside_tree():
		move_fixture(fx as DMXFixture, xform)


## Set a look property (dimmer, color, white, strobe, pan, tilt...) as one
## undo step. Quick repeats on the same fixture and property (the mouse wheel
## on a slider, a box's arrows) merge into a single step.
func set_fixture_value(fx: DMXFixture, prop: StringName, value: Variant) -> void:
	var before: Variant = fx.get(prop)
	fx.set(prop, value)
	record_fixture_value(fx, prop, before, true)


## The property was already changed (by dragging a slider or the colour
## picker): store the change from `before` to its value now as one step.
func record_fixture_value(fx: DMXFixture, prop: StringName, before: Variant, merge := false) -> void:
	var after: Variant = fx.get(prop)
	if after == before:
		return
	record("Change %s" % prop, _apply_value.bind(fx, prop, after), _apply_value.bind(fx, prop, before),
		false, _merge_key(fx, prop) if merge else "")


func _apply_value(fx: Object, prop: StringName, value: Variant) -> void:
	if is_instance_valid(fx):
		fx.set(prop, value)


## Re-patch a fixture to a new start address, with undo.
func set_address(fx: DMXFixture, address: int) -> void:
	if fx.start_address == address:
		return
	record("Patch fixture", _apply_address.bind(fx, address), _apply_address.bind(fx, fx.start_address),
		true, _merge_key(fx, "address"))


func _apply_address(fx: Object, address: int) -> void:
	if is_instance_valid(fx):
		(fx as DMXFixture).start_address = address
		_clear_universe()
		fixtures_changed.emit()


# ---------------------------------------------------------------- undo / redo

## Add a step to the undo history. `do_call` redoes it and `undo_call` undoes
## it; with `execute` false the change has already happened. Steps with the
## same non-empty `merge_key` less than a moment apart become one step.
func record(action: String, do_call: Callable, undo_call: Callable, execute := false, merge_key := "") -> void:
	if merge_key.is_empty():
		history.create_action(action)
	else:
		# UndoRedo merges same-named MERGE_ENDS actions made within 800 ms, keeping
		# the first undo and the last do. The key keeps fixtures/properties apart.
		history.create_action("%s [%s]" % [action, merge_key], UndoRedo.MERGE_ENDS)
	history.add_do_method(do_call)
	history.add_undo_method(undo_call)
	history.commit_action(execute)


## `obj` was just added (and is attached now). Undo calls `detach`, redo `attach`.
## The history keeps `obj` alive while it is detached and frees it once the
## step can't be redone any more.
func record_added(action: String, obj: Object, attach: Callable, detach: Callable) -> void:
	history.create_action(action)
	history.add_do_method(attach)
	history.add_undo_method(detach)
	history.add_do_reference(obj)
	history.commit_action(false)


## Like record_added, for several things added together (a mirrored pair).
func record_added_all(action: String, objs: Array, attach: Callable, detach: Callable) -> void:
	history.create_action(action)
	history.add_do_method(attach)
	history.add_undo_method(detach)
	for obj: Object in objs:
		history.add_do_reference(obj)
	history.commit_action(false)


## Remove `obj` now by calling `detach`; undo calls `attach`. The history keeps
## `obj` alive until the step falls off the end of the history.
func record_removed(action: String, obj: Object, attach: Callable, detach: Callable) -> void:
	history.create_action(action)
	history.add_do_method(detach)
	history.add_undo_method(attach)
	history.add_undo_reference(obj)
	history.commit_action()


## Like record_removed, for several things taken away together (a box
## selection deleted at once): `detach` removes them all now, undo calls
## `attach`, and the history keeps every one of them alive meanwhile.
func record_removed_all(action: String, objs: Array, attach: Callable, detach: Callable) -> void:
	history.create_action(action)
	history.add_do_method(detach)
	history.add_undo_method(attach)
	for obj: Object in objs:
		history.add_undo_reference(obj)
	history.commit_action()


## Several edits as one undo step: everything recorded between begin_step() and
## end_step() is undone together (e.g. loading the demo rig).
func begin_step(action: String) -> void:
	history.create_action(action)


func end_step() -> void:
	history.commit_action(false)


func undo() -> bool:
	if history.is_committing_action():
		return false
	return history.undo()


func redo() -> bool:
	if history.is_committing_action():
		return false
	return history.redo()


func _merge_key(obj: Object, what: String) -> String:
	return "%d:%s" % [obj.get_instance_id(), what]


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and history:
		history.free()


## Front bottom bars of the two default trusses (stage_room.tscn's Set).
const FRONT_TRUSS_TUBE := Vector3(0, 3.536, 0.621)
const BACK_TRUSS_TUBE := Vector3(0, 3.536, -0.679)


## Add a fixture clamped onto the truss tube nearest `near`, with the middle of
## its clamps as close to `near` as the tube allows. With no truss on stage it
## just hangs at `near`.
func hang_fixture(entry: FixtureCatalog.Entry, near: Vector3) -> DMXFixture:
	var pipe := StageRoom.pipe_near(truss_pipes, near)
	if pipe == null:
		return add_fixture(entry, near)
	var mounts := StageFixture3D.mounts_of(StageFixture3D.scene_path(entry.body, entry.profile.fixture_name))
	var xf := StageRoom.hang(pipe, pipe.along_of(near), mounts, pipe.face_for(near - pipe.point(pipe.along_of(near))))
	return add_fixture(entry, xf.origin, xf.basis)


## Where a fixture sits on the stage and which way it faces.
static func fixture_transform(fx: DMXFixture) -> Transform3D:
	var b: Basis = fx.get_meta(META_BASIS, Basis.IDENTITY)
	var p: Vector3 = fx.get_meta(META_POSITION, Vector3.ZERO)
	return Transform3D(b, p)


## The name shown everywhere in the UI: your own name if you gave one.
static func display_name(fx: DMXFixture) -> String:
	return String(fx.get_meta(META_LABEL, fx.name))


## Give a fixture your own name. An empty name goes back to "Par 3" style.
func rename_fixture(fx: DMXFixture, new_name: String) -> void:
	if fx == null:
		return
	var clean := new_name.strip_edges()
	if clean == String(fx.name):
		clean = ""
	var old := String(fx.get_meta(META_LABEL, ""))
	if clean == old:
		return
	record("Rename fixture", _apply_label.bind(fx, clean), _apply_label.bind(fx, old), true)


func _apply_label(fx: Object, label: String) -> void:
	if not is_instance_valid(fx):
		return
	if label.is_empty():
		fx.remove_meta(META_LABEL)
	else:
		fx.set_meta(META_LABEL, label)
	fixtures_changed.emit()


func request_rename(fx: DMXFixture) -> void:
	if fx:
		select(fx)
		rename_requested.emit(fx)


## First address with `count` free channels in a row (1-based), or 1 if full.
func next_free_address(count: int) -> int:
	var used := PackedByteArray()
	used.resize(513)
	for fx in fixtures():
		for i in fx.profile.channels.size():
			var a := fx.start_address + i
			if a <= 512:
				used[a] = 1
	var run := 0
	for a in range(1, 513):
		run = 0 if used[a] else run + 1
		if run == count:
			return a - count + 1
	return 1


## Move every fixture that clashes with an earlier one (or runs past 512) to
## the first free gap. Fixtures that were fine stay exactly where they are.
## One undo step. Returns how many were moved.
func fix_overlaps() -> int:
	var used := PackedByteArray()
	used.resize(513)
	var movers: Array[DMXFixture] = []
	for fx in fixtures():
		var count := fx.profile.channels.size()
		var clash := fx.start_address < 1 or fx.start_address + count - 1 > 512
		for i in count:
			if not clash and used[fx.start_address + i]:
				clash = true
		if clash:
			movers.append(fx)
		else:
			for i in count:
				used[fx.start_address + i] = 1
	if movers.is_empty():
		return 0
	begin_step("Fix DMX overlaps")
	for fx in movers:
		var count := fx.profile.channels.size()
		var at := _free_run(used, count)
		for i in count:
			if at + i <= 512:
				used[at + i] = 1
		_patch_in_step(fx, at)
	end_step()
	return movers.size()


## Line every fixture up one after another from channel 1, in rig order, with
## no gaps. One undo step.
func pack_addresses() -> void:
	begin_step("Pack DMX addresses")
	var at := 1
	for fx in fixtures():
		_patch_in_step(fx, at)
		at += fx.profile.channels.size()
	end_step()


func _patch_in_step(fx: DMXFixture, address: int) -> void:
	if fx.start_address == address:
		return
	history.add_do_method(_apply_address.bind(fx, address))
	history.add_undo_method(_apply_address.bind(fx, fx.start_address))
	_apply_address(fx, address)


## First `count` free addresses in a row in `used` (1-based), or 1 if none.
static func _free_run(used: PackedByteArray, count: int) -> int:
	var run := 0
	for a in range(1, 513):
		run = 0 if used[a] else run + 1
		if run == count:
			return a - count + 1
	return 1


## "Par 1 · red" for a channel, or "" if nothing is patched there.
func channel_owner(address: int) -> String:
	for fx in fixtures():
		var i := address - fx.start_address
		if i >= 0 and i < fx.profile.channels.size():
			return "%s · %s" % [display_name(fx), fx.profile.channels[i]]
	return ""


func patched_channel_count() -> int:
	var n := 0
	for fx in fixtures():
		n += fx.profile.channels.size()
	return n


func _clear_universe() -> void:
	# Fixtures rewrite their own channels every frame; this clears the rest.
	universe.data.fill(0)


# ---------------------------------------------------------------- transport

## True while the DJ's software drives the transport (local play/seek are off).
func following_dj() -> bool:
	return dj != null and dj.is_following()


func toggle_play() -> void:
	if following_dj():
		return
	playing = not playing
	if song:
		if playing:
			if position_beats >= length_beats:
				position_beats = 0.0
			music_player.play(beats_to_seconds(position_beats))
			show_started.emit(song)
		else:
			music_player.stop() # position_beats keeps where we paused
	transport_changed.emit()


func stop() -> void:
	if following_dj():
		return
	playing = false
	position_beats = 0.0
	music_player.stop()
	transport_changed.emit()


func seek(beats: float) -> void:
	if following_dj():
		return
	position_beats = clampf(beats, 0.0, length_beats)
	if song and music_player.playing:
		music_player.seek(beats_to_seconds(position_beats))
	transport_changed.emit()


func set_bpm(value: float) -> void:
	var seconds := beats_to_seconds(position_beats)
	bpm = clampf(value, 40.0, 220.0)
	if song:
		# Same moment in the song, new grid. The song remembers its tempo.
		position_beats = seconds_to_beats(seconds)
		length_beats = seconds_to_beats(song.duration)
		if not is_equal_approx(song.bpm, bpm):
			song.bpm = bpm
			library.update(song)
	transport_changed.emit()


func beats_to_seconds(beats: float) -> float:
	return beats * 60.0 / bpm


func seconds_to_beats(seconds: float) -> float:
	return seconds * bpm / 60.0


# ---------------------------------------------------------------- songs

## Put a song on the timeline: its audio, tempo, length and linked show.
func load_song(s: Song) -> void:
	if s == song:
		return
	var was_playing := playing and not following_dj()
	playing = false
	position_beats = 0.0
	music_player.stop()
	song = s
	if s == null:
		music_player.stream = null
		song_title = ""
		show_name = "Untitled show"
		length_beats = 256.0
	else:
		music_player.stream = AudioDecoder.load_stream(s.file_path)
		if s.bpm > 0.0:
			bpm = s.bpm
		song_title = s.display_title()
		show_name = s.show_name
		length_beats = seconds_to_beats(s.duration)
		library.ensure_peaks(s)
	song_changed.emit(s)
	transport_changed.emit()
	if was_playing and s:
		toggle_play()


## Drop files on the window or pick them in the import dialog. If nothing is
## on the timeline yet, the first new song is loaded.
func import_songs(paths: PackedStringArray) -> Array[Song]:
	var added := library.import_files(paths)
	if song == null and not added.is_empty():
		load_song(added[0])
	return added


func _on_library_changed() -> void:
	if song and not library.songs.has(song):
		load_song(null)


func _on_music_finished() -> void:
	playing = false
	position_beats = length_beats
	transport_changed.emit()


func set_workspace(value: Workspace) -> void:
	workspace = value
	workspace_changed.emit(value)


# ---------------------------------------------------------------- cues

func record_cue() -> void:
	var cue := cue_stack.record_cue("", 1.0)
	cues_changed.emit()
	record("Record cue", _insert_cue.bind(cue, cue_stack.cues.size() - 1), _remove_cue.bind(cue))


func _insert_cue(cue: LightCue, index: int) -> void:
	if not cue_stack.cues.has(cue):
		cue_stack.cues.insert(mini(index, cue_stack.cues.size()), cue)
		cues_changed.emit()


func _remove_cue(cue: LightCue) -> void:
	var i := cue_stack.cues.find(cue)
	if i < 0:
		return
	cue_stack.cues.remove_at(i)
	if cue_stack.current >= i:
		cue_stack.current -= 1 # the cue after it keeps being "next"
	cues_changed.emit()


func go_cue(index: int = -1) -> void:
	if index < 0:
		cue_stack.go()
	else:
		cue_stack.go_to(index)
	cues_changed.emit()


# ---------------------------------------------------------------- looks

var _look_tween: Tween
var _applied_look: Look ## the look most recently applied, for the shelf highlight


## Store what the fixtures are doing now as a new look on the shelf.
## Returns null (and saves nothing) if another look already has that name.
func save_look(look_name: String = "") -> Look:
	var name_to_use := look_name.strip_edges()
	if name_to_use.is_empty():
		name_to_use = looks.next_name()
	if looks.is_name_taken(name_to_use):
		return null
	var look := Look.capture(rig, name_to_use)
	_applied_look = look # it is what is on stage right now
	looks.add(look)
	record("Save look", looks.add.bind(look), looks.remove.bind(look))
	return look


func delete_look(look: Look) -> void:
	if editing_look == look:
		cancel_look_edit()
	if _applied_look == look:
		_applied_look = null
	looks.remove(look)
	record("Delete look", looks.remove.bind(look), looks.add.bind(look))


func rename_look(look: Look, new_name: String) -> void:
	var before := look.look_name
	looks.rename(look, new_name)
	if look.look_name != before:
		record("Rename look", looks.rename.bind(look, look.look_name), looks.rename.bind(look, before))


## Fade the fixtures to a look (its own fade time unless `fade` is given),
## one undo step. Fixtures the look doesn't know about are left alone.
func apply_look(look: Look, fade: float = -1.0) -> void:
	var secs := look.fade_time if fade < 0.0 else fade
	var before := look.current_values(rig)
	_applied_look = look
	record("Apply look", _set_looks_values.bind(look.values, secs, look), _set_looks_values.bind(before, 0.0, null), true)


func applied_look() -> Look:
	return _applied_look


# Editing a look. Outside of this, changing fixtures never touches a saved look:
# "Save look" always makes a new one. Editing is a mode you enter on purpose
# (Edit on the shelf); the stage shows a badge while it is on, and you leave it
# with Save changes (the look takes what is on stage) or Cancel.

## The look being edited, or null.
var editing_look: Look
var _pre_edit_values: Dictionary = {} ## the stage before Edit, for Cancel


func is_editing_look() -> bool:
	return editing_look != null


## Put the look on stage (no fade) and start editing it.
func begin_look_edit(look: Look) -> void:
	if editing_look == look:
		return
	if editing_look:
		cancel_look_edit()
	_pre_edit_values = Look.capture(rig, "").values
	editing_look = look
	apply_look(look, 0.0)
	look_editing_changed.emit(look)
	looks_changed.emit()


## Store what is on stage now (and the fade time) into the look being edited.
func finish_look_edit(fade_time: float = -1.0) -> void:
	var look := editing_look
	if look == null:
		return
	var before := {"values": look.values.duplicate(true), "fade": look.fade_time}
	var after := {"values": Look.capture(rig, "").values, "fade": look.fade_time if fade_time < 0.0 else fade_time}
	editing_look = null
	_pre_edit_values = {}
	record("Edit look", _set_look_data.bind(look, after), _set_look_data.bind(look, before), true)
	look_editing_changed.emit(null)


## Leave editing without changing the look; the stage goes back to how it
## was before Edit was pressed.
func cancel_look_edit() -> void:
	if editing_look == null:
		return
	var restore := _pre_edit_values
	editing_look = null
	_pre_edit_values = {}
	_set_looks_values(restore, 0.0, null)
	look_editing_changed.emit(null)


func _set_look_data(look: Look, data: Dictionary) -> void:
	look.values = (data["values"] as Dictionary).duplicate(true)
	look.fade_time = float(data["fade"])
	looks.save(look)
	looks_changed.emit()


func _set_looks_values(values: Dictionary, secs: float, look: Look) -> void:
	if _look_tween:
		_look_tween.kill()
		_look_tween = null
	cue_stack.stop() # a cue fade would fight the look
	var fade := secs > 0.0
	if fade:
		_look_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	var added := 0
	for path in values:
		var fx := rig.get_node_or_null(NodePath(str(path))) as DMXFixture
		if fx == null:
			continue # that fixture was removed since the look was saved
		var props: Dictionary = values[path]
		for prop in props:
			if fade:
				_look_tween.tween_property(fx, NodePath(str(prop)), props[prop], secs)
				added += 1
			else:
				fx.set(prop, props[prop])
	if fade and added == 0: # an empty Tween throws an error when it starts
		_look_tween.kill()
		_look_tween = null
	_applied_look = look
	looks_changed.emit()


# ---------------------------------------------------------------- demo

## Four RGB pars and two movers in a loose arc, so a new user has something
## to click on. Bryan's real rig can replace this once profiles are saved.
func load_demo_rig() -> void:
	var catalog := FixtureCatalog.entries()
	var par: FixtureCatalog.Entry = catalog[1]
	var mover: FixtureCatalog.Entry = catalog[4]
	var colors: Array[Color] = [Color("ff3b6b"), Color("ffb547"), Color("38c6ff"), Color("8b5cff")]
	symmetry.suspended = true # the demo rig is already laid out; don't double it
	begin_step("Load demo rig") # one Ctrl+Z takes the whole rig away again
	# Clamped onto the front tubes of the two trusses, as the stage view would hang them.
	for i in 4:
		var fx := hang_fixture(par, FRONT_TRUSS_TUBE + Vector3(-3.0 + i * 2.0, 0, 0))
		fx.color = colors[i]
	for i in 2:
		var fx := hang_fixture(mover, BACK_TRUSS_TUBE + Vector3(-1.6 + i * 3.2, 0, 0))
		fx.color = Color("f5f0ff")
		fx.dimmer = 0.8
		fx.pan = 0.5 + (0.06 if i == 0 else -0.06)
		fx.tilt = 0.62
	# Two LED bars on the floor at the back wall, washing up it.
	var bar: FixtureCatalog.Entry = catalog[6]
	for i in 2:
		var fx := add_fixture(bar, Vector3(-2.6 + i * 5.2, StageFixture3D.mount_offset(bar.body), -5.55), StageRoom.mount_basis(Vector3.UP) * Basis(Vector3.UP, PI)) # lean towards the wall
		fx.color = Color("19d3c5")
	end_step()
	symmetry.suspended = false
	select(null)
