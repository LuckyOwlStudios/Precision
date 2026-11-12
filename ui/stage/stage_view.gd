class_name StageView
extends Control
## The 3D stage in the middle of the window.
##   Drop a fixture from the library  -> it clamps onto the truss tube nearest the
##                                       cursor, or sticks flush to the wall or
##                                       floor (hold Alt: no snapping)
##   Drop a structure piece            -> base plates go on the floor; truss and
##                                       corner boxes snap onto the nearest free
##                                       connector (truss end, plate, corner face)
##   Left click / double-click / F2    -> select / rename a fixture
##   Left drag a fixture               -> slide it along the tube or surface it is on
##   Left drag on empty space          -> box select fixtures (and, in the Stage
##                                       workspace, structure pieces); Shift adds.
##                                       Delete removes them all as one undo step,
##                                       dragging one of them slides them all across
##                                       the floor plan, Esc clears the selection
##   Stage workspace, a structure piece: click selects, drag re-snaps it,
##                                       R turns it a quarter turn, Delete removes it
##   Shift + left drag                 -> re-stick it onto another surface
##   W / E                             -> move / rotate gizmo; Ctrl while dragging snaps.
##                                       The rotate rings depend on how the fixture is
##                                       mounted (see MountRotation): swing around the
##                                       truss, spin under a single clamp, spin on the
##                                       spot on a floor or wall, any axis when free
##   Ctrl+Z / Ctrl+R                   -> undo / redo (main window): placing, moving,
##                                       turning and deleting fixtures and pieces
##   Hold right mouse                  -> fly, like the Godot editor: drag to look,
##                                       WASD move, Q/E down/up, Shift faster,
##                                       Alt slower, wheel sets the fly speed
##   Alt+left drag                     -> orbit       Middle drag -> pan
##   Mouse wheel                       -> zoom        F -> frame selection / rig
##   Top / Front / Side buttons        -> orthographic drawing views (numpad 7 / 1 / 3, numpad 5
##                                       back to perspective): no perspective, true to scale,
##                                       with grid, labels, trim heights and beam coverage
##                                       (see DraftingOverlay). Right or middle drag pans, wheel zooms
##                                       to the cursor, D measures, Alt+left drag goes back to a
##                                       free perspective view. Touch: two fingers pan, pinch zooms
##   T / Point at button               -> aim the selected moving heads: click or drag on the
##                                       stage and every selected head points there (one undo
##                                       step), Esc or T again to finish
##   Z / Work, Show buttons            -> work lights on (evenly lit room) / dark show room

const PICK_RADIUS_PX := 12.0 ## fallback only: a click this close to a fixture's middle picks it
const DRAG_THRESHOLD_PX := 4.0
const TOUCH_DRAG_THRESHOLD_PX := 12.0 ## a fingertip wobbles more than a mouse

const PIPE_GRAB_PX := 26.0 ## a fixture snaps to a tube this close to the cursor on screen
const CONNECTOR_GRAB_PX := 70.0 ## a piece snaps to a free connector this close on screen

const FLY_SPEED_DEFAULT := 4.0 ## metres a second
const FLY_SPEED_MIN := 0.25
const FLY_SPEED_MAX := 40.0
const FLY_FAST := 3.0 ## Shift
const FLY_SLOW := 0.25 ## Alt
const LOOK_DEG_PER_PX := 0.25
const TOUCH_ORBIT_DEG_PER_PX := 0.3
const TOUCH_PAN_PER_PX := 0.0016 ## of the camera distance
const TOUCH_PICK_PX := 24.0 ## gizmo handle reach for a fingertip (a mouse uses TransformGizmo.PICK_PX)
const ORTHO_DISTANCE := 60.0 ## the drawing camera sits well outside the room
const ORTHO_SIZE_MIN := 1.5 ## metres of height on screen
const ORTHO_SIZE_MAX := 40.0
const ORTHO_VIEWS := {
	"Top": {"kind": DraftingOverlay.Kind.PLAN, "yaw": 0.0, "pitch": -90.0, "pivot": Vector3(0, 0, -0.5), "size": 14.0},
	"Front": {"kind": DraftingOverlay.Kind.FRONT, "yaw": 0.0, "pitch": 0.0, "pivot": Vector3(0, 2.6, -0.5), "size": 9.0},
	"Side": {"kind": DraftingOverlay.Kind.SIDE, "yaw": -90.0, "pitch": 0.0, "pivot": Vector3(0, 2.6, -0.5), "size": 9.0},
}
const FLY_KEYS: Array[Key] = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E]
const HINT_MORE := "" ## the "?" button beside the hint opens the full list
const SHORTCUTS_BBCODE := "[b]Select[/b]\nClick  pick fixture or truss\nDrag empty space  box select (Shift adds)\nEsc  deselect · Delete  remove\nH  hide selection · Shift+H  isolate it · Alt+H  show all\n\n[b]Edit[/b]\nW  move gizmo · E  rotate gizmo (Ctrl while dragging snaps)\nR  turn truss piece · Shift drag  re-stick to a surface\nF2  rename · Ctrl+D  duplicate (copies follow the mouse, click to drop) · M  mirror · Ctrl+Z / Ctrl+R  undo / redo\nCtrl+C / Ctrl+V  copy a fixture's look, paste on the selection\n\n[b]Camera[/b]\nRight drag  fly (WASD, Q/E down/up, Shift faster, Alt slower, wheel speed)\nAlt + left drag  orbit · Middle drag  pan · Wheel  zoom · F  frame selection (or the rig)\nTouch: two fingers pinch zoom / orbit, three pan\n\n[b]View[/b]\nZ  work lights / show lights\nNumpad 7 / 1 / 3  top plan / front / side (drawing views, true to scale)\nNumpad 5  perspective and back\nIn a drawing view: D  measure · right or middle drag  pan · wheel  zoom to cursor\nTouch: two fingers pan, pinch zoom\n? or F1  this list"

var ctx: StudioContext

var look := StageLook.new() ## haze and render quality (visual only)
var _visuals: Dictionary = {} ## DMXFixture -> StageFixture3D

var _yaw := 0.0
var _pitch := -14.0
var _distance := 12.5
var _orbiting := false
var _panning := false
var _panning_middle := false
var _panning_right := false ## right button held in a drawing view
var _drag_threshold := DRAG_THRESHOLD_PX ## set per press: bigger for a finger
var _touches := TouchGestures.new()
var _touch_locked := false ## a gesture is going (or just ended): ignore the leftover finger's mouse events
var _view_preset := "Perspective" ## which of the view buttons is on
var _last_ortho := "Top" ## numpad 5 returns to this
var _ortho_size := 14.0 ## metres of height the drawing views show
var _persp_saved: Dictionary = {} ## the free camera, kept while a drawing view is up
var _note := "" ## a message that replaces the hint for a few seconds
var _note_until := 0
var _flying := false ## right mouse held: look around in place, WASD/QE move
var _fly_speed := FLY_SPEED_DEFAULT
var _surfaces: Array[StageRoom.Surface] = []
var _pipes: Array[StageRoom.Pipe] = [] ## truss tubes fixtures clamp onto

# Structure pieces (the truss set).
var _ghost: StructurePiece ## preview while a piece is dragged in from the library
var _ghost_path := ""
var _selected_piece: StructurePiece
var _piece_drag: StructurePiece
var _piece_drag_started := false
var _piece_before := Transform3D.IDENTITY ## where the dragged piece started, for undo

# Dragging a fixture by its body (not the gizmo).
var _dragging: DMXFixture
var _drag_started := false
var _drag_restick := false
var _press_pos := Vector2.ZERO
var _drag_plane := Plane()
var _drag_offset := Vector3.ZERO ## fixture origin minus the grab point on the plane
var _drag_screen_offset := Vector2.ZERO ## fixture on screen minus the cursor
var _drag_start := Transform3D.IDENTITY
var _drag_pipe: StageRoom.Pipe ## the tube it slides along, if hung on one
var _drag_along_offset := 0.0 ## clamps' place on the tube minus the grab point's
var _edit_before := Transform3D.IDENTITY ## where the fixture being dragged started, for undo

# Box select: drag on empty space to pick several things at once.
var _group: Array[Object] = [] ## fixtures and pieces picked together (two or more), else empty
var _boxing := false
var _box_from := Vector2.ZERO
var _box_add := false ## Shift held: add to what is already selected
var _group_drag := false ## pressed on a member of the group
var _group_drag_started := false
var _group_target: Object ## the member pressed on
var _group_plane := Plane() ## level plane through it: the group slides across the floor plan
var _group_grab := Vector3.ZERO
var _group_before: Array[Transform3D] = []
var _grab_copies: Array[DMXFixture] = [] ## Ctrl+D copies following the mouse until you click
var _grab_start: Array[Transform3D] = []
var _grab_plane := Plane(Vector3.UP, 0.0)
var _grab_origin := Vector3.ZERO

# Point at: aim the selected moving heads at a spot on the stage.
var _aiming := false
var _aim_drag := false
var _aim_before: Dictionary = {} ## DMXFixture -> Vector2(pan, tilt) when the press began, for undo
var _aim_unreachable := 0 ## selected heads that can't reach the spot (shown in the hint)

var _mode_buttons: Dictionary = {} ## TransformGizmo.Mode -> Button
var _view_buttons: Dictionary = {} ## preset name -> Button
var _shading_buttons: Array[Button] = [] ## indexed by StageLook.Shading

