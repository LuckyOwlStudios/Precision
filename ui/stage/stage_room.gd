class_name StageRoom
extends RefCounted
## Snapping maths for the room the rig lives in. The room itself is
## stage_room.tscn: its StageSurface nodes (floor, back wall, DJ booth) are the
## boxes fixtures stick flush against, and the truss in its Set is built from
## structure pieces whose TubeSnap nodes are the tubes fixtures clamp onto.
##
## Plain box and line maths (no physics engine), so placement behaves the same
## in every renderer and can be called from input handlers at any time.

enum Kind { FLOOR, WALL, TRUSS, FURNITURE } ## TRUSS is unused now: trusses are structure pieces

## A fixture whose clamps are this close to a tube counts as hung on it.
const ON_PIPE_TOLERANCE := 0.01
## Tubes whose ends are this close (and that line up) join into one run.
const JOIN_TOLERANCE := 0.012


class Surface:
	extends RefCounted
	var box: AABB
	var kind: Kind

	func _init(p_box: AABB, p_kind: Kind) -> void:
		box = p_box
		kind = p_kind


## One straight run of tube that clamps can grip, from `a` to `b`: a single
## TubeSnap, or several that line up end to end across joined trusses.
## `faces` are the world directions, away from the truss, fixtures may hang
## on (the first is the default); with `around` set they may hang anywhere
## round the tube instead, in steps of `step` degrees counted from faces[0].
class Pipe:
	extends RefCounted
	var a: Vector3
	var b: Vector3
	var faces: Array[Vector3] = []
	var around := false
	var step := 0.0

	func _init(p_a: Vector3, p_b: Vector3, p_faces: Array[Vector3], p_around := false, p_step := 0.0) -> void:
		a = p_a
		b = p_b
		for f in p_faces:
			faces.append(f.normalized())
		if faces.is_empty():
			faces.append(Vector3.DOWN)
		around = p_around
		step = p_step

	## The default face: the first one listed.
	var out: Vector3:
		get:
			return faces[0]

	## The face to hang on when the fixture should point `want` (any direction;
	## only its part square to the tube counts): the listed face nearest it, or
	## with `around` that direction itself, rounded to `step`.
	func face_for(want: Vector3) -> Vector3:
		var u := axis()
		var w := want - u * want.dot(u)
		if w.length() < 1e-6:
			return faces[0]
		w = w.normalized()
		if around:
			if step <= 0.0:
				return w
			var ref := faces[0]
			var ang := ref.signed_angle_to(w, u)
			var turn := deg_to_rad(snappedf(rad_to_deg(ang), step))
			return ref.rotated(u, turn).normalized()
		var best := faces[0]
		for f in faces:
			if f.dot(w) > best.dot(w):
				best = f
		return best

	## True when both runs let fixtures hang the same ways.
	func same_faces(other: Pipe) -> bool:
		if around != other.around or not is_equal_approx(step, other.step):
			return false
		if around:
			return true
		if faces.size() != other.faces.size():
			return false
		for f in faces:
			var found := false
			for g in other.faces:
				if f.dot(g) > 0.99:
					found = true
			if not found:
				return false
		return true

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

	## Distance from a point to the tube itself (its ends included).
	func distance_to(p: Vector3) -> float:
		return p.distance_to(point(clampf(along_of(p), 0.0, length())))

	## Where along the tube a ray passes closest, clamped to its ends, and how
	## close it gets: [along, distance, distance along the ray].
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
		return [s, p.distance_to(origin + v * t), t]


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


## Every tube of every structure piece under `root`, with tubes that line up
## end to end joined into one run, so a fixture can slide across a joint.
static func pipes_in(root: Node) -> Array[Pipe]:
	var pipes: Array[Pipe] = []
	for n in root.find_children("*", "", true, false):
		if n is TubeSnap and (n as TubeSnap).enabled:
			var t := n as TubeSnap
			pipes.append(Pipe.new(t.world_start(), t.world_end(), t.world_faces(), t.mode == TubeSnap.Mode.AROUND, t.step))
	var merged := true
	while merged:
		merged = false
		for i in pipes.size():
			for j in range(i + 1, pipes.size()):
				var joined := _join(pipes[i], pipes[j])
				if joined:
					pipes[i] = joined
					pipes.remove_at(j)
					merged = true
					break
			if merged:
				break
	return pipes


