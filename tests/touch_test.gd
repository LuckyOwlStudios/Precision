extends SceneTree
## Checks touch gestures on the stage view. Run from the project folder:
##   godot --headless --path . --script res://tests/touch_test.gd

var failures := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func _init() -> void:
	test_gestures()
	await test_stage()
	test_theme()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func test_gestures() -> void:
	print("TouchGestures")
	var g := TouchGestures.new()
	g.press(0, Vector2(100, 100))
	check(g.drag(0, Vector2(120, 100)).is_empty(), "one finger is not a gesture")
	g.press(1, Vector2(220, 100))
	var spread: Dictionary = g.drag(1, Vector2(320, 100))
	check(spread["pinch"] > 1.0, "moving apart spreads")
	var pinch: Dictionary = g.drag(1, Vector2(220, 100))
	check(pinch["pinch"] < 1.0, "moving together pinches")
	var pan: Dictionary = g.drag(0, Vector2(120, 140))
	check((pan["pan"] as Vector2).y > 0.0, "dragging down moves the middle down")
	g.release(1)
	check(g.count() == 1, "release drops a finger")


func test_stage() -> void:
	print("stage view")
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	ctx.load_demo_rig()
	ctx.set_workspace(StudioContext.Workspace.STAGE)
	var view: StageView = main.get_node("%StageView")
	root.size = Vector2i(1280, 800)
	await process_frame
	await process_frame
	var d0 := view._distance
	var yaw0 := view._yaw
	var pivot0 := view._pivot.position
	_touch(view, 0, true, Vector2(500, 400))
	_touch(view, 1, true, Vector2(700, 400))
	check(view._touch_locked, "two fingers start a gesture")
	_drag(view, 1, Vector2(900, 400), Vector2(200, 0))
	check(view._distance < d0, "spreading zooms in")
	_drag(view, 0, Vector2(520, 400), Vector2(20, 0))
	check(not is_equal_approx(view._yaw, yaw0), "two-finger drag orbits")
	_touch(view, 2, true, Vector2(600, 500))
	_drag(view, 2, Vector2(700, 500), Vector2(100, 0))
	check(not view._pivot.position.is_equal_approx(pivot0), "three-finger drag pans")
	var emu := InputEventMouseButton.new()
	emu.device = InputEvent.DEVICE_ID_EMULATION
	emu.button_index = MOUSE_BUTTON_LEFT
	emu.pressed = true
	emu.position = Vector2(400, 300)
	view._gui_input(emu)
	check(not view._boxing, "a leftover finger does not start a box")
	for i in 3:
		_touch(view, i, false, Vector2.ZERO)
	check(not view._touch_locked, "gesture ends when all fingers lift")


func test_theme() -> void:
	print("theme")
	var plain := LuckyTheme.build()
	var big := LuckyTheme.build(true)
	check(big.get_stylebox("normal", "Button").get_minimum_size().y
		> plain.get_stylebox("normal", "Button").get_minimum_size().y, "touch buttons are taller")


func _touch(view: StageView, index: int, down: bool, at: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = down
	e.position = at
	view._gui_input(e)


func _drag(view: StageView, index: int, at: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	e.relative = rel
	view._gui_input(e)
