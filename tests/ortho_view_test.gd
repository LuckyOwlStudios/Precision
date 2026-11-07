extends SceneTree
## Checks the orthographic drawing views (Top plan, Front and Side elevation):
## the camera really is orthographic and square on, the numpad shortcuts and
## returning to the free camera, panning and zooming to the cursor, clicking a
## fixture, and the measuring and snapping maths of the drafting layer. Run
## from the project folder:
##   godot --headless --path . --script res://tests/ortho_view_test.gd

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

	await test_views_are_square_on()
	await test_numpad_and_return()
	await test_leaving_by_orbit()
	await test_pan_and_zoom()
	await test_click_picks_fixture()
	await test_snap_and_measure()
	await test_beam_footprint()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	view._gui_input(ev)


func click(at: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		view._gui_input(ev)


func wheel(at: Vector2, up: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.position = at
	view._gui_input(ev)


func test_views_are_square_on() -> void:
	print("views")
	var cam := view._camera as Camera3D
	check(cam.projection == Camera3D.PROJECTION_PERSPECTIVE, "starts in perspective")
	view.show_view("Top")
	await frames(2)
	check(cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "top plan is orthographic")
	check((-cam.global_basis.z).dot(Vector3.DOWN) > 0.9999, "top plan looks straight down")
	check(cam.global_basis.y.dot(Vector3.FORWARD) > 0.9999, "top plan has the back of the stage up")
	view.show_view("Front")
	await frames(2)
	check((-cam.global_basis.z).dot(Vector3.FORWARD) > 0.9999, "front elevation looks at the back wall")
	check(absf(cam.global_basis.y.dot(Vector3.UP)) > 0.9999, "front elevation is level")
	view.show_view("Side")
	await frames(2)
	check((-cam.global_basis.z).dot(Vector3.RIGHT) > 0.9999, "side elevation looks from house left")
	check(cam.global_basis.x.dot(Vector3.BACK) > 0.9999, "side elevation has the audience on the right")
	var wall := view._room.get_node("LeftWall") as Node3D
	check(not wall.visible, "the near wall is hidden in the side view")
	check(view._drafting.visible and view._draft_bar.visible, "drawing layer and its buttons show")
	view.show_view("Perspective")
	await frames(2)
	check(wall.visible and not view._drafting.visible, "back in perspective the wall and layer are restored")


func test_numpad_and_return() -> void:
	print("shortcuts")
	var cam := view._camera as Camera3D
	view.set_orbit(40.0, -30.0, 11.0)
	key(KEY_KP_7)
	check(view._view_preset == "Top" and cam.projection == Camera3D.PROJECTION_ORTHOGONAL, "numpad 7 is the top plan")
	key(KEY_KP_1)
	check(view._view_preset == "Front", "numpad 1 is front")
	key(KEY_KP_3)
	check(view._view_preset == "Side", "numpad 3 is side")
	key(KEY_KP_5)
	check(view._view_preset == "Perspective", "numpad 5 leaves the drawing view")
	check(is_equal_approx(view._yaw, 40.0) and is_equal_approx(view._pitch, -30.0) and is_equal_approx(view._distance, 11.0),
		"the free camera comes back where it was")
	key(KEY_KP_5)
	check(view._view_preset == "Side", "numpad 5 again returns to the last drawing view")
	key(KEY_KP_5)


func test_leaving_by_orbit() -> void:
	print("orbit from a drawing view")
	view.show_view("Top")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.alt_pressed = true
	ev.position = Vector2(300, 300)
	view._gui_input(ev)
	check(view._view_preset == "Perspective", "Alt + left drag carries on in perspective")
	ev.pressed = false
	view._gui_input(ev)
	view.show_view("Front")
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	view._gui_input(rmb)
	check(view._view_preset == "Perspective", "flying (right button) also leaves it")
	rmb.pressed = false
	view._gui_input(rmb)


func test_pan_and_zoom() -> void:
	print("pan and zoom")
	view.show_view("Front")
	await frames(2)
	var cam := view._camera as Camera3D
	var at := Vector2(900, 300)
	var d := view._drafting as DraftingOverlay
	var before := d.point_at(at)
	wheel(at, true)
	var after := d.point_at(at)
	check(view._ortho_size < 9.0, "wheel zooms in")
	check(before.distance_to(after) < 0.001, "the point under the cursor stays put")
	var pivot_before := view._pivot.position
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_MIDDLE
	down.pressed = true
	view._gui_input(down)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(100, 0)
	drag.position = Vector2(500, 300)
	view._gui_input(drag)
	down.pressed = false
	view._gui_input(down)
	var moved := view._pivot.position - pivot_before
	check(moved.x < -0.1 and absf(moved.y) < 0.001 and absf(moved.z) < 0.001, "dragging right slides the drawing right (the view moves left)")
	var per_px := view._ortho_size / view.size.y
	check(is_equal_approx(absf(moved.x), 100.0 * per_px), "one pixel of drag is one pixel of drawing")
	check(is_equal_approx(cam.size, view._ortho_size), "the camera shows the zoomed height")


func test_click_picks_fixture() -> void:
	print("picking")
	view.show_view("Front")
	await frames(3)
	var cam := view._camera as Camera3D
	ctx.select(null)
	var fx: DMXFixture = ctx.fixtures()[0]
	var at := cam.unproject_position((view._visuals[fx] as StageFixture3D).center())
	click(at)
	check(ctx.selected == fx, "clicking a fixture in the front elevation selects it")
	view.show_view("Top")
	await frames(3)
	ctx.select(null)
	at = cam.unproject_position((view._visuals[fx] as StageFixture3D).center())
	click(at)
	check(ctx.selected == fx, "and in the top plan too, even with truss drawn over it")


func test_snap_and_measure() -> void:
	print("snapping and measuring")
	view.show_view("Top")
	await frames(3)
	var cam := view._camera as Camera3D
	var d := view._drafting as DraftingOverlay
	var empty := Vector2(120, 700)
	var p := d.snap_point(empty, true)
	check(is_equal_approx(p.x, snappedf(p.x, 0.25)) and is_equal_approx(p.z, snappedf(p.z, 0.25)), "points snap to the quarter metre grid")
	check(absf(p.y) < 0.001, "plan points are on the floor")
	var fx: DMXFixture = ctx.fixtures()[0]
	var mount := StudioContext.fixture_transform(fx).origin
	var s := cam.unproject_position(mount) + Vector2(4, 3)
	var snapped := d.snap_point(s, false)
	check(is_equal_approx(snapped.x, mount.x) and is_equal_approx(snapped.z, mount.z), "a point near a fixture snaps onto it")
	check(view._draft_measure != null, "measure button exists")
	key(KEY_D)
	check(d.measuring, "D starts measuring")
	click(Vector2(200, 400))
	check(d.has_measurement(), "the first click places a point instead of selecting")
	click(Vector2(400, 400))
	click(Vector2(600, 400))
	key(KEY_ESCAPE)
	check(not d.has_measurement(), "Esc clears the line")
	key(KEY_ESCAPE)
	check(not d.measuring, "and a second Esc stops measuring")


func test_beam_footprint() -> void:
	print("beam footprint")
	view.show_view("Top")
	await frames(3)
	var d := view._drafting as DraftingOverlay
	var found := false
	for fx: DMXFixture in view._visuals:
		var v := view._visuals[fx] as StageFixture3D
		if v.beam_dir().dot(Vector3.DOWN) > 0.99:
			var beam := d._beam_of(fx)
			var centre: Vector3 = beam["centre"]
			var origin: Vector3 = beam["origin"]
			var rim: PackedVector3Array = beam["rim"]
			check(absf(centre.y) < 0.01, "a downward beam lands on the floor (%s)" % StudioContext.display_name(fx))
			var radius := rim[0].distance_to(centre)
			var expected := (origin.y) * tan(deg_to_rad(v.beam_half_angle()))
			check(absf(radius - expected) < 0.05 or radius <= v.beam_length() * tan(deg_to_rad(v.beam_half_angle())) + 0.05, "its footprint radius matches the cone angle")
			found = true
			break
	check(found, "the demo rig has a downward beam to test")
	check(DraftingOverlay.pick_step(DraftingOverlay.MINOR_STEPS, 0.3) == 0.5, "grid step grows with zoom")


func _find_view(n: Node) -> StageView:
	if n is StageView:
		return n
	for c in n.get_children():
		var v := _find_view(c)
		if v:
			return v
	return null
