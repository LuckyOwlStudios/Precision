class_name TouchScroller
extends Node
## Swipe-to-scroll for fingers. Godot turns a finger into a mouse click, so the
## list under it just selects (or starts a drag) instead of scrolling. This
## watches the touches itself: a finger that moves mostly up or down over a
## scrollable thing (ScrollContainer, ItemList, Tree) scrolls it, and keeps
## gliding when lifted.
##
## A tap still selects. Sideways movement, or holding still for a moment before
## moving, is left alone so drag-and-drop out of a list keeps working. A finger
## that lands on a slider or scroll bar is never taken over.
## Add one anywhere in the tree (main_window does, with a touchscreen).

const DEADZONE_PX := 8.0 ## movement before it counts as a swipe
const HOLD_MSEC := 350 ## resting this long before moving means "drag", not "scroll"
const FRICTION := 0.002 ## fraction of speed left after one second of gliding
const STOP_SPEED := 20.0 ## px/s under which the glide ends
const MAX_SPEED := 6000.0
const FAR := Vector2(-10000.0, -10000.0) ## a release sent here can't click anything

enum Phase { IDLE, PENDING, SCROLLING, PASSING }

var _phase := Phase.IDLE
var _finger := -1
var _target: Control
var _bar: VScrollBar
var _start := Vector2.ZERO
var _down_msec := 0
var _velocity := 0.0 ## px/s, content moving with the finger
var _last_usec := 0
var _glide_bar: VScrollBar
var _glide_pos := 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		if _on_drag(event as InputEventScreenDrag):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION and _phase == Phase.SCROLLING:
		# The finger's mouse twin must not keep pressing, hovering or dragging what is under it.
		if event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
			var mb := event as InputEventMouseButton
			mb.position = FAR
			mb.global_position = FAR


func _process(delta: float) -> void:
	if _glide_bar == null:
		return
	if not is_instance_valid(_glide_bar) or not _glide_bar.is_visible_in_tree():
		_glide_bar = null
		return
	_glide_pos -= _velocity * delta # kept as a float: the bar rounds its own value to whole pixels
	_glide_bar.value = _glide_pos
	_velocity *= pow(FRICTION, delta)
	var at_edge := _glide_pos <= _glide_bar.min_value or _glide_pos >= _glide_bar.max_value - _glide_bar.page
	if absf(_velocity) < STOP_SPEED or at_edge:
		_glide_bar = null


func _on_touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		_glide_bar = null # a new touch stops a glide
		if _phase != Phase.IDLE:
			_phase = Phase.PASSING # a second finger: leave it to the stage's gestures
			return
		_finger = t.index
		_start = t.position
		_down_msec = Time.get_ticks_msec()
		_velocity = 0.0
		_last_usec = Time.get_ticks_usec()
		_target = null
		_bar = null
		_phase = Phase.PENDING
		var hit := _find_target(t.position)
		_target = hit["target"]
		_bar = hit["bar"]
		if _target == null:
			_phase = Phase.PASSING
	elif t.index == _finger:
		if _phase == Phase.SCROLLING and absf(_velocity) > STOP_SPEED and is_instance_valid(_bar):
			_glide_bar = _bar
			_glide_pos = _bar.value
		_phase = Phase.IDLE
		_finger = -1
		_target = null
		_bar = null


## Returns true when the drag was used to scroll.
func _on_drag(d: InputEventScreenDrag) -> bool:
	if d.index != _finger or _bar == null or not is_instance_valid(_bar):
		return false
	if _phase == Phase.PENDING:
		var moved := d.position - _start
		if moved.length() < DEADZONE_PX:
			return false
		if Time.get_ticks_msec() - _down_msec > HOLD_MSEC or absf(moved.y) < absf(moved.x):
			_phase = Phase.PASSING
			return false
		_phase = Phase.SCROLLING
		_cancel_press()
	if _phase != Phase.SCROLLING:
		return false
	_bar.value -= d.relative.y
	# Speed measured here: the event's own velocity is not filled in on every platform.
	var now := Time.get_ticks_usec()
	var dt := maxf((now - _last_usec) / 1e6, 0.004)
	_last_usec = now
	_velocity = lerpf(_velocity, clampf(d.relative.y / dt, -MAX_SPEED, MAX_SPEED), 0.5)
	return true


## The finger's press already reached whatever is under it. Move the mouse
## off it so a button there does not stay armed.
func _cancel_press() -> void:
	var m := InputEventMouseMotion.new()
	m.device = InputEvent.DEVICE_ID_EMULATION
	m.position = FAR
	m.global_position = FAR
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(m)


## What a finger at `at` would scroll: the deepest scrollable under it that has
## somewhere to go, with its vertical scroll bar. Empty when the finger is on a
## slider or scroll bar, or on nothing scrollable.
func _find_target(at: Vector2) -> Dictionary:
	var none := {"target": null, "bar": null}
	var chain: Array[Control] = []
	_collect(get_tree().root, at, chain)
	if chain.is_empty():
		return none
	var hit := chain[0] # deepest first
	if hit is Range or hit is SpinBox or hit is LineEdit or hit is TextEdit:
		return none
	for c: Control in chain:
		var bar := scroll_bar_of(c)
		if bar != null and bar.max_value - bar.page > 1.0:
			return {"target": c, "bar": bar}
	return none


## Visible controls under `at`, deepest first.
func _collect(node: Node, at: Vector2, out: Array[Control]) -> void:
	for child in node.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		_collect(child, at, out)
		if child is Control:
			var c := child as Control
			if c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(at):
				out.append(c)


## The vertical scroll bar of anything that scrolls, or null.
static func scroll_bar_of(c: Control) -> VScrollBar:
	if c is ScrollContainer:
		return (c as ScrollContainer).get_v_scroll_bar()
	if c is ItemList:
		return (c as ItemList).get_v_scroll_bar()
	if c is Tree:
		for child in c.get_children(true):
			if child is VScrollBar:
				return child as VScrollBar
	return null
