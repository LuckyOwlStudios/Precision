class_name LedRingPreview
extends RefCounted
## What the 3D stage draws on a fixture's LED ring (the "LED Ring Beam").
## The fixture's manual gives the ring no per-LED DMX channels: one channel
## picks one of 51 built-in effects ("Each 4 values as an effect") and another
## sets their speed. The manual does not say what the effects look like, so
## these are stand-ins: the effect number only picks a pattern and a colour
## from a small set, so different values look different on the preview.
## Replace `pattern()` once the real effects are known.

const LED_COUNT := 30
const EFFECT_COUNT := 51
const _PATTERNS := 6


## 1..51 for the value of the ring effect channel (52 = effect 1, each 4 more
## is the next one), or 0 for "inner effect" (0-51: the ring's built-in show).
static func effect_number(value: int) -> int:
	if value < 52:
		return 0
	return mini((value - 52) / 4 + 1, EFFECT_COUNT)


## Turns per second at ring speed value 0..255 (slow to fast).
static func turns_per_second(speed: int) -> float:
	return lerpf(0.15, 2.5, clampf(speed / 255.0, 0.0, 1.0))


## The colour of each of the `count` LEDs at time `t` seconds. `base` is the
## fixture's own colour (not used yet: the built-in effects have their own colours).
static func leds(effect_value: int, speed: int, t: float, base: Color, count: int = LED_COUNT) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(count)
	var n := effect_number(effect_value)
	var turn := fposmod(t * turns_per_second(speed), 1.0)
	for i in count:
		out[i] = pattern(n, i / float(count), turn, base)
	return out


## One LED: `pos` 0..1 round the ring from the top, clockwise; `turn` 0..1
## through one cycle of the effect.
static func pattern(effect: int, pos: float, turn: float, base: Color) -> Color:
	if effect == 0:
		# Inner effect: a slow colour wash round the ring.
		return Color.from_hsv(fposmod(pos + turn, 1.0), 0.85, 1.0)
	var hue_shift: float = fposmod(effect * 0.137, 1.0)
	match (effect - 1) % _PATTERNS:
		0: # rainbow rolling round
			return Color.from_hsv(fposmod(pos - turn + hue_shift, 1.0), 1.0, 1.0)
		1: # one comet with a tail
			var d := fposmod(turn - pos, 1.0)
			return Color.from_hsv(hue_shift, 1.0, clampf(1.0 - d * 4.0, 0.0, 1.0))
		2: # two opposite comets
			var d2 := fposmod(turn * 2.0 - pos * 2.0, 1.0)
			return Color.from_hsv(hue_shift, 1.0, clampf(1.0 - d2 * 3.0, 0.0, 1.0))
		3: # half the ring lit, swapping sides
			var on := fposmod(pos - turn, 1.0) < 0.5
			return Color.from_hsv(hue_shift, 1.0, 1.0) if on else Color.from_hsv(fposmod(hue_shift + 0.5, 1.0), 1.0, 1.0)
		4: # the whole ring fading through colours
			return Color.from_hsv(fposmod(turn + hue_shift, 1.0), 1.0, 1.0)
		_: # red, green and blue thirds spinning
			var third := int(floorf(fposmod(pos - turn, 1.0) * 3.0))
			return [Color.RED, Color.GREEN, Color.BLUE][third]
