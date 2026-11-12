class_name PositionLibrary
extends Node
## The Positions shelf. Each position is saved as its own file in the library folder
## (same place as the song list) right after every change, so positions survive
## restarting the app. No UI in here: panels listen to `positions_changed`.

signal positions_changed

## Override for tests.
@export var root_dir: String = "user://library"

var positions: Array[PositionPreset] = []

var _loaded := false


func _ready() -> void:
	_ensure_loaded()


func positions_dir() -> String:
	return root_dir.path_join("positions")


func _ensure_loaded() -> void:
	if not _loaded:
		load_positions()


func load_positions() -> void:
	_loaded = true
	positions.clear()
	var dir := DirAccess.open(positions_dir())
	if dir:
		for file in dir.get_files():
			if file.get_extension() == "tres":
				var p := ResourceLoader.load(positions_dir().path_join(file), "", ResourceLoader.CACHE_MODE_IGNORE) as PositionPreset
				if p:
					positions.append(p)
	positions.sort_custom(func(a: PositionPreset, b: PositionPreset) -> bool: return a.id < b.id)
	positions_changed.emit()


## Add a position and save it. Gives it an id (also its file name) if it has none.
func add(p: PositionPreset) -> void:
	_ensure_loaded()
	if p.id.is_empty():
		p.id = "%d_%04d" % [Time.get_unix_time_from_system(), randi() % 10000]
	if not positions.has(p):
		positions.append(p)
	save(p)
	positions_changed.emit()


## The position with this id, or null (deleted since a show used it).
func find(position_id: String) -> PositionPreset:
	_ensure_loaded()
	for p in positions:
		if p.id == position_id:
			return p
	return null


func remove(p: PositionPreset) -> void:
	_ensure_loaded()
	positions.erase(p)
	var path := _path(p)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	positions_changed.emit()


func rename(p: PositionPreset, new_name: String) -> void:
	new_name = new_name.strip_edges()
	if new_name.is_empty() or new_name == p.position_name or is_name_taken(new_name, p):
		return
	p.position_name = new_name
	save(p)
	positions_changed.emit()


func save(p: PositionPreset) -> void:
	DirAccess.make_dir_recursive_absolute(positions_dir())
	var err := ResourceSaver.save(p, _path(p))
	if err != OK:
		push_warning("PositionLibrary: could not save '%s' (error %d)" % [p.position_name, err])


## True when another position (not `except`) already has this name. Names are
## compared without case or surrounding spaces, so "Intro" and "intro " clash.
func is_name_taken(position_name: String, except: PositionPreset = null) -> bool:
	_ensure_loaded()
	var key := position_name.strip_edges().to_lower()
	for l in positions:
		if l != except and l.position_name.strip_edges().to_lower() == key:
			return true
	return false


## "Position 3" style name that no other position uses yet.
func next_name() -> String:
	_ensure_loaded()
	var n := positions.size() + 1
	while is_name_taken("Position %d" % n):
		n += 1
	return "Position %d" % n


func _path(p: PositionPreset) -> String:
	return positions_dir().path_join(p.id + ".tres")
