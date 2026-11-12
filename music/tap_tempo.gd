class_name TapTempo
extends RefCounted
## Works out a tempo from someone tapping along to the music. Feed it the time
## of every tap; it averages the gaps of the last few taps. A pause longer than
## `reset_after` starts a fresh count, so tapping a new song never mixes in the
## old one.

## Gap (seconds) after which the next tap starts over.
var reset_after := 2.0
## How many recent taps are averaged. More = steadier, slower to follow.
var window := 8

var _taps: PackedFloat64Array = []


## Register a tap at `time` (seconds, any steady clock). Returns the tempo in
## BPM, or 0.0 while there is only one tap and so no tempo yet.
func tap(time: float) -> float:
	if not _taps.is_empty() and time - _taps[_taps.size() - 1] > reset_after:
		_taps.clear()
	_taps.append(time)
	if _taps.size() > window:
		_taps.remove_at(0)
	if _taps.size() < 2:
		return 0.0
	var gap := (_taps[_taps.size() - 1] - _taps[0]) / float(_taps.size() - 1)
	if gap <= 0.0:
		return 0.0
	return snappedf(60.0 / gap, 0.1)


## How many taps are currently counted (0 after a pause).
func count() -> int:
	return _taps.size()


func reset() -> void:
	_taps.clear()
