extends SceneTree
## Checks multi-selection from the On stage list (range and toggle land on the stage
## and in the inspector's group) and Ctrl+click on the 3D stage. Run from the project folder:
##   godot --headless --path . --script res://tests/range_select_test.gd

var failures := 0
var checks := 0
var view: StageView
var ctx: StudioContext
var panel: RigPanel


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
	await process_frame
	ctx = main.get_node("%Studio")
	ctx.load_demo_rig()
	ctx.set_workspace(StudioContext.Workspace.STAGE)
	view = _find(main, "StageView") as StageView
	panel = _find(main, "RigPanel") as RigPanel
	root.size = Vector2i(1280, 800)
	await process_frame
	await process_frame
	await test_list()
	await test_ctrl_click()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls or (n.get_script() and (n.get_script() as Script).get_global_name() == cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f:
			return f
	return null


func test_list() -> void:
	print("On stage list")
	var list: ItemList = panel.get_node("%List")
	check(list.select_mode == ItemList.SELECT_MULTI, "the list allows Shift range and Ctrl toggle")
	var fixtures := ctx.fixtures()
	# What a Shift+click from row 1 to row 3 leaves in the list.
	list.deselect_all()
	for i in range(1, 4):
		list.select(i, false)
	list.multi_selected.emit(3, true)
	await process_frame
	await process_frame
	check(ctx.selected_group.size() == 3, "a range of three rows selects three fixtures on the stage (%d)" % ctx.selected_group.size())
	check(ctx.selected_group.has(fixtures[1]) and ctx.selected_group.has(fixtures[3]), "the ends are in it")
	check(view._group.size() == 3, "the stage view shows the same group")
	# Ctrl+click on row 5 adds it.
	list.select(5, false)
	list.multi_selected.emit(5, true)
	await process_frame
	await process_frame
	check(ctx.selected_group.size() == 4 and ctx.selected_group.has(fixtures[5]), "Ctrl+click adds one more")
	# Ctrl+click on row 2 takes it out.
	list.deselect(2)
	list.multi_selected.emit(2, false)
	await process_frame
	await process_frame
	check(ctx.selected_group.size() == 3 and not ctx.selected_group.has(fixtures[2]), "Ctrl+click on a selected row removes it")
	# Selecting on the stage lights the rows.
	ctx.pick([fixtures[0]])
	await process_frame
	check(ctx.selected == fixtures[0] and list.get_selected_items() == PackedInt32Array([0]), "picking one on the stage highlights its row alone")
	ctx.pick([fixtures[2], fixtures[4]])
	await process_frame
	check(list.get_selected_items() == PackedInt32Array([2, 4]), "a group on the stage highlights all its rows")
	ctx.pick([])
	await process_frame
	check(list.get_selected_items().is_empty() and ctx.selected == null and ctx.selected_group.is_empty(), "picking none clears everything")


func test_ctrl_click() -> void:
	print("Ctrl+click on the stage")
	view.get_parent().remove_child(view)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	holder.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_orbit(0.0, -14.0, 16.0)
	for i in 5:
		await process_frame
	var fixtures := ctx.fixtures()
	var a := _screen_of(fixtures[0])
	var b := _screen_of(fixtures[1])
	view._set_selection([])
	_click(a, false)
	check(ctx.selected == fixtures[0], "plain click selects one")
	_click(b, true)
	check(ctx.selected_group.size() == 2 and ctx.selected_group.has(fixtures[0]) and ctx.selected_group.has(fixtures[1]), "Ctrl+click adds a second")
	_click(a, true)
	check(ctx.selected == fixtures[1] and ctx.selected_group.is_empty(), "Ctrl+click on a member takes it out, leaving one")
	_click(a, true)
	_click(b, true)
	check(ctx.selected == fixtures[0] and ctx.selected_group.is_empty(), "adding one back then removing the other leaves just that one")


func _screen_of(fx: DMXFixture) -> Vector2:
	var v: StageFixture3D = view._visuals[fx]
	return view._camera.unproject_position(v.center())


func _click(at: Vector2, ctrl: bool) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		ev.ctrl_pressed = ctrl
		view._gui_input(ev)
