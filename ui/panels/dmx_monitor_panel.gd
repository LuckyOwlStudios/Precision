class_name DMXMonitorPanel
extends MarginContainer
## The universe, made easy to read: a map of all 512 addresses on top, then one
## box per fixture with its channels and live values. Fixtures that share
## addresses are flagged in red. Selecting a fixture here or on the stage
## selects it in both places.

const CARD_SCENE := preload("res://ui/panels/dmx_fixture_card.tscn")

var ctx: StudioContext

var _info: DMXPatchInfo
var _cards: Dictionary = {}    ## DMXFixture -> DMXFixtureCard
var _open: Dictionary = {}     ## DMXFixture -> true; remembered across rebuilds
var _hovered: DMXFixture
var _last_status := ""
var _window: Window ## the pop-out window while the panel is undocked
var _dock: Node ## where the panel lives when docked (a tab of the right dock)
var _dock_index := 0

@onready var _overview: DMXOverview = %Overview
@onready var _status: Label = %Status
@onready var _hint: Label = %Hint
@onready var _problems: Label = %Problems
@onready var _scroll: ScrollContainer = %Scroll
@onready var _list: GridContainer = %Cards
@onready var _empty: Label = %Empty
@onready var _pop_out: Button = %PopOut
@onready var _fix_button: Button = %FixOverlaps
@onready var _pack_button: Button = %Pack

const CARD_MIN_WIDTH := 250.0


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.fixtures_changed.connect(_rebuild)
	ctx.selection_changed.connect(_on_selection_changed)
	_overview.slot_hovered.connect(_on_slot_hovered)
	_overview.fixture_clicked.connect(_on_overview_clicked)
	_overview.fixture_moved.connect(func(fx: DMXFixture, start: int) -> void: ctx.set_address(fx, start))
	_fix_button.pressed.connect(func() -> void: ctx.fix_overlaps())
	_pack_button.pressed.connect(func() -> void: ctx.pack_addresses())
	_pop_out.pressed.connect(_toggle_pop_out)
	_scroll.resized.connect(_update_columns)
	_rebuild()


func _rebuild() -> void:
	if ctx == null:
		return
	var fixtures := ctx.fixtures()
	_info = DMXPatchInfo.build(fixtures)
	# Same fixtures as before (a re-patch or rename): update the cards in place.
	if fixtures.size() == _cards.size() and fixtures.all(func(fx: DMXFixture) -> bool: return _cards.has(fx)):
		for fx in fixtures:
			(_cards[fx] as DMXFixtureCard).refresh(_info)
		_overview.info = _info
		_update_problems()
		_overview.queue_redraw()
		return
	for card: Node in _list.get_children():
		_list.remove_child(card)
		card.queue_free()
	_cards.clear()
	_overview.info = _info
	_empty.visible = _info.fixtures.is_empty()
	for fx in _info.fixtures:
		var card: DMXFixtureCard = CARD_SCENE.instantiate()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_child(card)
		card.setup(fx, _info, _open.has(fx), fx == ctx.selected)
		card.header_pressed.connect(_on_header_pressed)
		card.hover_changed.connect(_on_card_hover)
		card.address_edited.connect(func(c: DMXFixtureCard, a: int) -> void: ctx.set_address(c.fixture, a))
		_cards[fx] = card
	_open = _open.duplicate() # keep only fixtures that still exist
	for fx: Object in _open.keys():
		if not is_instance_valid(fx) or not _cards.has(fx):
			_open.erase(fx)
	_update_problems()
	_update_focus()
	_overview.queue_redraw()


func _update_problems() -> void:
	var n := 0
	for fx in _info.fixtures:
		if _info.has_problem(fx):
			n += 1
	_problems.text = "%d fixture%s share channels. Red squares and red ! badges show where; give each its own address range." % [n, "" if n == 1 else "s"]
	_problems.visible = n > 0
	_fix_button.visible = n > 0
	_pack_button.visible = _info.fixtures.size() > 1


