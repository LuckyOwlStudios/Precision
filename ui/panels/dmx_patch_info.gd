class_name DMXPatchInfo
extends RefCounted
## Who owns which DMX address, worked out once per patch change: each fixture's
## colour, which addresses are shared by two fixtures, and who overlaps whom.
## The overview strip and the fixture cards both read from this, so they
## always agree.

## One colour per fixture, in rig order. Amber (selection) and red (problems)
## are left out on purpose, so those two keep their meaning.
const PALETTE: Array[Color] = [
	Color("ff6fae"), Color("5cc8ff"), Color("9b7cff"), Color("3ddc97"),
	Color("d4e157"), Color("2ee6c8"), Color("ff9a76"), Color("e089ff"),
]

var fixtures: Array[DMXFixture] = []
var colors: Dictionary = {}    ## DMXFixture -> Color
var owners: Array = []         ## index 1..512 -> Array[DMXFixture]
var overlaps: Dictionary = {}  ## DMXFixture -> Array of the other fixtures it shares addresses with
var overflow: Dictionary = {}  ## DMXFixture -> true if it runs past channel 512
var used_count := 0            ## addresses with at least one fixture
var shared_count := 0          ## addresses with two or more


static func build(p_fixtures: Array[DMXFixture]) -> DMXPatchInfo:
	var info := DMXPatchInfo.new()
	info.fixtures = p_fixtures
	info.owners.resize(513)
	for a in 513:
		info.owners[a] = []
	for i in p_fixtures.size():
		var fx := p_fixtures[i]
		info.colors[fx] = PALETTE[i % PALETTE.size()]
		for c in fx.profile.channels.size():
			var a := fx.start_address + c
			if a > 512:
				info.overflow[fx] = true
			elif a >= 1:
				info.owners[a].append(fx)
	for a in range(1, 513):
		var list: Array = info.owners[a]
		if list.size() > 0:
			info.used_count += 1
		if list.size() > 1:
			info.shared_count += 1
			for fx: DMXFixture in list:
				var others: Array = info.overlaps.get(fx, [])
				for other: DMXFixture in list:
					if other != fx and not others.has(other):
						others.append(other)
				info.overlaps[fx] = others
	return info


func first_owner(address: int) -> DMXFixture:
	if address < 1 or address > 512 or owners[address].is_empty():
		return null
	return owners[address][0]


func is_shared(address: int) -> bool:
	return address >= 1 and address <= 512 and owners[address].size() > 1


func has_problem(fx: DMXFixture) -> bool:
	return overlaps.has(fx) or overflow.has(fx)


## "Ch 12–14" or "Ch 5".
static func range_text(fx: DMXFixture) -> String:
	var last := fx.start_address + fx.profile.channels.size() - 1
	if last <= fx.start_address:
		return "Ch %d" % fx.start_address
	return "Ch %d–%d" % [fx.start_address, last]


## Plain-words problem for a fixture ("Shares channels with Par 2"), or "".
func problem_text(fx: DMXFixture) -> String:
	var parts: PackedStringArray = []
	if overlaps.has(fx):
		var names: PackedStringArray = []
		for other: DMXFixture in overlaps[fx]:
			names.append(StudioContext.display_name(other))
		parts.append("Shares channels with " + ", ".join(names))
	if overflow.has(fx):
		parts.append("Runs past channel 512")
	return ". ".join(parts)