@onready var _viewport: SubViewport = %Viewport
@onready var _env: Environment = (%Environment as WorldEnvironment).environment
@onready var _work_lights: Node3D = %WorkLights ## key + fill, on in Work shading only
@onready var _room: Node3D = %Room
@onready var _set: Node3D = _room.get_node("Set") ## the structure pieces
@onready var _fixtures: Node3D = %Fixtures ## a StageFixture3D per placed fixture goes here
@onready var _pivot: Node3D = %Pivot
@onready var _camera: Camera3D = %Camera
@onready var _grid: MeshInstance3D = %Grid
@onready var _drafting: DraftingOverlay = %Drafting
@onready var _draft_bar: Control = %DraftBar
@onready var _draft_measure: Button = %DraftMeasure
@onready var _drop_marker: MeshInstance3D = %DropMarker
@onready var _gizmo: TransformGizmo = %Gizmo
@onready var _box_select: Panel = %BoxSelect
@onready var _tools: Control = %Tools
@onready var _snap_button: Button = %Snap
@onready var _aim_button: Button = %Aim
@onready var _mirror_button: Button = %Mirror
@onready var _mirror_options: Control = %MirrorOptions ## axis and centre, shown while mirroring
@onready var _mirror_plane: MeshInstance3D = %MirrorPlane
@onready var _axis_x: Button = %AxisX
@onready var _axis_z: Button = %AxisZ
@onready var _center_label: Label = %CenterLabel
@onready var _center_box: UnitSpinBox = %Center
@onready var _haze: HSlider = %Haze
@onready var _haze_label: ResetLabel = %HazeLabel
@onready var _empty_hint: Control = %EmptyHint
## The empty-stage welcome (with "Load demo rig") is a startup nicety: once the user
## clicks the stage or places anything it stays gone, even if the stage empties again.
var _empty_hint_done := false
@onready var _help: Label = %Help


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	_drafting.ctx = ctx
	ctx.fixtures_changed.connect(_sync_fixtures)
	ctx.selection_changed.connect(_on_selection_changed)
	ctx.pick_requested.connect(func(list: Array) -> void: _set_selection(list))
	ctx.delete_requested.connect(_delete_selected)
	ctx.duplicate_requested.connect(_duplicate_selected)
	ctx.fixture_moved.connect(_on_fixture_moved)
	ctx.workspace_changed.connect(_on_workspace_changed)
	ctx.piece_moved.connect(func(p: StructurePiece) -> void:
		_follow_piece(p)
		_rebuild_pipes())
	ctx.symmetry.changed.connect(_sync_mirror)
	ctx.look_editing_changed.connect(_show_look_edit_badge)
	_style_look_edit_badge()
	ctx.set_root = _set
	ctx.truss_pipes = _pipes
	ctx.stage_surfaces = _surfaces
	_sync_fixtures()


