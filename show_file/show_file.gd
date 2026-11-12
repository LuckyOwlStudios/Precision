class_name ShowFile
extends RefCounted
## The show file on disk: reading, writing and versioning. What goes inside is
## up to the sections (see ShowManager); this only knows the envelope.
##
## A show file is JSON:
##   {
##     "format": "precision-show",
##     "version": 1,
##     "saved_at": "2026-11-12T19:00:00",
##     "sections": { "<id>": <whatever that section stores>, ... }
##   }
##
## Adding a feature to the file never needs a new version: give it its own
## section id. Old files simply lack the section (it loads as "empty") and old
## builds keep a section they don't know and write it back untouched. Bump
## VERSION only when an existing section changes shape, and teach migrate()
## to upgrade the older layout.

const FORMAT := "precision-show"
const VERSION := 1
const EXTENSION := "precision"


## Result of read(): `error` is empty on success.
class ReadResult:
	extends RefCounted
	var error := ""
	var sections: Dictionary = {}


static func read(path: String) -> ReadResult:
	var result := ReadResult.new()
	if not FileAccess.file_exists(path):
		result.error = "The file doesn't exist any more:\n%s" % path
		return result
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		result.error = "This isn't a Precision show file (or it is damaged):\n%s" % path
		return result
	var data: Dictionary = json.data
	if str(data.get("format", "")) != FORMAT:
		result.error = "This isn't a Precision show file:\n%s" % path
		return result
	var version := int(data.get("version", 0))
	if version > VERSION:
		result.error = "This show was saved by a newer Precision (file version %d, this one reads up to %d). Update Precision to open it." % [version, VERSION]
		return result
	data = migrate(data)
	var sections: Variant = data.get("sections", {})
	result.sections = sections if sections is Dictionary else {}
	return result


## Upgrade an older file's layout to VERSION. Nothing to do yet: add a step per
## version here (if version < 2: ...) when a section's shape changes.
static func migrate(data: Dictionary) -> Dictionary:
	return data


## Write the sections to `path`. The file is written next to the target first
## and moved over it, so a crash or a full disk never leaves half a show.
static func write(path: String, sections: Dictionary) -> Error:
	var doc := {
		"format": FORMAT,
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"sections": sections,
	}
	var dir := path.get_base_dir()
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(doc, "\t", false))
	var write_error := f.get_error()
	f.close()
	if write_error != OK:
		DirAccess.remove_absolute(tmp)
		return write_error
	return DirAccess.rename_absolute(tmp, path)


## `path` with the show extension added if it has none.
static func with_extension(path: String) -> String:
	return path if path.get_extension().to_lower() == EXTENSION else path + "." + EXTENSION
