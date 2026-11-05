class_name SongLibraryPanel
extends MarginContainer
## Songs and the light show linked to each one. Drag audio files anywhere onto
## the window (or press +) to import. Click a song to put it on the timeline;
## right-click to rename its show or remove it.
## The library itself is SongLibrary (music/); this panel only shows it.

const SONG_ROW := preload("res://ui/panels/song_row.tscn")

var ctx: StudioContext

var _menu_song: Song

@onready var _search: LineEdit = %Search
@onready var _rows: VBoxContainer = %Rows
@onready var _scroll: ScrollContainer = %Scroll
@onready var _empty: Control = %Empty
@onready var _status: Label = %Status
@onready var _count: Label = %Count
@onready var _dialog: FileDialog = %ImportDialog
@onready var _menu: PopupMenu = %SongMenu
@onready var _rename: ConfirmationDialog = %RenameDialog
@onready var _rename_edit: LineEdit = %RenameEdit


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.library.songs_changed.connect(_rebuild)
	ctx.library.song_updated.connect(_on_song_updated)
	ctx.library.import_finished.connect(_on_import_finished)
	ctx.song_changed.connect(func(_s: Song) -> void: _mark_current())
	_rebuild()


func _ready() -> void:
	%ImportButton.pressed.connect(_open_dialog)
	_search.text_changed.connect(func(_t: String) -> void: _rebuild())
	_menu.id_pressed.connect(_on_menu)
	_rename.register_text_enter(_rename_edit)
	_rename.confirmed.connect(_on_rename_confirmed)
	_dialog.files_selected.connect(func(paths: PackedStringArray) -> void: ctx.import_songs(paths))


func _open_dialog() -> void:
	_dialog.popup_centered_ratio(0.6)


func _rebuild() -> void:
	if ctx == null:
		return
	for c in _rows.get_children():
		c.queue_free()
	var list := ctx.library.search(_search.text)
	for s in list:
		var row: SongRow = SONG_ROW.instantiate()
		row.song = s
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
