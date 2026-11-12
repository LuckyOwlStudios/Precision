class_name TimelinePanel
extends VBoxContainer
## Beat-grid timeline along the bottom: a music lane, one lane per fixture,
## bars and beats on the ruler, and a red playhead.
## Effect clips live on the fixture lanes (see TimelineCanvas); the Snap menu
## sets the grid they move on.

var ctx: StudioContext

@onready var _canvas: TimelineCanvas = %Canvas
@onready var _pos_label: Label = %Position
@onready var _hscroll: HScrollBar = %HScroll


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	_canvas.ctx = ctx
	ctx.transport_changed.connect(_update_label)
	ctx.song_changed.connect(func(_s: Song) -> void: _update_label())
	_update_label()


func _ready() -> void:
	%Zoom.value_changed.connect(func(v: float) -> void: _canvas.px_per_beat = v)
	# Snap: 1 beat, 1/2, 1/4, bar, off (same order as the menu).
	var snaps := [1.0, 0.5, 0.25, 4.0, 0.0]
	%Snap.item_selected.connect(func(i: int) -> void: _canvas.snap_beats = snaps[i])
	%FirstBeat.pressed.connect(func() -> void: ctx.set_first_beat_here())
	%AddPhrase.pressed.connect(func() -> void: _canvas.add_phrase_at_playhead())
	_hscroll.value_changed.connect(func(v: float) -> void:
		if not is_equal_approx(v, _canvas.scroll_beats):
			_canvas.scroll_to(v))


## Keep the scrollbar matched to the song length and the canvas's view.
func _process(_delta: float) -> void:
	if ctx == null or not is_visible_in_tree():
		return
	var page := _canvas.visible_beats()
	_hscroll.max_value = ctx.length_beats + page
	_hscroll.page = page
	_hscroll.set_value_no_signal(_canvas.scroll_beats)


func _update_label() -> void:
	var has_song := ctx.song != null and not ctx.following_dj()
	%FirstBeat.disabled = not has_song
	%AddPhrase.disabled = not has_song
	# Bars count from the song's first beat; before it is the lead-in.
	var b := ctx.position_beats - ctx.first_beat_beats()
	var secs := ctx.position_beats * 60.0 / ctx.bpm
	var bar := "LEAD-IN" if b < 0.0 else "BAR %d.%d" % [int(b / 4.0) + 1, int(b) % 4 + 1]
	var phrase := ""
	if ctx.song:
		var i := ctx.song.phrase_index_at(secs)
		if i >= 0:
			phrase = "  ·  " + str(ctx.song.phrases[i].name)
	_pos_label.text = "%s    %02d:%04.1f%s" % [bar, int(secs / 60.0), fmod(secs, 60.0), phrase]
