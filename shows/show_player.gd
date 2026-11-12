class_name ShowPlayer
extends Node
## Plays the loaded song's show: every frame it works out what each clip under
## the playhead does to its fixtures and puts the result in the fixtures' `live`
## layer. The fixtures' own values (what you set in the inspector, a look or a
## cue) stay untouched underneath, so effects add on top of the look and the
## lights go back to it when the clips end.
##
## When the song has no show of its own, plays the built-in fallback look
## instead (StudioContext.fallback_show()).
##
## Runs before the fixtures each frame (process_priority -10 in the scene), and
## from the playhead whether or not the song is playing, so scrubbing
## the timeline previews the show.

## Set by StudioContext.
var ctx: StudioContext

var _driven: Array[DMXFixture] = [] ## fixtures that had a live layer last frame


func _process(_delta: float) -> void:
	if ctx == null:
		return
	var fallback := ctx.fallback_show()
	if fallback:
		evaluate(fallback, fposmod(ctx.position_beats, FallbackLooks.CYCLE_BEATS))
	else:
		evaluate(ctx.show, ctx.position_beats)


## Put the show at beat `b` into the fixtures. Public so tests can call it.
func evaluate(show: SongShow, b: float) -> void:
	var results := {} ## DMXFixture -> values dictionary
	if show:
		for clip in show.clips:
			var w := clip.weight_at(b)
			if w <= 0.0:
				continue
			var t := b - clip.start
			var n := clip.targets.size()
			for i in n:
				var fx := ctx.rig.get_node_or_null(NodePath(clip.targets[i])) as DMXFixture
				if fx == null or not EffectTemplates.supports(clip.template, fx):
					continue # removed from the rig, or re-patched into something that can't do it
				var v: Dictionary = results.get(fx, {})
				if v.is_empty():
					v = fx.capture()
					results[fx] = v
				var before := v.duplicate()
				if EffectTemplates.is_reference(clip.template):
					_apply_reference(clip, str(clip.targets[i]), fx, v)
				else:
					EffectTemplates.apply(clip.template, clip.effective_params(ctx.effects), t, i, n, fx, v)
				if w < 1.0:
					_blend(before, v, w)
	for fx in _driven:
		if is_instance_valid(fx) and not results.has(fx):
			fx.live.clear()
	_driven.clear()
	for fx: DMXFixture in results:
		fx.live = results[fx]
		_driven.append(fx)


## A "Position" or "Look" clip: copy what the saved preset says for this fixture.
## Looked up by id every frame, so editing the preset changes the show at once;
## a deleted preset (or a fixture it never covered) simply does nothing.
func _apply_reference(clip: ShowClip, path: String, fx: DMXFixture, v: Dictionary) -> void:
	var ref := str(clip.params.get("ref", ""))
	if ref.is_empty():
		return
	var saved: Dictionary
	if clip.template == "position":
		var pos := ctx.positions.find(ref)
		saved = pos.values.get(path, {}) if pos else {}
	else:
		var look := ctx.looks.find(ref)
		saved = look.values.get(path, {}) if look else {}
	for prop: String in saved:
		if clip.template == "position" or StudioContext.look_property_supported(prop, fx):
			v[prop] = saved[prop]


## Fade: mix each changed value from `before` toward `after` by `w`.
static func _blend(before: Dictionary, after: Dictionary, w: float) -> void:
	for k in after:
		var a: Variant = before.get(k)
		var z: Variant = after[k]
		if a == z:
			continue
		if z is PackedColorArray or z is PackedFloat32Array:
			after[k] = DMXFixture.blend_pixels(a, z, w)
		elif z is Color:
			var from: Color = a
			after[k] = from.lerp(z, w)
		elif z is float or z is int:
			var mixed := lerpf(float(a), float(z), w)
			after[k] = roundi(mixed) if z is int else mixed


## Let go of every fixture (when the show changes, for example).
func release_all() -> void:
	for fx in _driven:
		if is_instance_valid(fx):
			fx.live.clear()
	_driven.clear()
