class_name StageSet
extends RefCounted
## Set dressing for the stage view: box truss with towers, side walls and the
## DJ gear on the booth. Pure decoration with no snapping or picking; the
## surfaces fixtures stick to live in StageRoom.

const CHORD_RADIUS := 0.024
const LACE_RADIUS := 0.011
const TOWER_X := 4.65


## Adds everything under `parent`.
static func build(parent: Node3D) -> void:
	var alu := StandardMaterial3D.new()
	alu.albedo_color = Color("9aa0a8")
	alu.metallic = 0.95
	alu.roughness = 0.28
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := StageRoom.TRUSS_SIZE
	var half_len := StageRoom.TRUSS_LENGTH * 0.5
	for z in StageRoom.TRUSS_Z:
		var y := StageRoom.TRUSS_Y
		_box_truss(st, Vector3(-half_len, y, z), Vector3(half_len, y, z), s, Vector3.UP)
		# Towers at both ends, down to base plates on the floor.
		for x: float in [-TOWER_X, TOWER_X]:
			_box_truss(st, Vector3(x, 0.02, z), Vector3(x, y - s * 0.5, z), s, Vector3.BACK)
			_add_box(parent, Vector3(0.6, 0.02, 0.6), Vector3(x, 0.01, z), alu)
			_add_box(parent, Vector3(s + 0.02, s + 0.02, s + 0.02), Vector3(x, y, z), alu) # corner block
	# One baked mesh for all of it: a few thousand triangles, a single draw call.
	var truss := MeshInstance3D.new()
	truss.mesh = st.commit()
	truss.material_override = alu
	parent.add_child(truss)

	_side_walls(parent)
	_booth_gear(parent)


## A square box truss from `a` to `b`: four chords at the corners and zig-zag
## lacing on each face.
static func _box_truss(st: SurfaceTool, a: Vector3, b: Vector3, size: float, up_hint: Vector3) -> void:
	var axis := (b - a).normalized()
	var length := a.distance_to(b)
	var u := up_hint - axis * up_hint.dot(axis)
	u = u.normalized()
	var v := axis.cross(u).normalized()
	var h := size * 0.5 - CHORD_RADIUS
	var corners: Array[Vector3] = [u * h + v * h, u * h - v * h, -u * h - v * h, -u * h + v * h]
	for c in corners:
		_tube(st, a + c, b + c, CHORD_RADIUS)
	var steps := maxi(1, int(round(length / size)))
	var step := length / steps
	for face in 4:
		var c0: Vector3 = corners[face]
		var c1: Vector3 = corners[(face + 1) % 4]
		for i in steps:
			var p0 := a + axis * (i * step)
			var p1 := a + axis * ((i + 1) * step)
			if i % 2 == 0:
				_tube(st, p0 + c0, p1 + c1, LACE_RADIUS)
			else:
				_tube(st, p0 + c1, p1 + c0, LACE_RADIUS)


## An open 8-sided tube from p to q with smooth normals.
static func _tube(st: SurfaceTool, p: Vector3, q: Vector3, r: float) -> void:
	const SIDES := 8
	var y := (q - p).normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	for i in SIDES:
		var a0 := TAU * i / SIDES
		var a1 := TAU * (i + 1) / SIDES
		var n0 := x * cos(a0) + z * sin(a0)
		var n1 := x * cos(a1) + z * sin(a1)
		for vtx: Array in [[n0, p], [n1, p], [n1, q], [n0, p], [n1, q], [n0, q]]:
			var n: Vector3 = vtx[0]
			st.set_normal(n)
			st.add_vertex((vtx[1] as Vector3) + n * r)


## Inward-facing planes: they catch spill from the rig, but you can see
## straight through them when the camera orbits outside the room.
static func _side_walls(parent: Node3D) -> void:
	var mat := StageRoom.wall_material()
	for side: float in [-1.0, 1.0]:
		var q := QuadMesh.new()
		q.size = Vector2(12.0, 6.0)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = mat
		mi.position = Vector3(8.0 * side, 3.0, 0.0)
		mi.rotation_degrees.y = -90.0 * side # the quad's front (+Z) faces into the room
		parent.add_child(mi)


## Two players and a mixer on the booth, with glowing screens and a light
## strip along the front of the booth.
static func _booth_gear(parent: Node3D) -> void:
	var gear := StandardMaterial3D.new()
	gear.albedo_color = Color("101114")
	gear.roughness = 0.35
	gear.metallic = 0.4
	var screen := StandardMaterial3D.new()
	screen.albedo_color = Color.BLACK
	screen.emission_enabled = true
	screen.emission = Color("4f8dff")
	screen.emission_energy_multiplier = 1.6
	var pad := StandardMaterial3D.new()
	pad.albedo_color = Color.BLACK
	pad.emission_enabled = true
	pad.emission = Color("ff3b6b")
	pad.emission_energy_multiplier = 2.0
	var top := 1.06
	for x: float in [-0.52, 0.52]:
		_add_box(parent, Vector3(0.36, 0.06, 0.4), Vector3(x, top + 0.03, -2.6), gear)
		_add_box(parent, Vector3(0.16, 0.012, 0.09), Vector3(x, top + 0.066, -2.74), screen)
		var jog := CylinderMesh.new()
		jog.top_radius = 0.1
		jog.bottom_radius = 0.1
		jog.height = 0.015
		_add_mesh(parent, jog, Vector3(x, top + 0.067, -2.55), gear)
		for i in 4:
			_add_box(parent, Vector3(0.05, 0.008, 0.03), Vector3(x - 0.11 + i * 0.075, top + 0.064, -2.44), pad)
	_add_box(parent, Vector3(0.3, 0.07, 0.38), Vector3(0, top + 0.035, -2.6), gear)
	_add_box(parent, Vector3(0.2, 0.01, 0.05), Vector3(0, top + 0.075, -2.72), screen)

	var strip := StandardMaterial3D.new()
	strip.albedo_color = Color.BLACK
	strip.emission_enabled = true
	strip.emission = Color("ffb547")
	strip.emission_energy_multiplier = 2.5
	_add_box(parent, Vector3(1.96, 0.012, 0.012), Vector3(0, 0.96, -2.2 + 0.006), strip) # under the lip of the booth top


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var b := BoxMesh.new()
	b.size = size
	_add_mesh(parent, b, pos, mat)


static func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
