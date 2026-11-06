class_name DMXOverview
extends Control
## All 512 addresses as a small map: 32 squares per row, every fixture in its
## own colour, shared addresses in red. Hover a square to see who owns it,
## click to select that fixture. The focused fixture stays bright, the rest dim.

signal slot_hovered(address: int) ## 0 when the pointer leaves
signal fixture_clicked(fixture: DMXFixture)

const COLUMNS := 32
const ROWS := 16
const GUTTER := 26.0 ## room for the row numbers on the left
const MAX_CELL := 14.0 ## keeps the map from growing huge in a wide window

var info: DMXPatchInfo
var focus: DMXFixture:
	set(v):
		if focus != v:
			focus = v
			queue_redraw()

var _hover := 0


func _ready() -> void:
	mouse_exited.connect(func() -> void:
		_hover = 0
		slot_hovered.emit(0)
		queue_redraw())


func _cell() -> float:
	return clampf(floorf((size.x - GUTTER) / COLUMNS), 3.0, MAX_CELL)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		custom_minimum_size.y = ROWS * _cell()
		queue_redraw()


func _address_at(at: Vector2) -> int:
	var cs := _cell()
	var col := int((at.x - GUTTER) / cs)
	var row := int(at.y / cs)
	if at.x < GUTTER or col < 0 or col >= COLUMNS or row < 0 or row >= ROWS:
		return 0
	return row * COLUMNS + col + 1


func _gui_input(event: InputEvent) -> void:
	if info == null:
		return
	if event is InputEventMouseMotion:
		var a := _address_at((event as InputEventMouseMotion).position)
		if a != _hover:
			_hover = a
			slot_hovered.emit(a)
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var fx := info.first_owner(_address_at(mb.position))
			if fx:
				fixture_clicked.emit(fx)
				accept_event()


func _draw() -> void:
	if info == null:
		return
	var cs := _cell()
	var font := get_theme_font("mono_font", "LuckyDMX")
	for row in ROWS:
		if row % 4 == 0 and font:
			draw_string(font, Vector2(0, row * cs + cs - 1), str(row * COLUMNS + 1), HORIZONTAL_ALIGNMENT_LEFT, GUTTER - 4, 9, UIPalette.TEXT_FAINT)
	for a in range(1, 513):
		var i := a - 1
		var r := Rect2(Vector2(GUTTER + (i % COLUMNS) * cs, (i / COLUMNS) * cs), Vector2(cs - 1, cs - 1))
		var list: Array = info.owners[a]
		if list.is_empty():
			draw_rect(r, UIPalette.INPUT_BG)
		elif list.size() > 1:
			draw_rect(r, UIPalette.LIVE)
			draw_line(r.position, r.end, UIPalette.APP_BG, 1.0)
		else:
			var fx: DMXFixture = list[0]
			var alpha := 0.8
			if focus:
				alpha = 1.0 if fx == focus else 0.28
			draw_rect(r, Color(info.colors[fx], alpha))
		if focus and list.has(focus):
			draw_rect(r.grow(0.5), Color(UIPalette.TEXT, 0.9), false, 1.0)
	if _hover > 0:
		var h := _hover - 1
		draw_rect(Rect2(Vector2(GUTTER + (h % COLUMNS) * cs, (h / COLUMNS) * cs), Vector2(cs - 1, cs - 1)).grow(1), UIPalette.TEXT, false, 1.0)
