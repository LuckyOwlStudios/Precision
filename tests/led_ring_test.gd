extends SceneTree
## Checks the LED Ring Beam: its 16-channel profile, the ring effect channel
## mapping, and the 3D model (30 ring LEDs, pan/tilt range).
##   godot --headless --path . --script res://tests/led_ring_test.gd

var _failed := 0


func _init() -> void:
	var entry: FixtureCatalog.Entry
	for e in FixtureCatalog.entries():
		if e.profile.fixture_name.begins_with("LED Ring Beam"):
			entry = e
	_expect(entry != null, "catalog lists the LED Ring Beam")
	var pr := entry.profile
	_expect(pr.channels.size() == 16 and pr.channels[0] == "pan" and pr.channels[13] == "ring_effect" and pr.channels[15] == "reset", "16 channels in manual order")
	_expect(pr.pixel_count() == 0, "no pixel channels (ring has effects only)")
	_expect(pr.pan_range_deg == 540.0 and pr.tilt_range_deg == 270.0, "pan 540, tilt 270")
	_expect(entry.body == FixtureCatalog.Body.MOVING_HEAD, "moving head body")

	# DMX out: shutter open, ring on, nothing resets.
	var uni := DMXUniverse.new()
	var fx := DMXFixture.new()
	fx.universe = uni
	fx.profile = pr
	fx.start_address = 1
	root.add_child(uni)
	root.add_child(fx)
	fx.pan = 0.5
	fx._process(0.0)
	_expect(uni.get_channel(1) == 128 and uni.get_channel(2) == 0, "pan 16 bit")
	_expect(uni.get_channel(6) == 255, "dimmer channel 6")
	_expect(uni.get_channel(7) == 255, "shutter open by default")
	_expect(uni.get_channel(12) == 255 and uni.get_channel(14) == 0 and uni.get_channel(16) == 0, "ring on, no effect, no reset")
	fx.set_raw("ring_effect", 100)
	fx._process(0.0)
	_expect(uni.get_channel(14) == 100 and fx.raw_value("ring_effect") == 100, "raw ring effect")

	# Effect numbering: 0-51 inner, 52-55 effect 1, 252-255 effect 51.
	_expect(LedRingPreview.effect_number(51) == 0 and LedRingPreview.effect_number(52) == 1, "effect 1 starts at 52")
	_expect(LedRingPreview.effect_number(56) == 2 and LedRingPreview.effect_number(255) == 51, "effect 51 ends at 255")
	var a := LedRingPreview.leds(60, 100, 0.0, Color.WHITE)
	var b := LedRingPreview.leds(200, 100, 0.0, Color.WHITE)
	_expect(a.size() == 30 and a != b, "different effects look different")
	_expect(LedRingPreview.turns_per_second(255) > LedRingPreview.turns_per_second(0), "speed goes slow to fast")

	# The 3D model.
	var path := StageFixture3D.scene_path(FixtureCatalog.Body.MOVING_HEAD, pr.fixture_name)
	_expect(path.ends_with("led_ring_beam.tscn"), "model chosen by name: " + path)
	var vis := (load(path) as PackedScene).instantiate() as StageFixture3D
	root.add_child(vis)
	_expect(vis.ring_material != null and vis.ring_material.get_shader_parameter("grid") == Vector2i(30, 1), "ring has 30 LEDs")
	_expect(not StageFixture3D.mounts_of(path).is_empty(), "has truss clamps")

	print("led_ring_test: ", "FAILED %d" % _failed if _failed else "ok")
	quit(1 if _failed else 0)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: ", what)
