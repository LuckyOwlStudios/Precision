class_name InspectorPanel
extends ScrollContainer
## Properties of the selected fixture: name, patch, placement, look and aim.
## A selected structure piece gets its own sections instead (StructureInfo),
## and so does an effect clip selected on the timeline (ClipInfo).
## Edits go straight to the DMXFixture, so the 3D stage and real lights follow.
## With two or more fixtures picked together (box select) the Look and Aim
## sections edit all of them: a change is written to every fixture as one undo
## step, and a value the fixtures disagree on is dimmed and shows "—".
## Every edit is one undo step (Ctrl+Z): a whole slider drag or colour-picker
## session counts once, and quick typing / wheel / arrow nudges merge.
##
## Everything here must fit the right dock's width: if the panel asks for more,
## the dock grows and squeezes the stage view every time a fixture is selected.
## Horizontal scrolling is set to "never" so content can't widen the dock.

var ctx: StudioContext
var fx: DMXFixture ## the one shown; with a group, its first fixture
var _group: Array[DMXFixture] = [] ## two or more fixtures edited together, else empty

var _syncing := false

# A slider being dragged, or the colour picker being open: the value before it
# started, stored as one undo step when it ends.
var _drag_prop := ""
var _drag_befores: Array = []
var _drag_fixtures: Array[DMXFixture] = []
var _color_fixtures: Array[DMXFixture] = []
var _color_befores: Array = []

@onready var _content: VBoxContainer = %Content
@onready var _empty: Control = %Empty
@onready var _clip_info: ClipInfo = %ClipInfo ## shown instead of everything else while a timeline clip is selected
@onready var _structure: StructureInfo = %StructureInfo ## shown instead of the fixture sections for a truss, corner box or base plate
@onready var _title: Label = %FixtureTitle
@onready var _detail: Label = %FixtureDetail
@onready var _name: LineEdit = %NameEdit
@onready var _address: SpinBox = %Address
@onready var _channels: Label = %Channels
@onready var _place: Array[UnitSpinBox] = [%PositionX, %PositionY, %PositionZ] ## metres inside; show metres or feet
@onready var _turn: Array[SpinBox] = [%RotationX, %RotationY, %RotationZ] ## degrees
@onready var _dimmer: HSlider = %Dimmer
@onready var _dimmer_value: SpinBox = %DimmerValue
@onready var _color: ColorPickerButton = %Colour
@onready var _swatches: SwatchRow = %Swatches
@onready var _white_row: Control = %WhiteRow
@onready var _white: HSlider = %White
@onready var _white_value: SpinBox = %WhiteValue
@onready var _strobe_row: Control = %StrobeRow
@onready var _strobe: HSlider = %Strobe
@onready var _strobe_value: SpinBox = %StrobeValue
@onready var _position_section: Control = %AimSection
@onready var _pan: HSlider = %Pan
@onready var _pan_value: SpinBox = %PanValue
@onready var _tilt: HSlider = %Tilt
@onready var _tilt_value: SpinBox = %TiltValue

## Which sections each workspace shows. Stage is about building the rig (name,
## patch, placement); Program is about how a fixture looks (look and aim).
const STAGE_SECTIONS: Array[StringName] = [&"Title", &"NameField", &"PatchHeading", &"AddressField", &"Channels", &"PlacementHeading", &"PositionField", &"RotationField"]
const PROGRAM_SECTIONS: Array[StringName] = [&"Title", &"NameField", &"LookHeading", &"DimmerField", &"ColourField", &"SwatchField", &"WhiteRow", &"StrobeRow", &"AimSection"]
## Several fixtures at once: no name, and placement stays a one-at-a-time job.
const GROUP_STAGE_SECTIONS: Array[StringName] = [&"Title"]
const GROUP_PROGRAM_SECTIONS: Array[StringName] = [&"Title", &"LookHeading", &"DimmerField", &"ColourField", &"SwatchField", &"WhiteRow", &"StrobeRow", &"AimSection"]
const MIXED := "—"

