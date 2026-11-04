class_name StageFixture3D
extends Node3D
## The 3D look of one DMXFixture: a body, glowing lenses with a halo, a beam
## cone and real lights (SpotLight3D for pars and moving heads, AreaLight3D for
## bars and strobes), all following the fixture's colour, dimmer, strobe, pan
## and tilt.
## Pure visuals: it reads the fixture and never writes DMX.

const MOUNT_HEIGHT := 3.4 ## default hanging height when placed without snapping
const BAR_PIXELS := 8
const PAN_RANGE_DEG := 540.0
const TILT_RANGE_DEG := 270.0
const PAR_AIM_DEG := -18.0 ## pars lean slightly towards the audience

const BEAM_SHADER := preload("res://ui/stage/beam.gdshader")
const MARKER_SHADER := preload("res://ui/stage/marker.gdshader")
const GLOW_SHADER := preload("res://ui/stage/lens_glow.gdshader")

static var _iris: Texture2D

var fixture: DMXFixture
var ctx: StudioContext
var look: StageLook ## haze and quality; null renders with defaults
var body: FixtureCatalog.Body = FixtureCatalog.Body.PAR

var _yoke := Node3D.new()   ## rotates with pan
var _head := Node3D.new()   ## rotates with tilt; the beam points down its -Y
var _beam_mat := ShaderMaterial.new()
var _lens_mat := StandardMaterial3D.new()
var _glow_mat := ShaderMaterial.new()
var _lights: Array[Light3D] = []
var _beam_strength := 1.0
var _marker := MeshInstance3D.new() ## camera-facing corner brackets while selected
var _marker_mat := ShaderMaterial.new()
var _marker_tween: Tween


func setup(p_fixture: DMXFixture, p_ctx: StudioContext, p_look: StageLook = null) -> void:
	fixture = p_fixture
	ctx = p_ctx
	look = p_look
	body = fixture.get_meta(StudioContext.META_BODY, FixtureCatalog.Body.PAR)
	name = "Visual_" + fixture.name
	_build()
	sync_position()


func sync_position() -> void:
	transform = StudioContext.fixture_transform(fixture)


## Distance from the fixture's origin to its mounting face (bracket or top of
## the base), along local +Y. Placing puts that face flush on the surface.
static func mount_offset(p_body: FixtureCatalog.Body) -> float:
	match p_body:
		FixtureCatalog.Body.PAR:
			return 0.215
		FixtureCatalog.Body.MOVING_HEAD:
			return 0.19
		FixtureCatalog.Body.BAR:
			return 0.07
		FixtureCatalog.Body.STROBE:
			return 0.11
	return 0.1


## Middle of the body in world space: what you click on, and where the gizmo sits.
func center() -> Vector3:
	return to_global(Vector3(0, -0.08, 0))


func set_selected(on: bool) -> void:
	if _marker_tween:
		_marker_tween.kill()
	if on:
		_marker.visible = true
		_marker_mat.set_shader_parameter("appear", 0.0)
	_marker_tween = create_tween()
	_marker_tween.tween_method(func(v: float) -> void: _marker_mat.set_shader_parameter("appear", v),
		float(_marker_mat.get_shader_parameter("appear")), 1.0 if on else 0.0, 0.16 if on else 0.1) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not on:
		_marker_tween.tween_callback(func() -> void: _marker.visible = false)


