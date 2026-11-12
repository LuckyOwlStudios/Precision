class_name EffectTemplates
extends RefCounted
## The built-in effect types. A template is a recipe: it says which settings it
## has (so the UI can build sliders for them) and how to change a fixture's
## values at a moment in the clip. Presets are a template plus chosen settings.
##
## Time is in beats from the start of the clip, so effects stay locked to the
## music whatever the tempo, and scrubbing or following the DJ always shows the
## same frame for the same spot in the song.
##
## Effects layer: each one changes only the properties it is about, starting
## from what the layers under it produced. A circle moves pan/tilt around
## wherever the light was aimed; a strobe gates the dimmer; so a spin and a
## strobe on the same moving head simply add up.

## Setting kinds.
const FLOAT := "float"
const COLOR := "color"
const BOOL := "bool"
const CHOICE := "choice"

## "Spread" (0..1) staggers the fixtures of a clip: 0 = all in step, 1 = spaced
## evenly through one loop (a circle fan, a rolling wave).

## Lane colours on the timeline, by what an effect touches.
const MOVE_COLOR := Color("4fa3ff")
const DIMMER_COLOR := Color("ffb547")
const COLOR_COLOR := Color("c86bff")


static func ids() -> PackedStringArray:
	return PackedStringArray(["circle", "sweep", "strobe", "pulse", "chase", "rainbow", "color", "dimmer"])


## {id, name, description, color, params: [{key, label, kind, min, max, step, unit, default, options}]}
static func get_template(id: String) -> Dictionary:
	match id:
		"circle":
			return _t(id, "Circle", "Moving heads trace a circle around where they are aimed.", MOVE_COLOR, [
				_f("size", "Size", 0.0, 120.0, 1.0, "°", 25.0),
				_f("beats", "Beats per loop", 0.25, 32.0, 0.25, " beats", 4.0),
				_b("reverse", "Reverse direction", false),
				_f("spread", "Spread", 0.0, 1.0, 0.05, "", 0.0),
			])
		"sweep":
			return _t(id, "Sweep", "Swing back and forth, left-right (pan) or up-down (tilt).", MOVE_COLOR, [
				_c("axis", "Direction", ["Pan", "Tilt"], 0),
				_f("width", "Width", 0.0, 270.0, 1.0, "°", 60.0),
				_f("beats", "Beats per swing", 0.25, 32.0, 0.25, " beats", 4.0),
				_f("spread", "Spread", 0.0, 1.0, 0.05, "", 0.0),
			])
		"strobe":
			return _t(id, "Strobe", "Flash on and off in time with the beat.", DIMMER_COLOR, [
				_f("rate", "Flashes per beat", 0.25, 8.0, 0.25, "", 2.0),
				_f("duty", "On time", 0.05, 0.95, 0.05, "", 0.3),
				_f("spread", "Spread", 0.0, 1.0, 0.05, "", 0.0),
			])
		"pulse":
			return _t(id, "Pulse", "Punch up on every beat and fade away.", DIMMER_COLOR, [
				_f("beats", "Beats per pulse", 0.25, 16.0, 0.25, " beats", 1.0),
				_f("depth", "Depth", 0.0, 1.0, 0.05, "", 1.0),
				_f("spread", "Spread", 0.0, 1.0, 0.05, "", 0.0),
			])
		"chase":
			return _t(id, "Chase", "Light one fixture at a time, moving along the group.", DIMMER_COLOR, [
				_f("beats", "Beats per step", 0.25, 8.0, 0.25, " beats", 1.0),
				_b("reverse", "Reverse direction", false),
				_b("bounce", "Bounce back", false),
				_b("pixels", "Along each bar's pixels", false),
			])
		"rainbow":
			return _t(id, "Rainbow", "Cycle through every colour.", COLOR_COLOR, [
				_f("beats", "Beats per cycle", 1.0, 64.0, 1.0, " beats", 16.0),
				_f("saturation", "Saturation", 0.0, 1.0, 0.05, "", 1.0),
				_f("spread", "Spread", 0.0, 1.0, 0.05, "", 0.25),
				_f("pixel_spread", "Spread across pixels", 0.0, 1.0, 0.05, "", 1.0),
			])
		"color":
			return _t(id, "Colour", "Change colour for the length of the clip.", COLOR_COLOR, [
				{"key": "color", "label": "Colour", "kind": COLOR, "default": Color("ff3b6b")},
			])
		"dimmer":
			return _t(id, "Dimmer", "Set the brightness for the length of the clip.", DIMMER_COLOR, [
				_f("level", "Level", 0.0, 1.0, 0.05, "", 1.0),
			])
	return {}


## What a fixture needs for this effect: "move" = pan or tilt, "color" = RGB,
## "light" = anything that can change brightness (a dimmer, or colour/white
## channels it can dim virtually).
static func needs(id: String) -> String:
	match id:
		"circle", "sweep":
			return "move"
		"rainbow", "color":
			return "color"
	return "light"


## Can this fixture do this effect? A crowd sweep on a par can't.
static func supports(id: String, fx: DMXFixture) -> bool:
	if fx == null or fx.profile == null:
		return false
	var pr := fx.profile
	match needs(id):
		"move":
			return pr.has_channel("pan") or pr.has_channel("tilt")
		"color":
			return pr.has_channel("red") and pr.has_channel("green") and pr.has_channel("blue")
	for ch in ["dimmer", "red", "green", "blue", "white", "amber", "uv", "strobe"]:
		if pr.has_channel(ch):
			return true
	return false


