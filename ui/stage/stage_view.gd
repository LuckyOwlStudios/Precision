class_name StageView
extends Control
## The 3D stage in the middle of the window.
##   Drop a fixture from the library  -> it is hung above the spot you dropped on
##   Left click                        -> select a fixture
##   Left drag a selected fixture      -> move it
##   Right drag / Alt+left drag        -> orbit       Middle drag -> pan
##   Mouse wheel                       -> zoom        F -> frame the rig

const PICK_RADIUS_PX := 28.0

var ctx: StudioContext

var _container := SubViewportContainer.new()
var _viewport := SubViewport.new()
var _world := Node3D.new()
var _pivot := Node3D.new()
var _camera := Camera3D.new()
var _visuals: Dictionary = {} ## DMXFixture -> StageFixture3D

var _yaw := 0.0
var _pitch := -14.0
var _distance := 12.5
var _orbiting := false
var _panning := false
var _dragging: DMXFixture
var _drag_moved := false

var _empty_hint: Control
var _overlay: Control


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.fixtures_changed.connect(_sync_fixtures)
	ctx.selection_changed.connect(_on_selection_changed)
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
	_viewport.msaa_3d = Viewport.MSAA_4X
	_container.add_child(_viewport)
	_viewport.add_child(_world)
	_build_world()
	_build_overlay()
	_update_camera()


# ---------------------------------------------------------------- world

func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = UIPalette.APP_BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("39404d")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Glow makes beams bloom nicely in Forward+, but washes the whole frame
	# grey in the Compatibility renderer, so only turn it on for Forward+.
	env.glow_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	# Floor: dark, slightly glossy so beams leave a pool and a reflection.
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("1c1f24")
	floor_mat.roughness = 0.55
	floor_mat.metallic = 0.1
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(60, 60)
	_add_static(floor_mesh, floor_mat, Vector3.ZERO)

	_add_grid(16, 12)

	# Back wall, truss and a DJ booth for scale.
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color("15171b")
	var wall := BoxMesh.new()
	wall.size = Vector3(16, 6, 0.2)
	_add_static(wall, wall_mat, Vector3(0, 3, -6))

	var truss_mat := StandardMaterial3D.new()
	truss_mat.albedo_color = Color("5a606b")
	truss_mat.metallic = 0.8
	truss_mat.roughness = 0.35
	for z: float in [0.5, -0.8]:
		var truss := BoxMesh.new()
		truss.size = Vector3(9.0, 0.12, 0.12)
		_add_static(truss, truss_mat, Vector3(0, StageFixture3D.MOUNT_HEIGHT + 0.3, z))

	var booth_mat := StandardMaterial3D.new()
	booth_mat.albedo_color = Color("1f2228")
	booth_mat.roughness = 0.7
	var booth := BoxMesh.new()
	booth.size = Vector3(2.0, 1.0, 0.8)
	_add_static(booth, booth_mat, Vector3(0, 0.5, -2.6))
	var deck := BoxMesh.new()
	deck.size = Vector3(1.6, 0.06, 0.5)
	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_color = Color("0b0c0e")
	_add_static(deck, deck_mat, Vector3(0, 1.03, -2.6))

	_world.add_child(_pivot)
	_pivot.add_child(_camera)
	_camera.fov = 50.0
	_pivot.position = Vector3(0, 1.4, -0.5)


func _add_static(mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_world.add_child(mi)


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
	mat.albedo_color = Color(1, 1, 1, 0.045)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = mat
	_world.add_child(mi)


# ---------------------------------------------------------------- overlay (2D on top of 3D)

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

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

	var help := Label.new()
	help.text = "Right drag orbit · Middle drag pan · Wheel zoom · F frame"
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
	sub.text = "Drag a fixture from the library onto the floor where its light should land."
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
			v.setup(fx, ctx)
			_visuals[fx] = v
	_empty_hint.visible = live.is_empty()


func _on_selection_changed(fx: DMXFixture) -> void:
	for key: DMXFixture in _visuals:
		(_visuals[key] as StageFixture3D).set_selected(key == fx)


# ---------------------------------------------------------------- drag and drop from the library

func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).get("kind") == "fixture"


func _drop_data(at: Vector2, data: Variant) -> void:
	var entry: FixtureCatalog.Entry = (data as Dictionary)["entry"]
	var hit: Variant = _floor_point(at)
	ctx.add_fixture(entry, hit if hit != null else Vector3.ZERO)


## Where a screen point hits the floor, or null if it misses (looking at the sky).
func _floor_point(at: Vector2) -> Variant:
	var origin := _camera.project_ray_origin(at)
	var dir := _camera.project_ray_normal(at)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
	if hit == null:
		return null
	# Keep fixtures inside the room (grid is 16 x 12 m, back wall at z = -6).
	var p: Vector3 = hit
	return Vector3(clampf(p.x, -7.5, 7.5), 0.0, clampf(p.z, -5.0, 5.5))


func _pick(at: Vector2) -> DMXFixture:
	var best: DMXFixture = null
	var best_d := PICK_RADIUS_PX
	for fx: DMXFixture in _visuals:
		var v: StageFixture3D = _visuals[fx]
		if _camera.is_position_behind(v.global_position):
			continue
		var d := _camera.unproject_position(v.global_position).distance_to(at)
		if d < best_d:
			best_d = d
			best = fx
	return best


# ---------------------------------------------------------------- camera input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed and mb.alt_pressed:
					_orbiting = true
				elif mb.pressed:
					var fx := _pick(mb.position)
					ctx.select(fx)
					_dragging = fx
					_drag_moved = false
				else:
					_orbiting = false
					_dragging = null
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
		elif _dragging:
			var hit: Variant = _floor_point(mm.position)
			if hit != null:
				ctx.move_fixture(_dragging, hit)
				(_visuals[_dragging] as StageFixture3D).sync_position()
				_drag_moved = true
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_F:
			_pivot.position = Vector3(0, 1.4, -0.5)
			_distance = 12.5
			_update_camera()
			accept_event()
		elif k.pressed and not k.echo and k.keycode == KEY_DELETE and ctx.selected:
			ctx.remove_fixture(ctx.selected)
			accept_event()


func _update_camera() -> void:
	_pivot.rotation_degrees = Vector3(_pitch, _yaw, 0)
	_camera.position = Vector3(0, 0, _distance)
	_camera.rotation = Vector3.ZERO
