class_name NowPlayingBar
extends PanelContainer
## The coloured band under the header: what is playing, the transport, tempo
## and blackout. Its background is a soft blur of the rig's live colours, so
## the band itself tells you what the room looks like right now.

var ctx: StudioContext

var _play := TransportButton.new(TransportButton.Icon.PLAY, true)
var _titles: VBoxContainer
var _progress := HSlider.new()
var _bpm := SpinBox.new()
var _beats: Array[Panel] = []
var _blackout := Button.new()
var _colors: PackedColorArray = []


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.transport_changed.connect(_sync)
	ctx.blackout_changed.connect(func(on: bool) -> void: _blackout.set_pressed_no_signal(on))
	_bpm.value = ctx.bpm
	_sync()


func _ready() -> void:
	theme_type_variation = &"HeroBar"
	custom_minimum_size.y = 76
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	var prev := TransportButton.new(TransportButton.Icon.PREV)
	prev.tooltip_text = "Back to start"
	prev.pressed.connect(func() -> void: ctx.seek(0.0))
	var stop := TransportButton.new(TransportButton.Icon.STOP)
	stop.tooltip_text = "Stop"
	stop.pressed.connect(func() -> void: ctx.stop())
	_play.tooltip_text = "Play / pause (Space)"
	_play.pressed.connect(func() -> void: ctx.toggle_play())
	for b: Control in [prev, _play, stop]:
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)

	_titles = UIKit.title_pair("", "")
	_titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_titles.custom_minimum_size.x = 260
	(_titles.get_meta("title") as Label).theme_type_variation = &"BigTitle"
	(_titles.get_meta("detail") as Label).theme_type_variation = &"TitleLabel"
	row.add_child(_titles)

	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress.step = 0.0
	_progress.focus_mode = Control.FOCUS_NONE
	_progress.value_changed.connect(func(v: float) -> void:
		if ctx and absf(v - ctx.position_beats) > 0.01:
			ctx.seek(v))
	row.add_child(_progress)

	# Beat dots: four, the current beat lit.
	var dots := HBoxContainer.new()
	dots.add_theme_constant_override("separation", 5)
	dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in 4:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(8, 8)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		sb.bg_color = Color(1, 1, 1, 0.15)
		p.add_theme_stylebox_override("panel", sb)
		dots.add_child(p)
		_beats.append(p)
	row.add_child(dots)

	_bpm.min_value = 40
	_bpm.max_value = 220
	_bpm.step = 0.5
	_bpm.suffix = "BPM"
	_bpm.custom_minimum_size.x = 104
	_bpm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bpm.tooltip_text = "Tempo of the song's beat grid. With DJ sync on, the lights follow the DJ's playhead and pitch."
	_bpm.value_changed.connect(func(v: float) -> void:
		if ctx:
			ctx.set_bpm(v))
	row.add_child(_bpm)

	_blackout.text = "BLACKOUT"
	_blackout.theme_type_variation = &"DangerButton"
	_blackout.toggle_mode = true
	_blackout.tooltip_text = "Send zeros to every channel while held on (Esc)"
	_blackout.focus_mode = Control.FOCUS_NONE
	_blackout.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_blackout.toggled.connect(func(on: bool) -> void: ctx.blackout = on)
	row.add_child(_blackout)


func _sync() -> void:
	if ctx == null:
		return
	_play.icon_kind = TransportButton.Icon.PAUSE if ctx.playing else TransportButton.Icon.PLAY
	(_titles.get_meta("title") as Label).text = ctx.song_title if not ctx.song_title.is_empty() else "No song loaded"
	(_titles.get_meta("detail") as Label).text = ctx.show_name
	_progress.max_value = ctx.length_beats
	_progress.set_value_no_signal(ctx.position_beats)
	var beat := int(ctx.position_beats) % 4
	for i in _beats.size():
		var sb := _beats[i].get_theme_stylebox("panel") as StyleBoxFlat
		sb.bg_color = (UIPalette.BEAT if i == beat and ctx.playing else Color(1, 1, 1, 0.15))


func _process(_delta: float) -> void:
	# Re-sample the rig's colours (left to right on stage) a few times a second.
	if ctx == null or Engine.get_process_frames() % 6 != 0:
		return
	var fixtures := ctx.fixtures()
	fixtures.sort_custom(func(a: DMXFixture, b: DMXFixture) -> bool:
		return (a.get_meta(StudioContext.META_POSITION, Vector3.ZERO) as Vector3).x < (b.get_meta(StudioContext.META_POSITION, Vector3.ZERO) as Vector3).x)
	var cols := PackedColorArray()
	for fx in fixtures:
		var k := 0.0 if ctx.blackout else fx.dimmer
		cols.append(Color(fx.color.r * k, fx.color.g * k, fx.color.b * k))
	if cols != _colors:
		_colors = cols
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var stops := _colors.duplicate()
	if stops.is_empty():
		stops = PackedColorArray([Color("2a2230"), Color("1d2230"), Color("1c2a2e")])
	if stops.size() == 1:
		stops.append(stops[0])
	# Wide soft horizontal gradient, muted so white text stays readable.
	for i in stops.size() - 1:
		var x0 := w * i / (stops.size() - 1)
		var x1 := w * (i + 1) / (stops.size() - 1)
		var c0 := _mute(stops[i])
		var c1 := _mute(stops[i + 1])
		draw_polygon(PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, h), Vector2(x0, h)]),
			PackedColorArray([c0, c1, c1, c0]))
	# Fade the bottom into the panels below, and a hairline.
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.45)]))
	draw_line(Vector2(0, h - 0.5), Vector2(w, h - 0.5), UIPalette.HAIRLINE)


static func _mute(c: Color) -> Color:
	return UIPalette.CENTER_BG.lerp(c, 0.55).darkened(0.15)
