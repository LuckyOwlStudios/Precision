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
##   Stage workspace, a structure piece: click selects, drag re-snaps it,
##                                       R turns it a quarter turn, Delete removes it
##   Shift + left drag                 -> re-stick it onto another surface
##   W / E                             -> move / rotate gizmo; Ctrl while dragging snaps
##   Hold right mouse                  -> fly, like the Godot editor: drag to look,
##                                       WASD move, Q/E down/up, Shift faster,
##                                       Alt slower, wheel sets the fly speed
##   Alt+left drag                     -> orbit       Middle drag -> pan
##   Mouse wheel                       -> zoom        F -> frame the rig
##   Z / Work, Show buttons            -> work lights on (evenly lit room) / dark show room

const PICK_RADIUS_PX := 28.0
const DRAG_THRESHOLD_PX := 4.0
const PIPE_GRAB_PX := 26.0 ## a fixture snaps to a tube this close to the cursor on screen
const CONNECTOR_GRAB_PX := 70.0 ## a piece snaps to a free connector this close on screen

const FLY_SPEED_DEFAULT := 4.0 ## metres a second
const FLY_SPEED_MIN := 0.25
const FLY_SPEED_MAX := 40.0
const FLY_FAST := 3.0 ## Shift
const FLY_SLOW := 0.25 ## Alt
const LOOK_DEG_PER_PX := 0.25
const FLY_KEYS: Array[Key] = [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E]
const HELP_TEXT := "Right drag fly (WASD, Q/E, wheel speed) · Alt drag orbit · Middle drag pan · Wheel zoom · F frame · Shift drag re-stick · F2 rename · Z work lights"

var ctx: StudioContext

var look := StageLook.new() ## haze and render quality (visual only)
var _visuals: Dictionary = {} ## DMXFixture -> StageFixture3D

var _yaw := 0.0
var _pitch := -14.0
var _distance := 12.5
var _orbiting := false
var _panning := false
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

var _mode_buttons: Dictionary = {} ## TransformGizmo.Mode -> Button
var _view_buttons: Dictionary = {} ## preset name -> Button
var _quality_buttons: Array[Button] = []
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
@onready var _drop_marker: MeshInstance3D = %DropMarker
@onready var _gizmo: TransformGizmo = %Gizmo
@onready var _tools: Control = %Tools
@onready var _snap_button: Button = %Snap
@onready var _haze: HSlider = %Haze
@onready var _empty_hint: Control = %EmptyHint
@onready var _help: Label = %Help


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.fixtures_changed.connect(_sync_fixtures)
	ctx.selection_changed.connect(_on_selection_changed)
	ctx.fixture_moved.connect(_on_fixture_moved)
	ctx.workspace_changed.connect(_on_workspace_changed)
	ctx.truss_pipes = _pipes
	_sync_fixtures()


func _ready() -> void:
	look.load_saved()
	_surfaces = StageRoom.surfaces_in(_room)
	_rebuild_pipes()
	(_drop_marker.material_override as ShaderMaterial).set_shader_parameter("color", UIPalette.ACCENT)
	_gizmo.camera = _camera

	# View presets, top left.
	_view_buttons = {"Perspective": %Perspective, "Front": %Front, "Top": %Top}
	for preset: String in _view_buttons:
		(_view_buttons[preset] as Button).pressed.connect(_set_view.bind(preset))

	# Gizmo mode and snapping, top right.
	_mode_buttons = {TransformGizmo.Mode.MOVE: %Move, TransformGizmo.Mode.ROTATE: %Rotate}
	for m: TransformGizmo.Mode in _mode_buttons:
		(_mode_buttons[m] as Button).pressed.connect(set_gizmo_mode.bind(m))
	_snap_button.tooltip_text = "Move in %.2f m steps and rotate in %d° steps. Hold Ctrl while dragging to flip this." % [TransformGizmo.MOVE_STEP, int(TransformGizmo.ROTATE_STEP)]
	set_gizmo_mode(TransformGizmo.Mode.MOVE)

	# Work / Show shading, top left beside the view presets.
	_shading_buttons = [%Work, %Show]
	for sh in _shading_buttons.size():
		_shading_buttons[sh].pressed.connect(func() -> void: look.shading = sh as StageLook.Shading)

	# Haze and quality, bottom right: how the stage is drawn, not the show.
	_haze.value = look.haze
	_haze.value_changed.connect(func(v: float) -> void: look.haze = v)
	_quality_buttons = [%Low, %Medium, %High, %Ultra]
	for q in _quality_buttons.size():
		_quality_buttons[q].pressed.connect(func() -> void: look.quality = q as StageLook.Quality)
	%ForwardPlusNote.visible = not look.forward_plus
	look.changed.connect(_sync_look_controls)
	_sync_look_controls()

	%LoadDemo.pressed.connect(func() -> void: ctx.load_demo_rig())

	look.changed.connect(_apply_look)
	_apply_look()
	_help.text = HELP_TEXT
	_update_camera()


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
	for i in _quality_buttons.size():
		_quality_buttons[i].button_pressed = i == look.quality
	for i in _shading_buttons.size():
		_shading_buttons[i].button_pressed = i == look.shading