func _build() -> void:
	# Real fixtures are black powder-coated aluminium.
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color("16181c")
	shell.metallic = 0.35
	shell.roughness = 0.42
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color("2b2f36")
	trim.metallic = 0.8
	trim.roughness = 0.3

	add_child(_yoke)
	_yoke.add_child(_head)

	var lens_r := 0.11
	match body:
		FixtureCatalog.Body.PAR:
			_head.rotation_degrees.x = PAR_AIM_DEG
			_add_mesh(_head, _cylinder(0.15, 0.13, 0.28), shell, Vector3(0, 0.02, 0))
			_add_mesh(_head, _cylinder(0.135, 0.135, 0.03), trim, Vector3(0, -0.12, 0)) # bezel
			_add_mesh(_head, _cylinder(0.1, 0.12, 0.04), trim, Vector3(0, 0.18, 0))    # rear cap
			_add_bracket(trim)
		FixtureCatalog.Body.MOVING_HEAD:
			_add_mesh(self, _box(Vector3(0.36, 0.14, 0.3)), shell, Vector3(0, 0.12, 0))
			_add_mesh(self, _box(Vector3(0.12, 0.012, 0.06)), _display_mat(), Vector3(0, 0.12, 0.151)) # menu display
			_add_mesh(_yoke, _box(Vector3(0.05, 0.3, 0.12)), shell, Vector3(-0.19, -0.08, 0))
			_add_mesh(_yoke, _box(Vector3(0.05, 0.3, 0.12)), shell, Vector3(0.19, -0.08, 0))
			_add_mesh(_yoke, _box(Vector3(0.43, 0.04, 0.14)), shell, Vector3(0, 0.05, 0))
			_head.position.y = -0.18
			_add_mesh(_head, _cylinder(0.12, 0.14, 0.32), shell, Vector3(0, 0.0, 0))
			_add_mesh(_head, _cylinder(0.145, 0.145, 0.03), trim, Vector3(0, -0.155, 0))
		FixtureCatalog.Body.BAR:
			_head.rotation_degrees.x = PAR_AIM_DEG
			_add_mesh(_head, _box(Vector3(1.0, 0.1, 0.12)), shell, Vector3.ZERO)
			_add_mesh(_head, _box(Vector3(1.04, 0.03, 0.14)), trim, Vector3(0, -0.04, 0))
			lens_r = 0.05
		FixtureCatalog.Body.STROBE:
			_head.rotation_degrees.x = PAR_AIM_DEG - 20.0
			_add_mesh(_head, _box(Vector3(0.45, 0.12, 0.2)), shell, Vector3.ZERO)

	# Lenses: glass that glows in the fixture's colour (bright enough to bloom).
	_lens_mat.albedo_color = Color("07080a")
	_lens_mat.roughness = 0.08
	_lens_mat.metallic = 0.2
	_lens_mat.emission_enabled = true
	_lens_mat.emission = Color.BLACK
	var lens_y := lens_height(body)
	var lens_positions: Array[Vector3] = []
	if body == FixtureCatalog.Body.BAR:
		for i in BAR_PIXELS:
			lens_positions.append(Vector3(-0.42 + i * 0.84 / (BAR_PIXELS - 1), lens_y, 0))
		for p in lens_positions:
			_add_mesh(_head, _cylinder(lens_r, lens_r, 0.012), _lens_mat, p)
	elif body == FixtureCatalog.Body.STROBE:
		lens_positions.append(Vector3(0, lens_y, 0))
		_add_mesh(_head, _box(Vector3(0.38, 0.012, 0.13)), _lens_mat, lens_positions[0])
	else:
		lens_positions.append(Vector3(0, lens_y, 0))
		_add_mesh(_head, _cylinder(lens_r, lens_r, 0.012), _lens_mat, lens_positions[0])

	# Halo around each lit lens, for that "looking into the rig" glare.
	_glow_mat.shader = GLOW_SHADER
	_glow_mat.render_priority = 2
	var glow_quad := QuadMesh.new()
	glow_quad.size = Vector2(2, 2)
	var glow_size := 0.32 if body == FixtureCatalog.Body.BAR else 0.75 if body == FixtureCatalog.Body.STROBE else 0.6
	_glow_mat.set_shader_parameter("size", glow_size)
	for p in lens_positions:
		var g := MeshInstance3D.new()
		g.mesh = glow_quad
		g.material_override = _glow_mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.extra_cull_margin = 2.0
		g.position = p + Vector3(0, -0.01, 0)
		_head.add_child(g)

	# Beam cone, hanging from the lens.
	var beam_length := beam_length_for(body)
	var spread := beam_angle()
	var far_radius := tan(deg_to_rad(spread)) * beam_length
	var near_radius := 0.45 if body == FixtureCatalog.Body.BAR else 0.18 if body == FixtureCatalog.Body.STROBE else lens_r * 0.8
	var cone := _cylinder(near_radius, far_radius + near_radius, beam_length)
	cone.radial_segments = 48
	cone.rings = 6
	cone.cap_top = false
	cone.cap_bottom = false
	_beam_mat.shader = BEAM_SHADER
	_beam_mat.set_shader_parameter("beam_length", beam_length)
	_beam_mat.set_shader_parameter("edge_softness", 2.4 if body == FixtureCatalog.Body.MOVING_HEAD else 1.4)
	_beam_mat.render_priority = 1
	var beam := MeshInstance3D.new()
	beam.mesh = cone
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = lens_y - 0.01 - beam_length * 0.5
	_head.add_child(beam)

	_build_lights(lens_y, spread)
	_apply_look()
	if look:
		look.changed.connect(_apply_look)

	# Selection brackets: a billboard, so they always face the camera.
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	_marker_mat.shader = MARKER_SHADER
	_marker_mat.set_shader_parameter("color", UIPalette.ACCENT)
	_marker_mat.set_shader_parameter("style", 0)
	_marker_mat.set_shader_parameter("world_size", _marker_size())
	_marker_mat.set_shader_parameter("appear", 0.0)
	_marker_mat.render_priority = 10
	_marker.mesh = quad
	_marker.material_override = _marker_mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.extra_cull_margin = 4.0 # the shader grows the quad past its mesh bounds
	_marker.position = Vector3(0, -0.18 if body == FixtureCatalog.Body.MOVING_HEAD else -0.08, 0)
	_marker.visible = false
	add_child(_marker)