func _ready() -> void:
	look.load_saved()
	_surfaces = StageRoom.surfaces_in(_room)
	if ctx:
		ctx.stage_surfaces = _surfaces
	_rebuild_pipes()
	(_drop_marker.material_override as ShaderMaterial).set_shader_parameter("color", UIPalette.ACCENT)
	_gizmo.camera = _camera
	var box_style := (_box_select.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
	box_style.bg_color = Color(UIPalette.ACCENT, 0.12)
	box_style.border_color = Color(UIPalette.ACCENT, 0.9)
	_box_select.add_theme_stylebox_override("panel", box_style)

	# View presets, top left.
	_view_buttons = {"Perspective": %Perspective, "Front": %Front, "Side": %Side, "Top": %Top}
	for preset: String in _view_buttons:
		(_view_buttons[preset] as Button).pressed.connect(_set_view.bind(preset))
	_drafting.camera = _camera
	_drafting.ctx = ctx
	_drafting.visuals = _visuals
	_drafting.surfaces = _surfaces
	%DraftGrid.toggled.connect(func(on: bool) -> void: _drafting.show_grid = on)
	%DraftLabels.toggled.connect(func(on: bool) -> void: _drafting.show_labels = on)
	%DraftBeams.toggled.connect(func(on: bool) -> void: _drafting.show_beams = on)
	_draft_measure.toggled.connect(_set_measuring)
	%DraftExport.pressed.connect(_export_plot)

	# Gizmo mode and snapping, top right.
	_mode_buttons = {TransformGizmo.Mode.MOVE: %Move, TransformGizmo.Mode.ROTATE: %Rotate}
	for m: TransformGizmo.Mode in _mode_buttons:
		(_mode_buttons[m] as Button).pressed.connect(set_gizmo_mode.bind(m))
	_update_snap_tooltip()
	AppSettings.hub().changed.connect(func(key: StringName) -> void:
		if key == &"units":
			_update_snap_tooltip())
	set_gizmo_mode(TransformGizmo.Mode.MOVE)
	_aim_button.toggled.connect(_set_aiming)

	# Mirror mode, beside Snap: toggle, axis and where the plane crosses the floor.
	_mirror_button.toggled.connect(func(on: bool) -> void: ctx.symmetry.enabled = on)
	_axis_x.pressed.connect(func() -> void: ctx.symmetry.axis = StageSymmetry.Axis.X)
	_axis_z.pressed.connect(func() -> void: ctx.symmetry.axis = StageSymmetry.Axis.Z)
	_center_box.metres_changed.connect(func(m: float) -> void: ctx.symmetry.set_offset(m))
	%CenterReset.pressed.connect(func() -> void: ctx.symmetry.reset())
	%CenterToSelection.pressed.connect(_center_on_selection)
	_sync_mirror()

	# Work / Show shading, top left beside the view presets.
	_shading_buttons = [%Work, %Show]
	for sh in _shading_buttons.size():
		_shading_buttons[sh].pressed.connect(func() -> void: look.shading = sh as StageLook.Shading)

	# Haze, bottom right: how the stage is drawn, not the show. (Quality is a
	# computer-wide choice in Settings; the look follows it.)
	_haze.value = look.haze
	_haze.value_changed.connect(func(v: float) -> void: look.haze = v)
	look.quality = AppSettings.quality
	AppSettings.hub().changed.connect(func(key: StringName) -> void:
		if key == &"quality":
			look.quality = AppSettings.quality)
	# Clicking "Haze" puts it back once it has been changed.
	_haze_label.default_text = "%d%%" % roundi(StageLook.DEFAULT_HAZE * 100.0)
	_haze_label.reset_requested.connect(func() -> void: look.haze = StageLook.DEFAULT_HAZE)
	look.changed.connect(_sync_look_controls)
	_sync_look_controls()

	%LoadDemo.pressed.connect(func() -> void:
		_dismiss_empty_hint()
		ctx.load_demo_rig())

	look.changed.connect(_apply_look)
	_apply_look()
	%Text.text = SHORTCUTS_BBCODE
	%ShortcutsButton.pressed.connect(_toggle_shortcuts)
	_update_help()
	_update_camera()


func _update_snap_tooltip() -> void:
	_snap_button.tooltip_text = tr("Move in %s steps and rotate in %d° steps. Hold Ctrl while dragging to flip this.") % [Units.length_text(TransformGizmo.MOVE_STEP), int(TransformGizmo.ROTATE_STEP)]


## Shading, haze or quality changed: retune the environment and the viewport.
## (Each fixture listens to `look` itself for its shadows and beams.)
func _apply_look() -> void:
	look.apply(_env)
	_work_lights.visible = look.work_lights()
	_viewport.msaa_3d = look.msaa()
	_viewport.positional_shadow_atlas_size = look.shadow_atlas_size()
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa = false
	look.save()


func _sync_look_controls() -> void:
	_haze.set_value_no_signal(look.haze)
	_haze_label.modified = not is_equal_approx(look.haze, StageLook.DEFAULT_HAZE)
	for i in _shading_buttons.size():
		_shading_buttons[i].button_pressed = i == look.shading


func _set_view(preset: String) -> void:
	if ORTHO_VIEWS.has(preset):
		var v: Dictionary = ORTHO_VIEWS[preset]
		if not _is_ortho():
			_persp_saved = {"yaw": _yaw, "pitch": _pitch, "distance": _distance, "pivot": _pivot.position}
		_yaw = v["yaw"]
		_pitch = v["pitch"]
		_pivot.position = v["pivot"]
		_ortho_size = v["size"]
		_last_ortho = preset
	elif _is_ortho() and not _persp_saved.is_empty():
		_yaw = _persp_saved["yaw"]
		_pitch = _persp_saved["pitch"]
		_distance = _persp_saved["distance"]
		_pivot.position = _persp_saved["pivot"]
	else:
		_yaw = 0.0
		_pitch = -14.0
	_view_preset = preset
	_sync_view()


## Show a view by name ("Perspective", "Top", "Front", "Side"). Used by the screenshot helper.
func show_view(preset: String) -> void:
	_set_view(preset)


func _is_ortho() -> bool:
	return ORTHO_VIEWS.has(_view_preset)


## Orbiting or flying from a drawing view: carry on in perspective from where it stood.
func _leave_ortho() -> void:
	if not _is_ortho():
		return
	_view_preset = "Perspective"
	_sync_view()


## The view changed: buttons, drawing layer, grid, and the wall that would block the camera.
func _sync_view() -> void:
	for key: String in _view_buttons:
		(_view_buttons[key] as Button).set_pressed_no_signal(key == _view_preset)
	var ortho := _is_ortho()
	_drafting.kind = ORTHO_VIEWS[_view_preset]["kind"] if ortho else DraftingOverlay.Kind.NONE
	_draft_bar.visible = ortho
	if not ortho:
		_draft_measure.button_pressed = false
	# From house left the side view would stare at the wall: take it away.
	var near_wall := _room.get_node_or_null("LeftWall") as Node3D
	if near_wall:
		near_wall.visible = _view_preset != "Side"
	# Seen edge on, the floor slab only shows reflections of the beams: the grid's floor line is enough.
	var floor_slab := _room.get_node_or_null("Floor") as Node3D
	if floor_slab:
		floor_slab.visible = _view_preset != "Front" and _view_preset != "Side"
	_update_camera()
	_update_gizmo()


## Zoom by a factor (below 1 closer): the orbit distance, or the height a drawing view shows.
func _zoom(factor: float) -> void:
	if _is_ortho():
		_ortho_size = clampf(_ortho_size * factor, ORTHO_SIZE_MIN, ORTHO_SIZE_MAX)
	else:
		_distance = clampf(_distance * factor, 3.0, 40.0)
	_update_camera()


func _set_measuring(on: bool) -> void:
	_drafting.measuring = on
	mouse_default_cursor_shape = Control.CURSOR_CROSS if on else Control.CURSOR_ARROW


func _export_plot() -> void:
	var path: String = await _drafting.export_png()
	_say("Saved plot to " + path if not path.is_empty() else "Couldn't save the plot", 6000)


## Show a message in place of the hint for a while.
func _say(text: String, millis := 4000) -> void:
	_note = text
	_note_until = Time.get_ticks_msec() + millis


# ---------------------------------------------------------------- fixtures

func _sync_fixtures() -> void:
	if ctx == null:
		return
	var live := ctx.fixtures()
	for fx: DMXFixture in _visuals.keys():
		if not live.has(fx) or not is_instance_valid(fx):
			var gone: Node = _visuals[fx]
			_fixtures.remove_child(gone) # now, so an undone fixture's new visual gets the same name
			gone.queue_free()
			_visuals.erase(fx)
			_group.erase(fx)
	for fx in live:
		if not _visuals.has(fx):
			var v := StageFixture3D.create(fx)
			_fixtures.add_child(v)
			v.setup(fx, ctx, look)
			_visuals[fx] = v
			_update_rigging(fx)
	if not live.is_empty():
		_empty_hint_done = true # once anything is placed, the welcome never returns this session
	_empty_hint.visible = live.is_empty() and not _empty_hint_done
	_update_gizmo()


func _dismiss_empty_hint() -> void:
	_empty_hint_done = true
	_empty_hint.visible = false


func _on_workspace_changed(_ws: StudioContext.Workspace) -> void:
	_update_gizmo()
	_sync_mirror() # the plane is a stage-building aid, like the grid
	# Pieces are only edited while setting up the stage: let go of them.
	if _group.is_empty():
		_select_piece(null)
	else:
		_set_selection(_group.filter(func(o: Object) -> bool: return o is DMXFixture))


func _on_selection_changed(fx: DMXFixture) -> void:
	if fx:
		_group.clear() # picked on its own (here or in a panel)
		_select_piece(null)
	_refresh_marks()
	_update_gizmo()


func _on_fixture_moved(fx: DMXFixture) -> void:
	if _visuals.has(fx):
		(_visuals[fx] as StageFixture3D).sync_position()
		_update_rigging(fx)
	if fx == ctx.selected and not _gizmo.is_dragging():
		_update_gizmo()


func _update_gizmo() -> void:
	# Handles only while setting up the stage, so programming can't nudge the rig.
	var fx := ctx.selected if ctx else null
	var staging := ctx != null and ctx.workspace == StudioContext.Workspace.STAGE
	_grid.visible = staging and not _is_ortho() # a placement aid (drawing views have their own grid)
	# Programming only needs the Point at button; the rest builds the rig.
	for c in _tools.get_children():
		(c as Control).visible = staging or c == _aim_button
	_refresh_aim_button()
	_gizmo.shown = staging and fx != null and _visuals.has(fx)
	if _gizmo.shown:
		_gizmo.target = StudioContext.fixture_transform(fx)
		_gizmo.rings = _rotation_axes(fx)


## The ways a fixture can be turned where it is mounted now (rotate rings).
func _rotation_axes(fx: DMXFixture) -> Array[MountRotation.Axis]:
	var body: FixtureCatalog.Body = fx.get_meta(StudioContext.META_BODY, FixtureCatalog.Body.PAR)
	return MountRotation.axes(StudioContext.fixture_transform(fx),
		MountRotation.rules_of(StageFixture3D.scene_path_of(fx)),
		StageFixture3D.mount_offset(body), _pipes, _surfaces)


func set_gizmo_mode(m: TransformGizmo.Mode) -> void:
	_gizmo.mode = m
	for key: TransformGizmo.Mode in _mode_buttons:
		(_mode_buttons[key] as Button).button_pressed = key == m


func _snapping(ctrl_held: bool) -> bool:
	return _snap_button.button_pressed != ctrl_held


# ---------------------------------------------------------------- placing against surfaces

## Clamps show while a fixture hangs on a tube and hide once it is moved off.
func _update_rigging(fx: DMXFixture) -> void:
	var tilt := MountRotation.stand_tilt(StudioContext.fixture_transform(fx),
		MountRotation.rules_of(StageFixture3D.scene_path_of(fx)),
		StageFixture3D.mount_offset(fx.get_meta(StudioContext.META_BODY, FixtureCatalog.Body.PAR)), _surfaces)
	(_visuals[fx] as StageFixture3D).set_rigged(_pipe_holding(fx), 0.0 if is_nan(tilt) else tilt)


func _pipe_holding(fx: DMXFixture) -> StageRoom.Pipe:
	return StageRoom.pipe_holding(_pipes, StudioContext.fixture_transform(fx), _mounts(fx))


func _mounts(fx: DMXFixture) -> PackedVector3Array:
	return StageFixture3D.mounts_of(StageFixture3D.scene_path_of(fx))


func _entry_mounts(entry: FixtureCatalog.Entry) -> PackedVector3Array:
	return StageFixture3D.mounts_of(StageFixture3D.scene_path(entry.body, entry.profile.fixture_name))


## Where a fixture would go if dropped (or re-stuck) at a screen point: clamped
## onto the truss tube under it by its MountPoints (`mounts`), or flush on the
## surface under it, beam pointing into the room. With `no_snap` (Alt held) it
## hangs at the default height above the floor point instead. Null on a miss.
func _placement(at: Vector2, body: FixtureCatalog.Body, mounts: PackedVector3Array, no_snap: bool) -> Variant:
	var origin := _camera.project_ray_origin(at)
	var dir := _camera.project_ray_normal(at)
	if no_snap:
		var p: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
		if p == null:
			return null
		var fp: Vector3 = p
		return Transform3D(Basis.IDENTITY, Vector3(clampf(fp.x, -7.5, 7.5), StageFixture3D.MOUNT_HEIGHT, clampf(fp.z, -5.5, 5.5)))
	if not mounts.is_empty():
		var grab := _pipe_at(at)
		if not grab.is_empty():
			return StageRoom.hang(grab[0], grab[1], mounts, grab[2])
	var hit := StageRoom.raycast(_surfaces, origin, dir)
	if hit == null:
		return null
	var pos := hit.position
	if hit.kind == StageRoom.Kind.FLOOR:
		pos = Vector3(clampf(pos.x, -7.5, 7.5), pos.y, clampf(pos.z, -5.5, 5.5)) # stay in the room
	return Transform3D(StageRoom.mount_basis(hit.normal), pos + hit.normal * StageFixture3D.mount_offset(body))


## The tube nearest the cursor on screen, where along it, and which face of it
## to hang on: [Pipe, along, face], or [] if none is within PIPE_GRAB_PX. Of
## tubes about as near, the one closer to the camera wins.
func _pipe_at(at: Vector2) -> Array:
	var origin := _camera.project_ray_origin(at)
	var dir := _camera.project_ray_normal(at)
	var best: Array = []
	var best_score := INF
	for pipe in _pipes:
		var r := pipe.closest_to_ray(origin, dir)
		var p := pipe.point(float(r[0]))
		if _camera.is_position_behind(p):
			continue
		var px := _camera.unproject_position(p).distance_to(at)
		if px > PIPE_GRAB_PX:
			continue
		var score := px + float(r[2]) * 2.0 # pixels, plus a nudge towards the front
		if score < best_score:
			best_score = score
			best = [pipe, float(r[0]), pipe.face_for(_aim_round(pipe, p, origin, dir, float(r[2])))]
	return best


## Which way round a tube the cursor points, for choosing its face: from the
## tube's centre line towards where the cursor's ray passes it. Left of the tube
## on screen means its left, above means its top. Right over the tube the ray
## gives no side, so it leans to the face looking at the camera.
func _aim_round(pipe: StageRoom.Pipe, p: Vector3, origin: Vector3, dir: Vector3, t: float) -> Vector3:
	var u := pipe.axis()
	var beside := origin + dir * t - p
	beside -= u * beside.dot(u)
	var to_cam := origin - p
	to_cam -= u * to_cam.dot(u)
	# How far off the tube the cursor is, measured against the tube's thickness.
	var off := clampf(beside.length() / (MountPoint.TUBE_RADIUS * 1.5), 0.0, 1.0)
	return beside.normalized() * off + to_cam.normalized() * 0.35


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if data is Dictionary and (data as Dictionary).get("kind") == "structure":
		_preview_piece(at, String((data as Dictionary)["path"]))
		return true
	var ok: bool = data is Dictionary and (data as Dictionary).get("kind") == "fixture"
	if ok:
		var entry: FixtureCatalog.Entry = (data as Dictionary)["entry"]
		var xf: Variant = _placement(at, entry.body, _entry_mounts(entry), Input.is_key_pressed(KEY_ALT))
		_drop_marker.visible = xf != null
		if xf != null:
			var t: Transform3D = xf
			# Lay the ring flat on the surface: the quad faces along the surface normal.
			var b := Basis(t.basis.x, t.basis.z, -t.basis.y)
			_drop_marker.global_transform = Transform3D(b, t.origin + t.basis.y * StageFixture3D.mount_offset(entry.body) * 0.97)
	return ok


func _drop_data(at: Vector2, data: Variant) -> void:
	_drop_marker.visible = false
	if (data as Dictionary).get("kind") == "structure":
		_drop_piece(at, String((data as Dictionary)["path"]))
		return
	var entry: FixtureCatalog.Entry = (data as Dictionary)["entry"]
	var xf: Variant = _placement(at, entry.body, _entry_mounts(entry), Input.is_key_pressed(KEY_ALT))
	if xf == null:
		xf = Transform3D(Basis.IDENTITY, Vector3(0, StageFixture3D.MOUNT_HEIGHT, 0))
	var t: Transform3D = xf
	ctx.add_fixture(entry, t.origin, t.basis)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_drafting.cursor = Vector2(-1, -1)
		_drop_marker.visible = false
		_clear_ghost()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		_set_flying(false) # alt-tabbed away mid-flight: don't keep flying


## The fixture or structure piece under the cursor, or null. Judged by the
## meshes you see (see StagePick): click anywhere on a fixture's body or a
## truss, not just its middle. Pieces only count while setting up the stage.
func _pick_at(at: Vector2) -> Object:
	var best: StagePick.Hit = null
	for fx: DMXFixture in _visuals:
		if _is_hidden(fx):
			continue
		var hit := StagePick.ray_node(_camera, at, _visuals[fx], fx)
		if hit and hit.beats(best):
			best = hit
	if best and _is_ortho():
		return best.target # in a plan the truss covers the lights hung under it: lights win
	if ctx.workspace == StudioContext.Workspace.STAGE:
		for p in _pieces():
			if _is_hidden(p):
				continue
			var hit := StagePick.ray_node(_camera, at, p, p, p.bounds)
			if hit and hit.beats(best):
				best = hit
	if best:
		return best.target
	# Nothing under the cursor: a fixture whose middle is very close on screen
	# still counts, for tiny far-away ones.
	var near_fx: DMXFixture = null
	var best_d := PICK_RADIUS_PX
	for fx: DMXFixture in _visuals:
		if _is_hidden(fx):
			continue
		var c := (_visuals[fx] as StageFixture3D).center()
		if _camera.is_position_behind(c):
			continue
		var d := _camera.unproject_position(c).distance_to(at)
		if d < best_d:
			best_d = d
			near_fx = fx
	return near_fx


# ---------------------------------------------------------------- moving a fixture by its body

func _begin_body_drag(fx: DMXFixture, at: Vector2, restick: bool) -> void:
	_dragging = fx
	_drag_started = false
	_drag_restick = restick
	_press_pos = at
	_drag_start = StudioContext.fixture_transform(fx)
	_edit_before = _drag_start
	var v: StageFixture3D = _visuals[fx]
	_drag_screen_offset = _camera.unproject_position(v.center()) - at
	# Slide along the surface it is mounted on: the plane through its origin,
	# facing the way the beam points. The grab point stays under the cursor.
	_drag_plane = Plane(-_drag_start.basis.y.normalized(), _drag_start.origin)
	var grab: Variant = _ray_plane(_drag_plane, at)
	_drag_offset = _drag_start.origin - (grab as Vector3) if grab != null else Vector3.ZERO
	# Hung on a tube: slide along the tube instead, clamps staying on it.
	_drag_pipe = _pipe_holding(fx)
	if _drag_pipe:
		var r := _drag_pipe.closest_to_ray(_camera.project_ray_origin(at), _camera.project_ray_normal(at))
		_drag_along_offset = StageRoom.clamps_along(_drag_pipe, _drag_start, _mounts(fx)) - float(r[0])


func _update_body_drag(at: Vector2, ctrl_held: bool) -> void:
	if not _drag_started:
		if at.distance_to(_press_pos) < _drag_threshold:
			return # a click, not a drag: don't nudge the fixture
		_drag_started = true
	var body: FixtureCatalog.Body = _dragging.get_meta(StudioContext.META_BODY, FixtureCatalog.Body.PAR)
	if _drag_restick:
		var xf: Variant = _placement(at + _drag_screen_offset, body, _mounts(_dragging), false)
		if xf != null:
			ctx.move_fixture(_dragging, xf)
		return
	if _drag_pipe:
		var r := _drag_pipe.closest_to_ray(_camera.project_ray_origin(at), _camera.project_ray_normal(at))
		var along := float(r[0]) + _drag_along_offset
		if _snapping(ctrl_held):
			# Snap where the clamps sit in the room, not the distance from the tube's end.
			var start := _drag_pipe.along_of(Vector3.ZERO)
			along = snappedf(along - start, TransformGizmo.MOVE_STEP) + start
		ctx.move_fixture(_dragging, StageRoom.slide(_drag_pipe, _drag_start, _mounts(_dragging), along))
		return
	var hit: Variant = _ray_plane(_drag_plane, at)
	if hit == null:
		return
	var pos: Vector3 = (hit as Vector3) + _drag_offset
	if _snapping(ctrl_held):
		var n := _drag_plane.normal
		for i in 3:
			if absf(n[i]) < 0.9: # snap the directions you can slide in
				pos[i] = snappedf(pos[i], TransformGizmo.MOVE_STEP)
	ctx.move_fixture(_dragging, Transform3D(_drag_start.basis, pos))


## Ray through a screen point meets a plane, ignoring near edge-on views (which
## would fling the fixture miles away for a pixel of mouse movement).
func _ray_plane(plane: Plane, at: Vector2) -> Variant:
	var dir := _camera.project_ray_normal(at)
	if absf(dir.dot(plane.normal)) < 0.06:
		return null
	return plane.intersects_ray(_camera.project_ray_origin(at), dir)


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if _touch_input(event):
		accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if _grabbing() and mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT):
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_confirm_grab()
			else:
				_cancel_grab()
			accept_event()
			return
		if mb.pressed:
			_dismiss_empty_hint() # any click on the stage except the demo button (which eats its own)
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed and mb.alt_pressed:
					_leave_ortho()
					_orbiting = true
				elif mb.pressed:
					_on_left_press(mb)
				else:
					_orbiting = false
					if _aim_drag:
						_end_aim()
					if _boxing:
						_end_box(mb.position)
					if _group_drag:
						_end_group_drag()
					if _dragging:
						if _drag_started:
							ctx.record_move(_dragging, _edit_before, "Move fixture")
						_dragging = null
					if _piece_drag:
						if _piece_drag_started:
							_record_piece_move(_piece_drag, _piece_before, "Move truss piece")
						_piece_drag = null
						_show_free_arrows(null)
						_rebuild_pipes()
					if _gizmo.is_dragging():
						_gizmo.end_drag()
						if ctx.selected:
							ctx.record_move(ctx.selected, _edit_before,
								"Turn fixture" if _gizmo.mode == TransformGizmo.Mode.ROTATE else "Move fixture")
						_update_gizmo()
			MOUSE_BUTTON_RIGHT:
				if _is_ortho() or _panning_right:
					_panning_right = mb.pressed and _is_ortho() # a drawing view has nothing to fly through: drag pans
					_panning = _panning_right or _panning_middle
				else:
					_set_flying(mb.pressed)
			MOUSE_BUTTON_MIDDLE:
				_panning_middle = mb.pressed
				_panning = _panning_middle or _panning_right
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed and _flying:
					_set_fly_speed(_fly_speed * 1.2)
				elif mb.pressed:
					_wheel_zoom(0.9, mb.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and _flying:
					_set_fly_speed(_fly_speed / 1.2)
				elif mb.pressed:
					_wheel_zoom(1.1, mb.position)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_drafting.cursor = mm.position
		if _grabbing() and not _flying:
			_update_grab(mm.position, mm.ctrl_pressed)
		elif _flying:
			_look(mm.relative)
		elif _orbiting:
			_yaw -= mm.relative.x * 0.3
			# Orbiting never dips the camera under the floor, but it won't snap
			# down a view that flying left looking up, either.
			_pitch = clampf(_pitch - mm.relative.y * 0.3, -89.0, maxf(5.0, _pitch))
			_update_camera()
		elif _panning and _is_ortho():
			# Slide the drawing under the cursor: one pixel is the same distance everywhere.
			var per_px := _ortho_size / maxf(size.y, 1.0)
			_pivot.position += (-_camera.global_basis.x * mm.relative.x + _camera.global_basis.y * mm.relative.y) * per_px
			_update_camera()
		elif _panning:
			var right := _camera.global_transform.basis.x
			var fwd := Vector3(_camera.global_transform.basis.z.x, 0, _camera.global_transform.basis.z.z).normalized()
			_pivot.position += (-right * mm.relative.x + -fwd * mm.relative.y) * _distance * 0.0016
			_update_camera()
		elif _aim_drag:
			_update_aim(mm.position)
		elif _boxing:
			_update_box(mm.position)
		elif _group_drag:
			_update_group_drag(mm.position, mm.ctrl_pressed)
		elif _gizmo.is_dragging() and ctx.selected:
			ctx.move_fixture(ctx.selected, _gizmo.drag(mm.position, _snapping(mm.ctrl_pressed)))
		elif _dragging:
			_update_body_drag(mm.position, mm.ctrl_pressed)
		elif _piece_drag:
			_update_piece_drag(mm.position)
		else:
			_gizmo.hovered = _gizmo.handle_at(mm.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if _flying and FLY_KEYS.has(k.physical_keycode):
			accept_event() # flying (see _process), not the W / E gizmo shortcuts
			return
		if not k.pressed or k.echo:
			return
		if _grabbing() and (k.keycode == KEY_ESCAPE or k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
			if k.keycode == KEY_ESCAPE:
				_cancel_grab()
			else:
				_confirm_grab()
			accept_event()
			return
		if k.ctrl_pressed or k.meta_pressed:
			return # Ctrl+Z, Ctrl+R... are the main window's, not W / E / R / Z here
		if k.unicode == 63 or k.keycode == KEY_QUESTION or k.keycode == KEY_F1:
			_toggle_shortcuts()
			accept_event()
			return
		match k.keycode:
			KEY_KP_1:
				_set_view("Front")
			KEY_KP_3:
				_set_view("Side")
			KEY_KP_7:
				_set_view("Top")
			KEY_KP_5:
				_set_view("Perspective" if _is_ortho() else _last_ortho)
			KEY_D:
				if not _is_ortho():
					return
				_draft_measure.button_pressed = not _draft_measure.button_pressed
			KEY_F:
				if _flying:
					return
				if _frame_selection():
					accept_event()
					return
				if _is_ortho():
					_set_view(_view_preset) # back to the whole stage
					accept_event()
					return
				_pivot.position = Vector3(0, 1.4, -0.5)
				_distance = 12.5
				_update_camera()
			KEY_W:
				set_gizmo_mode(TransformGizmo.Mode.MOVE)
			KEY_E:
				set_gizmo_mode(TransformGizmo.Mode.ROTATE)
			KEY_M:
				ctx.symmetry.enabled = not ctx.symmetry.enabled
			KEY_Z:
				look.shading = StageLook.Shading.SHOW if look.work_lights() else StageLook.Shading.WORK
			KEY_T:
				if _aim_button.disabled and not _aiming:
					return
				_aim_button.button_pressed = not _aiming
			KEY_ESCAPE:
				if _drafting.measuring:
					if _drafting.has_measurement():
						_drafting.clear_measurement() # first Esc clears the line, the next leaves measuring
					else:
						_draft_measure.button_pressed = false
					accept_event()
					return
				if _aiming:
					_aim_button.button_pressed = false # leave Point at first; Esc again deselects
					accept_event()
					return
				if _group.is_empty() and not _selected_piece and not ctx.selected:
					return
				_set_selection([])
			KEY_DELETE:
				if not _group.is_empty():
					_delete_group()
				elif _selected_piece:
					_delete_piece(_selected_piece)
				elif ctx.selected:
					ctx.remove_fixture(ctx.selected)
				else:
					return
			KEY_R:
				if not _selected_piece:
					return
				var before := _selected_piece.global_transform
				_selected_piece.global_transform = StructureSnap.turned(_selected_piece, _pieces())
				_follow_piece(_selected_piece)
				_rebuild_pipes()
				_record_piece_move(_selected_piece, before, "Turn truss piece")
			_:
				return
		accept_event()


func _on_left_press(mb: InputEventMouseButton) -> void:
	var finger := _from_touch(mb)
	_gizmo.pick_px = TOUCH_PICK_PX if finger else TransformGizmo.PICK_PX
	_drag_threshold = TOUCH_DRAG_THRESHOLD_PX if finger else DRAG_THRESHOLD_PX
	if _drafting.measuring:
		_drafting.measure_click(mb.position, _snap_button.button_pressed != mb.ctrl_pressed)
		return
	if _aiming:
		_begin_aim(mb.position)
		return
	var handle := _gizmo.handle_at(mb.position)
	if handle != TransformGizmo.Handle.NONE and ctx.selected:
		_edit_before = StudioContext.fixture_transform(ctx.selected)
		_gizmo.target = _edit_before
		_gizmo.begin_drag(handle, mb.position)
		return
	var picked := _pick_at(mb.position)
	if picked == null:
		_begin_box(mb.position, mb.shift_pressed)
		return
	if mb.ctrl_pressed or mb.meta_pressed:
		_toggle_in_selection(picked) # Ctrl+click adds or removes just this one
		return
	if _group.has(picked) and ctx.workspace == StudioContext.Workspace.STAGE:
		_begin_group_drag(picked, mb.position)
		return
	var fx: DMXFixture = picked if picked is DMXFixture else null
	ctx.select(fx)
	if fx == null:
		var piece: StructurePiece = picked if picked is StructurePiece else null
		_select_piece(piece)
		if piece:
			_piece_drag = piece
			_piece_drag_started = false
			_piece_before = piece.global_transform
			_press_pos = mb.position
		return
	if mb.double_click:
		ctx.request_rename(fx)
		return
	_begin_body_drag(fx, mb.position, mb.shift_pressed)


# ---------------------------------------------------------------- touch

## A finger's mouse click is told apart by its device id, which Godot sets to
## DEVICE_ID_EMULATION for events it makes from touches.
func _from_touch(event: InputEvent) -> bool:
	return event.device == InputEvent.DEVICE_ID_EMULATION


## Camera gestures. Returns true when the event was a touch gesture's (or the
## mouse echo of a finger that is part of one) and must not reach the mouse code.
func _touch_input(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches.press(st.index, st.position)
			if _touches.count() >= 2:
				if not _touch_locked:
					_cancel_pointer_edit() # the first finger was the start of a gesture, not an edit
				_touch_locked = true
		else:
			_touches.release(st.index)
			if _touches.count() == 0:
				_touch_locked = false
		return false # the first finger's own click still takes its normal path
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		var g := _touches.drag(sd.index, sd.position)
		if g.is_empty():
			return false
		_apply_gesture(g["pan"], g["pinch"], _touches.count())
		return true
	if _touch_locked and event is InputEventMouse and _from_touch(event):
		return true
	return false


func _apply_gesture(pan: Vector2, pinch: float, fingers: int) -> void:
	if pinch != 1.0:
		_zoom(1.0 / pinch)
	if _is_ortho():
		# Two or more fingers: slide the drawing (pinch, above, zooms). No orbiting here.
		var per_px := _ortho_size / maxf(size.y, 1.0)
		_pivot.position += (-_camera.global_basis.x * pan.x + _camera.global_basis.y * pan.y) * per_px
	elif fingers >= 3:
		var right := _camera.global_transform.basis.x
		var fwd := Vector3(_camera.global_transform.basis.z.x, 0, _camera.global_transform.basis.z.z).normalized()
		_pivot.position += (-right * pan.x + -fwd * pan.y) * _distance * TOUCH_PAN_PER_PX
	else:
		_yaw -= pan.x * TOUCH_ORBIT_DEG_PER_PX
		_pitch = clampf(_pitch - pan.y * TOUCH_ORBIT_DEG_PER_PX, -89.0, maxf(5.0, _pitch))
	_update_camera()


## Put back whatever a single finger had started (a drag, a box, a gizmo turn)
## when a second one lands: the user meant to move the camera.
func _cancel_pointer_edit() -> void:
	if _boxing:
		_boxing = false
		_box_select.visible = false
	if _group_drag:
		_group_drag = false
		if _group_drag_started:
			_place_group(_group, _group_before)
	if _dragging:
		if _drag_started:
			ctx.move_fixture(_dragging, _edit_before)
		_dragging = null
	if _piece_drag:
		if _piece_drag_started:
			_piece_drag.global_transform = _piece_before
			_follow_piece(_piece_drag)
		_piece_drag = null
		_show_free_arrows(null)
		_rebuild_pipes()
	if _gizmo.is_dragging():
		_gizmo.end_drag()
		if ctx.selected:
			ctx.move_fixture(ctx.selected, _edit_before)
		_update_gizmo()


# ---------------------------------------------------------------- fly camera (hold right mouse)

func _set_flying(on: bool) -> void:
	if on == _flying:
		return
	_flying = on
	if on:
		grab_focus() # take the keys from any text field, so WASD doesn't type
	_update_help()


func _set_fly_speed(speed: float) -> void:
	_fly_speed = clampf(speed, FLY_SPEED_MIN, FLY_SPEED_MAX)
	_update_help()


## The bottom hint shows only what applies right now; the rest is behind "?".
func _update_help() -> void:
	var text: String
	if Time.get_ticks_msec() < _note_until:
		text = _note
	elif _drafting.measuring:
		text = "Click two points to measure (fixtures snap, Snap rounds to the grid) · Esc clears · D when done"
	elif _aiming:
		text = "Click or drag where the lights should point · Esc or T when done"
		if _aim_unreachable > 0:
			text += " · %d can't reach it" % _aim_unreachable
	elif _grabbing():
		text = "Move the mouse to place the copies · Click or Enter drops them · Esc or right click cancels"
	elif _flying:
		text = "Flying %.1f m/s · WASD move · Q/E down/up · Shift faster · Alt slower · Wheel speed" % _fly_speed
	elif not _group.is_empty():
		text = "W move · E rotate · Ctrl+D duplicate · Delete remove · Esc deselect" + HINT_MORE
	elif _selected_piece:
		text = "Drag to move · R turn · Delete remove · Esc deselect" + HINT_MORE
	elif ctx and ctx.selected:
		text = "W move · E rotate · Ctrl+D duplicate · F2 rename · Delete remove" + HINT_MORE
	elif _is_ortho():
		text = "Drag to box select · Right drag pan · Wheel zoom · D measure · Numpad 5 perspective"
	else:
		text = "Drag to box select · Right drag to fly" + HINT_MORE
	if text != _help.text:
		_help.text = text


func _toggle_shortcuts() -> void:
	var popup: PopupPanel = %ShortcutsPopup
	if popup.visible:
		popup.hide()
	else:
		popup.popup_centered()


## Turn the camera where it stands. The orbit pivot is carried along, kept the
## same distance in front, so orbit, pan and zoom carry on from the new view.
func _look(relative: Vector2) -> void:
	var eye := _camera.global_position
	_yaw -= relative.x * LOOK_DEG_PER_PX
	_pitch = clampf(_pitch - relative.y * LOOK_DEG_PER_PX, -89.0, 89.0)
	var b := Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0))
	_pivot.position = eye - b * Vector3(0, 0, _distance)
	_update_camera()


func _process(delta: float) -> void:
	_update_help()
	if not _flying:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_set_flying(false) # the release went somewhere else
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META):
		return # a shortcut like Ctrl+S, not a move
	var b := _camera.global_basis
	var move := Vector3.ZERO
	# Physical keys: the same spots on AZERTY and other layouts, as in Godot.
	if Input.is_physical_key_pressed(KEY_W):
		move -= b.z
	if Input.is_physical_key_pressed(KEY_S):
		move += b.z
	if Input.is_physical_key_pressed(KEY_A):
		move -= b.x
	if Input.is_physical_key_pressed(KEY_D):
		move += b.x
	if Input.is_physical_key_pressed(KEY_E):
		move += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		move -= Vector3.UP
	if move == Vector3.ZERO:
		return
	var speed := _fly_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= FLY_FAST
	elif Input.is_key_pressed(KEY_ALT):
		speed *= FLY_SLOW
	_pivot.position += move.normalized() * speed * delta
	_update_camera()


## Wheel zoom. A drawing view zooms towards the cursor, so what is under it stays put.
func _wheel_zoom(factor: float, at: Vector2) -> void:
	if not _is_ortho():
		_zoom(factor)
		return
	var before := _drafting.point_at(at)
	_zoom(factor)
	_pivot.position += before - _drafting.point_at(at)
	_update_camera()


## Point the orbit camera (degrees, metres). Used by the screenshot helper.
func set_orbit(yaw: float, pitch: float, distance: float) -> void:
	_yaw = yaw
	_pitch = pitch
	_distance = distance
	_update_camera()


func _update_camera() -> void:
	_pivot.rotation_degrees = Vector3(_pitch, _yaw, 0)
	var ortho := _is_ortho()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL if ortho else Camera3D.PROJECTION_PERSPECTIVE
	_camera.size = _ortho_size
	_camera.far = 250.0 if ortho else 4000.0
	_camera.position = Vector3(0, 0, ORTHO_DISTANCE if ortho else _distance)
	_camera.rotation = Vector3.ZERO
	_gizmo.queue_redraw()


# ---------------------------------------------------------------- mirror mode

## Mirror mode, its axis or its centre changed: update the buttons and the plane.
func _sync_mirror() -> void:
	if ctx == null:
		return
	var sym := ctx.symmetry
	_mirror_button.set_pressed_no_signal(sym.enabled)
	_axis_x.set_pressed_no_signal(sym.axis == StageSymmetry.Axis.X)
	_axis_z.set_pressed_no_signal(sym.axis == StageSymmetry.Axis.Z)
	_center_label.text = "At %s  " % ("X" if sym.axis == StageSymmetry.Axis.X else "Z")
	if not is_equal_approx(_center_box.get_metres(), sym.offset()):
		_center_box.set_metres_no_signal(sym.offset())
	var staging := ctx.workspace == StudioContext.Workspace.STAGE
	_mirror_options.visible = sym.enabled and staging
	_mirror_plane.visible = sym.enabled and staging
	if sym.axis == StageSymmetry.Axis.X:
		_mirror_plane.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(sym.center.x, 3.0, sym.center.z))
	else:
		_mirror_plane.transform = Transform3D(Basis.IDENTITY, Vector3(sym.center.x, 3.0, sym.center.z))


