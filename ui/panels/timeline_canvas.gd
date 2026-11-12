class_name TimelineCanvas
extends Control
## The drawn part of the timeline: ruler, lanes, waveform, effect clips and
## playhead. One lane per fixture; a clip shows on the lane of every fixture it
## runs on, and clips that overlap in time stack in rows inside the lane, like
## tracks in an animation editor.
##
##   Drag a preset from the Effects shelf onto a lane (or onto the music lane
##   for every fixture). Drag a clip to move it, drag its ends to stretch it.
##   Right-click a clip for Duplicate / Save as preset / Delete.
##   Ruler: right-click to add a phrase (intro, drop...) or set where the first
##   beat is; drag a phrase flag (snaps to bars, Alt = free) or the cyan first-beat
##   flag to move it; M adds a phrase at the playhead.
##   Wheel (or the scrollbar) scrolls time, Shift+wheel scrolls lanes, Ctrl+wheel
##   zooms, Home goes back to the start. Click a lane's name to select that fixture.

const HEADER_W := 168.0
const RULER_H := 42.0
const PHRASE_H := 16.0 ## phrase flags along the top of the ruler
const FLAG_GRAB := 7.0 ## px either side of a marker that grabs it
const MUSIC_H := 52.0
const LANE_H := 30.0
const ROW_H := 24.0 ## one row of clips inside a lane
const EDGE_PX := 7.0 ## grab zone for stretching a clip

var ctx: StudioContext
var px_per_beat := 22.0
var scroll_beats := 0.0
var scroll_y := 0.0 ## lanes scrolled up by this many pixels
## Grid snap in beats for moving and stretching clips; 0 = off.
var snap_beats := 1.0
var _scrubbing := false

enum Drag { NONE, MOVE, LEFT, RIGHT, PHRASE, FIRST_BEAT }
var _drag := Drag.NONE
var _drag_clip: ShowClip
var _drag_before: Dictionary
var _drag_from_x := 0.0
var _drag_start := 0.0
var _drag_end := 0.0
var _drop_lane := -2 ## lane under a dragged preset: -1 = music lane (all fixtures), -2 = none
var _drop_preset: EffectPreset ## the preset being dragged over the timeline, to grey out lanes that can't do it
## Set when you scroll by hand, so the view stops chasing the playhead until
## you seek, scrub, or press play again.
var _manual_scroll := false
var _last_pos := 0.0
var _was_playing := false
var _menu: PopupMenu
var _menu_clip: ShowClip
var _marks_menu: PopupMenu
var _add_sub: PopupMenu
var _kind_sub: PopupMenu
var _rename_dialog: ConfirmationDialog
var _rename_edit: LineEdit
var _menu_phrase := -1 ## phrase under a right-click, or -1
var _menu_seconds := 0.0 ## where a right-click landed, snapped to a bar
var _menu_seconds_raw := 0.0 ## the same, unsnapped
var _drag_phrase: Dictionary
var _drag_marks: Dictionary ## the song's marks when a marker drag began

enum MenuItem { DUPLICATE, SAVE_PRESET, DELETE }
enum MarksItem { FIRST_HERE, FIRST_AT, NUDGE_BACK, NUDGE_FWD, RESET_GRID, RENAME, DELETE_PHRASE }
const ADD_BASE := 100 ## "Add phrase" submenu ids: ADD_BASE + index in PhraseKinds.KINDS
const KIND_BASE := 200 ## "Change to" submenu ids


func _ready() -> void:
	focus_mode = FOCUS_CLICK
	_menu = PopupMenu.new()
	_menu.add_item("Duplicate", MenuItem.DUPLICATE)
	_menu.add_item("Save as preset", MenuItem.SAVE_PRESET)
	_menu.add_separator()
	_menu.add_item("Delete", MenuItem.DELETE)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	_marks_menu = PopupMenu.new()
	_add_sub = PopupMenu.new()
	_kind_sub = PopupMenu.new()
	for i in PhraseKinds.KINDS.size():
		_add_sub.add_item(PhraseKinds.KINDS[i], ADD_BASE + i)
		_kind_sub.add_item(PhraseKinds.KINDS[i], KIND_BASE + i)
	_add_sub.id_pressed.connect(_on_marks_menu)
	_kind_sub.id_pressed.connect(_on_marks_menu)
	_marks_menu.id_pressed.connect(_on_marks_menu)
	_marks_menu.add_child(_add_sub)
	_marks_menu.add_child(_kind_sub)
	add_child(_marks_menu)
	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "Rename phrase"
	_rename_edit = LineEdit.new()
	_rename_edit.custom_minimum_size = Vector2(240, 0)
	_rename_dialog.add_child(_rename_edit)
	_rename_dialog.register_text_enter(_rename_edit)
	_rename_dialog.confirmed.connect(func() -> void:
		ctx.rename_phrase(_menu_phrase, _rename_edit.text.strip_edges()))
	add_child(_rename_dialog)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drop_lane = -2
		_drop_preset = null


