class_name CueStack
extends Node
## A console-style cue list. go() fades to the next cue, back() to the previous one.
## Set up a look on your fixtures, then call record_cue() to store it, like
## pressing RECORD on a lighting desk.

signal cue_started(index: int, cue: LightCue)

## Where fixture paths are resolved from. Defaults to this node's parent.
@export var fixtures_root: Node
@export var cues: Array[LightCue] = []

var current: int = -1
var _tween: Tween


func go() -> void:
	go_to(current + 1)


func back() -> void:
	go_to(current - 1)


func go_to(index: int) -> void:
	if index < 0 or index >= cues.size():
		return
	current = index
	var cue := cues[index]
	if _tween:
		_tween.kill()
		_tween = null

	var fade := cue.fade_time > 0.0
	if fade:
		_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)

	var added := 0
	for path in cue.values:
		var fx := _root().get_node_or_null(NodePath(str(path)))
		if fx == null:
			push_warning("CueStack: fixture '%s' not found" % path)
			continue
		var props: Dictionary = cue.values[path]
		for prop in props:
			if fade:
				_tween.tween_property(fx, NodePath(str(prop)), props[prop], cue.fade_time)
				added += 1
			else:
				fx.set(prop, props[prop])

	if fade and added == 0: # an empty Tween throws an error when it starts
		_tween.kill()
		_tween = null
	cue_started.emit(index, cue)


## Snapshot every DMXFixture under fixtures_root into a new cue and append it.
func record_cue(cue_name: String = "", fade_time: float = 1.0) -> LightCue:
	var cue := LightCue.new()
	cue.cue_name = cue_name if not cue_name.is_empty() else "Cue %d" % (cues.size() + 1)
	cue.fade_time = fade_time
	var root := _root()
	for fx in root.find_children("*", "DMXFixture", true, false):
		cue.values[str(root.get_path_to(fx))] = fx.capture()
	cues.append(cue)
	return cue


func _root() -> Node:
	return fixtures_root if fixtures_root else get_parent()
