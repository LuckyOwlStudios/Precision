class_name StageFixture3D
extends Node3D
## The 3D look of one DMXFixture: a body, a glowing lens, a beam cone and a
## spot light, all following the fixture's colour, dimmer, pan and tilt.
## Pure visuals: it reads the fixture and never writes DMX.

const MOUNT_HEIGHT := 3.4 ## default hanging height when placed without snapping
const BEAM_LENGTH := 6.0
const PAN_RANGE_DEG := 540.0
const TILT_RANGE_DEG := 270.0
const PAR_AIM_DEG := -18.0 ## pars lean slightly towards the audience

const BEAM_SHADER := preload("res://ui/stage/beam.gdshader")

var fixture: DMXFixture
var ctx: StudioContext
var body: FixtureCatalog.Body = FixtureCatalog.Body.PAR

var _yoke := Node3D.new()   ## rotates with pan
var _head := Node3D.new()   ## rotates with tilt; the beam points down its -Y
var _beam_mat := ShaderMaterial.new()
var _lens_mat := StandardMaterial3D.new()
var _light := SpotLight3D.new()
var _ring := MeshInstance3D.new()


func setup(p_fixture: DMXFixture, p_ctx: StudioContext) -> void:
	fixture = p_fixture
	ctx = p_ctx
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
	_ring.visible = on


func _build() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color("4a4e56")
	metal.metallic = 0.6
	metal.roughness = 0.45

	add_child(_yoke)
	_yoke.add_child(_head)

	var beam_angle := 14.0
	match body:
		FixtureCatalog.Body.PAR:
			_head.rotation_degrees.x = PAR_AIM_DEG
			_add_mesh(_head, _cylinder(0.15, 0.13, 0.28), metal, Vector3(0, 0.02, 0))
			_add_bracket(metal)
			beam_angle = 16.0
		FixtureCatalog.Body.MOVING_HEAD:
			_add_mesh(self, _box(Vector3(0.36, 0.14, 0.3)), metal, Vector3(0, 0.12, 0))
			_add_mesh(_yoke, _box(Vector3(0.05, 0.3, 0.12)), metal, Vector3(-0.19, -0.08, 0))
			_add_mesh(_yoke, _box(Vector3(0.05, 0.3, 0.12)), metal, Vector3(0.19, -0.08, 0))
			_yoke.position.y = 0.0
			_head.position.y = -0.18
			_add_mesh(_head, _cylinder(0.12, 0.14, 0.32), metal, Vector3(0, 0.0, 0))
			beam_angle = 9.0
		FixtureCatalog.Body.BAR:
			_head.rotation_degrees.x = PAR_AIM_DEG
			_add_mesh(_head, _box(Vector3(1.0, 0.1, 0.12)), metal, Vector3.ZERO)
			beam_angle = 30.0
		FixtureCatalog.Body.STROBE:
			_head.rotation_degrees.x = PAR_AIM_DEG - 20.0
			_add_mesh(_head, _box(Vector3(0.45, 0.12, 0.2)), metal, Vector3.ZERO)
			beam_angle = 45.0

	# Lens: a flat disc that glows in the fixture's colour.
	_lens_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var lens := _cylinder(0.11 if body != FixtureCatalog.Body.BAR else 0.05, 0.11 if body != FixtureCatalog.Body.BAR else 0.05, 0.01)
	var lens_y := -0.13 if body == FixtureCatalog.Body.PAR else -0.17 if body == FixtureCatalog.Body.MOVING_HEAD else -0.06
	if body == FixtureCatalog.Body.BAR:
		for i in 6:
			_add_mesh(_head, lens, _lens_mat, Vector3(-0.4 + i * 0.16, lens_y, 0))
	else:
		_add_mesh(_head, lens, _lens_mat, Vector3(0, lens_y, 0))

	# Beam cone, hanging from the lens.
	var far_radius := tan(deg_to_rad(beam_angle)) * BEAM_LENGTH
	var cone := _cylinder(0.08 if body != FixtureCatalog.Body.BAR else 0.4, far_radius, BEAM_LENGTH)
	cone.radial_segments = 32
	cone.rings = 1
	_beam_mat.shader = BEAM_SHADER
	_beam_mat.set_shader_parameter("beam_length", BEAM_LENGTH)
	var beam := MeshInstance3D.new()
	beam.mesh = cone
	beam.material_override = _beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = lens_y - BEAM_LENGTH * 0.5
	_head.add_child(beam)

	# Real light so the floor and the booth get a pool of colour.
	_light.rotation_degrees.x = -90.0 # SpotLight3D shines down -Z; turn it to -Y
	_light.position.y = lens_y
	_light.spot_angle = beam_angle * 1.15
	_light.spot_range = 12.0
	_light.spot_attenuation = 0.6
	_light.shadow_enabled = false
	_head.add_child(_light)

	# Amber ring shown while selected.
	var torus := TorusMesh.new()
	torus.inner_radius = 0.3
	torus.outer_radius = 0.36
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = UIPalette.ACCENT
	_ring.mesh = torus
	_ring.material_override = ring_mat
	_ring.position.y = -0.05
	_ring.rotation_degrees.x = 90.0 # stand it up so it faces the audience/camera
	_ring.visible = false
	add_child(_ring)


func _add_bracket(mat: Material) -> void:
	_add_mesh(self, _box(Vector3(0.36, 0.03, 0.05)), mat, Vector3(0, 0.2, 0))


func _process(_delta: float) -> void:
	if fixture == null or not is_instance_valid(fixture):
		return
	var level := 0.0 if (ctx and ctx.blackout) else fixture.dimmer
	var c := fixture.color
	# Add white/amber channels on top of RGB so RGBW fixtures preview sensibly.
	c = Color(
		minf(c.r + fixture.white + fixture.amber, 1.0),
		minf(c.g + fixture.white + fixture.amber * 0.6, 1.0),
		minf(c.b + fixture.white + fixture.uv * 0.5, 1.0))
	if body == FixtureCatalog.Body.STROBE:
		c = Color.WHITE

	_beam_mat.set_shader_parameter("beam_color", c)
	_beam_mat.set_shader_parameter("intensity", 0.5 * level)
	_lens_mat.albedo_color = Color(0.08, 0.08, 0.09).lerp(c, clampf(level * 1.2, 0.0, 1.0))
	_light.light_color = c
	_light.light_energy = 6.0 * level
	_light.visible = level > 0.01

	if body == FixtureCatalog.Body.MOVING_HEAD:
		_yoke.rotation_degrees.y = (fixture.pan - 0.5) * PAN_RANGE_DEG
		_head.rotation_degrees.x = -(fixture.tilt - 0.5) * TILT_RANGE_DEG


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