## Put the mirror plane through the middle of what is selected.
func _center_on_selection() -> void:
	var items := _selection()
	if items.is_empty():
		return
	var sum := Vector3.ZERO
	for o in items:
		sum += _transform_of(o).origin
	var c := sum / items.size()
	ctx.symmetry.set_offset(c.x if ctx.symmetry.axis == StageSymmetry.Axis.X else c.z)


## The twin of a truss piece while mirroring, else null.
func _twin_piece(piece: Object) -> StructurePiece:
	if not ctx.symmetry.active():
		return null
	return StageSymmetry.partner_of(piece) as StructurePiece


## Keep a piece's twin where the mirror says it should be.
func _follow_piece(piece: StructurePiece) -> void:
	var twin := _twin_piece(piece)
	if twin and is_instance_valid(piece) and piece.is_inside_tree():
		twin.global_transform = ctx.symmetry.twin_transform(piece, piece.global_transform)


## `items` plus the twin of each, when mirroring (no duplicates).
func _with_twins(items: Array) -> Array:
	var all := items.duplicate()
	if ctx.symmetry.active():
		for o: Object in items:
			var twin := StageSymmetry.partner_of(o)
			if twin and not all.has(twin):
				all.append(twin)
	return all


# ---------------------------------------------------------------- duplicate (Ctrl+D)

