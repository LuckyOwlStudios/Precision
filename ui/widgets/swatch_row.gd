class_name SwatchRow
extends HFlowContainer
## The saved colours (StudioContext.swatches) as a row of small squares: click
## one to use it, right-click to forget it, "+" saves the colour now shown.
## The row only reports clicks; the inspector puts the colour on the fixtures.

signal picked(color: Color)
signal save_requested

var ctx: StudioContext


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.swatches_changed.connect(_rebuild)
	_rebuild()


func _rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	for i in ctx.swatches.size():
		var colour := ctx.swatches[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(24, 24)
		b.tooltip_text = "#%s. Click to use it, right-click to remove." % colour.to_html(false)
		b.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = colour
			box.set_corner_radius_all(4)
			box.set_border_width_all(2 if state == "hover" else 1)
			box.border_color = Color(1, 1, 1, 0.85) if state == "hover" else Color(0, 0, 0, 0.45)
			b.add_theme_stylebox_override(state, box)
		b.pressed.connect(func() -> void: picked.emit(colour))
		b.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				ctx.remove_swatch(i))
		add_child(b)
	var add := Button.new()
	add.text = "+"
	add.custom_minimum_size = Vector2(24, 24)
	add.focus_mode = Control.FOCUS_NONE
	add.tooltip_text = "Save the colour shown above as a swatch."
	add.pressed.connect(save_requested.emit)
	add_child(add)
