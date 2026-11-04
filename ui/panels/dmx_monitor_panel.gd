class_name DMXMonitorPanel
extends MarginContainer
## Live view of the 512 channels being sent. Patched channels get an outline;
## brightness of each cell is the channel value. Hover a cell for details.

var ctx: StudioContext
var _grid: DMXGrid
var _status := Label.new()


class DMXGrid:
	extends Control
	const COLUMNS := 10 ## rows of ten read like a console: 1-10, 11-20, ...
	var ctx: StudioContext

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _cell_size() -> float:
		return floorf(size.x / COLUMNS)

	func _process(_delta: float) -> void:
		if is_visible_in_tree():
			custom_minimum_size.y = ceilf(512.0 / COLUMNS) * _cell_size()
			queue_redraw()

	func _draw() -> void:
		if ctx == null:
			return
		var cs := _cell_size()
		var font := get_theme_font("mono_font", "LuckyDMX")
		var patched := PackedByteArray()
		patched.resize(513)
		for fx in ctx.fixtures():
			for i in fx.profile.channels.size():
				if fx.start_address + i <= 512:
					patched[fx.start_address + i] = 1
		for a in range(1, 513):
			var i := a - 1
			var r := Rect2(Vector2((i % COLUMNS) * cs, floorf(float(i) / COLUMNS) * cs), Vector2(cs - 2, cs - 2))
			var v := 0 if ctx.blackout else ctx.universe.get_channel(a)
			draw_rect(r, UIPalette.INPUT_BG)
			if v > 0:
				draw_rect(r, Color(UIPalette.ACCENT, 0.1 + 0.6 * v / 255.0))
			if patched[a]:
				draw_rect(r, Color(UIPalette.TEXT_DIM, 0.5), false, 1.0)
			if cs >= 20 and font:
				var txt := str(v) if patched[a] else str(a)
				var col := UIPalette.TEXT if patched[a] else UIPalette.TEXT_FAINT.darkened(0.35)
				draw_string(font, r.position + Vector2(0, r.size.y * 0.5 + 4), txt, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10, col)

	func _get_tooltip(at: Vector2) -> String:
		var cs := _cell_size()
		var a := int(at.y / cs) * COLUMNS + int(at.x / cs) + 1
		if a < 1 or a > 512 or ctx == null:
			return ""
		var who := ctx.channel_owner(a)
		return "Channel %d = %d%s" % [a, ctx.universe.get_channel(a), ("\n" + who) if who != "" else ""]


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	_grid.ctx = ctx


func _ready() -> void:
	add_theme_constant_override("margin_left", UIPalette.COLUMN_PAD)
	add_theme_constant_override("margin_right", UIPalette.COLUMN_PAD)
	add_theme_constant_override("margin_top", 16)
	add_theme_constant_override("margin_bottom", 16)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	col.add_child(UIKit.section("Universe 1"))
	_status.theme_type_variation = &"Caption"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_grid = DMXGrid.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.tooltip_text = " " # enables _get_tooltip
	scroll.add_child(_grid)


func _process(_delta: float) -> void:
	if ctx and is_visible_in_tree():
		_status.text = "%d of 512 channels patched. Art-Net to %s at %d Hz.%s Patched cells show their value; hover any cell for details." % [
			ctx.patched_channel_count(), ctx.output.target_ip, int(ctx.universe.refresh_rate),
			" BLACKOUT is on." if ctx.blackout else ""]
