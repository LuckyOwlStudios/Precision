class_name DMXCardHeader
extends Control
## The clickable top of a fixture card: colour tab, arrow, name, address range
## and a red "!" when its addresses clash with another fixture.

var title := ""
var range_text := ""
var color := UIPalette.TEXT_DIM
var open := false
var warn := false
var hovered := false


func _init() -> void:
	custom_minimum_size.y = 34
	mouse_filter = Control.MOUSE_FILTER_PASS


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		hovered = what == NOTIFICATION_MOUSE_ENTER
		queue_redraw()


func _draw() -> void:
	if hovered:
		draw_rect(Rect2(Vector2.ZERO, size), UIPalette.HOVER)
	draw_rect(Rect2(0, 0, 4, size.y), color)
	var c := Vector2(18, size.y * 0.5)
	var pts := PackedVector2Array([c + Vector2(-3, -4), c + Vector2(3, 0), c + Vector2(-3, 4)])
	if open:
		pts = PackedVector2Array([c + Vector2(-4, -2), c + Vector2(4, -2), c + Vector2(0, 3)])
	draw_colored_polygon(pts, UIPalette.TEXT_DIM)
	var ui := get_theme_default_font()
	var mono := get_theme_font("mono_font", "LuckyDMX")
	var right := size.x - 10.0
	if warn:
		draw_circle(Vector2(right - 6, size.y * 0.5), 7, UIPalette.LIVE)
		if ui:
			draw_string(ui, Vector2(right - 10, size.y * 0.5 + 5), "!", HORIZONTAL_ALIGNMENT_CENTER, 8, 13, UIPalette.APP_BG)
		right -= 20
	if mono:
		var w := mono.get_string_size(range_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(mono, Vector2(right - w, size.y * 0.5 + 4), range_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPalette.TEXT_DIM)
		right -= w + 10
	if ui:
		draw_string(ui, Vector2(32, size.y * 0.5 + 5), title, HORIZONTAL_ALIGNMENT_LEFT, maxf(right - 32, 20), UIPalette.FONT_SIZE, UIPalette.TEXT)
