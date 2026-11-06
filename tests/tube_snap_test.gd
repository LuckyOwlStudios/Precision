extends SceneTree
## Checks TubeSnap faces (fixed angles and all round) and that fixtures hang on
## the face the cursor points at.
##   godot --headless --path . --script res://tests/tube_snap_test.gd

var _failed := 0


func _init() -> void:
	# Angles round the tube, measured from the node's +Y.
	_expect("0 is up", TubeSnap.face_dir(0.0), Vector3.UP)
	_expect("90 is front", TubeSnap.face_dir(90.0), Vector3.BACK)
	_expect("180 is down", TubeSnap.face_dir(180.0), Vector3.DOWN)
	_expect("-90 is back", TubeSnap.face_dir(-90.0), Vector3.FORWARD)

	# A truss corner bar: top and front faces.
	var corner := TubeSnap.new()
	corner.length = 2.0
	corner.angles = PackedFloat32Array([0.0, 90.0])
	root.add_child(corner)
	var faces := corner.world_faces()
	_expect("corner bar has two faces", faces.size(), 2)
	var pipe := StageRoom.Pipe.new(corner.world_start(), corner.world_end(), faces)
	_expect("aiming up picks the top face", pipe.face_for(Vector3(0, 1, 0.3)), Vector3.UP)
	_expect("aiming forward picks the front face", pipe.face_for(Vector3(0, -0.2, 1)), Vector3.BACK)
	_expect("aiming down (into the truss) picks the front", pipe.face_for(Vector3(0, -1, 0.35)), Vector3.BACK)
	_expect("along the tube gives the default face", pipe.face_for(Vector3.RIGHT), Vector3.UP)

	var mounts := PackedVector3Array([Vector3.ZERO])
	var top := StageRoom.hang(pipe, 1.0, mounts)
	_expect("top face: beam points up", -top.basis.y, Vector3.UP)
	var side := StageRoom.hang(pipe, 1.0, mounts, Vector3.BACK)
	_expect("front face: beam points out the front", -side.basis.y, Vector3.BACK)
	_expect("front face: still along the tube", absf(side.basis.x.dot(Vector3.RIGHT)), 1.0)
	_expect("front face: right-handed", side.basis.determinant() > 0.0, true)
	var held := StageRoom.pipe_holding([pipe] as Array[StageRoom.Pipe], side, mounts)
	_expect("front-hung fixture is held by the tube", held == pipe, true)

	# A rotated piece turns its faces with it.
	var turned := Node3D.new()
	turned.rotation_degrees = Vector3(0, 180, 0)
	root.add_child(turned)
	var back := TubeSnap.new()
	back.angles = PackedFloat32Array([90.0])
	turned.add_child(back)
	_expect("rotated piece: front face turns round", back.world_faces()[0], Vector3.FORWARD)

	# A 360 tube: anywhere round it, optionally in steps.
	var ring := TubeSnap.new()
	ring.mode = TubeSnap.Mode.AROUND
	root.add_child(ring)
	var free := StageRoom.Pipe.new(Vector3.ZERO, Vector3.RIGHT, ring.world_faces(), true, 0.0)
	var aim := Vector3(0, 1, 1).normalized()
	_expect("360 tube hangs the way you aim", free.face_for(aim), aim)
	var stepped := StageRoom.Pipe.new(Vector3.ZERO, Vector3.RIGHT, ring.world_faces(), true, 90.0)
	_expect("360 tube in 90 degree steps rounds to the nearest", stepped.face_for(Vector3(0, 0.3, 1)), Vector3.BACK)

	# Joining runs only when faces match.
	var a := StageRoom.Pipe.new(Vector3.ZERO, Vector3.RIGHT, faces)
	var b := StageRoom.Pipe.new(Vector3.RIGHT, Vector3.RIGHT * 2, faces)
	var c := StageRoom.Pipe.new(Vector3.RIGHT, Vector3.RIGHT * 2, [Vector3.DOWN] as Array[Vector3])
	_expect("same faces join", a.same_faces(b), true)
	_expect("different faces don't join", a.same_faces(c), false)

	print("tube snap test: ", "FAILED" if _failed else "ok")
	quit(1 if _failed else 0)


func _expect(label: String, got: Variant, want: Variant) -> void:
	var same := false
	if got is Vector3:
		same = (got as Vector3).is_equal_approx(want)
	elif got is float:
		same = is_equal_approx(got, want)
	else:
		same = got == want
	if not same:
		_failed += 1
		print("FAIL ", label, ": got ", got, ", wanted ", want)
