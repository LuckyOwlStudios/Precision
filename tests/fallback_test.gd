extends SceneTree
## Checks the fallback looks: tempo picks a tier (with hysteresis), the look
## is a normal show that loops, and it plays only for songs with no show while
## the lights are live, including an unknown track from the DJ.
##   godot --headless --path . --script res://tests/fallback_test.gd

var _failed := 0


func _init() -> void:
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	var was_enabled := AppSettings.fallback_looks
	AppSettings.fallback_looks = true

	# Tempo -> tier.
	_expect(FallbackLooks.tier_for(90.0) == FallbackLooks.Tier.CHILL, "90 BPM is chill")
	_expect(FallbackLooks.tier_for(120.0) == FallbackLooks.Tier.GROOVE, "120 BPM is groove")
	_expect(FallbackLooks.tier_for(128.0) == FallbackLooks.Tier.DRIVE, "128 BPM is drive")
	_expect(FallbackLooks.tier_for(174.0) == FallbackLooks.Tier.HARD, "174 BPM is hard")
	_expect(FallbackLooks.tier_for(0.0) == FallbackLooks.Tier.GROOVE, "unknown tempo counts as 120")
	_expect(FallbackLooks.tier_for(70.0) == FallbackLooks.Tier.HARD, "70 BPM is read as half-time (140), hard")
	_expect(FallbackLooks.tier_for(125.0, FallbackLooks.Tier.GROOVE) == FallbackLooks.Tier.GROOVE, "just over a boundary keeps the current tier")
	_expect(FallbackLooks.tier_for(130.0, FallbackLooks.Tier.GROOVE) == FallbackLooks.Tier.DRIVE, "well over a boundary switches")

	# The look itself.
	var targets := PackedStringArray(["A", "B"])
	for t in FallbackLooks.NAMES.size():
		var show := FallbackLooks.build(t as FallbackLooks.Tier, targets)
		var inside := true
		for c in show.clips:
			inside = inside and c.start >= 0.0 and c.end() <= FallbackLooks.CYCLE_BEATS and c.targets == targets
		_expect(not show.clips.is_empty() and inside, "%s look stays inside its cycle" % FallbackLooks.NAMES[t])
		_expect(show.file_path.is_empty(), "%s look is never saved" % FallbackLooks.NAMES[t])

	# When it plays.
	ctx.load_demo_rig()
	ctx.load_song(null)
	ctx.bpm = 128.0
	ctx.playing = true
	ctx.set_workspace(StudioContext.Workspace.PROGRAM)
	_expect(ctx.fallback_show() == null, "not while programming (Program workspace, no DJ)")
	ctx.set_workspace(StudioContext.Workspace.LIVE)
	var fb := ctx.fallback_show()
	_expect(fb != null and ctx.fallback_name() == "Drive", "live and playing with no show: Drive look at 128 BPM")
	ctx.show_player.evaluate(fb, 8.0)
	var lit := ctx.fixtures().any(func(f: DMXFixture) -> bool: return not f.live.is_empty())
	_expect(lit, "the look drives the fixtures")
	ctx.show_player.release_all()
	ctx.playing = false
	_expect(ctx.fallback_show() == null, "not while stopped")
	ctx.playing = true
	AppSettings.fallback_looks = false
	_expect(ctx.fallback_show() == null, "the setting turns it off")
	AppSettings.fallback_looks = true
	var clip := ShowClip.new()
	clip.targets = PackedStringArray([ctx.fixture_path(ctx.fixtures()[0])])
	ctx.show.clips.append(clip)
	_expect(ctx.fallback_show() == null, "a song with a programmed show plays its own")
	ctx.show.clips.clear()

	# An unknown track from the DJ keeps the lights going.
	var sim := ctx.dj.use(DJSync.Kind.SIMULATOR) as SimulatedDJSource
	ctx.playing = false
	var unknown := Song.new()
	unknown.id = "fallback_test_unknown"
	unknown.title = "Not in the library"
	unknown.source_path = "/nowhere/unknown.mp3"
	unknown.duration = 200.0
	unknown.bpm = 150.0
	sim.load_track(unknown)
	sim.toggle()
	await process_frame
	await process_frame
	_expect(ctx.song == null and ctx.playing, "unknown DJ track: playing with no song")
	_expect(ctx.fallback_show() != null and ctx.fallback_name() == "Hard", "unknown DJ track at 150 BPM: Hard look")
	ctx.dj.use(DJSync.Kind.OFF)

	AppSettings.fallback_looks = was_enabled
	print("fallback_test: %s" % ("FAILED (%d)" % _failed if _failed else "all passed"))
	quit(1 if _failed else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
