extends SceneTree
## Checks box select on the 3D stage: dragging on empty space, deleting and
## moving the group as one undo step, base plate highlight, and that a dropped
## truss piece isn't left selected. Run from the project folder:
##   godot --headless --path . --script res://tests/box_select_test.gd

var failures := 0
var checks := 0
var view: StageView
var ctx: StudioContext


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
	view = _find_view(main)
	root.size = Vector2i(1280, 800)
	view.get_parent().remove_child(view)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	holder.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_orbit(0.0, -14.0, 16.0)
	await frames(5)

	test_base_plate_highlight()
	test_box_everything()
	test_shift_adds_and_click_clears()
	test_group_move()
	test_drop_not_selected()
	test_program_workspace()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func press(at: Vector2, down: bool, shift := false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = at
	ev.shift_pressed = shift
	view._gui_input(ev)


func move(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	view._gui_input(ev)


func drag(from: Vector2, to: Vector2, shift := false) -> void:
	press(from, true, shift)
	for i in range(1, 6):
		move(from.lerp(to, i / 5.0))
	press(to, false, shift)


func key(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.pressed = true
	view._gui_input(ev)


func overlay_on(p: StructurePiece) -> bool:
	for n in p.find_children("*", "GeometryInstance3D", true, false):
		if (n is MeshInstance3D or (n is CSGShape3D and (n as CSGShape3D).is_root_shape())) \
				and (n as GeometryInstance3D).material_overlay != null:
			return true
	return false


func test_base_plate_highlight() -> void:
	print("base plate highlight")
	var plate: StructurePiece = view._set.get_node("PlateFrontLeft")
	view._select_piece(plate)
	check(overlay_on(plate), "a selected base plate gets the tint like truss does")
	view._select_piece(null)
	check(not overlay_on(plate), "and loses it when deselected")


func test_box_everything() -> void:
	print("box everything, delete, undo")
	var fixtures := ctx.fixtures()
	var pieces := view._pieces()
	var order: Array[String] = []
	for fx in fixtures:
		order.append(String(fx.name))
	drag(Vector2(2, 2), Vector2(view.size) - Vector2(2, 2))
	check(view._group.size() == fixtures.size() + pieces.size(),
		"a box over the whole view picks every fixture and piece (%d of %d)" % [view._group.size(), fixtures.size() + pieces.size()])
	check(ctx.selected == null and not view._box_select.visible, "no single selection; box hidden after release")
	check(view._group.all(func(o: Object) -> bool: return o is DMXFixture or overlay_on(o)), "every picked piece is tinted")
	key(KEY_DELETE)
	check(ctx.fixtures().is_empty() and view._pieces().is_empty(), "Delete removes all of them")
	ctx.undo()
	var back: Array[String] = []
	for fx in ctx.fixtures():
		back.append(String(fx.name))
	check(back == order, "one undo brings every fixture back in its place in the rig")
	check(view._pieces().size() == pieces.size(), "and every piece")
	check(view._group.size() == fixtures.size() + pieces.size(), "and selects them again")
	ctx.redo()
	check(ctx.fixtures().is_empty() and view._pieces().is_empty(), "redo deletes them again")
	ctx.undo()
	key(KEY_ESCAPE)
	check(view._group.is_empty() and not view._pieces().any(overlay_on), "Esc clears the selection")


func test_shift_adds_and_click_clears() -> void:
	print("shift adds, click clears")
	var cam := view._camera
	var fxs := ctx.fixtures()
	var a := cam.unproject_position((view._visuals[fxs[0]] as StageFixture3D).center())
	var b := cam.unproject_position((view._visuals[fxs[3]] as StageFixture3D).center())
	drag(a - Vector2(8, 8), a + Vector2(8, 8))
	check(ctx.selected == fxs[0] and view._group.is_empty(), "a box around one fixture selects just it, as a click would")
	drag(b + Vector2(-8, 40), b + Vector2(8, -8), true) # from the empty air under it, not the truss
	check(view._group.size() == 2 and view._group.has(fxs[0]) and view._group.has(fxs[3]), "Shift + box adds another")
	press(Vector2(view.size.x - 4, view.size.y * 0.5), true)
	press(Vector2(view.size.x - 4, view.size.y * 0.5), false)
	check(view._group.is_empty() and ctx.selected == null, "a click on empty space clears it")


func test_group_move() -> void:
	print("move the group")
	var cam := view._camera
	var fxs := ctx.fixtures()
	var bars: Array[DMXFixture] = [fxs[6], fxs[7]] # the two floor bars
	view._set_selection(bars)
	var before: Array[Vector3] = [StudioContext.fixture_transform(bars[0]).origin, StudioContext.fixture_transform(bars[1]).origin]
	var at := cam.unproject_position((view._visuals[bars[0]] as StageFixture3D).center())
	check(view._pick_at(at) == bars[0], "the first bar is under the cursor")
	drag(at, at + Vector2(120, 0))
	var d0 := StudioContext.fixture_transform(bars[0]).origin - before[0]
	var d1 := StudioContext.fixture_transform(bars[1]).origin - before[1]
	check(d0.length() > 0.3 and d0.is_equal_approx(d1), "dragging one moves both by the same amount (%s)" % d0)
	check(is_zero_approx(d0.y), "keeping their height")
	ctx.undo()
	check(StudioContext.fixture_transform(bars[0]).origin.is_equal_approx(before[0])
		and StudioContext.fixture_transform(bars[1]).origin.is_equal_approx(before[1]), "one undo puts both back")
	press(at, true)
	press(at, false)
	check(ctx.selected == bars[0] and view._group.is_empty(), "a click on a member picks just that one")
	ctx.select(null)


func test_drop_not_selected() -> void:
	print("dropping a truss piece")
	var cam := view._camera
	view._drop_piece(cam.unproject_position(Vector3(0, 0, 2.5)), "res://structure/pieces/base_plate.tscn")
	var plate: StructurePiece = view._pieces()[view._pieces().size() - 1]
	check(plate.global_position.distance_to(Vector3(0, 0, 2.5)) < 0.3, "a base plate drops on the floor")
	check(view._selected_piece == null and not overlay_on(plate), "and isn't left selected or tinted")
	var before := view._pieces().size()
	view._drop_piece(cam.unproject_position(plate.global_position + Vector3(0, 0.3, 0)), "res://structure/pieces/truss_1m.tscn")
	var pieces := view._pieces()
	check(pieces.size() == before + 1, "the piece is placed")
	var placed: StructurePiece = pieces[pieces.size() - 1]
	check(placed.global_position.distance_to(plate.global_position) < 1.0, "the truss stands on the new plate")
	check(view._selected_piece == null and not overlay_on(placed), "and it isn't left selected or tinted")
	ctx.undo()
	check(view._pieces().size() == before, "undo takes it away")
	ctx.redo()
	check(view._selected_piece == null and not overlay_on(placed), "redo puts it back untinted")
	ctx.undo()
	ctx.undo()


func test_program_workspace() -> void:
	print("program workspace")
	ctx.set_workspace(StudioContext.Workspace.PROGRAM)
	drag(Vector2(2, 2), Vector2(view.size) - Vector2(2, 2))
	check(view._group.size() == ctx.fixtures().size() and view._group.all(func(o: Object) -> bool: return o is DMXFixture),
		"while programming a box picks fixtures only")
	ctx.set_workspace(StudioContext.Workspace.STAGE)
	check(view._group.size() == ctx.fixtures().size(), "switching back keeps the fixtures selected")


func _find_view(n: Node) -> StageView:
	if n is StageView:
		return n
	for c in n.get_children():
		var v := _find_view(c)
		if v:
			return v
	return null
