class_name LightCue
extends Resource
## A stored look: what each fixture should be doing, plus how long to fade there.

@export var cue_name: String = ""
@export var fade_time: float = 1.0
## Fixture path (relative to the CueStack's fixtures_root) -> { property: value }
## e.g. { "Par1": { "color": Color.BLUE, "dimmer": 1.0 } }
@export var values: Dictionary = {}
