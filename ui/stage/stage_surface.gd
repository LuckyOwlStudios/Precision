@tool
class_name StageSurface
extends MeshInstance3D
## A box in the room that fixtures stick to when you drop or re-stick them
## (floor, walls, trusses, the DJ booth). Give it a BoxMesh: the snapping box
## is that mesh's bounds wherever you move the node in stage_room.tscn.
## A hidden surface still snaps, which is how the trusses work: the lattice
## you see is drawn by TrussLattice, the plain box here is only for snapping.

@export var kind: StageRoom.Kind = StageRoom.Kind.FURNITURE


## The snapping box in world space.
func world_box() -> AABB:
	return global_transform * get_aabb()
