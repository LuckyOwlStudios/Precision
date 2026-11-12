class_name PaletteAction
extends RefCounted
## One thing the person can do, as listed in the Ctrl+K action search.
## Made by ActionRegistry.register(); features do not construct these directly.

var id: StringName
var title: String
## Grouping shown before the title ("Edit", "View", "Fixture"). Optional.
var category: String
## Shortcut as text for display only ("Ctrl+Z", "Alt+H"). The shortcut itself is
## still handled by whoever owns it; this just tells the person about it.
var shortcut: String
## Extra words that should find this action ("delete" for Remove, "undo" for Revert).
var keywords: String
var run: Callable
## Optional Callable returning bool. When it returns false the action is left
## out of the list (nothing selected, nothing to undo, ...). Invalid = always on.
var enabled: Callable


func is_enabled() -> bool:
	return run.is_valid() and (not enabled.is_valid() or enabled.call() as bool)


## "Edit › Undo", or just the title when there is no category.
func display_title() -> String:
	return title if category.is_empty() else "%s › %s" % [category, title]


func execute() -> void:
	if is_enabled():
		run.call()
