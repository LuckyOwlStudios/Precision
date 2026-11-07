extends SceneTree
## Checks the Looks shelf: save, apply with undo, rename, delete, unique names,
## edit mode, and that looks survive a reload from disk.
##   godot --headless --path . --script res://tests/looks_test.gd

var _failed := 0


func _init() -> void:
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	ctx.looks.root_dir = "user://looks_test"
	ctx.looks.load_looks()
	for l in ctx.looks.looks.duplicate():
		ctx.looks.remove(l)

	ctx.load_demo_rig()
	var fx := ctx.fixtures()[0]
	fx.color = Color.RED
	var look := ctx.save_look("Warm up")
	_expect(ctx.looks.looks.size() == 1 and look.look_name == "Warm up", "save adds a look to the shelf")
	_expect(ctx.save_look("").look_name != "", "an empty name gets a default")

	fx.color = Color.BLUE
	ctx.apply_look(look, 0.0)
	_expect(fx.color == Color.RED, "apply puts the fixture back to the saved colour")
	ctx.undo()
	_expect(fx.color == Color.BLUE, "undo restores what was on stage")
	ctx.redo()
	_expect(fx.color == Color.RED, "redo applies it again")

	ctx.rename_look(look, "Doors open")
	_expect(look.look_name == "Doors open", "rename")
	ctx.looks.load_looks()
	_expect(ctx.looks.looks.size() == 2, "looks come back from disk")
	var names := ctx.looks.looks.map(func(l: Look) -> String: return l.look_name)
	_expect(names.has("Doors open"), "renamed look was saved")

	# Names are unique (ignoring case and spaces).
	_expect(ctx.save_look(" doors OPEN ") == null, "a duplicate name is refused")
	_expect(ctx.looks.looks.size() == 2, "nothing was added for the duplicate")
	# load_looks() made fresh Look objects, so find them again by name.
	look = ctx.looks.looks[0] if ctx.looks.looks[0].look_name == "Doors open" else ctx.looks.looks[1]
	var other: Look = ctx.looks.looks[1] if look == ctx.looks.looks[0] else ctx.looks.looks[0]
	ctx.rename_look(other, "Doors open")
	_expect(other.look_name != "Doors open", "rename to a taken name is refused")

	# Edit mode: changes only go into the look on Save changes.
	look = ctx.looks.looks[0] if ctx.looks.looks[0].look_name == "Doors open" else ctx.looks.looks[1]
	fx.color = Color.GREEN
	ctx.begin_look_edit(look)
	_expect(ctx.editing_look == look and fx.color == Color.RED, "edit puts the look on stage")
	fx.color = Color.YELLOW
	ctx.cancel_look_edit()
	_expect(ctx.editing_look == null and fx.color == Color.GREEN, "cancel puts the stage back")
	_expect(look.values[str(ctx.rig.get_path_to(fx))]["color"] == Color.RED, "cancel leaves the look alone")
	ctx.begin_look_edit(look)
	fx.color = Color.YELLOW
	ctx.finish_look_edit(4.0)
	_expect(look.values[str(ctx.rig.get_path_to(fx))]["color"] == Color.YELLOW and is_equal_approx(look.fade_time, 4.0), "save changes stores the stage and fade")
	ctx.undo()
	_expect(look.values[str(ctx.rig.get_path_to(fx))]["color"] == Color.RED, "undo takes the edit back")
	ctx.redo()

	var back: Look = ctx.looks.looks[0]
	ctx.delete_look(back)
	_expect(ctx.looks.looks.size() == 1, "delete removes it")
	ctx.undo()
	_expect(ctx.looks.looks.size() == 2, "undo brings it back")

	for l in ctx.looks.looks.duplicate():
		ctx.looks.remove(l)
	print("looks_test: %s" % ("FAILED (%d)" % _failed if _failed else "all passed"))
	quit(1 if _failed else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
