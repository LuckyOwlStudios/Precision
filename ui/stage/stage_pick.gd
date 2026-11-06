class_name StagePick
extends RefCounted
## Clicking things on the stage: which fixture or structure piece is under the
## cursor, judged by the meshes you actually see (no physics bodies needed).
##
## Every visible mesh of a fixture or piece is tested two ways:
##   exact - the ray touches the mesh's own triangles
##   near  - the ray passes through the mesh's box, grown by a few pixels on
##           screen, so thin truss tubes, the gaps in a truss lattice and far
##           away fixtures are still easy to hit
## A structure piece also passes its authored `bounds` box, which counts as
## solid: clicking through the gaps of a truss lattice picks that truss, not
## the one behind it.
## An exact hit beats a near one (so a click just beside a thin tube doesn't
## steal it from the fixture you are actually on); between two hits of the
## same kind, the nearer one wins.
##
## Meshes that are light rather than things are skipped: anything named Beam,
## Glow... or Marker (beam cones, lens halos, selection brackets), and any node
## in the "no_pick" group, so a new fixture scene only needs those names.

const SKIP_PREFIXES: Array[String] = ["Beam", "Glow", "Marker"]
const NO_PICK_GROUP := &"no_pick"
const PAD_PX := 6.0 ## how far outside a mesh's box a click still counts, in screen pixels

static var _triangles: Dictionary = {} ## Mesh -> TriangleMesh, built on first click


## One thing the ray hit.
class Hit:
	var target: Object ## the DMXFixture or StructurePiece
	var exact := false ## touched the mesh itself, not just its padded box
	var distance := INF ## metres from the ray's origin

	func beats(other: Hit) -> bool:
		if other == null:
			return true
		if exact != other.exact:
			return exact
		return distance < other.distance


## The best hit of a camera ray on the meshes under `root`, or null.
## `solid_box` (in root's own space, e.g. a piece's pick bounds) counts as
## solid: a ray through it is an exact hit.
static func ray_node(cam: Camera3D, at: Vector2, root: Node3D, target: Object,
		solid_box: AABB = AABB()) -> Hit:
	var origin := cam.project_ray_origin(at)
	var dir := cam.project_ray_normal(at)
	var best: Hit = null
	if solid_box.has_volume():
		best = _test(cam, origin, dir, root.global_transform, solid_box, null, target, best, true)
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		if not _pickable(n, root):
			continue
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh:
				best = _test(cam, origin, dir, mi.global_transform, mi.mesh.get_aabb(), mi.mesh, target, best)
		elif n is CSGShape3D and (n as CSGShape3D).is_root_shape():
			var csg := n as CSGShape3D
			var parts := csg.get_meshes()
			if parts.size() >= 2 and parts[1] is Mesh:
				var m: Mesh = parts[1]
				var xf := csg.global_transform * (parts[0] as Transform3D)
				best = _test(cam, origin, dir, xf, m.get_aabb(), m, target, best)
	return best


static func _pickable(n: Node, root: Node) -> bool:
	var g := n as GeometryInstance3D
	if not g.is_visible_in_tree():
		return false
	var p: Node = n
	while p and p != root:
		if p.is_in_group(NO_PICK_GROUP):
			return false
		for s in SKIP_PREFIXES:
			if String(p.name).begins_with(s):
				return false
		p = p.get_parent()
	return true


## Test one box (and its mesh, if given) placed at `xf`; returns the better of
## that and `best`. A `solid` box is an exact hit wherever the ray enters it.
static func _test(cam: Camera3D, origin: Vector3, dir: Vector3, xf: Transform3D,
		box: AABB, mesh: Mesh, target: Object, best: Hit, solid := false) -> Hit:
	if not box.has_surface():
		return best
	# Grow the box by a few screen pixels' worth of metres at its distance,
	# converted into the mesh's own (possibly scaled) units.
	var centre := xf * box.get_center()
	var s := xf.basis.get_scale().abs()
	var scale := maxf(minf(s.x, minf(s.y, s.z)), 1e-4)
	var pad := world_per_px(cam, centre) * PAD_PX / scale
	var inv := xf.affine_inverse()
	var lo := inv * origin
	var ld := inv.basis * dir # not normalised: t stays in world metres
	var t := _ray_box(box.grow(pad), lo, ld)
	if t < 0.0:
		return best
	var hit := Hit.new()
	hit.target = target
	hit.distance = t
	if solid:
		var inside := _ray_box(box, lo, ld)
		if inside >= 0.0:
			hit.exact = true
			hit.distance = inside
	elif mesh:
		var exact := _ray_mesh(mesh, lo, ld)
		if not exact.is_empty():
			hit.exact = true
			hit.distance = ((xf * (exact["position"] as Vector3)) - origin).length()
	return hit if hit.beats(best) else best


static func _ray_mesh(mesh: Mesh, lo: Vector3, ld: Vector3) -> Dictionary:
	var tri: TriangleMesh = _triangles.get(mesh)
	if tri == null:
		tri = mesh.generate_triangle_mesh()
		if tri == null:
			return {}
		_triangles[mesh] = tri
	return tri.intersect_ray(lo, ld)


## Where a ray enters a box: the distance along it (0 if it starts inside),
## or -1 if it misses.
static func _ray_box(box: AABB, o: Vector3, d: Vector3) -> float:
	var t_near := 0.0
	var t_far := INF
	for a in 3:
		var lo: float = box.position[a]
		var hi: float = box.end[a]
		if absf(d[a]) < 1e-12:
			if o[a] < lo or o[a] > hi:
				return -1.0
			continue
		var t1 := (lo - o[a]) / d[a]
		var t2 := (hi - o[a]) / d[a]
		t_near = maxf(t_near, minf(t1, t2))
		t_far = minf(t_far, maxf(t1, t2))
		if t_near > t_far:
			return -1.0
	return t_near


## How many metres one screen pixel covers at world point `p` (works for
## perspective and orthographic cameras).
static func world_per_px(cam: Camera3D, p: Vector3) -> float:
	var depth := -(cam.global_transform.affine_inverse() * p).z
	if depth <= cam.near:
		return 0.0
	var sp := cam.unproject_position(p)
	return cam.project_position(sp, depth).distance_to(cam.project_position(sp + Vector2(1, 0), depth))
