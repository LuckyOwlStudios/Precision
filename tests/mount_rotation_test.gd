extends SceneTree
## Checks which ways fixtures can turn on the stage for each kind of mounting,
## that turning keeps them on their truss or floor, and that undo puts them back.
##   godot --headless --path . --script res://tests/mount_rotation_test.gd

var _failed := 0


func _init() -> void:
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	ctx.load_demo_rig()
	await process_frame
	var view: StageView = _find_view(main)
	var surfaces := StageRoom.surfaces_in(view.get_node("%Room"))
	var pipes := ctx.truss_pipes

	var fixtures := ctx.fixtures()
	var par: DMXFixture = fixtures[0]
	var mover: DMXFixture = fixtures[4]
	var bar: DMXFixture = fixtures[6]

	# What each mounting allows.
	_expect_kinds("par on a truss (one clamp)", _axes(par, pipes, surfaces),
		[MountRotation.Kind.SWING, MountRotation.Kind.SPIN_CLAMP])
	_expect_kinds("mover on a truss (two clamps)", _axes(mover, pipes, surfaces), [MountRotation.Kind.SWING])
	_expect_kinds("bar on the floor", _axes(bar, pipes, surfaces),
		[MountRotation.Kind.SPIN_SURFACE, MountRotation.Kind.TILT_STAND])
	var floating := Transform3D(Basis.IDENTITY, Vector3(0, 2, 2))
	var rules := MountRotation.rules_of(StageFixture3D.scene_path_of(par))
	_expect_kinds("par placed freely", MountRotation.axes(floating, rules, 0.215, pipes, surfaces),
		[MountRotation.Kind.FREE_X, MountRotation.Kind.FREE_Y, MountRotation.Kind.FREE_Z])

	# Swing the par round the tube, then spin it under its clamp: still hung.
	var before := StudioContext.fixture_transform(par)
	var axes := _axes(par, pipes, surfaces)
	ctx.move_fixture(par, axes[0].turned(before, deg_to_rad(40)))
	_expect(StageRoom.pipe_holding(pipes, StudioContext.fixture_transform(par), rules.mounts) != null, "par still hung after swinging")
	axes = _axes(par, pipes, surfaces)
	ctx.move_fixture(par, axes[1].turned(StudioContext.fixture_transform(par), deg_to_rad(60)))
	_expect(StageRoom.pipe_holding(pipes, StudioContext.fixture_transform(par), rules.mounts) != null, "par still hung after spinning on its clamp")
	_expect(_axes(par, pipes, surfaces).size() == 2, "par keeps both rings after turning")
	await process_frame
	var jaw := _first_mount_point(view, par)
	_expect(jaw != null and absf(jaw.jaw_turn) > 0.5, "par's clamp jaw turns back to follow the tube (%s)" % [jaw.jaw_turn if jaw else "none"])
	var jaw_x := jaw.global_basis * Basis(Vector3.UP, jaw.jaw_turn) * Vector3.RIGHT
	var pipe := StageRoom.pipe_holding(pipes, StudioContext.fixture_transform(par), rules.mounts)
	_expect(absf(jaw_x.normalized().dot(pipe.axis())) > 0.999, "par's clamp jaw runs along the tube")

	# Undo both turns.
	ctx.record_move(par, before, "Turn fixture")
	ctx.undo()
	_expect(StudioContext.fixture_transform(par).is_equal_approx(before), "undo puts the par back")
	ctx.redo()
	_expect(not StudioContext.fixture_transform(par).is_equal_approx(before), "redo turns it again")

	# Mover swings around its tube and stays on it.
	var m0 := StudioContext.fixture_transform(mover)
	var mrules := MountRotation.rules_of(StageFixture3D.scene_path_of(mover))
	ctx.move_fixture(mover, _axes(mover, pipes, surfaces)[0].turned(m0, deg_to_rad(-75)))
	_expect(StageRoom.pipe_holding(pipes, StudioContext.fixture_transform(mover), mrules.mounts) != null, "mover still hung after swinging")

	# Bar spins on the floor and stays standing on it.
	var b0 := StudioContext.fixture_transform(bar)
	ctx.move_fixture(bar, _axes(bar, pipes, surfaces)[0].turned(b0, deg_to_rad(33)))
	var b1 := StudioContext.fixture_transform(bar)
	_expect(MountRotation.standing_on(b1, StageFixture3D.mount_offset(FixtureCatalog.Body.BAR), surfaces), "bar still standing after spinning")
	_expect(b1.origin.is_equal_approx(b0.origin), "bar spins on the spot")

	# Bar tilts on its stand about its long axis: still on the floor, still on
	# the spot, can then still spin, and undo puts it back.
	var brules := MountRotation.rules_of(StageFixture3D.scene_path_of(bar))
	var boff := StageFixture3D.mount_offset(FixtureCatalog.Body.BAR)
	var flat := StudioContext.fixture_transform(bar)
	_expect(absf(MountRotation.stand_tilt(flat, brules, boff, surfaces)) < 0.001, "bar starts flat on its stand")
	ctx.move_fixture(bar, _axes(bar, pipes, surfaces)[1].turned(flat, deg_to_rad(35)))
	var tilted := StudioContext.fixture_transform(bar)
	_expect(is_equal_approx(absf(MountRotation.stand_tilt(tilted, brules, boff, surfaces)), deg_to_rad(35)), "bar tilts 35 degrees on its stand")
	_expect(tilted.origin.is_equal_approx(flat.origin), "tilting does not lift the bar")
	_expect(_axes(bar, pipes, surfaces).size() == 2, "tilted bar keeps its spin and tilt rings")
	_expect(MountRotation.mount_of(tilted, brules, boff, pipes, surfaces) == MountRotation.Mount.SURFACE, "tilted bar still counts as standing")
	ctx.move_fixture(bar, _axes(bar, pipes, surfaces)[0].turned(tilted, deg_to_rad(50)))
	_expect(is_equal_approx(absf(MountRotation.stand_tilt(StudioContext.fixture_transform(bar), brules, boff, surfaces)), deg_to_rad(35)), "spinning keeps the tilt")
	ctx.move_fixture(bar, tilted)
	ctx.record_move(bar, flat, "Tilt fixture")
	ctx.undo()
	_expect(StudioContext.fixture_transform(bar).is_equal_approx(flat), "undo flattens the bar again")
	var par_rules := MountRotation.rules_of(StageFixture3D.scene_path_of(par))
	_expect(is_nan(MountRotation.stand_tilt(flat, par_rules, boff, surfaces)), "a par has no tilting stand")

	# The gizmo draws one ring per axis in rotate mode.
	ctx.set_workspace(StudioContext.Workspace.STAGE)
	ctx.select(par)
	await process_frame
	var gizmo: TransformGizmo = view.get_node("%Gizmo")
	_expect(gizmo.rings.size() == 2, "gizmo shows two rings for the par")

	# Drag each ring with the mouse, face on and side on: the par turns and
	# stays on the truss.
	gizmo.mode = TransformGizmo.Mode.ROTATE
	for i in gizmo.rings.size():
		var start := StudioContext.fixture_transform(par)
		gizmo.target = start
		var ring := gizmo.rings[i]
		var u := TransformGizmo._perpendicular(ring.dir)
		var grab := gizmo.camera.unproject_position(ring.pivot + u * gizmo._world_len_at(ring.pivot) * TransformGizmo.RING_SCALE)
		var h := gizmo.handle_at(grab)
		_expect(h == TransformGizmo.Handle.X + i, "ring %d is under the cursor at its edge (got %d)" % [i, h])
		if h == TransformGizmo.Handle.NONE:
			continue
		gizmo.begin_drag(h, grab)
		var xf := gizmo.drag(grab + Vector2(30, 30), false)
		gizmo.end_drag()
		ctx.move_fixture(par, xf)
		_expect(not xf.basis.is_equal_approx(start.basis), "dragging ring %d turns the par" % i)
		_expect(StageRoom.pipe_holding(pipes, xf, rules.mounts) != null, "par still hung after dragging ring %d" % i)

	print("mount_rotation_test: ", "FAILED %d" % _failed if _failed else "all passed")
	quit(1 if _failed else 0)


