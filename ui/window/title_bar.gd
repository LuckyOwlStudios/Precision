class_name TitleBar
extends PanelContainer
## Makes the app's header the window's title bar (the OS title bar is turned
## off in project settings, like IntelliJ's). Empty header space drags the
## window, double-click maximizes or restores it, and a WindowControls node at
## the right end holds minimize / maximize / close.
##
## Anything in the header that should stay clickable (buttons, tabs) simply
## handles its own mouse events; plain labels and spacers have mouse_filter
## Ignore or Pass, so their clicks fall through to this bar.


func _ready() -> void:
	# Window buttons sit flush against the top-right corner, so drop the
	# theme's right padding for this bar only.
	var style := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.content_margin_right = 0.0
	add_theme_stylebox_override("panel", style)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	if mb.double_click:
		WindowControls.toggle_maximized()
	elif DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
		_drag_window()
	accept_event()


## Drag from a maximized window restores it under the cursor first, then the OS
## moves the window. A borderless window doesn't get Windows' own edge snapping,
## so when the drag ends (on Windows the call blocks until the drop) we snap by
## hand: top edge maximizes, left/right edge fills that half of the screen.
func _drag_window() -> void:
	var window := get_window()
	if WindowControls.is_maximized():
		var grab := DisplayServer.mouse_get_position()
		var frac := float(get_global_mouse_position().x) / maxf(size.x, 1.0)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		window.position = Vector2i(grab.x - int(window.size.x * frac), grab.y - int(get_global_mouse_position().y))
	DisplayServer.window_start_drag()
	if OS.get_name() == "Windows":
		_snap_to_screen_edge()


func _snap_to_screen_edge() -> void:
	var window := get_window()
	var mouse := DisplayServer.mouse_get_position()
	var screen := DisplayServer.window_get_current_screen()
	for i in DisplayServer.get_screen_count():
		if DisplayServer.screen_get_usable_rect(i).has_point(mouse):
			screen = i
	var area := DisplayServer.screen_get_usable_rect(screen)
	const EDGE := 4
	if mouse.y <= area.position.y + EDGE:
		window.current_screen = screen
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	elif mouse.x <= area.position.x + EDGE or mouse.x >= area.end.x - EDGE:
		var half := Vector2i(area.size.x / 2, area.size.y)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		window.size = half
		window.position = area.position if mouse.x <= area.position.x + EDGE else Vector2i(area.end.x - half.x, area.position.y)
