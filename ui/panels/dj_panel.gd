class_name DJPanel
extends ScrollContainer
## The DJ tab: choose what the lights follow (nothing, the built-in
## simulator, or VirtualDJ), see what the DJ is playing and which of your
## songs it matched, and nudge the light timing.
##
## The simulator controls let you act as the DJ without any software:
## pick a song, play, pause, scrub and move the pitch.

var ctx: StudioContext

var _sim_songs: Array[Song] = []

@onready var _kind: OptionButton = %Source
@onready var _dot: Panel = %Dot
@onready var _status: Label = %Status
@onready var _deck: Control = %Deck
@onready var _deck_title: Label = %DeckTitle
@onready var _deck_detail: Label = %DeckDetail
@onready var _match: Label = %Match
@onready var _offset: SpinBox = %Offset

@onready var _vdj_box: Control = %VirtualDJ
@onready var _host: LineEdit = %Host
@onready var _port: SpinBox = %Port
@onready var _password: LineEdit = %Password
@onready var _os2l: CheckBox = %OS2L

@onready var _sim_box: Control = %Simulator
@onready var _sim_song: OptionButton = %SimTrack
@onready var _sim_play: Button = %SimPlay
@onready var _sim_seek: HSlider = %SimSeek
@onready var _sim_pitch: SpinBox = %SimPitch
@onready var _sim_time: Label = %SimTime


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.dj.status_changed.connect(_sync)
	ctx.library.songs_changed.connect(_fill_songs)
	_offset.value = ctx.dj.light_offset_ms
	_fill_songs()
	_sync()


func _ready() -> void:
	_kind.item_selected.connect(func(i: int) -> void: _switch(i as DJSync.Kind))
	_offset.value_changed.connect(func(v: float) -> void: ctx.dj.light_offset_ms = v)
	%Reconnect.pressed.connect(func() -> void: _switch(DJSync.Kind.VIRTUALDJ))
	%CopyDiagnostics.pressed.connect(_copy_diagnostics)
	%SimLoad.pressed.connect(_sim_load)
	_sim_play.pressed.connect(func() -> void:
		var sim := _sim()
		if sim:
			sim.toggle())
	_sim_seek.value_changed.connect(func(v: float) -> void:
		var sim := _sim()
		if sim and absf(v - sim.true_position()) > 0.2:
			sim.seek(v))
	_sim_pitch.value_changed.connect(func(v: float) -> void:
		var sim := _sim()
		if sim:
			sim.pitch_percent = v)


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


func _copy_diagnostics() -> void:
	var vdj := ctx.dj.source as VirtualDJSource if ctx else null
	if vdj == null:
		return
	DisplayServer.clipboard_set(vdj.diagnostics_report())
	%CopyDiagnostics.text = "Copied!"
	await get_tree().create_timer(1.5).timeout
	%CopyDiagnostics.text = "Copy diagnostics"


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

	var title := _deck_title
	var detail := _deck_detail
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
