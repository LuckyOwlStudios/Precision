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

@export var fixture_name: String = "Generic RGB"
## Channel names in order. Index 0 = the fixture's start address.
@export var channels: PackedStringArray = PackedStringArray(["dimmer", "red", "green", "blue"])
## Fixed raw values (0-255) for channels like "mode" or "shutter open".
@export var defaults: Dictionary = {}
## Moving heads: how far pan and tilt travel across their full DMX range, in
## degrees (from the manual, e.g. "pan 540°, tilt 270°"). Pan/tilt 0..1 maps
## onto 0..this many degrees.
@export_range(1.0, 720.0, 1.0, "suffix:°") var pan_range_deg: float = 540.0
@export_range(1.0, 360.0, 1.0, "suffix:°") var tilt_range_deg: float = 270.0


func has_channel(channel_name: String) -> bool:
	return channels.has(channel_name)
