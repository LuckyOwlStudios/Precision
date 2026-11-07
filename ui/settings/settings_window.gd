class_name SettingsWindow
extends Window
## The Settings window, opened from the button in the header. The layout lives
## in settings_window.tscn; each setting is one row there plus one block here
## that shows AppSettings and writes the person's choice back. It listens to
## AppSettings, so changing a setting anywhere keeps this window in step.
##
## To add a setting: add its row in the scene, add a var to AppSettings, then
## give it a "_sync_x" and a handler in _ready() below.

@onready var _quality_label: ResetLabel = %QualityLabel
@onready var _quality_buttons: Array[Button] = [%Low, %Medium, %High, %Ultra]
@onready var _units_label: ResetLabel = %UnitsLabel
@onready var _unit_buttons: Array[Button] = [%Metric, %Imperial] ## indexed by Units.System
@onready var _language_label: ResetLabel = %LanguageLabel
@onready var _language: OptionButton = %Language


func _ready() -> void:
	close_requested.connect(hide)
	%Close.pressed.connect(hide)
	%ResetAll.pressed.connect(AppSettings.reset_to_defaults)

	# Graphics quality.
	for q in _quality_buttons.size():
		_quality_buttons[q].pressed.connect(func() -> void: AppSettings.quality = q as StageLook.Quality)
	_quality_label.default_text = tr(StageLook.QUALITY_NAMES[AppSettings.DEFAULT_QUALITY])
	_quality_label.reset_requested.connect(func() -> void: AppSettings.quality = AppSettings.DEFAULT_QUALITY)
	%ForwardPlusNote.visible = RenderingServer.get_current_rendering_method() != "forward_plus"

	# Units.
	for u in _unit_buttons.size():
		_unit_buttons[u].pressed.connect(func() -> void: AppSettings.units = u as Units.System)
	_units_label.default_text = tr(_unit_buttons[AppSettings.DEFAULT_UNITS].text)
	_units_label.reset_requested.connect(func() -> void: AppSettings.units = AppSettings.DEFAULT_UNITS)

	# Language: one entry per column of locale/strings.csv.
	for lang in Localization.languages():
		_language.add_item(lang.name)
		_language.set_item_metadata(_language.item_count - 1, lang.code)
	_language_label.default_text = Localization.languages()[0].name
	_language.item_selected.connect(func(i: int) -> void:
		AppSettings.language = str(_language.get_item_metadata(i)))
	_language_label.reset_requested.connect(func() -> void: AppSettings.language = AppSettings.DEFAULT_LANGUAGE)

	AppSettings.hub().changed.connect(func(_key: StringName) -> void: _sync())
	_sync()


func open() -> void:
	_sync()
	popup_centered()


func _sync() -> void:
	for i in _quality_buttons.size():
		_quality_buttons[i].set_pressed_no_signal(i == AppSettings.quality)
	_quality_label.modified = AppSettings.quality != AppSettings.DEFAULT_QUALITY
	for i in _unit_buttons.size():
		_unit_buttons[i].set_pressed_no_signal(i == AppSettings.units)
	_units_label.modified = AppSettings.units != AppSettings.DEFAULT_UNITS
	for i in _language.item_count:
		if _language.get_item_metadata(i) == AppSettings.language:
			_language.select(i)
	_language_label.modified = AppSettings.language != AppSettings.DEFAULT_LANGUAGE
