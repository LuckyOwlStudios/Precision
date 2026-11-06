extends SceneTree
## Re-patching from the DMX panel: drag on the map, fix overlaps, tidy up, undo.
##   godot --headless --path . --script res://tests/dmx_patch_test.gd

var _fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		push_error("FAIL: " + what)
	print(("ok   " if ok else "FAIL ") + what)


func _init() -> void:
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	ctx.load_demo_rig()
	ctx.set_workspace(0)
	(main.get_node("%RightTabs") as TabContainer).current_tab = 2
	for i in 5: await process_frame
	var fx := ctx.fixtures()
	var starts := fx.map(func(f: DMXFixture) -> int: return f.start_address)

	# Clash two fixtures, then fix them.
	ctx.set_address(fx[1], fx[0].start_address + 1)
	var info := DMXPatchInfo.build(ctx.fixtures())
	_check(info.has_problem(fx[0]) and info.has_problem(fx[1]), "overlap detected")
	_check(ctx.fix_overlaps() == 1, "fix_overlaps moves one fixture")
	info = DMXPatchInfo.build(ctx.fixtures())
	_check(info.shared_count == 0, "no shared addresses after fix")
	_check(fx[0].start_address == starts[0], "first fixture keeps its place")
	ctx.undo()
	info = DMXPatchInfo.build(ctx.fixtures())
	_check(info.shared_count > 0, "undo brings the overlap back")
	ctx.undo()
	_check(fx[1].start_address == starts[1], "second undo restores the clean patch")

	# Pack from 1.
	ctx.pack_addresses()
	var at := 1
	var packed := true
	for f in ctx.fixtures():
		packed = packed and f.start_address == at
		at += f.profile.channels.size()
	_check(packed, "pack_addresses lines everything up from 1")
	ctx.undo()
	_check(fx[2].start_address == starts[2], "undo restores addresses after pack")

	# Drag on the map: pick up fixture 0 by its 2nd channel (address 2) and drop on slot 40.
	var dmx = main.get_node("%DMX")
	var ov: DMXOverview = dmx._overview
	ov.size = Vector2(26 + 32 * 8, 16 * 8)
	var cs := 8.0
	var slot := func(a: int) -> Vector2:
		var i := a - 1
		return Vector2(DMXOverview.GUTTER + (i % 32) * cs + 2, (i / 32) * cs + 2)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = slot.call(fx[0].start_address + 1)
	ov._gui_input(press)
	_check(ctx.selected == fx[0], "pressing a fixture on the map selects it")
	var move := InputEventMouseMotion.new()
	move.position = slot.call(100)
	ov._gui_input(move)
	_check(fx[0].start_address == 99, "dragging moves the start so the grabbed channel follows the pointer")
	move.position = slot.call(512)
	ov._gui_input(move)
	_check(fx[0].start_address == 512 - fx[0].profile.channels.size() + 1, "dragging clamps at the end of the universe")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	ov._gui_input(release)
	move.position = slot.call(5)
	ov._gui_input(move)
	_check(fx[0].start_address != 5, "after release the fixture stays put")

	# Card number box.
	var card: DMXFixtureCard = dmx._cards[fx[3]]
	card._address.value = 200
	_check(fx[3].start_address == 200, "typing a start address re-patches")
	_check(dmx._cards[fx[3]] == card, "the card is updated in place, not rebuilt")
	print("DONE fails=", _fails)
	quit(1 if _fails else 0)
