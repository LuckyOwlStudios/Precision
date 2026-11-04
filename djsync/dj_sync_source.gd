class_name DJSyncSource
extends Node
## Base class for anything that tells us what the DJ is doing: DJ software
## over the network, a hardware player, or the built-in simulator.
##
## An adapter only has to report what it hears, using the _report_* calls.
## This class turns those (late, jittery) reports into a smooth clock that
## the lights can follow every frame: position_seconds() keeps running
## between reports at the speed the DJ is playing, and small differences are
## eased out instead of jumping. A real jump (the DJ seeks or a new track
## starts) snaps straight to the new position.
##
## Show logic never talks to an adapter directly; DJSync listens to these
## signals and drives the StudioContext transport.

## The link to the DJ software came up or went down. `detail` is a short
## human-readable status ("Connected to VirtualDJ on 127.0.0.1:80").
signal connection_changed(connected: bool, detail: String)
## The DJ started a different track (null = the deck is empty).
signal track_changed(track: DJTrack)
## Playing or paused/stopped.
signal play_state_changed(playing: bool)
## The position jumped (seek, cue, loop back, new track). Small drift does
## not fire this.
signal position_jumped(seconds: float)
## A beat landed. `beat_number` counts up from the protocol's start
## (or 0 if it doesn't count); `bpm` is the tempo being heard.
signal beat(beat_number: int, bpm: float)
## The heard tempo changed (pitch fader or a new track).
signal tempo_changed(bpm: float)

## Differences bigger than this are treated as a jump, not drift.
const JUMP_SECONDS := 0.25
## Fraction of a small difference removed on each report. Lower = smoother,
## higher = tighter.
const SLEW := 0.25
## Rate is measured over at least this long, so jitter between two close
## reports can't make the clock speed up or slow down.
const RATE_WINDOW := 0.75

var source_name: String = "DJ source"
var connected: bool = false
var status_detail: String = "Not connected"
var track: DJTrack
var playing: bool = false
## Tempo the audience hears (track BPM times the pitch). 0 if unknown.
var bpm: float = 0.0
## Exact length of the current track when we know it better than the
## protocol does (DJSync sets it from the matched library song). Adapters
## that read the position as a fraction of the track use it. Cleared on
## every track change.
var duration_hint: float = 0.0

# Clock: position = _anchor_pos + (now - _anchor_us) * _rate while playing.
var _anchor_pos: float = 0.0
var _anchor_us: int = 0
var _rate: float = 1.0
var _rate_fixed: bool = false ## adapter reports the rate itself
# Reference raw report for measuring the rate.
var _ref_pos: float = -1.0
var _ref_us: int = 0


## Start listening / connecting. Adapters override.
func start() -> void:
	pass


## Disconnect and go quiet. Adapters override and call super().
func stop() -> void:
	_set_connected(false, "Stopped")


## Where the DJ is in the current track right now, in seconds of the track
## (so pitching up makes it run faster, as the audio does).
func position_seconds() -> float:
	if not playing:
		return _anchor_pos
	return _anchor_pos + float(_now_us() - _anchor_us) / 1_000_000.0 * _rate


## Playback speed relative to the track's own tempo (1.0 = no pitch).
func rate() -> float:
	return _rate


# --------------------------------------------------------- for adapters

func _set_connected(value: bool, detail: String) -> void:
	if value == connected and detail == status_detail:
		return
	connected = value
	status_detail = detail
	connection_changed.emit(value, detail)
	if not value and playing:
		_set_playing(false)


func _set_track(t: DJTrack) -> void:
	if t != null and t.is_empty():
		t = null
	if t == null and track == null:
		return
	if t != null and t.same_as(track):
		track = t # keep the newer details (duration, bpm...)
		return
	track = t
	duration_hint = 0.0
	_ref_pos = -1.0
	if not _rate_fixed:
		_rate = 1.0
	track_changed.emit(t)


func _set_playing(value: bool) -> void:
	if value == playing:
		return
	# Freeze or restart the clock at the current estimate.
	_anchor_pos = position_seconds()
	_anchor_us = _now_us()
	_ref_pos = -1.0
	playing = value
	play_state_changed.emit(value)


func _set_bpm(value: float) -> void:
	if value <= 0.0 or is_equal_approx(value, bpm):
		return
	bpm = value
	tempo_changed.emit(value)


## The DJ software said the track is at `seconds`. `age` is how old that
## reading already is when it reaches us (e.g. half a network round trip).
## Pass `p_rate` if the protocol knows the pitch; otherwise it is measured.
func _report_position(seconds: float, age: float = 0.0, p_rate: float = -1.0) -> void:
	var now := _now_us()
	if p_rate > 0.0:
		_rate = clampf(p_rate, 0.25, 4.0)
		_rate_fixed = true
	if playing:
		seconds += age * _rate # it has moved on since the reading was taken
	var predicted := position_seconds()
	var error := seconds - predicted

	if not playing or absf(error) > JUMP_SECONDS:
		var jumped := absf(error) > JUMP_SECONDS
		_anchor_pos = seconds
		_anchor_us = now
		_ref_pos = seconds
		_ref_us = now
		if jumped:
			position_jumped.emit(seconds)
		return

	# Measure speed over a long enough window to ignore jitter.
	if not _rate_fixed:
		if _ref_pos < 0.0:
			_ref_pos = seconds
			_ref_us = now
		else:
			var dt := float(now - _ref_us) / 1_000_000.0
			if dt >= RATE_WINDOW:
				var measured := (seconds - _ref_pos) / dt
				if measured > 0.5 and measured < 1.5:
					_rate = lerpf(_rate, measured, 0.5)
				_ref_pos = seconds
				_ref_us = now

	# Ease out the small difference.
	_anchor_pos = predicted + error * SLEW
	_anchor_us = now


func _report_beat(beat_number: int, p_bpm: float) -> void:
	_set_bpm(p_bpm)
	beat.emit(beat_number, p_bpm)


## Overridable so tests can drive time by hand.
func _now_us() -> int:
	return Time.get_ticks_usec()