## The real lights. Every light is turned so its -Z shines down the head's -Y.
##   Pars and moving heads: one SpotLight3D.
##   Bars and strobes: an AreaLight3D the size of the LED face (Godot 4.7+),
##   or a row of wide spot lights on older Godot versions.
func _build_lights(lens_y: float, spread: float) -> void:
	var use_area := (body == FixtureCatalog.Body.BAR or body == FixtureCatalog.Body.STROBE) \
		and (look == null or look.has_area_lights) and ClassDB.class_exists("AreaLight3D")
	if use_area:
		var area: Light3D = ClassDB.instantiate("AreaLight3D")
		# After the -90° turn, the area's local Y runs along the head's Z (depth).
		area.set("area_size", Vector2(0.96, 0.06) if body == FixtureCatalog.Body.BAR else Vector2(0.38, 0.13))
		area.set("area_range", 9.0)
		area.set("area_attenuation", 1.0)
		_add_light(area, Vector3(0, lens_y - 0.012, 0))
		return
	if body == FixtureCatalog.Body.BAR:
		for i in 3:
			_add_light(_make_spot(spread * 1.6), Vector3(-0.3 + i * 0.3, lens_y - 0.012, 0))
		return
	var spot := _make_spot(spread)
	if is_spot_mover():
		# A spot mover's iris gives a crisp round edge, unlike a soft par wash.
		spot.light_projector = _iris_texture()
		spot.spot_angle_attenuation = 0.35
	_add_light(spot, Vector3(0, lens_y - 0.012, 0))


func _make_spot(spread: float) -> SpotLight3D:
	var spot := SpotLight3D.new()
	spot.spot_angle = minf(spread * 1.1, 80.0)
	spot.spot_range = 14.0
	spot.spot_attenuation = 0.8
	spot.spot_angle_attenuation = 1.4
	return spot


func _add_light(l: Light3D, pos: Vector3) -> void:
	l.rotation_degrees.x = -90.0 # lights shine down -Z; turn them to -Y
	l.position = pos
	l.shadow_enabled = false
	l.shadow_bias = 0.04
	l.shadow_normal_bias = 1.0
	l.light_specular = 0.6
	l.visible = false
	_head.add_child(l)
	_lights.append(l)


## Quality or haze changed: shadows, fog contribution and beam strength.
func _apply_look() -> void:
	var shadows := false
	var fog := 1.0
	var soft := 0.0
	if look:
		shadows = look.mover_shadows() if body == FixtureCatalog.Body.MOVING_HEAD else look.wash_shadows()
		fog = 1.0 if look.volumetric() else 0.0
		soft = 0.04 if look.quality == StageLook.Quality.ULTRA else 0.0
		_beam_mat.set_shader_parameter("haze_texture", lerpf(0.15, 0.5, look.haze))
		_beam_strength = look.beam_strength()
	for l in _lights:
		l.shadow_enabled = shadows
		l.light_volumetric_fog_energy = fog * _fog_energy()
		if not l.is_class("AreaLight3D"):
			l.set("light_size", soft)


func _fog_energy() -> float:
	match body:
		FixtureCatalog.Body.MOVING_HEAD:
			return 1.6
		FixtureCatalog.Body.BAR, FixtureCatalog.Body.STROBE:
			return 0.4
	return 0.9


## Spread from the beam's centre to its edge, in degrees.
func beam_angle() -> float:
	match body:
		FixtureCatalog.Body.MOVING_HEAD:
			return 6.0 if is_spot_mover() else 13.0
		FixtureCatalog.Body.BAR:
			return 28.0
		FixtureCatalog.Body.STROBE:
			return 40.0
	return 15.0


## Spot movers (narrow, hard edged) versus wash movers (wide, soft).
func is_spot_mover() -> bool:
	if body != FixtureCatalog.Body.MOVING_HEAD:
		return false
	return not String(fixture.get_meta(StudioContext.META_PROFILE_LABEL, "")).to_lower().contains("wash")


