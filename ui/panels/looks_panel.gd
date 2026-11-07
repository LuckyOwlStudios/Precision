class_name LooksPanel
extends MarginContainer
## The Looks shelf as a grid of big tiles. One panel, two jobs:
##   Program (live_mode off) - design: click selects, double-click or Fire fades
##     to it, and the tools below save, edit, rename and delete looks.
##   Live (live_mode on) - perform: tiles are bigger, one tap fires the look,
##     and the design tools are gone so nothing gets changed by accident.

## Show it as the performance surface (Live workspace) instead of the editor.
@export var live_mode := false

var ctx: StudioContext

var _selected: Look
var _group := ButtonGroup.new()

@onready var _grid: HFlowContainer = %Grid
@onready var _empty: Label = %Empty
@onready var _scroll: ScrollContainer = %Scroll
@onready var _look_name: LineEdit = %LookName
@onready var _edit_banner: PanelContainer = %EditBanner


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.looks_changed.connect(_rebuild)
	ctx.look_editing_changed.connect(func(_l: Look) -> void: _rebuild())
	_rebuild()


func _ready() -> void:
	%Design.visible = not live_mode
	_look_name.text_changed.connect(func(_t: String) -> void: _update_buttons())
	_look_name.text_submitted.connect(func(_t: String) -> void:
		if not %SaveLook.disabled:
			_save_look())
	%SaveLook.pressed.connect(_save_look)
	%FireLook.pressed.connect(func() -> void: _fire(_selected))
	%EditLook.pressed.connect(func() -> void:
		if _selected:
			ctx.begin_look_edit(_selected))
	%RenameLook.pressed.connect(func() -> void:
		if _selected:
			ctx.rename_look(_selected, _look_name.text))
	%DeleteLook.pressed.connect(func() -> void:
		if _selected:
			ctx.delete_look(_selected))
	%EditDone.pressed.connect(func() -> void: ctx.finish_look_edit(%EditFade.value))
	%EditCancel.pressed.connect(func() -> void: ctx.cancel_look_edit())

	# Amber outline so editing a look can't be mistaken for the normal shelf.
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UIPalette.ACCENT, 0.08)
	box.border_color = UIPalette.ACCENT
	box.set_border_width_all(1)
	box.set_corner_radius_all(UIPalette.RADIUS)
	box.set_content_margin_all(10)
	_edit_banner.add_theme_stylebox_override("panel", box)
	%EditTitle.add_theme_color_override("font_color", UIPalette.ACCENT)


func _save_look() -> void:
	var look := ctx.save_look(_look_name.text)
	if look:
		_look_name.clear()
		_selected = look
	_update_buttons()


func _fire(look: Look) -> void:
	if look and not ctx.is_editing_look():
		ctx.apply_look(look)


## A tile's look: dark card, amber outline when it is what's on stage.
func _tile_style(base: Color, outline: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = base
	s.border_color = outline
	s.set_border_width_all(width)
	s.set_corner_radius_all(UIPalette.RADIUS * 2)
	s.set_content_margin_all(10)
	return s


func _make_tile(look: Look) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(170, 112) if live_mode else Vector2(132, 84)
	tile.text = "%s\n%.1fs fade" % [look.look_name, look.fade_time]
	tile.clip_text = true
	tile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tile.add_theme_font_size_override("font_size", 17 if live_mode else UIPalette.FONT_SIZE + 1)
	tile.tooltip_text = look.look_name
	var applied := look == ctx.applied_look()
	var editing := look == ctx.editing_look
	var outline := UIPalette.ACCENT if (applied or editing) else UIPalette.HAIRLINE
	var width := 2 if (applied or editing) else 1
	tile.add_theme_stylebox_override("normal", _tile_style(UIPalette.RAISED, outline, width))
	tile.add_theme_stylebox_override("hover", _tile_style(UIPalette.HOVER, outline, width))
	tile.add_theme_stylebox_override("pressed", _tile_style(UIPalette.ACCENT_DIM, UIPalette.ACCENT, 2))
	tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if applied or editing:
		tile.add_theme_color_override("font_color", UIPalette.ACCENT)
		tile.add_theme_color_override("font_hover_color", UIPalette.ACCENT)
	tile.disabled = ctx.is_editing_look() and not editing and live_mode
	if live_mode:
		tile.pressed.connect(_fire.bind(look))
	else:
		tile.toggle_mode = true
		tile.button_group = _group
		tile.pressed.connect(func() -> void:
			_selected = look
			_update_buttons())
		tile.gui_input.connect(func(event: InputEvent) -> void:
			var mb := event as InputEventMouseButton
			if mb and mb.pressed and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
				_fire(look))
		if look == _selected:
			tile.set_pressed_no_signal(true)
	return tile


func _rebuild() -> void:
	if ctx == null:
		return
	if ctx.is_editing_look():
		_selected = ctx.editing_look
	elif _selected and not ctx.looks.looks.has(_selected):
		_selected = null
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var shelf := ctx.looks.looks
	for look in shelf:
		_grid.add_child(_make_tile(look))
	_scroll.visible = not shelf.is_empty()
	_empty.visible = shelf.is_empty()
	if live_mode:
		_empty.text = "No looks yet. Design some in Program, then fire them here."
	var editing := ctx.is_editing_look()
	_edit_banner.visible = editing and not live_mode
	if editing:
		%EditTitle.text = "Editing look: %s" % ctx.editing_look.look_name
		%EditFade.set_value_no_signal(ctx.editing_look.fade_time)
	if live_mode:
		%Hint.text = "Finish editing in Program to fire looks" if editing else "Tap a look to fade the stage to it"
	else:
		%Hint.text = "" if editing else "Double-click to fire"
	_look_name.visible = not editing
	%SaveLook.visible = not editing
	%LookButtons.visible = not editing
	_update_buttons()


func _update_buttons() -> void:
	if ctx == null:
		return
	var typed := _look_name.text.strip_edges()
	var clash := not typed.is_empty() and ctx.looks.is_name_taken(typed)
	%SaveLook.disabled = clash
	%FireLook.disabled = _selected == null
	%EditLook.disabled = _selected == null
	%RenameLook.disabled = _selected == null or typed.is_empty() or clash
	%DeleteLook.disabled = _selected == null
	%NameTaken.visible = clash and not ctx.is_editing_look()
	%NameTaken.text = "A look named \"%s\" already exists. Pick another name." % typed
