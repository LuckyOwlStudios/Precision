class_name SimulatedDJSource
extends DJSyncSource
## A pretend DJ deck, so the sync can be built and tried without DJ software
## or hardware. Load a song from your library, press play, pause, scrub and
## move the pitch, and the lights react exactly as they would to a real DJ.
##
## It deliberately behaves like a network source: it only reports its
## position every `report_interval` seconds, a little late and with random
## jitter, so the smoothing in DJSyncSource gets exercised for real.

## How often the "DJ software" reports its position.
@export var report_interval: float = 0.1
## How late each report arrives, on average (seconds).
@export var report_delay: float = 0.02
## Random extra lateness, up to this many seconds.
@export var report_jitter: float = 0.015

## Pitch fader in percent (+8 = 8 % faster).
var pitch_percent: float = 0.0:
	set(value):
		_true_pos = true_position()
		_true_us = _now_us()
		pitch_percent = clampf(value, -50.0, 50.0)
		if track and track.bpm > 0.0:
			_set_bpm(track.bpm * true_rate())

# The deck's real state (what the "DJ software" knows).
var _deck_playing := false
var _true_pos := 0.0
var _true_us := 0
var _next_report := 0.0
var _last_beat := -1
var _rng := RandomNumberGenerator.new()
var _generation := 0 ## bumped on seek/pause so late reports from before are dropped


func _init() -> void:
	source_name = "Simulator"


func start() -> void:
	_set_connected(true, "Simulator running")


func stop() -> void:
	pause()
	super()


## Put a track on the deck. Accepts a library Song or a DJTrack.
func load_track(what: Variant) -> void:
	var t: DJTrack = null
	if what is Song:
		var s: Song = what
		t = DJTrack.make(s.title, s.artist, s.source_path, s.duration, s.bpm, 1)
	elif what is DJTrack:
		t = what
	_deck_playing = false
	_true_pos = 0.0
	_true_us = _now_us()
	_last_beat = -1
	_set_playing(false)
	_set_track(t)
	_report_position(0.0)
	if t and t.bpm > 0.0:
		_set_bpm(t.bpm * true_rate())


func play() -> void:
	if track == null or _deck_playing:
		return
	_true_pos = true_position()
	_true_us = _now_us()
	_deck_playing = true
	_send_report()
	_set_playing(true)


func pause() -> void:
	if not _deck_playing:
		return
	_true_pos = true_position()
	_true_us = _now_us()
	_deck_playing = false
	_generation += 1
	_set_playing(false)
	_report_position(_true_pos)


func toggle() -> void:
	if _deck_playing:
		pause()
	else:
		play()


func seek(seconds: float) -> void:
	_true_pos = clampf(seconds, 0.0, track.duration if track and track.duration > 0.0 else seconds)
	_true_us = _now_us()
	_generation += 1
	_send_report()


func deck_playing() -> bool:
	return _deck_playing


func true_rate() -> float:
	return 1.0 + pitch_percent / 100.0


## Where the simulated deck really is (what the audience would hear).
func true_position() -> float:
	if not _deck_playing:
		return _true_pos
	return _true_pos + float(_now_us() - _true_us) / 1_000_000.0 * true_rate()


func _process(delta: float) -> void:
	if not connected or track == null:
		return
	if _deck_playing and track.duration > 0.0 and true_position() >= track.duration:
		_true_pos = track.duration
		_true_us = _now_us()
		_deck_playing = false
		_set_playing(false)
		_report_position(_true_pos)
		return
	_next_report -= delta
	if _deck_playing and _next_report <= 0.0:
		_next_report = report_interval
		_send_report()
	if _deck_playing and track.bpm > 0.0:
		var b := int(floor(true_position() * track.bpm / 60.0))
		if b != _last_beat:
			_last_beat = b
			_report_beat(b, track.bpm * true_rate())


func _send_report() -> void:
	# Read the position now, deliver it a little later, like a network would.
	var lateness := report_delay + _rng.randf() * report_jitter
	var reading := true_position()
	if not _deck_playing or lateness <= 0.0 or not is_inside_tree():
		_report_position(reading)
		return
	var gen := _generation
	get_tree().create_timer(lateness, true, false, true).timeout.connect(func() -> void:
		if _deck_playing and gen == _generation:
			_report_position(reading, lateness))
