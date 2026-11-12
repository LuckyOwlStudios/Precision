@tool
class_name FixtureProfile
extends Resource
## Describes a fixture's DMX channel layout. Save one as a .tres per fixture
## model / mode, and copy the channel order from the fixture's manual.
##
## Channel names DMXFixture understands:
##   dimmer, red, green, blue, white, amber, uv, strobe,
##   pan, pan_fine, tilt, tilt_fine
## Any other name (gobo, mode, macro, speed...) is allowed. Drive it with
## DMXFixture.set_raw() or give it a fixed value in `defaults`.
##
## Pixel fixtures (LED bars, pixel strips, matrices) number their per-pixel
## channels from 1: "red_1", "green_1", ... "white_28". Pixel n is the n-th
## cell of `pixel_layout`, left to right, then the next row. Build the list
## with pixel_channels() instead of typing all of them. Channels without a
## number (a master dimmer, strobe) work for the whole fixture as usual.

@export var fixture_name: String = "Generic RGB"
## Channel names in order. Index 0 = the fixture's start address.
@export var channels: PackedStringArray = PackedStringArray(["dimmer", "red", "green", "blue"]):
	set(value):
		channels = value
		_parsed = false
## How the pixels sit on the fixture: columns x rows, as seen from the front
## with the fixture the way the 3D body is built (a bar: left to right).
## (0, 0) = one row of all the pixels. Only used when the channels have pixels.
@export var pixel_layout: Vector2i = Vector2i.ZERO
## Fixed raw values (0-255) for channels like "mode" or "shutter open".
@export var defaults: Dictionary = {}
## Moving heads: how far pan and tilt travel across their full DMX range, in
## degrees (from the manual, e.g. "pan 540°, tilt 270°"). Pan/tilt 0..1 maps
## onto 0..this many degrees.
@export_range(1.0, 720.0, 1.0, "suffix:°") var pan_range_deg: float = 540.0
@export_range(1.0, 360.0, 1.0, "suffix:°") var tilt_range_deg: float = 270.0


## Parsed form of `channels`, rebuilt when they change.
var _parsed := false
var _bases: PackedStringArray = [] ## per channel: name without its pixel number
var _pixels: PackedInt32Array = [] ## per channel: 0-based pixel, or -1
var _pixel_count := 0
var _base_set: Dictionary = {} ## every base name, for has_channel


## True if the fixture has this channel, either whole-fixture ("red") or on
## its pixels ("red_1", "red_2"...).
func has_channel(channel_name: String) -> bool:
	_parse()
	return _base_set.has(channel_name)


## How many pixels the channels address; 0 for an ordinary fixture.
func pixel_count() -> int:
	_parse()
	return _pixel_count


## Columns x rows of the pixels (see pixel_layout). (1, 1) without pixels.
func pixel_grid() -> Vector2i:
	var n := pixel_count()
	if n == 0:
		return Vector2i.ONE
	if pixel_layout.x > 0 and pixel_layout.y > 0:
		return pixel_layout
	return Vector2i(n, 1)


## Name of channel `i` without its pixel number ("red_12" -> "red").
func channel_base(i: int) -> String:
	_parse()
	return _bases[i]


## 0-based pixel channel `i` belongs to, or -1 for a whole-fixture channel.
func channel_pixel(i: int) -> int:
	_parse()
	return _pixels[i]


## Short description of the channels, folding the pixel run:
## "dimmer, strobe, 28 pixels × (red, green, blue, white)".
func summary() -> String:
	_parse()
	if _pixel_count == 0:
		return ", ".join(channels)
	var parts: PackedStringArray = []
	var per_pixel: PackedStringArray = []
	var folded := false
	for i in channels.size():
		if _pixels[i] < 0:
			parts.append(channels[i])
		elif not folded:
			folded = true
			parts.append("")
		if _pixels[i] == 0:
			per_pixel.append(_bases[i])
	var text := "%d pixels × (%s)" % [_pixel_count, ", ".join(per_pixel)]
	for j in parts.size():
		if parts[j] == "":
			parts[j] = text
	return ", ".join(parts)


## Channel names for `count` pixels with `per_pixel` channels each, numbered
## from 1, with `before` / `after` (whole-fixture channels) around them.
## pixel_channels(["red", "green", "blue", "white"], 28, ["dimmer", "strobe"])
static func pixel_channels(per_pixel: PackedStringArray, count: int,
		before: PackedStringArray = [], after: PackedStringArray = []) -> PackedStringArray:
	var out := before.duplicate()
	for n in count:
		for c in per_pixel:
			out.append("%s_%d" % [c, n + 1])
	out.append_array(after)
	return out


## "red_12" -> ["red", 11]; "pan_fine" or "red" -> [name, -1].
static func split_pixel(channel_name: String) -> Array:
	var cut := channel_name.rfind("_")
	if cut > 0:
		var tail := channel_name.substr(cut + 1)
		if tail.is_valid_int() and int(tail) >= 1:
			return [channel_name.substr(0, cut), int(tail) - 1]
	return [channel_name, -1]


func _parse() -> void:
	if _parsed:
		return
	_parsed = true
	_bases.resize(channels.size())
	_pixels.resize(channels.size())
	_base_set.clear()
	_pixel_count = 0
	for i in channels.size():
		var sp := split_pixel(channels[i])
		_bases[i] = sp[0]
		_pixels[i] = sp[1]
		_base_set[sp[0]] = true
		_pixel_count = maxi(_pixel_count, int(sp[1]) + 1)
