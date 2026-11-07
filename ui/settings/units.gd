class_name Units
extends RefCounted
## Lengths for people. The app works in metres everywhere inside; this turns a
## length into what the person chose to see (metres or feet) and back.
##
##   label.text = Units.length_text(3.2)      # "3.20 m"  or  "10' 6\""
##   box.value = Units.to_display(3.2)        # 3.2       or  10.499 (feet)
##   var m := Units.from_display(box.value)   # back to metres
##
## Draw rulers and dimension lines with Units.nice_step() and Units.length_text()
## so a grid line lands on a round number in whichever system is showing.

enum System { METRIC, IMPERIAL }

const FEET_PER_METRE := 3.280839895
const METRES_PER_FOOT := 0.3048


static func system() -> System:
	return AppSettings.units


static func is_imperial() -> bool:
	return system() == System.IMPERIAL


## Metres in, number of the current unit out (metres or decimal feet).
static func to_display(metres: float) -> float:
	return metres * FEET_PER_METRE if is_imperial() else metres


static func from_display(value: float) -> float:
	return value * METRES_PER_FOOT if is_imperial() else value


## "m" or "ft": the unit of to_display(), for spin box suffixes.
static func suffix() -> String:
	return "ft" if is_imperial() else "m"


## A length as text. Metric: "3.20 m". Imperial: feet and inches, "10' 6\"".
## `decimals` only applies to metric (feet are rounded to the nearest inch).
static func length_text(metres: float, decimals: int = 2) -> String:
	if not is_imperial():
		return "%.*f m" % [decimals, metres]
	var negative := metres < 0.0
	var inches := roundi(absf(metres) / 0.0254)
	var feet := inches / 12
	inches = inches % 12
	return "%s%d' %d\"" % ["-" if negative and (feet > 0 or inches > 0) else "", feet, inches]


## A signed length, for how far something moved: "+0.25 m" / "+0' 10\"".
static func delta_text(metres: float, decimals: int = 2) -> String:
	if not is_imperial():
		return "%+.*f m" % [decimals, metres]
	return ("+" if metres >= 0.0 else "") + length_text(metres)


## A round grid or ruler step near `metres`: 0.25, 0.5, 1, 2, 5 m ... or in
## imperial 6", 1', 2', 5', 10' ... (returned in metres either way).
static func nice_step(metres: float) -> float:
	var in_unit := to_display(metres)
	var base := pow(10.0, floorf(log(maxf(in_unit, 1e-6)) / log(10.0)))
	var best := base
	for mult: float in [1.0, 2.0, 5.0, 10.0]:
		best = base * mult
		if best >= in_unit:
			break
	return from_display(best)
