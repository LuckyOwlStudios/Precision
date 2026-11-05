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

const ARROW_LENGTH := 0.2
const ARROW_COLOR := Color(1.0, 0.62, 0.15)

static var _arrow_mesh: ArrayMesh
static var _arrow_material: StandardMaterial3D
var _arrow: MeshInstance3D


## An arrow out of the face (+Y), drawn on top of everything. Always shown in
## the editor; in the app the stage view shows it on free connectors while you
## place a piece. Not saved into the scene.
func _ready() -> void:
	_arrow = MeshInstance3D.new()
	_arrow.mesh = _arrow_shape()
	_arrow.material_override = _arrow_shape_material()
	_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.visible = Engine.is_editor_hint()
	add_child(_arrow)


func set_arrow_visible(on: bool) -> void:
	if _arrow:
		_arrow.visible = on


static func _arrow_shape_material() -> StandardMaterial3D:
	if _arrow_material == null:
		_arrow_material = StandardMaterial3D.new()
		_arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_arrow_material.albedo_color = ARROW_COLOR
		_arrow_material.no_depth_test = true
		_arrow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_arrow_material.render_priority = 3
	return _arrow_material


## A shaft and a cone head along +Y, starting just off the face.
static func _arrow_shape() -> ArrayMesh:
	if _arrow_mesh:
		return _arrow_mesh
	const SIDES := 10
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shaft_r := 0.008
	var head_r := 0.024
	var head_start := ARROW_LENGTH * 0.62
	for i in SIDES:
		var a0 := TAU * i / SIDES
		var a1 := TAU * (i + 1) / SIDES
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b := Vector3(0, 0.01, 0)
		var h := Vector3(0, head_start, 0)
		var tip := Vector3(0, ARROW_LENGTH, 0)
		# shaft
		for v in [b + d0 * shaft_r, b + d1 * shaft_r, h + d1 * shaft_r, b + d0 * shaft_r, h + d1 * shaft_r, h + d0 * shaft_r]:
			st.add_vertex(v)
		# head: cone and its base
		for v in [h + d0 * head_r, h + d1 * head_r, tip, h, h + d1 * head_r, h + d0 * head_r]:
			st.add_vertex(v)
	_arrow_mesh = st.commit()
	return _arrow_mesh


func piece() -> StructurePiece:
	var n := get_parent()
	while n and not (n is StructurePiece):
		n = n.get_parent()
	return n as StructurePiece


func accepts_kind(k: StructurePiece.Kind) -> bool:
	return (accepts & StructurePiece.kind_flag(k)) != 0
