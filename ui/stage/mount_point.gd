@tool
class_name MountPoint
extends MeshInstance3D
## One truss clamp on a fixture: where the fixture grips a truss tube when it
## is hung. Put one in a fixture scene for every clamp the real fixture uses:
## a par or strobe has one on its bracket, a moving head has two (one on each
## omega bracket), a light bar has one at each end.
##
## The node's origin is the centre of the tube it grips, and the tube runs
## along the node's X axis. The fixture's mounting side is local +Y, so the
## clamp hangs down from the tube by `drop` to the bracket it bolts onto.
## Keep every MountPoint of a fixture on one line along the fixture's X axis
## (same Y and Z), since they all grip the same tube.
##
## The clamp itself is drawn from the settings below, in the editor too (the
## mesh is not saved). Anything else that only goes on when the fixture is
## rigged, like a moving head's omega bracket, goes under this node: the
## whole lot is hidden while the fixture stands on the floor or a wall.

const TUBE_RADIUS := 0.024 ## standard 48 mm truss tube
## How far a clamp reaches past its centre along the tube (half the jaw, plus
## a little room): a fixture slides until its outermost clamp is this far from
## the end of the tube.
const CLAMP_HALF_WIDTH := 0.03

## Tube centre to the face the clamp bolts onto (the bracket or the fixture's top).
@export_range(0.04, 0.3, 0.001, "suffix:m") var drop := 0.07:
	set(v):
		drop = v
		_rebuild()
## How wide the clamp's jaw is, along the tube.
@export_range(0.02, 0.08, 0.001, "suffix:m") var width := 0.04:
	set(v):
		width = v
		_rebuild()
## Which side the wing screw sticks out of, in local Z (1 = towards +Z).
@export var screw_side := 1.0:
	set(v):
		screw_side = v
		_rebuild()


func _ready() -> void:
	_rebuild()


func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage &= ~PROPERTY_USAGE_STORAGE # built here, never saved


## A hook clamp like the ones on most DJ fixtures: a band hooked over the tube,
## a cast body under it with a wing screw biting into the tube from the side,
## and a bolt down into the bracket.
func _rebuild() -> void:
	if not is_inside_tree():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := TUBE_RADIUS
	var hw := width * 0.5
	var side := signf(screw_side) if screw_side != 0.0 else 1.0
	# The hook: a band around the tube from the far side, over the top, to the body.
	_arc(st, r + 0.002, r + 0.009, hw, deg_to_rad(-150.0) * side, deg_to_rad(95.0) * side)
	# The body under the tube, from just below it down towards the bracket.
	var body_top := -r * 0.55
	var body_bottom := -drop + 0.018
	_box(st, Vector3(-hw, body_bottom, -0.022), Vector3(hw, body_top, 0.022))
	# A thicker cheek on the screw side where the band ends.
	_box(st, Vector3(-hw, body_top, side * 0.018), Vector3(hw, -r * 0.1, side * (r + 0.014)))
	# Wing screw through the cheek, biting into the tube from the side.
	_cylinder(st, Vector3(0, -r * 0.5, side * (r + 0.006)), Vector3(0, -r * 0.5, side * (r + 0.036)), 0.0045)
	_box(st, Vector3(-0.022, -r * 0.5 - 0.009, side * (r + 0.032)), Vector3(0.022, -r * 0.5 + 0.009, side * (r + 0.036)))
	# Bolt and washer down into the bracket.
	_cylinder(st, Vector3(0, body_bottom, 0), Vector3(0, -drop, 0), 0.006)
	_cylinder(st, Vector3(0, -drop + 0.004, 0), Vector3(0, -drop, 0), 0.016)
	mesh = st.commit()


## A band around the X axis between two radii, from angle a0 to a1 (radians,
## measured from +Y towards +Z).
static func _arc(st: SurfaceTool, r0: float, r1: float, hw: float, a0: float, a1: float) -> void:
	const STEPS := 14
	if a1 < a0:
		var t := a0
		a0 = a1
		a1 = t
	for i in STEPS:
		var t0 := lerpf(a0, a1, float(i) / STEPS)
		var t1 := lerpf(a0, a1, float(i + 1) / STEPS)
		var n0 := Vector3(0, cos(t0), sin(t0))
		var n1 := Vector3(0, cos(t1), sin(t1))
		var l := Vector3(-hw, 0, 0)
		var h := Vector3(hw, 0, 0)
		# outer and inner faces, smooth around the tube
		_quad_smooth(st, l + n0 * r1, h + n0 * r1, h + n1 * r1, l + n1 * r1, n0, n0, n1, n1)
		_quad_smooth(st, l + n0 * r0, l + n1 * r0, h + n1 * r0, h + n0 * r0, -n0, -n1, -n1, -n0)
		# the two edges of the band
		_quad(st, l + n0 * r0, l + n0 * r1, l + n1 * r1, l + n1 * r0, Vector3.LEFT)
		_quad(st, h + n0 * r0, h + n1 * r0, h + n1 * r1, h + n0 * r1, Vector3.RIGHT)
	# end caps
	for a: float in [a0, a1]:
		var n := Vector3(0, cos(a), sin(a))
		var tangent := Vector3(0, -sin(a), cos(a)) * (1.0 if a == a1 else -1.0)
		_quad(st, Vector3(-hw, 0, 0) + n * r0, Vector3(hw, 0, 0) + n * r0, Vector3(hw, 0, 0) + n * r1, Vector3(-hw, 0, 0) + n * r1, tangent)


static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var a := Vector3(minf(lo.x, hi.x), minf(lo.y, hi.y), minf(lo.z, hi.z))
	var b := Vector3(maxf(lo.x, hi.x), maxf(lo.y, hi.y), maxf(lo.z, hi.z))
	var c: Array[Vector3] = [
		Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(a.x, b.y, a.z),
		Vector3(a.x, a.y, b.z), Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z),
	]
	_quad(st, c[0], c[1], c[2], c[3], Vector3.FORWARD)
	_quad(st, c[5], c[4], c[7], c[6], Vector3.BACK)
	_quad(st, c[4], c[0], c[3], c[7], Vector3.LEFT)
	_quad(st, c[1], c[5], c[6], c[2], Vector3.RIGHT)
	_quad(st, c[3], c[2], c[6], c[7], Vector3.UP)
	_quad(st, c[4], c[5], c[1], c[0], Vector3.DOWN)


## A closed round rod from p to q.
static func _cylinder(st: SurfaceTool, p: Vector3, q: Vector3, r: float) -> void:
	const SIDES := 10
	var y := (q - p).normalized()
	var x := y.cross(Vector3.UP if absf(y.y) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	for i in SIDES:
		var a0 := TAU * i / SIDES
		var a1 := TAU * (i + 1) / SIDES
		var n0 := x * cos(a0) + z * sin(a0)
		var n1 := x * cos(a1) + z * sin(a1)
		_quad_smooth(st, p + n0 * r, p + n1 * r, q + n1 * r, q + n0 * r, n0, n1, n1, n0)
		_tri(st, p, p + n1 * r, p + n0 * r, -y)
		_tri(st, q, q + n0 * r, q + n1 * r, y)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_quad_smooth(st, a, b, c, d, n, n, n, n)


static func _quad_smooth(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	for v: Array in [[a, na], [b, nb], [c, nc], [a, na], [c, nc], [d, nd]]:
		st.set_normal(v[1])
		st.add_vertex(v[0])


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	for v: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)
