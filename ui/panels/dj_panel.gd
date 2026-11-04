class_name DJPanel
extends ScrollContainer
## The DJ tab: choose what the lights follow (nothing, the built-in
## simulator, or VirtualDJ), see what the DJ is playing and which of your
## songs it matched, and nudge the light timing.
##
## The simulator controls let you act as the DJ without any software:
## pick a song, play, pause, scrub and move the pitch.

var ctx: StudioContext

var _kind := OptionButton.new()
var _dot := Panel.new()
var _status := Label.new()
var _deck: VBoxContainer
var _match := Label.new()
var _offset := SpinBox.new()

var _vdj_box := VBoxContainer.new()
var _host := LineEdit.new()
var _port := SpinBox.new()
var _password := LineEdit.new()
var _os2l := CheckBox.new()

var _sim_box := VBoxContainer.new()
var _sim_song := OptionButton.new()
var _sim_play := Button.new()
var _sim_seek := HSlider.new()
var _sim_pitch := SpinBox.new()
var _sim_time := Label.new()
var _sim_songs: Array[Song] = []


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.dj.status_changed.connect(_sync)
	ctx.library.songs_changed.connect(_fill_songs)
	_offset.value = ctx.dj.light_offset_ms
	_fill_songs()
	_sync()


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(UIKit.padded(col))
	(get_child(0) as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL

	col.add_child(UIKit.section("Follow the DJ"))
	for t: String in ["Off", "Simulator", "VirtualDJ"]:
		_kind.add_item(t)
	_kind.tooltip_text = "What the lights follow. Off = the timeline plays on its own."
	_kind.item_selected.connect(func(i: int) -> void: _switch(i as DJSync.Kind))
	col.add_child(UIKit.field("Source", _kind))

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	_dot.custom_minimum_size = Vector2(8, 8)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	_dot.add_theme_stylebox_override("panel", sb)
	status_row.add_child(_dot)
	_status.theme_type_variation = &"Subtitle"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_status)
	col.add_child(status_row)

	_deck = UIKit.title_pair("", "")
	col.add_child(_deck)
	_match.theme_type_variation = &"Subtitle"
	_match.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_match)

	_offset.min_value = -500
	_offset.max_value = 500
	_offset.step = 5
	_offset.suffix = "ms"
	_offset.tooltip_text = "Fire the lights this much earlier (+) or later (-) than the DJ's playhead, to make up for interface or fixture delay."
	_offset.value_changed.connect(func(v: float) -> void: ctx.dj.light_offset_ms = v)
	col.add_child(UIKit.field("Light offset", _offset))

	# VirtualDJ settings
	_vdj_box.add_theme_constant_override("separation", 8)
	_vdj_box.add_child(UIKit.section("VirtualDJ"))
	_host.text = "127.0.0.1"
	_host.tooltip_text = "Computer running VirtualDJ. 127.0.0.1 = this one."
	_vdj_box.add_child(UIKit.field("Address", _host))
	_port.min_value = 1
	_port.max_value = 65535
	_port.value = 80
	_port.tooltip_text = "The port set in VirtualDJ's Network Control plugin."
	_vdj_box.add_child(UIKit.field("Port", _port))
	_password.secret = true
	_password.placeholder_text = "none"
	_password.tooltip_text = "The password set in the Network Control plugin, if any."
	_vdj_box.add_child(UIKit.field("Password", _password))
	_os2l.text = "Beat messages (OS2L, port 9996)"
	_os2l.button_pressed = true
	_os2l.tooltip_text = "In VirtualDJ set the option os2lDirectIp to 127.0.0.1:9996 for beat-exact timing."
	_vdj_box.add_child(_os2l)
	var reconnect := Button.new()
	reconnect.text = "Reconnect"
	reconnect.pressed.connect(func() -> void: _switch(DJSync.Kind.VIRTUALDJ))
	_vdj_box.add_child(reconnect)
	var help := Label.new()
	help.theme_type_variation = &"Subtitle"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.text = "In VirtualDJ (Pro): Settings > Extensions > Effects > Other > Network Control. Turn it on as an Auto-Start master effect and set its port here."
	_vdj_box.add_child(help)
	col.add_child(_vdj_box)

	# Simulator deck
	_sim_box.add_theme_constant_override("separation", 8)
	_sim_box.add_child(UIKit.section("Simulated deck"))
	_sim_song.tooltip_text = "The track the pretend DJ loads"
	_sim_song.fit_to_longest_item = false
	_sim_box.add_child(UIKit.field("Track", _sim_song))
	var row := HBoxContainer.new()
	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.tooltip_text = "Put this track on the deck, like a DJ loading the next song"
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.pressed.connect(_sim_load)
	row.add_child(load_btn)
	_sim_play.text = "Play"
	_sim_play.theme_type_variation = &"AccentButton"
	_sim_play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sim_play.pressed.connect(func() -> void:
		var sim := _sim()
		if sim:
			sim.toggle())
	row.add_child(_sim_play)
	_sim_box.add_child(row)
	_sim_seek.step = 0.0
	_sim_seek.focus_mode = Control.FOCUS_NONE
	_sim_seek.tooltip_text = "Scrub the deck: the lights jump with it"
	_sim_seek.value_changed.connect(func(v: float) -> void:
		var sim := _sim()
		if sim and absf(v - sim.true_position()) > 0.2:
			sim.seek(v))
	_sim_box.add_child(_sim_seek)
	_sim_time.theme_type_variation = &"Subtitle"
	_sim_box.add_child(_sim_time)
	_sim_pitch.min_value = -16
	_sim_pitch.max_value = 16
	_sim_pitch.step = 0.5
	_sim_pitch.suffix = "%"
	_sim_pitch.tooltip_text = "Pitch fader: the track and the lights speed up together"
	_sim_pitch.value_changed.connect(func(v: float) -> void:
		var sim := _sim()
		if sim:
			sim.pitch_percent = v)
	_sim_box.add_child(UIKit.field("Pitch", _sim_pitch))
	col.add_child(_sim_box)


