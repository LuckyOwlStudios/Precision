class_name NowPlayingBar
extends PanelContainer
## The coloured band under the header: what is playing, the transport, tempo
## and blackout. Its background is a soft blur of the rig's live colours, so
## the band itself tells you what the room looks like right now.

var ctx: StudioContext

var _colors: PackedColorArray = []

@onready var _play: TransportButton = %Play
@onready var _title: Label = %SongTitle
@onready var _show: Label = %ShowName
@onready var _progress: HSlider = %Progress
@onready var _bpm: SpinBox = %Bpm
@onready var _beats: Array[Panel] = [%Beat1, %Beat2, %Beat3, %Beat4]
@onready var _master: HSlider = %GrandMaster
@onready var _blackout: Button = %Blackout


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.transport_changed.connect(_sync)
	ctx.blackout_changed.connect(func(on: bool) -> void: _blackout.set_pressed_no_signal(on))
	ctx.grand_master_changed.connect(func(v: float) -> void: _master.set_value_no_signal(v * 100.0))
	_bpm.value = ctx.bpm
	_master.set_value_no_signal(ctx.grand_master * 100.0)
	_sync()


func _ready() -> void:
	%Prev.pressed.connect(func() -> void: ctx.seek(0.0))
	%Stop.pressed.connect(func() -> void: ctx.stop())
	_play.pressed.connect(func() -> void: ctx.toggle_play())
	_progress.value_changed.connect(func(v: float) -> void:
		if ctx and absf(v - ctx.position_beats) > 0.01:
			ctx.seek(v))
	_bpm.value_changed.connect(func(v: float) -> void:
		if ctx:
			ctx.set_bpm(v))
	_master.value_changed.connect(func(v: float) -> void: ctx.grand_master = v / 100.0)
	_master.gui_input.connect(func(e: InputEvent) -> void:
		# Double-click the fader to snap back to full.
		if e is InputEventMouseButton and e.double_click and e.button_index == MOUSE_BUTTON_LEFT:
			ctx.grand_master = 1.0)
	_blackout.toggled.connect(func(on: bool) -> void: ctx.blackout = on)


func _sync() -> void:
	if ctx == null:
		return
	_play.icon_kind = TransportButton.Icon.PAUSE if ctx.playing else TransportButton.Icon.PLAY
	_title.text = ctx.song_title if not ctx.song_title.is_empty() else "No song loaded"
	_show.text = ctx.show_name
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
		var k := 0.0 if ctx.blackout else fx.dimmer * ctx.grand_master
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