# ------------------------------------------------------------------ layout

## Lanes top to bottom: {fx, path, y, h, rows: {ShowClip: row}}. `y` already
## includes the vertical scroll.
func _lanes() -> Array[Dictionary]:
	var by_path := {}
	if ctx.show:
		for clip in ctx.show.clips:
			for path in clip.targets:
				if not by_path.has(path):
					by_path[path] = []
				by_path[path].append(clip)
	var out: Array[Dictionary] = []
	var y := RULER_H + MUSIC_H - scroll_y
	for fx in ctx.fixtures():
		var path := ctx.fixture_path(fx)
		var clips: Array = by_path.get(path, [])
		clips.sort_custom(func(a: ShowClip, b: ShowClip) -> bool: return a.start < b.start)
		var row_ends: Array[float] = []
		var rows := {}
		for clip: ShowClip in clips:
			var r := 0
			while r < row_ends.size() and row_ends[r] > clip.start + 0.0001:
				r += 1
			if r == row_ends.size():
				row_ends.append(0.0)
			row_ends[r] = clip.end()
			rows[clip] = r
		var h := maxf(LANE_H, row_ends.size() * ROW_H + 6.0)
		out.append({"fx": fx, "path": path, "y": y, "h": h, "rows": rows})
		y += h
	return out


func _content_height() -> float:
	var h := RULER_H + MUSIC_H
	for lane in _lanes():
		h += lane.h
	return h + scroll_y


func _clip_rect(lane: Dictionary, clip: ShowClip) -> Rect2:
	var r: int = lane.rows[clip]
	var x0 := _x(clip.start)
	var x1 := _x(clip.end())
	return Rect2(x0, lane.y + 3.0 + r * ROW_H, maxf(4.0, x1 - x0), ROW_H - 3.0)


## {clip, lane, rect} under a point, or {}.
func _clip_at(pos: Vector2) -> Dictionary:
	if pos.x < HEADER_W:
		return {}
	for lane in _lanes():
		if pos.y < lane.y or pos.y >= lane.y + lane.h:
			continue
		for clip: ShowClip in lane.rows:
			var rect := _clip_rect(lane, clip)
			if rect.grow_individual(EDGE_PX * 0.5, 0, EDGE_PX * 0.5, 0).has_point(pos):
				return {"clip": clip, "lane": lane, "rect": rect}
	return {}


## Index of the fixture lane at a height; -1 = music lane, -2 = ruler/nothing.
func _lane_index_at(y: float) -> int:
	if y >= RULER_H and y < RULER_H + MUSIC_H:
		return -1
	var lanes := _lanes()
	for i in lanes.size():
		if y >= lanes[i].y and y < lanes[i].y + lanes[i].h and y >= RULER_H + MUSIC_H:
			return i
	return -2


func _beat_at(x: float) -> float:
	return scroll_beats + (x - HEADER_W) / px_per_beat


## Snap to the beat grid, which starts at the song's first beat.
func _snap(b: float) -> float:
	if snap_beats <= 0.0:
		return b
	var fb := ctx.first_beat_beats()
	return fb + roundf((b - fb) / snap_beats) * snap_beats


func _process(_delta: float) -> void:
	if is_visible_in_tree() and ctx:
		_follow_playhead()
		queue_redraw()


func _x(beat: float) -> float:
	return HEADER_W + (beat - scroll_beats) * px_per_beat