func _switch(k: DJSync.Kind) -> void:
	var settings := {}
	if k == DJSync.Kind.VIRTUALDJ:
		settings = {"host": _host.text.strip_edges(), "port": int(_port.value), "password": _password.text, "use_os2l": _os2l.button_pressed}
	ctx.dj.use(k, settings)
	if k == DJSync.Kind.SIMULATOR:
		_sim_pitch.set_value_no_signal(0.0)
		if ctx.song:
			_sim_song.select(maxi(0, _sim_songs.find(ctx.song)))
			_sim_load()


func _sim() -> SimulatedDJSource:
	return ctx.dj.source as SimulatedDJSource if ctx else null


func _sim_load() -> void:
	var sim := _sim()
	var i := _sim_song.selected
	if sim and i >= 0 and i < _sim_songs.size():
		sim.load_track(_sim_songs[i])


func _fill_songs() -> void:
	if ctx == null:
		return
	_sim_songs = ctx.library.songs.duplicate()
	_sim_song.clear()
	for s in _sim_songs:
		_sim_song.add_item(s.display_title())
	if _sim_songs.is_empty():
		_sim_song.add_item("Import a song first")
		_sim_song.disabled = true
	else:
		_sim_song.disabled = false


func _sync() -> void:
	if ctx == null:
		return
	var dj := ctx.dj
	_kind.select(dj.kind)
	var src := dj.source
	_status.text = dj.status_text()
	var ok := src != null and src.connected
	(_dot.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = UIPalette.OK if ok else UIPalette.TEXT_FAINT
	_vdj_box.visible = dj.kind == DJSync.Kind.VIRTUALDJ
	_sim_box.visible = dj.kind == DJSync.Kind.SIMULATOR

	var title := _deck.get_meta("title") as Label
	var detail := _deck.get_meta("detail") as Label
	_deck.visible = src != null
	_match.visible = src != null
	if src == null:
		return
	if src.track == null:
		title.text = "Nothing on the deck"
		detail.text = ""
		_match.text = ""
	else:
		title.text = src.track.title if not src.track.title.is_empty() else src.track.file_path.get_file()
		var bits := PackedStringArray()
		if not src.track.artist.is_empty():
			bits.append(src.track.artist)
		bits.append("Playing" if src.playing else "Paused")
		if src.track.deck > 0:
			bits.append("Deck %d" % src.track.deck)
		detail.text = " · ".join(bits)
		if dj.matched:
			_match.text = "Show: %s (matched by %s)" % [dj.matched.show_name, dj.match_how]
		else:
			_match.text = "Not in your library, so the lights wait. Import this song to give it a show."


func _process(_delta: float) -> void:
	var sim := _sim()
	if sim == null or not _sim_box.visible:
		return
	_sim_play.text = "Pause" if sim.deck_playing() else "Play"
	if sim.track:
		_sim_seek.max_value = maxf(sim.track.duration, 1.0)
		_sim_seek.set_value_no_signal(sim.true_position())
		_sim_time.text = "%s / %s   ·   lights at %s" % [Song.format_time(sim.true_position()), Song.format_time(sim.track.duration), Song.format_time(sim.position_seconds())]
	# Play/pause also changes the status line.
	if Engine.get_process_frames() % 15 == 0:
		_sync()
