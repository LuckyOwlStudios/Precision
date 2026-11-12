class_name ProfileStore
extends RefCounted
## The fixture profiles the person made or imported. One .tres per fixture in
## the user data folder, so they survive updates and show up in the Fixtures
## library under "My fixtures".

const DEFAULT_DIR := "user://fixtures"

## Tests point this somewhere else.
static var dir: String = DEFAULT_DIR


## Every saved profile, sorted by file name. Each has its resource_path set.
static func load_all() -> Array[FixtureProfile]:
	var out: Array[FixtureProfile] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var files := d.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".tres"):
			continue
		var res := ResourceLoader.load(dir.path_join(f), "", ResourceLoader.CACHE_MODE_IGNORE)
		if res is FixtureProfile:
			out.append(res as FixtureProfile)
	return out


## Saves `profile` to `path` (to keep editing the same file), or to a new
## file named after it. Returns the path, or "" if writing failed.
static func save(profile: FixtureProfile, path: String = "") -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	if path.is_empty() or not path.begins_with(dir):
		path = _free_path(slug(profile.fixture_name))
	var err := ResourceSaver.save(profile, path, ResourceSaver.FLAG_CHANGE_PATH)
	if err != OK:
		push_error("Could not save fixture profile to %s (error %d)" % [path, err])
		return ""
	return path


## Removes a saved profile's file.
static func delete(profile: FixtureProfile) -> bool:
	var path := profile.resource_path
	if path.is_empty() or not path.begins_with(dir):
		return false
	return DirAccess.remove_absolute(path) == OK


## "Wash Bar Light (8ch)" -> "wash-bar-light-8ch"
static func slug(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		var is_word := (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9")
		if is_word:
			out += ch
		elif not out.is_empty() and not out.ends_with("-"):
			out += "-"
	out = out.trim_suffix("-")
	return out if not out.is_empty() else "fixture"


static func _free_path(base: String) -> String:
	var path := dir.path_join(base + ".tres")
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s-%d.tres" % [base, n])
		n += 1
	return path
