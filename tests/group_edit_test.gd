extends SceneTree
## Checks editing several fixtures at once from the inspector: a value applies
## to every picked fixture as one undo step, differing values show as mixed,
## and colour swatches. Run from the project folder:
##   godot --headless --path . --script res://tests/group_edit_test.gd

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
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	ctx.load_demo_rig()
	ctx.set_workspace(StudioContext.Workspace.PROGRAM)
	var inspector: InspectorPanel = _find(main)
	await process_frame

	var list := ctx.fixtures()
	var three: Array[DMXFixture] = [list[0], list[1], list[2]]
	three[0].dimmer = 0.2
	three[1].dimmer = 0.6
	three[2].dimmer = 0.6
	three[0].color = Color.RED
	three[1].color = Color.BLUE
	ctx.history.clear_history()

	ctx.set_group(three)
	await process_frame
	check(inspector.fx == three[0], "group: inspector shows the first fixture")
	check(inspector._group.size() == 3, "group: inspector holds all three")
	check(inspector._mixed("dimmer"), "dimmer differs, shown as mixed")
	check(inspector._mixed("color"), "colour differs, shown as mixed")
	check((inspector.get_node("%DimmerValue") as SpinBox).get_line_edit().text == InspectorPanel.MIXED, "mixed box shows a dash")

	# Typed value reaches every fixture, one undo step.
	(inspector.get_node("%DimmerValue") as SpinBox).value = 50.0
	await process_frame
	check(three.all(func(f: DMXFixture) -> bool: return is_equal_approx(f.dimmer, 0.5)), "typing 50% sets all three")
	check(not inspector._mixed("dimmer"), "no longer mixed")
	check((inspector.get_node("%DimmerValue") as SpinBox).get_line_edit().text.contains("50"), "box shows 50 again")
	ctx.undo()
	check(is_equal_approx(three[0].dimmer, 0.2) and is_equal_approx(three[1].dimmer, 0.6), "one undo restores each fixture's own dimmer")
	ctx.redo()
	check(is_equal_approx(three[2].dimmer, 0.5), "redo applies it again")
	ctx.undo()

	# Slider drag = one step.
	var slider: HSlider = inspector.get_node("%Dimmer")
	slider.drag_started.emit()
	slider.value = 0.7
	slider.value = 0.9
	slider.drag_ended.emit(true)
	check(three.all(func(f: DMXFixture) -> bool: return is_equal_approx(f.dimmer, 0.9)), "slider drag sets all")
	ctx.undo()
	check(is_equal_approx(three[0].dimmer, 0.2), "whole drag undone in one step")

	# Swatch applies colour to all, one undo step.
	ctx.set_fixtures_value(three, &"color", Color.GREEN)
	check(three.all(func(f: DMXFixture) -> bool: return f.color == Color.GREEN), "colour set on all")
	ctx.undo()
	check(three[0].color == Color.RED and three[1].color == Color.BLUE, "undo restores each colour")

	# Swatch palette.
	var before := ctx.swatches.size()
	ctx.add_swatch(Color("123456"))
	check(ctx.swatches.size() == before + 1, "swatch added")
	ctx.add_swatch(Color("123456"))
	check(ctx.swatches.size() == before + 1, "duplicate swatch ignored")
	ctx.remove_swatch(ctx.swatches.size() - 1)
	check(ctx.swatches.size() == before, "swatch removed")

	# Back to one fixture.
	ctx.set_group([])
	ctx.select(three[1])
	await process_frame
	check(inspector._group.is_empty(), "single selection leaves group mode")

	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _find(n: Node) -> InspectorPanel:
	if n is InspectorPanel:
		return n
	for c in n.get_children():
		var f := _find(c)
		if f:
			return f
	return null
