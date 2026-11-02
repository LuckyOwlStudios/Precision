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

var data := PackedByteArray()
var _accum := 0.0


func _init() -> void:
	data.resize(512)


## address is 1-based, like on a console / fixture display.
func set_channel(address: int, value: int) -> void:
	if address < 1 or address > 512:
		return
	data[address - 1] = clampi(value, 0, 255)


func get_channel(address: int) -> int:
	if address < 1 or address > 512:
		return 0
	return data[address - 1]


func blackout() -> void:
	data.fill(0)
	if output:
		output.send_universe(universe_id, data)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() and not send_in_editor:
		return
	if output == null:
		return
	_accum += delta
	var interval := 1.0 / refresh_rate
	if _accum >= interval:
		_accum = fmod(_accum, interval)
		output.send_universe(universe_id, data)
