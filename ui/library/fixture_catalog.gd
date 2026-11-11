class_name FixtureCatalog
extends RefCounted
## The fixtures that appear in the library panel.
## For now these are generic profiles built in code. Later this can scan a
## folder of FixtureProfile .tres files (one per fixture model).

## Visual body used in the 3D stage. Keeps the stage independent of DMX details.
enum Body { PAR, MOVING_HEAD, BAR, STROBE }


class Entry:
	extends RefCounted
	var category: String
	var profile: FixtureProfile
	var body: Body
	var short_name: String ## "Par", used to name placed fixtures ("Par 3")

	func _init(p_category: String, p_profile: FixtureProfile, p_body: Body, p_short: String) -> void:
		category = p_category
		profile = p_profile
		body = p_body
		short_name = p_short


static func _profile(display_name: String, channels: PackedStringArray, defaults: Dictionary = {}) -> FixtureProfile:
	var p := FixtureProfile.new()
	p.fixture_name = display_name
	p.channels = channels
	p.defaults = defaults
	return p


static func entries() -> Array[Entry]:
	var list: Array[Entry] = []
	list.append(Entry.new("Pars", _profile("Generic RGB Par (3ch)", ["red", "green", "blue"]), Body.PAR, "Par"))
	list.append(Entry.new("Pars", _profile("Generic RGB Par (4ch)", ["dimmer", "red", "green", "blue"]), Body.PAR, "Par"))
	list.append(Entry.new("Pars", _profile("Generic RGBW Par (7ch)", ["dimmer", "red", "green", "blue", "white", "strobe", "mode"], {"mode": 0}), Body.PAR, "Par"))
	list.append(Entry.new("Pars", _profile("Generic RGBWA+UV Par (6ch)", ["red", "green", "blue", "white", "amber", "uv"]), Body.PAR, "Par"))
	list.append(Entry.new("Moving heads", _profile("Generic Spot Mover (9ch)", ["pan", "tilt", "dimmer", "red", "green", "blue", "white", "strobe", "speed"], {"speed": 0}), Body.MOVING_HEAD, "Mover"))
	list.append(Entry.new("Moving heads", _profile("Generic Wash Mover 16-bit (11ch)", ["pan", "pan_fine", "tilt", "tilt_fine", "dimmer", "red", "green", "blue", "white", "strobe", "speed"], {"speed": 0}), Body.MOVING_HEAD, "Mover"))
	list.append(Entry.new("Bars and strobes", _profile("Generic RGB Bar (4ch)", ["dimmer", "red", "green", "blue"]), Body.BAR, "Bar"))
	# "Wash Bar Light" (28 RGBW LEDs), from its user manual. Its 2/8-channel
	# effect modes and 112/114-channel per-pixel modes are not profiled yet.
	list.append(Entry.new("Bars and strobes", _profile("Wash Bar Light RGBW (4ch)", ["red", "green", "blue", "white"]), Body.BAR, "Bar"))
	list.append(Entry.new("Bars and strobes", _profile("Wash Bar Light RGBW (6ch)", ["dimmer", "strobe", "red", "green", "blue", "white"]), Body.BAR, "Bar"))
	list.append(Entry.new("Bars and strobes", _profile("Generic Strobe (2ch)", ["dimmer", "strobe"]), Body.STROBE, "Strobe"))
	return list
