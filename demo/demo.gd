extends Node2D
## Self-contained test: builds an Art-Net output, one fixture, a timeline
## (AnimationPlayer) and a cue stack in code, with an on-screen preview swatch.
##
## Controls:  SPACE = GO next cue   B = back   P = play/stop timeline   ESC = blackout
##
## Edit PROFILE_CHANNELS, START_ADDRESS and TARGET_IP to match your light.

const TARGET_IP := "255.255.255.255"
const START_ADDRESS := 1
const PROFILE_CHANNELS := ["dimmer", "red", "green", "blue", "white", "strobe", "mode"]

var universe: DMXUniverse
var fixture: DMXFixture
var player: AnimationPlayer
var cues: CueStack
var preview: ColorRect
var status: Label


func _ready() -> void:
	var out := ArtNetOutput.new()
	out.name = "ArtNet"
	out.target_ip = TARGET_IP
	add_child(out)

	universe = DMXUniverse.new()
	universe.name = "Universe0"
	universe.output = out
	add_child(universe)

	var profile := FixtureProfile.new()
	profile.fixture_name = "Generic RGBW Par (7ch)"
	profile.channels = PackedStringArray(PROFILE_CHANNELS)
	profile.defaults = {"mode": 0}

	fixture = DMXFixture.new()
	fixture.name = "Par1"
	fixture.universe = universe
	fixture.profile = profile
	fixture.start_address = START_ADDRESS
	add_child(fixture)

	_build_ui()
	_build_timeline()
	_build_cues()


func _build_timeline() -> void:
	var anim := Animation.new()
	anim.length = 8.0
	anim.loop_mode = Animation.LOOP_LINEAR

	var c := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(c, NodePath("Par1:color"))
	anim.track_insert_key(c, 0.0, Color.RED)
	anim.track_insert_key(c, 2.0, Color.ORANGE)
	anim.track_insert_key(c, 4.0, Color.MAGENTA)
	anim.track_insert_key(c, 6.0, Color.CYAN)
	anim.track_insert_key(c, 8.0, Color.RED)

	# Dimmer "breathing" pulse every second
	var d := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(d, NodePath("Par1:dimmer"))
	for i in 9:
		anim.track_insert_key(d, float(i), 1.0)
		if i < 8:
			anim.track_insert_key(d, i + 0.5, 0.25)

	var lib := AnimationLibrary.new()
	lib.add_animation("show", anim)
	player = AnimationPlayer.new()
	player.name = "Timeline"
	add_child(player) # root_node defaults to "..", so "Par1:color" resolves from here
	player.add_animation_library("", lib)


func _build_cues() -> void:
	cues = CueStack.new()
	cues.name = "Cues"
	cues.fixtures_root = self
	add_child(cues)
	cues.cue_started.connect(func(i, cue): status.text = "Cue %d: %s" % [i + 1, cue.cue_name])

	cues.cues.append(_cue("Warm wash", 2.0, Color(1.0, 0.55, 0.2), 1.0))
	cues.cues.append(_cue("Deep blue", 3.0, Color(0.05, 0.1, 1.0), 0.8))
	cues.cues.append(_cue("Snap to white", 0.0, Color.WHITE, 1.0))
	cues.cues.append(_cue("Fade out", 4.0, Color.WHITE, 0.0))


func _cue(n: String, fade: float, col: Color, dim: float) -> LightCue:
	var cue := LightCue.new()
	cue.cue_name = n
	cue.fade_time = fade
	cue.values = {"Par1": {"color": col, "dimmer": dim}}
	return cue


func _build_ui() -> void:
	preview = ColorRect.new()
	preview.position = Vector2(40, 40)
	preview.size = Vector2(200, 200)
	add_child(preview)

	status = Label.new()
	status.position = Vector2(40, 260)
	status.text = "SPACE = GO   B = back   P = timeline   ESC = blackout"
	add_child(status)


func _process(_delta: float) -> void:
	var k := fixture.dimmer
	preview.color = Color(fixture.color.r * k, fixture.color.g * k, fixture.color.b * k)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE:
			player.stop()
			cues.go()
		KEY_B:
			player.stop()
			cues.back()
		KEY_P:
			if player.is_playing():
				player.stop()
				status.text = "Timeline stopped"
			else:
				player.play("show")
				status.text = "Timeline playing"
		KEY_ESCAPE:
			player.stop()
			cues.stop() # otherwise a running fade would bring the light back up
			fixture.dimmer = 0.0
			status.text = "Blackout"
