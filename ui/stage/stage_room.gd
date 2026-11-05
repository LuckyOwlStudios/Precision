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
## The truss's four chords are 48 mm tubes; clamps grip these.
const CHORD_RADIUS := MountPoint.TUBE_RADIUS
## A fixture whose clamps are this close to a tube counts as hung on it.
const ON_PIPE_TOLERANCE := 0.01
## Trusses are thin, so aiming this close to one still hangs the fixture on it.
const TRUSS_GRAB_MARGIN := 0.22


class Surface:
	extends RefCounted
	var box: AABB
	var kind: Kind
	var pipes: Array[Pipe] = [] ## the tubes fixtures clamp onto (trusses only)

	func _init(p_box: AABB, p_kind: Kind) -> void:
		box = p_box
		kind = p_kind
		if kind == Kind.TRUSS:
			pipes = StageRoom.truss_pipes(box)


## One straight tube that clamps can grip, from `a` to `b`. `out` is the side
## fixtures hang on, pointing away from the truss (down for the bottom chords).
class Pipe:
	extends RefCounted
	var a: Vector3
	var b: Vector3
	var out: Vector3

	func _init(p_a: Vector3, p_b: Vector3, p_out: Vector3) -> void:
		a = p_a
		b = p_b
		out = p_out

	func axis() -> Vector3:
		return (b - a).normalized()

	func length() -> float:
		return a.distance_to(b)

	func point(along: float) -> Vector3:
		return a + axis() * along

	## How far along the tube a point is (not clamped).
	func along_of(p: Vector3) -> float:
		return (p - a).dot(axis())

	## Distance from a point to the tube's centre line (as if it ran on forever).
	func distance_to_line(p: Vector3) -> float:
		var d := p - a
		return (d - axis() * d.dot(axis())).length()

	## Where along the tube a ray passes closest, clamped to its ends, and how
	## close it gets: [along, distance].
	func closest_to_ray(origin: Vector3, dir: Vector3) -> Array:
		var u := axis()
		var v := dir.normalized()
		var w := a - origin
		var b_ := u.dot(v)
		var denom := 1.0 - b_ * b_
		var s := 0.0
		if denom > 1e-6:
			s = (b_ * v.dot(w) - u.dot(w)) / denom
		s = clampf(s, 0.0, length())
		var p := point(s)
		var t := maxf((p - origin).dot(v), 0.0)
		return [s, p.distance_to(origin + v * t)]


## Where a ray met a surface. `normal` points out of the surface, into the room.
class Hit:
	extends RefCounted
	var position: Vector3
	var normal: Vector3
	var kind: Kind
	var pipe: Pipe ## the truss tube it grabbed, if it hit a truss
	var along := 0.0 ## where on that tube

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


## The tubes of a box truss that fixtures hang from: its two bottom chords.
## The truss runs along the box's longest side.
static func truss_pipes(box: AABB) -> Array[Pipe]:
	var run := 0
	for i in 3:
		if box.size[i] > box.size[run]:
			run = i
	var across := 2 if run == 0 else 0 # the other horizontal direction
	var inset := CHORD_RADIUS
	var c := box.get_center()
	var list: Array[Pipe] = []
	for side: float in [-1.0, 1.0]:
		var p := c
		p.y = box.position.y + inset
		p[across] = c[across] + side * (box.size[across] * 0.5 - inset)
		var a := p
		var b := p
		a[run] = box.position[run]
		b[run] = box.end[run]
		list.append(Pipe.new(a, b, Vector3.DOWN))
	return list


## Every tube in the room, from all its trusses.
static func pipes_of(list: Array[Surface]) -> Array[Pipe]:
	var pipes: Array[Pipe] = []
	for s in list:
		pipes.append_array(s.pipes)
	return pipes


