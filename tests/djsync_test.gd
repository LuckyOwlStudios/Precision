extends SceneTree
## Headless checks for DJ sync. Run from the project folder:
##   godot --headless --path . --script res://tests/djsync_test.gd
## The VirtualDJ check needs the fake VirtualDJ server running first:
##   python3 tests/fake_virtualdj.py &      (then add -- vdj to the command)

var failures := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


## A source whose clock we move by hand.
class ManualClock extends DJSyncSource:
	var now_us := 1_000_000
	func _now_us() -> int:
		return now_us


func _init() -> void:
	await process_frame
	test_matcher()
	test_clock()
	test_os2l_parser()
	test_vdj_parsing()
	await test_follow_simulator()
	if "vdj" in OS.get_cmdline_user_args():
		await test_virtualdj()
	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func song(title: String, artist: String, src: String, duration: float = 200.0, bpm: float = 120.0) -> Song:
	var s := Song.new()
	s.id = title.md5_text().substr(0, 16)
	s.title = title
	s.artist = artist
	s.source_path = src
	s.duration = duration
	s.bpm = bpm
	s.show_name = title + " show"
	return s


func test_matcher() -> void:
	print("Track matching")
	var a := song("Strobe", "deadmau5", "C:\\Music\\deadmau5 - Strobe.mp3")
	var b := song("Levels (Original Mix)", "Avicii", "/music/levels.mp3")
	var c := song("Intro", "Artist One", "/m/one-intro.mp3")
	var d := song("Intro", "Artist Two", "/m/two-intro.mp3")
	var e := song("Titanium", "David Guetta & Sia", "/m/titanium.wav")
	var lib: Array[Song] = [a, b, c, d, e]

	check(TrackMatcher.find(DJTrack.make("whatever", "", "c:/music/DEADMAU5 - strobe.mp3"), lib) == a, "same file, different slashes and case")
	check(TrackMatcher.find(DJTrack.make("", "", "/Volumes/USB/levels.mp3"), lib) == b, "same file name in another folder")
	check(TrackMatcher.find(DJTrack.make("Strobe", "Deadmau5"), lib) == a, "title + artist")
	check(TrackMatcher.find(DJTrack.make("Levels", "Avicii"), lib) == b, "loose: (Original Mix) ignored")
	check(TrackMatcher.find(DJTrack.make("Intro", "Artist Two"), lib) == d, "same title, artist decides")
	check(TrackMatcher.find(DJTrack.make("Intro", ""), lib) == null, "ambiguous title gives no match")
	check(TrackMatcher.find(DJTrack.make("Titanium", "Sia and David Guetta feat. Nobody"), lib) == e, "collaborators in any order")
	check(TrackMatcher.find(DJTrack.make("", "", "D:/dj/deadmau5 - Strobe (Extended).flac"), lib) == a, "Artist - Title from file name")
	check(TrackMatcher.find(DJTrack.make("Unknown Song", "Nobody"), lib) == null, "unknown track gives null")


func test_clock() -> void:
	print("Clock smoothing")
	var src := ManualClock.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	src._set_track(DJTrack.make("t"))
	src._report_position(10.0)
	src._set_playing(true)
	# The DJ plays at +4 % pitch; reports every 100 ms, 0-30 ms late.
	var truth := 10.0
	var worst := 0.0
	for i in 100:
		src.now_us += 100_000
		truth += 0.1 * 1.04
		var late := rng.randf() * 0.03
		src._report_position(truth - late * 1.04, late)
		if i > 30:
			worst = maxf(worst, absf(src.position_seconds() - truth))
	check(worst < 0.012, "follows a pitched, jittery deck within 12 ms (worst %.1f ms)" % (worst * 1000.0))
	check(absf(src.rate() - 1.04) < 0.01, "measures the pitch (%.3f)" % src.rate())
	# Between reports it keeps running.
	src.now_us += 50_000
	check(absf(src.position_seconds() - (truth + 0.052)) < 0.012, "runs on between reports")
	# Seek: jumps straight away.
	var jumped := [-1.0]
	src.position_jumped.connect(func(s: float) -> void: jumped[0] = s)
	src._report_position(60.0)
	check(is_equal_approx(src.position_seconds(), 60.0) and is_equal_approx(jumped[0], 60.0), "a seek jumps at once")
	# Pause freezes.
	src._set_playing(false)
	var frozen := src.position_seconds()
	src.now_us += 2_000_000
	check(is_equal_approx(src.position_seconds(), frozen), "pause freezes the position")
	src.free()


