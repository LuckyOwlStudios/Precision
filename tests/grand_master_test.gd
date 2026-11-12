extends SceneTree
## Grand master scales dimmer output. Run:
##   godot --headless --path . --script res://tests/grand_master_test.gd

var _fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _initialize() -> void:
	var uni := DMXUniverse.new()
	var with_dimmer := FixtureProfile.new()
	with_dimmer.channels = PackedStringArray(["dimmer", "red", "green", "blue"])
	var rgb := FixtureProfile.new()
	rgb.channels = PackedStringArray(["red", "green", "blue"])

	var a := DMXFixture.new()
	a.profile = with_dimmer
	a.universe = uni
	a.start_address = 1
	a.dimmer = 1.0
	a.color = Color(1, 0, 0)
	var b := DMXFixture.new()
	b.profile = rgb
	b.universe = uni
	b.start_address = 11
	b.dimmer = 1.0
	b.color = Color(1, 0, 0)

	a._process(0.0)
	b._process(0.0)
	_check(uni.get_channel(1) == 255 and uni.get_channel(11) == 255, "full master leaves output alone")

	uni.grand_master = 0.5
	a._process(0.0)
	b._process(0.0)
	_check(uni.get_channel(1) == 128, "dimmer channel halves")
	_check(uni.get_channel(2) == 255, "colour untouched when a dimmer channel exists")
	_check(uni.get_channel(11) == 128, "virtual dimmer scales colour on RGB-only fixtures")

	uni.grand_master = 0.0
	a._process(0.0)
	b._process(0.0)
	_check(uni.get_channel(1) == 0 and uni.get_channel(11) == 0, "zero master is dark")

	print("grand_master_test: ", "OK" if _fails == 0 else "%d failed" % _fails)
	quit(1 if _fails else 0)
