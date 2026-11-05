@tool
class_name TrussConnector
extends Marker3D
## A face of a structural piece that another piece can join onto: the end of a
## truss, a face of a corner box, the top of a base plate.
##
## Local +Y points out of the face. Local +Z is "outward x up" (the face
## direction crossed with the piece's up), or any sideways direction on faces
## that point straight up or down. Keeping to that rule is what makes trusses
## that join through a corner box stay upright, so copy an existing connector
## when you add one. Two pieces join with their connectors at the same point,
## +Y facing each other and +Z opposite (a half turn about X).

## Which kinds of piece may join here.
@export_flags("Base plate", "Truss", "Corner") var accepts := StructurePiece.ACCEPTS_TRUSS


func piece() -> StructurePiece:
	var n := get_parent()
	while n and not (n is StructurePiece):
		n = n.get_parent()
	return n as StructurePiece


func accepts_kind(k: StructurePiece.Kind) -> bool:
	return (accepts & StructurePiece.kind_flag(k)) != 0
