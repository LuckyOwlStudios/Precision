class_name SongRow
extends PanelContainer
## One song in the library list. The layout is song_row.tscn; the song
## library panel makes one per song and sets `song` before adding it.

signal activated(song: Song)
signal context_requested(song: Song, at: Vector2)

var song: Song
var current := false:
	set(v):
		current = v
		if is_node_ready():
			_restyle()
var _hover := false

@onready var _title: Label = %Title
@onready var _detail: Label = %Detail
@onready var _show: Label = %Show


func _ready() -> void:
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))
	refresh()


func refresh() -> void:
	_title.text = song.display_title()
	_detail.text = song.detail_line()
	_show.text = "◆ " + song.show_name + ("   · reading waveform…" if song.analysing else "")
	tooltip_text = "%s\nImported from %s" % [song.display_title(), song.source_path]
	_restyle()


func _set_hover(on: bool) -> void:
	_hover = on
	_restyle()


func _restyle() -> void:
	var sb := StyleBoxFlat.new()
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	sb.set_corner_radius_all(UIPalette.RADIUS)
	sb.bg_color = UIPalette.SELECTED_ROW if current else (UIPalette.HOVER if _hover else Color(0, 0, 0, 0))
	if current:
		sb.border_color = UIPalette.BEAT
		sb.border_width_left = 2
	add_theme_stylebox_override("panel", sb)
	_show.add_theme_color_override("font_color", UIPalette.BEAT if current else UIPalette.TEXT_FAINT)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(song)
		accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		context_requested.emit(song, mb.global_position)
		accept_event()
