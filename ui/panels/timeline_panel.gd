class_name TimelinePanel
extends VBoxContainer
## Beat-grid timeline along the bottom: a music lane, one lane per fixture,
## bars and beats on the ruler, and a red playhead.
## Effect clips live on the fixture lanes (see TimelineCanvas); the Snap menu
## sets the grid they move on.

var ctx: StudioContext

@onready var _canvas: TimelineCanvas = %Canvas
@onready var _pos_label: Label = %Position


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	_canvas.ctx = ctx
	ctx.transport_changed.connect(_update_label)
	_update_label()


func _ready() -> void:
	%Zoom.value_changed.connect(func(v: float) -> void: _canvas.px_per_beat = v)
	# Snap: 1 beat, 1/2, 1/4, bar, off (same order as the menu).
	var snaps := [1.0, 0.5, 0.25, 4.0, 0.0]
	%Snap.item_selected.connect(func(i: int) -> void: _canvas.snap_beats = snaps[i])


func _update_label() -> void:
	var b := ctx.position_beats
	var secs := b * 60.0 / ctx.bpm
	_pos_label.text = "BAR %d.%d    %02d:%04.1f" % [int(b / 4.0) + 1, int(b) % 4 + 1, int(secs / 60.0), fmod(secs, 60.0)]
