#!/usr/bin/env python3
"""Upload a fixed-address RV32I flat binary to MiniFS; optionally run it."""
import argparse
import glob
import json
import os
from pathlib import Path
import select
import termios
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", default="build/firmware/hello_app.bin")
    parser.add_argument("--name", default="hello.app")
    parser.add_argument("--port")
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    payload = Path(args.file).read_bytes()
    if not 4 <= len(payload) <= 6644:
        parser.error("application must be 4..6644 bytes")
    try:
        name = args.name.encode("ascii")
    except UnicodeEncodeError:
        parser.error("file name must be ASCII")
    if not 1 <= len(name) <= 15 or any(c in b" /\r\n\t" for c in name):
        parser.error("file name must be 1..15 ASCII bytes, no whitespace or slash")
    ports = glob.glob("/dev/serial/by-id/usb-Xilinx_JTAG+3Serial_*-if03-port0")
    if args.port is None:
        if len(ports) != 1:
            parser.error("Specify --port when there is not exactly one ZCU104 serial port")
        args.port = ports[0]

    checksum = sum(payload) & 0xFFFFFFFF
    fd = os.open(args.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    original = termios.tcgetattr(fd)
    captured = bytearray()
    try:
        attrs = termios.tcgetattr(fd)
        attrs[0] = attrs[1] = attrs[3] = 0
        attrs[2] = termios.CLOCAL | termios.CREAD | termios.CS8
        attrs[4] = attrs[5] = termios.B115200
        attrs[6][termios.VMIN] = attrs[6][termios.VTIME] = 0
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
        termios.tcflush(fd, termios.TCIFLUSH)

        def write_all(data):
            pending = memoryview(data)
            deadline = time.monotonic() + 30
            while pending:
                if time.monotonic() >= deadline:
                    raise TimeoutError("UART write timeout")
                if select.select([], [fd], [], 0.1)[1]:
                    pending = pending[os.write(fd, pending):]

        def until(marker, seconds=30):
            deadline = time.monotonic() + seconds
            start = len(captured)
            while marker not in captured[start:]:
                if time.monotonic() >= deadline:
                    raise TimeoutError(f"Waiting for {marker!r}; received {bytes(captured[start:])!r}")
                if select.select([fd], [], [], 0.1)[0]:
                    chunk = os.read(fd, 4096)
                    if not chunk:
                        raise RuntimeError("UART disconnected")
                    captured.extend(chunk)
            return bytes(captured[start:])

        write_all(b"\r")
        until(b"rv> ")
        write_all(f"upload {args.name} {len(payload)} {checksum:08x}\r".encode("ascii"))
        until(b"send hex:\r\n")
        hex_bytes = payload.hex().encode("ascii")
        for pos in range(0, len(hex_bytes), 256):
            write_all(hex_bytes[pos:pos + 256])
        reply = until(b"rv> ", seconds=60)
        if b"uploaded\r\n" not in reply:
            raise RuntimeError(f"Upload failed: {reply!r}")

        app_reply = b""
        if args.run:
            write_all(f"run {args.name}\r".encode("ascii"))
            app_reply = until(b"rv> ", seconds=30)
            if b"running\r\n" not in app_reply or b"returned\r\n" not in app_reply:
                raise RuntimeError(f"App did not return: {app_reply!r}")
        print(json.dumps({"uploaded": args.name, "bytes": len(payload),
                          "checksum": f"{checksum:08x}", "ran": args.run,
                          "app_output": app_reply.decode("ascii", errors="replace")}, indent=2))
    finally:
        output = Path("build/zcu104_shell/upload_capture.bin")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(captured)
        termios.tcsetattr(fd, termios.TCSANOW, original)
        os.close(fd)


if __name__ == "__main__":
    main()
