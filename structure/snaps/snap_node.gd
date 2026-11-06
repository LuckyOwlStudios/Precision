@tool
class_name SnapNode
extends Node3D
## Base class for every place a fixture can snap onto. Put one (a subclass,
## such as TubeSnap) in a structure piece's scene and the Stage view will snap
## fixtures to it; the subclass decides how: along a line, around a tube, on
## a fixed set of faces.
##
## Subclasses draw their own editor helper by overriding _build_helper().

## Switch a snap off without deleting it.
@export var enabled := true:
	set(v):
		enabled = v
		update_helper()

const HELPER_COLOR := Color(1.0, 0.7, 0.2)

var _helper: MeshInstance3D


func _ready() -> void:
	update_helper()


## Every enabled snap of a given class under `root` (all snaps if `type` is null).
static func all_in(root: Node, type: Variant = null) -> Array[SnapNode]:
	var list: Array[SnapNode] = []
	for n in root.find_children("*", "", true, false):
		if n is SnapNode and (n as SnapNode).enabled and (type == null or is_instance_of(n, type)):
			list.append(n)
	return list


## Redraw the editor helper (lines only seen in the Godot editor).
func update_helper() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _helper == null:
		_helper = MeshInstance3D.new() # editor helper only: not owned, never saved
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = HELPER_COLOR
		mat.no_depth_test = true
		_helper.material_override = mat
		add_child(_helper)
	var m := ImmediateMesh.new()
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	_build_helper(m)
	m.surface_add_vertex(Vector3.ZERO) # keep the surface non-empty
	m.surface_add_vertex(Vector3.ZERO)
	m.surface_end()
	_helper.mesh = m
	_helper.visible = enabled


## Add line pairs to `m` (in this node's space) showing how the snap works.
func _build_helper(_m: ImmediateMesh) -> void:
	pass
