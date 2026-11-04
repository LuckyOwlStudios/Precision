class_name FixtureLibraryPanel
extends MarginContainer
## Fixture library: search, then drag a fixture onto the 3D stage
## (or double-click it to hang it centre stage).

var ctx: StudioContext

var _search := LineEdit.new()
var _tree := Tree.new()
var _entries: Array[FixtureCatalog.Entry] = []


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx


func _ready() -> void:
	add_theme_constant_override("margin_left", UIPalette.COLUMN_PAD)
	add_theme_constant_override("margin_right", UIPalette.COLUMN_PAD)
	add_theme_constant_override("margin_top", 16)
	add_theme_constant_override("margin_bottom", 8)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	var head := UIKit.section("Fixtures", "+", "Add a fixture profile (coming soon)")
	(head.get_meta("action") as Button).disabled = true
	col.add_child(head)

	_search.placeholder_text = "Search fixtures"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _rebuild())
	col.add_child(_search)

	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.select_mode = Tree.SELECT_ROW
	_tree.set_drag_forwarding(_get_drag, Callable(), Callable())
	_tree.item_activated.connect(_on_activated)
	col.add_child(_tree)

	var hint := Label.new()
	hint.text = "Drag onto the stage, or double-click to hang centre stage."
	hint.theme_type_variation = &"Caption"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	_entries = FixtureCatalog.entries()
	_rebuild()


func _rebuild() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var query := _search.text.strip_edges().to_lower()
	var groups: Dictionary = {}
	for i in _entries.size():
		var e := _entries[i]
		if not query.is_empty() and not e.profile.fixture_name.to_lower().contains(query) and not e.category.to_lower().contains(query):
			continue
		if not groups.has(e.category):
			var g := _tree.create_item(root)
			g.set_text(0, e.category.to_upper())
			g.set_selectable(0, false)
			g.set_custom_color(0, UIPalette.TEXT_FAINT)
			g.set_custom_font_size(0, UIPalette.FONT_SIZE_SMALL)
			groups[e.category] = g
		var item := _tree.create_item(groups[e.category])
		item.set_text(0, e.profile.fixture_name)
		item.set_tooltip_text(0, "%d channels: %s" % [e.profile.channels.size(), ", ".join(e.profile.channels)])
		item.set_metadata(0, i)


func _selected_entry() -> FixtureCatalog.Entry:
	var item := _tree.get_selected()
	if item == null or item.get_metadata(0) == null:
		return null
	return _entries[int(item.get_metadata(0))]


func _get_drag(at: Vector2) -> Variant:
	var item := _tree.get_item_at_position(at)
	if item == null or item.get_metadata(0) == null:
		return null
	var entry := _entries[int(item.get_metadata(0))]
	var preview := Button.new()
	preview.text = entry.profile.fixture_name
	preview.theme_type_variation = &"AccentButton"
	_tree.set_drag_preview(preview)
	return {"kind": "fixture", "entry": entry}


func _on_activated() -> void:
	var e := _selected_entry()
	if e and ctx:
		# Hang it under the front truss, centre stage.
		ctx.add_fixture(e, Vector3(0, StageRoom.TRUSS_BOTTOM - StageFixture3D.mount_offset(e.body), StageRoom.TRUSS_Z[0]))
