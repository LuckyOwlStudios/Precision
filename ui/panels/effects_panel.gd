class_name EffectsPanel
extends MarginContainer
## The Effects shelf (built-in and your own presets, dragged onto the timeline)
## and, below it, the settings of the effect clip selected on the timeline.

var ctx: StudioContext

@onready var _presets: ItemList = %Presets
@onready var _clip_box: VBoxContainer = %ClipBox
@onready var _clip_name: LineEdit = %ClipName
@onready var _params: VBoxContainer = %Params
@onready var _timing: GridContainer = %Timing
@onready var _targets: VBoxContainer = %Targets

var _clip: ShowClip ## the clip the settings below belong to
var _building := false


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.effects.presets_changed.connect(_rebuild_presets)
	ctx.clip_selected.connect(_show_clip)
	ctx.fixtures_changed.connect(func() -> void: _show_clip(ctx.selected_clip))
	_rebuild_presets()
	_show_clip(ctx.selected_clip)


func _ready() -> void:
	_presets.set_drag_forwarding(_drag_preset, Callable(), Callable())
	_presets.item_selected.connect(func(_i: int) -> void: _update_preset_buttons())
	_presets.item_activated.connect(func(_i: int) -> void: _add_at_playhead())
	%AddAtPlayhead.pressed.connect(_add_at_playhead)
	%DeletePreset.pressed.connect(func() -> void:
		var p := _selected_preset()
		if p and not p.built_in:
			ctx.delete_preset(p))
	_clip_name.text_submitted.connect(func(_t: String) -> void: _rename_clip())
	_clip_name.focus_exited.connect(_rename_clip)
	%SavePreset.pressed.connect(_save_preset)
	%Duplicate.pressed.connect(func() -> void:
		if _clip:
			ctx.duplicate_clip(_clip))
	%DeleteClip.pressed.connect(func() -> void:
		if _clip:
			ctx.remove_clip(_clip))
	%AllFixtures.pressed.connect(_target_all)

func _target_all() -> void:
	if _clip == null:
		return
	var paths := PackedStringArray()
	for fx in ctx.fixtures():
		paths.append(ctx.fixture_path(fx))
	var change := func() -> void: _clip.targets = paths
	_edit(change, "Change effect fixtures")
	_show_clip(_clip)


# ----------------------------------------------------------------- shelf

func _rebuild_presets() -> void:
	if ctx == null:
		return
	var keep := _selected_preset()
	_presets.clear()
	for p in ctx.effects.presets:
		var idx := _presets.add_item(p.preset_name)
		_presets.set_item_tooltip(idx, "%s · %s" % [EffectTemplates.display_name(p.template), "built in" if p.built_in else "your preset"])
		_presets.set_item_icon(idx, _swatch(EffectTemplates.lane_color(p.template)))
		_presets.set_item_custom_fg_color(idx, UIPalette.TEXT if not p.built_in else UIPalette.TEXT_DIM)
		if p == keep:
			_presets.select(idx)
	_update_preset_buttons()


var _swatches := {} ## Color -> small square icon, the colour clips get on the timeline


func _swatch(c: Color) -> Texture2D:
	if not _swatches.has(c):
		var img := Image.create(10, 10, false, Image.FORMAT_RGBA8)
		img.fill(c)
		_swatches[c] = ImageTexture.create_from_image(img)
	return _swatches[c]


func _selected_preset() -> EffectPreset:
	if ctx == null:
		return null
	var sel := _presets.get_selected_items()
	if sel.is_empty() or sel[0] >= ctx.effects.presets.size():
		return null
	return ctx.effects.presets[sel[0]]


func _update_preset_buttons() -> void:
	var p := _selected_preset()
	%AddAtPlayhead.disabled = p == null or ctx.fixtures().is_empty()
	%DeletePreset.disabled = p == null or p.built_in


func _drag_preset(at: Vector2) -> Variant:
	var i := _presets.get_item_at_position(at, true)
	if i < 0:
		return null
	_presets.select(i)
	var p: EffectPreset = ctx.effects.presets[i]
	var chip := Label.new()
	chip.text = "  %s  " % p.preset_name
	var box := StyleBoxFlat.new()
	box.bg_color = Color(EffectTemplates.lane_color(p.template), 0.85)
	box.set_corner_radius_all(4)
	box.set_content_margin_all(4)
	chip.add_theme_stylebox_override("normal", box)
	_presets.set_drag_preview(chip)
	return {"effect_preset": p}


func _add_at_playhead() -> void:
	var p := _selected_preset()
	if p == null or ctx.fixtures().is_empty():
		return
	var targets: Array[DMXFixture] = []
	if ctx.selected:
		targets.append(ctx.selected)
	else:
		targets = ctx.fixtures()
	ctx.add_clip(p, ctx.position_beats, targets)


# ------------------------------------------------------- selected clip

func _show_clip(clip: ShowClip) -> void:
	_clip = clip
	_clip_box.visible = clip != null
	%PresetNote.visible = false
	if clip == null:
		return
	_building = true
	_clip_name.text = clip.clip_name
	var t := EffectTemplates.get_template(clip.template)
	%ClipKind.text = "%s: %s" % [t.get("name", clip.template), t.get("description", "")]
	for c in _timing.get_children():
		c.queue_free()
	_add_number(_timing, "Starts at bar", clip.start / 4.0 + 1.0, 1.0, 999.0, 0.0625, "", _set_start_bar)
	_add_number(_timing, "Length", clip.length, 0.25, 512.0, 0.25, " beats", _set_length)
	_add_number(_timing, "Fade in", clip.fade_in, 0.0, 64.0, 0.25, " beats", _set_fade_in)
	_add_number(_timing, "Fade out", clip.fade_out, 0.0, 64.0, 0.25, " beats", _set_fade_out)

	for c in _params.get_children():
		c.queue_free()
	for p: Dictionary in t.get("params", []):
		_add_param(p)

	for c in _targets.get_children():
		c.queue_free()
	for fx in ctx.fixtures():
		var path := ctx.fixture_path(fx)
		var check := CheckBox.new()
		check.text = StudioContext.display_name(fx)
		check.button_pressed = clip.targets.has(path)
		check.toggled.connect(_toggle_target.bind(path))
		_targets.add_child(check)
	_building = false


