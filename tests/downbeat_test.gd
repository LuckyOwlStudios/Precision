extends SceneTree
## Headless checks for the automatic first-beat guess. Run from the project folder:
##   godot --headless --path . --script res://tests/downbeat_test.gd

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
	await process_frame
	test_estimate()
	await test_guess()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


## A waveform with `first` seconds of near-silence, then a kick every beat.
func kicks(first: float, bpm: float, seconds: float) -> PackedFloat32Array:
	var pps := Song.PEAKS_PER_SECOND
	var peaks := PackedFloat32Array()
	peaks.resize(int(seconds * pps))
	for i in peaks.size():
		peaks[i] = 0.02
	var t := first
	while t < seconds:
		var i := roundi(t * pps)
		for j in 4:
			if i + j < peaks.size():
				peaks[i + j] = 1.0 - j * 0.2
		t += 60.0 / bpm
	return peaks


func test_estimate() -> void:
	print("Finding the first beat")
	var t := BeatGrid.estimate_first_beat(kicks(1.7, 128.0, 40.0), Song.PEAKS_PER_SECOND, 128.0)
	check(absf(t - 1.7) < 0.04, "kick after 1.7 s of quiet found at %.2f s" % t)
	t = BeatGrid.estimate_first_beat(kicks(0.0, 120.0, 40.0), Song.PEAKS_PER_SECOND, 120.0)
	check(absf(t) < 0.04, "kick on the very first sample -> %.2f s" % t)
	check(BeatGrid.estimate_first_beat(PackedFloat32Array(), 50, 128.0) < 0.0, "no waveform -> no guess")
	check(BeatGrid.estimate_first_beat(kicks(0.0, 120.0, 10.0), 50, 0.0) < 0.0, "no tempo -> no guess")


func test_guess() -> void:
	print("Guess goes into the song's beat offset")
	var ctx: StudioContext = (load("res://ui/main/studio_context.tscn") as PackedScene).instantiate()
	root.add_child(ctx)
	ctx.library.root_dir = "user://test_downbeat_%d" % Time.get_ticks_usec()
	ctx.library.songs.clear()
	var s := Song.new()
	s.id = "downbeat1"
	s.duration = 40.0
	s.bpm = 128.0
	s.peaks = kicks(1.7, 128.0, 40.0)
	ctx.library.songs.append(s)
	check(ctx.library.guess_first_beat(s) and absf(s.beat_offset - 1.7) < 0.04, "library guesses a song that has none")
	check(not s.beat_offset_set, "a guess doesn't count as set by hand")
	s.beat_offset = 0.0
	s.beat_offset_set = true
	check(not ctx.library.guess_first_beat(s) and s.beat_offset == 0.0, "a hand-set offset is left alone")
	s.beat_offset_set = false
	ctx.song = s # skip audio loading
	ctx.guess_first_beat()
	check(absf(s.beat_offset - 1.7) < 0.04 and not s.beat_offset_set, "Find first beat automatically, undoable")
	ctx.history.undo()
	check(s.beat_offset == 0.0, "undo puts it back")
	ctx.set_first_beat_here()
	check(s.beat_offset_set, "First beat here counts as set by hand")
	check(Song.from_dict(s.to_dict()).beat_offset_set, "the flag is saved")
	ctx.queue_free()
	await process_frame
