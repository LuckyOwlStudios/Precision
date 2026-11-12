#!/usr/bin/env python3
"""Copies UDP datagrams to a USB DMX interface's serial port.

Godot can't open serial ports, so USBProOutput sends ready-made Enttec DMX USB
Pro messages here and this writes them to the device unchanged.

  pip install pyserial
  python3 tools/usb_dmx_bridge.py --list
  python3 tools/usb_dmx_bridge.py --port COM3
  python3 tools/usb_dmx_bridge.py                 # picks an Enttec/FTDI port

Listens on 127.0.0.1:6455 by default (local only). Reconnects if the
interface is unplugged and plugged back in.
"""
import argparse
import socket
import sys
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    sys.exit("pyserial is missing. Install it with: pip install pyserial")

ENTTEC_VID = 0x0403  # FTDI, used by Enttec and most clones


def find_port():
    for p in list_ports.comports():
        if p.vid == ENTTEC_VID:
            return p.device
    return None


def open_serial(path):
    # The Pro protocol runs over USB; the baud rate is ignored by the device.
    return serial.Serial(path, baudrate=57600, timeout=0, write_timeout=0.5)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true", help="list serial ports and exit")
    ap.add_argument("--port", help="serial port, e.g. COM3 or /dev/ttyUSB0 (default: first FTDI device)")
    ap.add_argument("--listen", default="127.0.0.1:6455", help="host:port to receive from Precision")
    args = ap.parse_args()

    if args.list:
        for p in list_ports.comports():
            vid = "%04x:%04x" % (p.vid, p.pid) if p.vid is not None else "-"
            print("%s\t%s\t%s" % (p.device, vid, p.description))
        return

    host, _, port = args.listen.rpartition(":")
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((host or "127.0.0.1", int(port)))
    sock.settimeout(1.0)

    ser = None
    last_warn = 0.0
    print("Listening on %s" % args.listen, flush=True)
    while True:
        try:
            data, _ = sock.recvfrom(1024)
        except socket.timeout:
            continue
        if ser is None:
            path = args.port or find_port()
            try:
                if path is None:
                    raise serial.SerialException("no USB DMX interface found")
                ser = open_serial(path)
                print("Connected to %s" % path, flush=True)
            except serial.SerialException as e:
                if time.time() - last_warn > 5:
                    print("Waiting for interface: %s" % e, flush=True)
                    last_warn = time.time()
                continue
        try:
            ser.write(data)
        except (serial.SerialException, OSError) as e:
            print("Lost interface: %s" % e, flush=True)
            try:
                ser.close()
            except Exception:
                pass
            ser = None


if __name__ == "__main__":
    main()
