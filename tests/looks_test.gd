extends SceneTree
## Checks the Looks shelf: save, apply with undo, rename, delete, and that looks
## survive a reload from disk.
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