## Two tubes as one run if they line up and touch end to end, else null.
static func _join(p: Pipe, q: Pipe) -> Pipe:
	if absf(p.axis().dot(q.axis())) < 0.9995 or not p.same_faces(q):
		return null
	if p.distance_to_line(q.a) > JOIN_TOLERANCE or p.distance_to_line(q.b) > JOIN_TOLERANCE:
		return null
	var run := p.length()
	var qa := p.along_of(q.a)
	var qb := p.along_of(q.b)
	var lo := minf(qa, qb)
	var hi := maxf(qa, qb)
	if lo > run + JOIN_TOLERANCE or hi < -JOIN_TOLERANCE:
		return null # same line, but a gap between them
	return Pipe.new(p.point(minf(0.0, lo)), p.point(maxf(run, hi)), p.faces, p.around, p.step)


## The tube nearest a point, or null if there are none.
static func pipe_near(pipes: Array[Pipe], p: Vector3) -> Pipe:
	var best: Pipe = null
	var best_d := INF
	for pipe in pipes:
		var d := pipe.distance_to(p)
		if d < best_d:
			best_d = d
			best = pipe
	return best


## Hang a fixture from a tube by its clamps. `mounts` are the fixture's
## MountPoint positions in its own space (see StageFixture3D.mounts_of), all on
## one line along its X axis. `along` is where the middle of the clamps should
## sit on the tube; it is kept far enough from the ends for every clamp to fit.
## The beam points away from the truss, and the fixture faces the audience (+Z)
## where it can.
## `side` is the face of the tube to hang on (default: its first one, see
## Pipe.face_for); a side face hangs the fixture off it, beam pointing outwards.
static func hang(pipe: Pipe, along: float, mounts: PackedVector3Array, side := Vector3.ZERO) -> Transform3D:
	var y := -(pipe.out if side == Vector3.ZERO else side).normalized()
	var x := pipe.axis()
	var facing := y.cross(Vector3.BACK).dot(x)
	if absf(facing) > 1e-4:
		if facing < 0.0:
			x = -x # keep the fixture's front (+Z) towards the audience
	elif x.cross(y).y < 0.0:
		x = -x # hung off a side facing the audience: keep its front up
	return slide(pipe, Transform3D(Basis(x, y, x.cross(y)).orthonormalized(), Vector3.ZERO), mounts, along)


## Move a fixture along a tube without turning it: the middle of its clamps
## goes to `along`, but no further than lets its outermost clamp reach an end.
## A 1.2 m bar with a clamp at each end stops 0.6 m from the end of the tube.
static func slide(pipe: Pipe, xform: Transform3D, mounts: PackedVector3Array, along: float) -> Transform3D:
	var r := slide_range(pipe, mounts)
	along = clampf(along, r.x, r.y)
	return Transform3D(xform.basis, pipe.point(along) - xform.basis * centre_of(mounts))


## How far along a tube the middle of a fixture's clamps may go: [from, to],
## keeping every clamp on the tube.
static func slide_range(pipe: Pipe, mounts: PackedVector3Array) -> Vector2:
	var centre := centre_of(mounts)
	var half_span := 0.0
	for m: Vector3 in mounts:
		half_span = maxf(half_span, absf(m.x - centre.x))
	var run := pipe.length()
	var margin := half_span + MountPoint.CLAMP_HALF_WIDTH
	return Vector2(minf(margin, run * 0.5), maxf(run - margin, run * 0.5))


# ---------------------------------------------------------------- fixtures side by side on one tube

## Fixtures on one tube keep this far apart (metres between their bodies).
const NEIGHBOUR_GAP := 0.005


