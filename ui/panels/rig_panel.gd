class_name RigPanel
extends MarginContainer
## Every fixture placed on the stage, with its DMX patch. Selecting here
## selects on the stage and in the inspector, and the other way round.
## Double-click a row (or press F2 / Enter) to give the fixture your own name.

var ctx: StudioContext

var _list := ItemList.new()
var _empty: Control
var _syncing := false
var _editor := LineEdit.new()
var _editing: DMXFixture


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.fixtures_changed.connect(_rebuild)
	ctx.selection_changed.connect(_on_selection_changed)
	_rebuild()


func _ready() -> void:
	add_theme_constant_override("margin_left", UIPalette.COLUMN_PAD)
	add_theme_constant_override("margin_right", UIPalette.COLUMN_PAD)
	add_theme_constant_override("margin_top", 16)
	add_theme_constant_override("margin_bottom", 8)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	var head := UIKit.section("On stage", "−", "Remove the selected fixture (Delete)")
	(head.get_meta("action") as Button).pressed.connect(func() -> void: ctx.remove_fixture(ctx.selected))
	col.add_child(head)

	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(_start_rename) # double-click or Enter
	_list.gui_input.connect(_on_list_input)
	col.add_child(_list)

	_editor.visible = false
	_editor.placeholder_text = "Fixture name"
	_editor.text_submitted.connect(func(_t: String) -> void: _finish_rename(true))
	_editor.focus_exited.connect(func() -> void: _finish_rename(true))
	_editor.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventKey and (e as InputEventKey).pressed and (e as InputEventKey).keycode == KEY_ESCAPE:
			_finish_rename(false)
			_editor.accept_event())
	_list.add_child(_editor)

	_empty = UIKit.empty_state("Nothing patched", "Fixtures you place on the stage appear here with their DMX address.")
	col.add_child(_empty)


func _rebuild() -> void:
	if ctx == null:
		return
	_list.clear()
	var fixtures := ctx.fixtures()
	for fx in fixtures:
		var last := fx.start_address + fx.profile.channels.size() - 1
		var i := _list.add_item("%s      U%d · %d–%d" % [StudioContext.display_name(fx), ctx.universe.universe_id + 1, fx.start_address, last])
		_list.set_item_metadata(i, fx)
		var tip := String(fx.get_meta(StudioContext.META_PROFILE_LABEL, ""))
		if fx.has_meta(StudioContext.META_LABEL):
			tip = "%s (%s)" % [tip, fx.name]
		_list.set_item_tooltip(i, tip + "\nDouble-click or F2 to rename")
	_list.visible = not fixtures.is_empty()
	_empty.visible = fixtures.is_empty()
	_on_selection_changed(ctx.selected)


func _on_item_selected(index: int) -> void:
	if not _syncing:
		ctx.select(_list.get_item_metadata(index))


func _on_selection_changed(fx: DMXFixture) -> void:
	_syncing = true
	_list.deselect_all()
	for i in _list.item_count:
		if _list.get_item_metadata(i) == fx:
			_list.select(i)
	_syncing = false


# ---------------------------------------------------------------- rename in place

func _on_list_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_F2:
		var sel := _list.get_selected_items()
		if not sel.is_empty():
			_start_rename(sel[0])
			_list.accept_event()


func _start_rename(index: int) -> void:
	_editing = _list.get_item_metadata(index)
	var r := _list.get_item_rect(index)
	r.position.y -= _list.get_v_scroll_bar().value
	_editor.position = r.position
	_editor.size = Vector2(_list.size.x - r.position.x - 4.0, r.size.y)
	_editor.text = StudioContext.display_name(_editing)
	_editor.visible = true
	_editor.grab_focus()
	_editor.select_all()


func _finish_rename(apply: bool) -> void:
	if _editing == null:
		return
	var fx := _editing
	_editing = null # first, so focus_exited during hide doesn't apply twice
	_editor.visible = false
	if apply and is_instance_valid(fx):
		ctx.rename_fixture(fx, _editor.text)
