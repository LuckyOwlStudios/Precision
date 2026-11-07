@tool
class_name DMXFixture
extends Node
## One physical light. Its properties are ordinary Godot properties, so you
## can keyframe them in an AnimationPlayer, tween them, or set them from code.
## Every frame it converts them to DMX values and writes them into its universe.

@export var universe: DMXUniverse
@export var profile: FixtureProfile
@export_range(1, 512) var start_address: int = 1

@export_group("Look")
@export_range(0.0, 1.0) var dimmer: float = 1.0
@export var color: Color = Color.WHITE
@export_range(0.0, 1.0) var white: float = 0.0
@export_range(0.0, 1.0) var amber: float = 0.0
@export_range(0.0, 1.0) var uv: float = 0.0
## Raw value. Strobe ranges differ per fixture, so check the manual.
@export_range(0, 255) var strobe: int = 0

@export_group("Position")
## 0..1 across the fixture's full range. Uses 16-bit if the profile has pan_fine.
@export_range(0.0, 1.0) var pan: float = 0.5
@export_range(0.0, 1.0) var tilt: float = 0.5

## What a running show is doing to this light right now (property -> value).
## It sits on top of the properties above for output only: the properties are
## what you programmed (inspector, looks, cues), `live` is what the timeline's
## effects make of them. Empty when nothing is playing on this light.
var live: Dictionary = {}

## Raw per-channel overrides (name -> 0..255). These take priority over everything else.
var _raw: Dictionary = {}

const LOOK_PROPERTIES := ["dimmer", "color", "white", "amber", "uv", "strobe", "pan", "tilt"]


func set_raw(channel_name: String, value: int) -> void:
	_raw[channel_name] = clampi(value, 0, 255)


func clear_raw(channel_name: String = "") -> void:
	if channel_name.is_empty():
		_raw.clear()
	else:
		_raw.erase(channel_name)


## A look property as it is being output: the show's live value if an effect is
## running on it, else the property itself. The 3D stage draws from this.
func out(prop: String) -> Variant:
	return live[prop] if live.has(prop) else get(prop)


## Snapshot of the current look, used by CueStack.record_cue().
func capture() -> Dictionary:
	var d := {}
	for p in LOOK_PROPERTIES:
		d[p] = get(p)
	return d


func _process(_delta: float) -> void:
	if universe == null or profile == null:
		return
	var chans := profile.channels
	for i in chans.size():
		universe.set_channel(start_address + i, _value_for(chans[i]))


func _value_for(channel_name: String) -> int:
	if _raw.has(channel_name):
		return _raw[channel_name]

	# Fixtures with no dimmer channel get a virtual dimmer applied to the colors.
	var d: float = out("dimmer")
	var c: Color = out("color")
	var k := 1.0 if profile.has_channel("dimmer") else d
	match channel_name:
		"dimmer": return _u8(d)
		"red": return _u8(c.r * k)
		"green": return _u8(c.g * k)
		"blue": return _u8(c.b * k)
		"white": return _u8(float(out("white")) * k)
		"amber": return _u8(float(out("amber")) * k)
		"uv": return _u8(float(out("uv")) * k)
		"strobe": return int(out("strobe"))
		"pan": return _coarse(float(out("pan")))
		"pan_fine": return _fine(float(out("pan")))
		"tilt": return _coarse(float(out("tilt")))
		"tilt_fine": return _fine(float(out("tilt")))

	if profile.defaults.has(channel_name):
		return clampi(int(profile.defaults[channel_name]), 0, 255)
	return 0


static func _u8(x: float) -> int:
	return clampi(roundi(x * 255.0), 0, 255)


static func _coarse(x: float) -> int:
	return (clampi(roundi(x * 65535.0), 0, 65535) >> 8) & 0xFF


static func _fine(x: float) -> int:
	return clampi(roundi(x * 65535.0), 0, 65535) & 0xFF
