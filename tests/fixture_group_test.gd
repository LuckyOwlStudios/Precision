extends SceneTree
## Checks named fixture groups: make from the selection, rename, recall, undo,
## persistence and the data export. Run from the project folder:
##   godot --headless --path . --script res://tests/fixture_group_test.gd

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
	ctx.groups.root_dir = "user://test_groups_%d" % randi()
	ctx.groups.load_groups()
	ctx.load_demo_rig()
	await process_frame
	var fx := ctx.fixtures()
	check(fx.size() >= 4, "demo rig has fixtures")

	check(ctx.make_group("Empty") == null, "nothing picked makes no group")
	ctx.pick([fx[0], fx[1], fx[2]])
	await process_frame
	var g := ctx.make_group("Front")
	check(g != null and g.fixtures.size() == 3, "Ctrl+G saves the three picked fixtures")
	check(ctx.make_group("front", [fx[3]]) == null, "a taken name (any case) is refused")
	var g2 := ctx.make_group("", [fx[3]])
	check(g2 != null and g2.group_name == "Group 2", "blank name gets Group N (%s)" % (g2.group_name if g2 else "null"))

	ctx.pick([])
	await process_frame
	check(ctx.recall_group(g) == 3, "recall picks three fixtures")
	await process_frame
	check(ctx.selected_group.size() == 3 and ctx.selected_group.has(fx[1]), "they are the stage group")
	ctx.recall_group(g2)
	await process_frame
	check(ctx.selected == fx[3], "a one-fixture group picks that fixture")

	ctx.rename_group(g, "Washes")
	check(g.group_name == "Washes", "rename")
	ctx.rename_group(g, "Group 2")
	check(g.group_name == "Washes", "rename to a taken name is refused")
	ctx.undo()
	check(g.group_name == "Front", "undo rename")

	var data := ctx.groups.to_data()
	check(data.size() == 2 and (data[0] as Dictionary).has("fixtures"), "to_data lists both groups")
	var back := FixtureGroup.from_dict(data[0])
	check(back.group_name == g.group_name and back.fixtures == g.fixtures, "dict round trip")

	ctx.groups.load_groups()
	check(ctx.groups.groups.size() == 2, "groups survive a reload from disk")
	g = ctx.groups.find_by_name("Front") # reloading made fresh objects

	ctx.remove_fixture(fx[2])
	await process_frame
	check(ctx.group_fixtures(g).size() == 2, "a removed fixture drops out of the group")

	ctx.pick([fx[0], fx[1]])
	await process_frame
	ctx.update_group(g)
	check(g.fixtures.size() == 2, "update from selection")
	ctx.delete_group(g)
	check(ctx.groups.groups.size() == 1, "delete")
	ctx.undo()
	check(ctx.groups.groups.size() == 2, "undo delete")

	var panel := main.find_child("OnStage", true, false) as RigPanel
	var list: ItemList = panel.get_node("%Groups")
	check(list.item_count == 2 and list.visible, "the On stage panel lists the groups")
	ctx.pick([])
	await process_frame
	list.item_selected.emit(0)
	await process_frame
	check(not ctx.selected_group.is_empty() or ctx.selected != null, "clicking a group row recalls it")

	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
