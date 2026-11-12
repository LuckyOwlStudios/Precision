extends SceneTree
## F frames the selection: the orbit pivot moves to it and the camera closes in;
## with nothing selected F still resets to the whole rig. Run from the project folder:
##   godot --headless --path . --script res://tests/frame_selection_test.gd

var failures := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func _find_view(n: Node) -> StageView:
	if n is StageView:
		return n
	for c in n.get_children():
		var v := _find_view(c)
		if v:
			return v
	return null


func press_f(view: StageView) -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_F
	ev.physical_keycode = KEY_F
	ev.pressed = true
	view._gui_input(ev)


func _init() -> void:
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	ctx.load_demo_rig()
	ctx.set_workspace(StudioContext.Workspace.STAGE)
	var view := _find_view(main)
	root.size = Vector2i(1280, 800)
	await process_frame

	var fixtures := ctx.fixtures()
	check(fixtures.size() >= 2, "demo rig has fixtures")
	var pivot: Node3D = view.get_node("%Pivot")

	view._set_selection([fixtures[0]])
	press_f(view)
	var c: Vector3 = (view._visuals[fixtures[0]] as StageFixture3D).center()
	check(pivot.position.distance_to(c) < 0.01, "F centres the pivot on one fixture")
	check(view._distance < 6.0, "camera closes in on one fixture")

	view._set_selection([fixtures[0], fixtures[1]])
	press_f(view)
	var mid := ((view._visuals[fixtures[0]] as StageFixture3D).center() + (view._visuals[fixtures[1]] as StageFixture3D).center()) * 0.5
	check(pivot.position.distance_to(mid) < 0.01, "F centres the pivot between two fixtures")

	view._set_selection([])
	press_f(view)
	check(is_equal_approx(view._distance, 12.5), "F with no selection frames the whole rig")

	view._set_selection([fixtures[0]])
	view._set_flying(true)
	var before := pivot.position
	press_f(view)
	check(pivot.position == before, "F is ignored while flying")
	view._set_flying(false)

	# Close zoom: LEDs are ~1 cm, so the wheel must get within centimetres and the near plane must follow.
	view._set_view("Perspective")
	for i in 80:
		view._zoom(0.9)
	check(is_equal_approx(view._distance, StageView.DISTANCE_MIN) and view._distance < 0.1, "wheel zooms to centimetres")
	check(view.get_node("%Camera").near < view._distance, "near plane stays in front of the pivot")
	var d := view._distance
	view._zoom(0.9)
	view._zoom(1.1)
	view._distance = 1.0
	view._zoom(0.9)
	check(is_equal_approx(view._distance, 0.9), "zoom steps scale with distance")
	view._set_view("Front")
	for i in 80:
		view._zoom(0.9)
	check(is_equal_approx(view._ortho_size, StageView.ORTHO_SIZE_MIN), "drawing view zooms to centimetres")

	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