func _grabbing() -> bool:
	return not _grab_copies.is_empty()


## Ctrl+D: copy the selected fixtures (a box selection too). The copies are
## patched to the next free addresses and follow the mouse over the floor, like
## Blender's grab, until you click (keep), or press Esc / right click (cancel).
func _duplicate_selected() -> void:
	if _grabbing():
		return
	var fxs: Array = _selection().filter(func(o: Object) -> bool: return o is DMXFixture)
	if fxs.is_empty():
		return
	var copies := ctx.duplicate_fixtures(fxs)
	if copies.is_empty():
		return
	_grab_copies = copies
	ctx.grabbing = true
	_set_selection(copies)
	_grab_start.clear()
	for fx in copies:
		_grab_start.append(StudioContext.fixture_transform(fx))
	if not is_visible_in_tree():
		# No stage in view to place them on (Live): drop them a metre over.
		var moved: Array[Transform3D] = []
		for xf in _grab_start:
			moved.append(xf.translated(Vector3(1.0, 0.0, 0.0)))
		_place_group(_grab_copies, moved)
		_confirm_grab()
		return
	var centre := (_visuals[copies[0]] as StageFixture3D).center()
	_grab_plane = Plane(Vector3.UP, centre.y)
	var hit: Variant = _ray_plane(_grab_plane, get_local_mouse_position())
	_grab_origin = hit if hit != null else centre
	_update_help()


