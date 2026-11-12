class_name LookLibrary
extends Node
## The Looks shelf. Looks belong to a show (every rig has different fixtures),
## so StudioContext turns `persist` off and the show file stores them (see
## ShowManager, section "looks"). With `persist` on, each look is instead saved
## as its own file in the library folder right after every change.
## No UI in here: panels listen to `looks_changed`.

signal looks_changed

## Override for tests.
@export var root_dir: String = "user://library"

## Save looks to the library folder on every change (and read them from there).
@export var persist := true

var looks: Array[Look] = []

var _loaded := false


func _ready() -> void:
	_ensure_loaded()


func looks_dir() -> String:
	return root_dir.path_join("looks")


func _ensure_loaded() -> void:
	if not _loaded:
		load_looks()


func load_looks() -> void:
	_loaded = true
	looks.clear()
	var dir := DirAccess.open(looks_dir()) if persist else null
	if dir:
		for file in dir.get_files():
			if file.get_extension() == "tres":
				var look := ResourceLoader.load(looks_dir().path_join(file), "", ResourceLoader.CACHE_MODE_IGNORE) as Look
				if look:
					looks.append(look)
	looks.sort_custom(func(a: Look, b: Look) -> bool: return a.id < b.id)
	looks_changed.emit()


## Add a look and save it. Gives it an id (also its file name) if it has none.
func add(look: Look) -> void:
	_ensure_loaded()
	if look.id.is_empty():
		look.id = "%d_%04d" % [Time.get_unix_time_from_system(), randi() % 10000]
	if not looks.has(look):
		looks.append(look)
	save(look)
	looks_changed.emit()


func remove(look: Look) -> void:
	_ensure_loaded()
	looks.erase(look)
	var path := _path(look)
	if persist and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	looks_changed.emit()


func rename(look: Look, new_name: String) -> void:
	new_name = new_name.strip_edges()
	if new_name.is_empty() or new_name == look.look_name or is_name_taken(new_name, look):
		return
	look.look_name = new_name
	save(look)
	looks_changed.emit()


func save(look: Look) -> void:
	if not persist:
		return
	DirAccess.make_dir_recursive_absolute(looks_dir())
	var err := ResourceSaver.save(look, _path(look))
	if err != OK:
		push_warning("LookLibrary: could not save '%s' (error %d)" % [look.look_name, err])


## True when another look (not `except`) already has this name. Names are
## compared without case or surrounding spaces, so "Intro" and "intro " clash.
func is_name_taken(look_name: String, except: Look = null) -> bool:
	_ensure_loaded()
	var key := look_name.strip_edges().to_lower()
	for l in looks:
		if l != except and l.look_name.strip_edges().to_lower() == key:
			return true
	return false


## "Look 3" style name that no other look uses yet.
func next_name() -> String:
	_ensure_loaded()
	var n := looks.size() + 1
	while is_name_taken("Look %d" % n):
		n += 1
	return "Look %d" % n


## Replace the whole shelf (opening a show).
func set_looks(list: Array[Look]) -> void:
	_loaded = true
	looks = list
	looks_changed.emit()


func _path(look: Look) -> String:
	return looks_dir().path_join(look.id + ".tres")
