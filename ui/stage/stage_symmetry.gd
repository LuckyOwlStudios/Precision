class_name StageSymmetry
extends RefCounted
## Mirror mode for building the stage. While `enabled`, everything placed,
## moved, turned or deleted on the stage is copied across a vertical mirror
## plane. The plane is perpendicular to `axis` and passes through `center`.
## A pair stays linked (see `link`) so editing one drags its twin along.

signal changed

enum Axis { X, Z }

const META_PARTNER := &"mirror_partner" ## the other half of a mirrored pair (Node)
const META_FLIP := &"mirror_flip" ## the local axis the pair flips (see default_flip)
const ON_PLANE := 0.02 ## metres: something this close to the plane is its own twin

var enabled := false:
	set(v):
		if v != enabled:
			enabled = v
			changed.emit()
var axis := Axis.X:
	set(v):
		if v != axis:
			axis = v
			changed.emit()
## A point on the plane. Only the coordinate along `axis` matters (x for
## Axis.X, z for Axis.Z); the other is kept so the plane's centre can be shown.
var center := Vector3.ZERO:
	set(v):
		if not v.is_equal_approx(center):
			center = v
			changed.emit()
## Set while loading a rig or following a twin, so it isn't mirrored again.
var suspended := false


func active() -> bool:
	return enabled and not suspended


## Unit normal of the mirror plane.
func normal() -> Vector3:
	return Vector3.RIGHT if axis == Axis.X else Vector3.BACK


## Coordinate of the plane along its axis.
func offset() -> float:
	return center.x if axis == Axis.X else center.z


func set_offset(value: float) -> void:
	center = Vector3(value, center.y, center.z) if axis == Axis.X else Vector3(center.x, center.y, value)


func reset() -> void:
	center = Vector3.ZERO


## `p` reflected across the plane.
func mirror_point(p: Vector3) -> Vector3:
	var n := normal()
	return p - 2.0 * (p - center).dot(n) * n


func mirror_dir(d: Vector3) -> Vector3:
	var n := normal()
	return d - 2.0 * d.dot(n) * n


## Which local axis (0 = x, 2 = z) to flip so a reflected basis is a proper
## rotation again. Never the local Y: that is the beam, and a twin's beam must
## be the mirror of the original's, not its opposite. Picks the one closest to
## the plane's normal as the object is placed now, and the pair keeps it from
## then on (see `link`): choosing it again on every turn made the twin jump
## when the other axis became the closer one.
func default_flip(xf: Transform3D) -> int:
	var b := xf.basis.orthonormalized()
	var n := normal()
	return 0 if absf(b.x.dot(n)) >= absf(b.z.dot(n)) else 2


## The placement of the twin of something placed at `xf`. Its position is
## reflected; its turn is the reflected turn: a tilt towards the plane becomes a
## tilt towards it on the other side. (Reflecting a basis gives a left-handed
## one, so the object's own mirror image is swapped back in by flipping local
## axis `flip`. Truss and fixtures are symmetric about it, so the twin looks
## like a true reflection.) `flip` -1 picks `default_flip`.
func mirror_transform(xf: Transform3D, flip := -1) -> Transform3D:
	var b := xf.basis.orthonormalized()
	if flip < 0:
		flip = default_flip(xf)
	var cols: Array[Vector3] = []
	for i in 3:
		cols.append(mirror_dir(b[i]))
	cols[flip] = -cols[flip]
	return Transform3D(Basis(cols[0], cols[1], cols[2]), mirror_point(xf.origin))


## The placement of `node`'s twin when `node` is at `xf` (uses the pair's flip).
func twin_transform(node: Object, xf: Transform3D) -> Transform3D:
	var flip := int(node.get_meta(META_FLIP, -1)) if node else -1
	return mirror_transform(xf, flip)


## Is something at `xf` sitting on the plane, so it is its own twin?
func on_plane(xf: Transform3D) -> bool:
	return absf((xf.origin - center).dot(normal())) < ON_PLANE


## Pair two nodes up.
static func link(a: Node, b: Node, flip: int) -> void:
	a.set_meta(META_PARTNER, b)
	b.set_meta(META_PARTNER, a)
	a.set_meta(META_FLIP, flip)
	b.set_meta(META_FLIP, flip)


## The twin of `o`, if it has one that is still on stage.
static func partner_of(o: Object) -> Node:
	if o == null or not o.has_meta(META_PARTNER):
		return null
	var p: Variant = o.get_meta(META_PARTNER)
	if p == null or not is_instance_valid(p):
		return null
	var n := p as Node
	return n if n.is_inside_tree() else null