func test_os2l_parser() -> void:
	print("OS2L messages")
	var l := OS2LListener.new()
	var beats: Array = []
	l.beat_received.connect(func(pos: int, bpm: float, change: bool, _s: float) -> void: beats.append([pos, bpm, change]))
	var rest := l.feed('{"evt":"beat","change":false,"pos":21,"bpm":121.96,"strength":0.9}{"evt":"beat","change":true,"pos":1,"bpm":128.0,"str')
	check(beats.size() == 1 and beats[0][0] == 21 and is_equal_approx(beats[0][1], 121.96), "one whole message read")
	rest = l.feed(rest + 'ength":0.5}\n')
	check(beats.size() == 2 and beats[1][2] == true and rest == "", "split message joined up")
	var btn := [""]
	l.button_received.connect(func(n: String, _p: String, on: bool) -> void: btn[0] = n if on else "")
	l.feed('{"evt":"btn","name":"Strobe {fast}","page":"p","state":"on"}')
	check(btn[0] == "Strobe {fast}", "braces inside strings are fine")
	l.free()


func test_vdj_parsing() -> void:
	print("VirtualDJ answers")
	check(VirtualDJSource.parse_duration("243.5") == 243.5, "seconds")
	check(VirtualDJSource.parse_duration("4:03") == 243.0, "m:ss")
	check(VirtualDJSource.parse_duration("1:04:03") == 3843.0, "h:mm:ss")
	check(VirtualDJSource.parse_bool("yes") and VirtualDJSource.parse_bool("true") and not VirtualDJSource.parse_bool("off"), "booleans")
	check(VirtualDJSource.strip_quotes("'Strobe'") == "Strobe", "quotes stripped")


func make_studio() -> StudioContext:
	var ctx := StudioContext.new()
	var dir := "user://test_djsync_%d" % Time.get_ticks_usec()
	ctx.ready.connect(func() -> void: ctx.library.root_dir = dir, CONNECT_ONE_SHOT)
	root.add_child(ctx)
	ctx.library.root_dir = dir
	ctx.library.songs.clear()
	return ctx


func frames(n: int) -> void:
	for i in n:
		await process_frame


