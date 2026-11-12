class_name PositionPreset
extends Resource
## A saved position: where each moving head was aimed (pan and tilt, nothing
## else) when you pressed "Save position". "Front of stage", "Crowd left"...
## Shows refer to a position by its `id`, never by copying the numbers, so
## updating a position changes every song that uses it.

## Stable file name; how shows and the library find it. Never changes, even
## when the position is renamed.
@export var id: String = ""
@export var position_name: String = ""
## Seconds to move there when fired by hand.
@export var fade_time: float = 1.0
## Fixture path (relative to the rig) -> { "pan": 0..1, "tilt": 0..1 }.
@export var values: Dictionary = {}


## Can this fixture be aimed (has a pan or tilt channel)?
static func can_aim(fx: DMXFixture) -> bool:
	return fx != null and fx.profile != null and (fx.profile.has_channel("pan") or fx.profile.has_channel("tilt"))


## Pan/tilt of every fixture in `fixtures` that can aim, keyed by rig path.
static func capture_values(root: Node, fixtures: Array) -> Dictionary:
	var d := {}
	for fx: DMXFixture in fixtures:
		if can_aim(fx):
			d[str(root.get_path_to(fx))] = {"pan": fx.pan, "tilt": fx.tilt}
	return d


static func capture(root: Node, fixtures: Array, p_name: String) -> PositionPreset:
	var p := PositionPreset.new()
	p.position_name = p_name
	p.values = capture_values(root, fixtures)
	return p


## What these fixtures are aimed at right now, for the paths this position
## touches. Used to undo applying one.
func current_values(root: Node) -> Dictionary:
	var d := {}
	for path in values:
		var fx := root.get_node_or_null(NodePath(str(path))) as DMXFixture
		if fx:
			d[path] = {"pan": fx.pan, "tilt": fx.tilt}
	return d