func _on_header_pressed(card: DMXFixtureCard) -> void:
	var fx := card.fixture
	if ctx.selected == fx:
		_set_open(fx, not card.open) # clicking the selected box folds it
	else:
		_open[fx] = true
		ctx.select(fx) # the selection handler opens it
		card.set_state(true, true)


func _set_open(fx: DMXFixture, value: bool) -> void:
	if value:
		_open[fx] = true
	else:
		_open.erase(fx)
	if _cards.has(fx):
		(_cards[fx] as DMXFixtureCard).set_state(value, ctx.selected == fx)


func _on_selection_changed(fx: DMXFixture) -> void:
	for other: DMXFixture in _cards:
		var card: DMXFixtureCard = _cards[other]
		card.set_state(_open.has(other) or other == fx, other == fx)
		if other == fx:
			_open[fx] = true
	_update_focus()
	if fx and _cards.has(fx):
		_scroll_to.call_deferred(_cards[fx])


func _scroll_to(card: Control) -> void:
	if is_instance_valid(card) and is_visible_in_tree():
		_scroll.ensure_control_visible(card)


func _on_card_hover(card: DMXFixtureCard, hovered: bool) -> void:
	_hovered = card.fixture if hovered else null
	_update_focus()


func _on_overview_clicked(fx: DMXFixture) -> void:
	ctx.select(fx)


func _update_focus() -> void:
	_overview.focus = _hovered if _hovered else ctx.selected


func _on_slot_hovered(address: int) -> void:
	_hovered = _info.first_owner(address) if address > 0 else null
	_update_focus()
	if address == 0:
		_hint.text = "Drag a fixture along the map to move it. Hover a square to see who owns it."
		return
	var list: Array = _info.owners[address]
	if list.is_empty():
		_hint.text = "Ch %d · free" % address
		return
	var names: PackedStringArray = []
	for fx: DMXFixture in list:
		names.append("%s · %s" % [StudioContext.display_name(fx), fx.profile.channels[address - fx.start_address]])
	_hint.text = "Ch %d · %s" % [address, "  AND  ".join(names)]


func _process(_delta: float) -> void:
	if ctx == null or not is_visible_in_tree():
		return
	for fx: DMXFixture in _cards:
		(_cards[fx] as DMXFixtureCard).update_values(ctx.universe, ctx.blackout)
	var text := "%d of 512 channels used, %d free. Art-Net to %s at %d Hz.%s" % [
		_info.used_count, 512 - _info.used_count, ctx.output.target_ip, int(ctx.universe.refresh_rate),
		" BLACKOUT is on." if ctx.blackout else ""]
	if text != _last_status:
		_last_status = text
		_status.text = text


## Cards flow into as many columns as fit: one in the narrow dock, several in a wide window.
func _update_columns() -> void:
	_list.columns = clampi(int(_scroll.size.x / CARD_MIN_WIDTH), 1, 6)


## Move the whole panel into its own resizable window, or back into the dock.
func _toggle_pop_out() -> void:
	if _window:
		_dock_back()
		return
	_dock = get_parent()
	_dock_index = get_index()
	var host := _dock.get_parent()
	_window = Window.new()
	_window.title = "DMX universe"
	_window.size = Vector2i(760, 660)
	_window.min_size = Vector2i(300, 320)
	_window.wrap_controls = false
	_window.close_requested.connect(_dock_back)
	var backdrop := ColorRect.new()
	backdrop.color = UIPalette.SIDE_BG
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.add_child(backdrop)
	host.add_child(_window)
	_dock.remove_child(self)
	_window.add_child(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_window.popup_centered()
	_pop_out.text = "Dock"


func _dock_back() -> void:
	if _window == null:
		return
	_window.remove_child(self)
	_dock.add_child(self)
	_dock.move_child(self, _dock_index)
	if _dock is TabContainer:
		(_dock as TabContainer).set_tab_title(_dock_index, "DMX")
		(_dock as TabContainer).current_tab = _dock_index
	_window.queue_free()
	_window = null
	_pop_out.text = "Pop out"
