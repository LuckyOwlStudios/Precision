class_name TimelinePanel
extends VBoxContainer
## Beat-grid timeline along the bottom: a music lane, one lane per fixture,
## bars and beats on the ruler, and a red playhead.
## First pass: it shows the grid and transport; clips and keyframes come next
## (they will map onto an AnimationPlayer, see the addon README).

var ctx: StudioContext
var _canvas: TimelineCanvas
var _zoom := HSlider.new()
var _pos_label := Label.new()


class TimelineCanvas:
	extends Control
	const HEADER_W := 168.0
	const RULER_H := 26.0
	const MUSIC_H := 52.0
	const LANE_H := 30.0
	var ctx: StudioContext
	var px_per_beat := 22.0
	var scroll_beats := 0.0
	var _scrubbing := false

	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP

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
		var lanes: Array[String] = [ctx.song_title if ctx.song else "Music"]
		for fx in ctx.fixtures():
			lanes.append(StudioContext.display_name(fx))
		var y := RULER_H
		for i in lanes.size():
			var lh := MUSIC_H if i == 0 else LANE_H
			if i % 2 == 1:
				draw_rect(Rect2(HEADER_W, y, w - HEADER_W, lh), Color(1, 1, 1, 0.012))
			draw_line(Vector2(0, y + lh), Vector2(w, y + lh), UIPalette.HAIRLINE)
			y += lh

		# Grid: beats faint, bars stronger, every 4th bar labelled.
		var first := floori(scroll_beats)
		var last := ceili(scroll_beats + (w - HEADER_W) / px_per_beat)
		for b in range(first, last + 1):
			var x := _x(b)
			if x < HEADER_W:
				continue
			var is_bar := b % 4 == 0
			var col := Color(1, 1, 1, 0.07) if is_bar else Color(1, 1, 1, 0.025)
			if (not is_bar) and px_per_beat < 8.0:
				continue
			draw_line(Vector2(x, RULER_H), Vector2(x, h), col)
			if is_bar:
				draw_line(Vector2(x, RULER_H - 8), Vector2(x, RULER_H), UIPalette.TEXT_FAINT)
				var bar_no := b / 4 + 1
				if (bar_no - 1) % (4 if px_per_beat < 14 else 1) == 0:
					draw_string(mono, Vector2(x + 4, RULER_H - 9), str(bar_no), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPalette.TEXT_DIM)
		draw_line(Vector2(HEADER_W, RULER_H), Vector2(w, RULER_H), UIPalette.HAIRLINE)

		# Music lane: the song's waveform on the beat grid, or a drop hint.
		var music_rect := Rect2(HEADER_W + 8, RULER_H + 8, w - HEADER_W - 16, MUSIC_H - 16)
		if ctx.song == null:
			draw_style_box(_dashed_box(), music_rect)
			draw_string(font, music_rect.position + Vector2(12, music_rect.size.y * 0.5 + 5), "Drop a song onto the window to build its show on the beat grid", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIPalette.TEXT_FAINT)
		else:
			_draw_waveform(Rect2(HEADER_W, RULER_H + 4, w - HEADER_W, MUSIC_H - 8), font)

		# Fixture lanes: a thin live colour strip so you can see each light at a glance.
		y = RULER_H + MUSIC_H
		for fx in ctx.fixtures():
			var c := fx.color * (0.0 if ctx.blackout else fx.dimmer)
			c.a = 1.0
			draw_rect(Rect2(HEADER_W - 6, y + 8, 3, LANE_H - 16), c)
			y += LANE_H

		# Lane headers (drawn last so the grid scrolls under them).
		draw_rect(Rect2(0, 0, HEADER_W, h), UIPalette.SIDE_BG)
		draw_line(Vector2(HEADER_W, 0), Vector2(HEADER_W, h), UIPalette.HAIRLINE)
		y = RULER_H
		for i in lanes.size():
			var lh := MUSIC_H if i == 0 else LANE_H
			var f := bold if i == 0 else font
			draw_string(f, Vector2(UIPalette.COLUMN_PAD, y + lh * 0.5 + 5), lanes[i], HORIZONTAL_ALIGNMENT_LEFT, HEADER_W - 28, 12, UIPalette.TEXT if i == 0 else UIPalette.TEXT_DIM)
			if i == 0:
				draw_string(font, Vector2(UIPalette.COLUMN_PAD, y + lh * 0.5 + 21), "%d BPM · 4/4" % roundi(ctx.bpm), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPalette.BEAT)
			draw_line(Vector2(0, y + lh), Vector2(HEADER_W, y + lh), UIPalette.HAIRLINE)
			y += lh
		draw_string(mono, Vector2(UIPalette.COLUMN_PAD, RULER_H - 9), "BAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UIPalette.TEXT_FAINT)

		# Playhead
		var px := _x(ctx.position_beats)
		if px >= HEADER_W:
			draw_line(Vector2(px, 0), Vector2(px, h), UIPalette.LIVE, 1.5)
			draw_colored_polygon(PackedVector2Array([Vector2(px - 6, 0), Vector2(px + 6, 0), Vector2(px, 8)]), UIPalette.LIVE)

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

	## Keep the playhead on screen while playing.
	func _follow_playhead() -> void:
		if not ctx.playing:
			return
		var visible_beats := (size.x - HEADER_W) / px_per_beat
		if ctx.position_beats > scroll_beats + visible_beats * 0.9 or ctx.position_beats < scroll_beats:
			scroll_beats = maxf(0.0, ctx.position_beats - visible_beats * 0.1)

	func _dashed_box() -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(UIPalette.BEAT, 0.03)
		s.border_color = Color(UIPalette.BEAT, 0.25)
		s.set_border_width_all(1)
		s.set_corner_radius_all(4)
		return s

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_scrubbing = mb.pressed and mb.position.x > HEADER_W
				if _scrubbing:
					_scrub(mb.position.x)
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				if mb.ctrl_pressed:
					px_per_beat = minf(px_per_beat * 1.15, 120.0)
				else:
					scroll_beats = maxf(0.0, scroll_beats - 4.0)
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				if mb.ctrl_pressed:
					px_per_beat = maxf(px_per_beat / 1.15, 3.0)
				else:
					scroll_beats = minf(ctx.length_beats, scroll_beats + 4.0)
			accept_event()
		elif event is InputEventMouseMotion and _scrubbing:
			_scrub((event as InputEventMouseMotion).position.x)

	func _scrub(x: float) -> void:
		ctx.seek(scroll_beats + (x - HEADER_W) / px_per_beat)


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	_canvas.ctx = ctx
	ctx.transport_changed.connect(_update_label)
	_update_label()


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	var head := PanelContainer.new()
	head.theme_type_variation = &"HeaderBar"
	head.custom_minimum_size.y = 40
	add_child(head)
	var row := HBoxContainer.new()
	head.add_child(row)
	var title := Label.new()
	title.text = "Timeline"
	title.uppercase = true
	title.theme_type_variation = &"SectionTitle"
	row.add_child(title)
	_pos_label.theme_type_variation = &"MonoLabel"
	_pos_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pos_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_pos_label)
	var snap := OptionButton.new()
	for s: String in ["Snap: 1 beat", "Snap: 1/2", "Snap: 1/4", "Snap: bar", "Snap: off"]:
		snap.add_item(s)
	snap.tooltip_text = "Grid snap for clips (clips coming soon)"
	row.add_child(snap)
	var zl := Label.new()
	zl.text = "Zoom"
	zl.theme_type_variation = &"Caption"
	row.add_child(zl)
	_zoom.min_value = 3
	_zoom.max_value = 120
	_zoom.value = 22
	_zoom.custom_minimum_size = Vector2(110, 20)
	_zoom.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_zoom.value_changed.connect(func(v: float) -> void: _canvas.px_per_beat = v)
	row.add_child(_zoom)

	_canvas = TimelineCanvas.new()
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.custom_minimum_size.y = 120
	add_child(_canvas)


func _update_label() -> void:
	var b := ctx.position_beats
	var secs := b * 60.0 / ctx.bpm
	_pos_label.text = "BAR %d.%d    %02d:%04.1f" % [int(b / 4.0) + 1, int(b) % 4 + 1, int(secs / 60.0), fmod(secs, 60.0)]
