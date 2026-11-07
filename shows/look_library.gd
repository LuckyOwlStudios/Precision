class_name LookLibrary
extends Node
## The Looks shelf. Each look is saved as its own file in the library folder
## (same place as the song list) right after every change, so looks survive
## restarting the app. No UI in here: panels listen to `looks_changed`.

signal looks_changed

## Override for tests.
@export var root_dir: String = "user://library"

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
	var dir := DirAccess.open(looks_dir())
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
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	looks_changed.emit()


func rename(look: Look, new_name: String) -> void:
	new_name = new_name.strip_edges()
	if new_name.is_empty() or new_name == look.look_name:
		return
	look.look_name = new_name
	save(look)
	looks_changed.emit()


func save(look: Look) -> void:
	DirAccess.make_dir_recursive_absolute(looks_dir())
	var err := ResourceSaver.save(look, _path(look))
	if err != OK:
		push_warning("LookLibrary: could not save '%s' (error %d)" % [look.look_name, err])


## "Look 3" style name that no other look uses yet.
func next_name() -> String:
	_ensure_loaded()
	var n := looks.size() + 1
	var taken := looks.map(func(l: Look) -> String: return l.look_name)
	while taken.has("Look %d" % n):
		n += 1
	return "Look %d" % n


func _path(look: Look) -> String:
	return looks_dir().path_join(look.id + ".tres")
