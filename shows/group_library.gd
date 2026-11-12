class_name GroupLibrary
extends Node
## The saved fixture groups. Each group is its own file in <library>/groups/,
## written straight after every change. No UI in here: panels listen to
## `groups_changed`. `to_data()` / `load_data()` give the whole list as plain
## dictionaries for anything that saves the rig or a show.

signal groups_changed

## Override for tests.
@export var root_dir: String = "user://library"

var groups: Array[FixtureGroup] = []

var _loaded := false


func _ready() -> void:
	_ensure_loaded()


func groups_dir() -> String:
	return root_dir.path_join("groups")


func _ensure_loaded() -> void:
	if not _loaded:
		load_groups()


func load_groups() -> void:
	_loaded = true
	groups.clear()
	var dir := DirAccess.open(groups_dir())
	if dir:
		for file in dir.get_files():
			if file.get_extension() == "tres":
				var g := ResourceLoader.load(groups_dir().path_join(file), "", ResourceLoader.CACHE_MODE_IGNORE) as FixtureGroup
				if g:
					groups.append(g)
	groups.sort_custom(func(a: FixtureGroup, b: FixtureGroup) -> bool: return a.id < b.id)
	groups_changed.emit()


## Add a group and save it. Gives it an id (also its file name) if it has none.
func add(g: FixtureGroup) -> void:
	_ensure_loaded()
	if g.id.is_empty():
		g.id = "%d_%04d" % [Time.get_unix_time_from_system(), randi() % 10000]
	if not groups.has(g):
		groups.append(g)
	save(g)
	groups_changed.emit()


func remove(g: FixtureGroup) -> void:
	_ensure_loaded()
	groups.erase(g)
	var path := _path(g)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	groups_changed.emit()


func rename(g: FixtureGroup, new_name: String) -> void:
	new_name = new_name.strip_edges()
	if new_name.is_empty() or new_name == g.group_name or is_name_taken(new_name, g):
		return
	g.group_name = new_name
	save(g)
	groups_changed.emit()


## Replace a group's members (after fixtures were added to or removed from it).
func set_members(g: FixtureGroup, paths: PackedStringArray) -> void:
	g.fixtures = paths.duplicate()
	save(g)
	groups_changed.emit()


func save(g: FixtureGroup) -> void:
	DirAccess.make_dir_recursive_absolute(groups_dir())
	var err := ResourceSaver.save(g, _path(g))
	if err != OK:
		push_warning("GroupLibrary: could not save '%s' (error %d)" % [g.group_name, err])


## True when another group (not `except`) has this name, ignoring case and
## surrounding spaces.
func is_name_taken(group_name: String, except: FixtureGroup = null) -> bool:
	_ensure_loaded()
	var key := group_name.strip_edges().to_lower()
	for g in groups:
		if g != except and g.group_name.strip_edges().to_lower() == key:
			return true
	return false


## "Group 3" style name that no other group uses yet.
func next_name() -> String:
	_ensure_loaded()
	var n := groups.size() + 1
	while is_name_taken("Group %d" % n):
		n += 1
	return "Group %d" % n


func find_by_name(group_name: String) -> FixtureGroup:
	_ensure_loaded()
	var key := group_name.strip_edges().to_lower()
	for g in groups:
		if g.group_name.strip_edges().to_lower() == key:
			return g
	return null


## Every group as plain dictionaries (see FixtureGroup.to_dict).
func to_data() -> Array:
	_ensure_loaded()
	return groups.map(func(g: FixtureGroup) -> Dictionary: return g.to_dict())


## Replace all groups with these dictionaries and save them.
func load_data(data: Array) -> void:
	_ensure_loaded()
	for g in groups.duplicate():
		remove(g)
	for d: Variant in data:
		if d is Dictionary:
			add(FixtureGroup.from_dict(d))


func _path(g: FixtureGroup) -> String:
	return groups_dir().path_join(g.id + ".tres")
