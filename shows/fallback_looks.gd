class_name FallbackLooks
extends RefCounted
## Looks that play by themselves when a song has no programmed show (an unknown
## track from the DJ, or a song you haven't programmed yet), so the lights are
## never dark or stuck while someone plays.
##
## The look is picked from the song's tempo and loops every CYCLE_BEATS beats,
## so it stays locked to the music whatever the pitch. Inside a cycle the
## energy moves like a phrase: it grooves, builds, then lifts before looping.
## Tempo is the only thing we always know; if a link later reports energy, it
## can pick the tier instead (see tier_for).
##
## A look is an ordinary SongShow built from the same effect clips as a
## programmed show, so ShowPlayer plays it with no special cases. It is never
## saved and never touches the song's own show.

enum Tier { CHILL, GROOVE, DRIVE, HARD }

const CYCLE_BEATS := 64.0
const BUILD_AT := 48.0 ## the build and the lift of each cycle
const LIFT_AT := 56.0
const HYSTERESIS_BPM := 3.0 ## a tempo must pass a boundary by this much to switch tier
## Upper tempo of each tier but the last.
const LIMITS: Array[float] = [100.0, 124.0, 140.0]
const NAMES: Array[String] = ["Chill", "Groove", "Drive", "Hard"]


## Which tier fits `bpm`. Pass the tier in use as `current` to stop it flickering
## when the tempo hovers around a boundary (a pitch fader nudged near 124).
## Unknown tempo (0 or less) counts as 120. Very slow tempos are taken as
## half-time (70 BPM hip-hop feels like 140).
static func tier_for(bpm: float, current: int = -1) -> Tier:
	if bpm <= 0.0:
		bpm = 120.0
	if bpm < 70.0:
		bpm *= 2.0
	var t := _raw_tier(bpm)
	if current >= 0 and current != t and absf(bpm - _nearest_limit(bpm)) < HYSTERESIS_BPM:
		return current as Tier
	return t


static func tier_name(t: Tier) -> String:
	return NAMES[t]


static func _raw_tier(bpm: float) -> Tier:
	for i in LIMITS.size():
		if bpm < LIMITS[i]:
			return i as Tier
	return Tier.HARD


static func _nearest_limit(bpm: float) -> float:
	var best := LIMITS[0]
	for l in LIMITS:
		if absf(l - bpm) < absf(best - bpm):
			best = l
	return best


## The look for `tier` on `targets` (fixture paths, in effect order). Fixtures
## that can't do an effect (a sweep on a par) are skipped by ShowPlayer.
static func build(tier: Tier, targets: PackedStringArray) -> SongShow:
	var show := SongShow.new()
	var all := CYCLE_BEATS
	var level: float = [0.6, 0.8, 0.9, 1.0][tier]
	var cycle_beats: float = [64.0, 32.0, 32.0, 16.0][tier]
	var saturation: float = [0.8, 0.9, 1.0, 1.0][tier]
	var pulse_beats: float = [2.0, 1.0, 1.0, 1.0][tier]
	var pulse_depth: float = [0.4, 0.6, 0.8, 1.0][tier]

	_add(show, "dimmer", {"level": level}, 0.0, all, targets)
	_add(show, "rainbow", {"beats": cycle_beats, "saturation": saturation, "spread": 0.25}, 0.0, all, targets)
	match tier:
		Tier.CHILL:
			_add(show, "sweep", {"axis": 0, "width": 70.0, "beats": 16.0, "spread": 0.5}, 0.0, all, targets)
		Tier.GROOVE:
			_add(show, "circle", {"size": 35.0, "beats": 8.0, "spread": 1.0}, 0.0, all, targets)
		Tier.DRIVE:
			_add(show, "circle", {"size": 40.0, "beats": 4.0, "spread": 1.0}, 0.0, all, targets)
		Tier.HARD:
			_add(show, "circle", {"size": 50.0, "beats": 2.0, "spread": 0.5}, 0.0, all, targets)
	_add(show, "pulse", {"beats": pulse_beats, "depth": pulse_depth}, 0.0, all, targets)

	# The phrase: a chase while it builds, a strobe on the lift. Chill stays calm.
	match tier:
		Tier.GROOVE:
			_add(show, "chase", {"beats": 1.0}, BUILD_AT, all - BUILD_AT, targets)
		Tier.DRIVE:
			_add(show, "chase", {"beats": 0.5, "bounce": true}, BUILD_AT, LIFT_AT - BUILD_AT, targets)
			_add(show, "strobe", {"rate": 1.0, "duty": 0.3}, LIFT_AT, all - LIFT_AT, targets)
		Tier.HARD:
			_add(show, "chase", {"beats": 0.25, "bounce": true}, BUILD_AT, LIFT_AT - BUILD_AT, targets)
			_add(show, "strobe", {"rate": 4.0, "duty": 0.2}, LIFT_AT, all - LIFT_AT, targets)
	return show


static func _add(show: SongShow, template: String, params: Dictionary, start: float, length: float, targets: PackedStringArray) -> void:
	var c := ShowClip.new()
	c.clip_name = EffectTemplates.display_name(template)
	c.template = template
	c.params = EffectTemplates.defaults(template)
	c.params.merge(params, true)
	c.start = start
	c.length = length
	c.targets = targets.duplicate()
	show.clips.append(c)