## How much of a tube a fixture's body covers: [from, to] along it, for the
## fixture at `xform` with its body box `box` (in its own space).
static func span_on(pipe: Pipe, xform: Transform3D, box: AABB) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in 8:
		var a := pipe.along_of(xform * box.get_endpoint(i))
		lo = minf(lo, a)
		hi = maxf(hi, a)
	return Vector2(lo, hi)


## Where the middle of a fixture's clamps may NOT go because its body would
## run into a neighbour's: `rel` is its body's span relative to the middle of
## its clamps, `others` the spans neighbours cover. One open range per neighbour.
static func blocked_by(rel: Vector2, others: Array[Vector2]) -> Array[Vector2]:
	var list: Array[Vector2] = []
	for o in others:
		list.append(Vector2(o.x - rel.y - NEIGHBOUR_GAP, o.y - rel.x + NEIGHBOUR_GAP))
	list.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	var merged: Array[Vector2] = []
	for b in list:
		if not merged.is_empty() and b.x <= merged[-1].y:
			merged[-1] = Vector2(merged[-1].x, maxf(merged[-1].y, b.y))
		else:
			merged.append(b)
	return merged


## The stretch of `limits` a fixture whose clamps' middle is at `at` can slide
## in without passing a neighbour: it stops at their edges. If it already
## overlaps one (an old rig), it isn't held back.
static func free_gap(limits: Vector2, blocked: Array[Vector2], at: float) -> Vector2:
	var gap := limits
	for b in blocked:
		if at > b.x and at < b.y:
			return limits
		if b.y <= at:
			gap.x = maxf(gap.x, b.y)
		elif b.x >= at:
			gap.y = minf(gap.y, b.x)
	return gap


## The free spot in `limits` nearest `want`, or NAN if the tube is full.
static func nearest_free(limits: Vector2, blocked: Array[Vector2], want: float) -> float:
	var options: Array[float] = [clampf(want, limits.x, limits.y)]
	for b in blocked:
		options.append(b.x)
		options.append(b.y)
	var best := NAN
	for a in options:
		if a < limits.x - 1e-6 or a > limits.y + 1e-6:
			continue
		var inside := false
		for b in blocked:
			if a > b.x + 1e-6 and a < b.y - 1e-6:
				inside = true
				break
		if not inside and (is_nan(best) or absf(a - want) < absf(best - want)):
			best = a
	return best


## Where the middle of a fixture's clamps is along a tube.
static func clamps_along(pipe: Pipe, xform: Transform3D, mounts: PackedVector3Array) -> float:
	return pipe.along_of(xform * centre_of(mounts))


## The middle of a fixture's clamps, in its own space.
static func centre_of(mounts: PackedVector3Array) -> Vector3:
	var centre := Vector3.ZERO
	for m: Vector3 in mounts:
		centre += m
	if not mounts.is_empty():
		centre /= mounts.size()
	return centre


## The tube a fixture is hung from: one that every clamp sits on, running along
## the fixture's X axis (or, with a single clamp, square to its Y). Null when it stands on a floor or wall instead, or was
## moved off the tube.
static func pipe_holding(pipes: Array[Pipe], xform: Transform3D, mounts: PackedVector3Array) -> Pipe:
	if mounts.is_empty():
		return null
	for pipe in pipes:
		if mounts.size() > 1:
			# Several clamps on one tube: the fixture's X runs along it.
			if absf(xform.basis.x.normalized().dot(pipe.axis())) < 0.99:
				continue
		elif absf(xform.basis.y.normalized().dot(pipe.axis())) > 0.02:
			# One clamp may be turned on its bolt (see MountRotation), but
			# the bolt still stands square to the tube.
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
static func raycast(list: Array[Surface], origin: Vector3, dir: Vector3) -> Hit:
	var best: Hit = null
	var best_t := INF
	for s in list:
		var r := ray_box(s.box, origin, dir)
		if r.is_empty() or float(r[0]) >= best_t:
			continue
		best_t = r[0]
		best = Hit.new(origin + dir * best_t, r[1], s.kind)
	return best


## Slab test: [distance, entry face normal], or [] on a miss.
static func ray_box(box: AABB, o: Vector3, d: Vector3) -> Array:
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
