class_name StageFixture3D
extends Node3D
## The 3D look of one DMXFixture: a body, glowing lenses with a halo, a beam
## cone and real lights (SpotLight3D for pars and moving heads, AreaLight3D for
## bars and strobes), all following the fixture's colour, dimmer, strobe, pan
## and tilt.
## Pure visuals: it reads the fixture and never writes DMX.
##
## Each body is a scene in ui/stage/fixtures/ (par, spot mover, wash mover,
## bar, strobe), so you can open one and reshape it in the editor. The scene
## needs a Yoke (turns with pan) holding a Head (turns with tilt, beam down its
## -Y) with the lights inside it, and a Marker for the selection brackets.
## The lens, halo, beam and marker materials are "local to scene", so every
## fixture on stage gets its own copies to colour.
## Its MountPoint nodes are the truss clamps: they say where the fixture grips
## a tube when hung, and show only while it is (see set_rigged). How many
## clamps it has also decides which ways it can be turned on stage (see
## MountRotation); "Rotating on stage" below overrides that per scene.

const MOUNT_HEIGHT := 3.4 ## default hanging height when placed without snapping
const BAR_PIXELS := 8

## Body scenes (loaded, not preloaded: they use this script themselves).
const SCENES := {
	FixtureCatalog.Body.PAR: "res://ui/stage/fixtures/par.tscn",
	FixtureCatalog.Body.BAR: "res://ui/stage/fixtures/bar.tscn",
	FixtureCatalog.Body.STROBE: "res://ui/stage/fixtures/strobe.tscn",
}
const SPOT_MOVER_SCENE := "res://ui/stage/fixtures/spot_mover.tscn"
const WASH_MOVER_SCENE := "res://ui/stage/fixtures/wash_mover.tscn"

static var _iris: Texture2D

@export var body: FixtureCatalog.Body = FixtureCatalog.Body.PAR
@export var lens_material: StandardMaterial3D ## glass that glows in the fixture's colour
@export var glow_material: ShaderMaterial ## halo around each lit lens
@export var beam_material: ShaderMaterial ## the beam cone
@export var marker_material: ShaderMaterial ## selection brackets

@export_group("Rotating on stage")
## Swing around the truss tube it hangs from. Auto: yes, if it has clamps.
@export var swing_on_truss: MountRotation.Allow = MountRotation.Allow.AUTO
## Turn under its clamp, on the clamp's bolt. Auto: only with a single clamp
## (and that clamp's MountPoint has `swivel` on); two clamps lock it.
@export var spin_on_clamp: MountRotation.Allow = MountRotation.Allow.AUTO
## Turn about the floor or wall it stands on (feet stay planted). Auto: yes.
@export var spin_on_surface: MountRotation.Allow = MountRotation.Allow.AUTO
## Tilt on a stand, around its own long axis (a light bar's U-bracket and
## knobs). Not DMX tilt: this is how the stand is set. Auto: no.
@export var tilt_on_stand: MountRotation.Allow = MountRotation.Allow.AUTO
@export_group("")

var fixture: DMXFixture
var ctx: StudioContext
var look: StageLook ## haze and quality; null renders with defaults

var _lights: Array[Light3D] = []
var _beam_strength := 1.0
var _marker_tween: Tween
var _selected := false
static var _body_boxes: Dictionary = {} ## scene path -> AABB, see body_box_of

@onready var _yoke: Node3D = %Yoke ## rotates with pan
@onready var _head: Node3D = %Head ## rotates with tilt; the beam points down its -Y
@onready var _marker: MeshInstance3D = %Marker ## camera-facing corner brackets while selected


## The visual for a fixture, not yet set up: the scene for its body.
static func create(p_fixture: DMXFixture) -> StageFixture3D:
	return (load(scene_path_of(p_fixture)) as PackedScene).instantiate()


## The body scene for a kind of fixture. `profile_label` tells spot movers from washes.
static func scene_path(p_body: FixtureCatalog.Body, profile_label: String) -> String:
	if p_body == FixtureCatalog.Body.MOVING_HEAD:
		return WASH_MOVER_SCENE if profile_label.to_lower().contains("wash") else SPOT_MOVER_SCENE
	return SCENES.get(p_body, SCENES[FixtureCatalog.Body.PAR])


static func scene_path_of(fx: DMXFixture) -> String:
	return scene_path(fx.get_meta(StudioContext.META_BODY, FixtureCatalog.Body.PAR),
		String(fx.get_meta(StudioContext.META_PROFILE_LABEL, "")))


## Where a body scene's clamps grip the tube, in the fixture's own space: one
## position per MountPoint. Read from the scene once and remembered.
static func mounts_of(path: String) -> PackedVector3Array:
	return MountRotation.rules_of(path).mounts


## The box round a body scene's solid parts (shell, yoke, clamps; not beams,
## glows, markers or a floor stand), in the fixture's own space. Read from the
## scene once and remembered. Used to keep fixtures on one tube from overlapping.
static func body_box_of(path: String) -> AABB:
	if _body_boxes.has(path):
		return _body_boxes[path]
	var box := AABB()
	var first := true
	var root := (load(path) as PackedScene).instantiate() as Node3D
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not _solid_part(mi, root):
			continue
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p and p != root:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b := xf * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	root.free()
	_body_boxes[path] = box
	return box


static func _solid_part(n: Node, root: Node) -> bool:
	var p: Node = n
	while p and p != root:
		if p is Node3D and not (p as Node3D).visible:
			return false
		if p.is_in_group(StagePick.NO_PICK_GROUP) or String(p.name) == "Stand":
			return false
		for prefix in StagePick.SKIP_PREFIXES:
			if String(p.name).begins_with(prefix):
				return false
		p = p.get_parent()
	return true


