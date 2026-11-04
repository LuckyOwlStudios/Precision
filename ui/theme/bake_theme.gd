@tool
extends EditorScript
## Regenerates lucky_dark.tres from UIPalette + LuckyTheme.
## After changing a colour: open this file in the Script editor and press
## File > Run (Ctrl+Shift+X). The editor picks up the new theme right away.
##
## From a terminal: godot --headless --script res://ui/theme/bake_theme_cli.gd

const OUT := "res://ui/theme/lucky_dark.tres"


func _run() -> void:
	var err := ResourceSaver.save(LuckyTheme.build(), OUT)
	if err == OK:
		print("Saved ", OUT)
	else:
		push_error("Could not save %s (error %d)" % [OUT, err])
