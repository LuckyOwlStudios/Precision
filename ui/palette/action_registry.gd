class_name ActionRegistry
extends RefCounted
## The list of actions the Ctrl+K search (CommandPalette) can find and run.
## Lives on StudioContext as `ctx.actions`, so any feature registers its own:
##
##     ctx.actions.register(&"fixture.duplicate", "Duplicate", _duplicate,
##         {category = "Fixture", shortcut = "Shift+D", keywords = "copy clone",
##          enabled = func() -> bool: return ctx.selected != null})
##
## Options (all optional): category, shortcut (display text only), keywords,
## enabled (Callable returning bool; false hides the action).
## Registering an id again replaces the earlier action, so panels can safely
## register from setup() more than once. Use unregister() for actions that
## only exist while some panel does.

signal changed

var _actions: Dictionary[StringName, PaletteAction] = {}


func register(id: StringName, title: String, run: Callable, options: Dictionary = {}) -> PaletteAction:
	var a := PaletteAction.new()
	a.id = id
	a.title = title
	a.run = run
	a.category = str(options.get("category", ""))
	a.shortcut = shortcut_text(str(options.get("shortcut", "")))
	a.keywords = str(options.get("keywords", ""))
	var en: Variant = options.get("enabled", Callable())
	a.enabled = en if en is Callable else Callable()
	_actions[id] = a
	changed.emit()
	return a


func unregister(id: StringName) -> void:
	if _actions.erase(id):
		changed.emit()


func get_action(id: StringName) -> PaletteAction:
	return _actions.get(id)


func count() -> int:
	return _actions.size()


## Enabled actions matching `query`, best match first. An empty query lists
## everything, grouped by category then title. Space-separated words must all
## match ("go live" finds "Workspace › Go to Live").
static func _sort_by_name(a: PaletteAction, b: PaletteAction) -> bool:
	return a.display_title().naturalnocasecmp_to(b.display_title()) < 0


func search(query: String) -> Array[PaletteAction]:
	var scored: Array[Dictionary] = []
	for a: PaletteAction in _actions.values():
		if not a.is_enabled():
			continue
		var s := 0 if query.strip_edges().is_empty() else fuzzy_score(query, "%s %s %s" % [a.category, a.title, a.keywords])
		if s >= 0:
			scored.append({action = a, score = s})
	scored.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if x.score != y.score:
			return x.score > y.score
		return _sort_by_name(x.action, y.action))
	var out: Array[PaletteAction] = []
	for e in scored:
		out.append(e.action)
	return out


## Fuzzy score of `query` against `text`: -1 when it does not match, else
## higher is better. Each space-separated word of the query has to appear as a
## subsequence of the text (so "dpl" finds "Duplicate"); consecutive letters,
## letters at the start of a word and plain substring hits score more.
static func fuzzy_score(query: String, text: String) -> int:
	var hay := text.to_lower()
	var total := 0
	for word in query.to_lower().split(" ", false):
		var s := _word_score(word, hay)
		if s < 0:
			return -1
		total += s
	return total


static func _word_score(word: String, hay: String) -> int:
	var score := 0
	var pos := 0
	var prev := -2
	for i in word.length():
		var at := hay.find(word[i], pos)
		if at < 0:
			return -1
		if at == prev + 1:
			score += 10 # runs of consecutive letters
		if at == 0 or not _is_alnum(hay[at - 1]):
			score += 8 # start of a word
		score -= mini(at - pos, 5) # skipped letters cost a little
		prev = at
		pos = at + 1
	if hay.contains(word):
		score += 20
		if hay.begins_with(word):
			score += 10
	return score


static func _is_alnum(ch: String) -> bool:
	var c := ch.unicode_at(0)
	return (c >= 48 and c <= 57) or (c >= 97 and c <= 122) or c > 127


## Shortcuts are written "Ctrl+Z" in code; a Mac shows them as "Cmd+Z".
static func shortcut_text(text: String) -> String:
	if OS.get_name() == "macOS":
		return text.replace("Ctrl", "Cmd")
	return text