## Show the clamps (and brackets under them) while the fixture hangs on a
## truss; hide them while it stands on the floor, a wall or the booth.
## `pipe` is the tube it hangs from, or null. Each clamp's jaw is turned to
## run along the tube, so a fixture spun under a single clamp still shows the
## clamp gripping the tube properly.
func set_rigged(pipe: StageRoom.Pipe, stand_tilt := 0.0) -> void:
	# A stand (if the scene has one) shows when not hung, and stays flat on
	# the floor while the fixture tilts on it.
	var stand := get_node_or_null("Stand") as Node3D
	if stand:
		stand.visible = pipe == null
		stand.transform = Transform3D(Basis(Vector3.RIGHT, -stand_tilt), Vector3.ZERO)
	for n in find_children("*", "", true, false):
		if n is MountPoint:
			var mp := n as MountPoint
			mp.visible = pipe != null
			if pipe == null:
				mp.jaw_turn = 0.0
				continue
			# The tube's direction in the clamp's own space, flattened onto its
			# XZ plane: the jaw turns about the bolt (local Y) to line up with it.
			var a := mp.global_basis.orthonormalized().inverse() * pipe.axis()
			var turn := atan2(-a.z, a.x)
			# The jaw looks the same half a turn round, so take the smaller turn.
			if turn > PI * 0.5:
				turn -= PI
			elif turn < -PI * 0.5:
				turn += PI
			mp.jaw_turn = turn


## Call once it is in the tree.
func setup(p_fixture: DMXFixture, p_ctx: StudioContext, p_look: StageLook = null) -> void:
	fixture = p_fixture
	ctx = p_ctx
	look = p_look
	name = "Visual_" + fixture.name
	for n in _head.find_children("*", "", true, false):
		if n is Light3D:
			_lights.append(n)
	if is_spot_mover():
		# A spot mover's iris gives a crisp round edge, unlike a soft par wash.
		for l in _lights:
			(l as SpotLight3D).light_projector = _iris_texture()
	_apply_look()
	if look:
		look.changed.connect(_apply_look)
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
	if on == _selected:
		return # already showing (or hiding): don't restart the brackets' animation
	_selected = on
	if _marker_tween:
		_marker_tween.kill()
	if on:
		_marker.visible = true
		marker_material.set_shader_parameter("appear", 0.0)
	_marker_tween = create_tween()
	_marker_tween.tween_method(func(v: float) -> void: marker_material.set_shader_parameter("appear", v),
		float(marker_material.get_shader_parameter("appear")), 1.0 if on else 0.0, 0.16 if on else 0.1) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not on:
		_marker_tween.tween_callback(func() -> void: _marker.visible = false)


## Quality or haze changed: shadows, fog contribution and beam strength.
func _apply_look() -> void:
	var shadows := false
	var fog := 1.0
	var soft := 0.0
	if look:
		shadows = look.mover_shadows() if body == FixtureCatalog.Body.MOVING_HEAD else look.wash_shadows()
		fog = 1.0 if look.volumetric() else 0.0
		soft = 0.04 if look.quality == StageLook.Quality.ULTRA else 0.0
		beam_material.set_shader_parameter("haze_texture", lerpf(0.15, 0.5, look.haze))
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


## Spot movers (narrow, hard edged) versus wash movers (wide, soft).
func is_spot_mover() -> bool:
	return body == FixtureCatalog.Body.MOVING_HEAD and is_spot_profile(fixture)


static func is_spot_profile(fx: DMXFixture) -> bool:
	return not String(fx.get_meta(StudioContext.META_PROFILE_LABEL, "")).to_lower().contains("wash")


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


func _process(_delta: float) -> void:
	if fixture == null or not is_instance_valid(fixture):
		return
	# out() = what is being sent, including effects running on the timeline.
	var level := 0.0 if (ctx and ctx.blackout) else float(fixture.out("dimmer"))
	level *= _strobe_gate()
	var c: Color = fixture.out("color")
	var wh := float(fixture.out("white"))
	var am := float(fixture.out("amber"))
	# Add white/amber channels on top of RGB so RGBW fixtures preview sensibly.
	c = Color(
		minf(c.r + wh + am, 1.0),
		minf(c.g + wh + am * 0.6, 1.0),
		minf(c.b + wh + float(fixture.out("uv")) * 0.5, 1.0))
	if body == FixtureCatalog.Body.STROBE:
		c = Color.WHITE

	beam_material.set_shader_parameter("beam_color", c)
	beam_material.set_shader_parameter("intensity", _beam_intensity() * level * _beam_strength)
	lens_material.emission = c
	lens_material.emission_energy_multiplier = 7.0 * level
	glow_material.set_shader_parameter("glow_color", c)
	glow_material.set_shader_parameter("intensity", 0.9 * level)
	glow_material.set_shader_parameter("beam_dir", -_head.global_basis.y)
	var energy := _light_energy() * level
	for l in _lights:
		l.light_color = c
		l.light_energy = energy
		l.visible = level > 0.01

	if body == FixtureCatalog.Body.MOVING_HEAD:
		_yoke.rotation_degrees.y = (float(fixture.out("pan")) - 0.5) * fixture.profile.pan_range_deg
		_head.rotation_degrees.x = -(float(fixture.out("tilt")) - 0.5) * fixture.profile.tilt_range_deg


## The strobe channel as a flash pattern: 0-9 open, then 1 to 20 flashes a second.
func _strobe_gate() -> float:
	var strobe := int(fixture.out("strobe"))
	if strobe < 10:
		return 1.0
	var hz := lerpf(1.0, 20.0, (strobe - 10) / 245.0)
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
