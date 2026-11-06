class_name DMXChannelRow
extends Control
## One channel of a fixture: address, name, a value bar and the number.

const HEIGHT := 22.0

var address := 1
var channel_name := ""
var color := UIPalette.TEXT_DIM
var value := 0:
	set(v):
		if v != value:
			value = v
			queue_redraw()


func _init() -> void:
	custom_minimum_size.y = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var font := get_theme_font("mono_font", "LuckyDMX")
	var ui := get_theme_default_font()
	var mid := size.y * 0.5
	if font:
		draw_string(font, Vector2(0, mid + 4), str(address), HORIZONTAL_ALIGNMENT_RIGHT, 28, 10, UIPalette.TEXT_FAINT)
		draw_string(font, Vector2(size.x - 28, mid + 4), str(value), HORIZONTAL_ALIGNMENT_RIGHT, 28, 11, UIPalette.TEXT)
	if ui:
		draw_string(ui, Vector2(36, mid + 4), channel_name, HORIZONTAL_ALIGNMENT_LEFT, 80, UIPalette.FONT_SIZE_SMALL + 1, UIPalette.TEXT_DIM)
	var bar := Rect2(Vector2(122, mid - 3), Vector2(maxf(size.x - 122 - 34, 8.0), 6))
	draw_rect(bar, UIPalette.INPUT_BG)
	if value > 0:
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * value / 255.0, bar.size.y)), color)
