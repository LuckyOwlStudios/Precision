class_name FixtureCatalog
extends RefCounted
## The fixtures that appear in the library panel.
## The built-in profiles are built in code; the person's own (made or imported
## in the profile editor) come from ProfileStore and are listed after them
## under "My fixtures".

const USER_CATEGORY := "My fixtures"
const _SHORT_NAMES: PackedStringArray = ["Par", "Mover", "Bar", "Strobe"] ## indexed by Body

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
	# effect modes are not profiled yet.
	var rgbw := PackedStringArray(["red", "green", "blue", "white"])
	list.append(Entry.new("Bars and strobes", _profile("Wash Bar Light RGBW (4ch)", rgbw), Body.BAR, "Bar"))
	list.append(Entry.new("Bars and strobes", _profile("Wash Bar Light RGBW (6ch)", ["dimmer", "strobe", "red", "green", "blue", "white"]), Body.BAR, "Bar"))
	list.append(Entry.new("Bars and strobes", _profile("Wash Bar Light 28 pixels (112ch)", FixtureProfile.pixel_channels(rgbw, 28)), Body.BAR, "Bar"))
	list.append(Entry.new("Bars and strobes", _profile("Wash Bar Light 28 pixels (114ch)", FixtureProfile.pixel_channels(rgbw, 28, ["dimmer", "strobe"])), Body.BAR, "Bar"))
	list.append(Entry.new("Bars and strobes", _profile("Generic Strobe (2ch)", ["dimmer", "strobe"]), Body.STROBE, "Strobe"))
	for p in ProfileStore.load_all():
		var body := clampi(p.body_style, 0, _SHORT_NAMES.size() - 1) as Body
		list.append(Entry.new(USER_CATEGORY, p, body, _SHORT_NAMES[body]))
	return list
