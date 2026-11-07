extends SceneTree
## Checks that moving a base plate carries the truss built on it and the
## fixtures hung there, that a truss carries its own fixtures, and that undo
## puts it all back.
##   godot --headless --path . --script res://tests/rig_carry_test.gd

var _failed := 0


func _init() -> void:
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	ctx.load_demo_rig()
	await process_frame
	var view: StageView = _find_view(main)
	var set_root: Node3D = view.get_node("%Room").get_node("Set")
	var plate: StructurePiece = set_root.get_node("PlateFrontLeft")
	var span: StructurePiece = set_root.get_node("SpanFront2")

	var carried := view._carried(plate)
	_expect("plate carries the truss on it", carried.has(set_root.get_node("TowerFrontLeft")), true)
	_expect("plate carries the whole joined front rig", carried.has(span), true)
	_expect("plate leaves the back rig alone", carried.has(set_root.get_node("PlateBackLeft")), false)
	var fxs: Array[DMXFixture] = []
	for o in carried:
		if o is DMXFixture:
			fxs.append(o)
	_expect("plate carries fixtures hung on its rig", fxs.size() > 0, true)

	var span_carry := view._carried(span)
	var only_fixtures := true
	for o in span_carry:
		if not o is DMXFixture:
			only_fixtures = false
	_expect("a truss carries only its own fixtures", only_fixtures, true)

	# Move the plate a metre to the right, as a drag does, then undo.
	var plate_before := plate.global_transform
	var span_before := span.global_transform
	var fx: DMXFixture = fxs[0] if not fxs.is_empty() else null
	var fx_before := StudioContext.fixture_transform(fx) if fx else Transform3D.IDENTITY
	view._begin_carry(plate)
	plate.global_transform = plate_before.translated(Vector3.RIGHT)
	view._move_carry(plate, plate_before)
	view._record_carry_move(plate, plate_before, "Move truss piece")
	_expect("truss moved with the plate", span.global_position, span_before.origin + Vector3.RIGHT)
	if fx:
		_expect("fixture moved with the plate", StudioContext.fixture_transform(fx).origin, fx_before.origin + Vector3.RIGHT)
	ctx.undo()
	_expect("undo puts the plate back", plate.global_position, plate_before.origin)
	_expect("undo puts the truss back", span.global_position, span_before.origin)
	if fx:
		_expect("undo puts the fixture back", StudioContext.fixture_transform(fx).origin, fx_before.origin)

	print("rig carry test: ", "FAILED" if _failed else "ok")
	quit(1 if _failed else 0)


func _expect(label: String, got: Variant, want: Variant) -> void:
	var same := false
	if got is Vector3:
		same = (got as Vector3).is_equal_approx(want)
	else:
		same = got == want
	if not same:
		_failed += 1
		print("FAIL ", label, ": got ", got, ", wanted ", want)


func _find_view(n: Node) -> StageView:
	if n is StageView:
		return n
	for c in n.get_children():
		var v := _find_view(c)
		if v:
			return v
	return null
