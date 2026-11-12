class_name AppSettings
extends RefCounted
## Preferences that belong to this computer and this person, not to a show:
## graphics quality, measurement units, language. Saved in user://settings.cfg.
##
## Static on purpose, so any panel can read a setting without being handed an
## object (no autoload needed, and it works from test scripts too):
##   AppSettings.units                         # read
##   AppSettings.units = Units.System.IMPERIAL # write: saves and notifies
##   AppSettings.hub().changed.connect(_on_setting_changed)
##
## To add a setting: add a var below (with a DEFAULT_ const), load and save it in
## load_saved() / save(), then add a row for it in ui/settings/settings_window.tscn.

## The one thing to connect to. `changed` fires with the setting's name
## ("quality", "units", "language") after it was saved.
class Hub extends RefCounted:
	signal changed(key: StringName)

const SAVE_PATH := "user://settings.cfg"
const LEGACY_LOOK_PATH := "user://stage_look.cfg" ## quality used to be saved here

const DEFAULT_QUALITY := StageLook.Quality.HIGH
const DEFAULT_UNITS := Units.System.METRIC
const DEFAULT_LANGUAGE := "en"

const DEFAULT_FALLBACK_LOOKS := true

static var _hub := Hub.new()
static var _loaded := false
static var _loading := false ## true while load_saved() fills the values: no saving, no signals

## Render quality of the 3D stage (see StageLook.Quality).
static var quality: StageLook.Quality = DEFAULT_QUALITY:
	get:
		_ensure_loaded()
		return quality
	set(v):
		_ensure_loaded()
		v = clampi(v, 0, StageLook.Quality.ULTRA) as StageLook.Quality
		if v == quality:
			return
		quality = v
		_changed(&"quality")

## Metric or imperial for every length shown in the app.
static var units: Units.System = DEFAULT_UNITS:
	get:
		_ensure_loaded()
		return units
	set(v):
		_ensure_loaded()
		if v == units:
			return
		units = v
		_changed(&"units")

## Play a built-in beat-reactive look when a song has no show of its own.
static var fallback_looks: bool = DEFAULT_FALLBACK_LOOKS:
	get:
		_ensure_loaded()
		return fallback_looks
	set(v):
		_ensure_loaded()
		if v == fallback_looks:
			return
		fallback_looks = v
		_changed(&"fallback_looks")

## Locale code, a column of locale/strings.csv ("en", later "de", "es", ...).
static var language: String = DEFAULT_LANGUAGE:
	get:
		_ensure_loaded()
		return language
	set(v):
		_ensure_loaded()
		if v == language:
			return
		language = v
		Localization.apply(language)
		_changed(&"language")


static func hub() -> Hub:
	_ensure_loaded()
	return _hub


## Read the file once. Also applies the saved language, so the first screen
## already comes up translated.
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	load_saved()


static func load_saved() -> void:
	_loaded = true
	_loading = true
	var cfg := ConfigFile.new()
	var found := cfg.load(SAVE_PATH) == OK
	var legacy := ConfigFile.new()
	var q: Variant = null
	if found and cfg.has_section_key("graphics", "quality"):
		q = cfg.get_value("graphics", "quality")
	elif legacy.load(LEGACY_LOOK_PATH) == OK and legacy.has_section_key("stage", "quality"):
		q = legacy.get_value("stage", "quality") # carry over the old choice
	quality = clampi(int(q if q != null else DEFAULT_QUALITY), 0, StageLook.Quality.ULTRA) as StageLook.Quality
	units = Units.System.IMPERIAL if int(cfg.get_value("units", "system", DEFAULT_UNITS)) == Units.System.IMPERIAL else Units.System.METRIC
	fallback_looks = bool(cfg.get_value("shows", "fallback_looks", DEFAULT_FALLBACK_LOOKS))
	language = Localization.closest(str(cfg.get_value("language", "locale", Localization.system_language())))
	Localization.apply(language)
	_loading = false


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("units", "system", units)
	cfg.set_value("shows", "fallback_looks", fallback_looks)
	cfg.set_value("language", "locale", language)
	cfg.save(SAVE_PATH)


static func reset_to_defaults() -> void:
	quality = DEFAULT_QUALITY
	units = DEFAULT_UNITS
	fallback_looks = DEFAULT_FALLBACK_LOOKS
	language = DEFAULT_LANGUAGE


static func _changed(key: StringName) -> void:
	if _loading:
		return
	save()
	_hub.changed.emit(key)
