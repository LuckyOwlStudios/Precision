@tool
class_name TrussLattice
extends MeshInstance3D
## The box truss rig over the stage: one straight run per entry in `rows`
## (at StageRoom.TRUSS_Y) with a tower at each end down to the floor.
## The lattice of tubes is too fiddly to place by hand, so this node builds
## its mesh from the settings below, in the editor too. The mesh is not
## saved into the scene; change the settings and it rebuilds.
## Snapping uses the hidden StageSurface boxes next to this node in
## stage_room.tscn, so move those too if you move a truss.

const CHORD_RADIUS := 0.024
const LACE_RADIUS := 0.011

## Z position of each truss run.
@export var rows: Array[float] = [0.5, -0.8]:
	set(v):
		rows = v
		_rebuild()
@export var height := StageRoom.TRUSS_Y:
	set(v):
		height = v
		_rebuild()
@export var length := StageRoom.TRUSS_LENGTH:
	set(v):
		length = v
		_rebuild()
## X position of the towers (both sides).
@export var tower_x := 4.65:
	set(v):
		tower_x = v
		_rebuild()
@export var size := StageRoom.TRUSS_SIZE:
	set(v):
		size = v
		_rebuild()


func _ready() -> void:
	_rebuild()


func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage &= ~PROPERTY_USAGE_STORAGE # built here, never saved


func _rebuild() -> void:
	if not is_inside_tree():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_len := length * 0.5
	for z in rows:
		_box_truss(st, Vector3(-half_len, height, z), Vector3(half_len, height, z), Vector3.UP)
		for x: float in [-tower_x, tower_x]:
			_box_truss(st, Vector3(x, 0.02, z), Vector3(x, height - size * 0.5, z), Vector3.BACK)
	# One baked mesh for all of it: a few thousand triangles, a single draw call.
	mesh = st.commit()


## A square box truss from `a` to `b`: four chords at the corners and zig-zag
## lacing on each face.
func _box_truss(st: SurfaceTool, a: Vector3, b: Vector3, up_hint: Vector3) -> void:
	var axis := (b - a).normalized()
	var run := a.distance_to(b)
	var u := up_hint - axis * up_hint.dot(axis)
	u = u.normalized()
	var v := axis.cross(u).normalized()
	var h := size * 0.5 - CHORD_RADIUS
	var corners: Array[Vector3] = [u * h + v * h, u * h - v * h, -u * h - v * h, -u * h + v * h]
	for c in corners:
		_tube(st, a + c, b + c, CHORD_RADIUS)
	var steps := maxi(1, int(round(run / size)))
	var step := run / steps
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
