extends SceneTree
## Checks effects on the timeline: presets become clips, clips run in parallel
## and layer (a circle and a strobe on the same mover), fades, the live layer
## leaving programmed values alone, undo, presets you save, and a song's show
## saving and loading.
##   godot --headless --path . --script res://tests/effects_test.gd

var _failed := 0


func _init() -> void:
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	ctx.effects.root_dir = "user://effects_test"
	ctx.effects.load_presets()
	for p in ctx.effects.presets.duplicate():
		ctx.effects.remove(p)
	_expect(ctx.effects.presets.size() == EffectPresetLibrary.built_ins().size(), "built-in presets are on the shelf")

	ctx.load_demo_rig()
	var movers := ctx.fixtures().filter(func(f: DMXFixture) -> bool: return f.profile.has_channel("pan"))
	_expect(movers.size() >= 2, "demo rig has movers")
	var mover: DMXFixture = movers[0]
	var base_pan := mover.pan
	var base_dimmer := mover.dimmer

	var circle := ctx.effects.find("builtin_00")
	var strobe: EffectPreset
	for p in ctx.effects.presets:
		if p.template == "strobe":
			strobe = p
			break
	var group: Array[DMXFixture] = []
	group.append(mover)
	var c1 := ctx.add_clip(circle, 0.0, group)
	var c2 := ctx.add_clip(strobe, 0.0, group)
	_expect(ctx.show.clips.size() == 2 and ctx.selected_clip == c2, "dropping presets adds clips")

	# Beat 1 of a 4-beat circle: a quarter of the way round, pan is back at
	# centre and tilt is at the top. Strobe at 2 flashes/beat, 30% on: off at 0.5.
	ctx.show_player.evaluate(ctx.show, 1.2)
	_expect(mover.live.has("pan") and not is_equal_approx(float(mover.live.tilt), mover.tilt), "circle moves the head")
	_expect(is_equal_approx(float(mover.live.dimmer), 0.0), "strobe gates the dimmer at the same time")
	_expect(is_equal_approx(mover.pan, base_pan) and is_equal_approx(mover.dimmer, base_dimmer), "programmed values are untouched")
	ctx.show_player.evaluate(ctx.show, 1.05)
	_expect(is_equal_approx(float(mover.live.dimmer), base_dimmer), "strobe on part of the flash")
	ctx.show_player.evaluate(ctx.show, 200.0)
	_expect(mover.live.is_empty(), "nothing after the clips end")

	# Fade in: halfway through a 4-beat fade, a Blackout clip is half way.
	var black: EffectPreset
	for p in ctx.effects.presets:
		if p.template == "dimmer":
			black = p
	var c3 := ctx.add_clip(black, 32.0, group)
	var before := c3.to_data()
	c3.fade_in = 4.0
	ctx.record_clip_change(c3, before)
	ctx.show_player.evaluate(ctx.show, 34.0)
	_expect(is_equal_approx(float(mover.live.dimmer), base_dimmer * 0.5), "fade in blends half way")
	ctx.undo()
	_expect(is_zero_approx(c3.fade_in), "undo the fade")
	ctx.undo()
	_expect(not ctx.show.clips.has(c3), "undo the add")
	ctx.redo()
	_expect(ctx.show.clips.has(c3), "redo the add")
	ctx.remove_clip(c3)
	_expect(not ctx.show.clips.has(c3), "delete a clip")

	# Spread: two movers in one circle start at different points.
	var pair: Array[DMXFixture] = []
	pair.append(movers[0])
	pair.append(movers[1])
	var fan := ctx.add_clip(circle, 64.0, pair)
	var b2 := fan.to_data()
	fan.params.spread = 1.0
	ctx.record_clip_change(fan, b2)
	ctx.show_player.evaluate(ctx.show, 64.0)
	var t0 := float(movers[0].live.tilt) - movers[0].tilt
	var t1 := float(movers[1].live.tilt) - movers[1].tilt
	var p0 := float(movers[0].live.pan) - movers[0].pan
	var p1 := float(movers[1].live.pan) - movers[1].pan
	_expect(p0 > 0.0 and p1 < 0.0 and absf(t0) < 0.001 and absf(t1) < 0.001, "spread puts the second mover on the other side")

	# Effects only go on fixtures that can do them.
	var pars := ctx.fixtures().filter(func(f: DMXFixture) -> bool: return not f.profile.has_channel("pan") and not f.profile.has_channel("tilt"))
	_expect(not pars.is_empty(), "demo rig has fixtures without pan/tilt")
	var par_only: Array[DMXFixture] = []
	par_only.append(pars[0])
	_expect(ctx.add_clip(circle, 96.0, par_only) == null, "a circle can't go on a par")
	var everyone := ctx.add_clip(circle, 96.0, ctx.fixtures())
	_expect(everyone.targets.size() == ctx.fixtures_supporting("circle").size() and everyone.targets.size() == movers.size(), "on the whole rig, only the movers get the circle")
	_expect(ctx.add_clip(strobe, 96.0, par_only) != null, "a strobe can go on a par")

	# Selecting a clip; selecting a fixture puts the fixture back.
	ctx.select_clip(everyone)
	_expect(ctx.selected_clip == everyone, "select a clip")
	ctx.select(mover)
	_expect(ctx.selected_clip == null, "selecting a fixture clears the clip selection")

	# Your own preset.
	c1.params.size = 60.0
	var mine := ctx.save_clip_as_preset(c1, "Big circle")
	_expect(mine != null and ctx.effects.presets.has(mine), "save as preset")
	_expect(ctx.save_clip_as_preset(c1, "big CIRCLE") == null, "preset names are unique")
	ctx.effects.load_presets()
	var found := false
	for p in ctx.effects.presets:
		if p.preset_name == "Big circle" and is_equal_approx(float(p.params.size), 60.0):
			found = true
	_expect(found, "your preset comes back from disk")

	# A song's show saves and loads with the song.
	var song := Song.new()
	song.id = "effects_test_song"
	song.duration = 120.0
	song.bpm = 120.0
	ctx.library.root_dir = "user://effects_test"
	ctx.song = song # skip audio loading: set the song and load its show directly
	ctx.show.file_path = ""
	ctx.save_show()
	_expect(song.show_id == song.id and FileAccess.file_exists(ctx.library.show_path_for(song)), "the show is saved for the song")
	var n := ctx.show.clips.size()
	ctx._load_show(null)
	_expect(ctx.show.clips.is_empty(), "another song starts with an empty show")
	ctx._load_show(song)
	_expect(ctx.show.clips.size() == n, "loading the song brings its show back")

	for p in ctx.effects.presets.duplicate():
		ctx.effects.remove(p)
	DirAccess.remove_absolute(ctx.library.show_path_for(song))
	print("effects_test: %s" % ("FAILED (%d)" % _failed if _failed else "all passed"))
	quit(1 if _failed else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
