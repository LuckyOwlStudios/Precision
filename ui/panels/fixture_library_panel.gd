class_name FixtureLibraryPanel
extends MarginContainer
## Fixture library: search, then drag a fixture onto the 3D stage
## (or double-click it to hang it centre stage). The Structure group holds the
## truss pieces (res://structure/pieces): drag them onto the stage to build a set.

var ctx: StudioContext

var _entries: Array[FixtureCatalog.Entry] = []
var _pieces: Array[StructureCatalog.Entry] = []

@onready var _search: LineEdit = %Search
@onready var _tree: Tree = %Tree
@onready var _editor: ProfileEditor = %ProfileEditor
@onready var _menu: PopupMenu = %ProfileMenu
@onready var _confirm: ConfirmationDialog = %ConfirmDelete

var _menu_entry: FixtureCatalog.Entry ## the "My fixtures" profile the menu is for


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx


func _ready() -> void:
	_search.text_changed.connect(func(_t: String) -> void: _rebuild())
	_tree.set_drag_forwarding(_get_drag, Callable(), Callable())
	_tree.item_activated.connect(_on_activated)
	%AddButton.pressed.connect(new_profile)
	_editor.saved.connect(func(profile: FixtureProfile) -> void: reload(profile))
	_tree.item_mouse_selected.connect(_on_item_mouse_selected)
	_menu.id_pressed.connect(_on_menu)
	_confirm.confirmed.connect(_on_delete_confirmed)
	_pieces = StructureCatalog.entries()
	reload()


## Opens the profile editor on a blank profile.
func new_profile() -> void:
	_editor.open_new()


## Re-reads the catalog (after a profile was saved or deleted). `select` is a
## just-saved profile to highlight.
func reload(select: FixtureProfile = null) -> void:
	_entries = FixtureCatalog.entries()
	_rebuild()
	if select == null:
		return
	for g in _tree.get_root().get_children():
		for item in g.get_children():
			var meta: Variant = item.get_metadata(0)
			if meta is int and _entries[int(meta)].profile.fixture_name == select.fixture_name:
				item.select(0)
				_tree.scroll_to_item(item)
				return


func _on_item_mouse_selected(at: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT:
		return
	var e := _selected_entry()
	if e == null or e.category != FixtureCatalog.USER_CATEGORY:
		return
	_menu_entry = e
	_menu.position = Vector2i(_tree.get_screen_position() + at)
	_menu.popup()


func _on_menu(id: int) -> void:
	if _menu_entry == null:
		return
	if id == 0:
		_editor.open_edit(_menu_entry.profile)
	else:
		_confirm.dialog_text = "Delete \"%s\"? Fixtures already on the stage keep working." % _menu_entry.profile.fixture_name
		_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	if _menu_entry != null and ProfileStore.delete(_menu_entry.profile):
		reload()


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
		item.set_tooltip_text(0, "%d channels: %s" % [e.profile.channels.size(), e.profile.summary()]
				+ ("\nRight-click to edit or delete." if e.category == FixtureCatalog.USER_CATEGORY else ""))
		item.set_metadata(0, i)
	var structure: TreeItem = null
	for i in _pieces.size():
		var p := _pieces[i]
		if not query.is_empty() and not p.display_name.to_lower().contains(query) and not "structure truss".contains(query):
			continue
		if structure == null:
			structure = _tree.create_item(root)
			structure.set_text(0, "STRUCTURE")
			structure.set_selectable(0, false)
			structure.set_custom_color(0, UIPalette.TEXT_FAINT)
			structure.set_custom_font_size(0, UIPalette.FONT_SIZE_SMALL)
		var item := _tree.create_item(structure)
		item.set_text(0, p.display_name)
		item.set_tooltip_text(0, "Drag onto the stage: base plates go on the floor, truss and corner boxes snap onto a free truss end, plate or corner face.")
		item.set_metadata(0, {"piece": i})


func _selected_entry() -> FixtureCatalog.Entry:
	var item := _tree.get_selected()
	if item == null or not (item.get_metadata(0) is int):
		return null
	return _entries[int(item.get_metadata(0))]


func _get_drag(at: Vector2) -> Variant:
	var item := _tree.get_item_at_position(at)
	if item == null or item.get_metadata(0) == null:
		return null
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary:
		var piece := _pieces[int((meta as Dictionary)["piece"])]
		var label := Button.new()
		label.text = piece.display_name
		label.theme_type_variation = &"AccentButton"
		_tree.set_drag_preview(label)
		return {"kind": "structure", "path": piece.path}
	var entry := _entries[int(meta)]
	var preview := Button.new()
	preview.text = entry.profile.fixture_name
	preview.theme_type_variation = &"AccentButton"
	_tree.set_drag_preview(preview)
	return {"kind": "fixture", "entry": entry}


func _on_activated() -> void:
	var e := _selected_entry()
	if e and ctx:
		# Clamp it onto the front truss, centre stage.
		ctx.hang_fixture(e, StudioContext.FRONT_TRUSS_TUBE)
