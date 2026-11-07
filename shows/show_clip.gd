class_name ShowClip
extends Resource
## One block on the timeline: an effect running on some fixtures from `start`
## for `length` beats. Clips may overlap, on the same fixture or not: they all
## run together, layered in the order they are in the show.

@export var clip_name: String = ""
@export var template: String = "circle"
## Full settings (template defaults merged with the preset's).
@export var params: Dictionary = {}
## Beats from the start of the song.
@export var start: float = 0.0
@export var length: float = 16.0
## Ease the effect in and out, in beats (0 = cut).
@export var fade_in: float = 0.0
@export var fade_out: float = 0.0
## Fixture paths (relative to the rig), in effect order: spread and chases run
## along this list.
@export var targets: PackedStringArray = PackedStringArray()


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
	c.params = EffectTemplates.defaults(p.template)
	c.params.merge(p.params.duplicate(true), true)
	c.start = at
	c.length = p.length_beats
	c.targets = fixtures.duplicate()
	return c


## Everything about the clip, for undo.
func to_data() -> Dictionary:
	return {"clip_name": clip_name, "template": template, "params": params.duplicate(true), "start": start,
		"length": length, "fade_in": fade_in, "fade_out": fade_out, "targets": targets.duplicate()}


func set_data(d: Dictionary) -> void:
	clip_name = d.clip_name
	template = d.template
	params = (d.params as Dictionary).duplicate(true)
	start = d.start
	length = d.length
	fade_in = d.fade_in
	fade_out = d.fade_out
	targets = (d.targets as PackedStringArray).duplicate()
