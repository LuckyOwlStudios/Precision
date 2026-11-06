extends SceneTree
## Checks clicking things on the 3D stage (StagePick). Run from the project folder:
##   godot --headless --path . --script res://tests/stage_pick_test.gd

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
	# Give the stage a real window's worth of pixels (headless starts tiny).
	root.size = Vector2i(1280, 800)
	view.get_parent().remove_child(view)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	holder.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(5)

	test_ray_box()
	await test_whole_fixture_body()
	await test_truss()
	await test_program_ignores_truss()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func test_ray_box() -> void:
	print("ray vs box")
	var box := AABB(Vector3(-1, -1, -1), Vector3(2, 2, 2))
	check(is_equal_approx(StagePick._ray_box(box, Vector3(0, 0, 5), Vector3(0, 0, -1)), 4.0), "hits the near face")
	check(StagePick._ray_box(box, Vector3(3, 0, 5), Vector3(0, 0, -1)) < 0.0, "misses beside it")
	check(StagePick._ray_box(box, Vector3.ZERO, Vector3(0, 0, -1)) == 0.0, "starting inside counts at once")


## Close up, a click anywhere on a fixture's body picks it, not only near its middle.
func test_whole_fixture_body() -> void:
	print("fixture bodies, close up")
	view.set_orbit(20.0, -5.0, 5.0)
	await frames(3)
	var cam: Camera3D = view._camera
	var rect := Rect2(Vector2.ZERO, view.size)
	for fx: DMXFixture in view._visuals:
		var v: StageFixture3D = view._visuals[fx]
		var n := 0
		var good := 0
		for mi: MeshInstance3D in v.find_children("*", "MeshInstance3D", true, false):
			if not (mi.name in ["Shell", "Base", "ArmLeft", "ArmRight"]):
				continue
			var ab := mi.mesh.get_aabb()
			for f in [Vector3(0.85, 0.5, 0.5), Vector3(0.15, 0.5, 0.5), Vector3(0.5, 0.85, 0.5),
					Vector3(0.5, 0.15, 0.5), Vector3(0.5, 0.5, 0.85), Vector3(0.5, 0.5, 0.15)]:
				var sp := cam.unproject_position(mi.global_transform * (ab.position + ab.size * f))
				if not rect.has_point(sp):
					continue
				n += 1
				if view._pick_at(sp) == fx:
					good += 1
		if n > 0:
			check(good == n, "%s: %d of %d points on its body pick it" % [fx.name, good, n])


func test_truss() -> void:
	print("truss")
	view.set_orbit(0.0, -8.0, 9.0)
	await frames(3)
	var cam: Camera3D = view._camera
	var span: StructurePiece = view._set.get_node("SpanFront2")
	var b := span.bounds
	# Along the whole front face, through the lattice gaps too.
	var good := 0
	var n := 0
	for i in 9:
		for j in [0.2, 0.5, 0.8]:
			var p := span.global_transform * (b.position + Vector3(b.size.x * (0.1 + 0.8 * i / 8.0), b.size.y * j, b.end.z))
			var got := view._pick_at(cam.unproject_position(p))
			n += 1
			if got == span:
				good += 1
	check(good == n, "SpanFront2: %d of %d points along it pick it (not the truss behind)" % [good, n])
	# Just beside the top chord, a few pixels off, still counts.
	var top := span.global_transform * Vector3(b.get_center().x + 0.3, b.end.y, b.end.z)
	var sp := cam.unproject_position(top) + Vector2(0, -3)
	check(view._pick_at(sp) == span, "3 px above the top chord still picks it")
	sp = cam.unproject_position(top) + Vector2(0, -30)
	check(view._pick_at(sp) != span, "30 px above it doesn't")


func test_program_ignores_truss() -> void:
	print("program workspace")
	ctx.set_workspace(StudioContext.Workspace.PROGRAM)
	await frames(2)
	var span: StructurePiece = view._set.get_node("SpanFront2")
	var sp := view._camera.unproject_position(span.global_transform * span.bounds.get_center())
	check(not (view._pick_at(sp) is StructurePiece), "truss pieces can't be picked while programming")
	ctx.set_workspace(StudioContext.Workspace.STAGE)


func _find_view(n: Node) -> StageView:
	if n is StageView:
		return n
	for c in n.get_children():
		var v := _find_view(c)
		if v:
			return v
	return null
