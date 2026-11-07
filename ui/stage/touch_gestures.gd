class_name TouchGestures
extends RefCounted
## Tracks the fingers on the stage and turns their movement into camera
## gestures: two fingers pinch (zoom) and drag (orbit), three drag (pan).
## One finger is left alone: Godot already turns it into a mouse click/drag.

const PINCH_MIN_PX := 4.0 ## spread under this is too close to read a ratio from

var _fingers: Dictionary = {} ## finger index -> screen position


func count() -> int:
	return _fingers.size()


func press(index: int, at: Vector2) -> void:
	_fingers[index] = at


func release(index: int) -> void:
	_fingers.erase(index)


## Move one finger. With two or more down, returns {"pan": Vector2, "pinch": float}:
## how far the middle of the fingers moved, and the change in how far apart they
## are (above 1 spreading, below 1 pinching). Otherwise an empty dictionary.
func drag(index: int, at: Vector2) -> Dictionary:
	if not _fingers.has(index):
		_fingers[index] = at
		return {}
	var centre_before := _centre()
	var spread_before := _spread()
	_fingers[index] = at
	if _fingers.size() < 2:
		return {}
	var pinch := 1.0
	var spread_after := _spread()
	if spread_before > PINCH_MIN_PX and spread_after > PINCH_MIN_PX:
		pinch = spread_after / spread_before
	return {"pan": _centre() - centre_before, "pinch": pinch}


func _centre() -> Vector2:
	var sum := Vector2.ZERO
	for p: Vector2 in _fingers.values():
		sum += p
	return sum / maxf(1.0, _fingers.size())


## Average distance of the fingers from their middle.
func _spread() -> float:
	var c := _centre()
	var total := 0.0
	for p: Vector2 in _fingers.values():
		total += p.distance_to(c)
	return total / maxf(1.0, _fingers.size())
