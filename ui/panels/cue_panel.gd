class_name CuePanel
extends MarginContainer
## The cue list: record the current look, then GO through cues with fades.
## Wraps the addon's CueStack.

var ctx: StudioContext

@onready var _list: ItemList = %List
@onready var _empty: Control = %Empty
@onready var _go: Button = %Go


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.cues_changed.connect(_rebuild)
	ctx.cue_stack.cue_started.connect(func(_i: int, _c: LightCue) -> void: _rebuild())
	_rebuild()


func _ready() -> void:
	_list.item_activated.connect(func(i: int) -> void: ctx.go_cue(i))
	%Record.pressed.connect(func() -> void: ctx.record_cue())
	_go.pressed.connect(func() -> void: ctx.go_cue())


func _rebuild() -> void:
	if ctx == null:
		return
	_list.clear()
	var cues := ctx.cue_stack.cues
	for i in cues.size():
		var c := cues[i]
		var live := i == ctx.cue_stack.current
		var idx := _list.add_item("%2d   %s      %.1fs" % [i + 1, c.cue_name, c.fade_time])
		if live:
			_list.set_item_custom_fg_color(idx, UIPalette.ACCENT)
	_list.visible = not cues.is_empty()
	_empty.visible = cues.is_empty()
	_go.disabled = cues.is_empty()
