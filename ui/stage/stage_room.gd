class_name StageRoom
extends RefCounted
## Snapping maths for the room the rig lives in. The room itself is
## stage_room.tscn: its StageSurface nodes (floor, back wall, trusses, DJ booth)
## are the boxes fixtures snap flush against when you place or re-stick one.
##
## Plain box maths (no physics engine), so placement behaves the same in
## every renderer and can be called from input handlers at any time.
##
## The constants below match where stage_room.tscn puts the trusses. They are
## used to hang the demo rig and double-clicked fixtures, so keep them in step
## if you move the trusses in the scene.

enum Kind { FLOOR, WALL, TRUSS, FURNITURE }

const TRUSS_Y := 3.7
const TRUSS_SIZE := 0.29 ## a standard 29 cm box truss
const TRUSS_LENGTH := 9.0
const TRUSS_BOTTOM := TRUSS_Y - TRUSS_SIZE * 0.5
const TRUSS_Z: Array[float] = [0.5, -0.8]
## Trusses are thin, so aiming this close to one still hangs the fixture on it.
const TRUSS_GRAB_MARGIN := 0.22


class Surface:
	extends RefCounted
	var box: AABB
	var kind: Kind

	func _init(p_box: AABB, p_kind: Kind) -> void:
		box = p_box
		kind = p_kind


## Where a ray met a surface. `normal` points out of the surface, into the room.
class Hit:
	extends RefCounted
	var position: Vector3
	var normal: Vector3
	var kind: Kind

	func _init(p_position: Vector3, p_normal: Vector3, p_kind: Kind) -> void:
		position = p_position
		normal = p_normal
		kind = p_kind


## Every StageSurface under `root` (usually the Room node), as world-space boxes.
static func surfaces_in(root: Node) -> Array[Surface]:
	var list: Array[Surface] = []
	for n in root.find_children("*", "", true, false):
		if n is StageSurface:
			list.append(Surface.new((n as StageSurface).world_box(), (n as StageSurface).kind))
	return list


## The nearest surface along a ray, or null if it only sees the void.
## A hit near a truss always hangs underneath it, pointing down.
static func raycast(list: Array[Surface], origin: Vector3, dir: Vector3) -> Hit:
	var best: Hit = null
	var best_t := INF
	for s in list:
		var box := s.box.grow(TRUSS_GRAB_MARGIN) if s.kind == Kind.TRUSS else s.box
		var r := _ray_box(box, origin, dir)
		if r.is_empty() or float(r[0]) >= best_t:
			continue
		best_t = r[0]
		var p := origin + dir * best_t
		if s.kind == Kind.TRUSS:
			var c := s.box.get_center()
			p = Vector3(clampf(p.x, s.box.position.x, s.box.end.x), s.box.position.y, c.z)
			best = Hit.new(p, Vector3.DOWN, s.kind)
		else:
			best = Hit.new(p, r[1], s.kind)
	return best


## Slab test: [distance, entry face normal], or [] on a miss.
static func _ray_box(box: AABB, o: Vector3, d: Vector3) -> Array:
	var t_near := -INF
	var t_far := INF
	var n := Vector3.ZERO
	for a in 3:
		var lo: float = box.position[a]
		var hi: float = box.end[a]
		if absf(d[a]) < 1e-9:
			if o[a] < lo or o[a] > hi:
				return []
			continue
		var t1 := (lo - o[a]) / d[a]
		var t2 := (hi - o[a]) / d[a]
		var side := -1.0 # entering through the low face: normal points -axis
		if t1 > t2:
			var tmp := t1
			t1 = t2
			t2 = tmp
			side = 1.0
		if t1 > t_near:
			t_near = t1
			n = Vector3.ZERO
			n[a] = side
		t_far = minf(t_far, t2)
		if t_near > t_far:
			return []
	if t_near < 0.0:
		return [] # starting inside the box (camera in a wall): ignore it
	return [t_near, n]


## Orientation for a fixture mounted on a surface: its mounting side (local +Y)
## against the surface, its beam (local -Y) pointing out into the room.
## Pars lean towards local +Z, so +Z is kept towards the audience where it can
## be, and towards the floor on walls that face the audience.
static func mount_basis(normal: Vector3) -> Basis:
	var y := -normal.normalized()
	var z := Vector3.BACK - y * Vector3.BACK.dot(y)
	if z.length() < 0.2:
		z = Vector3.DOWN - y * Vector3.DOWN.dot(y)
	z = z.normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, x.cross(y)).orthonormalized()