## Fixture property -> [slider, number box]. The box shows the value in the
## units you'd type (see _unit_scale); both write the same fixture property.
var _pairs: Dictionary = {}


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.selection_changed.connect(_show)
	ctx.group_changed.connect(_show)
	_swatches.setup(ctx)
	_swatches.picked.connect(func(c: Color) -> void:
		if not _fixtures().is_empty():
			ctx.set_fixtures_value(_fixtures(), &"color", c))
	_swatches.save_requested.connect(func() -> void: ctx.add_swatch(_color.color))
	ctx.piece_selection_changed.connect(func(_p: StructurePiece) -> void: _show(ctx.selected))
	_structure.setup(ctx)
	_clip_info.setup(ctx)
	ctx.clip_selected.connect(func(_c: ShowClip) -> void: _show(ctx.selected))
	ctx.fixtures_changed.connect(func() -> void: _show(ctx.selected))
	ctx.workspace_changed.connect(func(_ws: StudioContext.Workspace) -> void: _show(ctx.selected))
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
			ctx.set_address(fx, int(v)))
	for sb: UnitSpinBox in _place:
		sb.metres_changed.connect(func(_m: float) -> void: _push_placement())
	for sb: SpinBox in _turn:
		sb.value_changed.connect(func(_v: float) -> void: _push_placement())
		# Let the X/Y/Z boxes share the dock's width instead of each asking for
		# room for four characters, which made the inspector wider than its dock.
		sb.get_line_edit().add_theme_constant_override("minimum_character_width", 0)
	_color.color_changed.connect(func(c: Color) -> void:
		if not _syncing:
			for f in _fixtures():
				f.color = c)
	_color.get_popup().about_to_popup.connect(func() -> void:
		_color_fixtures = _fixtures()
		_color_befores = _color_fixtures.map(func(f: DMXFixture) -> Variant: return f.color))
	_color.popup_closed.connect(func() -> void:
		var live := _color_fixtures.filter(is_instance_valid)
		if live.size() == _color_fixtures.size() and not live.is_empty():
			ctx.record_fixtures_values(live, &"color", _color_befores)
		_color_fixtures = []
		_color_befores = [])
	# Each slider and its number box write straight to the fixture property of
	# the same name; _pull copies the fixture back into both.
	_bind(_dimmer, _dimmer_value, "dimmer")
	_bind(_white, _white_value, "white")
	_bind(_strobe, _strobe_value, "strobe")
	_bind(_pan, _pan_value, "pan")
	_bind(_tilt, _tilt_value, "tilt")


func _bind(s: HSlider, box: SpinBox, prop: String) -> void:
	_pairs[prop] = [s, box]
	box.get_line_edit().add_theme_constant_override("minimum_character_width", 0)
	s.value_changed.connect(func(v: float) -> void:
		if not _syncing and fx:
			_write(prop, v))
	box.value_changed.connect(func(v: float) -> void:
		if not _syncing and fx:
			_write(prop, v / _unit_scale(prop)))
	# A whole drag is one undo step, recorded when the mouse lets go.
	s.drag_started.connect(func() -> void:
		if fx:
			_drag_prop = prop
			_drag_fixtures = _fixtures()
			_drag_befores = _drag_fixtures.map(func(f: DMXFixture) -> Variant: return f.get(prop)))
	s.drag_ended.connect(func(_changed: bool) -> void:
		if _drag_prop == prop:
			_end_drag()
		_drag_prop = "")


## Set a look property (0..1, or 0..255 for strobe) and show it in both widgets.
func _write(prop: String, v: float) -> void:
	var value: Variant = roundi(v) if prop == "strobe" else clampf(v, 0.0, 1.0)
	if _drag_prop == prop:
		for f in _drag_fixtures:
			f.set(prop, value) # recorded as one step when the drag ends
	else:
		ctx.set_fixtures_value(_fixtures(), prop, value)
	_sync_pair(prop)


## The fixtures an edit applies to: the whole group, or just the selected one.
func _fixtures() -> Array[DMXFixture]:
	if not _group.is_empty():
		return _group.duplicate()
	var list: Array[DMXFixture] = []
	if fx:
		list.append(fx)
	return list


## Store a finished slider drag as one undo step.
func _end_drag() -> void:
	var live := _drag_fixtures.filter(is_instance_valid)
	if live.size() == _drag_fixtures.size() and not live.is_empty():
		ctx.record_fixtures_values(live, StringName(_drag_prop), _drag_befores)
	_drag_fixtures = []
	_drag_befores = []


## True when the fixtures being edited together don't all have this value.
func _mixed(prop: String) -> bool:
	var first: Variant = fx.get(prop)
	for f in _group:
		var v: Variant = f.get(prop)
		if v is float:
			if not is_equal_approx(v, first):
				return true
		elif v != first:
			return true
	return false


## How the number box shows a property: dimmer and white in percent, pan and
## tilt in degrees across the fixture's range, strobe as the raw DMX value.
func _unit_scale(prop: String) -> float:
	match prop:
		"pan": return fx.profile.pan_range_deg
		"tilt": return fx.profile.tilt_range_deg
		"strobe": return 1.0
	return 100.0


func _sync_pair(prop: String) -> void:
	var s: HSlider = _pairs[prop][0]
	var box: SpinBox = _pairs[prop][1]
	var v := float(fx.get(prop))
	var mixed := _mixed(prop)
	var was := _syncing
	_syncing = true
	s.value = v
	s.modulate.a = 0.4 if mixed else 1.0
	# Leave a box alone while you're typing in it.
	var line := box.get_line_edit()
	if not line.has_focus():
		var shown := v * _unit_scale(prop)
		if not mixed and line.text == MIXED:
			# The box already holds this number, so setting it again would not
			# redraw the text: nudge it off first.
			box.value = box.min_value if shown != box.min_value else box.max_value
		box.value = shown
		if mixed:
			line.text = MIXED
	_syncing = was


func _focus_name() -> void:
	_name.grab_focus()
	_name.select_all()


func _apply_name(t: String) -> void:
	if not _syncing and fx and is_instance_valid(fx):
		ctx.rename_fixture(fx, t)


