class_name PositionLibrary
extends Node
## The show's Positions shelf. Positions belong to the show, not the computer: each show
## has its own fixtures, so a position only makes sense inside it. They are saved in
## the show file (the `positions` section, see to_data / from_data) and an undo step
## marks the show as changed. No UI in here: panels listen to `positions_changed`.

signal positions_changed

var positions: Array[PositionPreset] = []


## Save format for the show file: a list of {id, name, fade, values}.
func to_data() -> Array:
	var list: Array = []
	for l in positions:
		list.append({"id": l.id, "name": l.position_name, "fade": l.fade_time, "values": l.values})
	return list


## Replace the shelf with what a show file holds (see ShowCodec.decode).
func from_data(data: Variant) -> void:
	positions.clear()
	data = ShowCodec.decode(data)
	if data is Array:
		for item: Variant in data:
			if not item is Dictionary:
				continue
			var d: Dictionary = item
			var p := PositionPreset.new()
			p.id = str(d.get("id", ""))
			p.position_name = str(d.get("name", ""))
			p.fade_time = float(d.get("fade", 1.0))
			p.values = d.get("values", {})
			_ensure_id(p)
			positions.append(p)
	positions_changed.emit()


func clear() -> void:
	positions.clear()
	positions_changed.emit()


## Add a position. Gives it an id if it has none.
func add(p: PositionPreset) -> void:
	_ensure_id(p)
	if not positions.has(p):
		positions.append(p)
	positions_changed.emit()


## The position with this id, or null (deleted, or this show never had it).
func find(position_id: String) -> PositionPreset:
	for l in positions:
		if l.id == position_id:
			return l
	return null


func remove(p: PositionPreset) -> void:
	positions.erase(p)
	positions_changed.emit()


func rename(p: PositionPreset, new_name: String) -> void:
	new_name = new_name.strip_edges()
	if new_name.is_empty() or new_name == p.position_name or is_name_taken(new_name, p):
		return
	p.position_name = new_name
	positions_changed.emit()


## True when another position (not `except`) already has this name. Names are
## compared without case or surrounding spaces, so "Intro" and "intro " clash.
func is_name_taken(position_name: String, except: PositionPreset = null) -> bool:
	var key := position_name.strip_edges().to_lower()
	for l in positions:
		if l != except and l.position_name.strip_edges().to_lower() == key:
			return true
	return false


## "Position 3" style name that no other position uses yet.
func next_name() -> String:
	var n := positions.size() + 1
	while is_name_taken("Position %d" % n):
		n += 1
	return "Position %d" % n


func _ensure_id(p: PositionPreset) -> void:
	if p.id.is_empty():
		p.id = "%d_%04d" % [Time.get_unix_time_from_system(), randi() % 10000]
