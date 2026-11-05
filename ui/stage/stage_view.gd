class_name StageView
extends Control
## The 3D stage in the middle of the window.
##   Drop a fixture from the library  -> it sticks flush to the truss, wall or
##                                       floor under the cursor (hold Alt: no snapping)
##   Left click / double-click / F2    -> select / rename a fixture
##   Left drag a fixture               -> slide it along the surface it is on
##   Shift + left drag                 -> re-stick it onto another surface
##   W / E                             -> move / rotate gizmo; Ctrl while dragging snaps
##   Right drag / Alt+left drag        -> orbit       Middle drag -> pan
##   Mouse wheel                       -> zoom        F -> frame the rig

const PICK_RADIUS_PX := 28.0
const DRAG_THRESHOLD_PX := 4.0

var ctx: StudioContext

var look := StageLook.new() ## haze and render quality (visual only)
var _visuals: Dictionary = {} ## DMXFixture -> StageFixture3D

var _yaw := 0.0
var _pitch := -14.0
var _distance := 12.5
var _orbiting := false
var _panning := false
var _surfaces: Array[StageRoom.Surface] = []

# Dragging a fixture by its body (not the gizmo).
var _dragging: DMXFixture
var _drag_started := false
var _drag_restick := false
var _press_pos := Vector2.ZERO
var _drag_plane := Plane()
var _drag_offset := Vector3.ZERO ## fixture origin minus the grab point on the plane
var _drag_screen_offset := Vector2.ZERO ## fixture on screen minus the cursor
var _drag_start := Transform3D.IDENTITY

var _mode_buttons: Dictionary = {} ## TransformGizmo.Mode -> Button
var _view_buttons: Dictionary = {} ## preset name -> Button
var _quality_buttons: Array[Button] = []

@onready var _viewport: SubViewport = %Viewport
@onready var _env: Environment = (%Environment as WorldEnvironment).environment
@onready var _room: Node3D = %Room
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


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.fixtures_changed.connect(_sync_fixtures)
	ctx.selection_changed.connect(_on_selection_changed)
	ctx.fixture_moved.connect(_on_fixture_moved)
	ctx.workspace_changed.connect(func(_ws: StudioContext.Workspace) -> void: _update_gizmo())
	_sync_fixtures()


func _ready() -> void:
	look.load_saved()
	_surfaces = StageRoom.surfaces_in(_room)
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
	_update_camera()


## Haze or quality changed: retune the environment and the viewport.
## (Each fixture listens to `look` itself for its shadows and beams.)
func _apply_look() -> void:
	look.apply(_env)
	_viewport.msaa_3d = look.msaa()
	_viewport.positional_shadow_atlas_size = look.shadow_atlas_size()
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa = false
	look.save()


func _sync_look_controls() -> void:
	_haze.set_value_no_signal(look.haze)
	for i in _quality_buttons.size():
		_quality_buttons[i].button_pressed = i == look.quality


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
	_empty_hint.visible = live.is_empty()
	_update_gizmo()


func _on_selection_changed(fx: DMXFixture) -> void:
	for key: DMXFixture in _visuals:
		(_visuals[key] as StageFixture3D).set_selected(key == fx)
	_update_gizmo()


func _on_fixture_moved(fx: DMXFixture) -> void:
	if _visuals.has(fx):
		(_visuals[fx] as StageFixture3D).sync_position()
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

## Where a fixture would go if dropped (or re-stuck) at a screen point: flush on
## the surface under it, beam pointing into the room. With `no_snap` (Alt held) it
## hangs at the default height above the floor point instead. Null on a miss.
func _placement(at: Vector2, body: FixtureCatalog.Body, no_snap: bool) -> Variant:
	var origin := _camera.project_ray_origin(at)
	var dir := _camera.project_ray_normal(at)
	if no_snap:
		var p: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
		if p == null:
			return null
		var fp: Vector3 = p
		return Transform3D(Basis.IDENTITY, Vector3(clampf(fp.x, -7.5, 7.5), StageFixture3D.MOUNT_HEIGHT, clampf(fp.z, -5.5, 5.5)))
	var hit := StageRoom.raycast(_surfaces, origin, dir)
	if hit == null:
		return null
	var pos := hit.position
	if hit.kind == StageRoom.Kind.FLOOR:
		pos = Vector3(clampf(pos.x, -7.5, 7.5), pos.y, clampf(pos.z, -5.5, 5.5)) # stay in the room
	return Transform3D(StageRoom.mount_basis(hit.normal), pos + hit.normal * StageFixture3D.mount_offset(body))


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	var ok: bool = data is Dictionary and (data as Dictionary).get("kind") == "fixture"
	if ok:
		var entry: FixtureCatalog.Entry = (data as Dictionary)["entry"]
		var xf: Variant = _placement(at, entry.body, Input.is_key_pressed(KEY_ALT))
		_drop_marker.visible = xf != null
		if xf != null:
			var t: Transform3D = xf
			# Lay the ring flat on the surface: the quad faces along the surface normal.
			var b := Basis(t.basis.x, t.basis.z, -t.basis.y)
			_drop_marker.global_transform = Transform3D(b, t.origin + t.basis.y * StageFixture3D.mount_offset(entry.body) * 0.97)
	return ok


func _drop_data(at: Vector2, data: Variant) -> void:
	_drop_marker.visible = false
	var entry: FixtureCatalog.Entry = (data as Dictionary)["entry"]
	var xf: Variant = _placement(at, entry.body, Input.is_key_pressed(KEY_ALT))
	if xf == null:
		xf = Transform3D(Basis.IDENTITY, Vector3(0, StageFixture3D.MOUNT_HEIGHT, 0))
	var t: Transform3D = xf
	ctx.add_fixture(entry, t.origin, t.basis)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END or what == NOTIFICATION_MOUSE_EXIT:
		_drop_marker.visible = false


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


func _update_body_drag(at: Vector2, ctrl_held: bool) -> void:
	if not _drag_started:
		if at.distance_to(_press_pos) < DRAG_THRESHOLD_PX:
			return # a click, not a drag: don't nudge the fixture
		_drag_started = true
	var body: FixtureCatalog.Body = _dragging.get_meta(StudioContext.META_BODY, FixtureCatalog.Body.PAR)
	if _drag_restick:
		var xf: Variant = _placement(at + _drag_screen_offset, body, false)
		if xf != null:
			ctx.move_fixture(_dragging, xf)
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
					if _gizmo.is_dragging():
						_gizmo.end_drag()
						_update_gizmo()
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_distance = maxf(3.0, _distance * 0.9)
					_update_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_distance = minf(40.0, _distance * 1.1)
					_update_camera()
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			_yaw -= mm.relative.x * 0.3
			_pitch = clampf(_pitch - mm.relative.y * 0.3, -89.0, 5.0)
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
		else:
			_gizmo.hovered = _gizmo.handle_at(mm.position)
	elif event is InputEventKey:
		var k := event as InputEventKey
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
			KEY_DELETE:
				if not ctx.selected:
					return
				ctx.remove_fixture(ctx.selected)
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
		return
	if mb.double_click:
		ctx.request_rename(fx)
		return
	_begin_body_drag(fx, mb.position, mb.shift_pressed)


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
