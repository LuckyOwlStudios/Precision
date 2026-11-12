extends SceneTree
## Checks pixel fixtures: pixel channel names, DMX output per pixel (falling
## back to the whole-fixture colour), the master dimmer, the bar's pixel face
## following the profile's layout, and effects running along the pixels.
##   godot --headless --path . --script res://tests/pixel_bar_test.gd

var _failed := 0


func _init() -> void:
	# Profile parsing.
	var names := FixtureProfile.pixel_channels(["red", "green", "blue", "white"], 28, ["dimmer", "strobe"])
	_expect(names.size() == 114 and names[2] == "red_1" and names[113] == "white_28", "114ch channel names")
	var pr := FixtureProfile.new()
	pr.channels = names
	_expect(pr.pixel_count() == 28, "28 pixels")
	_expect(pr.has_channel("red") and pr.has_channel("dimmer") and not pr.has_channel("pan"), "has_channel sees pixel channels")
	_expect(pr.pixel_grid() == Vector2i(28, 1), "default layout is one row")
	_expect(pr.channel_base(6) == "red" and pr.channel_pixel(6) == 1, "red_2 is pixel 1")
	_expect(FixtureProfile.split_pixel("pan_fine") == ["pan_fine", -1], "pan_fine is not a pixel")
	_expect(pr.summary() == "dimmer, strobe, 28 pixels × (red, green, blue, white)", "summary folds pixels: " + pr.summary())

	# DMX output.
	var uni := DMXUniverse.new()
	var fx := DMXFixture.new()
	fx.universe = uni
	fx.profile = pr
	fx.start_address = 1
	fx.color = Color(0, 0, 1)
	fx.dimmer = 0.5
	root.add_child(uni)
	root.add_child(fx)
	fx.pixel_colors = PackedColorArray([Color(1, 0, 0), Color(0, 1, 0)])
	fx.pixel_whites = PackedFloat32Array([1.0])
	fx._process(0.0)
	_expect(uni.get_channel(1) == 128, "master dimmer")
	_expect(uni.get_channel(3) == 255 and uni.get_channel(5) == 0 and uni.get_channel(6) == 255, "pixel 1 red + white")
	_expect(uni.get_channel(8) == 255 and uni.get_channel(10) == 0, "pixel 2 green, white follows fixture (0)")
	_expect(uni.get_channel(11) == 0 and uni.get_channel(13) == 255, "pixel 3 follows fixture blue")

	# No dimmer channel: the dimmer scales every pixel.
	var pr112 := FixtureProfile.new()
	pr112.channels = FixtureProfile.pixel_channels(["red", "green", "blue", "white"], 28)
	fx.profile = pr112
	fx.dimmer = 0.5
	fx._process(0.0)
	_expect(uni.get_channel(1) == 128, "112ch: virtual dimmer on pixels")

	# Effects: a pixel chase lights one pixel at a time.
	fx.profile = pr
	fx.pixel_colors = PackedColorArray()
	fx.pixel_whites = PackedFloat32Array()
	var v := fx.capture()
	EffectTemplates.apply("chase", {"beats": 1.0, "pixels": true}, 3.5, 0, 1, fx, v)
	var pc: PackedColorArray = v.pixel_colors
	_expect(pc.size() == 28 and pc[3] == Color(0, 0, 1) and pc[2] == Color.BLACK, "pixel chase on pixel 4 at beat 3")
	v = fx.capture()
	EffectTemplates.apply("rainbow", {}, 0.0, 0, 1, fx, v)
	pc = v.pixel_colors
	_expect(pc.size() == 28 and not pc[0].is_equal_approx(pc[14]), "rainbow rolls along the pixels")
	var blended: PackedColorArray = DMXFixture.blend_pixels(PackedColorArray([Color.BLACK]), PackedColorArray([Color.WHITE, Color.RED]), 0.5)
	_expect(blended.size() == 2 and blended[0].is_equal_approx(Color(0.5, 0.5, 0.5)), "pixel fades blend per pixel")

	# 3D: the bar's face uses the pixel layout.
	fx.live = {"pixel_colors": PackedColorArray([Color(1, 0, 0)])}
	fx.set_meta(StudioContext.META_BODY, FixtureCatalog.Body.BAR)
	var vis := StageFixture3D.create(fx)
	root.add_child(vis)
	await process_frame
	vis.setup(fx, null)
	vis._process(0.0)
	var mat := vis.pixel_material
	_expect(mat != null and mat.get_shader_parameter("grid") == Vector2i(28, 1), "face shows 28 cells")
	_expect(mat.get_shader_parameter("pixel_data") is ImageTexture, "face reads a pixel texture")
	var img: Image = vis._pixel_image # the headless renderer can't read textures back
	_expect(img.get_pixel(0, 0).r > 0.9 and img.get_pixel(0, 0).b < 0.1 and img.get_pixel(1, 0).b > 0.9, "cell colours follow the pixels")
	fx.profile = _plain()
	vis._process(0.0)
	_expect(mat.get_shader_parameter("grid") == Vector2i(8, 1), "plain bar profile: 8 cells in one colour")

	# The Wash Bar Light uses its own exact model.
	_expect(StageFixture3D.scene_path(FixtureCatalog.Body.BAR, "Wash Bar Light 28 pixels (114ch)").ends_with("models/wash_bar_light.tscn"), "wash bar has its own model")
	_expect(StageFixture3D.scene_path(FixtureCatalog.Body.BAR, "Generic RGB Bar (4ch)").ends_with("fixtures/bar.tscn"), "other bars keep the generic one")
	var box := StageFixture3D.body_box_of("res://ui/stage/fixtures/models/wash_bar_light.tscn")
	_expect(absf(box.size.x - 1.0) < 0.01, "wash bar is 1 m long: %s" % box.size)
	fx.profile = pr
	fx.set_meta(StudioContext.META_PROFILE_LABEL, "Wash Bar Light 28 pixels (114ch)")
	var wb := StageFixture3D.create(fx)
	root.add_child(wb)
	await process_frame
	wb.setup(fx, null)
	fx.live = {"pixel_whites": PackedFloat32Array([0.5])}
	wb._process(0.0)
	_expect(wb.pixel_material.get_shader_parameter("led_rows") == 4, "four LED lines")
	_expect(absf(wb._pixel_image.get_pixel(0, 0).a - 0.5) < 0.01 and wb._pixel_image.get_pixel(1, 0).a == 0.0, "white goes in alpha for the white LED lines")

	print("pixel_bar_test: %s" % ("FAILED (%d)" % _failed if _failed else "all passed"))
	quit(1 if _failed else 0)


func _plain() -> FixtureProfile:
	var p := FixtureProfile.new()
	p.channels = PackedStringArray(["dimmer", "red", "green", "blue"])
	return p


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		printerr("FAIL: " + what)
	else:
		print("ok: " + what)
