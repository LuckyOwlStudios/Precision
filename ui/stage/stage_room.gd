class_name StageRoom
extends RefCounted
## The room the rig lives in: floor, back wall, trusses and the DJ booth, as
## boxes. The stage view draws them, and fixtures snap flush against them when
## you place or re-stick one.
##
## Plain box maths (no physics engine), so placement behaves the same in
## every renderer and can be called from input handlers at any time.

enum Kind { FLOOR, WALL, TRUSS, FURNITURE }

const TRUSS_Y := 3.7
const TRUSS_SIZE := 0.12
const TRUSS_BOTTOM := TRUSS_Y - TRUSS_SIZE * 0.5
const TRUSS_Z: Array[float] = [0.5, -0.8]
## Trusses are thin, so aiming this close to one still hangs the fixture on it.
const TRUSS_GRAB_MARGIN := 0.22


class Surface:
	extends RefCounted
	var box: AABB
	var kind: Kind
	var material: StandardMaterial3D

	func _init(p_box: AABB, p_kind: Kind, p_material: StandardMaterial3D) -> void:
		box = p_box
		kind = p_kind
		material = p_material


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


static func surfaces() -> Array[Surface]:
	var list: Array[Surface] = []

	# Floor: dark, slightly glossy so beams leave a pool and a reflection.
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("1c1f24")
	floor_mat.roughness = 0.55
	floor_mat.metallic = 0.1
	list.append(Surface.new(_box(Vector3(0, -0.05, 0), Vector3(60, 0.1, 60)), Kind.FLOOR, floor_mat))

	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color("15171b")
	list.append(Surface.new(_box(Vector3(0, 3, -6), Vector3(16, 6, 0.2)), Kind.WALL, wall_mat))

	var truss_mat := StandardMaterial3D.new()
	truss_mat.albedo_color = Color("5a606b")
	truss_mat.metallic = 0.8
	truss_mat.roughness = 0.35
	for z in TRUSS_Z:
		list.append(Surface.new(_box(Vector3(0, TRUSS_Y, z), Vector3(9.0, TRUSS_SIZE, TRUSS_SIZE)), Kind.TRUSS, truss_mat))

	var booth_mat := StandardMaterial3D.new()
	booth_mat.albedo_color = Color("1f2228")
	booth_mat.roughness = 0.7
	list.append(Surface.new(_box(Vector3(0, 0.5, -2.6), Vector3(2.0, 1.0, 0.8)), Kind.FURNITURE, booth_mat))
	var deck_mat := StandardMaterial3D.new()
	deck_mat.albedo_color = Color("0b0c0e")
	list.append(Surface.new(_box(Vector3(0, 1.03, -2.6), Vector3(1.6, 0.06, 0.5)), Kind.FURNITURE, deck_mat))
	return list


static func _box(center: Vector3, size: Vector3) -> AABB:
	return AABB(center - size * 0.5, size)


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
