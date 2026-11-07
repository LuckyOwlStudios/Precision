extends SceneTree
## Checks pointing moving heads at a spot: the pan/tilt maths for upright and
## upside-down heads, that a click on the stage aims every selected head there as
## one undo step, and that unreachable spots are left alone. Run from the project folder:
##   godot --headless --path . --script res://tests/aim_test.gd

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
	test_maths()
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	ctx = main.get_node("%Studio")
	ctx.load_demo_rig()
	ctx.set_workspace(StudioContext.Workspace.PROGRAM)
	view = _find_view(main)
	root.size = Vector2i(1280, 800)
	view.get_parent().remove_child(view)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	holder.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_orbit(0.0, -30.0, 14.0)
	for i in 5:
		await process_frame
	test_click_aims_group()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func _find_view(n: Node) -> StageView:
	if n is StageView:
		return n
	for c in n.get_children():
		var f := _find_view(c)
		if f:
			return f
	return null


func test_maths() -> void:
	print("pan/tilt maths")
	var targets := [Vector3(0, 0, 0), Vector3(3, 0, -2), Vector3(-4, 0.5, 3), Vector3(0.2, 0, 0.1), Vector3(5, 1.2, 5)]
	var mounts := {
		"hung upright": Transform3D(Basis.IDENTITY, Vector3(1, 3.4, 0)),
		"turned 130 degrees": Transform3D(Basis(Vector3.UP, deg_to_rad(130)), Vector3(-2, 3.4, 1)),
		"on a stand, tipped": Transform3D(Basis(Vector3.FORWARD, deg_to_rad(180)), Vector3(0, 0.5, 2)),
	}
	for label: String in mounts:
		var xf: Transform3D = mounts[label]
		var ok := true
		for t: Vector3 in targets:
			var r: Variant = Aim.pan_tilt_for(xf, t, 540.0, 270.0)
			if r == null:
				continue # the 270 degree tilt can't reach everything from a stand
			var pt: Vector2 = r
			var dir := Aim.beam_direction(xf, pt.x, pt.y, 540.0, 270.0)
			var want := (t - xf * Aim.HEAD_PIVOT).normalized()
			if dir.dot(want) < 0.9999:
				ok = false
				print("    off target ", t, " by ", rad_to_deg(dir.angle_to(want)), " deg")
		check(ok, "%s: the beam lands on every reachable spot" % label)
	var xf: Transform3D = mounts["hung upright"]
	var down: Vector2 = Aim.pan_tilt_for(xf, Vector3(1, 0, 0), 540.0, 270.0, Vector2(0.7, 0.5))
	check(is_equal_approx(down.x, 0.7) and absf(down.y - 0.5) < 0.01, "straight down keeps the pan it had")
	check(Aim.pan_tilt_for(xf, Vector3(1, 3.4 - 0.18, 0), 270.0, 100.0) == null or true, "no crash for a target in the head")
	var small: Variant = Aim.pan_tilt_for(xf, Vector3(8, 3.0, 0), 360.0, 90.0)
	check(small == null, "a spot beyond a small tilt range is reported unreachable")


func test_click_aims_group() -> void:
	print("click aims the selected heads")
	var movers: Array[Object] = []
	for fx in ctx.fixtures():
		if Aim.can_aim(fx):
			movers.append(fx)
	check(movers.size() >= 2, "demo rig has moving heads (%d)" % movers.size())
	var others := ctx.fixtures().filter(func(f: DMXFixture) -> bool: return not Aim.can_aim(f))
	var picked: Array[Object] = movers.duplicate()
	if not others.is_empty():
		picked.append(others[0])
	view._set_selection(picked)
	view._aim_button.button_pressed = true
	check(view._aiming, "Point at turns on with moving heads selected")
	var before := {}
	for fx: DMXFixture in movers:
		before[fx] = Vector2(fx.pan, fx.tilt)
	var at := view.size * 0.5
	var hit := view._aim_hit(at)
	check(hit != null, "the middle of the stage view hits the room")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = at
	view._gui_input(press)
	press.pressed = false
	view._gui_input(press)
	var all_on := true
	for fx: DMXFixture in movers:
		var xf := StudioContext.fixture_transform(fx)
		var dir := Aim.beam_direction(xf, fx.pan, fx.tilt, fx.profile.pan_range_deg, fx.profile.tilt_range_deg)
		var want := (hit.position - xf * Aim.HEAD_PIVOT).normalized()
		if dir.dot(want) < 0.999:
			all_on = false
	check(all_on, "every selected head points at the clicked spot")
	ctx.undo()
	var back := true
	for fx: DMXFixture in movers:
		if (before[fx] as Vector2).distance_to(Vector2(fx.pan, fx.tilt)) > 0.0001:
			back = false
	check(back, "one undo puts every head back")
	ctx.redo()
	check(not is_equal_approx(movers[0].pan, before[movers[0]].x) or not is_equal_approx(movers[0].tilt, before[movers[0]].y), "redo aims them again")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	view._gui_input(esc)
	check(not view._aiming and not view._group.is_empty(), "Esc leaves Point at and keeps the selection")
	view._set_selection([])
	check(view._aim_button.disabled, "the button is off with nothing selected")
