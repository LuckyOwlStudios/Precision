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
		DisplayServer.window_start_drag()
	accept_event()
