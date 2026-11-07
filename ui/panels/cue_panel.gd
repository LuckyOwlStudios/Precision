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
@onready var _edit_banner: PanelContainer = %EditBanner


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	ctx.cues_changed.connect(_rebuild)
	ctx.cue_stack.cue_started.connect(func(_i: int, _c: LightCue) -> void: _rebuild())
	ctx.looks_changed.connect(_rebuild_looks)
	ctx.look_editing_changed.connect(func(_l: Look) -> void: _rebuild_looks())
	_rebuild()
	_rebuild_looks()


func _ready() -> void:
	_list.item_activated.connect(func(i: int) -> void: ctx.go_cue(i))
	%Record.pressed.connect(func() -> void: ctx.record_cue())
	_go.pressed.connect(func() -> void: ctx.go_cue())
	_looks.item_activated.connect(func(i: int) -> void:
		if not ctx.is_editing_look():
			ctx.apply_look(ctx.looks.looks[i]))
	_looks.item_selected.connect(func(_i: int) -> void: _update_look_buttons())
	_looks.empty_clicked.connect(func(_p: Vector2, _b: int) -> void:
		_looks.deselect_all()
		_update_look_buttons())
	_look_name.text_changed.connect(func(_t: String) -> void: _update_look_buttons())
	_look_name.text_submitted.connect(func(_t: String) -> void:
		if not %SaveLook.disabled:
			_save_look())
	%SaveLook.pressed.connect(_save_look)
	%EditLook.pressed.connect(func() -> void:
		var look := _selected_look()
		if look:
			ctx.begin_look_edit(look))
	%RenameLook.pressed.connect(func() -> void:
		var look := _selected_look()
		if look:
			ctx.rename_look(look, _look_name.text))
	%DeleteLook.pressed.connect(func() -> void:
		var look := _selected_look()
		if look:
			ctx.delete_look(look))
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
	if ctx.save_look(_look_name.text):
		_look_name.clear()
	_update_look_buttons()


func _selected_look() -> Look:
	var sel := _looks.get_selected_items()
	if sel.is_empty() or sel[0] >= ctx.looks.looks.size():
		return null
	return ctx.looks.looks[sel[0]]


func _rebuild_looks() -> void:
	if ctx == null:
		return
	var keep := _looks.get_selected_items()
	_looks.clear()
	var shelf := ctx.looks.looks
	for look in shelf:
		var is_edit := look == ctx.editing_look
		var idx := _looks.add_item(("✎  " if is_edit else "") + look.look_name)
		if is_edit or look == ctx.applied_look():
			_looks.set_item_custom_fg_color(idx, UIPalette.ACCENT)
	var editing_index := shelf.find(ctx.editing_look)
	if editing_index >= 0:
		_looks.select(editing_index)
	elif not keep.is_empty() and keep[0] < shelf.size():
		_looks.select(keep[0])
	_looks.visible = not shelf.is_empty()
	_looks_empty.visible = shelf.is_empty()

	var editing := ctx.is_editing_look()
	_edit_banner.visible = editing
	if editing:
		%EditTitle.text = "Editing look: %s" % ctx.editing_look.look_name
		%EditFade.set_value_no_signal(ctx.editing_look.fade_time)
	# While editing, the only way out is Save changes or Cancel.
	_look_name.visible = not editing
	%LookButtons.visible = not editing
	_update_look_buttons()


func _update_look_buttons() -> void:
	if ctx == null:
		return
	var look := _selected_look()
	var typed := _look_name.text.strip_edges()
	var clash := not typed.is_empty() and ctx.looks.is_name_taken(typed)
	%SaveLook.disabled = clash
	%EditLook.disabled = look == null
	%RenameLook.disabled = look == null or typed.is_empty() or clash
	%DeleteLook.disabled = look == null
	%NameTaken.visible = clash and not ctx.is_editing_look()
	%NameTaken.text = "A look named \"%s\" already exists. Pick another name." % typed
