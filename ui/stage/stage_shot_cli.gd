extends SceneTree
## Dev helper: renders the 3D stage alone with the demo rig and saves a PNG,
## for checking the look at a given haze and quality.
##   godot --path . --script res://ui/stage/stage_shot_cli.gd -- out.png [haze 0-1] [quality 0-3] [yaw] [pitch] [distance]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://stage.png"
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")
	ctx.load_demo_rig()
	ctx.set_workspace(StudioContext.Workspace.PROGRAM)
	var view: StageView = _find_view(main)
	# Take the stage view out of the layout and fill the window with it.
	view.get_parent().remove_child(view)
	main.visible = false # keeps running: it owns the rig and the studio state
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(holder)
	holder.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if args.size() > 1:
		view.look.haze = float(args[1])
	if args.size() > 2:
		view.look.quality = int(args[2]) as StageLook.Quality
	if args.size() > 5:
		view.set_orbit(float(args[3]), float(args[4]), float(args[5]))
	for i in 40:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size())
	quit()


func _find_view(n: Node) -> StageView:
	if n is StageView:
		return n
	for c in n.get_children():
		var v := _find_view(c)
		if v:
			return v
	return null