func _push_placement() -> void:
	if _syncing or fx == null:
		return
	var pos := Vector3(_place[0].get_metres(), _place[1].get_metres(), _place[2].get_metres())
	var rot := Vector3(deg_to_rad(_turn[0].value), deg_to_rad(_turn[1].value), deg_to_rad(_turn[2].value))
	var before := StudioContext.fixture_transform(fx)
	ctx.move_fixture(fx, Transform3D(Basis.from_euler(rot), pos))
	ctx.record_move(fx, before, "Move fixture", true)


func _show(_changed: Variant = null) -> void:
	var group: Array[DMXFixture] = []
	if ctx.selected == null:
		for f in ctx.selected_group:
			if is_instance_valid(f):
				group.append(f)
	if group.size() < 2:
		group.clear()
	var p_fx: DMXFixture = ctx.selected if group.is_empty() else group[0]
	if (p_fx != fx or group != _group) and _drag_prop != "":
		_end_drag() # selection changed mid-drag
		_drag_prop = ""
	fx = p_fx
	_group = group
	# An effect clip selected on the timeline takes over the inspector.
	var clip := ctx.selected_clip
	_clip_info.visible = clip != null
	_clip_info.show_clip(clip)
	if clip:
		_structure.visible = false
		_content.visible = false
		return
	# A structure piece is selected on its own, never together with a fixture.
	var piece := ctx.selected_piece if fx == null else null
	_structure.visible = piece != null
	_content.visible = piece == null
	_structure.show_piece(piece)
	if piece:
		return
	var has := fx != null
	for c in _content.get_children():
		(c as Control).visible = has
	_empty.visible = not has
	if not has:
		return
	var stage := ctx.workspace == StudioContext.Workspace.STAGE
	var grouped := not _group.is_empty()
	if grouped:
		_title.text = "%d fixtures" % _group.size()
		_detail.text = "Switch to Program to edit their look together." if stage \
			else "Changes apply to every selected fixture. Dimmed values differ."
	else:
		_title.text = StudioContext.display_name(fx)
		_detail.text = String(fx.get_meta(StudioContext.META_PROFILE_LABEL, fx.profile.fixture_name))
	var wanted := STAGE_SECTIONS if stage else PROGRAM_SECTIONS
	if grouped:
		wanted = GROUP_STAGE_SECTIONS if stage else GROUP_PROGRAM_SECTIONS
	for c in _content.get_children():
		(c as Control).visible = wanted.has(c.name)
	var all := _fixtures()
	_white_row.visible = _white_row.visible and all.any(func(f: DMXFixture) -> bool: return f.profile.has_channel("white"))
	_strobe_row.visible = _strobe_row.visible and all.any(func(f: DMXFixture) -> bool: return f.profile.has_channel("strobe"))
	_position_section.visible = _position_section.visible and all.any(func(f: DMXFixture) -> bool: return f.profile.has_channel("pan") or f.profile.has_channel("tilt"))
	_channels.text = "Channels %d–%d: %s" % [fx.start_address, fx.start_address + fx.profile.channels.size() - 1, fx.profile.summary()]
	_syncing = true
	# Inside _syncing: shrinking the range clamps the box, which would otherwise
	# write that clamped angle into the newly selected fixture.
	_pan_value.max_value = fx.profile.pan_range_deg
	_tilt_value.max_value = fx.profile.tilt_range_deg
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
	for prop: String in _pairs:
		_sync_pair(prop)
	var colour_mixed := _mixed("color")
	_color.text = MIXED if colour_mixed else ""
	_color.tooltip_text = "The selected fixtures have different colours. Pick one to set them all." if colour_mixed else ""
	if not _color.get_popup().visible:
		_color.color = fx.color
	if not _group.is_empty():
		_syncing = false
		return # placement is edited one fixture at a time
	var xf := StudioContext.fixture_transform(fx)
	var euler := xf.basis.get_euler()
	# Hung or standing fixtures only turn the ways their mounting allows (the
	# Rotate gizmo's rings); typing angles would twist them off the truss or
	# floor, so the boxes only take typing for fixtures placed freely.
	var free := _mount(fx, xf) == MountRotation.Mount.FREE
	for sb in _turn:
		sb.editable = free
		sb.tooltip_text = "" if free else "Mounted fixtures turn with the Rotate gizmo (E) in the stage view."
	for i in 3:
		# Leave a box alone while you're typing in it.
		if not _place[i].get_line_edit().has_focus():
			_place[i].set_metres(xf.origin[i])
		if not _turn[i].get_line_edit().has_focus():
			_turn[i].value = rad_to_deg(euler[i])
	_syncing = false


func _mount(p_fx: DMXFixture, xf: Transform3D) -> MountRotation.Mount:
	var body: FixtureCatalog.Body = p_fx.get_meta(StudioContext.META_BODY, FixtureCatalog.Body.PAR)
	return MountRotation.mount_of(xf, MountRotation.rules_of(StageFixture3D.scene_path_of(p_fx)),
		StageFixture3D.mount_offset(body), ctx.truss_pipes, ctx.stage_surfaces)


func _process(_delta: float) -> void:
	if fx and is_instance_valid(fx) and is_visible_in_tree():
		_pull()
