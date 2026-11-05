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
signal transport_changed
signal blackout_changed(active: bool)
signal workspace_changed(workspace: Workspace)
signal cues_changed
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
@onready var music_player: AudioStreamPlayer = $Music
@onready var dj: DJSync = $DJSync ## follows the DJ software; off until a source is picked

var song: Song ## the song loaded on the timeline, or null

var selected: DMXFixture
var workspace: Workspace = Workspace.PROGRAM

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


func _ready() -> void:
	library.songs_changed.connect(_on_library_changed)

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
	return fx


func remove_fixture(fx: DMXFixture) -> void:
	if fx == null:
		return
	if selected == fx:
		select(null)
	rig.remove_child(fx)
	fx.queue_free()
	_clear_universe()
	fixtures_changed.emit()


func select(fx: DMXFixture) -> void:
	if selected == fx:
		return
	selected = fx
	selection_changed.emit(fx)


func move_fixture(fx: DMXFixture, xform: Transform3D) -> void:
	fx.set_meta(META_POSITION, xform.origin)
	fx.set_meta(META_BASIS, xform.basis.orthonormalized())
	fixture_moved.emit(fx)


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
	if clean.is_empty() or clean == String(fx.name):
		if not fx.has_meta(META_LABEL):
			return
		fx.remove_meta(META_LABEL)
	elif clean == display_name(fx):
		return
	else:
		fx.set_meta(META_LABEL, clean)
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
	cue_stack.record_cue("", 1.0)
	cues_changed.emit()


func go_cue(index: int = -1) -> void:
	if index < 0:
		cue_stack.go()
	else:
		cue_stack.go_to(index)
	cues_changed.emit()


# ---------------------------------------------------------------- demo

## Four RGB pars and two movers in a loose arc, so a new user has something
## to click on. Bryan's real rig can replace this once profiles are saved.
func load_demo_rig() -> void:
	var catalog := FixtureCatalog.entries()
	var par: FixtureCatalog.Entry = catalog[1]
	var mover: FixtureCatalog.Entry = catalog[4]
	var colors: Array[Color] = [Color("ff3b6b"), Color("ffb547"), Color("38c6ff"), Color("8b5cff")]
	# Hung flush under the two trusses, as the stage view would place them.
	var par_y := StageRoom.TRUSS_BOTTOM - StageFixture3D.mount_offset(par.body)
	var mover_y := StageRoom.TRUSS_BOTTOM - StageFixture3D.mount_offset(mover.body)
	for i in 4:
		var fx := add_fixture(par, Vector3(-3.0 + i * 2.0, par_y, StageRoom.TRUSS_Z[0]))
		fx.color = colors[i]
	for i in 2:
		var fx := add_fixture(mover, Vector3(-1.6 + i * 3.2, mover_y, StageRoom.TRUSS_Z[1]))
		fx.color = Color("f5f0ff")
		fx.dimmer = 0.8
		fx.pan = 0.5 + (0.06 if i == 0 else -0.06)
		fx.tilt = 0.62
	# Two LED bars on the floor at the back wall, washing up it.
	var bar: FixtureCatalog.Entry = catalog[6]
	for i in 2:
		var fx := add_fixture(bar, Vector3(-2.6 + i * 5.2, StageFixture3D.mount_offset(bar.body), -5.55), StageRoom.mount_basis(Vector3.UP) * Basis(Vector3.UP, PI)) # lean towards the wall
		fx.color = Color("19d3c5")
	select(null)
