extends SceneTree
## Settings, units and languages. Run:
##   godot --headless --path . --script res://tests/settings_test.gd
## Uses (and then restores) the real user://settings.cfg.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _initialize() -> void:
	var saved_q := AppSettings.quality
	var saved_u := AppSettings.units
	var saved_l := AppSettings.language

	# Units
	AppSettings.units = Units.System.METRIC
	_check(Units.length_text(3.2) == "3.20 m", "metric text")
	_check(is_equal_approx(Units.to_display(2.0), 2.0), "metric display")
	AppSettings.units = Units.System.IMPERIAL
	_check(Units.length_text(3.2004) == "10' 6\"", "imperial text: " + Units.length_text(3.2004))
	_check(Units.length_text(-0.3048) == "-1' 0\"", "negative feet")
	_check(is_equal_approx(Units.from_display(Units.to_display(1.234)), 1.234), "round trip")
	_check(is_equal_approx(Units.nice_step(0.3), 0.3048 * 0.5) or is_equal_approx(Units.nice_step(0.3), 0.3048), "nice step is a round number of feet")

	# A unit box keeps exact metres through a unit switch and does not drift.
	var box := UnitSpinBox.new()
	box.min_value = -30.0
	box.max_value = 30.0
	box.step = 0.01
	AppSettings.units = Units.System.METRIC
	root.add_child(box)
	await process_frame
	var got: Array[float] = []
	box.metres_changed.connect(func(m: float) -> void: got.append(m))
	box.set_metres(1.2345)
	_check(got.is_empty(), "programmatic set doesn't report a user edit")
	AppSettings.units = Units.System.IMPERIAL
	_check(box.suffix == " ft", "suffix follows units")
	_check(is_equal_approx(box.get_metres(), 1.2345), "exact metres survive the switch: %s value %s step %s" % [box.get_metres(), box.value, box.step])
	box.value = 10.0 # the person types 10 ft
	_check(got.size() == 1 and is_equal_approx(got[0], 3.048), "typed feet become metres")
	AppSettings.units = Units.System.METRIC
	_check(is_equal_approx(box.get_metres(), 3.048) and box.suffix == " m", "back to metric")
	box.queue_free()

	# Language
	_check(Localization.has("en"), "English is available")
	_check(Localization.closest("fr_CA") == "en", "unknown language falls back to English")
	AppSettings.language = "en"
	_check(TranslationServer.get_locale().begins_with("en"), "locale applied")

	# Persistence
	AppSettings.quality = StageLook.Quality.ULTRA
	AppSettings.units = Units.System.IMPERIAL
	var cfg := ConfigFile.new()
	_check(cfg.load(AppSettings.SAVE_PATH) == OK, "settings file written")
	_check(int(cfg.get_value("graphics", "quality", -1)) == StageLook.Quality.ULTRA, "quality saved")
	_check(int(cfg.get_value("units", "system", -1)) == Units.System.IMPERIAL, "units saved")
	var seen: Array[StringName] = []
	AppSettings.hub().changed.connect(func(k: StringName) -> void: seen.append(k))
	AppSettings.quality = StageLook.Quality.LOW
	_check(seen == [&"quality"], "change signal names the setting")

	# Settings window builds and follows the settings
	var win: SettingsWindow = load("res://ui/settings/settings_window.tscn").instantiate()
	root.add_child(win)
	await process_frame
	AppSettings.quality = StageLook.Quality.MEDIUM
	_check(win._quality_buttons[StageLook.Quality.MEDIUM].button_pressed, "window shows the quality")
	win._unit_buttons[Units.System.METRIC].pressed.emit()
	_check(AppSettings.units == Units.System.METRIC, "window button sets units")

	# Drawing sheet: rulers, grid and labels follow the units too.
	AppSettings.units = Units.System.IMPERIAL
	_check(DraftingOverlay._len(3.048) == "10.00 ft", "overlay label in feet: " + DraftingOverlay._len(3.048))
	var feet_step := DraftingOverlay.pick_step(DraftingOverlay.minor_steps(), 0.3)
	_check(is_equal_approx(feet_step, 0.3048), "grid lands on whole feet: %s" % feet_step)
	AppSettings.units = Units.System.METRIC
	_check(DraftingOverlay._len(3.048) == "3.05 m", "overlay label in metres")

	# The real window: settings button opens it; quality moved out of the stage view.
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	_check(main.get_node_or_null("%Search") == null, "search bar replaced")
	(main.get_node("%SettingsButton") as Button).pressed.emit()
	await process_frame
	_check((main.get_node("%SettingsWindow") as Window).visible, "settings button opens the window")
	AppSettings.quality = StageLook.Quality.LOW
	_check((main.get_node("%StageView") as StageView).look.quality == StageLook.Quality.LOW, "stage follows quality")
	AppSettings.units = Units.System.IMPERIAL
	await process_frame
	var px: UnitSpinBox = main.get_node("%Inspector").get_node("%PositionX")
	_check(px.suffix == " ft", "inspector boxes follow units")

	AppSettings.quality = saved_q
	AppSettings.units = saved_u
	AppSettings.language = saved_l
	print("settings test: %s" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(1 if _fails > 0 else 0)
