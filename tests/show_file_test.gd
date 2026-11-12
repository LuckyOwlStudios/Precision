extends SceneTree
## Save and open a whole show: rig, patch, looks of fixtures, mirror pairs, truss
## set, cues; the dirty flag; sections this build doesn't know survive a save.
##   godot --headless --path . --script res://tests/show_file_test.gd

var _failed := 0
const PATH := "user://show_file_test.precision"


func _init() -> void:
	# The test saves shows, which changes "the last show" in user://session.cfg: put it back after.
	var had_session := FileAccess.file_exists(ShowManager.SESSION_FILE)
	var session_text := FileAccess.get_file_as_string(ShowManager.SESSION_FILE) if had_session else ""
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	var shows := ctx.shows
	var stage: StageView = main.get_node("%StageView")

	# A rig to save: the demo, plus things the file has to carry.
	var default_pieces := ctx.structure_pieces().size()
	_expect(default_pieces > 0, "the default set has truss pieces")
	ctx.load_demo_rig()
	await process_frame
	var fixtures := ctx.fixtures()
	var n := fixtures.size()
	var bar := fixtures[n - 1]
	var bar_channels := bar.profile.channels
	bar.pixel_colors = PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
	bar.strobe = 7
	bar.color = Color(0.25, 0.5, 0.75)
	ctx.rename_fixture(fixtures[0], "Left wash")
	fixtures[1].start_address = 100
	StageSymmetry.link(fixtures[2], fixtures[3], 2)
	var first_pos := StudioContext.fixture_transform(fixtures[4])
	ctx.record_cue()
	ctx.cue_stack.cues[0].cue_name = "Warm intro"
	ctx.cue_stack.cues[0].fade_time = 3.5
	ctx.symmetry.center = Vector3(1, 0, 0)
	bar.strobe = 9
	var look := ctx.save_look("Doors open")
	var look_id := look.id
	bar.strobe = 7

	# Dirty tracking.
	_expect(shows.is_dirty() and not shows.has_path(), "an edited, never saved show is dirty")
	_expect(shows.title() == ShowManager.UNTITLED, "untitled until saved")
	_expect(shows.save_as(PATH), "save as writes the file")
	_expect(not shows.is_dirty() and shows.title() == "show_file_test", "saving clears dirty and names the show")
	ctx.rename_fixture(fixtures[0], "Right wash")
	_expect(shows.is_dirty(), "an edit after saving makes it dirty again")
	ctx.undo()
	_expect(not shows.is_dirty(), "undoing back to the saved state is clean")

	# New: empty rig, default set.
	shows.new_show()
	await process_frame
	_expect(ctx.fixtures().is_empty(), "new show has no fixtures")
	_expect(ctx.structure_pieces().size() == default_pieces, "new show has the default set")
	_expect(ctx.cue_stack.cues.is_empty(), "new show has no cues")
	_expect(ctx.looks.looks.is_empty(), "new show has no looks")
	_expect(not shows.has_path() and not shows.is_dirty(), "new show is untitled and clean")
	_expect(not ctx.history.has_undo(), "new show has no undo history")

	# Open it again: everything is back.
	_expect(shows.open(PATH), "open succeeds")
	await process_frame
	var back := ctx.fixtures()
	_expect(back.size() == n, "all fixtures are back (%d of %d)" % [back.size(), n])
	_expect(StudioContext.display_name(back[0]) == "Left wash", "your own fixture name is back")
	_expect(back[1].start_address == 100, "patch address is back")
	var b := back[n - 1]
	_expect(b.pixel_colors.size() == 3 and b.pixel_colors[1].is_equal_approx(Color.GREEN), "per-pixel colours are back")
	_expect(b.strobe == 7 and typeof(b.strobe) == TYPE_INT, "strobe is back as an int")
	_expect(b.color.is_equal_approx(Color(0.25, 0.5, 0.75)), "colour is back")
	_expect(b.profile.channels == bar_channels, "profile channels are back")
	_expect(StudioContext.fixture_transform(back[4]).is_equal_approx(first_pos), "position and turn are back")
	_expect(StageSymmetry.partner_of(back[2]) == back[3] and int(back[2].get_meta(StageSymmetry.META_FLIP)) == 2, "mirror pair is linked again")
	_expect(ctx.cue_stack.cues.size() == 1 and ctx.cue_stack.cues[0].cue_name == "Warm intro" and is_equal_approx(ctx.cue_stack.cues[0].fade_time, 3.5), "cue is back")
	_expect(ctx.structure_pieces().size() == default_pieces, "truss set is back")
	_expect(ctx.looks.looks.size() == 1 and ctx.looks.looks[0].look_name == "Doors open" and ctx.looks.looks[0].id == look_id, "look is back with the same id")
	var restored: Dictionary = ctx.looks.looks[0].values[str(ctx.rig.get_path_to(b))]
	_expect(int(restored["strobe"]) == 9 and typeof(restored["strobe"]) == TYPE_INT, "look values are back (strobe as int)")
	_expect(ctx.symmetry.center.is_equal_approx(Vector3(1, 0, 0)), "mirror plane is back")
	_expect(shows.has_path() and not shows.is_dirty(), "an opened show is clean")
	# The next fixture added carries on the numbering.
	var par_entry: FixtureCatalog.Entry = FixtureCatalog.entries()[1]
	var added := ctx.add_fixture(par_entry, Vector3(0, 1, 0))
	_expect(String(added.name) == "Par 5", "numbering continues after open (%s)" % added.name)
	ctx.undo()

	# A moved truss piece is saved too.
	var piece := ctx.structure_pieces()[0]
	piece.position += Vector3(0.5, 0, 0)
	var moved := piece.transform
	_expect(shows.save(), "save to the same file")
	shows.new_show()
	shows.open(PATH)
	await process_frame
	_expect(ctx.structure_pieces()[0].transform.is_equal_approx(moved), "moved truss piece is back")

	# A section from somewhere else survives a round trip.
	var text := FileAccess.get_file_as_string(PATH)
	var doc: Dictionary = JSON.parse_string(text)
	doc["sections"]["future_thing"] = {"hello": [1, 2, 3]}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	_expect(shows.open(PATH), "a file with an unknown section opens")
	shows.save()
	var again: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	_expect(again["sections"].has("future_thing"), "unknown sections are written back")

	# A file from the future and a file that isn't a show are refused, and nothing changes.
	var count := ctx.fixtures().size()
	var failures: Array[String] = []
	shows.open_failed.connect(func(m: String) -> void: failures.append(m))
	doc["version"] = ShowFile.VERSION + 1
	f = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	_expect(not shows.open(PATH) and failures.size() == 1, "a newer file is refused")
	f = FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	_expect(not shows.open(PATH) and failures.size() == 2, "a damaged file is refused")
	_expect(not shows.open("user://nope.precision") and failures.size() == 3, "a missing file is refused")
	_expect(ctx.fixtures().size() == count, "a refused file changes nothing")

	# Codec round trip through real JSON text.
	var sample := {"c": Color(0.1, 0.2, 0.3, 0.4), "v": Vector3(1, 2, 3), "x": Transform3D(Basis.from_euler(Vector3(0.3, 0.2, 0.1)), Vector3(4, 5, 6)),
		"p": PackedColorArray([Color.RED]), "list": [1, "two", 3.5, true], "s": &"name"}
	var round: Dictionary = ShowCodec.decode(JSON.parse_string(JSON.stringify(ShowCodec.encode(sample))))
	_expect((round["c"] as Color).is_equal_approx(sample["c"]) and (round["v"] as Vector3).is_equal_approx(sample["v"]), "codec: Color, Vector3")
	_expect((round["x"] as Transform3D).is_equal_approx(sample["x"]), "codec: Transform3D")
	_expect((round["p"] as PackedColorArray)[0] == Color.RED and round["list"][1] == "two" and round["s"] == "name", "codec: packed arrays, lists, strings")

	DirAccess.remove_absolute(PATH)
	if had_session:
		var sf := FileAccess.open(ShowManager.SESSION_FILE, FileAccess.WRITE)
		sf.store_string(session_text)
		sf.close()
	else:
		DirAccess.remove_absolute(ShowManager.SESSION_FILE)
	print("show_file_test: ", "OK" if _failed == 0 else "%d FAILED" % _failed)
	quit(_failed)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		print("FAIL: ", what)
