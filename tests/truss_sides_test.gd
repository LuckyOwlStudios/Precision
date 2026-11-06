extends SceneTree
## Checks that fixtures can hang off the outward side faces of a truss tube as
## well as its top and bottom.
##   godot --headless --path . --script res://tests/truss_sides_test.gd

var _failed := 0


func _init() -> void:
	var pipe := StageRoom.Pipe.new(Vector3(-1, 3, 0.1), Vector3(1, 3, 0.1), Vector3.UP, Vector3.BACK)
	var mounts := PackedVector3Array([Vector3.ZERO])
	_expect("looking from above picks the top face", pipe.side_towards(Vector3(0, 6, 0.1), 1.0), Vector3.UP)
	_expect("looking from the front picks the side face", pipe.side_towards(Vector3(0, 3, 5), 1.0), Vector3.BACK)
	var top := StageRoom.hang(pipe, 1.0, mounts)
	_expect("top face: beam points up", -top.basis.y, Vector3.UP)
	var side := StageRoom.hang(pipe, 1.0, mounts, Vector3.BACK)
	_expect("side face: beam points out of the side", -side.basis.y, Vector3.BACK)
	_expect("side face: still along the tube", absf(side.basis.x.dot(Vector3.RIGHT)), 1.0)
	_expect("side face: basis stays right-handed", side.basis.determinant() > 0.0, true)
	var plain := StageRoom.Pipe.new(Vector3.ZERO, Vector3.RIGHT, Vector3.DOWN)
	_expect("one-face tube always uses its face", plain.side_towards(Vector3(0, 9, 9), 0.5), Vector3.DOWN)
	var held := StageRoom.pipe_holding([pipe] as Array[StageRoom.Pipe], side, mounts)
	_expect("side-hung fixture counts as held by the tube", held == pipe, true)
	print("truss sides test: ", "FAILED" if _failed else "ok")
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