func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func test_follow_simulator() -> void:
	print("Following the simulator")
	var ctx := make_studio()
	var a := song("Alpha", "DJ One", "/m/alpha.mp3", 180.0, 120.0)
	var b := song("Bravo", "DJ Two", "/m/bravo.mp3", 200.0, 128.0)
	ctx.library.songs.append_array([a, b])
	var started: Array[Song] = []
	ctx.show_started.connect(func(s: Song) -> void: started.append(s))

	var sim: SimulatedDJSource = ctx.dj.use(DJSync.Kind.SIMULATOR)
	check(ctx.following_dj(), "DJ sync on")
	sim.load_track(DJTrack.make("Alpha", "DJ One"))
	check(ctx.song == a and ctx.dj.match_how == "title and artist", "loading Alpha on the deck loads Alpha's show")
	check(not ctx.playing, "not playing until the DJ plays")

	sim.play()
	await wait(1.0)
	check(ctx.playing and started == [a], "DJ plays -> show starts")
	var err := absf(ctx.beats_to_seconds(ctx.position_beats) - sim.true_position())
	check(err < 0.03, "playhead follows the deck (%.1f ms off)" % (err * 1000.0))

	sim.pause()
	await frames(3)
	var held := ctx.position_beats
	await wait(0.3)
	check(not ctx.playing and is_equal_approx(held, ctx.position_beats), "DJ pauses -> show pauses and holds")

	sim.play()
	await wait(0.3)
	check(ctx.playing and ctx.position_beats > held and started.size() == 2, "DJ resumes -> show continues from there")

	sim.seek(90.0)
	await wait(0.2)
	err = absf(ctx.beats_to_seconds(ctx.position_beats) - sim.true_position())
	check(err < 0.03, "DJ jumps to 1:30 -> lights jump too (%.1f ms off)" % (err * 1000.0))

	sim.pitch_percent = 6.0
	await wait(2.0)
	err = absf(ctx.beats_to_seconds(ctx.position_beats) - sim.true_position())
	check(err < 0.03, "pitch +6 %% -> still in step (%.1f ms off)" % (err * 1000.0))

	sim.load_track(b)
	await frames(2)
	check(ctx.song == b and not ctx.playing, "DJ loads Bravo -> Bravo's show is ready")
	sim.play()
	await wait(0.3)
	check(ctx.playing and started.back() == b, "and starts with it")

	sim.load_track(DJTrack.make("Not In Library", "Someone"))
	await frames(2)
	check(ctx.song == null and ctx.dj.matched == null, "unknown track -> timeline cleared, lights wait")

	ctx.toggle_play()
	check(not ctx.playing, "local play button does nothing while following")

	ctx.dj.use(DJSync.Kind.OFF)
	check(not ctx.following_dj(), "sync off")
	ctx.queue_free()
	await frames(2)


func test_virtualdj() -> void:
	print("VirtualDJ over HTTP (fake server)")
	var ctx := make_studio()
	var s := song("Strobe", "deadmau5", "C:/Music/strobe.mp3", 200.0, 128.0)
	ctx.library.songs.append(s)
	var vdj: VirtualDJSource = ctx.dj.use(DJSync.Kind.VIRTUALDJ, {"host": "127.0.0.1", "port": 18080, "os2l_port": 19996})
	await wait(1.5)
	check(vdj.connected, "connects")
	check(ctx.song == s, "VirtualDJ's track matched to the library (%s)" % ctx.dj.match_how)
	check(ctx.playing, "playing")
	# Ask the fake server where it really is, and compare.
	var http := HTTPRequest.new()
	root.add_child(http)
	var worst := 0.0
	for i in 5:
		var t0 := Time.get_ticks_usec()
		http.request("http://127.0.0.1:18080/truth")
		var res: Array = await http.request_completed
		var rtt := float(Time.get_ticks_usec() - t0) / 1_000_000.0
		var truth := (res[3] as PackedByteArray).get_string_from_utf8().to_float() + rtt / 2.0
		worst = maxf(worst, absf(vdj.position_seconds() - truth))
		await wait(0.2)
	check(worst < 0.04, "position within 40 ms of VirtualDJ (worst %.1f ms)" % (worst * 1000.0))

	# OS2L beats from the "DJ software".
	var beats := [0]
	vdj.beat.connect(func(_n: int, _b: float) -> void: beats[0] += 1)
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", 19996)
	for i in 30:
		peer.poll()
		if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		await process_frame
	peer.put_data('{"evt":"beat","change":false,"pos":5,"bpm":128.0,"strength":1}'.to_utf8_buffer())
	await frames(5)
	check(beats[0] == 1, "OS2L beat received")

	http.request("http://127.0.0.1:18080/pause")
	await http.request_completed
	await wait(0.5)
	check(not ctx.playing, "VirtualDJ pauses -> show pauses")
	http.request("http://127.0.0.1:18080/quit")
	await http.request_completed
	await wait(2.5)
	check(not vdj.connected, "notices VirtualDJ went away")
	ctx.dj.use(DJSync.Kind.OFF)
	ctx.queue_free()
	await frames(2)