func _set_start_bar(bar: float) -> void:
	var change := func() -> void: _clip.start = (bar - 1.0) * 4.0
	_edit(change, "Move effect", true)


func _set_length(v: float) -> void:
	var change := func() -> void:
		_clip.length = v
		_clip.fade_in = minf(_clip.fade_in, v)
		_clip.fade_out = minf(_clip.fade_out, v)
	_edit(change, "Stretch effect", true)


func _set_fade_in(v: float) -> void:
	var change := func() -> void: _clip.fade_in = minf(v, _clip.length)
	_edit(change, "Change fade", true)


func _set_fade_out(v: float) -> void:
	var change := func() -> void: _clip.fade_out = minf(v, _clip.length)
	_edit(change, "Change fade", true)


func _toggle_target(on: bool, path: String) -> void:
	var change := func() -> void:
		var paths := _clip.targets.duplicate()
		var i := paths.find(path)
		if on and i < 0:
			paths.append(path)
		elif not on and i >= 0:
			paths.remove_at(i)
		_clip.targets = paths
	_edit(change, "Change effect fixtures")


func _add_param(p: Dictionary) -> void:
	var key: String = p.key
	var value: Variant = _clip.params.get(key, p.default)
	match p.kind:
		EffectTemplates.FLOAT:
			var row := VBoxContainer.new()
			var label := Label.new()
			label.text = p.label
			label.theme_type_variation = &"Caption"
			row.add_child(label)
			var line := HBoxContainer.new()
			var slider := HSlider.new()
			slider.min_value = p.min
			slider.max_value = p.max
			slider.step = p.step
			slider.value = float(value)
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var box := SpinBox.new()
			box.min_value = p.min
			box.max_value = p.max
			box.step = p.step
			box.suffix = str(p.get("unit", "")).strip_edges()
			box.value = float(value)
			box.custom_minimum_size.x = 96
			slider.value_changed.connect(func(v: float) -> void:
				box.set_value_no_signal(v)
				_set_param(key, v))
			box.value_changed.connect(func(v: float) -> void:
				slider.set_value_no_signal(v)
				_set_param(key, v))
			line.add_child(slider)
			line.add_child(box)
			row.add_child(line)
			_params.add_child(row)
		EffectTemplates.BOOL:
			var check := CheckBox.new()
			check.text = p.label
			check.button_pressed = bool(value)
			check.toggled.connect(func(on: bool) -> void: _set_param(key, on))
			_params.add_child(check)
		EffectTemplates.CHOICE:
			var row := HBoxContainer.new()
			var label := Label.new()
			label.text = p.label
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var pick := OptionButton.new()
			for o: String in p.options:
				pick.add_item(o)
			pick.select(int(value))
			pick.item_selected.connect(func(i: int) -> void: _set_param(key, i))
			row.add_child(pick)
			_params.add_child(row)
		EffectTemplates.COLOR:
			var row := HBoxContainer.new()
			var label := Label.new()
			label.text = p.label
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			var pick := ColorPickerButton.new()
			pick.color = value
			pick.edit_alpha = false
			pick.custom_minimum_size = Vector2(64, 28)
			pick.color_changed.connect(func(c: Color) -> void: _set_param(key, c))
			row.add_child(pick)
			_params.add_child(row)


func _add_number(grid: GridContainer, caption: String, value: float, lo: float, hi: float, step: float, suffix: String, on_change: Callable) -> void:
	var label := Label.new()
	label.text = caption
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	var box := SpinBox.new()
	box.min_value = lo
	box.max_value = hi
	box.step = step
	box.suffix = suffix.strip_edges()
	box.value = value
	box.custom_minimum_size.x = 110
	box.value_changed.connect(on_change)
	grid.add_child(box)


func _set_param(key: String, value: Variant) -> void:
	var change := func() -> void: _clip.params[key] = value
	_edit(change, "Change effect", true)


## Change the clip with `change`, then record it as one undo step (dragging a
## slider merges into a single step).
func _edit(change: Callable, action: String, merge := false) -> void:
	if _building or _clip == null:
		return
	var before := _clip.to_data()
	change.call()
	ctx.record_clip_change(_clip, before, action, merge)


func _rename_clip() -> void:
	if _clip == null or _clip_name.text.strip_edges().is_empty() or _clip_name.text == _clip.clip_name:
		return
	var n := _clip_name.text.strip_edges()
	var change := func() -> void: _clip.clip_name = n
	_edit(change, "Rename effect")


func _save_preset() -> void:
	if _clip == null:
		return
	_rename_clip()
	var wanted := _clip.clip_name
	var p := ctx.save_clip_as_preset(_clip, wanted if not ctx.effects.is_name_taken(wanted) else "")
	%PresetNote.visible = true
	if p:
		%PresetNote.text = "Saved \"%s\" to the Effects shelf." % p.preset_name
	else:
		%PresetNote.text = "Couldn't save: that name is taken."
