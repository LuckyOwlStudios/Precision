class_name ShowMenu
extends Node
## The File menu and its dialogs: New, Open, Open recent, Save, Save as, and the
## "Save changes first?" question. The shortcuts (Ctrl+N / O / S / Shift+S) are
## handled by the main window, which calls the same functions.

@onready var _open_dialog: FileDialog = %OpenDialog
@onready var _save_dialog: FileDialog = %SaveDialog
@onready var _unsaved: ConfirmationDialog = %UnsavedDialog
@onready var _error: AcceptDialog = %ErrorDialog

var ctx: StudioContext
var shows: ShowManager
var _menu: PopupMenu
var _recent_menu: PopupMenu
var _name_label: Label
## What to do once the unsaved-changes question is settled (open, new, quit...).
var _pending := Callable()
## What to do once a Save as that was asked for by that question has written the file.
var _after_save := Callable()

enum Item { NEW, OPEN, SAVE, SAVE_AS }


func setup(p_ctx: StudioContext, button: MenuButton, name_label: Label) -> void:
	ctx = p_ctx
	shows = ctx.shows
	_name_label = name_label
	_menu = button.get_popup()
	_menu.add_item(tr("New show") + "      Ctrl+N", Item.NEW)
	_menu.add_item(tr("Open…") + "      Ctrl+O", Item.OPEN)
	_recent_menu = PopupMenu.new()
	_recent_menu.name = "Recent"
	_recent_menu.id_pressed.connect(_on_recent_pressed)
	_menu.add_child(_recent_menu)
	_menu.add_submenu_node_item(tr("Open recent"), _recent_menu)
	_menu.add_separator()
	_menu.add_item(tr("Save") + "      Ctrl+S", Item.SAVE)
	_menu.add_item(tr("Save as…") + "      Ctrl+Shift+S", Item.SAVE_AS)
	_menu.id_pressed.connect(_on_item_pressed)
	_menu.about_to_popup.connect(_refresh_recent)

	var a := ctx.actions
	a.register(&"file.new", "New show", new_show, {category = "File", shortcut = "Ctrl+N", keywords = "empty clear start over"})
	a.register(&"file.open", "Open show…", open_dialog, {category = "File", shortcut = "Ctrl+O", keywords = "load"})
	a.register(&"file.save", "Save show", save, {category = "File", shortcut = "Ctrl+S", keywords = "write"})
	a.register(&"file.save_as", "Save show as…", save_as, {category = "File", shortcut = "Ctrl+Shift+S", keywords = "write copy"})

	_open_dialog.file_selected.connect(func(f: String) -> void: shows.open(f))
	_save_dialog.file_selected.connect(_on_save_path_chosen)
	_save_dialog.canceled.connect(func() -> void: _after_save = Callable())
	_unsaved.confirmed.connect(_on_unsaved_save)
	_unsaved.add_button(tr("Don't save"), true, "discard")
	_unsaved.custom_action.connect(_on_unsaved_custom)
	_unsaved.canceled.connect(func() -> void: _pending = Callable())
	shows.open_failed.connect(_show_error.bind(tr("Couldn't open the show")))
	shows.save_failed.connect(_show_error.bind(tr("Couldn't save the show")))
	shows.state_changed.connect(_update_title)
	_update_title()


# ---------------------------------------------------------------- what the menu does

func new_show() -> void:
	_guard(shows.new_show)


func open_dialog() -> void:
	_guard(func() -> void:
		_aim(_open_dialog)
		_open_dialog.popup_centered_ratio(0.6))


func open_path(file: String) -> void:
	_guard(shows.open.bind(file))


func save() -> void:
	if shows.has_path():
		shows.save()
	else:
		save_as()


func save_as() -> void:
	_aim(_save_dialog)
	_save_dialog.current_file = shows.title() + "." + ShowFile.EXTENSION
	_save_dialog.popup_centered_ratio(0.6)


## The window's close button: leave only once unsaved changes are dealt with.
func request_quit() -> void:
	_guard(func() -> void: get_tree().quit())


# ---------------------------------------------------------------- internals

## Run `then` now, or after the person has decided what to do about unsaved changes.
func _guard(then: Callable) -> void:
	if not shows.is_dirty():
		then.call()
		return
	_pending = then
	_unsaved.dialog_text = tr("Save changes to \"%s\" first?") % shows.title()
	_unsaved.popup_centered()


func _on_unsaved_save() -> void:
	var then := _pending
	_pending = Callable()
	if shows.has_path():
		if shows.save():
			then.call()
		return
	_after_save = then # no file yet: ask where, then carry on
	save_as()


func _on_unsaved_custom(action: StringName) -> void:
	if action != &"discard":
		return
	_unsaved.hide()
	var then := _pending
	_pending = Callable()
	then.call()


func _on_save_path_chosen(file: String) -> void:
	var then := _after_save
	_after_save = Callable()
	if shows.save_as(file) and then.is_valid():
		then.call()


func _on_item_pressed(id: int) -> void:
	match id:
		Item.NEW: new_show()
		Item.OPEN: open_dialog()
		Item.SAVE: save()
		Item.SAVE_AS: save_as()


func _refresh_recent() -> void:
	_recent_menu.clear()
	var i := 0
	for f in shows.recent():
		if f != shows.path and FileAccess.file_exists(f):
			_recent_menu.add_item(f.get_file().get_basename(), i)
			_recent_menu.set_item_metadata(_recent_menu.item_count - 1, f)
			_recent_menu.set_item_tooltip(_recent_menu.item_count - 1, f)
		i += 1
	if _recent_menu.item_count == 0:
		_recent_menu.add_item(tr("(none yet)"))
		_recent_menu.set_item_disabled(0, true)


func _on_recent_pressed(id: int) -> void:
	var index := _recent_menu.get_item_index(id)
	var file := String(_recent_menu.get_item_metadata(index))
	if not file.is_empty():
		open_path(file)


## Start the dialog in the folder of the current show (or Documents).
func _aim(dialog: FileDialog) -> void:
	dialog.current_dir = shows.path.get_base_dir() if shows.has_path() else OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)


func _show_error(message: String, title: String) -> void:
	_error.title = title
	_error.dialog_text = message
	_error.popup_centered()


## The window title and the name beside the File button: "Friday set •" while
## there are changes that aren't saved.
func _update_title() -> void:
	var text := shows.title() + (" •" if shows.is_dirty() else "")
	_name_label.text = text
	_name_label.tooltip_text = shows.path if shows.has_path() else tr("Not saved yet")
	var window := get_window()
	if window:
		window.title = "%s — Precision" % text
