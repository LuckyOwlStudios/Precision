class_name StructureCatalog
extends RefCounted
## The structural pieces in the library: every scene in res://structure/pieces/.
## Drop a new piece scene in that folder and it shows up.

const FOLDER := "res://structure/pieces"


class Entry:
	extends RefCounted
	var path: String
	var display_name: String
	var kind: StructurePiece.Kind

	func _init(p_path: String, p_name: String, p_kind: StructurePiece.Kind) -> void:
		path = p_path
		display_name = p_name
		kind = p_kind


static var _entries: Array[Entry] = []


static func entries() -> Array[Entry]:
	if not _entries.is_empty():
		return _entries
	for file in ResourceLoader.list_directory(FOLDER):
		if not file.ends_with(".tscn"):
			continue
		var path := FOLDER.path_join(file)
		var piece := (load(path) as PackedScene).instantiate() as StructurePiece
		if piece == null:
			continue
		var label := piece.display_name if not piece.display_name.is_empty() else file.get_basename().capitalize()
		_entries.append(Entry.new(path, label, piece.kind))
		piece.free()
	_entries.sort_custom(func(a: Entry, b: Entry) -> bool:
		return a.kind < b.kind if a.kind != b.kind else a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return _entries
