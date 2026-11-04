class_name OS2LListener
extends Node
## Receives OS2L, the open "lighting control" protocol that VirtualDJ (and a
## few other apps) send: one small JSON message per beat, plus buttons and
## commands. The DJ software connects to us over TCP.
##
## OS2L carries the beat and the tempo but not the track name or position,
## so on its own it can't pick a song's show; VirtualDJSource uses it to put
## the lights exactly on the beat while the HTTP link supplies the rest.
##
## VirtualDJ normally finds OS2L receivers with Bonjour (DNS-SD), which Godot
## can't advertise, so point VirtualDJ at us directly: in VirtualDJ's
## Settings > Options, set `os2lDirectIp` to `127.0.0.1:9996` (or this
## computer's address and `port`).

## A beat: `pos` is VirtualDJ's running beat count, `change` is true when the
## beat doesn't follow on from the last one (new track, jump, deck change).
signal beat_received(pos: int, bpm: float, change: bool, strength: float)
## A VirtualDJ button mapped to OS2L ("os2l_button" in a mapping).
signal button_received(name: String, page: String, on: bool)
## A VirtualDJ command mapped to OS2L ("os2l_cmd").
signal command_received(id: int, param: float)
signal client_count_changed(count: int)

@export var port: int = 9996

var _server := TCPServer.new()
var _peers: Array[StreamPeerTCP] = []
var _buffers: Array[String] = []


func listen() -> Error:
	close()
	var err := _server.listen(port)
	if err != OK:
		push_warning("OS2L: can't listen on port %d (%s)" % [port, error_string(err)])
	return err


func close() -> void:
	for p in _peers:
		p.disconnect_from_host()
	_peers.clear()
	_buffers.clear()
	if _server.is_listening():
		_server.stop()


func is_listening() -> bool:
	return _server.is_listening()


func client_count() -> int:
	return _peers.size()


func _exit_tree() -> void:
	close()


func _process(_delta: float) -> void:
	if not _server.is_listening():
		return
	var before := _peers.size()
	while _server.is_connection_available():
		_peers.append(_server.take_connection())
		_buffers.append("")
	for i in range(_peers.size() - 1, -1, -1):
		var p := _peers[i]
		p.poll()
		if p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_peers.remove_at(i)
			_buffers.remove_at(i)
			continue
		var n := p.get_available_bytes()
		if n > 0:
			var got := p.get_data(n)
			if got[0] == OK:
				_buffers[i] = feed(_buffers[i] + (got[1] as PackedByteArray).get_string_from_utf8())
	if _peers.size() != before:
		client_count_changed.emit(_peers.size())


## Handles every complete {...} message in `text` and returns what's left
## over (a message cut off mid-way). Public so tests can feed it directly.
func feed(text: String) -> String:
	var depth := 0
	var start := -1
	var in_string := false
	var escaped := false
	var consumed := 0
	for i in text.length():
		var c := text[i]
		if in_string:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == "\"":
				in_string = false
			continue
		match c:
			"\"":
				in_string = true
			"{":
				if depth == 0:
					start = i
				depth += 1
			"}":
				if depth > 0:
					depth -= 1
					if depth == 0 and start >= 0:
						_handle(text.substr(start, i - start + 1))
						consumed = i + 1
						start = -1
	if depth == 0:
		return "" # nothing pending (whitespace between messages is dropped)
	var rest := text.substr(consumed)
	return rest if rest.length() < 65536 else "" # don't grow forever on garbage


func _handle(json: String) -> void:
	var msg: Variant = JSON.parse_string(json)
	if not msg is Dictionary:
		return
	var d: Dictionary = msg
	match str(d.get("evt", "")):
		"beat":
			beat_received.emit(int(d.get("pos", 0)), float(d.get("bpm", 0.0)), bool(d.get("change", false)), float(d.get("strength", 0.0)))
		"btn":
			button_received.emit(str(d.get("name", "")), str(d.get("page", "")), str(d.get("state", "")) == "on")
		"cmd":
			command_received.emit(int(d.get("id", 0)), float(d.get("param", 0.0)))
