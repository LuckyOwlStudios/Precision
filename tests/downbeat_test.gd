extends SceneTree
## Headless checks for downbeat alignment. Run from the project folder:
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
	await test_lead_in()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


## A waveform with `first` seconds of near-silence, then a kick every beat.
func kicks(first: float, bpm: float, seconds: float) -> PackedFloat32Array:
	var pps := Song.PEAKS_PER_SECOND
	var peaks := PackedFloat32Array()
	peaks.resize(int(seconds * pps))
	for i in peaks.size():
		peaks[i] = 0.02
	var period := 60.0 / bpm
	var t := first
	while t < seconds:
		var i := roundi(t * pps)
		for j in 4:
			if i + j < peaks.size():
				peaks[i + j] = 1.0 - j * 0.2
		t += period
	return peaks


func test_estimate() -> void:
	print("Finding the first downbeat")
	var peaks := kicks(1.7, 128.0, 40.0)
	var t := BeatGrid.estimate_first_beat(peaks, Song.PEAKS_PER_SECOND, 128.0)
	check(absf(t - 1.7) < 0.04, "kick after 1.7 s of quiet found at %.2f s" % t)
	peaks = kicks(0.0, 120.0, 40.0)
	t = BeatGrid.estimate_first_beat(peaks, Song.PEAKS_PER_SECOND, 120.0)
	check(absf(t) < 0.04, "kick on the very first sample -> %.2f s" % t)
	check(BeatGrid.estimate_first_beat(PackedFloat32Array(), 50, 128.0) < 0.0, "no waveform -> no guess")
	check(BeatGrid.estimate_first_beat(peaks, 50, 0.0) < 0.0, "no tempo -> no guess")


func test_lead_in() -> void:
	print("Show waits for the downbeat")
	var ctx: StudioContext = (load("res://ui/main/studio_context.tscn") as PackedScene).instantiate()
	root.add_child(ctx)
	ctx.library.root_dir = "user://test_downbeat_%d" % Time.get_ticks_usec()
	ctx.library.songs.clear()
	var s := Song.new()
	s.id = "downbeat1"
	s.title = "Intro Song"
	s.artist = "Tester"
	s.duration = 200.0
	s.bpm = 120.0
	s.first_beat = 2.0
	ctx.library.songs.append(s)
	ctx.load_song(s)
	check(is_equal_approx(ctx.beats_to_seconds(0.0), 2.0), "beat 0 is the downbeat at 2.0 s")
	check(is_equal_approx(ctx.seconds_to_beats(3.0), 2.0), "3.0 s is beat 2 at 120 BPM")
	check(is_equal_approx(ctx.length_beats, 396.0), "length counts from the downbeat")

	# Following a simulated DJ deck: during the 2 s intro the show holds.
	var sim: SimulatedDJSource = ctx.dj.use(DJSync.Kind.SIMULATOR)
	sim.load_track(DJTrack.make("Intro Song", "Tester"))
	await process_frame
	sim.play()
	await create_timer(0.8).timeout
	check(ctx.playing and ctx.in_lead_in and ctx.position_beats == 0.0 and ctx.show_beat() < 0.0, "intro: playing but the show holds before beat 1")
	await create_timer(1.8).timeout
	check(not ctx.in_lead_in and ctx.position_beats > 0.0 and ctx.show_beat() == ctx.position_beats, "downbeat passed: show running")
	var err := absf(ctx.beats_to_seconds(ctx.position_beats) - sim.true_position())
	check(err < 0.03, "still in step with the deck (%.1f ms off)" % (err * 1000.0))

	# Setting the downbeat by hand keeps the playhead on the same music.
	sim.pause()
	await create_timer(0.2).timeout
	var here := ctx.current_seconds()
	ctx.set_downbeat_here()
	check(is_equal_approx(s.first_beat, here) and s.first_beat_set, "Set downbeat at playhead moves the grid to %.2f s" % here)
	check(ctx.position_beats == 0.0, "playhead is now beat 0")
	check(Song.from_dict(s.to_dict()).first_beat == s.first_beat, "downbeat is saved with the song")

	ctx.dj.use(DJSync.Kind.OFF)
	ctx.queue_free()
	await process_frame
