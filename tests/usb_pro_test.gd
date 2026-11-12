extends SceneTree
## USB DMX Pro framing. Run:
##   godot --headless --path . --script res://tests/usb_pro_test.gd

var _fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _initialize() -> void:
	var full := PackedByteArray()
	full.resize(512)
	full[0] = 255
	full[511] = 7
	var f := USBProOutput.build_frame(full)
	_check(f.size() == 512 + 6, "full frame size")
	_check(f[0] == 0x7E and f[1] == 6, "header and label")
	_check(f[2] == (513 & 0xFF) and f[3] == (513 >> 8), "length counts start code (513)")
	_check(f[4] == 0, "start code")
	_check(f[5] == 255 and f[516] == 7, "channels kept in order")
	_check(f[f.size() - 1] == 0xE7, "end byte")

	var short := USBProOutput.build_frame(PackedByteArray([1, 2, 3]))
	_check(short.size() == 24 + 6, "short data padded to 24 channels")
	_check(short[2] == 25 and short[3] == 0, "short length")
	_check(short[5] == 1 and short[7] == 3 and short[8] == 0, "padding is zeros")

	var big := PackedByteArray()
	big.resize(600)
	_check(USBProOutput.build_frame(big).size() == 512 + 6, "oversize data clamped to 512")

	print("usb_pro_test: ", "OK" if _fails == 0 else "%d FAILED" % _fails)
	quit(_fails)
