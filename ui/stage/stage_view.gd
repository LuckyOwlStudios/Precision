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

var _container := SubViewportContainer.new()
var _viewport := SubViewport.new()
var _world := Node3D.new()
var _pivot := Node3D.new()
var _camera := Camera3D.new()
var _visuals: Dictionary = {} ## DMXFixture -> StageFixture3D
var look := StageLook.new() ## haze and render quality (visual only)
var _env: Environment

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

var _empty_hint: Control
var _overlay: Control
var _gizmo := TransformGizmo.new()
var _mode_buttons: Dictionary = {} ## TransformGizmo.Mode -> Button
var _snap_button := Button.new()
var _tools: HBoxContainer
var _drop_marker := MeshInstance3D.new()
var _grid: MeshInstance3D


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.fixtures_changed.connect(_sync_fixtures)
	ctx.selection_changed.connect(_on_selection_changed)
	ctx.fixture_moved.connect(_on_fixture_moved)
	ctx.workspace_changed.connect(func(_ws: StudioContext.Workspace) -> void: _update_gizmo())
	_sync_fixtures()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	# The container only displays the 3D image; this Control handles input.
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_container)
	_viewport.own_world_3d = true
	look.load_saved()
	look.changed.connect(_apply_look)
	_container.add_child(_viewport)
	_viewport.add_child(_world)
	_build_world()
	_build_overlay()
	_update_camera()


# ---------------------------------------------------------------- world

func _build_world() -> void:
	_env = look.build_environment()
	var we := WorldEnvironment.new()
	we.environment = _env
	_world.add_child(we)
	_apply_look()

	_surfaces = StageRoom.surfaces()
	for surf in _surfaces:
		if surf.kind == StageRoom.Kind.TRUSS:
			continue # drawn as a lattice by StageSet
		var mesh := BoxMesh.new()
		mesh.size = surf.box.size
		_add_static(mesh, surf.material, surf.box.get_center())
	StageSet.build(_world)
	_add_grid(16, 12)
	_build_drop_marker()

	_world.add_child(_pivot)
	_pivot.add_child(_camera)
	_camera.fov = 50.0
	_pivot.position = Vector3(0, 1.4, -0.5)


## Haze or quality changed: retune the environment and the viewport.
## (Each fixture listens to `look` itself for its shadows and beams.)
func _apply_look() -> void:
	look.apply(_env)
	_viewport.msaa_3d = look.msaa()
	_viewport.positional_shadow_atlas_size = look.shadow_atlas_size()
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa = false
	look.save()


func _add_static(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_world.add_child(mi)


## Amber ring that shows where a dragged-in fixture will land, lying flat on
## the surface (same look as the selection brackets).
func _build_drop_marker() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://ui/stage/marker.gdshader")
	mat.set_shader_parameter("color", UIPalette.ACCENT)
	mat.set_shader_parameter("style", 1)
	mat.set_shader_parameter("billboard", false)
	mat.set_shader_parameter("world_size", 0.28)
	mat.set_shader_parameter("min_px", 16.0)
	mat.render_priority = 10
	_drop_marker.mesh = quad
	_drop_marker.material_override = mat
	_drop_marker.extra_cull_margin = 4.0
	_drop_marker.visible = false
	_world.add_child(_drop_marker)


func _add_grid(w: int, d: int) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for x in range(-w / 2, w / 2 + 1):
		im.surface_add_vertex(Vector3(x, 0.002, -d / 2.0))
		im.surface_add_vertex(Vector3(x, 0.002, d / 2.0))
	for z in range(-d / 2, d / 2 + 1):
		im.surface_add_vertex(Vector3(-w / 2.0, 0.002, z))
		im.surface_add_vertex(Vector3(w / 2.0, 0.002, z))
	im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.05)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_grid = MeshInstance3D.new()
	_grid.mesh = im
	_grid.material_override = mat
	_grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(_grid)


