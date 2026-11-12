extends SceneTree
## Action registry and Ctrl+K palette. Run:
##   godot --headless --path . --script res://tests/palette_test.gd

var _fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _initialize() -> void:
	# Fuzzy matching.
	_check(ActionRegistry.fuzzy_score("dpl", "Fixture Duplicate") >= 0, "subsequence matches")
	_check(ActionRegistry.fuzzy_score("xyz", "Fixture Duplicate") < 0, "non-match is -1")
	_check(ActionRegistry.fuzzy_score("dup", "Fixture Duplicate") > ActionRegistry.fuzzy_score("dup", "Do unrelated pieces"), "tight match beats scattered")
	_check(ActionRegistry.fuzzy_score("go live", "Workspace Go to Live") >= 0, "every word must match, any order of spacing")

	var reg := ActionRegistry.new()
	var ran: Array[String] = []
	var on := [true]
	reg.register(&"a.undo", "Undo", func() -> void: ran.append("undo"), {category = "Edit", shortcut = "Ctrl+Z", keywords = "revert"})
	reg.register(&"a.dup", "Duplicate", func() -> void: ran.append("dup"), {category = "Fixture", enabled = func() -> bool: return on[0]})
	_check(reg.count() == 2, "two registered")
	_check(reg.search("").size() == 2, "empty query lists all")
	_check(reg.search("revert")[0].id == &"a.undo", "keywords are searched")
	_check(reg.search("dup")[0].id == &"a.dup", "title search")
	on[0] = false
	_check(reg.search("dup").is_empty(), "disabled actions hidden")
	on[0] = true
	reg.register(&"a.undo", "Undo again", func() -> void: pass)
	_check(reg.count() == 2, "same id replaces")
	reg.unregister(&"a.undo")
	_check(reg.count() == 1, "unregister")

	# The palette scene: type, arrow, Enter.
	var pal: CommandPalette = load("res://ui/palette/command_palette.tscn").instantiate()
	root.add_child(pal)
	pal.setup(reg)
	await process_frame
	pal.open()
	await process_frame
	_check(pal.visible, "opens")
	var field: LineEdit = pal.get_node("%Field")
	field.text = "dup"
	field.text_changed.emit("dup")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	field.gui_input.emit(enter)
	_check(ran == ["dup"], "Enter runs the action: " + str(ran))
	_check(not pal.visible, "closes after running")

	print("palette tests: ", "OK" if _fails == 0 else "%d failed" % _fails)
	quit(1 if _fails else 0)
