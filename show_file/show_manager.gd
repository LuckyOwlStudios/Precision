class_name ShowManager
extends Node
## The current show file: New, Open, Save, Save As, "reopen the last show on
## launch" and the unsaved-changes flag. Lives in studio_context.tscn as
## ctx.shows.
##
## A show is the rig, the truss set, the patch, cues and stage settings (not
## the computer-wide song library, effect presets or Settings). Each feature
## that belongs in the file registers a *section* and keeps its own data
## format. To save something new, in the feature's setup:
##
##   ctx.shows.register_section(&"groups",
##       func() -> Variant: return _to_data(),        # called on Save
##       func(data: Variant) -> void: _from_data(data), # called on Open
##       func() -> void: _clear(),                    # New / file without it
##       30)                                          # load order (lower first)
##
## Values go through ShowCodec so Color, Vector3 and friends survive the JSON.
## Sections load in `order`, after every reset. Existing orders: structure 10,
## rig 20, cues 30, stage 40. Use something after 20 if you refer to fixtures.

## Path, name or unsaved-changes state changed (the window title follows).
signal state_changed
## A show was opened or started fresh; panels rebuild what they cache.
signal show_loaded
## Opening failed (the message is ready to show to the person).
signal open_failed(message: String)
## Saving failed.
signal save_failed(message: String)

const SESSION_FILE := "user://session.cfg"
const MAX_RECENT := 8
const UNTITLED := "Untitled show"

var ctx: StudioContext
## Where the show is saved, empty for a show that has never been saved.
var path := "":
	set(v):
		path = v
		state_changed.emit()

var _sections: Array[Dictionary] = [] ## {id, save, load, reset, order}
## Sections found in a file that nothing here knows (made by a newer build or a
## feature that isn't installed). Written back untouched.
var _foreign: Dictionary = {}
var _saved_version := 0
var _forced_dirty := false
var _recent: PackedStringArray = []
## The show to come back to on the next launch: the one open when the app closed.
## Empty after New, so a launch doesn't bring back something you walked away from.
var _last := ""


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.history.version_changed.connect(state_changed.emit)
	_load_session()
	_saved_version = ctx.history.get_version()


func register_section(id: StringName, save: Callable, load_data: Callable, reset: Callable, order := 50) -> void:
	for s in _sections:
		if s.id == id:
			push_warning("ShowManager: section '%s' registered twice" % id)
			return
	_sections.append({id = id, save = save, load = load_data, reset = reset, order = order})
	_sections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.order < b.order)


# ---------------------------------------------------------------- state

func has_path() -> bool:
	return not path.is_empty()


## "Friday set" for friday_set.precision, else "Untitled show".
func title() -> String:
	return path.get_file().get_basename() if has_path() else UNTITLED


func is_dirty() -> bool:
	return _forced_dirty or ctx.history.get_version() != _saved_version


## For a change that isn't an undo step.
func mark_dirty() -> void:
	_forced_dirty = true
	state_changed.emit()


func recent() -> PackedStringArray:
	return _recent


# ---------------------------------------------------------------- new / open / save

## An empty stage with the default truss and no fixtures. Does not ask about
## unsaved changes: the UI does that first.
func new_show() -> void:
	_begin_load()
	for s in _sections:
		(s.reset as Callable).call()
	_foreign.clear()
	path = ""
	_last = ""
	_save_session()
	_finish_load()


## Load `file`. On failure nothing changes and open_failed fires.
func open(file: String) -> bool:
	var result := ShowFile.read(file)
	if not result.error.is_empty():
		open_failed.emit(result.error)
		return false
	_begin_load()
	var known := {}
	for s in _sections:
		known[str(s.id)] = true
		(s.reset as Callable).call()
		if result.sections.has(str(s.id)):
			(s.load as Callable).call(result.sections[str(s.id)])
	_foreign.clear()
	for id: String in result.sections:
		if not known.has(id):
			_foreign[id] = result.sections[id]
	path = file
	_remember(file)
	_finish_load()
	return true


## Save to the current path. Returns false if the show has no path yet (the UI
## then asks for one) or the write failed.
func save() -> bool:
	return has_path() and _write(path)


func save_as(file: String) -> bool:
	file = ShowFile.with_extension(file)
	if not _write(file):
		return false
	path = file
	_remember(file)
	return true


## Open the show that was open when the app was last closed, if it is still there.
func reopen_last() -> bool:
	return not _last.is_empty() and FileAccess.file_exists(_last) and open(_last)


func _write(file: String) -> bool:
	var sections := _foreign.duplicate(true)
	for s in _sections:
		sections[str(s.id)] = ShowCodec.encode((s.save as Callable).call())
	var err := ShowFile.write(file, sections)
	if err != OK:
		save_failed.emit("Couldn't save the show to\n%s\n(%s)" % [file, error_string(err)])
		return false
	_saved_version = ctx.history.get_version()
	_forced_dirty = false
	state_changed.emit()
	return true


func _begin_load() -> void:
	# The old show's undo steps hold nodes and numbers that don't exist any more.
	ctx.begin_show_load()


func _finish_load() -> void:
	ctx.history.clear_history()
	_saved_version = ctx.history.get_version()
	_forced_dirty = false
	ctx.end_show_load()
	show_loaded.emit()
	state_changed.emit()


# ---------------------------------------------------------------- recent files and last show

func _remember(file: String) -> void:
	var list := PackedStringArray([file])
	for f in _recent:
		if f != file and list.size() < MAX_RECENT:
			list.append(f)
	_recent = list
	_last = file
	_save_session()


func _save_session() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("shows", "recent", _recent)
	cfg.set_value("shows", "last", _last)
	cfg.save(SESSION_FILE)


func _load_session() -> void:
	var cfg := ConfigFile.new()
	_recent.clear()
	if cfg.load(SESSION_FILE) == OK:
		for f: String in cfg.get_value("shows", "recent", PackedStringArray()):
			_recent.append(f)
		_last = str(cfg.get_value("shows", "last", ""))
