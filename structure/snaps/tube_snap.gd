@tool
class_name TubeSnap
extends SnapNode
## A tube fixture clamps can grip: a straight bar from this node's origin along
## its local +X for `length` metres. Fixtures slide along it until a clamp
## reaches an end, and tubes that line up end to end (a run of joined trusses)
## count as one long tube.
##
## Which way round the tube a fixture may hang is set by `mode`:
## - ANGLES: only on the faces listed in `angles`. A truss corner bar takes two,
##   e.g. 0 and 90 for its top and its front.
## - AROUND: anywhere round the tube (360°), in steps of `step` degrees
##   (0 = free), e.g. a lone pipe or a ceiling bar.
##
## Angles are degrees about the tube (+X), measured from this node's +Y:
## 0 = +Y (up), 90 = +Z (front), 180 = -Y (down), -90 = -Z (back).
## The cursor picks the face: beside the tube on the left means its left face,
## above it means its top. The first angle is the default face.

enum Mode { ANGLES, AROUND }

const RADIUS := MountPoint.TUBE_RADIUS

@export_range(0.05, 20.0, 0.01, "suffix:m") var length := 1.0:
	set(v):
		length = v
		update_helper()
@export var mode := Mode.ANGLES:
	set(v):
		mode = v
		notify_property_list_changed()
		update_helper()
## Faces fixtures hang on (ANGLES mode), in degrees round the tube from +Y.
@export var angles := PackedFloat32Array([180.0]):
	set(v):
		angles = v
		update_helper()
## Snap step round the tube in AROUND mode, in degrees; 0 for free.
@export_range(0.0, 180.0, 1.0, "suffix:°") var step := 0.0:
	set(v):
		step = v
		update_helper()


func _validate_property(property: Dictionary) -> void:
	if property.name == "angles" and mode != Mode.ANGLES:
		property.usage = PROPERTY_USAGE_NO_EDITOR
	elif property.name == "step" and mode != Mode.AROUND:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func world_start() -> Vector3:
	return global_position


func world_end() -> Vector3:
	return to_global(Vector3(length, 0, 0))


## The direction of an angle round the tube, in this node's space.
static func face_dir(degrees: float) -> Vector3:
	return Basis(Vector3.RIGHT, deg_to_rad(degrees)) * Vector3.UP


## The faces fixtures may hang on, in world space: the listed angles in ANGLES
## mode, or just the 0° face (where AROUND counts its steps from) in AROUND mode.
func world_faces() -> Array[Vector3]:
	var list: Array[Vector3] = []
	if mode == Mode.AROUND:
		list.append((global_basis * face_dir(0.0)).normalized())
		return list
	for a: float in angles:
		list.append((global_basis * face_dir(a)).normalized())
	return list


func _build_helper(m: ImmediateMesh) -> void:
	var mid := Vector3(length * 0.5, 0, 0)
	m.surface_add_vertex(Vector3.ZERO)
	m.surface_add_vertex(Vector3(length, 0, 0))
	if mode == Mode.AROUND:
		var n := 24
		for i in n: # a ring round the middle
			m.surface_add_vertex(mid + face_dir(360.0 * i / n) * 0.06)
			m.surface_add_vertex(mid + face_dir(360.0 * (i + 1) / n) * 0.06)
		return
	for a: float in angles:
		m.surface_add_vertex(mid)
		m.surface_add_vertex(mid + face_dir(a) * 0.08)
