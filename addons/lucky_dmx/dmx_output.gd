@tool
class_name DMXOutput
extends Node
## Base class for anything that can send a DMX universe somewhere.
## Subclass this for Art-Net, sACN, USB interfaces (Enttec), etc.


func send_universe(_universe: int, _data: PackedByteArray) -> void:
	pass
