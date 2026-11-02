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


func has_channel(channel_name: String) -> bool:
	return channels.has(channel_name)
