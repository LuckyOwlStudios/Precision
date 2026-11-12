extends SceneTree
## Fixture profile editor: name guessing, pasted charts, Open Fixture Library
## and GDTF import, saving, and the editor's own checks.
##   godot --headless --path . --script res://tests/profile_editor_test.gd

var _fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		push_error("FAIL: " + what)
	print(("ok   " if ok else "FAIL ") + what)


const OFL := """{
  "name": "Test Mover", "categories": ["Moving Head"],
  "physical": {"focus": {"panMax": 540, "tiltMax": 270}},
  "availableChannels": {
    "Pan": {"fineChannelAliases": ["Pan fine"], "capability": {"type": "Pan", "angleStart": "0deg", "angleEnd": "540deg"}},
    "Tilt": {"capability": {"type": "Tilt", "angleStart": "0deg", "angleEnd": "270deg"}},
    "Dimmer": {"capability": {"type": "Intensity"}},
    "Red": {"capability": {"type": "ColorIntensity", "color": "Red"}},
    "Shutter": {"capabilities": [{"dmxRange": [0, 7], "type": "ShutterStrobe", "shutterEffect": "Open"}]},
    "Control": {"defaultValue": 20, "capability": {"type": "Maintenance"}}
  },
  "modes": [
    {"name": "Short", "channels": ["Pan", "Tilt", "Dimmer", "Red"]},
    {"name": "Long", "channels": ["Pan", "Pan fine", "Tilt", null, "Shutter", "Control", "Dimmer"]}
  ]
}"""

const GDTF := """<GDTF><FixtureType Name="Test Bar"><DMXModes><DMXMode Name="Default"><DMXChannels>
<DMXChannel Offset="1" Geometry="Body"><LogicalChannel Attribute="Dimmer"><ChannelFunction Attribute="Dimmer" Default="255/1"/></LogicalChannel></DMXChannel>
<DMXChannel Offset="2" Geometry="P1"><LogicalChannel Attribute="ColorAdd_R"><ChannelFunction Attribute="ColorAdd_R"/></LogicalChannel></DMXChannel>
<DMXChannel Offset="3" Geometry="P1"><LogicalChannel Attribute="ColorAdd_G"><ChannelFunction Attribute="ColorAdd_G"/></LogicalChannel></DMXChannel>
<DMXChannel Offset="4" Geometry="P2"><LogicalChannel Attribute="ColorAdd_R"><ChannelFunction Attribute="ColorAdd_R"/></LogicalChannel></DMXChannel>
<DMXChannel Offset="5" Geometry="P2"><LogicalChannel Attribute="ColorAdd_G"><ChannelFunction Attribute="ColorAdd_G"/></LogicalChannel></DMXChannel>
</DMXChannels></DMXMode></DMXModes></FixtureType></GDTF>"""


