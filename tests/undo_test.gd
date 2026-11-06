extends SceneTree
## Checks the shared undo history: adding, removing, renaming, re-patching and
## re-lighting fixtures, recorded cues, and that quick edits merge into one step.
##   godot --headless --path . --script res://tests/undo_test.gd

var _failed := 0


func _init() -> void:
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")

	# The whole demo rig is one step.
	ctx.load_demo_rig()
	var n := ctx.fixtures().size()
	_expect(n > 0, "demo rig loads (%d fixtures)" % n)
	ctx.undo()
	_expect(ctx.fixtures().is_empty(), "one undo takes the demo rig away")
	ctx.redo()
	_expect(ctx.fixtures().size() == n, "redo brings it back")
	await process_frame

	# Remove a fixture, undo: same node, same place in the rig, same patch.
	var par: DMXFixture = ctx.fixtures()[1]
	var address := par.start_address
	ctx.remove_fixture(par)
	_expect(not ctx.fixtures().has(par), "remove takes the par off")
	ctx.undo()
	_expect(ctx.fixtures().find(par) == 1 and par.start_address == address, "undo puts the par back where it was")
	ctx.redo()
	_expect(not ctx.fixtures().has(par), "redo removes it again")
	ctx.undo()
	await process_frame

	# Rename.
	ctx.rename_fixture(par, "Left wash")
	ctx.undo()
	_expect(StudioContext.display_name(par) == String(par.name), "undo rename")
	ctx.redo()
	_expect(StudioContext.display_name(par) == "Left wash", "redo rename")

	# Look values: quick repeats merge, separate edits don't.
	par.dimmer = 0.2
	ctx.set_fixture_value(par, &"dimmer", 0.4)
	ctx.set_fixture_value(par, &"dimmer", 0.6)
	ctx.set_fixture_value(par, &"dimmer", 0.8)
	ctx.undo()
	_expect(is_equal_approx(par.dimmer, 0.2), "wheel-style dimmer changes undo as one step (%.2f)" % par.dimmer)
	ctx.redo()
	_expect(is_equal_approx(par.dimmer, 0.8), "and redo as one (%.2f)" % par.dimmer)
	var other: DMXFixture = ctx.fixtures()[2]
	var other_before := other.dimmer
	ctx.set_fixture_value(other, &"dimmer", 0.1)
	ctx.undo()
	_expect(is_equal_approx(other.dimmer, other_before) and is_equal_approx(par.dimmer, 0.8),
		"another fixture's change is its own step")

	# A drag recorded at the end.
	var before_color := par.color
	par.color = Color.RED
	par.color = Color.BLUE
	ctx.record_fixture_value(par, &"color", before_color)
	ctx.undo()
	_expect(par.color == before_color, "colour picker session undoes in one step")

	# Re-patch.
	ctx.set_address(par, 400)
	ctx.undo()
	_expect(par.start_address == address, "undo re-patch")

	# Move.
	var before := StudioContext.fixture_transform(par)
	ctx.move_fixture(par, before.translated(Vector3(1, 0, 0)))
	ctx.record_move(par, before, "Move fixture")
	ctx.undo()
	_expect(StudioContext.fixture_transform(par).is_equal_approx(before), "undo move")

	# Cues.
	ctx.record_cue()
	ctx.record_cue()
	_expect(ctx.cue_stack.cues.size() == 2, "two cues recorded")
	ctx.undo()
	_expect(ctx.cue_stack.cues.size() == 1, "undo removes the last cue")
	ctx.redo()
	_expect(ctx.cue_stack.cues.size() == 2, "redo puts it back")

	# A new fixture after an undo drops the redo branch (and frees what it held).
	ctx.remove_fixture(par)
	ctx.undo()
	ctx.undo() # the remove, then the cue
	ctx.record_cue()
	_expect(not ctx.redo(), "nothing to redo after a new edit")

	# Ctrl+R redoes; plain R does not.
	ctx.set_fixture_value(other, &"tilt", 0.9)
	await create_timer(1.0).timeout # out of the merge window
	var tilt_before := other.tilt
	ctx.set_fixture_value(other, &"tilt", 0.1)
	_press(KEY_Z, true)
	_expect(is_equal_approx(other.tilt, tilt_before), "Ctrl+Z undoes")
	_press(KEY_R, true)
	_expect(is_equal_approx(other.tilt, 0.1), "Ctrl+R redoes")
	_press(KEY_Z, true)
	_press(KEY_Z, true, true)
	_expect(is_equal_approx(other.tilt, 0.1), "Ctrl+Shift+Z redoes")
	_press(KEY_Z, true)
	_press(KEY_Y, true)
	_expect(is_equal_approx(other.tilt, 0.1), "Ctrl+Y redoes")

	print("undo_test: ", "FAILED %d" % _failed if _failed else "all passed")
	quit(1 if _failed else 0)


func _press(key: Key, ctrl: bool, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	e.pressed = true
	root.push_input(e)
	var up := e.duplicate() as InputEventKey
	up.pressed = false
	root.push_input(up)


func _expect(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed += 1
