extends SceneTree
## Swipe-to-scroll and double-tap focus with fingers Run from the project folder:
##   godot --headless --path . --script res://tests/touch_scroll_test.gd

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
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	root.add_child(TouchScroller.new()) # main_window adds one only with a touchscreen
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	ctx.load_demo_rig()
	ctx.set_workspace(StudioContext.Workspace.STAGE)
	root.size = Vector2i(1280, 800)
	for i in 4:
		await process_frame

	var list: ItemList = main.get_node("%OnStage").find_child("List", true, false)
	var bar := list.get_v_scroll_bar()
	check(bar.max_value - bar.page > 1.0, "the fixture list has more rows than fit")
	var mid := list.get_global_rect().get_center()

	print("swipe")
	await _swipe(mid, Vector2(0, -60), 0)
	var after_up := bar.value
	check(after_up > 0.0, "swiping up scrolls the list down")
	await _swipe(mid, Vector2(0, 60), 0)
	check(bar.value < after_up, "swiping down scrolls back")

	bar.value = 0.0
	await _swipe(mid, Vector2(60, 0), 0)
	check(bar.value == 0.0, "a sideways swipe leaves the list alone (drag and drop)")

	await _swipe(mid, Vector2(0, -60), 500)
	check(bar.value == 0.0, "holding still first leaves it alone (drag and drop)")

	await _swipe(mid, Vector2(0, -3), 0)
	check(bar.value == 0.0, "a tap that wobbles does not scroll")

	var inspector: ScrollContainer = main.get_node("%Inspector")
	var sl: Slider = _first_slider(inspector)
	if sl != null and inspector.get_v_scroll_bar().max_value - inspector.get_v_scroll_bar().page > 1.0:
		await _swipe(sl.get_global_rect().get_center(), Vector2(0, -60), 0)
		check(inspector.get_v_scroll_bar().value == 0.0, "a finger on a slider does not scroll")

	print("glide")
	bar.value = 0.0
	await _swipe(mid, Vector2(0, -60), 0, 0.02)
	var at_release := bar.value
	for i in 5:
		await process_frame
	check(bar.value > at_release, "the list keeps gliding after release")

	print("double tap")
	var view: StageView = main.get_node("%StageView")
	var fx := ctx.fixtures()[0]
	var pos := view._camera.unproject_position((view._visuals[fx] as StageFixture3D).center())
	var dist0 := view._distance
	ctx.select(null)
	view._on_left_press(_click(pos, true, true))
	check(view._distance < dist0, "double-tapping a fixture frames it")
	var before_mouse := view._distance
	view._distance = 15.0
	view._on_left_press(_click(pos, false, true))
	check(is_equal_approx(view._distance, 15.0), "a mouse double-click still renames, not frames")

	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _click(at: Vector2, finger: bool, double: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.device = InputEvent.DEVICE_ID_EMULATION if finger else 0
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.double_click = double
	e.position = at
	return e


func _first_slider(n: Node) -> Slider:
	if n is Slider and (n as Slider).is_visible_in_tree():
		return n
	for c in n.get_children():
		var s := _first_slider(c)
		if s != null:
			return s
	return null


## One finger down, `total` px of movement over ten steps, then up. `rest` ms
## before it starts moving. `step_delay` > 0 makes the drag fast, so it has speed.
func _swipe(start: Vector2, total: Vector2, rest_msec: int, _speed := 0.0) -> void:
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.pressed = true
	t.position = start
	Input.parse_input_event(t)
	await process_frame
	if rest_msec > 0:
		OS.delay_msec(rest_msec)
	var p := start
	for i in 10:
		var step := total / 10.0
		p += step
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = p
		d.relative = step
		d.velocity = step * 60.0
		Input.parse_input_event(d)
		await process_frame
	var r := InputEventScreenTouch.new()
	r.index = 0
	r.pressed = false
	r.position = p
	Input.parse_input_event(r)
	await process_frame