func _update_grab(at: Vector2, ctrl_held: bool) -> void:
	var hit: Variant = _ray_plane(_grab_plane, at)
	if hit == null:
		return
	var delta: Vector3 = (hit as Vector3) - _grab_origin
	delta.y = 0.0
	if _snapping(ctrl_held):
		delta.x = snappedf(delta.x, TransformGizmo.MOVE_STEP)
		delta.z = snappedf(delta.z, TransformGizmo.MOVE_STEP)
	var xfs: Array[Transform3D] = []
	for xf in _grab_start:
		xfs.append(xf.translated(delta))
	_place_group(_grab_copies, xfs)


## Keep the copies where they are, as one undo step.
func _confirm_grab() -> void:
	var fxs: Array = _grab_copies.duplicate()
	_grab_copies.clear()
	ctx.grabbing = false
	_grab_start.clear()
	var indices: Array[int] = []
	for fx: DMXFixture in fxs:
		indices.append(fx.get_index())
	ctx.record_added_all("Duplicate %d fixture%s" % [fxs.size(), "" if fxs.size() == 1 else "s"], fxs,
		_attach_group.bind(fxs, indices, [], []), _detach_group.bind(fxs, []))
	_update_help()


## Throw the copies away; nothing was recorded, so there is nothing to undo.
func _cancel_grab() -> void:
	var fxs: Array = _grab_copies.duplicate()
	_grab_copies.clear()
	ctx.grabbing = false
	_grab_start.clear()
	_set_selection([])
	ctx.detach_fixtures(fxs)
	for fx: DMXFixture in fxs:
		fx.free()
	_update_help()


# ---------------------------------------------------------------- structure pieces (the truss set)

func _pieces(ignore: StructurePiece = null) -> Array[StructurePiece]:
	var list: Array[StructurePiece] = []
	for c in _set.get_children():
		if c is StructurePiece and c != ignore and c != _ghost:
			list.append(c)
	return list


## The set changed: collect its tubes again (joined into runs) and show or hide
## each fixture's clamps to match.
func _rebuild_pipes() -> void:
	_pipes = StageRoom.pipes_in(_set)
	if ctx:
		ctx.truss_pipes = _pipes
	for fx: DMXFixture in _visuals:
		_update_rigging(fx)
	if ctx:
		_update_gizmo() # a fixture's tube may have come or gone: its rings change


## Where `piece` would go for the cursor at `at`: a base plate on the floor
## under it, anything else joined onto the free connector nearest the cursor.
## Null if there is nowhere to put it.
func _piece_placement(at: Vector2, piece: StructurePiece) -> Variant:
	if piece.kind == StructurePiece.Kind.BASE_PLATE:
		var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(_camera.project_ray_origin(at), _camera.project_ray_normal(at))
		if hit == null:
			return null
		var p: Vector3 = hit
		if _snapping(Input.is_key_pressed(KEY_CTRL)):
			p = Vector3(snappedf(p.x, TransformGizmo.MOVE_STEP), 0.0, snappedf(p.z, TransformGizmo.MOVE_STEP))
		p = Vector3(clampf(p.x, -7.5, 7.5), 0.0, clampf(p.z, -5.5, 5.5))
		return Transform3D(piece.global_basis.orthonormalized(), p)
	var best: TrussConnector = null
	var best_px := CONNECTOR_GRAB_PX
	for c in StructureSnap.free_connectors(_pieces(piece), piece):
		if not c.accepts_kind(piece.kind) or _camera.is_position_behind(c.global_position):
			continue
		var px := _camera.unproject_position(c.global_position).distance_to(at)
		if px < best_px:
			best_px = px
			best = c
	if best == null:
		return null
	return StructureSnap.attach(piece, best)


