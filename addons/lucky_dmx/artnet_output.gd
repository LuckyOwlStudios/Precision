@tool
class_name ArtNetOutput
extends DMXOutput
## Sends ArtDMX packets over UDP (port 6454).
## Works with any Art-Net node / Ethernet-to-DMX box, and with software
## visualizers (QLC+, Capture, etc.) for testing without hardware.

## IP of your Art-Net node, or a broadcast address like 255.255.255.255
## or 2.255.255.255. Unicast to the node's IP is preferred once you know it.
@export var target_ip: String = "255.255.255.255":
	set(value):
		target_ip = value
		_udp = null # reopen with the new address on next send

@export var port: int = 6454

var _udp: PacketPeerUDP
var _sequence: int = 0


func _ensure_socket() -> bool:
	if _udp != null:
		return true
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true) # must be set before a broadcast dest address
	var err := _udp.set_dest_address(target_ip, port)
	if err != OK:
		push_error("ArtNetOutput: could not set destination %s:%d (error %d)" % [target_ip, port, err])
		_udp = null
		return false
	return true


func send_universe(universe: int, data: PackedByteArray) -> void:
	if not _ensure_socket():
		return

	var length := data.size()
	if length % 2 == 1: # Art-Net requires an even length, 2..512
		length += 1

	var pkt := PackedByteArray()
	pkt.append_array("Art-Net".to_ascii_buffer())
	pkt.append(0)
	pkt.append(0x00) # OpCode ArtDMX = 0x5000, little-endian
	pkt.append(0x50)
	pkt.append(0)    # Protocol version 14, big-endian
	pkt.append(14)
	_sequence = _sequence % 255 + 1 # 1..255 (0 would disable sequencing)
	pkt.append(_sequence)
	pkt.append(0)    # Physical port (informational)
	pkt.append(universe & 0xFF)          # SubUni: sub-net + universe
	pkt.append((universe >> 8) & 0x7F)   # Net
	pkt.append((length >> 8) & 0xFF)     # Length, big-endian
	pkt.append(length & 0xFF)
	pkt.append_array(data)
	if data.size() < length:
		pkt.append(0)

	_udp.put_packet(pkt)
