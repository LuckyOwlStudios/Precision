extends SceneTree
## Checks the straight truss pieces show the Blender models, at the right size
## for their bounds and connectors, and that the corner box still builds.
##   godot --headless --path . --script res://tests/truss_model_test.gd

var _failed := 0
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for piece: String in ["truss_0_5m", "truss_1m", "truss_2m", "truss_3m"]:
		var scene: Node3D = (load("res://structure/pieces/%s.tscn" % piece) as PackedScene).instantiate()
		root.add_child(scene)
		var lattice := scene.get_node("Lattice") as TrussMesh
		var bounds: AABB = scene.get("bounds")
		_expect(piece + " uses its model", lattice.mesh.resource_path, "res://structure/models/%s.res" % piece)
		var box := lattice.mesh.get_aabb()
		_expect(piece + " model fills its bounds", box.position.distance_to(bounds.position) < 0.002 \
				and box.size.distance_to(bounds.size) < 0.002, true)
		# The model's end plates sit flush with the connectors.
		_expect(piece + " ends meet the connectors", absf(box.end.x - (scene.get_node("EndB") as Node3D).position.x) < 0.002, true)
		# Clamps hang on the chords' outer face: 14.5 cm out, as on the model.
		var tube := scene.get_node("TopFront") as Node3D
		_expect(piece + " tube snap matches the chords", absf(tube.position.y + MountPoint.TUBE_RADIUS - box.end.y) < 0.002, true)
		scene.free()

	var corner: Node3D = (load("res://structure/pieces/corner_box.tscn") as PackedScene).instantiate()
	root.add_child(corner)
	var mesh := (corner.get_node("Lattice") as TrussMesh).mesh
	_expect("corner box still builds its tubes", mesh != null and mesh.resource_path.is_empty() and mesh.get_surface_count() == 1, true)
	corner.free()

	var odd := TrussMesh.new()
	odd.length = 1.5
	root.add_child(odd)
	_expect("other lengths build from tubes", odd.model_path(), "")
	_expect("other lengths still get a mesh", odd.mesh != null and odd.mesh.get_aabb().size.x > 1.49, true)
	odd.free()

	print("%d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed else 0)


func _expect(what: String, got: Variant, want: Variant) -> void:
	_checks += 1
	if got != want:
		_failed += 1
		printerr("FAIL %s: got %s, want %s" % [what, got, want])
