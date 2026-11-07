class_name Localization
extends RefCounted
## Languages. All the app's words live in locale/strings.csv: one row per
## phrase, one column per language. The English wording itself is the key, so
## the scenes keep readable text and English works with no lookup at all; a
## Label or Button whose text matches a row is translated by Godot on its own.
## Text built in code goes through tr("...") (or Localization.t()).
##
## Adding a language is a new column: copy the `en` column, translate it, give
## the column a locale code as header ("de", "es", "pt_BR") and set the row
## LANGUAGE_NAME to the language written in itself ("Deutsch"). It then shows up
## in Settings > Language with no code changes. See docs/localization.md.
##
## The CSV is read here at start-up rather than imported by the editor, so
## editing it takes effect on the next run with no re-import step.

const CSV_PATH := "res://locale/strings.csv"
const NAME_KEY := "LANGUAGE_NAME"

static var _names: Dictionary = {} ## locale code -> name of the language in itself
static var _loaded := false


## [{code, name}], English first, the rest in the order of the CSV columns.
static func languages() -> Array[Dictionary]:
	_load()
	var out: Array[Dictionary] = []
	for code: String in _names:
		out.append({"code": code, "name": _names[code]})
	return out


static func has(code: String) -> bool:
	_load()
	return _names.has(code)


## The best available match for a code from the OS or an old save:
## "de_AT" -> "de" if only "de" exists, anything unknown -> "en".
static func closest(code: String) -> String:
	_load()
	if _names.has(code):
		return code
	var base := code.split("_")[0]
	if _names.has(base):
		return base
	for have: String in _names:
		if have.split("_")[0] == base:
			return have
	return AppSettings.DEFAULT_LANGUAGE


static func system_language() -> String:
	return OS.get_locale()


static func apply(code: String) -> void:
	_load()
	TranslationServer.set_locale(closest(code))


## Translate a phrase for code that is not a Node (a Node has tr()).
static func t(text: String) -> String:
	return TranslationServer.translate(text)


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_names[AppSettings.DEFAULT_LANGUAGE] = "English" # works even if the file is missing
	var file := FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		push_warning("Localization: %s not found, English only" % CSV_PATH)
		return
	var header := file.get_csv_line()
	var translations: Array[Translation] = [] # column i of the header -> translation (key column is null)
	for i in header.size():
		if i == 0 or header[i].strip_edges() == "":
			translations.append(null)
			continue
		var tr_res := Translation.new()
		tr_res.locale = header[i].strip_edges()
		translations.append(tr_res)
		_names[tr_res.locale] = tr_res.locale
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 2 or row[0].strip_edges() == "":
			continue
		for i in mini(row.size(), translations.size()):
			var res := translations[i]
			if res == null or row[i] == "":
				continue
			if row[0] == NAME_KEY:
				_names[res.locale] = row[i]
			else:
				res.add_message(row[0], row[i])
	for res in translations:
		if res:
			TranslationServer.add_translation(res)
