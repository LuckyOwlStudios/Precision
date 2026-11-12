class_name ProfileImport
extends RefCounted
## Turns outside fixture descriptions into FixtureProfiles:
##   - a channel list typed or pasted from a manual (from_text)
##   - an Open Fixture Library fixture, as its .json (from_ofl)
##   - a GDTF file (from_gdtf)
## Every importer returns {"profiles": Array[FixtureProfile], "notes": PackedStringArray}
## with one profile per DMX mode; notes are things it had to guess or skip.

## Channel names DMXFixture understands.
const STANDARD: PackedStringArray = ["dimmer", "red", "green", "blue", "white", "amber", "uv",
		"strobe", "pan", "pan_fine", "tilt", "tilt_fine"]
## Colours that can repeat per pixel ("red_1", "red_2"...).
const COLOURS: PackedStringArray = ["red", "green", "blue", "white", "amber", "uv"]

const _COLOUR_WORDS := {
	"red": "red", "green": "green", "blue": "blue", "white": "white", "amber": "amber",
	"uv": "uv", "ultraviolet": "uv", "violet": "uv",
	"warm": "white", "cold": "white", "cool": "white",
	"r": "red", "g": "green", "b": "blue", "w": "white", "a": "amber",
}
const _DIMMER_WORDS: PackedStringArray = ["dimmer", "master", "intensity", "brightness", "dim"]
const _STROBE_WORDS: PackedStringArray = ["strobe", "shutter", "flash"]


# --- Names ---------------------------------------------------------------

## "Master Dimmer" -> "dimmer", "Strobe / Shutter" -> "strobe", "Pan Fine" ->
## "pan_fine", "Red 3" -> "red_3", "Color wheel" -> "color_wheel". Anything it
## doesn't know becomes a tidy lower-case name of its own.
static func normalize_name(text: String) -> String:
	var tokens := _tokens(text)
	if tokens.is_empty():
		return ""
	var last_number := 0
	if tokens.size() > 1 and tokens[-1].is_valid_int():
		last_number = int(tokens[-1])
		tokens.remove_at(tokens.size() - 1)
	for axis: String in ["pan", "tilt"]:
		if tokens.has(axis) and not tokens.has("speed"):
			var fine := tokens.has("fine") or tokens.has("lsb") or tokens.has("16bit") or tokens.has("16")
			return axis + ("_fine" if fine else "")
	var role := ""
	if tokens.size() <= 3:
		for t in tokens:
			if _COLOUR_WORDS.has(t) and (t.length() > 1 or tokens.size() == 1):
				role = _COLOUR_WORDS[t]
				break
	if role.is_empty():
		for t in tokens:
			if _STROBE_WORDS.has(t):
				return "strobe"
		for t in tokens:
			if _DIMMER_WORDS.has(t):
				return "dimmer"
		role = ""
	if not role.is_empty():
		return role if last_number == 0 else "%s_%d" % [role, last_number]
	return sanitize("_".join(tokens) + (str(last_number) if last_number > 0 else ""))


## Lower-case letters and digits with single underscores, and no trailing
## "_3" (which would mean "pixel 3" to FixtureProfile).
static func sanitize(text: String) -> String:
	var out := "_".join(_tokens(text))
	var cut := out.rfind("_")
	if cut > 0 and out.substr(cut + 1).is_valid_int():
		out = out.substr(0, cut) + out.substr(cut + 1)
	return out if not out.is_empty() else "channel"


