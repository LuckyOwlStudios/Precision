class_name BeatGrid
extends RefCounted
## Guesses where a track's beat grid starts, from its waveform and tempo.
##
## The waveform has one peak per 1/pps seconds (20 ms at 50), so the guess is
## good to about a frame of that. It is only a starting point: you can nudge
## it with "Set downbeat at playhead".

## The first time the track is this loud (0..1 of its loudest peak) counts
## as the music starting.
const LOUD := 0.3
## Only this much of the start is used to find the grid.
const WINDOW_SECONDS := 60.0


## Seconds into the track where the first downbeat is, or -1 if there is
## nothing to go on. Assumes the first beat you can hear is a downbeat, which
## is how DJ tracks are cut.
static func estimate_first_beat(peaks: PackedFloat32Array, pps: int, bpm: float) -> float:
	if bpm <= 0.0 or peaks.size() < 4:
		return -1.0
	var period := 60.0 / bpm * pps # samples per beat
	var count := mini(peaks.size(), int(WINDOW_SECONDS * pps))
	var start := -1
	for i in count:
		if peaks[i] >= LOUD:
			start = i
			break
	if start < 0:
		return -1.0
	# Which phase of the beat do the sudden rises in loudness line up with?
	var best_phase := 0
	var best_score := -1.0
	for ph in ceili(period):
		var score := 0.0
		var k := 0
		while true:
			var i := roundi(ph + k * period)
			if i >= count:
				break
			if i > 0:
				score += maxf(0.0, peaks[i] - peaks[i - 1])
			k += 1
		if score > best_score:
			best_score = score
			best_phase = ph
	# The grid line at or just before where the music starts (half a beat of
	# slack, since the first hit can land a little early or late).
	var k0 := maxi(0, ceili((start - best_phase - 0.5 * period) / period))
	return (best_phase + k0 * period) / pps