func _set_view(preset: String) -> void:
	for key: String in _view_buttons:
		(_view_buttons[key] as Button).button_pressed = key == preset
	match preset:
		"Perspective":
			_yaw = 0.0
			_pitch = -14.0
		"Front":
			_yaw = 0.0
			_pitch = -2.0
		"Top":
			_yaw = 0.0
			_pitch = -88.0
	_update_camera()


# ---------------------------------------------------------------- fixtures

func _sync_fixtures() -> void:
	if ctx == null:
		return
	var live := ctx.fixtures()
	for fx: DMXFixture in _visuals.keys():
		if not live.has(fx) or not is_instance_valid(fx):
			(_visuals[fx] as Node).queue_free()
			_visuals.erase(fx)
	for fx in live:
		if not _visuals.has(fx):
			var v := StageFixture3D.create(fx)
			_fixtures.add_child(v)
			v.setup(fx, ctx, look)
			_visuals[fx] = v
			_update_rigging(fx)
	_empty_hint.visible = live.is_empty()
	_update_gizmo()


func _on_workspace_changed(_ws: StudioContext.Workspace) -> void:
	_update_gizmo()
	_select_piece(null) # pieces are only edited while setting up the stage


func _on_selection_changed(fx: DMXFixture) -> void:
	if fx:
		_select_piece(null)
	for key: DMXFixture in _visuals:
		(_visuals[key] as StageFixture3D).set_selected(key == fx)
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
	_grid.visible = staging # a placement aid; the show looks cleaner without it
	_tools.visible = staging
	_gizmo.shown = staging and fx != null and _visuals.has(fx)
	if _gizmo.shown:
		_gizmo.target = StudioContext.fixture_transform(fx)


func set_gizmo_mode(m: TransformGizmo.Mode) -> void:
	_gizmo.mode = m
	for key: TransformGizmo.Mode in _mode_buttons:
		(_mode_buttons[key] as Button).button_pressed = key == m


func _snapping(ctrl_held: bool) -> bool:
	return _snap_button.button_pressed != ctrl_held


# ---------------------------------------------------------------- placing against surfaces

## Clamps show while a fixture hangs on a tube and hide once it is moved off.
func _update_rigging(fx: DMXFixture) -> void:
	(_visuals[fx] as StageFixture3D).set_rigged(_pipe_holding(fx) != null)


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
			return StageRoom.hang(grab[0], grab[1], mounts)
	var hit := StageRoom.raycast(_surfaces, origin, dir)
	if hit == null:
		return null
	var pos := hit.position
	if hit.kind == StageRoom.Kind.FLOOR:
		pos = Vector3(clampf(pos.x, -7.5, 7.5), pos.y, clampf(pos.z, -5.5, 5.5)) # stay in the room
	return Transform3D(StageRoom.mount_basis(hit.normal), pos + hit.normal * StageFixture3D.mount_offset(body))


## The tube nearest the cursor on screen, and where along it: [Pipe, along],
## or [] if none is within PIPE_GRAB_PX. Of tubes about as near, the one
## closer to the camera wins.
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
			best = [pipe, float(r[0])]
	return best


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
		_drop_marker.visible = false
		_clear_ghost()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		_set_flying(false) # alt-tabbed away mid-flight: don't keep flying


func _pick(at: Vector2) -> DMXFixture:
	var best: DMXFixture = null
	var best_d := PICK_RADIUS_PX
	for fx: DMXFixture in _visuals:
		var v: StageFixture3D = _visuals[fx]
		var c := v.center()
		if _camera.is_position_behind(c):
			continue
		var d := _camera.unproject_position(c).distance_to(at)
		if d < best_d:
			best_d = d
			best = fx
	return best


# ---------------------------------------------------------------- moving a fixture by its body

