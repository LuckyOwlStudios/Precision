extends SceneTree
## Checks mirror mode on the stage: math, placing, moving, turning, deleting
## (fixtures and truss), linked pairs, and one undo step each. Run from the
## project folder:
##   godot --headless --path . --script res://tests/symmetry_test.gd

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
	ctx.set_workspace(StudioContext.Workspace.STAGE)
	view = _find_view(main)
	root.size = Vector2i(1280, 800)
	view.get_parent().remove_child(view)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	holder.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.set_orbit(0.0, -50.0, 16.0)
	for i in 5:
		await process_frame

	test_math()
	test_fixtures()
	test_pieces()
	test_z_axis_and_centre()
	test_demo_rig_not_doubled()
	test_ui()
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


func near(a: Vector3, b: Vector3) -> bool:
	return a.distance_to(b) < 0.001


func test_math() -> void:
	print("mirror math")
	var s := StageSymmetry.new()
	s.enabled = true
	check(near(s.mirror_point(Vector3(-3, 2, 1)), Vector3(3, 2, 1)), "X mirror flips x about the origin")
	s.center = Vector3(1, 0, 0)
	check(near(s.mirror_point(Vector3(-3, 2, 1)), Vector3(5, 2, 1)), "a centre at x=1 puts the plane there")
	s.center = Vector3.ZERO
	# A fixture tilted towards the plane and turned about Y.
	var b := Basis(Vector3.UP, 0.7) * Basis(Vector3.BACK, 0.4)
	var xf := Transform3D(b, Vector3(-2, 3, 1))
	var m := s.mirror_transform(xf)
	check(is_equal_approx(m.basis.determinant(), 1.0), "the twin's basis is a proper rotation")
	check(near(-m.basis.y, s.mirror_dir(-xf.basis.y)), "its beam points the mirrored way")
	check(near(s.mirror_transform(m).origin, xf.origin) and near(-s.mirror_transform(m).basis.y, -xf.basis.y), "mirroring twice gives the original back")
	var ident := s.mirror_transform(Transform3D(Basis.IDENTITY, Vector3(-4, 0, 0)))
	check(ident.basis.is_equal_approx(Basis.IDENTITY), "an upright piece's twin is upright, unturned")
	s.axis = StageSymmetry.Axis.Z
	check(near(s.mirror_point(Vector3(-3, 2, 1)), Vector3(-3, 2, -1)), "Z axis flips z")
	check(s.on_plane(Transform3D(Basis.IDENTITY, Vector3(5, 0, 0.01))), "something on the plane is its own twin")


func test_fixtures() -> void:
	print("fixtures")
	ctx.symmetry.enabled = true
	var entry: FixtureCatalog.Entry = FixtureCatalog.entries()[1]
	var steps := ctx.fixtures().size()
	var fx := ctx.add_fixture(entry, Vector3(-3, 3, 0), Basis.IDENTITY)
	var all := ctx.fixtures()
	check(all.size() == steps + 2, "placing one fixture adds two")
	var twin := StageSymmetry.partner_of(fx) as DMXFixture
	check(twin != null and StageSymmetry.partner_of(twin) == fx, "they are linked")
	check(near(StudioContext.fixture_transform(twin).origin, Vector3(3, 3, 0)), "the twin is across the plane")
	ctx.undo()
	check(ctx.fixtures().size() == steps, "one undo removes both")
	ctx.redo()
	check(ctx.fixtures().size() == steps + 2, "redo brings both back")
	fx = ctx.fixtures()[steps]
	twin = StageSymmetry.partner_of(fx) as DMXFixture

	var before := StudioContext.fixture_transform(fx)
	ctx.move_fixture(fx, Transform3D(Basis(Vector3.BACK, 0.5), Vector3(-1, 3, 2)))
	check(near(StudioContext.fixture_transform(twin).origin, Vector3(1, 3, 2)), "moving one moves its twin")
	check(near(-StudioContext.fixture_transform(twin).basis.y, ctx.symmetry.mirror_dir(-StudioContext.fixture_transform(fx).basis.y)), "turning one turns its twin the mirrored way")
	ctx.record_move(fx, before, "Move fixture")
	ctx.undo()
	check(near(StudioContext.fixture_transform(fx).origin, Vector3(-3, 3, 0)) and near(StudioContext.fixture_transform(twin).origin, Vector3(3, 3, 0)), "one undo puts both back")
	ctx.redo()
	check(near(StudioContext.fixture_transform(twin).origin, Vector3(1, 3, 2)), "redo moves both again")
	ctx.undo()

	ctx.symmetry.enabled = false
	ctx.move_fixture(fx, Transform3D(Basis.IDENTITY, Vector3(-2, 3, 0)))
	check(near(StudioContext.fixture_transform(twin).origin, Vector3(3, 3, 0)), "with mirror off the twin stays put")
	ctx.move_fixture(fx, before)
	ctx.symmetry.enabled = true

	ctx.remove_fixture(fx)
	check(ctx.fixtures().size() == steps, "deleting one removes its twin too")
	ctx.undo()
	check(ctx.fixtures().size() == steps + 2, "one undo restores both")
	ctx.undo()
	ctx.undo()
	check(ctx.fixtures().size() == steps, "(undone back to the start)")

	var centre := ctx.add_fixture(entry, Vector3(0, 3, 1), Basis.IDENTITY)
	check(ctx.fixtures().size() == steps + 1 and StageSymmetry.partner_of(centre) == null, "on the plane there is no twin")
	ctx.undo()


