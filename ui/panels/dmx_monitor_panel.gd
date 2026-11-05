class_name DMXMonitorPanel
extends MarginContainer
## Live view of the 512 channels being sent. Patched channels get an outline;
## brightness of each cell is the channel value. Hover a cell for details.

var ctx: StudioContext

@onready var _grid: DMXGrid = %Grid
@onready var _status: Label = %Status


func setup(p_ctx: StudioContext) -> void:
	ctx = p_ctx
	_grid.ctx = ctx


func _process(_delta: float) -> void:
	if ctx and is_visible_in_tree():
		_status.text = "%d of 512 channels patched. Art-Net to %s at %d Hz.%s Patched cells show their value; hover any cell for details." % [
			ctx.patched_channel_count(), ctx.output.target_ip, int(ctx.universe.refresh_rate),
			" BLACKOUT is on." if ctx.blackout else ""]
