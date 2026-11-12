class_name CommandPalette
extends Control
## Ctrl+K action search, like Blender's F3: type a few letters of what you want
## ("undo", "go live", "dup"), Up/Down to pick, Enter to run it. Esc, a click
## outside, or Ctrl+K again closes it. Each row shows the action's shortcut so
## the search doubles as a way to learn them.
##
## The actions come from an ActionRegistry (ctx.actions); see that file for how
## a feature adds its own. The layout is in command_palette.tscn.

const MAX_RESULTS := 60

@onready var _field: LineEdit = %Field
@onready var _list: Tree = %List
@onready var _empty: Label = %Empty

var _registry: ActionRegistry
var _results: Array[PaletteAction] = []
var _index := 0
var _return_focus: Control


func _ready() -> void:
	visible = false
	_field.text_changed.connect(func(_t: String) -> void: _refresh())
	_field.gui_input.connect(_on_field_input)
	_list.item_activated.connect(_run_current)
	# A single click runs the row; keyboard moves only select it.
	_list.item_mouse_selected.connect(func(_pos: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT:
			_run_current())
	%Dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close())


func setup(registry: ActionRegistry) -> void:
	_registry = registry


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	if _registry == null:
		return
	_return_focus = get_viewport().gui_get_focus_owner()
	_field.text = ""
	visible = true
	_refresh()
	_field.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()
	_return_focus = null


func _refresh() -> void:
	_results = _registry.search(_field.text)
	if _results.size() > MAX_RESULTS:
		_results.resize(MAX_RESULTS)
	_list.clear()
	var root := _list.create_item()
	for a in _results:
		var item := _list.create_item(root)
		item.set_text(0, a.display_title())
		item.set_text(1, a.shortcut)
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_custom_color(1, UIPalette.TEXT_DIM)
	_empty.visible = _results.is_empty()
	_list.visible = not _results.is_empty()
	_select(0)


func _select(i: int) -> void:
	if _results.is_empty():
		_index = 0
		return
	_index = posmod(i, _results.size())
	var item := _list.get_root().get_child(_index)
	item.select(0)
	_list.scroll_to_item(item)


func _run_current(_unused: Variant = null) -> void:
	if _results.is_empty():
		return
	var action := _results[_index]
	close() # first, so the action sees the focus it would have had without us
	action.execute()


func _on_field_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_DOWN:
			_select(_index + 1)
		KEY_UP:
			_select(_index - 1)
		KEY_PAGEDOWN:
			_select(mini(_index + 8, _results.size() - 1))
		KEY_PAGEUP:
			_select(maxi(_index - 8, 0))
		KEY_ENTER, KEY_KP_ENTER:
			_run_current()
		KEY_ESCAPE:
			close()
		KEY_K:
			if not (key.ctrl_pressed or key.meta_pressed):
				return
			close()
		_:
			return
	_field.accept_event()