func _begin_body_drag(fx: DMXFixture, at: Vector2, restick: bool) -> void:
	_dragging = fx
	_drag_started = false
	_drag_restick = restick
	_press_pos = at
	_drag_start = StudioContext.fixture_transform(fx)
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
		if at.distance_to(_press_pos) < DRAG_THRESHOLD_PX:
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
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed and mb.alt_pressed:
					_orbiting = true
				elif mb.pressed:
					_on_left_press(mb)
				else:
					_orbiting = false
					_dragging = null
					if _piece_drag:
						_piece_drag = null
						_rebuild_pipes()
					if _gizmo.is_dragging():
						_gizmo.end_drag()
						_update_gizmo()
			MOUSE_BUTTON_RIGHT:
				_set_flying(mb.pressed)
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed and _flying:
					_set_fly_speed(_fly_speed * 1.2)
				elif mb.pressed:
					_distance = maxf(3.0, _distance * 0.9)
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed and _flying:
					_set_fly_speed(_fly_speed / 1.2)
				elif mb.pressed:
					_distance = minf(40.0, _distance * 1.1)
					_update_camera()
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _flying:
			_look(mm.relative)
		elif _orbiting:
			_yaw -= mm.relative.x * 0.3
			# Orbiting never dips the camera under the floor, but it won't snap
			# down a view that flying left looking up, either.
			_pitch = clampf(_pitch - mm.relative.y * 0.3, -89.0, maxf(5.0, _pitch))
			_update_camera()
		elif _panning:
			var right := _camera.global_transform.basis.x
			var fwd := Vector3(_camera.global_transform.basis.z.x, 0, _camera.global_transform.basis.z.z).normalized()
			_pivot.position += (-right * mm.relative.x + -fwd * mm.relative.y) * _distance * 0.0016
			_update_camera()
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
		match k.keycode:
			KEY_F:
				_pivot.position = Vector3(0, 1.4, -0.5)
				_distance = 12.5
				_update_camera()
			KEY_W:
				set_gizmo_mode(TransformGizmo.Mode.MOVE)
			KEY_E:
				set_gizmo_mode(TransformGizmo.Mode.ROTATE)
			KEY_Z:
				if k.ctrl_pressed or k.meta_pressed:
					return # leave Ctrl+Z / Cmd+Z for undo
				look.shading = StageLook.Shading.SHOW if look.work_lights() else StageLook.Shading.WORK
			KEY_DELETE:
				if _selected_piece:
					_delete_piece(_selected_piece)
				elif ctx.selected:
					ctx.remove_fixture(ctx.selected)
				else:
					return
			KEY_R:
				if not _selected_piece:
					return
				_selected_piece.global_transform = StructureSnap.turned(_selected_piece, _pieces())
				_rebuild_pipes()
			_:
				return
		accept_event()


func _on_left_press(mb: InputEventMouseButton) -> void:
	var handle := _gizmo.handle_at(mb.position)
	if handle != TransformGizmo.Handle.NONE and ctx.selected:
		_gizmo.target = StudioContext.fixture_transform(ctx.selected)
		_gizmo.begin_drag(handle, mb.position)
		return
	var fx := _pick(mb.position)
	ctx.select(fx)
	if fx == null:
		var piece: StructurePiece = _pick_piece(mb.position) if ctx.workspace == StudioContext.Workspace.STAGE else null
		_select_piece(piece)
		if piece:
			_piece_drag = piece
			_piece_drag_started = false
			_press_pos = mb.position
		return
	if mb.double_click:
		ctx.request_rename(fx)
		return
	_begin_body_drag(fx, mb.position, mb.shift_pressed)


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


func _update_help() -> void:
	_help.text = "Flying %.1f m/s · WASD move · Q/E down/up · Shift faster · Alt slower · Wheel speed" % _fly_speed if _flying else HELP_TEXT


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


## Point the orbit camera (degrees, metres). Used by the screenshot helper.
func set_orbit(yaw: float, pitch: float, distance: float) -> void:
	_yaw = yaw
	_pitch = pitch
	_distance = distance
	_update_camera()


func _update_camera() -> void:
	_pivot.rotation_degrees = Vector3(_pitch, _yaw, 0)
	_camera.position = Vector3(0, 0, _distance)
	_camera.rotation = Vector3.ZERO
	_gizmo.queue_redraw()


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
	var xf: Variant = _piece_placement(at, _ghost)
	_ghost.visible = xf != null
	if xf != null:
		_ghost.global_transform = xf


func _clear_ghost() -> void:
	if _ghost:
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
	_rebuild_pipes()
	_select_piece(piece)


func _update_piece_drag(at: Vector2) -> void:
	if not _piece_drag_started:
		if at.distance_to(_press_pos) < DRAG_THRESHOLD_PX:
			return
		_piece_drag_started = true
	var xf: Variant = _piece_placement(at, _piece_drag)
	if xf != null:
		_piece_drag.global_transform = xf


func _delete_piece(piece: StructurePiece) -> void:
	_select_piece(null)
	_set.remove_child(piece)
	piece.queue_free()
	_rebuild_pipes()


func _select_piece(piece: StructurePiece) -> void:
	if _selected_piece == piece:
		return
	if _selected_piece and is_instance_valid(_selected_piece):
		_selected_piece.set_highlight(false)
	_selected_piece = piece
	if piece:
		piece.set_highlight(true)
		if ctx and ctx.selected:
			ctx.select(null)


## The structure piece under the cursor (nearest its box along the ray), or null.
func _pick_piece(at: Vector2) -> StructurePiece:
	var origin := _camera.project_ray_origin(at)
	var dir := _camera.project_ray_normal(at)
	var best: StructurePiece = null
	var best_t := INF
	for p in _pieces():
		var r := StageRoom.ray_box(p.world_bounds(), origin, dir)
		if not r.is_empty() and float(r[0]) < best_t:
			best_t = r[0]
			best = p
	return best
