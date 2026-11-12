class_name EffectsPanel
extends MarginContainer
## The Effects shelf: built-in and your own presets, dragged onto the timeline.
## A clip selected on the timeline is edited in the Inspector tab (ClipInfo).

var ctx: StudioContext

@onready var _presets: ItemList = %Presets


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.effects.presets_changed.connect(_rebuild_presets)
	_rebuild_presets()


func _ready() -> void:
	_presets.set_drag_forwarding(_drag_preset, Callable(), Callable())
	_presets.item_selected.connect(func(_i: int) -> void: _update_preset_buttons())
	_presets.item_activated.connect(func(_i: int) -> void: _add_at_playhead())
	_presets.item_clicked.connect(func(_i: int, _at: Vector2, _b: int) -> void: %ShelfNote.visible = false)
	%AddAtPlayhead.pressed.connect(_add_at_playhead)
	%DeletePreset.pressed.connect(func() -> void:
		var p := _selected_preset()
		if p and not p.built_in:
			ctx.delete_preset(p))


# ----------------------------------------------------------------- shelf

func _rebuild_presets() -> void:
	if ctx == null:
		return
	var keep := _selected_preset()
	_presets.clear()
	for p in ctx.effects.presets:
		var idx := _presets.add_item(p.preset_name)
		_presets.set_item_tooltip(idx, "%s (%s) · %s" % [EffectTemplates.display_name(p.template), EffectTemplates.needs_text(p.template), "built in" if p.built_in else "your preset"])
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
	%ShelfNote.visible = false
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
	if p == null:
		return
	var pool: Array[DMXFixture] = []
	if ctx.selected and EffectTemplates.supports(p.template, ctx.selected):
		pool.append(ctx.selected)
	elif not ctx.selected_group.is_empty():
		for fx in ctx.selected_group: # a recalled group: the effect runs on just those
			if EffectTemplates.supports(p.template, fx):
				pool.append(fx)
	else:
		pool = ctx.fixtures_supporting(p.template)
	if pool.is_empty():
		%ShelfNote.text = "No fixture on stage can do %s: it %s." % [p.preset_name, EffectTemplates.needs_text(p.template)]
		%ShelfNote.visible = true
		return
	%ShelfNote.visible = false
	ctx.add_clip(p, ctx.position_beats, pool)