static func lens_height(p_body: FixtureCatalog.Body) -> float:
	match p_body:
		FixtureCatalog.Body.PAR:
			return -0.13
		FixtureCatalog.Body.MOVING_HEAD:
			return -0.17
	return -0.06


static func beam_length_for(p_body: FixtureCatalog.Body) -> float:
	match p_body:
		FixtureCatalog.Body.MOVING_HEAD:
			return 10.0
		FixtureCatalog.Body.BAR:
			return 4.5
		FixtureCatalog.Body.STROBE:
			return 3.5
	return 6.5


## A round iris with a slightly soft edge, used as the spot mover's projector.
static func _iris_texture() -> Texture2D:
	if _iris:
		return _iris
	const N := 128
	var img := Image.create(N, N, false, Image.FORMAT_L8)
	for y in N:
		for x in N:
			var r := Vector2(x + 0.5 - N * 0.5, y + 0.5 - N * 0.5).length() / (N * 0.5)
			var v := 1.0 - smoothstep(0.82, 0.96, r)
			v *= lerpf(1.0, 0.8, r * r) # hot centre
			img.set_pixel(x, y, Color(v, v, v))
	_iris = ImageTexture.create_from_image(img)
	return _iris


static func _display_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = Color("3d7bff")
	m.emission_energy_multiplier = 1.5
	return m


## Half-width of the selection frame, roughly the body's size.
func _marker_size() -> float:
	match body:
		FixtureCatalog.Body.BAR:
			return 0.62
		FixtureCatalog.Body.STROBE:
			return 0.32
		FixtureCatalog.Body.MOVING_HEAD:
			return 0.42
	return 0.26


func _add_bracket(mat: Material) -> void:
	_add_mesh(self, _box(Vector3(0.36, 0.03, 0.05)), mat, Vector3(0, 0.2, 0))


func _process(_delta: float) -> void:
	if fixture == null or not is_instance_valid(fixture):
		return
	var level := 0.0 if (ctx and ctx.blackout) else fixture.dimmer
	level *= _strobe_gate()
	var c := fixture.color
	# Add white/amber channels on top of RGB so RGBW fixtures preview sensibly.
	c = Color(
		minf(c.r + fixture.white + fixture.amber, 1.0),
		minf(c.g + fixture.white + fixture.amber * 0.6, 1.0),
		minf(c.b + fixture.white + fixture.uv * 0.5, 1.0))
	if body == FixtureCatalog.Body.STROBE:
		c = Color.WHITE

	_beam_mat.set_shader_parameter("beam_color", c)
	_beam_mat.set_shader_parameter("intensity", _beam_intensity() * level * _beam_strength)
	_lens_mat.emission = c
	_lens_mat.emission_energy_multiplier = 7.0 * level
	_glow_mat.set_shader_parameter("glow_color", c)
	_glow_mat.set_shader_parameter("intensity", 0.9 * level)
	_glow_mat.set_shader_parameter("beam_dir", -_head.global_basis.y)
	var energy := _light_energy() * level
	for l in _lights:
		l.light_color = c
		l.light_energy = energy
		l.visible = level > 0.01

	if body == FixtureCatalog.Body.MOVING_HEAD:
		_yoke.rotation_degrees.y = (fixture.pan - 0.5) * PAN_RANGE_DEG
		_head.rotation_degrees.x = -(fixture.tilt - 0.5) * TILT_RANGE_DEG


## The strobe channel as a flash pattern: 0-9 open, then 1 to 20 flashes a second.
func _strobe_gate() -> float:
	if fixture.strobe < 10:
		return 1.0
	var hz := lerpf(1.0, 20.0, (fixture.strobe - 10) / 245.0)
	return 1.0 if fmod(Time.get_ticks_msec() / 1000.0 * hz, 1.0) < 0.25 else 0.0


func _beam_intensity() -> float:
	match body:
		FixtureCatalog.Body.MOVING_HEAD:
			return 0.9 if is_spot_mover() else 0.55
		FixtureCatalog.Body.BAR:
			return 0.22
		FixtureCatalog.Body.STROBE:
			return 0.3
	return 0.42


func _light_energy() -> float:
	var area := not _lights.is_empty() and _lights[0].is_class("AreaLight3D")
	match body:
		FixtureCatalog.Body.MOVING_HEAD:
			return 60.0 if is_spot_mover() else 40.0
		FixtureCatalog.Body.BAR:
			return 14.0 if area else 4.0
		FixtureCatalog.Body.STROBE:
			return 30.0 if area else 30.0
	return 40.0


# ---------------------------------------------------------------- mesh helpers

static func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
