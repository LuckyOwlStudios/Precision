@tool
class_name USBProOutput
extends DMXOutput
## Sends DMX through a USB interface that speaks the Enttec DMX USB Pro
## protocol (Enttec DMX USB Pro / Pro Mk2 and the many clones).
##
## Godot cannot open serial ports, so this talks to a tiny helper
## (tools/usb_dmx_bridge.py) over localhost UDP. The helper only copies
## bytes to the USB device; all the protocol lives here.

## Which DMX universe goes out of the interface (0 = "Universe 1").
## A Pro interface has a single output, so other universes are ignored.
@export var universe_id: int = 0
## Where the helper listens.
@export var bridge_host: String = "127.0.0.1"
@export var bridge_port: int = 6455:
	set(value):
		bridge_port = value
		_udp = null
## Start the helper automatically while the app runs. Leave off if you run
## the helper yourself.
@export var auto_start_bridge: bool = false
## Serial port the helper opens: "COM3", "/dev/ttyUSB0", "/dev/cu.usbserial-EN123456".
## Blank lets the helper pick the first port that looks like an Enttec/FTDI.
@export var serial_port: String = ""
## Python 3 with pyserial installed (pip install pyserial).
@export var python_path: String = "python3"
@export var bridge_script: String = "res://tools/usb_dmx_bridge.py"

const START := 0x7E
const END := 0xE7
const LABEL_SEND_DMX := 6 ## "Output Only Send DMX Packet Request"

var _udp: PacketPeerUDP
var _bridge_pid: int = -1


## One Pro "send DMX" message: 7E, label, length LSB, length MSB, start code 0,
## channels, E7. The length counts the start code. Pro interfaces take 24..512
## channels; shorter data is padded with zeros up to 24.
static func build_frame(data: PackedByteArray) -> PackedByteArray:
	var channels := data.slice(0, 512)
	if channels.size() < 24:
		channels.resize(24)
	var length := channels.size() + 1
	var pkt := PackedByteArray([START, LABEL_SEND_DMX, length & 0xFF, (length >> 8) & 0xFF, 0])
	pkt.append_array(channels)
	pkt.append(END)
	return pkt


func send_universe(universe: int, data: PackedByteArray) -> void:
	if universe != universe_id:
		return
	if _udp == null:
		_udp = PacketPeerUDP.new()
		var err := _udp.set_dest_address(bridge_host, bridge_port)
		if err != OK:
			push_error("USBProOutput: could not set helper address %s:%d (error %d)" % [bridge_host, bridge_port, err])
			_udp = null
			return
	_udp.put_packet(build_frame(data))


func _ready() -> void:
	if auto_start_bridge and not Engine.is_editor_hint():
		start_bridge()


func _exit_tree() -> void:
	stop_bridge()


## Launches the helper. Returns false if it could not start.
func start_bridge() -> bool:
	stop_bridge()
	var args := PackedStringArray([ProjectSettings.globalize_path(bridge_script), "--listen", "%s:%d" % [bridge_host, bridge_port]])
	if serial_port != "":
		args.append_array(["--port", serial_port])
	_bridge_pid = OS.create_process(python_path, args)
	if _bridge_pid <= 0:
		push_error("USBProOutput: could not start '%s'. Is Python 3 installed?" % python_path)
		_bridge_pid = -1
		return false
	return true


func stop_bridge() -> void:
	if _bridge_pid > 0:
		OS.kill(_bridge_pid)
		_bridge_pid = -1
