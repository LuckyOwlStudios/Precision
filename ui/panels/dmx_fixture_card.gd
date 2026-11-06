class_name DMXFixtureCard
extends PanelContainer
## One fixture's box in the DMX list: name, start address and (when open) all
## of its channels with live values. Click the header to open/close it; that
## also selects the fixture on the stage.

signal header_pressed(card: DMXFixtureCard)
signal hover_changed(card: DMXFixtureCard, hovered: bool)

var fixture: DMXFixture
var color := UIPalette.TEXT_DIM
var open := false
var selected := false

@onready var _header: DMXCardHeader = %Header
@onready var _problem: Label = %Problem
@onready var _problem_box: Control = %ProblemBox
@onready var _rows: VBoxContainer = %Rows

var _style := StyleBoxFlat.new()


func _ready() -> void:
	_style.set_corner_radius_all(UIPalette.RADIUS)
	_style.set_border_width_all(1)
	_style.set_content_margin_all(0)
	add_theme_stylebox_override("panel", _style)
	_header.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			header_pressed.emit(self))
	_header.mouse_entered.connect(func() -> void: hover_changed.emit(self, true))
	_header.mouse_exited.connect(func() -> void: hover_changed.emit(self, false))


func setup(fx: DMXFixture, info: DMXPatchInfo, p_open: bool, p_selected: bool) -> void:
	fixture = fx
	color = info.colors[fx]
	_header.title = StudioContext.display_name(fx)
	_header.range_text = DMXPatchInfo.range_text(fx)
	_header.color = color
	_header.warn = info.has_problem(fx)
	_problem.text = info.problem_text(fx)
	for i in fx.profile.channels.size():
		var row := DMXChannelRow.new()
		row.address = fx.start_address + i
		row.channel_name = String(fx.profile.channels[i]).replace("_", " ")
		row.color = color
		_rows.add_child(row)
	set_state(p_open, p_selected)


func set_state(p_open: bool, p_selected: bool) -> void:
	open = p_open
	selected = p_selected
	_header.open = open
	_header.queue_redraw()
	_rows.visible = open
	_problem_box.visible = open and not _problem.text.is_empty()
	_style.bg_color = UIPalette.RAISED if selected else UIPalette.SIDE_BG.lightened(0.03)
	_style.border_color = UIPalette.ACCENT if selected else UIPalette.HAIRLINE


## Live values; called every frame while the card is open.
func update_values(universe: DMXUniverse, blackout: bool) -> void:
	if not open:
		return
	for row: DMXChannelRow in _rows.get_children():
		row.value = 0 if blackout else universe.get_channel(row.address)
