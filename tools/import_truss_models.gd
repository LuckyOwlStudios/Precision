extends SceneTree
## Turns the truss GLBs from Blender into the meshes the truss pieces load.
##   godot --headless --path . --script res://tools/import_truss_models.gd
## The GLBs sit in structure/models/source (built there by build_truss.py),
## which Godot ignores, so they are read here with GLTFDocument and every
## part is merged into one ArrayMesh per length, saved next to the pieces.

const SOURCE := "res://structure/models/source/"
const OUT := "res://structure/models/"


func _init() -> void:
	var failed := 0
	for file in DirAccess.get_files_at(SOURCE):
		if file.get_extension() != "glb":
			continue
		var mesh := _merged(SOURCE + file)
		if mesh == null:
			failed += 1
			continue
		var path := OUT + file.get_basename() + ".res"
		var err := ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS)
		print("%s: %d vertices, %s -> %s" % [file, _vertex_count(mesh), mesh.get_aabb(), path])
		if err != OK:
			failed += 1
	quit(1 if failed else 0)


## Every mesh in the GLB, with its node transform baked in, as one surface.
func _merged(path: String) -> ArrayMesh:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		push_error("could not read " + path)
		return null
	var scene := doc.generate_scene(state)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var xf := _transform_to(mi, scene)
		for s in mi.mesh.get_surface_count():
			st.append_from(mi.mesh, s, xf)
	scene.free()
	st.index()
	var mesh := st.commit()
	mesh.resource_name = path.get_file().get_basename()
	return mesh


func _transform_to(n: Node3D, top: Node) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != top:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _vertex_count(mesh: ArrayMesh) -> int:
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