func _preview_piece(at: Vector2, path: String) -> void:
	if _ghost == null or _ghost_path != path:
		_clear_ghost()
		_ghost = (load(path) as PackedScene).instantiate() as StructurePiece
		_ghost_path = path
		_set.add_child(_ghost)
		_ghost.set_highlight(true)
	_show_free_arrows(_ghost)
	var xf: Variant = _piece_placement(at, _ghost)
	_ghost.visible = xf != null
	if xf != null:
		_ghost.global_transform = xf


## Arrows on the connectors a piece could join, while you place one; none
## when `piece` is null.
func _show_free_arrows(piece: StructurePiece) -> void:
	var free: Array[TrussConnector] = []
	if piece:
		for c in StructureSnap.free_connectors(_pieces(piece), piece):
			if c.accepts_kind(piece.kind):
				free.append(c)
	for p in _pieces():
		for c in p.connectors():
			c.set_arrow_visible(free.has(c))


func _clear_ghost() -> void:
	_show_free_arrows(null)
	if _ghost:
		_set.remove_child(_ghost) # now: a dying ghost must not count as part of the set
		_ghost.queue_free()
		_ghost = null
		_ghost_path = ""


func _drop_piece(at: Vector2, path: String) -> void:
	_preview_piece(at, path)
	var placed := _ghost.visible
	var xf := _ghost.global_transform
	_clear_ghost()
	if not placed:
		return # nothing to join onto there
	var piece := (load(path) as PackedScene).instantiate() as StructurePiece
	_set.add_child(piece)
	piece.global_transform = xf
	# Mirror mode: a twin goes down across the plane (unless this one is on it).
	var pieces: Array = [piece]
	var xfs: Array = [xf]
	if ctx.symmetry.active() and not ctx.symmetry.on_plane(xf):
		var twin := (load(path) as PackedScene).instantiate() as StructurePiece
		_set.add_child(twin)
		var flip := ctx.symmetry.default_flip(xf)
		twin.global_transform = ctx.symmetry.mirror_transform(xf, flip)
		StageSymmetry.link(piece, twin, flip)
		pieces.append(twin)
		xfs.append(twin.global_transform)
	_rebuild_pipes()
	# Not selected: once it is down it looks like the rest of the set. Click it to edit it.
	if pieces.size() == 1:
		ctx.record_added("Add truss piece", piece, _attach_piece.bind(piece, xf, false), _detach_piece.bind(piece))
	else:
		ctx.record_added_all("Add mirrored truss pieces", pieces, _attach_pieces.bind(pieces, xfs), _detach_pieces.bind(pieces))


func _attach_pieces(pieces: Array, xfs: Array) -> void:
	for i in pieces.size():
		_attach_piece(pieces[i], xfs[i], false)


func _detach_pieces(pieces: Array) -> void:
	for p: Object in pieces:
		_detach_piece(p)


func _update_piece_drag(at: Vector2) -> void:
	if not _piece_drag_started:
		if at.distance_to(_press_pos) < _drag_threshold:
			return
		_piece_drag_started = true
		_show_free_arrows(_piece_drag)
	var xf: Variant = _piece_placement(at, _piece_drag)
	if xf != null:
		_piece_drag.global_transform = xf
		_follow_piece(_piece_drag)


## Delete a piece. Undo puts it back where it was (the history keeps it alive).
func _delete_piece(piece: StructurePiece) -> void:
	if _twin_piece(piece):
		_delete_items(_with_twins([piece]))
		return
	ctx.record_removed("Delete truss piece", piece, _attach_piece.bind(piece, piece.global_transform),
		_detach_piece.bind(piece))


func _attach_piece(piece: Object, xf: Transform3D, select := true) -> void:
	if not is_instance_valid(piece) or (piece as Node).get_parent() != null:
		return
	_set.add_child(piece as Node)
	(piece as StructurePiece).global_transform = xf
	_rebuild_pipes()
	if select:
		_select_piece(piece as StructurePiece)
	else:
		_refresh_marks()


func _detach_piece(piece: Object) -> void:
	if not is_instance_valid(piece) or (piece as Node).get_parent() != _set:
		return
	if _selected_piece == piece:
		_select_piece(null)
	if _piece_drag == piece:
		_piece_drag = null
	_group.erase(piece)
	(piece as StructurePiece).set_highlight(false) # so it comes back plain if undone
	_set.remove_child(piece as Node)
	_rebuild_pipes()


func _record_piece_move(piece: StructurePiece, before: Transform3D, action: String) -> void:
	var after := piece.global_transform
	if after.is_equal_approx(before):
		return
	ctx.record(action, _place_piece.bind(piece, after), _place_piece.bind(piece, before))


func _place_piece(piece: Object, xf: Transform3D) -> void:
	if is_instance_valid(piece) and (piece as Node).is_inside_tree():
		(piece as StructurePiece).global_transform = xf
		_follow_piece(piece as StructurePiece)
		_rebuild_pipes()


func _select_piece(piece: StructurePiece) -> void:
	if piece:
		_group.clear()
	_selected_piece = piece
	if piece and ctx and ctx.selected:
		ctx.select(null)
	_refresh_marks()


# ---------------------------------------------------------------- selection (one thing, or a box of several)

## Brackets on selected fixtures and a tint on selected pieces: the single
## selection (ctx.selected / _selected_piece) or every member of the group.
func _refresh_marks() -> void:
	var fx_sel: DMXFixture = ctx.selected if ctx else null
	for fx: DMXFixture in _visuals:
		(_visuals[fx] as StageFixture3D).set_selected(fx == fx_sel or _group.has(fx))
	for p in _pieces():
		p.set_highlight(p == _selected_piece or _group.has(p))
	if ctx:
		ctx.select_piece(_selected_piece if _group.is_empty() else null) # the inspector's details
		ctx.set_group(_group) # the inspector edits a group's fixtures together
	_refresh_aim_button()


## Everything selected right now, single or group.
func _selection() -> Array[Object]:
	if not _group.is_empty():
		return _group.duplicate()
	var list: Array[Object] = []
	if ctx.selected:
		list.append(ctx.selected)
	if _selected_piece:
		list.append(_selected_piece)
	return list


## Select exactly `items` (fixtures and/or pieces). One item is an ordinary
## selection (inspector, gizmo); two or more make a group.
## Frame the camera on whatever is selected (fixtures, truss, or a group).
## Returns false when nothing is selected so F can fall back to the whole rig.
func _frame_selection() -> bool:
	var points: Array[Vector3] = []
	for o: Object in _selection():
		if not is_instance_valid(o):
			continue
		if o is DMXFixture and _visuals.has(o):
			points.append((_visuals[o] as StageFixture3D).center())
		elif o is Node3D:
			points.append((o as Node3D).global_position)
	if points.is_empty():
		return false
	var box := AABB(points[0], Vector3.ZERO)
	for pt in points:
		box = box.expand(pt)
	_pivot.position = box.get_center()
	if _is_ortho():
		_ortho_size = maxf(box.get_longest_axis_size() * 1.6, 3.0)
	else:
		var radius := maxf(box.size.length() * 0.5, 0.4) # a single fixture is ~0.8 m across
		_distance = clampf(radius * 3.0, 1.5, 60.0)
	_update_camera()
	return true


func _set_selection(items: Array) -> void:
	if items.size() == 1:
		_group.clear()
		if items[0] is DMXFixture:
			_selected_piece = null
			ctx.select(items[0] as DMXFixture)
			_refresh_marks()
		else:
			_select_piece(items[0] as StructurePiece)
		return
	_group.clear()
	_selected_piece = null
	ctx.select(null)
	for o: Object in items:
		if is_instance_valid(o) and not _group.has(o):
			_group.append(o)
	_refresh_marks()
	_update_gizmo()


# ---------------------------------------------------------------- hide / isolate (editor view only)

## Hidden things are only left out of this view: no picking, no box select. The
## fixture itself is untouched, so DMX output and cues carry on as before.
func _is_hidden(o: Object) -> bool:
	if o is DMXFixture:
		return _visuals.has(o) and not (_visuals[o] as Node3D).visible
	return o is Node3D and not (o as Node3D).visible


func _set_hidden(o: Object, hidden: bool) -> void:
	if o is DMXFixture:
		if _visuals.has(o):
			(_visuals[o] as Node3D).visible = not hidden
	elif o is Node3D:
		(o as Node3D).visible = not hidden


## Everything that can be hidden: every fixture and set piece.
func _all_things() -> Array[Object]:
	var list: Array[Object] = []
	for fx: DMXFixture in _visuals:
		list.append(fx)
	for p in _pieces():
		list.append(p)
	return list


## H: hide what is selected (and drop it from the selection).
func _hide_selection() -> void:
	var sel := _selection()
	if sel.is_empty():
		return
	_set_selection([])
	for o in sel:
		_set_hidden(o, true)


## Shift+H: hide everything except the selection.
func _isolate_selection() -> void:
	var keep := _selection()
	if keep.is_empty():
		return
	for o in _all_things():
		_set_hidden(o, not keep.has(o))


## Alt+H: show everything again.
func _unhide_all() -> void:
	for o in _all_things():
		_set_hidden(o, false)


func _begin_box(at: Vector2, add: bool) -> void:
	_boxing = true
	_box_from = at
	_box_add = add
	if not add:
		_set_selection([]) # a plain click on empty space deselects, as before


func _box_rect(at: Vector2) -> Rect2:
	return Rect2(_box_from, Vector2.ZERO).expand(at)


func _update_box(at: Vector2) -> void:
	var dragged := at.distance_to(_box_from) >= _drag_threshold
	_box_select.visible = dragged
	if dragged:
		var r := _box_rect(at)
		_box_select.position = r.position
		_box_select.size = r.size


