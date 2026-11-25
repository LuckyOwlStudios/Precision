class_name ResizeHandle
extends Control
## A thin strip along a window edge or corner. Since the window has no OS
## frame, dragging one of these asks the OS to start a native resize.

@export var edge := DisplayServer.WINDOW_EDGE_LEFT


func _ready() -> void:
	mouse_default_cursor_shape = _cursor()
	# Hidden while maximized or fullscreen: nothing to resize then.
	get_window().size_changed.connect(_update_visible)
	_update_visible()


func _update_visible() -> void:
	visible = not WindowControls.is_maximized()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		DisplayServer.window_start_resize(edge as DisplayServer.WindowResizeEdge)
		accept_event()


func _cursor() -> Control.CursorShape:
	match edge:
		DisplayServer.WINDOW_EDGE_LEFT, DisplayServer.WINDOW_EDGE_RIGHT:
			return Control.CURSOR_HSIZE
		DisplayServer.WINDOW_EDGE_TOP, DisplayServer.WINDOW_EDGE_BOTTOM:
			return Control.CURSOR_VSIZE
		DisplayServer.WINDOW_EDGE_TOP_LEFT, DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT:
			return Control.CURSOR_FDIAGSIZE
		_:
			return Control.CURSOR_BDIAGSIZE
