class_name PositionsPanel
extends MarginContainer
## The Positions shelf: save where moving heads are aimed, go back to it, and
## drop it into the song's show. Shows keep a link to the position (not a copy
## of the numbers), so Update here changes every song that uses it.

var ctx: StudioContext

var _selected: PositionPreset

@onready var _list: ItemList = %List
@onready var _name: LineEdit = %PositionName


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.positions_changed.connect(_rebuild)
	ctx.fixtures_changed.connect(_update_buttons)
	ctx.selection_changed.connect(func(_fx: DMXFixture) -> void: _update_buttons())
	ctx.group_changed.connect(_update_buttons)
	_rebuild()


func _ready() -> void:
	_name.text_changed.connect(func(_t: String) -> void: _update_buttons())
	_name.text_submitted.connect(func(_t: String) -> void:
		if not %SavePosition.disabled:
			_save())
	%SavePosition.pressed.connect(_save)
	_list.item_selected.connect(func(i: int) -> void:
		_selected = _list.get_item_metadata(i)
		_update_buttons())
	_list.item_activated.connect(func(i: int) -> void: ctx.apply_position(_list.get_item_metadata(i)))
	%Aim.pressed.connect(func() -> void:
		if _selected:
			ctx.apply_position(_selected))
	%Update.pressed.connect(func() -> void:
		if _selected:
			ctx.update_position(_selected))
	%Rename.pressed.connect(func() -> void:
		if _selected:
			ctx.rename_position(_selected, _name.text))
	%Delete.pressed.connect(func() -> void:
		if _selected:
			ctx.delete_position(_selected))
	%AddToShow.pressed.connect(func() -> void:
		if _selected:
			ctx.add_reference_clip("position", _selected.id, _selected.position_name, ctx.position_beats, _selected_fixtures()))


## The fixtures a clip for the selected position goes on: the ones it covers.
func _selected_fixtures() -> Array:
	var list: Array = []
	for path in _selected.values:
		var fx := ctx.rig.get_node_or_null(NodePath(str(path))) as DMXFixture
		if fx:
			list.append(fx)
	return list


func _save() -> void:
	var p := ctx.save_position(_name.text)
	if p:
		_name.clear()
		_selected = p
	_rebuild()


func _rebuild() -> void:
	if ctx == null:
		return
	if _selected and not ctx.positions.positions.has(_selected):
		_selected = null
	_list.clear()
	for p in ctx.positions.positions:
		var idx := _list.add_item(p.position_name)
		_list.set_item_metadata(idx, p)
		_list.set_item_tooltip(idx, "%d moving head%s" % [p.values.size(), "" if p.values.size() == 1 else "s"])
		if p == _selected:
			_list.select(idx)
	_list.visible = not ctx.positions.positions.is_empty()
	%Empty.visible = not _list.visible
	_update_buttons()


func _update_buttons() -> void:
	if ctx == null:
		return
	var typed := _name.text.strip_edges()
	var clash := not typed.is_empty() and ctx.positions.is_name_taken(typed)
	var sources := ctx.position_sources().size()
	%Source.text = "Saves the aim of %d moving head%s%s." % [sources, "" if sources == 1 else "s", " (select fixtures to choose which)" if ctx.selected == null and ctx.selected_group.is_empty() else ""]
	%SavePosition.disabled = clash or sources == 0
	%Aim.disabled = _selected == null
	%Update.disabled = _selected == null or sources == 0
	%Rename.disabled = _selected == null or typed.is_empty() or clash
	%Delete.disabled = _selected == null
	%AddToShow.disabled = _selected == null
	%NameTaken.visible = clash
	%NameTaken.text = "A position named \"%s\" already exists. Pick another name." % typed
