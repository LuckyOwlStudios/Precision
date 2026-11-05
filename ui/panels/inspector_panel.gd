class_name InspectorPanel
extends ScrollContainer
## Properties of the selected fixture: name, patch, placement, look and aim.
## Edits go straight to the DMXFixture, so the 3D stage and real lights follow.
##
## Everything here must fit the right dock's width: if the panel asks for more,
## the dock grows and squeezes the stage view every time a fixture is selected.
## Horizontal scrolling is set to "never" so content can't widen the dock.

var ctx: StudioContext
var fx: DMXFixture

var _syncing := false

@onready var _content: VBoxContainer = %Content
@onready var _empty: Control = %Empty
@onready var _title: Label = %FixtureTitle
@onready var _detail: Label = %FixtureDetail
@onready var _name: LineEdit = %NameEdit
@onready var _address: SpinBox = %Address
@onready var _channels: Label = %Channels
@onready var _place: Array[SpinBox] = [%PositionX, %PositionY, %PositionZ] ## metres
@onready var _turn: Array[SpinBox] = [%RotationX, %RotationY, %RotationZ] ## degrees
@onready var _dimmer: HSlider = %Dimmer
@onready var _dimmer_value: Label = %DimmerValue
@onready var _color: ColorPickerButton = %Colour
@onready var _white_row: Control = %WhiteRow
@onready var _white: HSlider = %White
@onready var _strobe_row: Control = %StrobeRow
@onready var _strobe: HSlider = %Strobe
@onready var _position_section: Control = %AimSection
@onready var _pan: HSlider = %Pan
@onready var _tilt: HSlider = %Tilt


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.selection_changed.connect(_show)
	ctx.fixtures_changed.connect(func() -> void: _show(ctx.selected))
	# Deferred: the window first switches to this tab so the field can take focus.
	ctx.rename_requested.connect(func(_f: DMXFixture) -> void: _focus_name.call_deferred())
	_show(ctx.selected)


func _ready() -> void:
	_name.text_submitted.connect(func(t: String) -> void:
		_apply_name(t)
		_name.release_focus())
	_name.focus_exited.connect(func() -> void: _apply_name(_name.text))
	_address.value_changed.connect(func(v: float) -> void:
		if not _syncing and fx:
			fx.start_address = int(v)
			ctx.universe.data.fill(0)
			ctx.fixtures_changed.emit())
	for sb: SpinBox in _place + _turn:
		sb.value_changed.connect(func(_v: float) -> void: _push_placement())
		# Let the X/Y/Z boxes share the dock's width instead of each asking for
		# room for four characters, which made the inspector wider than its dock.
		sb.get_line_edit().add_theme_constant_override("minimum_character_width", 0)
	_color.color_changed.connect(func(c: Color) -> void:
		if not _syncing and fx:
			fx.color = c)
	# Sliders write straight to the fixture property of the same name.
	_bind_slider(_dimmer, "dimmer")
	_bind_slider(_white, "white")
	_bind_slider(_strobe, "strobe")
	_bind_slider(_pan, "pan")
	_bind_slider(_tilt, "tilt")


func _bind_slider(s: HSlider, prop: String) -> void:
	s.value_changed.connect(func(v: float) -> void:
		if not _syncing and fx:
			fx.set(prop, int(v) if prop == "strobe" else v))


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
	_title.text = StudioContext.display_name(fx)
	_detail.text = String(fx.get_meta(StudioContext.META_PROFILE_LABEL, fx.profile.fixture_name))
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