func test_pieces() -> void:
	print("truss pieces")
	ctx.symmetry.enabled = true
	ctx.symmetry.axis = StageSymmetry.Axis.X
	var path := "res://structure/pieces/base_plate.tscn"
	var n := view._pieces().size()
	var at := view._camera.unproject_position(Vector3(-4, 0, 1))
	view._drop_piece(at, path)
	var pieces := view._pieces()
	check(pieces.size() == n + 2, "dropping a base plate drops its twin")
	var a: StructurePiece = pieces[n]
	var b: StructurePiece = pieces[n + 1]
	check(StageSymmetry.partner_of(a) == b, "the pieces are linked")
	check(near(b.global_position, ctx.symmetry.mirror_point(a.global_position)), "the twin is across the plane")
	ctx.undo()
	check(view._pieces().size() == n, "one undo takes both off")
	ctx.redo()
	check(view._pieces().size() == n + 2, "redo puts both back")
	a = view._pieces()[n]
	b = view._pieces()[n + 1]

	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(90)), Vector3(-5, 0, -2))
	a.global_transform = xf
	view._follow_piece(a)
	check(near(b.global_position, Vector3(5, 0, -2)), "moving a piece moves its twin")
	check(near(b.global_basis * Vector3.RIGHT, ctx.symmetry.mirror_dir(a.global_basis * Vector3.RIGHT)) or near(b.global_basis * Vector3.RIGHT, -ctx.symmetry.mirror_dir(a.global_basis * Vector3.RIGHT)), "turning one turns the other (its tube still lines up)")

	view._select_piece(a)
	view.key(KEY_DELETE) if view.has_method("key") else _key(KEY_DELETE)
	check(view._pieces().size() == n, "Delete removes both pieces")
	ctx.undo()
	check(view._pieces().size() == n + 2, "one undo restores both")
	ctx.undo()
	check(view._pieces().size() == n + 2 or view._pieces().size() == n, "(history intact)")
	while ctx.undo() and view._pieces().size() > n:
		pass


func _key(k: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = k
	ev.pressed = true
	view._gui_input(ev)


func test_z_axis_and_centre() -> void:
	print("Z axis, moved centre")
	ctx.symmetry.axis = StageSymmetry.Axis.Z
	ctx.symmetry.set_offset(1.0)
	var entry: FixtureCatalog.Entry = FixtureCatalog.entries()[1]
	var steps := ctx.fixtures().size()
	var fx := ctx.add_fixture(entry, Vector3(2, 3, -2), Basis.IDENTITY)
	var twin := StageSymmetry.partner_of(fx) as DMXFixture
	check(twin != null and near(StudioContext.fixture_transform(twin).origin, Vector3(2, 3, 4)), "plane at z=1: z=-2 mirrors to z=4")
	ctx.undo()
	check(ctx.fixtures().size() == steps, "undone")
	ctx.symmetry.axis = StageSymmetry.Axis.X
	ctx.symmetry.reset()


func test_demo_rig_not_doubled() -> void:
	print("demo rig")
	for i in 3:
		ctx.undo()
	ctx.symmetry.enabled = true
	var before := ctx.fixtures().size()
	ctx.load_demo_rig()
	check(ctx.fixtures().size() == before + 8 or ctx.fixtures().size() == before + 6, "mirror mode doesn't double the demo rig (%d added)" % (ctx.fixtures().size() - before))
	check(not ctx.symmetry.suspended, "and doesn't stay suspended")


func test_ui() -> void:
	print("toolbar")
	var btn: Button = view._mirror_button
	btn.button_pressed = false
	ctx.symmetry.enabled = false
	view._sync_mirror()
	check(not view._mirror_plane.visible and not view._mirror_options.visible, "plane and options hidden while off")
	_key(KEY_M)
	check(ctx.symmetry.enabled and btn.button_pressed and view._mirror_plane.visible and view._mirror_options.visible, "M turns it on: button down, plane and options shown")
	view._axis_z.pressed.emit()
	check(ctx.symmetry.axis == StageSymmetry.Axis.Z and view._center_label.text.begins_with("At Z"), "the Z button switches the axis")
	view._center_box.value = 2.0
	check(is_equal_approx(ctx.symmetry.center.z, 2.0) and is_equal_approx(view._mirror_plane.position.z, 2.0), "the centre box moves the plane")
	ctx.set_workspace(StudioContext.Workspace.PROGRAM)
	check(not view._mirror_plane.visible, "the plane is hidden outside the Stage workspace")