## Short reason shown when a fixture can't do an effect.
static func needs_text(id: String) -> String:
	match needs(id):
		"move":
			return "needs a moving head (pan/tilt)"
		"color":
			return "needs a colour (RGB) fixture"
	return "needs a fixture that can dim"


static func display_name(id: String) -> String:
	return str(get_template(id).get("name", id))


static func lane_color(id: String) -> Color:
	return get_template(id).get("color", Color.GRAY)


## Every setting with its default, so a preset or clip missing one still works.
static func defaults(id: String) -> Dictionary:
	var d := {}
	for p: Dictionary in get_template(id).get("params", []):
		d[p.key] = p.default
	return d


## Change `v` (property -> value, already holding what the layers below made)
## for one fixture. `t` is beats since the clip started; `index`/`count` place
## this fixture within the clip's fixtures, for spread and chases.
static func apply(id: String, params: Dictionary, t: float, index: int, count: int, fx: DMXFixture, v: Dictionary) -> void:
	var p := defaults(id)
	p.merge(params, true)
	var offset := (float(index) / maxf(1.0, count)) * float(p.get("spread", 0.0))
	match id:
		"circle":
			var dir := -1.0 if p.reverse else 1.0
			var a := TAU * (t / maxf(0.01, p.beats) + offset) * dir
			v.pan = clampf(v.pan + p.size * cos(a) / _pan_range(fx), 0.0, 1.0)
			v.tilt = clampf(v.tilt + p.size * sin(a) / _tilt_range(fx), 0.0, 1.0)
		"sweep":
			var s := sin(TAU * (t / maxf(0.01, p.beats) * 0.5 + offset)) * float(p.width) * 0.5
			if int(p.axis) == 0:
				v.pan = clampf(v.pan + s / _pan_range(fx), 0.0, 1.0)
			else:
				v.tilt = clampf(v.tilt + s / _tilt_range(fx), 0.0, 1.0)
		"strobe":
			var phase := fposmod(t * p.rate + offset, 1.0)
			if phase >= p.duty:
				v.dimmer = 0.0
		"pulse":
			var phase := fposmod(t / maxf(0.01, p.beats) + offset, 1.0)
			v.dimmer *= lerpf(1.0, pow(1.0 - phase, 2.0), p.depth)
		"chase":
			var px := fx.profile.pixel_count() if p.pixels else 0
			var steps := px if px > 0 else maxi(1, count)
			var step := int(floor(t / maxf(0.01, p.beats)))
			var pos := step % steps
			if p.bounce and steps > 1:
				var cycle := (steps - 1) * 2
				pos = step % cycle
				if pos >= steps:
					pos = cycle - pos
			if p.reverse:
				pos = steps - 1 - pos
			if px > 0:
				# One pixel lit at a time, running along the bar.
				var colors := PackedColorArray()
				var whites := PackedFloat32Array()
				colors.resize(px)
				whites.resize(px)
				var on_color: Color = v.color
				for i in px:
					var c: Color = v.pixel_colors[i] if i < v.pixel_colors.size() else on_color
					var w: float = v.pixel_whites[i] if i < v.pixel_whites.size() else float(v.white)
					colors[i] = c if i == pos else Color.BLACK
					whites[i] = w if i == pos else 0.0
				v.pixel_colors = colors
				v.pixel_whites = whites
			elif pos != index:
				v.dimmer = 0.0
		"rainbow":
			var hue := fposmod(t / maxf(0.01, p.beats) + offset, 1.0)
			v.color = Color.from_hsv(hue, p.saturation, 1.0)
			var px := fx.profile.pixel_count()
			if px > 1 and p.pixel_spread > 0.0:
				# Pixel bars: the colours roll along the bar.
				var colors := PackedColorArray()
				colors.resize(px)
				for i in px:
					colors[i] = Color.from_hsv(fposmod(hue + p.pixel_spread * i / px, 1.0), p.saturation, 1.0)
				v.pixel_colors = colors
			else:
				v.pixel_colors = PackedColorArray() # whole bar in one colour
		"color":
			v.color = p.color
			v.pixel_colors = PackedColorArray() # a colour clip colours every pixel
		"dimmer":
			v.dimmer = p.level


static func _pan_range(fx: DMXFixture) -> float:
	return fx.profile.pan_range_deg if fx and fx.profile and fx.profile.pan_range_deg > 0.0 else 540.0


static func _tilt_range(fx: DMXFixture) -> float:
	return fx.profile.tilt_range_deg if fx and fx.profile and fx.profile.tilt_range_deg > 0.0 else 270.0


static func _t(id: String, p_name: String, desc: String, color: Color, params: Array) -> Dictionary:
	return {"id": id, "name": p_name, "description": desc, "color": color, "params": params}


static func _f(key: String, label: String, lo: float, hi: float, step: float, unit: String, def: float) -> Dictionary:
	return {"key": key, "label": label, "kind": FLOAT, "min": lo, "max": hi, "step": step, "unit": unit, "default": def}


static func _b(key: String, label: String, def: bool) -> Dictionary:
	return {"key": key, "label": label, "kind": BOOL, "default": def}


static func _c(key: String, label: String, options: Array, def: int) -> Dictionary:
	return {"key": key, "label": label, "kind": CHOICE, "options": options, "default": def}