static func _tokens(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur := ""
	for ch in text.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			cur += ch
		elif not cur.is_empty():
			out.append(cur)
			cur = ""
	if not cur.is_empty():
		out.append(cur)
	return out


## Makes `name` unique among `used` ("gobo" -> "gobo2") and records it.
static func unique(name: String, used: Dictionary) -> String:
	var out := name
	var n := 2
	while used.has(out):
		out = "%s%d" % [name, n]
		n += 1
	used[out] = true
	return out


# --- Typed or pasted list ----------------------------------------------------

## Channel names from a pasted chart. Lines like "1 Dimmer", "CH2: Red 0-255",
## "3. Green" or tab-separated table rows work; so does a plain list of names.
static func from_text(text: String) -> PackedStringArray:
	var numbered := RegEx.new()
	numbered.compile("^\\s*(?:ch(?:annel)?\\.?\\s*)?(\\d+)\\s*[\\.\\):\\-\\t ]\\s*(.*)$")
	var range_tail := RegEx.new()
	range_tail.compile("\\s*[\\(\\[]?\\s*\\d+\\s*(?:-|–|~|to)\\s*\\d+.*$")
	var paren_tail := RegEx.new()
	paren_tail.compile("\\s*\\(.*$")
	var lines := text.split("\n", false)
	var picked: PackedStringArray = []
	var any_numbered := false
	for line in lines:
		if numbered.search(line) != null:
			any_numbered = true
			break
	for line in lines:
		var raw := line.strip_edges()
		if raw.is_empty():
			continue
		var label := raw
		var m := numbered.search(raw)
		if m != null:
			label = m.get_string(2)
		elif any_numbered:
			continue
		if "\t" in label:
			label = label.split("\t")[0]
		label = range_tail.sub(label, "")
		label = paren_tail.sub(label, "")
		var name := normalize_name(label)
		if not name.is_empty():
			picked.append(name)
	return picked


# --- Open Fixture Library -----------------------------------------------------

## `json_text` is a fixture file from open-fixture-library.org (the page's
## "Fixture JSON" / the .json next to it).
static func from_ofl(json_text: String) -> Dictionary:
	var out := _empty()
	var data: Variant = JSON.parse_string(json_text)
	if not (data is Dictionary):
		out.notes.append("That doesn't look like an Open Fixture Library file.")
		return out
	var fixture: Dictionary = data
	var available: Dictionary = fixture.get("availableChannels", {})
	if available.is_empty() or not (fixture.get("modes") is Array):
		out.notes.append("No channels or modes found in that file.")
		return out
	var fixture_name := str(fixture.get("name", "Imported fixture"))
	var body := _body_from_categories(fixture.get("categories", []))
	var pan_range := 0.0
	var tilt_range := 0.0
	var focus: Dictionary = (fixture.get("physical", {}) as Dictionary).get("focus", {})
	if focus.get("panMax") is float or focus.get("panMax") is int:
		pan_range = float(focus["panMax"])
	if focus.get("tiltMax") is float or focus.get("tiltMax") is int:
		tilt_range = float(focus["tiltMax"])

	# Fine channel aliases ("Pan fine") point back at the channel they extend.
	var fine_of: Dictionary = {} ## alias -> [channel key, level]
	for key in available:
		var cdef: Dictionary = available[key]
		var aliases: Array = cdef.get("fineChannelAliases", [])
		for i in aliases.size():
			fine_of[str(aliases[i])] = [str(key), i + 1]

	var modes: Array = fixture["modes"]
	for mode_v in modes:
		var mode: Dictionary = mode_v
		var used: Dictionary = {}
		var names := PackedStringArray()
		var defaults: Dictionary = {}
		var skipped_insert := false
		for entry in mode.get("channels", []):
			if entry == null:
				names.append(unique("unused", used))
				continue
			if entry is Dictionary:
				skipped_insert = true
				continue
			var key := str(entry)
			var level := 0
			var base_key := key
			if fine_of.has(key):
				base_key = (fine_of[key] as Array)[0]
				level = (fine_of[key] as Array)[1]
			var cdef: Dictionary = available.get(base_key, {})
			var role := _ofl_role(cdef)
			if role.is_empty():
				role = sanitize(base_key)
			if level == 1:
				role += "_fine"
			elif level > 1:
				role += "_fine%d" % level
			var name := unique(role, used)
			names.append(name)
			if not STANDARD.has(name) and cdef.has("defaultValue") and level == 0:
				defaults[name] = _ofl_default(cdef["defaultValue"], (cdef.get("fineChannelAliases", []) as Array).size())
		var p := FixtureProfile.new()
		p.fixture_name = fixture_name if modes.size() == 1 else "%s (%s)" % [fixture_name, str(mode.get("name", mode.get("shortName", "mode")))]
		p.channels = names
		p.defaults = defaults
		p.body_style = body
		if pan_range > 0.0:
			p.pan_range_deg = clampf(pan_range, 1.0, 720.0)
		if tilt_range > 0.0:
			p.tilt_range_deg = clampf(tilt_range, 1.0, 360.0)
		out.profiles.append(p)
		if skipped_insert:
			out.notes.append("%s: pixel/matrix channels aren't imported yet; add them with 'Add pixels'." % p.fixture_name)
	return out


static func _ofl_role(cdef: Dictionary) -> String:
	var caps: Array = []
	if cdef.has("capability"):
		caps = [cdef["capability"]]
	elif cdef.has("capabilities"):
		caps = cdef["capabilities"]
	if caps.is_empty() or not (caps[0] is Dictionary):
		return ""
	var cap: Dictionary = caps[0]
	match str(cap.get("type", "")):
		"Intensity":
			return "dimmer"
		"ColorIntensity":
			return normalize_name(str(cap.get("color", "")))
		"Pan":
			return "pan"
		"Tilt":
			return "tilt"
		"ShutterStrobe", "StrobeSpeed", "StrobeDuration":
			return "strobe"
	return ""


static func _ofl_default(value: Variant, fine_count: int) -> int:
	var v := 0
	if value is String and (value as String).ends_with("%"):
		v = roundi(float((value as String).trim_suffix("%")) * 2.55)
	elif value is float or value is int:
		v = int(value) >> (8 * fine_count)
	return clampi(v, 0, 255)


static func _body_from_categories(categories: Variant) -> int:
	if not (categories is Array):
		return 0
	for c in categories:
		var s := str(c).to_lower()
		if s.contains("moving"):
			return 1
		if s.contains("bar") or s.contains("pixel"):
			return 2
		if s.contains("strobe") or s.contains("blinder"):
			return 3
	return 0


# --- GDTF ---------------------------------------------------------------------

## `path` is a .gdtf file (a zip holding description.xml).
static func from_gdtf(path: String) -> Dictionary:
	var out := _empty()
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		out.notes.append("Couldn't open %s." % path.get_file())
		return out
	var xml := zip.read_file("description.xml")
	zip.close()
	if xml.is_empty():
		out.notes.append("No description.xml inside that GDTF file.")
		return out
	return from_gdtf_xml(xml)


static func from_gdtf_xml(xml: PackedByteArray) -> Dictionary:
	var out := _empty()
	var parser := XMLParser.new()
	if parser.open_buffer(xml) != OK:
		out.notes.append("That GDTF description couldn't be read.")
		return out
	var fixture_name := "Imported fixture"
	var modes: Array[Dictionary] = [] ## {name, channels: [{offsets, attr, default}]}
	var mode: Dictionary = {}
	var channel: Dictionary = {}
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		match parser.get_node_name():
			"FixtureType":
				fixture_name = parser.get_named_attribute_value_safe("Name")
			"DMXMode":
				mode = {"name": parser.get_named_attribute_value_safe("Name"), "channels": []}
				modes.append(mode)
			"DMXChannel":
				if mode.is_empty():
					continue
				var offsets: Array[int] = []
				for part in parser.get_named_attribute_value_safe("Offset").split(",", false):
					if part.is_valid_int():
						offsets.append(int(part))
				channel = {"offsets": offsets, "attr": "", "default": -1}
				(mode["channels"] as Array).append(channel)
			"LogicalChannel":
				if not channel.is_empty() and str(channel["attr"]).is_empty():
					channel["attr"] = parser.get_named_attribute_value_safe("Attribute")
			"ChannelFunction":
				if not channel.is_empty() and int(channel["default"]) < 0:
					var def := parser.get_named_attribute_value_safe("Default")
					if not def.is_empty():
						var bits := def.split("/")
						var v := int(bits[0])
						var bytes := int(bits[1]) if bits.size() > 1 else 1
						channel["default"] = clampi(v >> (8 * (bytes - 1)), 0, 255)
	if modes.is_empty():
		out.notes.append("No DMX modes found in that GDTF file.")
		return out
	for m in modes:
		var p := _gdtf_profile(m, fixture_name if modes.size() == 1 else "%s (%s)" % [fixture_name, m["name"]])
		out.profiles.append(p)
	return out


static func _gdtf_profile(mode: Dictionary, profile_name: String) -> FixtureProfile:
	var slots: Array[String] = []
	var slot_default: Dictionary = {}
	for ch in mode["channels"]:
		var offsets: Array = ch["offsets"]
		if offsets.is_empty():
			continue
		var base := _gdtf_role(str(ch["attr"]))
		for level in offsets.size():
			var at: int = int(offsets[level]) - 1
			if at < 0 or at > 511:
				continue
			while slots.size() <= at:
				slots.append("")
			var n := base
			if level == 1:
				n += "_fine"
			elif level > 1:
				n += "_fine%d" % level
			slots[at] = n
			if level == 0 and int(ch["default"]) >= 0:
				slot_default[at] = int(ch["default"])
	# Repeated colours are pixels: red_1, red_2... in address order.
	var counts: Dictionary = {}
	for s in slots:
		counts[s] = int(counts.get(s, 0)) + 1
	var seen: Dictionary = {}
	var used: Dictionary = {}
	var names := PackedStringArray()
	var defaults: Dictionary = {}
	for i in slots.size():
		var s := slots[i]
		var n: String
		if s.is_empty():
			n = unique("unused", used)
		elif COLOURS.has(s) and int(counts[s]) > 1:
			seen[s] = int(seen.get(s, 0)) + 1
			n = "%s_%d" % [s, seen[s]]
			used[n] = true
		else:
			n = unique(s, used)
		names.append(n)
		if not STANDARD.has(n) and not n.contains("_") and slot_default.has(i):
			defaults[n] = slot_default[i]
	var p := FixtureProfile.new()
	p.fixture_name = profile_name
	p.channels = names
	p.defaults = defaults
	if names.has("pan"):
		p.body_style = 1
	elif p.pixel_count() > 1:
		p.body_style = 2
	return p


static func _gdtf_role(attr: String) -> String:
	var a := attr.to_lower()
	if a.begins_with("coloradd_") or a.begins_with("colorrgb_"):
		var suffix := a.get_slice("_", 1)
		match suffix:
			"r", "red":
				return "red"
			"g", "green":
				return "green"
			"b", "blue":
				return "blue"
			"w", "white":
				return "white"
			"ry", "amber":
				return "amber"
			"uv":
				return "uv"
	if a == "dimmer":
		return "dimmer"
	if a == "pan" or a == "tilt":
		return a
	if a.begins_with("shutter") or a.begins_with("strobe"):
		return "strobe"
	if a == "uv" or a == "uv1":
		return "uv"
	return sanitize(attr) if not attr.is_empty() else "channel"


static func _empty() -> Dictionary:
	var profiles: Array[FixtureProfile] = []
	return {"profiles": profiles, "notes": PackedStringArray()}
