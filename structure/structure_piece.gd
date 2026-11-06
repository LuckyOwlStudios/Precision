@tool
class_name StructurePiece
extends Node3D
## One structural element of a set: a base plate, a straight truss, a corner box.
## Pieces join by their TrussConnector children: drop a piece near a free
## connector and it snaps on, face to face (see StructureSnap). Fixtures clamp
## onto the TubeSnap children.
##
## Every piece scene lives in res://structure/. To make a new one, give it this
## script, set `kind` and `bounds`, and add connectors and tubes as children.

enum Kind { BASE_PLATE, TRUSS, CORNER }

## Bit flags for TrussConnector.accepts, one per Kind.
const ACCEPTS_BASE_PLATE := 1
const ACCEPTS_TRUSS := 2
const ACCEPTS_CORNER := 4

@export var kind: Kind = Kind.TRUSS
## Shown in the library.
@export var display_name := ""
## The box you click to pick the piece, in its own space.
@export var bounds := AABB(Vector3(-0.5, -0.145, -0.145), Vector3(1, 0.29, 0.29))

static var _highlight: StandardMaterial3D


func connectors() -> Array[TrussConnector]:
	var list: Array[TrussConnector] = []
	for n in find_children("*", "", true, false):
		if n is TrussConnector:
			list.append(n)
	return list


func tubes() -> Array[TubeSnap]:
	var list: Array[TubeSnap] = []
	for n in find_children("*", "", true, false):
		if n is TubeSnap:
			list.append(n)
	return list


## The picking box in world space.
func world_bounds() -> AABB:
	return global_transform * bounds


static func kind_flag(k: Kind) -> int:
	return 1 << int(k)


## A soft accent tint over the whole piece while it is selected. Covers both
## plain meshes (truss lattice) and CSG shapes (base plate): only the root CSG
## shape draws, so that is the one that gets the tint.
func set_highlight(on: bool) -> void:
	if _highlight == null:
		_highlight = StandardMaterial3D.new()
		_highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_highlight.albedo_color = Color(UIPalette.ACCENT, 0.35)
		_highlight.no_depth_test = false
	for n in find_children("*", "GeometryInstance3D", true, false):
		if n is CSGShape3D and not (n as CSGShape3D).is_root_shape():
			continue
		if n is MeshInstance3D or n is CSGShape3D:
			(n as GeometryInstance3D).material_overlay = _highlight if on else null
