extends SceneTree
## Checks the Blender-style numpad camera keys: Ctrl for the opposite side, orbit in
## steps, the audience view on 0, and framing the selection (numpad .) or the rig (Home).
## Run from the project folder:
##   godot --headless --path . --script res://tests/numpad_views_test.gd

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
	view.set_orbit(25.0, -20.0, 14.0)
	await frames(5)

	await test_opposite_views()
	await test_orbit_steps()
	await test_audience_view()
	await test_framing()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func key(code: Key, ctrl := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.ctrl_pressed = ctrl
	ev.pressed = true
	view._gui_input(ev)


func look_dir() -> Vector3:
	return -(view._camera as Camera3D).global_basis.z


func test_opposite_views() -> void:
	print("opposite views")
	var cam := view._camera as Camera3D
	key(KEY_KP_1, true)
	await frames(2)
	check(view._view_preset == "Back" and cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "Ctrl+numpad 1 is the back elevation")
	check(look_dir().dot(Vector3.BACK) > 0.9999, "it looks from the back of the stage toward the audience")
	check(absf(cam.global_basis.y.dot(Vector3.UP)) > 0.9999, "and is level")
	check(view._view_buttons["Front"].button_pressed, "the Front button stays lit")
	check(view._drafting.view_name() == "Back elevation", "the drawing is titled for it")
	check(view._drafting._h_sign() < 0.0, "its ruler runs the other way, so the numbers flip")
	key(KEY_KP_3, true)
	await frames(2)
	check(view._view_preset == "SideRight" and look_dir().dot(Vector3.LEFT) > 0.9999, "Ctrl+numpad 3 looks from house right")
	check(not (view._room.get_node("RightWall") as Node3D).visible and (view._room.get_node("LeftWall") as Node3D).visible, "the near wall is the right one")
	key(KEY_KP_7, true)
	await frames(2)
	check(view._view_preset == "Bottom" and look_dir().dot(Vector3.UP) > 0.9999, "Ctrl+numpad 7 looks up from underneath")
	check(not (view._room.get_node("Floor") as Node3D).visible, "the floor is out of the way")
	check(view._drafting._v_sign() > 0.0, "the plan's Z ruler is flipped")
	key(KEY_KP_7)
	await frames(2)
	check(view._view_preset == "Top" and (view._room.get_node("Floor") as Node3D).visible, "plain numpad 7 is still the top plan, floor back")
	key(KEY_KP_1)
	key(KEY_KP_5)
	check(view._view_preset == "Perspective", "numpad 5 still leaves a drawing view")
	key(KEY_KP_3, true)
	key(KEY_KP_5)
	key(KEY_KP_5)
	check(view._view_preset == "SideRight", "numpad 5 returns to the far side it left")
	view.show_view("Perspective")


func test_orbit_steps() -> void:
	print("orbit steps")
	view.set_orbit(20.0, -30.0, 12.0)
	key(KEY_KP_6)
	check(is_equal_approx(view._yaw, 35.0), "numpad 6 orbits 15° right")
	key(KEY_KP_4)
	key(KEY_KP_4)
	check(is_equal_approx(view._yaw, 5.0), "numpad 4 orbits left")
	key(KEY_KP_8)
	check(is_equal_approx(view._pitch, -45.0), "numpad 8 raises the camera")
	key(KEY_KP_2)
	key(KEY_KP_2)
	check(is_equal_approx(view._pitch, -15.0), "numpad 2 lowers it")
	for i in 10:
		key(KEY_KP_2)
	check(view._pitch <= 5.0, "it will not go under the floor")
	for i in 20:
		key(KEY_KP_8)
	check(view._pitch >= -89.0, "nor flip over the top")
	view.show_view("Front")
	key(KEY_KP_4)
	check(view._view_preset == "Perspective" and is_equal_approx(view._yaw, -15.0), "orbiting from a drawing view carries on in perspective")


func test_audience_view() -> void:
	print("audience view")
	view.show_view("Top")
	key(KEY_KP_0)
	await frames(2)
	check(view._view_preset == "Perspective" and not view._is_ortho(), "numpad 0 is perspective")
	check(is_equal_approx(view._yaw, 0.0) and view._pivot.position.is_equal_approx(StageView.DEFAULT_PIVOT) and is_equal_approx(view._distance, StageView.DEFAULT_DISTANCE), "at the default camera")
	check(look_dir().z < -0.9, "looking at the stage from the audience")


func test_framing() -> void:
	print("framing")
	var cam := view._camera as Camera3D
	view.set_orbit(40.0, -30.0, 30.0)
	ctx.select(null)
	view._set_selection([])
	var before := view._distance
	key(KEY_KP_PERIOD)
	check(is_equal_approx(view._distance, before), "numpad . with nothing selected leaves the camera")
	var fx: DMXFixture = ctx.fixtures()[0]
	view._set_selection([fx])
	key(KEY_KP_PERIOD)
	await frames(2)
	var c: Vector3 = (view._visuals[fx] as StageFixture3D).center()
	check(view._pivot.position.is_equal_approx(c), "numpad . centres the selected fixture")
	check(view._distance < 8.0, "and moves in on it")
	var screen := cam.unproject_position(c)
	check(screen.distance_to(view.size * 0.5) < 2.0, "it lands mid-view")
	view._set_selection([])
	view.set_orbit(40.0, -30.0, 3.0)
	key(KEY_HOME)
	await frames(2)
	var box: AABB = view._rig_box()
	var inside := true
	for i in 8:
		if not Rect2(Vector2.ZERO, view.size).has_point(cam.unproject_position(box.get_endpoint(i))):
			inside = false
	check(inside, "Home fits the whole rig in view")
	check(view._distance > 3.0, "backing off from a close camera")
	view.show_view("Front")
	view._set_selection([fx])
	key(KEY_KP_PERIOD)
	await frames(2)
	check(view._is_ortho() and view._pivot.position.is_equal_approx(c) and view._ortho_size < 9.0, "in a drawing view numpad . centres and zooms in")
	var p := cam.unproject_position(c)
	check(Rect2(Vector2.ZERO, view.size).has_point(p), "keeping the fixture on the sheet")
	key(KEY_HOME)
	await frames(2)
	check(view._is_ortho() and view._ortho_size > 3.0, "Home in a drawing view fits the rig")
	view.show_view("Perspective")


func _find_view(n: Node) -> StageView:
	if n is StageView:
		return n
	for c in n.get_children():
		var v := _find_view(c)
		if v:
			return v
	return null
