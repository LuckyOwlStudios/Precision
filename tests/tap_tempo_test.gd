extends SceneTree
## Tap tempo maths. Run:
##   godot --headless --path . --script res://tests/tap_tempo_test.gd

var _fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _initialize() -> void:
	var t := TapTempo.new()
	_check(t.tap(10.0) == 0.0, "one tap has no tempo yet")
	_check(is_equal_approx(t.tap(10.5), 120.0), "two taps 0.5 s apart = 120 BPM")
	t.tap(11.0)
	_check(is_equal_approx(t.tap(11.5), 120.0), "steady taps stay at 120")

	# Wobbly human taps average out.
	t.reset()
	var now := 0.0
	var bpm := 0.0
	for gap: float in [0.0, 0.48, 0.52, 0.49, 0.51, 0.50]:
		now += gap
		bpm = t.tap(now)
	_check(absf(bpm - 120.0) < 1.0, "wobbly taps average to ~120 (got %s)" % bpm)

	# A long pause starts over, so the old tempo is forgotten.
	t.tap(100.0)
	_check(t.tap(100.0 + 3.0) == 0.0, "a pause over reset_after restarts the count")
	_check(t.count() == 1, "only the new tap is counted")
	_check(is_equal_approx(t.tap(103.4), 60.0 / 0.4), "new run uses the new gap")

	# Only the last `window` taps count: tempo follows a tempo change.
	t.reset()
	now = 0.0
	for i in 8:
		t.tap(now)
		now += 0.6
	for i in 8:
		bpm = t.tap(now)
		now += 0.4
	_check(is_equal_approx(bpm, 150.0), "old taps drop out of the window (got %s)" % bpm)

	print("tap_tempo_test: ", "FAIL" if _fails else "ok")
	quit(1 if _fails else 0)
