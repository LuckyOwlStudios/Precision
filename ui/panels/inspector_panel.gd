class_name InspectorPanel
extends ScrollContainer
## Properties of the selected fixture: name, patch, placement, look and aim.
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
var _name := LineEdit.new()
var _place: Array[SpinBox] = [] ## X, Y, Z in metres
var _turn: Array[SpinBox] = [] ## rotation X, Y, Z in degrees
var _syncing := false


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.selection_changed.connect(_show)
	ctx.fixtures_changed.connect(func() -> void: _show(ctx.selected))
	# Deferred: the window first switches to this tab so the field can take focus.
	ctx.rename_requested.connect(func(_f: DMXFixture) -> void: _focus_name.call_deferred())
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

	_name.placeholder_text = "Name this fixture"
	_name.tooltip_text = "Your own name, shown on the stage list and timeline (F2). Leave empty for the default."
	_name.text_submitted.connect(func(t: String) -> void:
		_apply_name(t)
		_name.release_focus())
	_name.focus_exited.connect(func() -> void: _apply_name(_name.text))
	_content.add_child(UIKit.field("Name", _name))

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

	# Placement: exact numbers for the gizmo's moves.
	_content.add_child(UIKit.section("Placement"))
	for i in 3:
		_place.append(_spin(-30.0, 30.0, 0.01, " m"))
		_turn.append(_spin(-180.0, 180.0, 0.5, "°"))
	_content.add_child(UIKit.field("Position", _xyz_row(_place)))
	_content.add_child(UIKit.field("Rotation", _xyz_row(_turn)))

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
	pos_box.add_child(UIKit.section("Aim"))
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


func _spin(lo: float, hi: float, step: float, suffix: String) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.suffix = suffix
	sb.select_all_on_focus = true
	sb.custom_arrow_step = 0.1 if suffix == " m" else 15.0
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.custom_minimum_size.x = 0
	sb.value_changed.connect(func(_v: float) -> void: _push_placement())
	return sb


func _xyz_row(boxes: Array[SpinBox]) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for sb in boxes:
		row.add_child(sb)
	return row


func _focus_name() -> void:
	_name.grab_focus()
	_name.select_all()


func _apply_name(t: String) -> void:
	if not _syncing and fx and is_instance_valid(fx):
		ctx.rename_fixture(fx, t)


func _push_placement() -> void:
	if _syncing or fx == null:
		return
	var pos := Vector3(_place[0].value, _place[1].value, _place[2].value)
	var rot := Vector3(deg_to_rad(_turn[0].value), deg_to_rad(_turn[1].value), deg_to_rad(_turn[2].value))
	ctx.move_fixture(fx, Transform3D(Basis.from_euler(rot), pos))


func _show(p_fx: DMXFixture) -> void:
	fx = p_fx
	var has := fx != null
	for c in _content.get_children():
		(c as Control).visible = has
	_empty.visible = not has
	if not has:
		return
	(_title.get_meta("title") as Label).text = StudioContext.display_name(fx)
	(_title.get_meta("detail") as Label).text = String(fx.get_meta(StudioContext.META_PROFILE_LABEL, fx.profile.fixture_name))
	_white_row.visible = fx.profile.has_channel("white")
	_strobe_row.visible = fx.profile.has_channel("strobe")
	_position_section.visible = fx.profile.has_channel("pan") or fx.profile.has_channel("tilt")
	_channels.text = "Channels %d–%d: %s" % [fx.start_address, fx.start_address + fx.profile.channels.size() - 1, ", ".join(fx.profile.channels)]
	_syncing = true
	_address.value = fx.start_address
	if not _name.has_focus():
		_name.text = String(fx.get_meta(StudioContext.META_LABEL, ""))
		_name.placeholder_text = String(fx.name)
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
	var xf := StudioContext.fixture_transform(fx)
	var euler := xf.basis.get_euler()
	for i in 3:
		# Leave a box alone while you're typing in it.
		if not _place[i].get_line_edit().has_focus():
			_place[i].value = xf.origin[i]
		if not _turn[i].get_line_edit().has_focus():
			_turn[i].value = rad_to_deg(euler[i])
	_syncing = false


func _process(_delta: float) -> void:
	if fx and is_instance_valid(fx) and is_visible_in_tree():
		_pull()
