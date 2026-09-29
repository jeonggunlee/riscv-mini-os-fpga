#!/usr/bin/env python3
"""Program the volatile ZCU104 shell bitstream and exercise MiniFS over UART."""
import argparse
import glob
import json
import os
from pathlib import Path
import select
import subprocess
import termios
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="ZCU104 FT4232 channel D, usually if03-port0")
    parser.add_argument("--program", action="store_true")
    args = parser.parse_args()
    ports = glob.glob("/dev/serial/by-id/usb-Xilinx_JTAG+3Serial_*-if03-port0")
    if args.port is None:
        if len(ports) != 1:
            parser.error("Specify --port when there is not exactly one ZCU104 serial port")
        args.port = ports[0]
    root = Path(__file__).resolve().parent.parent
    out = root / "build" / "zcu104_shell"
    out.mkdir(parents=True, exist_ok=True)
    bitfile = out / "zcu104_mini_shell.bit"
    if args.program and not bitfile.exists():
        parser.error("Run make vivado-zcu104-shell first")

    fd = os.open(args.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    original = termios.tcgetattr(fd)
    data = bytearray()
    try:
        attrs = termios.tcgetattr(fd)
        attrs[0] = attrs[1] = attrs[3] = 0
        attrs[2] = termios.CLOCAL | termios.CREAD | termios.CS8
        attrs[4] = attrs[5] = termios.B115200
        attrs[6][termios.VMIN] = attrs[6][termios.VTIME] = 0
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
        termios.tcflush(fd, termios.TCIFLUSH)

        if args.program:
            with (out / "hardware_program.log").open("w") as log:
                subprocess.run([
                    "vivado", "-mode", "batch", "-nojournal", "-nolog", "-source",
                    str(root / "scripts" / "program_zcu104.tcl"),
                ], cwd=root, env={**os.environ, "SHELL_BUILD": "1"},
                    stdout=log, stderr=subprocess.STDOUT, check=True, timeout=120)

        def wait_for(marker, start=0, seconds=15):
            deadline = time.monotonic() + seconds
            while marker not in data[start:]:
                if time.monotonic() >= deadline:
                    raise RuntimeError(f"Timed out waiting for {marker!r}; got {bytes(data[-200:])!r}")
                if select.select([fd], [], [], 0.1)[0]:
                    chunk = os.read(fd, 4096)
                    if not chunk:
                        raise RuntimeError("UART disconnected")
                    data.extend(chunk)

        if not args.program:
            print("Waiting for prompt; press SW20 if the board is already running.")
        wait_for(b"rv> ", seconds=30)
        assert b"mini shell boot" in data, "Boot banner missing"

        def command(line, expected):
            start = len(data)
            os.write(fd, line.encode("ascii") + b"\r")
            wait_for(b"rv> ", start=start)
            reply = bytes(data[start:])
            if expected not in reply:
                raise RuntimeError(f"{line!r}: expected {expected!r}, got {reply!r}")
            return reply

        command("write hello.txt Hello", b"written")
        command("cat hello.txt", b"Hello\r\n")
        command("ls", b"hello.txt  5 bytes")
        command("rm hello.txt", b"removed")
        after = command("ls", b"rv> ")
        if b"hello.txt" in after:
            raise RuntimeError("Deleted file still appears in ls output")
        result = {"passed": True, "commands": ["write", "cat", "ls", "rm", "ls"],
                  "bytes": len(data), "port": args.port, "programmed": args.program}
        print(json.dumps(result, indent=2))
    finally:
        (out / "uart_capture.bin").write_bytes(data)
        termios.tcsetattr(fd, termios.TCSANOW, original)
        os.close(fd)


if __name__ == "__main__":
    main()
