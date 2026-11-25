@tool
class_name WindowButton
extends Button
## One title-bar button whose icon is drawn with lines, so it looks the same on
## every platform and needs no font glyphs or image files.

enum Glyph { MINIMIZE, MAXIMIZE, RESTORE, CLOSE }

@export var glyph := Glyph.MINIMIZE:
	set(value):
		glyph = value
		queue_redraw()
## Hover colour; the close button uses red.
@export var hover_color := UIPalette.HOVER


func _ready() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(48, 0)
	size_flags_vertical = Control.SIZE_FILL
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var hovered := is_hovered()
	if hovered:
		draw_rect(Rect2(Vector2.ZERO, size), hover_color)
	var col := Color.WHITE if (hovered and glyph == Glyph.CLOSE) else UIPalette.TEXT
	var c := (size / 2.0).round() + Vector2(0.5, 0.5)
	var h := 5.0
	match glyph:
		Glyph.MINIMIZE:
			draw_line(c + Vector2(-h, 0), c + Vector2(h, 0), col)
		Glyph.MAXIMIZE:
			draw_rect(Rect2(c - Vector2(h, h), Vector2(h, h) * 2), col, false)
		Glyph.RESTORE:
			draw_rect(Rect2(c + Vector2(-h, -h + 2), Vector2(h * 2 - 2, h * 2 - 2)), col, false)
			draw_polyline(PackedVector2Array([c + Vector2(-h + 2, -h + 2), c + Vector2(-h + 2, -h), c + Vector2(h, -h), c + Vector2(h, h - 2), c + Vector2(h - 2, h - 2)]), col)
		Glyph.CLOSE:
			draw_line(c + Vector2(-h, -h), c + Vector2(h, h), col)
			draw_line(c + Vector2(-h, h), c + Vector2(h, -h), col)
