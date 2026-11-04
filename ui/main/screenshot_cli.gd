extends SceneTree
## Dev helper: opens the main window, loads the demo rig and saves a PNG.
##   godot --path . --script res://ui/main/screenshot_cli.gd -- out.png [workspace 0-2] [empty|rig] [right tab]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://screenshot.png"
	var ws := int(args[1]) if args.size() > 1 else 1
	var empty := args.size() > 2 and args[2] == "empty"
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	if not empty:
		ctx.load_demo_rig()
		ctx.select(ctx.fixtures()[4])
		ctx.record_cue()
		ctx.cue_stack.cues[0].cue_name = "Warm intro"
		ctx.record_cue()
		ctx.cue_stack.cues[1].cue_name = "Drop: full colour"
		ctx.cues_changed.emit()
		ctx.seek(37.0)
	ctx.set_workspace(ws)
	if args.size() > 3:
		(main.get_node("%RightTabs") as TabContainer).current_tab = int(args[3])
	for i in 30:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	quit()