# ---------------------------------------------------------------- overlay (2D on top of 3D)

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_gizmo.camera = _camera
	_overlay.add_child(_gizmo)

	# View presets, top left.
	var bar := HBoxContainer.new()
	bar.position = Vector2(16, 14)
	bar.add_theme_constant_override("separation", 2)
	_overlay.add_child(bar)
	for preset: String in ["Perspective", "Front", "Top"]:
		var b := Button.new()
		b.text = preset
		b.theme_type_variation = &"PillButton"
		b.toggle_mode = true
		b.button_pressed = preset == "Perspective"
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.pressed.connect(_set_view.bind(preset, bar))
		bar.add_child(b)

	# Gizmo mode and snapping, top right.
	var tools := HBoxContainer.new()
	tools.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tools.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tools.offset_left = -16
	tools.offset_right = -16
	tools.offset_top = 14
	tools.add_theme_constant_override("separation", 2)
	_overlay.add_child(tools)
	_tools = tools
	for m: TransformGizmo.Mode in [TransformGizmo.Mode.MOVE, TransformGizmo.Mode.ROTATE]:
		var b := Button.new()
		b.text = "Move  W" if m == TransformGizmo.Mode.MOVE else "Rotate  E"
		b.tooltip_text = "Drag the arrows to move along one axis, the squares to move in a plane" if m == TransformGizmo.Mode.MOVE else "Drag a ring to turn the fixture around that axis"
		b.theme_type_variation = &"PillButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.pressed.connect(set_gizmo_mode.bind(m))
		tools.add_child(b)
		_mode_buttons[m] = b
	var gap := Control.new()
	gap.custom_minimum_size.x = 10
	tools.add_child(gap)
	_snap_button.text = "Snap"
	_snap_button.tooltip_text = "Move in %.2f m steps and rotate in %d° steps. Hold Ctrl while dragging to flip this." % [TransformGizmo.MOVE_STEP, int(TransformGizmo.ROTATE_STEP)]
	_snap_button.theme_type_variation = &"PillButton"
	_snap_button.toggle_mode = true
	_snap_button.focus_mode = Control.FOCUS_NONE
	_snap_button.mouse_filter = Control.MOUSE_FILTER_STOP
	tools.add_child(_snap_button)
	set_gizmo_mode(TransformGizmo.Mode.MOVE)

	_build_look_controls()

	var help := Label.new()
	help.text = "Right drag orbit · Middle drag pan · Wheel zoom · F frame · Shift drag re-stick · F2 rename"
	help.theme_type_variation = &"Caption"
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(16, -30)
	help.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_overlay.add_child(help)

	# Empty state, centred.
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title := Label.new()
	title.text = "Your stage is empty"
	title.theme_type_variation = &"BigTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := Label.new()
	sub.text = "Drag a fixture from the library onto a truss, wall or the floor. It sticks to what you drop it on."
	sub.theme_type_variation = &"Subtitle"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var demo := Button.new()
	demo.text = "Load demo rig"
	demo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	demo.mouse_filter = Control.MOUSE_FILTER_STOP
	demo.pressed.connect(func() -> void: ctx.load_demo_rig())
	box.add_child(title)
	box.add_child(sub)
	box.add_child(demo)
	_empty_hint = box
	_overlay.add_child(box)


## Haze and quality, bottom right: how the stage is drawn, not the show.
func _build_look_controls() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	row.offset_left = -16
	row.offset_right = -16
	row.offset_top = -14
	row.offset_bottom = -14
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(row)

	var haze_label := Label.new()
	haze_label.text = "Haze"
	haze_label.theme_type_variation = &"Caption"
	row.add_child(haze_label)
	var haze := HSlider.new()
	haze.custom_minimum_size = Vector2(110, 0)
	haze.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	haze.min_value = 0.0
	haze.max_value = 1.0
	haze.step = 0.01
	haze.value = look.haze
	haze.focus_mode = Control.FOCUS_NONE
	haze.mouse_filter = Control.MOUSE_FILTER_STOP
	haze.tooltip_text = "How much haze is in the room. Beams and light shafts show up more in haze."
	haze.value_changed.connect(func(v: float) -> void: look.haze = v)
	row.add_child(haze)
	var quality_buttons: Array[Button] = []

	var gap := Control.new()
	gap.custom_minimum_size.x = 6
	row.add_child(gap)
	for q in StageLook.Quality.size():
		var b := Button.new()
		b.text = StageLook.QUALITY_NAMES[q]
		b.theme_type_variation = &"PillButton"
		b.toggle_mode = true
		b.button_pressed = q == look.quality
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.tooltip_text = [
			"Fastest: beam cones only, no shadows or volumetric haze",
			"Volumetric haze, moving head shadows, ambient occlusion",
			"Every light casts shadows, floor reflections, smoother haze",
			"Highest detail haze, soft shadows, light bounce. Needs a strong GPU",
		][q]
		b.pressed.connect(func() -> void: look.quality = q as StageLook.Quality)
		row.add_child(b)
		quality_buttons.append(b)
	look.changed.connect(func() -> void:
		haze.set_value_no_signal(look.haze)
		for i in quality_buttons.size():
			quality_buttons[i].button_pressed = i == look.quality)
	if not look.forward_plus:
		var note := Label.new()
		note.text = "Haze and shadows need the Forward+ renderer"
		note.theme_type_variation = &"Caption"
		row.add_child(note)


func _set_view(preset: String, bar: HBoxContainer) -> void:
	for b in bar.get_children():
		(b as Button).button_pressed = (b as Button).text == preset
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
			var v := StageFixture3D.new()
			_world.add_child(v)
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
