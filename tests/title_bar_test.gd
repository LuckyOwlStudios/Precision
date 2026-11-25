extends SceneTree
## Checks the custom title bar: window buttons exist, empty header space is
## draggable (not swallowed by a child), and the resize handles are in place.
## Run from the project folder:
##   godot --headless --path . --script res://tests/title_bar_test.gd

var failures := 0


func check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func _init() -> void:
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	check(ProjectSettings.get_setting("display/window/size/borderless") == true, "OS title bar is off")
	check(main.find_child("Header", true, false) is TitleBar, "header is the title bar")
	var controls := main.find_child("WindowControls", true, false) as WindowControls
	check(controls != null and controls.get_child_count() == 3, "minimize, maximize and close buttons")
	for n in ["DragSpaceLeft", "DragSpaceRight"]:
		var c := main.find_child(n, true, false) as Control
		check(c != null and c.mouse_filter == Control.MOUSE_FILTER_PASS, n + " passes clicks to the title bar")
	var handles := main.find_child("ResizeHandles", true, false)
	check(handles != null and handles.get_child_count() == 8, "eight resize handles")
	quit(1 if failures > 0 else 0)
