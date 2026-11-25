class_name WindowControls
extends HBoxContainer
## Minimize, maximize/restore and close buttons for the borderless window.

## The close button was pressed. The main window answers by asking about unsaved
## changes, same as when the OS asks the window to close.
signal close_requested

@onready var _minimize: WindowButton = %Minimize
@onready var _maximize: WindowButton = %Maximize
@onready var _close: WindowButton = %Close


func _ready() -> void:
	_minimize.pressed.connect(func() -> void: DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED))
	_maximize.pressed.connect(toggle_maximized)
	_close.pressed.connect(close_requested.emit)
	get_window().size_changed.connect(_update_icons)
	_update_icons()


static func is_maximized() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_MAXIMIZED or mode == DisplayServer.WINDOW_MODE_FULLSCREEN


static func toggle_maximized() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_maximized() else DisplayServer.WINDOW_MODE_MAXIMIZED)


func _update_icons() -> void:
	_maximize.glyph = WindowButton.Glyph.RESTORE if is_maximized() else WindowButton.Glyph.MAXIMIZE
	_maximize.tooltip_text = "Restore" if is_maximized() else "Maximize"
