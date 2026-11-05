class_name StructureSnap
extends RefCounted
## How structural pieces join. Plain transform maths on TrussConnector nodes:
##   Base plates      -> stand on the floor only
##   Trusses          -> join a base plate, another truss's end, or a corner box face
##   Corner boxes     -> join a truss end; their other faces let the run turn
## Which kinds may join where is set per connector (TrussConnector.accepts),
## so a new piece only needs its connectors placed.

## Connectors this close together are joined (so neither is free).
const JOIN_TOLERANCE := 0.01


## A connector's transform in its piece's own space (works out of the tree too).
static func local_of(c: TrussConnector, piece: Node3D) -> Transform3D:
	var t := c.transform
	var p := c.get_parent()
	while p and p != piece:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## Connectors on `pieces` that nothing is joined to yet, leaving out `ignore`
## (the piece being moved) both as a target and as something that fills one.
static func free_connectors(pieces: Array[StructurePiece], ignore: StructurePiece) -> Array[TrussConnector]:
	var all: Array[TrussConnector] = []
	for p in pieces:
		if p != ignore:
			all.append_array(p.connectors())
	var list: Array[TrussConnector] = []
	for c in all:
		var taken := false
		for other in all:
			if other != c and other.piece() != c.piece() \
					and other.global_position.distance_to(c.global_position) < JOIN_TOLERANCE:
				taken = true
				break
		if not taken:
			list.append(c)
	return list


## Where `piece` goes to join `target` with the best of its own connectors:
## faces together, and the piece kept upright where it can be. Null if the
## target doesn't take this kind of piece.
static func attach(piece: StructurePiece, target: TrussConnector) -> Variant:
	if not target.accepts_kind(piece.kind):
		return null
	var best: Variant = null
	var best_up := -INF
	for c in piece.connectors():
		var xf := join(target.global_transform, local_of(c, piece))
		var up := xf.basis.y.normalized().dot(Vector3.UP)
		if up > best_up + 0.001:
			best_up = up
			best = xf
	return best


## The piece transform that puts a connector (at `own_local` in the piece) face
## to face with a connector at `target`: same point, +Y opposite, +Z opposite.
static func join(target: Transform3D, own_local: Transform3D) -> Transform3D:
	var half_turn := Transform3D(Basis(Vector3.RIGHT, PI), Vector3.ZERO)
	return (target * half_turn * own_local.affine_inverse()).orthonormalized()


## The connector of `piece` that is joined to some other piece, and that other
## connector: [own, other], or [] if it stands alone.
static func joint_of(piece: StructurePiece, pieces: Array[StructurePiece]) -> Array:
	for c in piece.connectors():
		for p in pieces:
			if p == piece:
				continue
			for other in p.connectors():
				if other.global_position.distance_to(c.global_position) < JOIN_TOLERANCE:
					return [c, other]
	return []


## Turn a piece a quarter turn about the joint it hangs from (or about its own
## up axis when nothing holds it, like a base plate).
static func turned(piece: StructurePiece, pieces: Array[StructurePiece]) -> Transform3D:
	var joint := joint_of(piece, pieces)
	var pivot := piece.global_position
	var axis := Vector3.UP
	if not joint.is_empty() and piece.kind != StructurePiece.Kind.BASE_PLATE:
		var other: TrussConnector = joint[1]
		pivot = other.global_position
		axis = other.global_basis.y.normalized()
	var rot := Transform3D(Basis(axis, PI * 0.5), Vector3.ZERO)
	var to_pivot := Transform3D(Basis.IDENTITY, pivot)
	return (to_pivot * rot * to_pivot.affine_inverse() * piece.global_transform).orthonormalized()
