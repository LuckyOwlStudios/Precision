class_name StructureInfo
extends VBoxContainer
## Details of the selected structure piece (truss, corner box, base plate), shown
## by the inspector in place of the fixture sections: name, size, what it is
## joined to, how many fixtures sit on it, and where it stands. Name, position
## and rotation are editable; every edit is one undo step (typing merges).
##
## Like the fixture sections it must fit the dock's width, so the X/Y/Z boxes
## drop their minimum width and the long labels wrap.

var ctx: StudioContext
var piece: StructurePiece

var _syncing := false
var _seen := Transform3D.IDENTITY ## the piece's transform when the facts were last worked out
var _shown: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0] ## what the six boxes showed (rounded) then

@onready var _title: Label = %PieceTitle
@onready var _detail: Label = %PieceDetail
@onready var _name: LineEdit = %PieceName
@onready var _type_value: Label = %TypeValue
@onready var _length_row: Control = %LengthRow
@onready var _length_value: Label = %LengthValue
@onready var _size_value: Label = %SizeValue
@onready var _fixtures_caption: Label = %FixturesCaption
@onready var _fixtures_value: Label = %FixturesValue
@onready var _joined: Label = %Joined
@onready var _place: Array[SpinBox] = [%PositionX, %PositionY, %PositionZ] ## metres
@onready var _turn: Array[SpinBox] = [%RotationX, %RotationY, %RotationZ] ## degrees


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.piece_moved.connect(func(p: StructurePiece) -> void:
		if p == piece:
			_refresh())
	ctx.fixtures_changed.connect(_refresh)
	ctx.fixture_moved.connect(func(_f: DMXFixture) -> void: _refresh())


func _ready() -> void:
	_name.text_submitted.connect(func(t: String) -> void:
		_apply_name(t)
		_name.release_focus())
	_name.focus_exited.connect(func() -> void: _apply_name(_name.text))
	for sb: SpinBox in _place + _turn:
		sb.value_changed.connect(func(_v: float) -> void: _push_placement())
		sb.get_line_edit().add_theme_constant_override("minimum_character_width", 0)


## Show `p`, or nothing when it is null.
func show_piece(p: StructurePiece) -> void:
	piece = p
	if piece == null:
		return
	if not _name.has_focus():
		_syncing = true
		_name.text = String(piece.get_meta(StudioContext.META_LABEL, ""))
		_syncing = false
	_refresh()


func _apply_name(t: String) -> void:
	if not _syncing and piece and is_instance_valid(piece):
		ctx.rename_piece(piece, t)


func _push_placement() -> void:
	if _syncing or piece == null or not is_instance_valid(piece):
		return
	# The boxes show rounded numbers. Only an axis you actually changed is
	# taken from them; the rest keep their exact values, so editing one axis
	# can't nudge a snapped piece off the piece it is joined to.
	var now := piece.global_transform
	var pos := now.origin
	var rot := now.basis.get_euler()
	for i in 3:
		if not is_equal_approx(_place[i].value, _shown[i]):
			pos[i] = _place[i].value
		if not is_equal_approx(_turn[i].value, _shown[3 + i]):
			rot[i] = deg_to_rad(_turn[i].value)
	ctx.place_piece(piece, Transform3D(Basis.from_euler(rot), pos))


## Work out the facts and copy the piece's placement into the boxes.
func _refresh() -> void:
	if piece == null or not is_instance_valid(piece) or not piece.is_inside_tree():
		return
	_seen = piece.global_transform
	var type_name := piece.display_name if piece.display_name != "" else String(piece.name)
	_title.text = StudioContext.piece_name(piece)
	_detail.text = type_name
	_type_value.text = _kind_name(piece.kind)
	var dims := piece.bounds.size
	# A truss is described by its length, which is always its long (X) side.
	_length_row.visible = piece.kind == StructurePiece.Kind.TRUSS
	_length_value.text = "%.2f m" % dims.x
	_size_value.text = "%.2f × %.2f × %.2f m" % [dims.x, dims.y, dims.z]
	_fixtures_caption.text = "Standing on it" if piece.kind == StructurePiece.Kind.BASE_PLATE else "Hung on it"
	_fixtures_value.text = str(_fixture_count())
	_joined.text = _joined_text()
	_syncing = true
	var euler := _seen.basis.get_euler()
	for i in 3:
		# Leave a box alone while you're typing in it.
		if not _place[i].get_line_edit().has_focus():
			_place[i].value = _seen.origin[i]
		if not _turn[i].get_line_edit().has_focus():
			_turn[i].value = rad_to_deg(euler[i])
		_shown[i] = _place[i].value
		_shown[3 + i] = _turn[i].value
	_syncing = false


static func _kind_name(k: StructurePiece.Kind) -> String:
	match k:
		StructurePiece.Kind.BASE_PLATE: return "Base plate"
		StructurePiece.Kind.CORNER: return "Corner box"
	return "Truss"


## Fixtures on this piece: clamped to its tubes, or (a base plate) standing on top.
func _fixture_count() -> int:
	var count := 0
	var pipes := StageRoom.pipes_in(piece)
	var top := piece.world_bounds().grow(0.3)
	for fx in ctx.fixtures():
		var xf := StudioContext.fixture_transform(fx)
		if piece.kind == StructurePiece.Kind.BASE_PLATE:
			if top.has_point(xf.origin):
				count += 1
		elif StageRoom.pipe_holding(pipes, xf, MountRotation.rules_of(StageFixture3D.scene_path_of(fx)).mounts) != null:
			count += 1
	return count


## One line per connector: what is joined there, or "free".
func _joined_text() -> String:
	var others: Array[TrussConnector] = []
	for p in ctx.structure_pieces():
		if p != piece:
			others.append_array(p.connectors())
	var lines: PackedStringArray = []
	for c in piece.connectors():
		var partner := "free"
		for o in others:
			if o.global_position.distance_to(c.global_position) < StructureSnap.JOIN_TOLERANCE:
				partner = StudioContext.piece_name(o.piece())
				break
		lines.append("%s: %s" % [String(c.name).capitalize(), partner])
	return "\n".join(lines)


func _process(_delta: float) -> void:
	# Dragged on the stage: follow it, and work out the joins again.
	if piece and is_instance_valid(piece) and piece.is_inside_tree() and is_visible_in_tree() \
			and not piece.global_transform.is_equal_approx(_seen):
		_refresh()
