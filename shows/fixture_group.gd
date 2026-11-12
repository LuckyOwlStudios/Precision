class_name FixtureGroup
extends Resource
## A named set of fixtures ("Front wash", "Movers") you can recall with one
## click. Members are stored as fixture paths relative to the rig, the same way
## looks, cues and effect clips refer to fixtures, so a group keeps working
## after a fixture is renamed and simply skips fixtures that were removed.

## Stable file name; also how the library tells groups apart.
@export var id: String = ""
@export var group_name: String = ""
## Fixture paths (relative to the rig), in rig order.
@export var fixtures: PackedStringArray = PackedStringArray()


## Plain data for saving a show or sending around: { id, name, fixtures }.
func to_dict() -> Dictionary:
	return {"id": id, "name": group_name, "fixtures": fixtures.duplicate()}


static func from_dict(d: Dictionary) -> FixtureGroup:
	var g := FixtureGroup.new()
	g.id = str(d.get("id", ""))
	g.group_name = str(d.get("name", ""))
	g.fixtures = PackedStringArray(d.get("fixtures", PackedStringArray()))
	return g