## The tubes of the trusses where stage_room.tscn puts them, for hanging
## fixtures from code (the demo rig) without the room in hand.
static func default_pipes() -> Array[Pipe]:
	var pipes: Array[Pipe] = []
	for z in TRUSS_Z:
		var box := AABB(Vector3(-TRUSS_LENGTH * 0.5, TRUSS_BOTTOM, z - TRUSS_SIZE * 0.5),
			Vector3(TRUSS_LENGTH, TRUSS_SIZE, TRUSS_SIZE))
		pipes.append_array(truss_pipes(box))
	return pipes


## Hang a fixture from a tube by its clamps. `mounts` are the fixture's
## MountPoint positions in its own space (see StageFixture3D.mounts_of), all on
## one line along its X axis. `along` is where the middle of the clamps should
## sit on the tube; it is kept far enough from the ends for every clamp to fit.
## The beam points away from the truss, and the fixture faces the audience (+Z)
## where it can.
static func hang(pipe: Pipe, along: float, mounts: PackedVector3Array) -> Transform3D:
	var y := -pipe.out.normalized()
	var x := pipe.axis()
	if y.cross(Vector3.BACK).dot(x) < 0.0:
		x = -x # keep the fixture's front (+Z) towards the audience
	return slide(pipe, Transform3D(Basis(x, y, x.cross(y)).orthonormalized(), Vector3.ZERO), mounts, along)


## Move a fixture along a tube without turning it: the middle of its clamps
## goes to `along`, kept far enough from the ends for every clamp to fit.
static func slide(pipe: Pipe, xform: Transform3D, mounts: PackedVector3Array, along: float) -> Transform3D:
	var centre := Vector3.ZERO
	var half_span := 0.0
	if not mounts.is_empty():
		for m: Vector3 in mounts:
			centre += m
		centre /= mounts.size()
		for m: Vector3 in mounts:
			half_span = maxf(half_span, absf(m.x - centre.x))
	var run := pipe.length()
	var margin := half_span + 0.03
	along = clampf(along, minf(margin, run * 0.5), maxf(run - margin, run * 0.5))
	return Transform3D(xform.basis, pipe.point(along) - xform.basis * centre)


## Where the middle of a fixture's clamps is along a tube.
static func clamps_along(pipe: Pipe, xform: Transform3D, mounts: PackedVector3Array) -> float:
	var centre := Vector3.ZERO
	for m: Vector3 in mounts:
		centre += m
	if not mounts.is_empty():
		centre /= mounts.size()
	return pipe.along_of(xform * centre)


## The tube a fixture is hung from: one that every clamp sits on, running along
## the fixture's X axis. Null when it stands on a floor or wall instead, or was
## moved off the tube.
static func pipe_holding(pipes: Array[Pipe], xform: Transform3D, mounts: PackedVector3Array) -> Pipe:
	if mounts.is_empty():
		return null
	for pipe in pipes:
		if absf(xform.basis.x.normalized().dot(pipe.axis())) < 0.99:
			continue
		var ok := true
		for m: Vector3 in mounts:
			var p := xform * m
			var along := pipe.along_of(p)
			if pipe.distance_to_line(p) > ON_PIPE_TOLERANCE or along < -0.01 or along > pipe.length() + 0.01:
				ok = false
				break
		if ok:
			return pipe
	return null


## The nearest surface along a ray, or null if it only sees the void.
## A hit near a truss grabs the closest of its bottom tubes: `pipe` and `along`
## say which and where, and the fixture hangs underneath it, pointing down.
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
		if s.kind == Kind.TRUSS and not s.pipes.is_empty():
			var pipe: Pipe = null
			var along := 0.0
			var closest := INF
			for candidate: Pipe in s.pipes:
				var r2: Array = candidate.closest_to_ray(origin, dir)
				if float(r2[1]) < closest:
					closest = r2[1]
					pipe = candidate
					along = r2[0]
			best = Hit.new(pipe.point(along) + pipe.out * CHORD_RADIUS, pipe.out, s.kind)
			best.pipe = pipe
			best.along = along
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