func _axes(fx: DMXFixture, pipes: Array[StageRoom.Pipe], surfaces: Array[StageRoom.Surface]) -> Array[MountRotation.Axis]:
	var body: FixtureCatalog.Body = fx.get_meta(StudioContext.META_BODY, FixtureCatalog.Body.PAR)
	return MountRotation.axes(StudioContext.fixture_transform(fx),
		MountRotation.rules_of(StageFixture3D.scene_path_of(fx)), StageFixture3D.mount_offset(body), pipes, surfaces)


func _expect_kinds(what: String, axes: Array[MountRotation.Axis], kinds: Array) -> void:
	var got: Array = []
	for a in axes:
		got.append(a.kind)
	_expect(got == kinds, "%s: rings %s (want %s)" % [what, got, kinds])


func _expect(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_failed += 1


func _first_mount_point(view: StageView, fx: DMXFixture) -> MountPoint:
	var v := view.get_node("%Fixtures").get_node_or_null(NodePath("Visual_" + String(fx.name)))
	if v == null:
		return null
	for n in v.find_children("*", "", true, false):
		if n is MountPoint:
			return n
	return null


func _find_view(n: Node) -> StageView:
	if n is StageView:
		return n
	for c in n.get_children():
		var v := _find_view(c)
		if v:
			return v
	return null
