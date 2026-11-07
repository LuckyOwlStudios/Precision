class_name UnitSpinBox
extends SpinBox
## A number box for a length. Set it up in the editor in METRES (min, max, step,
## custom arrow step); it shows metres or feet to match the Units setting and
## keeps the real value in metres. Use set_metres() / get_metres() instead of
## `value`, and `metres_changed` instead of `value_changed`.
##
## A box that shows rounded feet doesn't nudge an untouched value: get_metres()
## returns the exact metres you set until you type something different.

signal metres_changed(metres: float)

var _min_m := 0.0
var _max_m := 0.0
var _step_m := 0.01
var _arrow_m := 0.0
var _metres := 0.0
var _ready_done := false
var _applying := false ## changing range and suffix: not an edit by the person


func _ready() -> void:
	_min_m = min_value
	_max_m = max_value
	_step_m = step
	_arrow_m = custom_arrow_step
	_metres = clampf(value, _min_m, _max_m) # still metres: the scene was authored in metres
	_ready_done = true
	_apply_units()
	value_changed.connect(_on_value_changed)
	AppSettings.hub().changed.connect(func(key: StringName) -> void:
		if key == &"units":
			_apply_units())


## The length in metres. Exact unless the person typed a different number.
func get_metres() -> float:
	return _metres if _matches_display() else Units.from_display(value)


func set_metres(m: float) -> void:
	_metres = m
	value = _display_of(m)


## Like set_metres but silent (no value_changed / metres_changed).
func set_metres_no_signal(m: float) -> void:
	_metres = m
	set_value_no_signal(_display_of(m))


func _display_of(m: float) -> float:
	return snappedf(Units.to_display(m), step)


func _matches_display() -> bool:
	return is_equal_approx(value, _display_of(_metres))


func _on_value_changed(_v: float) -> void:
	if _applying or _matches_display():
		return
	_metres = Units.from_display(value)
	metres_changed.emit(_metres)


func _apply_units() -> void:
	if not _ready_done:
		return
	# Feet have the same 0.01 step but cover a bit more range; the arrows jump
	# half a foot instead of 0.1 m.
	_applying = true
	var imperial := Units.is_imperial()
	# A Range rounds values to steps counted from its minimum, so the ends must
	# sit on the step grid too or every value comes out slightly off.
	step = _step_m
	min_value = snappedf(Units.to_display(_min_m), _step_m)
	max_value = snappedf(Units.to_display(_max_m), _step_m)
	custom_arrow_step = (0.5 if imperial else _arrow_m) if _arrow_m > 0.0 else 0.0
	suffix = " " + Units.suffix()
	set_value_no_signal(_display_of(_metres))
	_applying = false
