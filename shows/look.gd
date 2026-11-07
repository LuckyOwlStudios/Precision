class_name Look
extends Resource
## A saved static look: what every fixture was doing when you pressed "Save look"
## (colour, dimmer, pan/tilt...), plus how long to fade there. Unlike a cue it
## is not part of a list: it lives in the Looks shelf and can be used any time,
## for example to set the mood before the first song.

## Stable file name; also how the library tells looks apart.
@export var id: String = ""
@export var look_name: String = ""
## Seconds to fade from whatever is on stage to this look.
@export var fade_time: float = 2.0
## Fixture path (relative to the rig) -> { property: value }, as in LightCue.
@export var values: Dictionary = {}


## Snapshot every fixture under `root` into a new look.
static func capture(root: Node, p_name: String, p_fade: float = 2.0) -> Look:
	var look := Look.new()
	look.look_name = p_name
	look.fade_time = p_fade
	for fx in root.find_children("*", "DMXFixture", true, false):
		look.values[str(root.get_path_to(fx))] = (fx as DMXFixture).capture()
	return look


## The values these fixtures hold right now, for the same paths this look
## touches. Used to undo applying a look.
func current_values(root: Node) -> Dictionary:
	var d := {}
	for path in values:
		var fx := root.get_node_or_null(NodePath(str(path))) as DMXFixture
		if fx:
			d[path] = fx.capture()
	return d