func _init() -> void:
	# Names.
	for pair in [["Master Dimmer", "dimmer"], ["Strobe / Shutter", "strobe"], ["Pan Fine", "pan_fine"],
			["Tilt", "tilt"], ["R", "red"], ["Warm White", "white"], ["Red 3", "red_3"],
			["Color wheel", "color_wheel"], ["Gobo 2", "gobo2"], ["Pan/Tilt speed", "pan_tilt_speed"]]:
		_check(ProfileImport.normalize_name(pair[0]) == pair[1], "'%s' -> %s (got %s)" % [pair[0], pair[1], ProfileImport.normalize_name(pair[0])])

	# Pasted charts.
	var chart := ProfileImport.from_text("Channel Function Value\n1\tDimmer\t0-255\nCH2: Red 0-255\n3. Green (0-255)\n4) Blue\n")
	_check(chart == PackedStringArray(["dimmer", "red", "green", "blue"]), "numbered chart parsed: %s" % chart)
	_check(ProfileImport.from_text("Dimmer\nRed\nGreen") == PackedStringArray(["dimmer", "red", "green"]), "plain list parsed")

	# Open Fixture Library.
	var ofl := ProfileImport.from_ofl(OFL)
	var profiles: Array = ofl.profiles
	_check(profiles.size() == 2, "OFL: one profile per mode")
	var short: FixtureProfile = profiles[0]
	_check(short.channels == PackedStringArray(["pan", "tilt", "dimmer", "red"]), "OFL short mode channels: %s" % short.channels)
	_check(short.body_style == 1 and short.pan_range_deg == 540.0 and short.tilt_range_deg == 270.0, "OFL moving head + ranges")
	var long_p: FixtureProfile = profiles[1]
	_check(long_p.channels == PackedStringArray(["pan", "pan_fine", "tilt", "unused", "strobe", "control", "dimmer"]), "OFL long mode (fine, unused, role names): %s" % long_p.channels)
	_check(int(long_p.defaults.get("control", 0)) == 20, "OFL default value kept for custom channel")
	_check(ProfileImport.from_ofl("nope").profiles.is_empty(), "OFL rejects junk")

	# GDTF.
	var gd := ProfileImport.from_gdtf_xml(GDTF.to_utf8_buffer())
	var bar: FixtureProfile = (gd.profiles as Array)[0]
	_check(bar.channels == PackedStringArray(["dimmer", "red_1", "green_1", "red_2", "green_2"]), "GDTF pixels numbered: %s" % bar.channels)
	_check(bar.pixel_count() == 2 and bar.body_style == 2, "GDTF repeated colours become a pixel bar")

	# URL.
	_check(ProfileEditor.ofl_json_url("https://open-fixture-library.org/cameo/flat-pro-12?x=1") == "https://open-fixture-library.org/cameo/flat-pro-12.json", "OFL page -> json url")
	_check(ProfileEditor.ofl_json_url("https://example.com/a/b").is_empty(), "other hosts refused")

	# Validation.
	var r := ProfileEditor.validate("", PackedStringArray())
	_check((r.errors as PackedStringArray).size() == 2, "blank profile has two errors")
	r = ProfileEditor.validate("X", PackedStringArray(["red", "red"]))
	_check((r.errors as PackedStringArray).is_empty() and (r.warnings as PackedStringArray).size() == 1, "duplicate names only warn")

	# Store round trip, in a scratch folder.
	ProfileStore.dir = "user://fixtures_test"
	for f in DirAccess.get_files_at(ProfileStore.dir):
		DirAccess.remove_absolute(ProfileStore.dir.path_join(f))
	var saved_path := ProfileStore.save(long_p)
	_check(saved_path.ends_with("test-mover-long.tres"), "saved under a name-based file: %s" % saved_path)
	var again := ProfileStore.save(long_p)
	_check(again != saved_path and again.ends_with("-2.tres"), "second save with same name gets its own file")
	var loaded := ProfileStore.load_all()
	_check(loaded.size() == 2 and loaded[0].channels == long_p.channels and loaded[0].body_style == 1, "profiles load back")
	_check(FixtureCatalog.entries().filter(func(e: FixtureCatalog.Entry) -> bool: return e.category == FixtureCatalog.USER_CATEGORY).size() == 2, "catalog lists them under My fixtures")
	_check(ProfileStore.delete(loaded[0]) and ProfileStore.load_all().size() == 1, "delete removes the file")
	for f in DirAccess.get_files_at(ProfileStore.dir):
		DirAccess.remove_absolute(ProfileStore.dir.path_join(f))

	# The editor window itself: type a chart, save, edit again.
	ProfileStore.dir = "user://fixtures_test"
	var ed: ProfileEditor = (load("res://ui/panels/profile_editor.tscn") as PackedScene).instantiate()
	root.add_child(ed)
	await process_frame
	ed.open_new()
	await process_frame
	(ed.get_node("%NameEdit") as LineEdit).text = "My Par"
	(ed.get_node("%NameEdit") as LineEdit).text_changed.emit("My Par")
	for n in ["dimmer", "red", "green", "blue"]:
		ed.call("_add_channel", n)
	await process_frame
	_check(not (ed.get_node("%Save") as Button).disabled, "Save enabled once named with channels")
	var made: Array[FixtureProfile] = []
	ed.saved.connect(func(p: FixtureProfile) -> void: made.append(p))
	(ed.get_node("%Save") as Button).pressed.emit()
	_check(made.size() == 1 and made[0].channels == PackedStringArray(["dimmer", "red", "green", "blue"]), "editor saves what was typed")
	var back := ProfileStore.load_all()
	_check(back.size() == 1 and back[0].fixture_name == "My Par", "saved profile is on disk")
	ed.open_edit(back[0])
	await process_frame
	(ed.get_node("%PixelChannels") as LineEdit).text = "red, green, blue"
	ed.call("_on_pixel_apply")
	(ed.get_node("%Save") as Button).pressed.emit()
	var edited := ProfileStore.load_all()
	_check(edited.size() == 1 and edited[0].pixel_count() == 8, "editing writes back to the same file with pixels")
	for f in DirAccess.get_files_at(ProfileStore.dir):
		DirAccess.remove_absolute(ProfileStore.dir.path_join(f))
	ProfileStore.dir = ProfileStore.DEFAULT_DIR

	print("profile editor test: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)
