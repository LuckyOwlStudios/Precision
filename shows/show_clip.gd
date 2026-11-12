class_name ShowClip
extends Resource
## One block on the timeline: an effect running on some fixtures from `start`
## for `length` beats. Clips may overlap, on the same fixture or not: they all
## run together, layered in the order they are in the show.

@export var clip_name: String = ""
@export var template: String = "circle"
## Full settings (template defaults merged with the preset's).
@export var params: Dictionary = {}
## Effect preset this clip is linked to ("" = on its own). While linked, the
## clip plays the preset's current settings, so editing the preset changes
## every clip (in every song) linked to it. Changing the clip's own settings
## unlinks it.
@export var preset_id: String = ""
## Beats from the start of the song.
@export var start: float = 0.0
@export var length: float = 16.0
## Ease the effect in and out, in beats (0 = cut).
@export var fade_in: float = 0.0
@export var fade_out: float = 0.0
## Fixture paths (relative to the rig), in effect order: spread and chases run
## along this list.
@export var targets: PackedStringArray = PackedStringArray()


## The settings to play: the linked preset's if it still exists and is the same
## effect, otherwise the clip's own.
func effective_params(effects: EffectPresetLibrary) -> Dictionary:
	if not preset_id.is_empty() and effects and not EffectTemplates.is_reference(template):
		var p := effects.find(preset_id)
		if p and p.template == template:
			var d := EffectTemplates.defaults(template)
			d.merge(p.params, true)
			return d
	return params


func end() -> float:
	return start + length


## 0..1 strength at song beat `b` (fades), 0 outside the clip.
func weight_at(b: float) -> float:
	if b < start or b >= end():
		return 0.0
	var w := 1.0
	if fade_in > 0.0:
		w = minf(w, (b - start) / fade_in)
	if fade_out > 0.0:
		w = minf(w, (end() - b) / fade_out)
	return clampf(w, 0.0, 1.0)


static func from_preset(p: EffectPreset, at: float, fixtures: PackedStringArray) -> ShowClip:
	var c := ShowClip.new()
	c.clip_name = p.preset_name
	c.template = p.template
	c.preset_id = p.id
	c.params = EffectTemplates.defaults(p.template)
	c.params.merge(p.params.duplicate(true), true)
	c.start = at
	c.length = p.length_beats
	c.targets = fixtures.duplicate()
	return c


## Everything about the clip, for undo.
func to_data() -> Dictionary:
	return {"clip_name": clip_name, "template": template, "preset_id": preset_id, "params": params.duplicate(true), "start": start,
		"length": length, "fade_in": fade_in, "fade_out": fade_out, "targets": targets.duplicate()}


func set_data(d: Dictionary) -> void:
	clip_name = d.clip_name
	template = d.template
	preset_id = d.get("preset_id", "")
	params = (d.params as Dictionary).duplicate(true)
	start = d.start
	length = d.length
	fade_in = d.fade_in
	fade_out = d.fade_out
	targets = (d.targets as PackedStringArray).duplicate()
