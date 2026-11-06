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

@onready var _overview: DMXOverview = %Overview
@onready var _status: Label = %Status
@onready var _hint: Label = %Hint
@onready var _problems: Label = %Problems
@onready var _scroll: ScrollContainer = %Scroll
@onready var _list: VBoxContainer = %Cards
@onready var _empty: Label = %Empty


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.fixtures_changed.connect(_rebuild)
	ctx.selection_changed.connect(_on_selection_changed)
	_overview.slot_hovered.connect(_on_slot_hovered)
	_overview.fixture_clicked.connect(_on_overview_clicked)
	_rebuild()


func _rebuild() -> void:
	if ctx == null:
		return
	for card: Node in _list.get_children():
		_list.remove_child(card)
		card.queue_free()
	_cards.clear()
	_info = DMXPatchInfo.build(ctx.fixtures())
	_overview.info = _info
	_empty.visible = _info.fixtures.is_empty()
	for fx in _info.fixtures:
		var card: DMXFixtureCard = CARD_SCENE.instantiate()
		_list.add_child(card)
		card.setup(fx, _info, _open.has(fx), fx == ctx.selected)
		card.header_pressed.connect(_on_header_pressed)
		card.hover_changed.connect(_on_card_hover)
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
		_hint.text = "Hover a square to see which fixture owns it. Click to select."
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
