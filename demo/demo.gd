extends Node2D
## Self-contained test: an Art-Net output, one fixture, a timeline
## (AnimationPlayer) and a cue stack, with an on-screen preview swatch.
## Everything lives in demo.tscn; this script only handles the keys.
##
## Controls:  SPACE = GO next cue   B = back   P = play/stop timeline   ESC = blackout
##
## To match your light, select ArtNet (Target Ip) and Par1 (Profile channels,
## Start Address) in the scene and change them in the Inspector. The colour
## and dimmer keys are on the Timeline node; the cues are on the Cues node.

@onready var fixture: DMXFixture = $Par1
@onready var player: AnimationPlayer = $Timeline
@onready var cues: CueStack = $Cues
@onready var preview: ColorRect = $Preview
@onready var status: Label = $Status


func _ready() -> void:
	cues.cue_started.connect(func(i: int, cue: LightCue) -> void: status.text = "Cue %d: %s" % [i + 1, cue.cue_name])


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
