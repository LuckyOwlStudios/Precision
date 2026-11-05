@tool
class_name TrussTube
extends Node3D
## One bar of a truss that fixture clamps can grip: a straight tube from this
## node's origin along its local +X for `length` metres. Fixtures snap to the
## nearest point on any tube and slide along it until a clamp reaches an end.
## Tubes that line up end to end (a run of joined trusses) count as one long
## tube, so a fixture can slide across a joint.
##
## In the editor the tube is drawn as a thin line so you can see where it is.

const RADIUS := MountPoint.TUBE_RADIUS

@export_range(0.05, 20.0, 0.01, "suffix:m") var length := 1.0:
	set(v):
		length = v
		_update_line()
## Which side of the tube fixtures hang on, in this node's space
## (down for a truss's bottom bars, up for its top bars).
@export var hang_side := Vector3.DOWN

var _line: MeshInstance3D


func _ready() -> void:
	_update_line()


func world_start() -> Vector3:
	return global_position


func world_end() -> Vector3:
	return to_global(Vector3(length, 0, 0))


func world_hang_side() -> Vector3:
	return (global_basis * hang_side).normalized()


func _update_line() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _line == null:
		_line = MeshInstance3D.new() # editor helper only: not owned, never saved
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.7, 0.2)
		mat.no_depth_test = true
		_line.material_override = mat
		add_child(_line)
	var m := ImmediateMesh.new()
	m.surface_begin(Mesh.PRIMITIVE_LINES)
	m.surface_add_vertex(Vector3.ZERO)
	m.surface_add_vertex(Vector3(length, 0, 0))
	m.surface_add_vertex(Vector3(length * 0.5, 0, 0))
	m.surface_add_vertex(hang_side.normalized() * 0.08 + Vector3(length * 0.5, 0, 0))
	m.surface_end()
	_line.mesh = m
