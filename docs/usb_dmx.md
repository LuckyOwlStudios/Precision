# USB DMX output (Enttec DMX USB Pro style)

`USBProOutput` (addons/lucky_dmx/usb_pro_output.gd) is a `DMXOutput` like `ArtNetOutput`.
It builds Enttec DMX USB Pro messages ("send DMX", label 6) and sends them over localhost
UDP to `tools/usb_dmx_bridge.py`, which writes the bytes to the interface's serial port.
Godot can't open serial ports itself, and a helper avoids per-platform native builds.

## Setup
1. `pip install pyserial`
2. `python3 tools/usb_dmx_bridge.py --list` shows your ports; then
   `python3 tools/usb_dmx_bridge.py --port COM3` (omit `--port` to auto-pick an FTDI device).
   Or set `auto_start_bridge` (and `serial_port`) on the output node and Precision starts it.
3. Add a `USBProOutput` node and point `Universe1.output` at it instead of `ArtNet`.

Works with Enttec DMX USB Pro / Pro Mk2 and clones that speak the same protocol.
Open DMX (FTDI, host-generated break) is not supported yet.
Not yet tested on real hardware.
