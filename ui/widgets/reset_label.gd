class_name ResetLabel
extends Label
## A setting's name that doubles as its reset button, like a slider caption in
## a pro app. While the setting is at its default it is a plain label. Once the
## value is changed (`modified = true`) it lights up a little, shows a hand
## cursor, turns amber on hover, and clicking it emits `reset_requested`.
##
## The label does not know the value or the default: the owner listens for
## `reset_requested`, puts the default back, and sets `modified` again.
##   label.reset_requested.connect(func() -> void: look.haze = StageLook.DEFAULT_HAZE)
##   label.modified = not is_equal_approx(look.haze, StageLook.DEFAULT_HAZE)

signal reset_requested

## Read in the tooltip while modified, e.g. "45%" gives "Click to reset to 45%".
@export var default_text: String = "default"

## True while the setting differs from its default: only then is it clickable.
var modified: bool = false:
	set(v):
		if modified == v:
			return
		modified = v
		_refresh()

var _hovered: bool = false
var _plain_tooltip: String


func _ready() -> void:
	_plain_tooltip = tooltip_text
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	_refresh()


func _gui_input(event: InputEvent) -> void:
	if not modified:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		accept_event()
		reset_requested.emit()


func _set_hovered(on: bool) -> void:
	_hovered = on
	_refresh()


func _refresh() -> void:
	# Plain label at default: let clicks fall through and keep the theme colour.
	mouse_filter = Control.MOUSE_FILTER_STOP if modified else Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if modified else Control.CURSOR_ARROW
	tooltip_text = (tr("Click to reset to %s") % default_text) if modified else _plain_tooltip
	if modified and _hovered:
		add_theme_color_override("font_color", UIPalette.ACCENT)
	elif modified:
		add_theme_color_override("font_color", UIPalette.TEXT_DIM)
	else:
		remove_theme_color_override("font_color")
