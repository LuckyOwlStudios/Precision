extends SceneTree
## Checks that fixtures on one tube stop at each other instead of overlapping.
##   godot --headless --path . --script res://tests/tube_neighbours_test.gd

var _failed := 0


func _init() -> void:
	var gap := StageRoom.NEIGHBOUR_GAP
	# A 1 m wide bar (body from -0.5 to +0.5 round its clamps) on a 6 m tube,
	# next to a neighbour covering 3..4 m.
	var rel := Vector2(-0.5, 0.5)
	var others: Array[Vector2] = [Vector2(3.0, 4.0)]
	var blocked := StageRoom.blocked_by(rel, others)
	_expect("one blocked stretch", blocked.size(), 1)
	_expect("blocked from the neighbour's left edge minus half the bar", blocked[0].x, 2.5 - gap)
	_expect("to its right edge plus half the bar", blocked[0].y, 4.5 + gap)

	var limits := Vector2(0.6, 5.4)
	var g := StageRoom.free_gap(limits, blocked, 1.0)
	_expect("sliding right stops at the neighbour", g.y, 2.5 - gap)
	_expect("sliding left still reaches the tube end", g.x, 0.6)
	var g2 := StageRoom.free_gap(limits, blocked, 5.0)
	_expect("from the far side it stops on the other edge", g2.x, 4.5 + gap)

	_expect("a free spot is kept", StageRoom.nearest_free(limits, blocked, 1.5), 1.5)
	_expect("dropping onto the neighbour moves to its nearest edge", StageRoom.nearest_free(limits, blocked, 3.2), 2.5 - gap)
	_expect("past the middle goes to the other edge", StageRoom.nearest_free(limits, blocked, 4.2), 4.5 + gap)

	var full: Array[Vector2] = [Vector2(0.0, 6.0)]
	_expect("a full tube has no spot", is_nan(StageRoom.nearest_free(limits, StageRoom.blocked_by(rel, full), 3.0)), true)

	var two: Array[Vector2] = [Vector2(2.0, 2.4), Vector2(2.6, 3.0)]
	_expect("close neighbours merge into one block", StageRoom.blocked_by(rel, two).size(), 1)

	print("tube neighbours test: ", "FAILED" if _failed else "ok")
	quit(1 if _failed else 0)


func _expect(label: String, got: Variant, want: Variant) -> void:
	var same: bool = is_equal_approx(got, want) if got is float else got == want
	if not same:
		_failed += 1
		print("FAIL ", label, ": got ", got, ", wanted ", want)