func _draw() -> void:
	if ctx == null:
		return
	var font := get_theme_default_font()
	var bold := get_theme_font("bold_font", "LuckyDMX")
	var mono := get_theme_font("mono_font", "LuckyDMX")
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), UIPalette.CENTER_BG)

	# Lanes
	var lanes := _lanes()
	for i in lanes.size():
		var lane: Dictionary = lanes[i]
		if i % 2 == 0:
			draw_rect(Rect2(HEADER_W, lane.y, w - HEADER_W, lane.h), Color(1, 1, 1, 0.012))
		if _drop_preset and not EffectTemplates.supports(_drop_preset.template, lane.fx):
			draw_rect(Rect2(HEADER_W, lane.y, w - HEADER_W, lane.h), Color(0, 0, 0, 0.35))
			draw_string(font, Vector2(HEADER_W + 12, lane.y + minf(lane.h, LANE_H) * 0.5 + 4), "Can't do %s: %s" % [_drop_preset.preset_name, EffectTemplates.needs_text(_drop_preset.template)], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPalette.TEXT_FAINT)
		elif i == _drop_lane:
			draw_rect(Rect2(HEADER_W, lane.y, w - HEADER_W, lane.h), Color(UIPalette.ACCENT, 0.08))
		draw_line(Vector2(0, lane.y + lane.h), Vector2(w, lane.y + lane.h), UIPalette.HAIRLINE)
	draw_line(Vector2(0, RULER_H + MUSIC_H), Vector2(w, RULER_H + MUSIC_H), UIPalette.HAIRLINE)

	# Grid: beats faint, bars stronger, every 4th bar labelled. It starts at the
	# song's first beat, so a track with a silent intro still lines up.
	var fb := ctx.first_beat_beats()
	var first := floori(scroll_beats - fb)
	var last := ceili(scroll_beats + (w - HEADER_W) / px_per_beat - fb)
	for k in range(first, last + 1):
		var x := _x(fb + k)
		if x < HEADER_W:
			continue
		var is_bar := posmod(k, 4) == 0
		var col := Color(1, 1, 1, 0.07) if is_bar else Color(1, 1, 1, 0.025)
		if (not is_bar) and px_per_beat < 8.0:
			continue
		draw_line(Vector2(x, PHRASE_H), Vector2(x, h), col)
		if is_bar:
			draw_line(Vector2(x, RULER_H - 8), Vector2(x, RULER_H), UIPalette.TEXT_FAINT)
			var bar_no := floori(k / 4.0) + 1
			if bar_no >= 1 and (bar_no - 1) % (4 if px_per_beat < 14 else 1) == 0:
				draw_string(mono, Vector2(x + 4, RULER_H - 9), str(bar_no), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPalette.TEXT_DIM)
	draw_line(Vector2(HEADER_W, RULER_H), Vector2(w, RULER_H), UIPalette.HAIRLINE)

	if ctx.song:
		_draw_phrases(font, w)

	# Music lane: the song's waveform on the beat grid, or a drop hint.
	var music_rect := Rect2(HEADER_W + 8, RULER_H + 8, w - HEADER_W - 16, MUSIC_H - 16)
	if ctx.song == null:
		draw_style_box(_dashed_box(), music_rect)
		draw_string(font, music_rect.position + Vector2(12, music_rect.size.y * 0.5 + 5), "Drop a song onto the window to build its show on the beat grid", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPalette.TEXT_FAINT)
	else:
		_draw_waveform(Rect2(HEADER_W, RULER_H + 4, w - HEADER_W, MUSIC_H - 8), font)

	if _drop_lane == -1:
		draw_rect(Rect2(HEADER_W, RULER_H, w - HEADER_W, MUSIC_H), Color(UIPalette.ACCENT, 0.08))
		draw_string(font, Vector2(HEADER_W + 12, RULER_H + MUSIC_H - 8), "Drop here to put it on every fixture that can do it", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPalette.ACCENT)

	# Effect clips, clipped to the lane area so they scroll under the ruler.
	for lane in lanes:
		if lane.y + lane.h < RULER_H + MUSIC_H or lane.y > h:
			continue
		for clip: ShowClip in lane.rows:
			var rect := _clip_rect(lane, clip)
			if rect.position.y >= RULER_H + MUSIC_H - 1.0:
				_draw_clip(rect, clip, font)

	# Fixture lanes: a thin live colour strip so you can see each light at a glance.
	for lane in lanes:
		var fx: DMXFixture = lane.fx
		var c: Color = fx.out("color") * (0.0 if ctx.blackout else float(fx.out("dimmer")) * ctx.grand_master)
		c.a = 1.0
		draw_rect(Rect2(HEADER_W - 6, lane.y + 8, 3, lane.h - 16), c)

	# Lane headers (drawn last so the grid scrolls under them).
	draw_rect(Rect2(0, 0, HEADER_W - 7, h), UIPalette.SIDE_BG)
	draw_line(Vector2(HEADER_W, 0), Vector2(HEADER_W, h), UIPalette.HAIRLINE)
	for lane in lanes:
		var fx: DMXFixture = lane.fx
		var f := bold if fx == ctx.selected else font
		draw_string(f, Vector2(UIPalette.COLUMN_PAD, lane.y + minf(lane.h, LANE_H) * 0.5 + 5), StudioContext.display_name(fx), HORIZONTAL_ALIGNMENT_LEFT, HEADER_W - 28, 12, UIPalette.TEXT if fx == ctx.selected else UIPalette.TEXT_DIM)
		draw_line(Vector2(0, lane.y + lane.h), Vector2(HEADER_W, lane.y + lane.h), UIPalette.HAIRLINE)
	# Ruler and music lane stay put over scrolled lanes.
	draw_rect(Rect2(0, 0, HEADER_W, RULER_H + MUSIC_H), UIPalette.SIDE_BG)
	draw_string(bold, Vector2(UIPalette.COLUMN_PAD, RULER_H + MUSIC_H * 0.5 + 5), ctx.song_title if ctx.song else "Music", HORIZONTAL_ALIGNMENT_LEFT, HEADER_W - 28, 12, UIPalette.TEXT)
	draw_string(font, Vector2(UIPalette.COLUMN_PAD, RULER_H + MUSIC_H * 0.5 + 21), ("%d BPM · 4/4" % roundi(ctx.bpm)) + ((" · 1st beat %.2fs" % ctx.song.beat_offset) if ctx.song and ctx.song.beat_offset > 0.0 else ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPalette.BEAT)
	draw_line(Vector2(0, RULER_H + MUSIC_H), Vector2(w, RULER_H + MUSIC_H), UIPalette.HAIRLINE)
	draw_line(Vector2(HEADER_W, 0), Vector2(HEADER_W, RULER_H + MUSIC_H), UIPalette.HAIRLINE)
	draw_string(mono, Vector2(UIPalette.COLUMN_PAD, PHRASE_H - 5), "PHRASES", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPalette.TEXT_FAINT)
	draw_string(mono, Vector2(UIPalette.COLUMN_PAD, RULER_H - 9), "BAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPalette.TEXT_FAINT)
	if lanes.is_empty():
		draw_string(font, Vector2(HEADER_W + 12, RULER_H + MUSIC_H + 20), "Add fixtures in the Stage workspace, then drag effects from the Effects tab onto their lanes", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPalette.TEXT_FAINT)
	elif ctx.show == null or ctx.show.clips.is_empty():
		draw_string(font, Vector2(HEADER_W + 12, RULER_H + MUSIC_H + LANE_H * 0.5 + 5), "Drag an effect from the Effects tab onto a fixture's lane", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPalette.TEXT_FAINT)

	# Playhead
	var px := _x(ctx.position_beats)
	if px >= HEADER_W:
		draw_line(Vector2(px, 0), Vector2(px, h), UIPalette.LIVE, 1.5)
		draw_colored_polygon(PackedVector2Array([Vector2(px - 6, 0), Vector2(px + 6, 0), Vector2(px, 8)]), UIPalette.LIVE)


## Phrase flags along the top of the ruler, tinted bands down the music lane,
## and the cyan first-beat flag.
func _draw_phrases(font: Font, w: float) -> void:
	var song := ctx.song
	for i in song.phrases.size():
		var ph: Dictionary = song.phrases[i]
		var x0 := _x(ctx.seconds_to_beats(ph.time))
		var x1 := w
		if i + 1 < song.phrases.size():
			x1 = _x(ctx.seconds_to_beats(song.phrases[i + 1].time))
		if x1 <= HEADER_W or x0 >= w:
			continue
		var col := PhraseKinds.color_for(ph.name)
		var vx0 := maxf(x0, HEADER_W)
		draw_rect(Rect2(vx0, 0, x1 - vx0, PHRASE_H - 1), Color(col, 0.28))
		draw_rect(Rect2(vx0, RULER_H, x1 - vx0, MUSIC_H), Color(col, 0.07))
		if x0 >= HEADER_W:
			draw_rect(Rect2(x0, 0, 2, PHRASE_H - 1), col)
			draw_line(Vector2(x0, RULER_H), Vector2(x0, RULER_H + MUSIC_H), Color(col, 0.6))
		var room := x1 - vx0 - 8.0
		if room > 12.0:
			draw_string(font, Vector2(vx0 + 6, PHRASE_H - 5), ph.name, HORIZONTAL_ALIGNMENT_LEFT, room, 10, col.lightened(0.35))
	var fx := _x(ctx.first_beat_beats())
	if fx >= HEADER_W - 1.0:
		draw_line(Vector2(fx, PHRASE_H), Vector2(fx, RULER_H + MUSIC_H), Color(UIPalette.BEAT, 0.55), 1.5)
		draw_colored_polygon(PackedVector2Array([Vector2(fx - 5, PHRASE_H + 1), Vector2(fx + 5, PHRASE_H + 1), Vector2(fx, PHRASE_H + 9)]), UIPalette.BEAT)


## Peaks drawn as one vertical line per pixel column, centred in the lane.
## The part already played is brighter, so you can see where you are.
func _draw_waveform(lane: Rect2, font: Font) -> void:
	var song := ctx.song
	var x0 := maxf(lane.position.x, _x(0.0))
	var x1 := minf(lane.end.x, _x(ctx.length_beats))
	if x1 <= x0:
		return
	var mid := lane.position.y + lane.size.y * 0.5
	var half := lane.size.y * 0.5
	var played_x := _x(ctx.position_beats)
	if song.peaks.is_empty():
		draw_line(Vector2(x0, mid), Vector2(x1, mid), Color(UIPalette.BEAT, 0.35))
		var msg := "Reading waveform…" if song.analysing else ""
		draw_string(font, Vector2(x0 + 8, mid - 6), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UIPalette.TEXT_FAINT)
		return
	var pps := float(Song.PEAKS_PER_SECOND)
	var secs_per_px := 60.0 / (ctx.bpm * px_per_beat)
	var n := song.peaks.size()
	var past := PackedVector2Array()
	var ahead := PackedVector2Array()
	var x := floorf(x0)
	while x < x1:
		var t := ctx.beats_to_seconds(scroll_beats + (x - HEADER_W) / px_per_beat)
		var i0 := clampi(int(t * pps), 0, n - 1)
		var i1 := clampi(int((t + secs_per_px) * pps), i0 + 1, n)
		var p := 0.0
		for i in range(i0, i1):
			p = maxf(p, song.peaks[i])
		var hh := maxf(0.5, p * half)
		var target := past if x < played_x else ahead
		target.append(Vector2(x + 0.5, mid - hh))
		target.append(Vector2(x + 0.5, mid + hh))
		x += 1.0
	if not past.is_empty():
		draw_multiline(past, Color(UIPalette.BEAT, 0.9))
	if not ahead.is_empty():
		draw_multiline(ahead, Color(UIPalette.BEAT, 0.45))


## Keep the playhead on screen while playing, and bring it into view when it
## jumps (Back to start, a seek, the DJ jumping). Scrolling by hand stops the
## chase until you seek, scrub or press play, so you can always look back to
## the start of the song while it plays.
func _follow_playhead() -> void:
	var pos := ctx.position_beats
	var jumped := absf(pos - _last_pos) > 0.5 and not _scrubbing
	var started := ctx.playing and not _was_playing
	_last_pos = pos
	_was_playing = ctx.playing
	if jumped or started:
		_manual_scroll = false
	if _manual_scroll or _scrubbing or _drag != Drag.NONE:
		return
	if not ctx.playing and not jumped:
		return
	var visible_beats := (size.x - HEADER_W) / px_per_beat
	if pos > scroll_beats + visible_beats * 0.9 or pos < scroll_beats:
		scroll_beats = maxf(0.0, pos - visible_beats * 0.1)


## Scroll the view by hand (wheel, trackpad, scrollbar).
func scroll_to(beats: float) -> void:
	scroll_beats = clampf(beats, 0.0, ctx.length_beats if ctx else 0.0)
	_manual_scroll = true


func visible_beats() -> float:
	return maxf(1.0, (size.x - HEADER_W) / px_per_beat)


func _dashed_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(UIPalette.BEAT, 0.03)
	s.border_color = Color(UIPalette.BEAT, 0.25)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	return s


func _draw_clip(rect: Rect2, clip: ShowClip, font: Font) -> void:
	if rect.end.x < HEADER_W or rect.position.x > size.x:
		return
	var vis := Rect2(Vector2(maxf(rect.position.x, HEADER_W), rect.position.y), Vector2.ZERO)
	vis.end = Vector2(minf(rect.end.x, size.x), rect.end.y)
	var base := EffectTemplates.lane_color(clip.template)
	var sel := clip == ctx.selected_clip
	var box := StyleBoxFlat.new()
	box.bg_color = Color(base, 0.85 if sel else 0.5)
	box.border_color = UIPalette.ACCENT if sel else Color(base.lightened(0.3), 0.9)
	box.set_border_width_all(2 if sel else 1)
	box.set_corner_radius_all(4)
	draw_style_box(box, vis)
	# Fades as ramps in the corners.
	var top := rect.position.y + 2.0
	var bottom := rect.end.y - 2.0
	if clip.fade_in > 0.0:
		var fx := rect.position.x + clip.fade_in * px_per_beat
		draw_line(Vector2(rect.position.x, bottom), Vector2(fx, top), Color(1, 1, 1, 0.6), 1.0, true)
	if clip.fade_out > 0.0:
		var fx := rect.end.x - clip.fade_out * px_per_beat
		draw_line(Vector2(fx, top), Vector2(rect.end.x, bottom), Color(1, 1, 1, 0.6), 1.0, true)
	# Name, kept readable when the clip starts off screen.
	var tx := vis.position.x + 6.0
	var room := vis.end.x - tx - 4.0
	if room > 14.0:
		draw_string(font, Vector2(tx, rect.position.y + rect.size.y * 0.5 + 4.0), clip.clip_name, HORIZONTAL_ALIGNMENT_LEFT, room, 11, UIPalette.TEXT if sel else Color(UIPalette.TEXT, 0.9))
	if sel:
		for ex in [rect.position.x + 2.0, rect.end.x - 4.0]:
			if ex >= HEADER_W:
				draw_rect(Rect2(ex, rect.position.y + 5.0, 2.0, rect.size.y - 10.0), UIPalette.ACCENT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				_press(mb.position)
			else:
				_release()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if ctx.song and mb.position.x >= HEADER_W and mb.position.y < RULER_H + MUSIC_H:
				_open_marks_menu(mb.position)
				accept_event()
				return
			var hit := _clip_at(mb.position)
			if not hit.is_empty():
				_menu_clip = hit.clip
				ctx.select_clip(_menu_clip)
				_menu.position = Vector2i(get_screen_position() + mb.position)
				_menu.popup()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mb.ctrl_pressed:
				px_per_beat = minf(px_per_beat * 1.15, 120.0)
			elif mb.shift_pressed:
				scroll_y = maxf(0.0, scroll_y - LANE_H)
			else:
				scroll_to(scroll_beats - 4.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.ctrl_pressed:
				px_per_beat = maxf(px_per_beat / 1.15, 3.0)
			elif mb.shift_pressed:
				scroll_y = clampf(scroll_y + LANE_H, 0.0, maxf(0.0, _content_height() - size.y))
			else:
				scroll_to(scroll_beats + 4.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_LEFT:
			scroll_to(scroll_beats - 4.0)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			scroll_to(scroll_beats + 4.0)
		accept_event()
	elif event is InputEventPanGesture:
		# Trackpad two-finger scroll: sideways moves through the song, up/down
		# through the lanes.
		var pan := (event as InputEventPanGesture).delta
		scroll_to(scroll_beats + pan.x * 2.0)
		scroll_y = clampf(scroll_y + pan.y * 8.0, 0.0, maxf(0.0, _content_height() - size.y))
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag != Drag.NONE:
			_drag_to(mm.position)
		elif _scrubbing:
			_scrub(mm.position.x)
		else:
			_update_cursor(mm.position)
	elif event is InputEventKey and event.is_pressed() and (event as InputEventKey).keycode == KEY_M and not (event as InputEventKey).ctrl_pressed and ctx.song:
		add_phrase_at_playhead()
		accept_event()
	elif event is InputEventKey and event.is_pressed() and ctx.selected_clip:
		var key := event as InputEventKey
		if key.keycode == KEY_DELETE or key.keycode == KEY_BACKSPACE:
			ctx.remove_clip(ctx.selected_clip)
			accept_event()
		elif key.keycode == KEY_D and (key.ctrl_pressed or key.meta_pressed):
			ctx.duplicate_clip(ctx.selected_clip)
			accept_event()
		elif key.keycode == KEY_ESCAPE:
			ctx.select_clip(null)
			accept_event()


func _press(pos: Vector2) -> void:
	if pos.x < HEADER_W:
		var li := _lane_index_at(pos.y)
		if li >= 0:
			ctx.select(_lanes()[li].fx) # a lane's name picks that fixture
		return
	if pos.y < RULER_H and ctx.song and not ctx.following_dj() and _press_marker(pos):
		return
	var hit := _clip_at(pos)
	if hit.is_empty():
		ctx.select_clip(null)
		_scrubbing = true
		_manual_scroll = false
		_scrub(pos.x)
		return
	var clip: ShowClip = hit.clip
	var rect: Rect2 = hit.rect
	ctx.select_clip(clip)
	_drag_clip = clip
	_drag_before = clip.to_data()
	_drag_from_x = pos.x
	_drag_start = clip.start
	_drag_end = clip.end()
	if pos.x <= rect.position.x + EDGE_PX:
		_drag = Drag.LEFT
	elif pos.x >= rect.end.x - EDGE_PX:
		_drag = Drag.RIGHT
	else:
		_drag = Drag.MOVE


## Grab a phrase flag or the first-beat flag on the ruler, if one is under `pos`.
func _press_marker(pos: Vector2) -> bool:
	var song := ctx.song
	var fx := _x(ctx.first_beat_beats())
	if pos.y >= PHRASE_H and absf(pos.x - fx) <= FLAG_GRAB:
		_drag = Drag.FIRST_BEAT
		_drag_marks = song.marks_state()
		return true
	var i := _phrase_at(pos)
	if i >= 0:
		_drag = Drag.PHRASE
		_drag_phrase = song.phrases[i]
		_drag_marks = song.marks_state()
		return true
	return false


## Index of the phrase flag under `pos` (ruler's top strip), or -1.
func _phrase_at(pos: Vector2) -> int:
	if pos.y >= RULER_H or pos.x < HEADER_W:
		return -1
	var best := -1
	var best_d := FLAG_GRAB + 1.0
	for i in ctx.song.phrases.size():
		var d := absf(pos.x - _x(ctx.seconds_to_beats(ctx.song.phrases[i].time)))
		if d < best_d and (pos.y < PHRASE_H or d <= FLAG_GRAB * 0.5):
			best = i
			best_d = d
	return best


func _drag_marker(pos: Vector2) -> void:
	var song := ctx.song
	var b := _beat_at(pos.x)
	if _drag == Drag.FIRST_BEAT:
		song.beat_offset = clampf(ctx.beats_to_seconds(b), 0.0, song.duration)
	else:
		var fb := ctx.first_beat_beats()
		if not Input.is_key_pressed(KEY_ALT):
			b = fb + roundf((b - fb) / 4.0) * 4.0 # phrases start on a bar
		_drag_phrase.time = clampf(ctx.beats_to_seconds(b), 0.0, song.duration)
		song.sort_phrases()
	ctx.marks_changed.emit()


func _open_marks_menu(pos: Vector2) -> void:
	_menu_phrase = _phrase_at(pos)
	var b := _beat_at(pos.x)
	var fb := ctx.first_beat_beats()
	b = fb + roundf((b - fb) / 4.0) * 4.0
	_menu_seconds_raw = maxf(0.0, ctx.beats_to_seconds(_beat_at(pos.x)))
	_menu_seconds = maxf(0.0, ctx.beats_to_seconds(b))
	_marks_menu.clear()
	if _menu_phrase >= 0:
		_marks_menu.add_item('Rename "%s"…' % ctx.song.phrases[_menu_phrase].name, MarksItem.RENAME)
		_marks_menu.add_submenu_node_item("Change to", _kind_sub)
		_marks_menu.add_item("Delete phrase", MarksItem.DELETE_PHRASE)
		_marks_menu.add_separator()
	_marks_menu.add_submenu_node_item("Add phrase here", _add_sub)
	_marks_menu.add_separator()
	_marks_menu.add_item("First beat at playhead", MarksItem.FIRST_HERE)
	_marks_menu.add_item("First beat here", MarksItem.FIRST_AT)
	_marks_menu.add_item("Nudge grid earlier (10 ms)", MarksItem.NUDGE_BACK)
	_marks_menu.add_item("Nudge grid later (10 ms)", MarksItem.NUDGE_FWD)
	_marks_menu.add_item("Reset grid to start", MarksItem.RESET_GRID)
	_marks_menu.position = Vector2i(get_screen_position() + pos)
	_marks_menu.popup()


func _on_marks_menu(id: int) -> void:
	if id >= KIND_BASE:
		var phrase_name := PhraseKinds.KINDS[id - KIND_BASE]
		if _menu_phrase >= 0:
			ctx.rename_phrase(_menu_phrase, phrase_name)
	elif id >= ADD_BASE:
		ctx.add_phrase(_menu_seconds, PhraseKinds.KINDS[id - ADD_BASE])
	else:
		match id:
			MarksItem.FIRST_HERE:
				ctx.set_first_beat_here()
			MarksItem.FIRST_AT:
				ctx.set_beat_offset(_menu_seconds_raw)
			MarksItem.NUDGE_BACK:
				ctx.nudge_beat_offset(-0.01)
			MarksItem.NUDGE_FWD:
				ctx.nudge_beat_offset(0.01)
			MarksItem.RESET_GRID:
				ctx.set_beat_offset(0.0)
			MarksItem.RENAME:
				_rename_edit.text = ctx.song.phrases[_menu_phrase].name
				_rename_dialog.popup_centered()
				_rename_edit.grab_focus()
				_rename_edit.select_all()
			MarksItem.DELETE_PHRASE:
				ctx.remove_phrase(_menu_phrase)


## M: drop a phrase at the playhead, named after the usual running order of a
## dance track (intro, build, drop...).
func add_phrase_at_playhead() -> void:
	var order := ["Intro", "Build", "Drop", "Breakdown", "Build", "Drop", "Outro"]
	var n := ctx.song.phrases.size()
	ctx.add_phrase(ctx.beats_to_seconds(ctx.position_beats), order[mini(n, order.size() - 1)])


func _drag_to(pos: Vector2) -> void:
	if _drag == Drag.PHRASE or _drag == Drag.FIRST_BEAT:
		_drag_marker(pos)
		return
	var clip := _drag_clip
	var delta := (pos.x - _drag_from_x) / px_per_beat
	var min_len := snap_beats if snap_beats > 0.0 else 0.25
	match _drag:
		Drag.MOVE:
			clip.start = maxf(0.0, _snap(_drag_start + delta))
			# A clip on one fixture can be dragged onto another fixture's lane.
			if clip.targets.size() == 1:
				var li := _lane_index_at(pos.y)
				var lanes := _lanes()
				if li >= 0 and lanes[li].path != clip.targets[0] and EffectTemplates.supports(clip.template, lanes[li].fx):
					clip.targets = PackedStringArray([lanes[li].path])
		Drag.LEFT:
			var s := clampf(_snap(_drag_start + delta), 0.0, _drag_end - min_len)
			clip.start = s
			clip.length = _drag_end - s
		Drag.RIGHT:
			clip.length = maxf(min_len, _snap(_drag_end + delta) - clip.start)
	clip.fade_in = minf(clip.fade_in, clip.length)
	clip.fade_out = minf(clip.fade_out, clip.length)


func _release() -> void:
	_scrubbing = false
	if _drag == Drag.NONE:
		return
	if _drag == Drag.PHRASE or _drag == Drag.FIRST_BEAT:
		ctx.commit_marks("Align beat grid" if _drag == Drag.FIRST_BEAT else "Move phrase", _drag_marks)
		_drag = Drag.NONE
		return
	var action := "Move effect" if _drag == Drag.MOVE else "Stretch effect"
	_drag = Drag.NONE
	ctx.record_clip_change(_drag_clip, _drag_before, action)
	_drag_clip = null


func _update_cursor(pos: Vector2) -> void:
	var hit := _clip_at(pos)
	if hit.is_empty():
		mouse_default_cursor_shape = CURSOR_ARROW
		return
	var rect: Rect2 = hit.rect
	if pos.x <= rect.position.x + EDGE_PX or pos.x >= rect.end.x - EDGE_PX:
		mouse_default_cursor_shape = CURSOR_HSIZE
	else:
		mouse_default_cursor_shape = CURSOR_DRAG


func _on_menu(id: int) -> void:
	var clip := _menu_clip
	if clip == null:
		return
	match id:
		MenuItem.DUPLICATE:
			ctx.duplicate_clip(clip)
		MenuItem.SAVE_PRESET:
			ctx.save_clip_as_preset(clip)
		MenuItem.DELETE:
			ctx.remove_clip(clip)
	_menu_clip = null


# ------------------------------------------------------------- drag & drop

## A preset dragged from the Effects shelf: {"effect_preset": EffectPreset}.
func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and (data as Dictionary).has("effect_preset")):
		return false
	var preset: EffectPreset = (data as Dictionary).effect_preset
	_drop_preset = preset
	var li := _lane_index_at(at.y) if at.x > HEADER_W else -2
	if li == -1 and ctx.fixtures_supporting(preset.template).is_empty():
		li = -2
	elif li >= 0 and not EffectTemplates.supports(preset.template, _lanes()[li].fx):
		li = -2 # a crowd sweep on a par: not allowed
	_drop_lane = li
	return li != -2


func _drop_data(at: Vector2, data: Variant) -> void:
	var preset: EffectPreset = (data as Dictionary).effect_preset
	var li := _lane_index_at(at.y)
	var targets: Array[DMXFixture] = []
	if li == -1:
		targets = ctx.fixtures_supporting(preset.template)
	elif li >= 0:
		targets.append(_lanes()[li].fx)
	_drop_lane = -2
	_drop_preset = null
	if targets.is_empty():
		return
	ctx.add_clip(preset, maxf(0.0, _snap(_beat_at(at.x))), targets)
	grab_focus()


func _scrub(x: float) -> void:
	ctx.seek(_beat_at(x))
