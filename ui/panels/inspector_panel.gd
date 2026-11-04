class_name InspectorPanel
extends ScrollContainer
## Properties of the selected fixture: patch, look and position.
## Edits go straight to the DMXFixture, so the 3D stage and real lights follow.

var ctx: StudioContext
var fx: DMXFixture

var _empty: Control
var _content := VBoxContainer.new()
var _title: VBoxContainer
var _address := SpinBox.new()
var _dimmer := HSlider.new()
var _dimmer_value := Label.new()
var _color := ColorPickerButton.new()
var _white_row: Control
var _white := HSlider.new()
var _strobe_row: Control
var _strobe := HSlider.new()
var _position_section: Control
var _pan := HSlider.new()
var _tilt := HSlider.new()
var _channels := Label.new()
var _syncing := false


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.selection_changed.connect(_show)
	_show(ctx.selected)


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := UIKit.padded(_content)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(pad)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 12)

	_empty = UIKit.empty_state("Nothing selected", "Click a fixture on the stage to edit it here.")
	_empty.custom_minimum_size.y = 220
	_content.add_child(_empty)

	_title = UIKit.title_pair("", "")
	_content.add_child(_title)

	# Patch
	var patch := UIKit.section("Patch")
	_content.add_child(patch)
	_address.min_value = 1
	_address.max_value = 512
	_address.value_changed.connect(func(v: float) -> void:
		if not _syncing and fx:
			fx.start_address = int(v)
			ctx.universe.data.fill(0)
			ctx.fixtures_changed.emit())
	_content.add_child(UIKit.field("Address", _address))
	_channels.theme_type_variation = &"Caption"
	_channels.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_channels)

	# Look
	_content.add_child(UIKit.section("Look"))
	_slider(_dimmer, 0.0, 1.0, 0.01, "dimmer")
	var dim_row := HBoxContainer.new()
	dim_row.add_child(_dimmer)
	_dimmer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dimmer_value.theme_type_variation = &"MonoLabel"
	_dimmer_value.custom_minimum_size.x = 40
	_dimmer_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dim_row.add_child(_dimmer_value)
	_content.add_child(UIKit.field("Dimmer", dim_row))

	_color.custom_minimum_size.y = 28
	_color.edit_alpha = false
	_color.color_changed.connect(func(c: Color) -> void:
		if not _syncing and fx:
			fx.color = c)
	_content.add_child(UIKit.field("Colour", _color))

	_slider(_white, 0.0, 1.0, 0.01, "white")
	_white_row = UIKit.field("White", _white)
	_content.add_child(_white_row)
	_slider(_strobe, 0, 255, 1, "strobe")
	_strobe_row = UIKit.field("Strobe", _strobe)
	_content.add_child(_strobe_row)

	# Position
	var pos_box := VBoxContainer.new()
	pos_box.add_theme_constant_override("separation", 12)
	pos_box.add_child(UIKit.section("Position"))
	_slider(_pan, 0.0, 1.0, 0.001, "pan")
	_slider(_tilt, 0.0, 1.0, 0.001, "tilt")
	pos_box.add_child(UIKit.field("Pan", _pan))
	pos_box.add_child(UIKit.field("Tilt", _tilt))
	_position_section = pos_box
	_content.add_child(pos_box)


func _slider(s: HSlider, lo: float, hi: float, step: float, prop: String) -> void:
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.y = 20
	s.value_changed.connect(func(v: float) -> void:
		if not _syncing and fx:
			fx.set(prop, int(v) if prop == "strobe" else v))


func _show(p_fx: DMXFixture) -> void:
	fx = p_fx
	var has := fx != null
	for c in _content.get_children():
		(c as Control).visible = has
	_empty.visible = not has
	if not has:
		return
	(_title.get_meta("title") as Label).text = fx.name
	(_title.get_meta("detail") as Label).text = String(fx.get_meta(StudioContext.META_PROFILE_LABEL, fx.profile.fixture_name))
	_white_row.visible = fx.profile.has_channel("white")
	_strobe_row.visible = fx.profile.has_channel("strobe")
	_position_section.visible = fx.profile.has_channel("pan") or fx.profile.has_channel("tilt")
	_channels.text = "Channels %d–%d: %s" % [fx.start_address, fx.start_address + fx.profile.channels.size() - 1, ", ".join(fx.profile.channels)]
	_syncing = true
	_address.value = fx.start_address
	_syncing = false
	_pull()


## Copy values from the fixture into the widgets (it may be animated or faded by a cue).
func _pull() -> void:
	if fx == null:
		return
	_syncing = true
	_dimmer.value = fx.dimmer
	_dimmer_value.text = "%d%%" % roundi(fx.dimmer * 100.0)
	if not _color.get_popup().visible:
		_color.color = fx.color
	_white.value = fx.white
	_strobe.value = fx.strobe
	_pan.value = fx.pan
	_tilt.value = fx.tilt
	_syncing = false


func _process(_delta: float) -> void:
	if fx and is_instance_valid(fx) and is_visible_in_tree():
		_pull()
