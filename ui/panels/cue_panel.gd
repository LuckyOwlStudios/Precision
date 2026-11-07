class_name CuePanel
extends MarginContainer
## The cue list: record the current look, then GO through cues with fades.
## Wraps the addon's CueStack.

var ctx: StudioContext

@onready var _list: ItemList = %List
@onready var _empty: Control = %Empty
@onready var _go: Button = %Go
@onready var _looks: ItemList = %Looks
@onready var _looks_empty: Label = %LooksEmpty
@onready var _look_name: LineEdit = %LookName


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.cues_changed.connect(_rebuild)
	ctx.cue_stack.cue_started.connect(func(_i: int, _c: LightCue) -> void: _rebuild())
	ctx.looks_changed.connect(_rebuild_looks)
	_rebuild()
	_rebuild_looks()


func _ready() -> void:
	_list.item_activated.connect(func(i: int) -> void: ctx.go_cue(i))
	%Record.pressed.connect(func() -> void: ctx.record_cue())
	_go.pressed.connect(func() -> void: ctx.go_cue())
	_looks.item_activated.connect(func(i: int) -> void: ctx.apply_look(ctx.looks.looks[i]))
	_looks.item_selected.connect(func(i: int) -> void: _look_name.text = ctx.looks.looks[i].look_name)
	_looks.empty_clicked.connect(func(_p: Vector2, _b: int) -> void: _looks.deselect_all())
	%SaveLook.pressed.connect(_save_look)
	_look_name.text_submitted.connect(func(_t: String) -> void: _save_look())
	%RenameLook.pressed.connect(func() -> void:
		var sel := _looks.get_selected_items()
		if not sel.is_empty():
			ctx.rename_look(ctx.looks.looks[sel[0]], _look_name.text))
	%DeleteLook.pressed.connect(func() -> void:
		var sel := _looks.get_selected_items()
		if not sel.is_empty():
			ctx.delete_look(ctx.looks.looks[sel[0]]))


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


func _save_look() -> void:
	ctx.save_look(_look_name.text)
	_look_name.clear()


func _rebuild_looks() -> void:
	if ctx == null:
		return
	var keep := _looks.get_selected_items()
	_looks.clear()
	var shelf := ctx.looks.looks
	for look in shelf:
		var idx := _looks.add_item(look.look_name)
		if look == ctx.applied_look():
			_looks.set_item_custom_fg_color(idx, UIPalette.ACCENT)
	if not keep.is_empty() and keep[0] < shelf.size():
		_looks.select(keep[0])
	_looks.visible = not shelf.is_empty()
	_looks_empty.visible = shelf.is_empty()
	%RenameLook.disabled = shelf.is_empty()
	%DeleteLook.disabled = shelf.is_empty()
