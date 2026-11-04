class_name CuePanel
extends MarginContainer
## The cue list: record the current look, then GO through cues with fades.
## Wraps the addon's CueStack.

var ctx: StudioContext

var _list := ItemList.new()
var _empty: Control
var _go := Button.new()


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.cues_changed.connect(_rebuild)
	ctx.cue_stack.cue_started.connect(func(_i: int, _c: LightCue) -> void: _rebuild())
	_rebuild()


func _ready() -> void:
	add_theme_constant_override("margin_left", UIPalette.COLUMN_PAD)
	add_theme_constant_override("margin_right", UIPalette.COLUMN_PAD)
	add_theme_constant_override("margin_top", 16)
	add_theme_constant_override("margin_bottom", 16)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	col.add_child(UIKit.section("Cue list"))

	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(i: int) -> void: ctx.go_cue(i))
	col.add_child(_list)
	_empty = UIKit.empty_state("No cues", "Set a look on the stage, then press Record to store it as a cue.")
	col.add_child(_empty)

	var row := HBoxContainer.new()
	var rec := Button.new()
	rec.text = "Record"
	rec.tooltip_text = "Store the current look of every fixture as a new cue"
	rec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rec.pressed.connect(func() -> void: ctx.record_cue())
	row.add_child(rec)
	_go.text = "GO"
	_go.theme_type_variation = &"AccentButton"
	_go.tooltip_text = "Fade to the next cue"
	_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_go.pressed.connect(func() -> void: ctx.go_cue())
	row.add_child(_go)
	col.add_child(row)


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
