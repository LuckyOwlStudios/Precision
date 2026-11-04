class_name SongLibraryPanel
extends MarginContainer
## Songs and the light show linked to each one. Drag audio files anywhere onto
## the window (or press +) to import. Click a song to put it on the timeline;
## right-click to rename its show or remove it.
## The library itself is SongLibrary (music/); this panel only shows it.

var ctx: StudioContext

var _search := LineEdit.new()
var _rows := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _empty: Control
var _status := Label.new()
var _count := Label.new()
var _dialog: FileDialog
var _menu := PopupMenu.new()
var _menu_song: Song
var _rename: ConfirmationDialog
var _rename_edit := LineEdit.new()


class SongRow:
	extends PanelContainer
	signal activated(song: Song)
	signal context_requested(song: Song, at: Vector2)
	var song: Song
	var current := false:
		set(v):
			current = v
			_restyle()
	var _hover := false
	var _pair: VBoxContainer
	var _show := Label.new()

	func _init(s: Song) -> void:
		song = s
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		add_child(row)
		_pair = UIKit.title_pair("", "")
		_pair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_pair.add_child(_show)
		_show.theme_type_variation = &"Caption"
		_show.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(_pair)
		mouse_entered.connect(_set_hover.bind(true))
		mouse_exited.connect(_set_hover.bind(false))
		refresh()

	func refresh() -> void:
		(_pair.get_meta("title") as Label).text = song.display_title()
		(_pair.get_meta("detail") as Label).text = song.detail_line()
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


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.library.songs_changed.connect(_rebuild)
	ctx.library.song_updated.connect(_on_song_updated)
	ctx.library.import_finished.connect(_on_import_finished)
	ctx.song_changed.connect(func(_s: Song) -> void: _mark_current())
	_rebuild()


func _ready() -> void:
	add_theme_constant_override("margin_left", UIPalette.COLUMN_PAD)
	add_theme_constant_override("margin_right", UIPalette.COLUMN_PAD)
	add_theme_constant_override("margin_top", 16)
	add_theme_constant_override("margin_bottom", 8)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	var head := UIKit.section("Songs", "+", "Import songs (or drag files onto the window)")
	(head.get_meta("action") as Button).pressed.connect(_open_dialog)
	col.add_child(head)

	_search.placeholder_text = "Search songs"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t: String) -> void: _rebuild())
	col.add_child(_search)

	_count.theme_type_variation = &"Caption"
	col.add_child(_count)

	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 2)
	_scroll.add_child(_rows)
	col.add_child(_scroll)

	_empty = UIKit.empty_state("No songs yet", "Drag MP3, WAV or OGG files onto the window, or press +. Each song gets its own light show that plays with it.")
	col.add_child(_empty)

	_status.theme_type_variation = &"Caption"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.visible = false
	col.add_child(_status)

	var hint := Label.new()
	hint.text = "Drop audio files anywhere on the window to import."
	hint.theme_type_variation = &"Caption"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	_menu.add_item("Rename show…", 0)
	_menu.add_separator()
	_menu.add_item("Remove from library", 1)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)

	_rename = ConfirmationDialog.new()
	_rename.title = "Rename show"
	_rename.add_child(_rename_edit)
	_rename.register_text_enter(_rename_edit)
	_rename.confirmed.connect(_on_rename_confirmed)
	add_child(_rename)


func _open_dialog() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		_dialog.title = "Import songs"
		_dialog.filters = PackedStringArray(["*.mp3, *.wav, *.ogg ; Audio files"])
		_dialog.files_selected.connect(func(paths: PackedStringArray) -> void: ctx.import_songs(paths))
		add_child(_dialog)
	_dialog.popup_centered_ratio(0.6)


func _rebuild() -> void:
	if ctx == null:
		return
	for c in _rows.get_children():
		c.queue_free()
	var list := ctx.library.search(_search.text)
	for s in list:
		var row := SongRow.new(s)
		row.activated.connect(func(song: Song) -> void: ctx.load_song(song))
		row.context_requested.connect(_on_context)
		_rows.add_child(row)
	var total := ctx.library.songs.size()
	_empty.visible = total == 0
	_scroll.visible = total > 0
	_count.visible = total > 0
	_count.text = "%d song%s" % [total, "" if total == 1 else "s"] if list.size() == total else "%d of %d songs" % [list.size(), total]
	_mark_current()


func _mark_current() -> void:
	for row in _rows.get_children():
		if row is SongRow and not row.is_queued_for_deletion():
			(row as SongRow).current = (row as SongRow).song == ctx.song


func _on_song_updated(s: Song) -> void:
	for row in _rows.get_children():
		if row is SongRow and (row as SongRow).song == s:
			(row as SongRow).refresh()


func _on_import_finished(added: Array[Song], failed: Array[Dictionary]) -> void:
	var lines: PackedStringArray = []
	if not added.is_empty():
		lines.append("Imported %d song%s." % [added.size(), "" if added.size() == 1 else "s"])
	for f in failed.slice(0, 4):
		lines.append("%s: %s" % [str(f.path).get_file(), f.reason])
	if failed.size() > 4:
		lines.append("…and %d more not imported." % (failed.size() - 4))
	_status.text = "\n".join(lines)
	_status.add_theme_color_override("font_color", UIPalette.ACCENT if not failed.is_empty() else UIPalette.TEXT_DIM)
	_status.visible = not lines.is_empty()


func _on_context(s: Song, at: Vector2) -> void:
	_menu_song = s
	var pos := Vector2i(at)
	if not get_viewport().gui_embed_subwindows:
		pos += get_window().position # popups are their own OS windows
	_menu.popup(Rect2i(pos, Vector2i.ZERO))


func _on_menu(id: int) -> void:
	if _menu_song == null:
		return
	match id:
		0:
			_rename_edit.text = _menu_song.show_name
			_rename.popup_centered(Vector2i(360, 0))
			_rename_edit.grab_focus()
			_rename_edit.select_all()
		1:
			ctx.library.remove(_menu_song)
			_menu_song = null


func _on_rename_confirmed() -> void:
	var name := _rename_edit.text.strip_edges()
	if _menu_song and not name.is_empty():
		_menu_song.show_name = name
		ctx.library.update(_menu_song)
		if ctx.song == _menu_song:
			ctx.show_name = name
			ctx.transport_changed.emit()