func _end_box(at: Vector2) -> void:
	_boxing = false
	_box_select.visible = false
	if at.distance_to(_box_from) < _drag_threshold:
		return # just a click
	var items: Array[Object] = []
	if _box_add:
		items = _selection()
	for o in _things_in(_box_rect(at)):
		if not items.has(o):
			items.append(o)
	_set_selection(items)


## Fixtures (and, while setting up the stage, pieces) whose middle is inside
## a screen rectangle.
func _things_in(rect: Rect2) -> Array[Object]:
	var list: Array[Object] = []
	for fx: DMXFixture in _visuals:
		if not _is_hidden(fx) and _on_screen_in((_visuals[fx] as StageFixture3D).center(), rect):
			list.append(fx)
	if ctx.workspace == StudioContext.Workspace.STAGE:
		for p in _pieces():
			if not _is_hidden(p) and _on_screen_in(p.world_bounds().get_center(), rect):
				list.append(p)
	return list


func _on_screen_in(p: Vector3, rect: Rect2) -> bool:
	return not _camera.is_position_behind(p) and rect.has_point(_camera.unproject_position(p))


func _transform_of(o: Object) -> Transform3D:
	if o is DMXFixture:
		return StudioContext.fixture_transform(o as DMXFixture)
	return (o as StructurePiece).global_transform


## Put each of `items` at its transform in `xfs` (fixtures and pieces alike).
func _place_group(items: Array, xfs: Array) -> void:
	var pieces_moved := false
	var followed: Array[Object] = [] ## mirror mode: a twin that comes along with its pair is not moved itself
	for i in items.size():
		var o: Object = items[i]
		if not is_instance_valid(o) or not (o as Node).is_inside_tree() or followed.has(o):
			continue
		if ctx.symmetry.active():
			var twin := StageSymmetry.partner_of(o)
			if twin and items.has(twin):
				followed.append(twin)
		if o is DMXFixture:
			ctx.move_fixture(o as DMXFixture, xfs[i])
		else:
			(o as StructurePiece).global_transform = xfs[i]
			_follow_piece(o as StructurePiece)
			pieces_moved = true
	if pieces_moved:
		_rebuild_pipes()


func _begin_group_drag(target: Object, at: Vector2) -> void:
	_group_drag = true
	_group_drag_started = false
	_group_target = target
	_press_pos = at
	var centre: Vector3
	if target is DMXFixture:
		centre = (_visuals[target] as StageFixture3D).center()
	else:
		centre = (target as StructurePiece).world_bounds().get_center()
	_group_plane = Plane(Vector3.UP, centre.y)
	var grab: Variant = _ray_plane(_group_plane, at)
	_group_grab = grab if grab != null else centre
	_group_before.clear()
	for o in _group:
		_group_before.append(_transform_of(o))


## Slide the whole group across the floor plan, keeping each thing's height.
func _update_group_drag(at: Vector2, ctrl_held: bool) -> void:
	if not _group_drag_started:
		if at.distance_to(_press_pos) < _drag_threshold:
			return
		_group_drag_started = true
	var hit: Variant = _ray_plane(_group_plane, at)
	if hit == null:
		return
	var delta: Vector3 = (hit as Vector3) - _group_grab
	delta.y = 0.0
	if _snapping(ctrl_held):
		delta.x = snappedf(delta.x, TransformGizmo.MOVE_STEP)
		delta.z = snappedf(delta.z, TransformGizmo.MOVE_STEP)
	var xfs: Array[Transform3D] = []
	for xf in _group_before:
		xfs.append(xf.translated(delta))
	_place_group(_group, xfs)


func _end_group_drag() -> void:
	_group_drag = false
	if not _group_drag_started:
		_set_selection([_group_target]) # a click on one of them picks just that one
		return
	var items := _group.duplicate()
	var after: Array[Transform3D] = []
	for o in items:
		after.append(_transform_of(o))
	ctx.record("Move %d things" % items.size(), _place_group.bind(items, after),
		_place_group.bind(items, _group_before.duplicate()))


## Delete everything in the group as one undo step; undo brings it all back
## (fixtures to their places in the rig, same patch) and selects it again.
## Ctrl+click: add `item` to the selection, or take it out if it is already in.
func _toggle_in_selection(item: Object) -> void:
	var items := _selection()
	if items.has(item):
		items.erase(item)
	else:
		items.append(item)
	_set_selection(items)


## Delete the selected fixture or group (the On stage list's Remove button).
func _delete_selected() -> void:
	if not _group.is_empty():
		_delete_group()
	elif ctx.selected:
		ctx.remove_fixture(ctx.selected)


func _delete_group() -> void:
	_delete_items(_with_twins(_group))


func _delete_items(items: Array) -> void:
	var fxs: Array[DMXFixture] = []
	var pieces: Array[StructurePiece] = []
	for o in items:
		if o is DMXFixture:
			fxs.append(o)
		elif o is StructurePiece:
			pieces.append(o)
	fxs.sort_custom(func(a: DMXFixture, b: DMXFixture) -> bool: return a.get_index() < b.get_index())
	var indices: Array[int] = []
	for fx in fxs:
		indices.append(fx.get_index())
	var xfs: Array[Transform3D] = []
	for p in pieces:
		xfs.append(p.global_transform)
	ctx.record_removed_all("Delete %d things" % items.size(), items.duplicate(),
		_attach_group.bind(fxs, indices, pieces, xfs), _detach_group.bind(fxs, pieces))


func _detach_group(fxs: Array, pieces: Array) -> void:
	_set_selection([])
	ctx.detach_fixtures(fxs)
	for p: Object in pieces:
		_detach_piece(p)


func _attach_group(fxs: Array, indices: Array, pieces: Array, xfs: Array) -> void:
	ctx.attach_fixtures(fxs, indices)
	for i in pieces.size():
		_attach_piece(pieces[i], xfs[i], false)
	var items: Array[Object] = []
	items.append_array(fxs)
	items.append_array(pieces)
	_set_selection(items)


# While a look is being edited, an amber badge at the top of the stage says so,
# so changes are never made to a saved look by accident.
func _style_look_edit_badge() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = UIPalette.ACCENT
	box.set_corner_radius_all(UIPalette.RADIUS)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	%LookEditBadge.add_theme_stylebox_override("panel", box)
	%LookEditText.add_theme_color_override("font_color", UIPalette.APP_BG)


func _show_look_edit_badge(look: Look) -> void:
	var badge: Control = %LookEditBadge
	badge.visible = look != null
	if look:
		%LookEditText.text = "EDITING LOOK: %s   ·   Save changes or Cancel in the Cues tab" % look.look_name.to_upper()


# ---------------------------------------------------------------- point moving heads at a spot

## The selected fixtures that can be aimed (they have pan and tilt), single or group.
func _aimable() -> Array[DMXFixture]:
	var list: Array[DMXFixture] = []
	if ctx == null:
		return list
	var picked: Array[Object] = _selection()
	for o in picked:
		if o is DMXFixture and Aim.can_aim(o as DMXFixture):
			list.append(o as DMXFixture)
	return list


func _refresh_aim_button() -> void:
	if _aim_button == null:
		return
	var n := _aimable().size()
	_aim_button.disabled = n == 0
	if n == 0 and _aiming:
		_aim_button.button_pressed = false
	_aim_button.tooltip_text = "Point the selected moving heads at a spot: click or drag on the stage and they all aim there (T).\n" + \
		("Select one or more moving heads first." if n == 0 else "%d moving head%s selected." % [n, "" if n == 1 else "s"])


func _set_aiming(on: bool) -> void:
	_aiming = on
	_aim_drag = false
	_aim_unreachable = 0
	if not on:
		_drop_marker.visible = false
	_update_help()


## Where a screen point meets the room: the nearest surface, or the floor plane
## when the ray misses every box. Null if it points at the sky.
func _aim_hit(at: Vector2) -> StageRoom.Hit:
	var origin := _camera.project_ray_origin(at)
	var dir := _camera.project_ray_normal(at)
	var hit := StageRoom.raycast(_surfaces, origin, dir)
	if hit:
		return hit
	var p: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
	if p == null:
		return null
	var floor_point: Vector3 = p
	return StageRoom.Hit.new(floor_point, Vector3.UP, StageRoom.Kind.FLOOR)


func _begin_aim(at: Vector2) -> void:
	_aim_before.clear()
	for fx in _aimable():
		_aim_before[fx] = Vector2(fx.pan, fx.tilt)
	if _aim_before.is_empty():
		return
	_aim_drag = true
	_update_aim(at)


func _update_aim(at: Vector2) -> void:
	var hit := _aim_hit(at)
	if hit == null:
		return
	_aim_unreachable = 0
	for fx: DMXFixture in _aim_before:
		if not Aim.aim_at(fx, StudioContext.fixture_transform(fx), hit.position):
			_aim_unreachable += 1
	# Ring on the spot, lying flat on whatever surface it is on.
	var b := StageRoom.mount_basis(hit.normal)
	_drop_marker.global_transform = Transform3D(Basis(b.x, b.z, -b.y), hit.position + hit.normal * 0.02)
	_drop_marker.visible = true
	_update_help()


## One undo step for the whole sweep: every head back to where it pointed.
func _end_aim() -> void:
	_aim_drag = false
	var before := _aim_before.duplicate()
	var after: Dictionary = {}
	for fx: DMXFixture in before:
		after[fx] = Vector2(fx.pan, fx.tilt)
	if after == before:
		return
	ctx.record("Point lights", _set_pan_tilt.bind(after), _set_pan_tilt.bind(before))


func _set_pan_tilt(values: Dictionary) -> void:
	for fx: DMXFixture in values:
		if is_instance_valid(fx):
			var v: Vector2 = values[fx]
			fx.pan = v.x
			fx.tilt = v.y
