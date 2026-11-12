extends SceneTree
## Checks position presets and by-reference shows: save/apply/undo a position,
## a "Position" clip following the position when it is updated, a "Look" clip
## following its look, an effect clip following its linked preset (and
## unlinking on change), and positions surviving a reload from disk.
##   godot --headless --path . --script res://tests/presets_test.gd

var _failed := 0


func _init() -> void:
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	ctx.positions.clear()
	ctx.looks.clear()
	ctx.effects.root_dir = "user://presets_test"
	ctx.effects.load_presets()
	for p in ctx.effects.presets.duplicate():
		ctx.effects.remove(p)

	ctx.load_demo_rig()
	var movers: Array[DMXFixture] = []
	for f in ctx.fixtures():
		if f.profile.has_channel("pan"):
			movers.append(f)
	_expect(movers.size() >= 2, "demo rig has movers")
	var m: DMXFixture = movers[0]

	# Save / apply / undo.
	m.pan = 0.25
	m.tilt = 0.75
	ctx.select(m)
	var pos := ctx.save_position("Front")
	_expect(pos != null and pos.values.size() == 1, "save position from the selection")
	_expect(ctx.save_position(" front ") == null, "duplicate position name refused")
	m.pan = 0.9
	ctx.apply_position(pos, 0.0)
	_expect(is_equal_approx(m.pan, 0.25) and is_equal_approx(m.tilt, 0.75), "apply aims the head")
	ctx.undo()
	_expect(is_equal_approx(m.pan, 0.9), "undo puts it back")

	# A Position clip follows the position by reference.
	var clip := ctx.add_reference_clip("position", pos.id, pos.position_name, 0.0, [m])
	_expect(clip != null and ctx.show.clips.has(clip), "position clip added")
	m.pan = 0.5
	ctx.show_player.evaluate(ctx.show, 1.0)
	_expect(is_equal_approx(m.live.get("pan", -1.0), 0.25), "clip aims at the saved position")
	m.pan = 0.6
	m.tilt = 0.1
	ctx.select(m)
	ctx.update_position(pos)
	ctx.show_player.evaluate(ctx.show, 1.0)
	_expect(is_equal_approx(m.live.get("pan", -1.0), 0.6), "updating the position changes the show")
	ctx.undo()
	ctx.show_player.evaluate(ctx.show, 1.0)
	_expect(is_equal_approx(m.live.get("pan", -1.0), 0.25), "undo of the update changes it back")
	ctx.rename_position(pos, "Stage front")
	ctx.show_player.evaluate(ctx.show, 1.0)
	_expect(is_equal_approx(m.live.get("pan", -1.0), 0.25), "renaming keeps the link")
	ctx.positions.from_data(JSON.parse_string(JSON.stringify(ShowCodec.encode(ctx.positions.to_data()))))
	_expect(ctx.positions.find(pos.id) != null, "position survives the show file")
	ctx.positions.remove(ctx.positions.find(pos.id))
	ctx.show_player.evaluate(ctx.show, 1.0)
	_expect(not m.live.has("pan") or is_equal_approx(m.live.pan, m.pan), "a deleted position does nothing")

	# A Look clip follows the look.
	m.color = Color.RED
	var look := ctx.save_look("Red")
	var lc := ctx.add_reference_clip("look", look.id, look.look_name, 32.0, [m])
	ctx.show_player.evaluate(ctx.show, 33.0)
	_expect(m.live.get("color") == Color.RED, "look clip shows the look")
	look.values[str(ctx.rig.get_path_to(m))]["color"] = Color.BLUE
	ctx.show_player.evaluate(ctx.show, 33.0)
	_expect(m.live.get("color") == Color.BLUE, "editing the look changes the show")
	ctx.show_player.evaluate(ctx.show, 0.0)
	_expect(lc != null, "look clip exists")

	# Both shelves are part of the show file, and a new show starts without them.
	_expect(ctx.looks.looks.size() == 1, "one look before the file round trip")
	var look_data: Variant = JSON.parse_string(JSON.stringify(ShowCodec.encode(ctx.looks.to_data())))
	ctx.looks.clear()
	_expect(ctx.looks.looks.is_empty(), "a new show has no looks")
	ctx.looks.from_data(look_data)
	_expect(ctx.looks.find(look.id) != null and ctx.looks.looks[0].values[str(ctx.rig.get_path_to(m))]["color"] == Color.BLUE, "looks come back from the show file")
	look = ctx.looks.find(look.id)

	# Effect clips stay linked to their preset until changed.
	var pulse := EffectPreset.make("Mine", "dimmer", {"level": 0.2}, 8.0)
	ctx.effects.add(pulse)
	var ec := ctx.add_clip(pulse, 64.0, [m] as Array[DMXFixture])
	_expect(ec.preset_id == pulse.id, "a clip made from a preset is linked to it")
	ctx.show_player.evaluate(ctx.show, 65.0)
	_expect(is_equal_approx(m.live.get("dimmer"), 0.2), "plays the preset's settings")
	pulse.params = {"level": 0.6}
	ctx.show_player.evaluate(ctx.show, 65.0)
	_expect(is_equal_approx(m.live.get("dimmer"), 0.6), "editing the preset changes the clip")
	ctx.unlink_clip(ec)
	pulse.params = {"level": 0.9}
	ctx.show_player.evaluate(ctx.show, 65.0)
	_expect(ec.preset_id == "" and is_equal_approx(m.live.get("dimmer"), 0.6), "unlinked clip keeps its own settings")
	ec.params.level = 0.3
	_expect(ctx.update_preset_from_clip(ec, pulse) and ec.preset_id == pulse.id, "update preset from clip relinks")
	ctx.show_player.evaluate(ctx.show, 65.0)
	_expect(is_equal_approx(m.live.get("dimmer"), 0.3) and is_equal_approx(pulse.params.level, 0.3), "preset now matches the clip")
	var builtin := ctx.effects.find("builtin_00")
	_expect(not ctx.update_preset_from_clip(ec, builtin), "built-in presets can't be updated")

	for p in ctx.effects.presets.duplicate():
		ctx.effects.remove(p)
	print("presets_test: %s" % ("FAILED (%d)" % _failed if _failed else "all passed"))
	quit(1 if _failed else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
