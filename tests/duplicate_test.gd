extends SceneTree
## Checks Ctrl+D on the stage: the copies are patched to free addresses, follow
## the mouse until a click, Esc cancels, and one undo removes them. Run from the
## project folder:
##   godot --headless --path . --script res://tests/duplicate_test.gd

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

	test_single()
	test_cancel()
	test_group()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func move(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	view._gui_input(ev)


func click(at: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = at
	view._gui_input(ev)


func key(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.pressed = true
	view._gui_input(ev)


func overlapping() -> bool:
	var used := {}
	for fx in ctx.fixtures():
		for i in fx.profile.channels.size():
			var a := fx.start_address + i
			if used.has(a):
				return true
			used[a] = true
	return false


func test_single() -> void:
	print("duplicate one fixture")
	var src: DMXFixture = ctx.fixtures()[0]
	src.dimmer = 0.4
	src.color = Color.RED
	ctx.select(src)
	var n := ctx.fixtures().size()
	var from := StudioContext.fixture_transform(src).origin
	ctx.duplicate_requested.emit()
	check(ctx.fixtures().size() == n + 1, "Ctrl+D adds a fixture")
	var copy: DMXFixture = ctx.fixtures()[n]
	check(ctx.selected == copy, "the copy is selected")
	check(copy.profile == src.profile and is_equal_approx(copy.dimmer, 0.4) and copy.color == Color.RED, "profile and look are copied")
	check(not overlapping(), "the copy is patched to a free address (%d)" % copy.start_address)
	check(String(copy.name) != String(src.name), "and gets its own name (%s)" % copy.name)
	check(ctx.grabbing, "undo waits while the copy is floating")
	var at := view._camera.unproject_position((view._visuals[copy] as StageFixture3D).center())
	move(at)
	move(at + Vector2(120, 0))
	var moved := StudioContext.fixture_transform(copy).origin
	check(not moved.is_equal_approx(from), "the copy follows the mouse")
	check(is_equal_approx(StudioContext.fixture_transform(src).origin.x, from.x), "the original stays")
	click(at + Vector2(120, 0))
	check(not ctx.grabbing and ctx.fixtures().size() == n + 1, "a click drops it")
	ctx.undo()
	check(ctx.fixtures().size() == n, "one undo removes the copy")
	ctx.redo()
	check(ctx.fixtures().size() == n + 1 and ctx.fixtures()[n] == copy, "redo brings it back")
	ctx.undo()


func test_cancel() -> void:
	print("cancel")
	var n := ctx.fixtures().size()
	ctx.select(ctx.fixtures()[0])
	ctx.duplicate_requested.emit()
	check(ctx.fixtures().size() == n + 1, "copy made")
	key(KEY_ESCAPE)
	await frames(2)
	check(ctx.fixtures().size() == n and not ctx.grabbing, "Esc throws the copy away")
	ctx.duplicate_requested.emit()
	click(Vector2(300, 300), MOUSE_BUTTON_RIGHT)
	await frames(2)
	check(ctx.fixtures().size() == n, "so does right click")
	check(not overlapping(), "no address clash left behind")


func test_group() -> void:
	print("duplicate a group")
	var fxs := ctx.fixtures()
	var n := fxs.size()
	view._set_selection([fxs[0], fxs[1], fxs[2]])
	ctx.duplicate_requested.emit()
	check(ctx.fixtures().size() == n + 3 and view._group.size() == 3, "three copies, selected together")
	check(not overlapping(), "all patched without clashes")
	key(KEY_ENTER)
	check(not ctx.grabbing, "Enter drops them")
	ctx.undo()
	check(ctx.fixtures().size() == n, "one undo removes all three")


func _find_view(node: Node) -> StageView:
	if node is StageView:
		return node
	for c in node.get_children():
		var v := _find_view(c)
		if v:
			return v
	return null
