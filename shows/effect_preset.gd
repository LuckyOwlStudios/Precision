class_name EffectPreset
extends Resource
## An effect with its settings chosen, ready to drag onto the timeline:
## "Slow wide circle" = the Circle template at size 45°, 8 beats per loop.
## The built-in presets ship with the app; "Save as preset" on a clip makes
## your own, saved in the library folder.

@export var id: String = ""
@export var preset_name: String = ""
## Which EffectTemplates recipe this uses ("circle", "strobe"...).
@export var template: String = "circle"
## Only the settings that differ from the template's defaults need to be here.
@export var params: Dictionary = {}
## How long a new clip from this preset is, in beats.
@export var length_beats: float = 16.0
## Built-in presets can't be renamed or deleted.
var built_in := false


static func make(p_name: String, p_template: String, p_params: Dictionary = {}, p_length := 16.0) -> EffectPreset:
	var p := EffectPreset.new()
	p.preset_name = p_name
	p.template = p_template
	p.params = p_params
	p.length_beats = p_length
	return p
