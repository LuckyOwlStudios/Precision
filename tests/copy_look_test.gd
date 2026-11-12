extends SceneTree
## Checks copy / paste of a fixture's look: properties match by channel name,
## paste works on one or many fixtures, and is one undo step. Run from the
## project folder:
##   godot --headless --path . --script res://tests/copy_look_test.gd

var failures := 0
var checks := 0


func check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)


func _profile(channels: Array[String]) -> FixtureProfile:
	var p := FixtureProfile.new()
	p.channels = PackedStringArray(channels)
	return p


func _init() -> void:
	var main: Control = (load("res://ui/main/main_window.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ctx: StudioContext = main.get_node("%Studio")

	var head := DMXFixture.new()
	head.profile = _profile(["dimmer", "red", "green", "blue", "pan", "tilt"])
	var par := DMXFixture.new()
	par.profile = _profile(["red", "green", "blue"])
	var dim_par := DMXFixture.new()
	dim_par.profile = _profile(["dimmer", "red", "green", "blue"])
	for fx in [head, par, dim_par]:
		ctx.rig.add_child(fx)

	head.dimmer = 0.4
	head.color = Color.RED
	head.pan = 0.9
	head.tilt = 0.1
	par.pan = 0.5
	ctx.history.clear_history()

	check(ctx.paste_look([par]) == 0, "paste with nothing copied does nothing")
	check(ctx.copy_look(head), "copy from a moving head")
	check(ctx.look_clipboard.has("pan"), "clipboard keeps pan/tilt from a head")

	var n := ctx.paste_look([par, dim_par])
	check(n == 2, "pasted onto two fixtures")
	check(par.color == Color.RED and dim_par.color == Color.RED, "colour pasted")
	check(is_equal_approx(dim_par.dimmer, 0.4), "dimmer pasted where the profile has one")
	check(is_equal_approx(par.pan, 0.5), "pan not pasted onto a fixture without pan")

	ctx.undo()
	check(par.color == Color.WHITE and dim_par.color == Color.WHITE and is_equal_approx(dim_par.dimmer, 1.0), "one undo reverts all pasted fixtures")
	ctx.redo()
	check(par.color == Color.RED, "redo pastes again")

	# Copying from a par leaves out pan/tilt, so a head keeps its aim.
	par.color = Color.GREEN
	ctx.copy_look(par)
	check(not ctx.look_clipboard.has("pan"), "par look has no pan")
	ctx.paste_look([head])
	check(head.color == Color.GREEN and is_equal_approx(head.pan, 0.9), "head takes colour, keeps its aim")

	print("\n%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)
