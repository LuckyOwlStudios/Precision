@tool
class_name TrussMesh
extends MeshInstance3D
## The lattice of tubes you see on a truss piece: four chords with zig-zag
## lacing for a straight run, or the twelve edges of a corner box. The tubes
## are too fiddly to place by hand, so the mesh is built from the settings
## below (in the editor too) and not saved into the scene.
## Fixtures clamp onto the TrussTube nodes next to this one, not onto the mesh,
## so keep those in step if you change the size.

enum Shape { STRAIGHT, CORNER }

const CHORD_RADIUS := MountPoint.TUBE_RADIUS
const LACE_RADIUS := 0.011

@export var shape: Shape = Shape.STRAIGHT:
	set(v):
		shape = v
		_rebuild()
## Length of a straight run along local X, centred on the origin.
@export_range(0.1, 10.0, 0.01, "suffix:m") var length := 1.0:
	set(v):
		length = v
		_rebuild()
## Outside width of the square truss (29 cm is the common size).
@export_range(0.1, 1.0, 0.01, "suffix:m") var size := 0.29:
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
	if shape == Shape.STRAIGHT:
		_box_truss(st, Vector3(-length * 0.5, 0, 0), Vector3(length * 0.5, 0, 0), Vector3.UP)
	else:
		_corner(st)
	mesh = st.commit()


## A square box truss from `a` to `b`: four chords at the corners and zig-zag
## lacing on each face.
func _box_truss(st: SurfaceTool, a: Vector3, b: Vector3, up_hint: Vector3) -> void:
	var axis := (b - a).normalized()
	var run := a.distance_to(b)
	var u := (up_hint - axis * up_hint.dot(axis)).normalized()
	var v := axis.cross(u).normalized()
	var h := size * 0.5 - CHORD_RADIUS
	var corners: Array[Vector3] = [u * h + v * h, u * h - v * h, -u * h - v * h, -u * h + v * h]
	for c in corners:
		tube(st, a + c, b + c, CHORD_RADIUS)
	var steps := maxi(1, int(round(run / size)))
	var step := run / steps
	for face in 4:
		var c0: Vector3 = corners[face]
		var c1: Vector3 = corners[(face + 1) % 4]
		for i in steps:
			var p0 := a + axis * (i * step)
			var p1 := a + axis * ((i + 1) * step)
			if i % 2 == 0:
				tube(st, p0 + c0, p1 + c1, LACE_RADIUS)
			else:
				tube(st, p0 + c1, p1 + c0, LACE_RADIUS)


## A corner box: the twelve edges of a cube plus a diagonal on each face.
func _corner(st: SurfaceTool) -> void:
	var h := size * 0.5 - CHORD_RADIUS
	for axis in 3:
		for s1: float in [-1.0, 1.0]:
			for s2: float in [-1.0, 1.0]:
				var p := Vector3.ZERO
				var q := Vector3.ZERO
				var o1 := (axis + 1) % 3
				var o2 := (axis + 2) % 3
				p[axis] = -h
				q[axis] = h
				p[o1] = s1 * h
				q[o1] = s1 * h
				p[o2] = s2 * h
				q[o2] = s2 * h
				tube(st, p, q, CHORD_RADIUS)
	for axis in 3:
		for s: float in [-1.0, 1.0]:
			var p := Vector3.ZERO
			var q := Vector3.ZERO
			var o1 := (axis + 1) % 3
			var o2 := (axis + 2) % 3
			p[axis] = s * h
			q[axis] = s * h
			p[o1] = -h
			q[o1] = h
			p[o2] = -h
			q[o2] = h
			tube(st, p, q, LACE_RADIUS)


## An open 8-sided tube from p to q with smooth normals.
static func tube(st: SurfaceTool, p: Vector3, q: Vector3, r: float) -> void:
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
