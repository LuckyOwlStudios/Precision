class_name StructureCodec
extends RefCounted
## The structure section of a show file: the truss, corner boxes and base
## plates of the stage set, each as "which piece scene, where, what you called
## it, which piece is its mirror twin".
##
## Layout: { "pieces": [ {scene, name, transform, label?, mirror?: {partner, flip}}, ... ] }


static func save(set_root: Node3D, ignore: Node = null) -> Dictionary:
	var pieces: Array[StructurePiece] = []
	for c in set_root.get_children():
		if c is StructurePiece and c != ignore and not c.is_queued_for_deletion() and not c.scene_file_path.is_empty():
			pieces.append(c)
	var list: Array = []
	for p in pieces:
		var entry := {"scene": p.scene_file_path, "name": String(p.name), "transform": p.transform}
		if p.has_meta(StudioContext.META_LABEL):
			entry["label"] = String(p.get_meta(StudioContext.META_LABEL))
		var twin := StageSymmetry.partner_of(p)
		if twin != null and pieces.has(twin):
			entry["mirror"] = {"partner": pieces.find(twin), "flip": int(p.get_meta(StageSymmetry.META_FLIP, -1))}
		list.append(entry)
	return {"pieces": list}


## Remove every piece from `set_root`. (They're freed at once, so the new ones
## can take the same node names.)
static func clear(set_root: Node3D) -> void:
	for c in set_root.get_children():
		if c is StructurePiece:
			set_root.remove_child(c)
			c.free()


static func load_data(set_root: Node3D, data: Variant) -> void:
	clear(set_root)
	if not data is Dictionary:
		return
	var entries: Array = (data as Dictionary).get("pieces", [])
	var made: Array[StructurePiece] = []
	for e: Variant in entries:
		var entry: Dictionary = e
		var scene := str(entry.get("scene", ""))
		var packed := load(scene) as PackedScene if ResourceLoader.exists(scene) else null
		var piece := packed.instantiate() as StructurePiece if packed else null
		if piece == null:
			push_warning("Show file: truss piece '%s' is not available, skipped" % scene)
			made.append(null)
			continue
		piece.name = str(entry.get("name", piece.name))
		set_root.add_child(piece)
		piece.transform = ShowCodec.decode(entry.get("transform", Transform3D.IDENTITY))
		if entry.has("label"):
			piece.set_meta(StudioContext.META_LABEL, str(entry["label"]))
		made.append(piece)
	for i in made.size():
		var m: Variant = (entries[i] as Dictionary).get("mirror")
		if made[i] == null or not m is Dictionary:
			continue
		var other := int((m as Dictionary).get("partner", -1))
		if other > i and other < made.size() and made[other] != null:
			StageSymmetry.link(made[i], made[other], int((m as Dictionary).get("flip", -1)))
