class_name DMXGrid
extends Control
## The 512-channel grid drawn by the DMX monitor panel.

const COLUMNS := 10 ## rows of ten read like a console: 1-10, 11-20, ...

var ctx: StudioContext


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
