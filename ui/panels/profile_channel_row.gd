class_name ProfileChannelRow
extends HBoxContainer
## One line of the profile editor's channel chart: address, name, quick-pick
## menu, fixed value, and move/delete. A "pixel run" line stands for many
## channels at once ("28 pixels x (red, green, blue, white)").

signal name_changed(text: String)
signal default_changed(value: int)
signal move_requested(direction: int)
signal delete_requested

## Common names offered in the ▾ menu; the first group is what DMXFixture drives.
const QUICK_NAMES: PackedStringArray = ["dimmer", "red", "green", "blue", "white", "amber", "uv",
		"strobe", "pan", "pan_fine", "tilt", "tilt_fine", "-", "mode", "speed", "macro", "color_wheel", "gobo", "zoom", "focus"]

@onready var _address: Label = %Address
@onready var _name: LineEdit = %NameEdit
@onready var _presets: MenuButton = %Presets
@onready var _default: SpinBox = %Default
@onready var _summary: Label = %Summary


func _ready() -> void:
	var menu := _presets.get_popup()
	for n in QUICK_NAMES:
		if n == "-":
			menu.add_separator()
		else:
			menu.add_item(n)
	menu.index_pressed.connect(func(i: int) -> void:
		_name.text = menu.get_item_text(i)
		_name.text_changed.emit(_name.text))
	_name.text_changed.connect(func(t: String) -> void:
		_sync_default_visibility()
		name_changed.emit(t))
	_default.value_changed.connect(func(v: float) -> void: default_changed.emit(int(v)))
	%Up.pressed.connect(func() -> void: move_requested.emit(-1))
	%Down.pressed.connect(func() -> void: move_requested.emit(1))
	%Delete.pressed.connect(func() -> void: delete_requested.emit())


## Shows an ordinary channel.
func show_channel(channel_name: String, default_value: int) -> void:
	_summary.visible = false
	_name.visible = true
	_presets.visible = true
	_name.text = channel_name
	_default.set_value_no_signal(default_value)
	_sync_default_visibility()


## Shows a pixel run instead of a single channel.
func show_pixels(text: String) -> void:
	_summary.visible = true
	_summary.text = text
	_name.visible = false
	_presets.visible = false
	_default.visible = false


func set_address_text(text: String) -> void:
	_address.text = text


func set_problem(has_problem: bool) -> void:
	_name.modulate = UIPalette.LIVE if has_problem else Color.WHITE


func focus_name() -> void:
	_name.grab_focus()
	_name.select_all()


## Only channels DMXFixture doesn't drive (mode, speed, gobo...) can hold a fixed value.
func _sync_default_visibility() -> void:
	_default.visible = not ProfileImport.STANDARD.has(_name.text.strip_edges()) and not _name.text.strip_edges().is_empty()
