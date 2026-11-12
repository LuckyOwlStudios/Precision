extends SceneTree
## Checks H (hide selection), Shift+H (isolate) and Alt+H (show all) on the 3D
## stage: hidden things can't be picked or boxed, and DMX state is untouched.
##   godot --headless --path . --script res://tests/hide_isolate_test.gd

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
	for i in 5:
		await process_frame

	test_hide_and_show_all()
	test_isolate()
	test_hidden_not_boxed()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func key(k: Key, shift := false, alt := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.pressed = true
	ev.shift_pressed = shift
	ev.alt_pressed = alt
	view._gui_input(ev)


func hidden_count() -> int:
	var n := 0
	for o in view._all_things():
		if view._is_hidden(o):
			n += 1
	return n


func test_hide_and_show_all() -> void:
	print("H hides, Alt+H shows all")
	var fx: DMXFixture = ctx.fixtures()[0]
	var dimmer_before: float = fx.dimmer
	ctx.select(fx)
	key(KEY_H)
	check(view._is_hidden(fx) and hidden_count() == 1, "H hides only the selected fixture")
	check(ctx.selected == null, "and drops it from the selection")
	check(fx.dimmer == dimmer_before and ctx.fixtures().has(fx), "the fixture itself is untouched (DMX unaffected)")
	key(KEY_H, false, true)
	check(hidden_count() == 0, "Alt+H shows everything again")
	key(KEY_H)
	check(hidden_count() == 0, "H with nothing selected does nothing")


func test_isolate() -> void:
	print("Shift+H isolates")
	var fx: DMXFixture = ctx.fixtures()[0]
	ctx.select(fx)
	key(KEY_H, true)
	check(not view._is_hidden(fx), "the selected fixture stays visible")
	check(hidden_count() == view._all_things().size() - 1, "everything else is hidden")
	key(KEY_H, false, true)
	check(hidden_count() == 0, "Alt+H brings it all back")


func test_hidden_not_boxed() -> void:
	print("hidden things can't be box-selected")
	var fx: DMXFixture = ctx.fixtures()[0]
	view._set_hidden(fx, true)
	check(not view._things_in(Rect2(Vector2.ZERO, Vector2(view.size))).has(fx), "box select skips a hidden fixture")
	view._unhide_all()


func _find_view(n: Node) -> StageView:
	if n is StageView:
		return n
	for c in n.get_children():
		var f := _find_view(c)
		if f:
			return f
	return null
