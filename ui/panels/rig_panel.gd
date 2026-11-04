class_name RigPanel
extends MarginContainer
## Every fixture placed on the stage, with its DMX patch. Selecting here
## selects on the stage and in the inspector, and the other way round.

var ctx: StudioContext

var _list := ItemList.new()
var _empty: Control
var _syncing := false


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
	col.add_child(_list)

	_empty = UIKit.empty_state("Nothing patched", "Fixtures you place on the stage appear here with their DMX address.")
	col.add_child(_empty)


func _rebuild() -> void:
	if ctx == null:
		return
	_list.clear()
	var fixtures := ctx.fixtures()
	for fx in fixtures:
		var last := fx.start_address + fx.profile.channels.size() - 1
		var i := _list.add_item("%s      U%d · %d–%d" % [fx.name, ctx.universe.universe_id + 1, fx.start_address, last])
		_list.set_item_metadata(i, fx)
		_list.set_item_tooltip(i, String(fx.get_meta(StudioContext.META_PROFILE_LABEL, "")))
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
