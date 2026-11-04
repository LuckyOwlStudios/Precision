extends SceneTree
## Command-line version of bake_theme.gd:
##   godot --headless --script res://ui/theme/bake_theme_cli.gd


func _init() -> void:
	var out := "res://ui/theme/lucky_dark.tres"
	var theme_builder: GDScript = load("res://ui/theme/lucky_theme.gd")
	var err := ResourceSaver.save(theme_builder.build(), out)
	print("Saved " + out if err == OK else "Error %d saving %s" % [err, out])
	quit(0 if err == OK else 1)
