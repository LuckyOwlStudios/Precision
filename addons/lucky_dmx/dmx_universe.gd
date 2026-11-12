@tool
class_name DMXUniverse
extends Node
## Holds the 512 channel values of one DMX universe and pushes them to an
## output at a fixed refresh rate. Fixtures write into this every frame.

@export var universe_id: int = 0
@export var output: DMXOutput
@export_range(1.0, 44.0) var refresh_rate: float = 40.0
## Send DMX while in the editor, so scrubbing an AnimationPlayer moves the real light.
@export var send_in_editor: bool = false
## While true every send carries zeros, but `data` keeps the live values so
## releasing blackout snaps straight back to the current look.
@export var blackout_held: bool = false

## Scales every fixture's intensity (0 to 1), like the grand master on a
## console. Fixtures read it when they write their dimmer / colour channels.
@export_range(0.0, 1.0) var grand_master: float = 1.0

var data := PackedByteArray()
var _zeros := PackedByteArray()
var _accum := 0.0


func _init() -> void:
	data.resize(512)
	_zeros.resize(512)
	# Run after fixtures (default priority 0) so each send carries this frame's values.
	process_priority = 100


## address is 1-based, like on a console / fixture display.
func set_channel(address: int, value: int) -> void:
	if address < 1 or address > 512:
		return
	data[address - 1] = clampi(value, 0, 255)


func get_channel(address: int) -> int:
	if address < 1 or address > 512:
		return 0
	return data[address - 1]


## Zero every channel and send once. Fixtures rewrite their channels on the
## next frame, so for a lasting blackout set fixture dimmers to 0 as well.
func blackout() -> void:
	data.fill(0)
	if output:
		output.send_universe(universe_id, _zeros if blackout_held else data)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not send_in_editor:
		return
	if output == null:
		return
	_accum += delta
	var interval := 1.0 / refresh_rate
	if _accum >= interval:
		_accum = fmod(_accum, interval)
		output.send_universe(universe_id, _zeros if blackout_held else data)
