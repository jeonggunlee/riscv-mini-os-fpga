#!/usr/bin/env python3
"""Capture PL UART before programming, then check the Mini OS on real hardware.

Linux/Python standard library only. Does not transmit serial data or toggle
DTR/RTS. --program explicitly replaces volatile FPGA configuration via Vivado.
"""
import argparse
from collections import Counter
import glob
import hashlib
import json
import os
from pathlib import Path
import select
import subprocess
import termios
import time


def has_interleaved_marker(data: bytes, marker: bytes) -> bool:
    """Ignore A/B/C task bytes inserted between MiniFS demo characters."""
    pos = 0
    for byte in data:
        if byte == marker[pos]:
            pos += 1
            if pos == len(marker):
                return True
        elif byte not in b"ABC":
            pos = 0
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="/dev/serial/by-id/...-if03-port0 (PL UART)")
    parser.add_argument("--seconds", type=float, default=5.0)
    parser.add_argument("--program", action="store_true")
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error("--seconds must be positive")
    ports = glob.glob("/dev/serial/by-id/usb-Xilinx_JTAG+3Serial_*-if03-port0")
    if args.port is None:
        if len(ports) != 1:
            parser.error("Specify --port: expected exactly one Xilinx channel D")
        args.port = ports[0]
    root = Path(__file__).resolve().parent.parent
    out = root / "build" / "zcu104"
    out.mkdir(parents=True, exist_ok=True)
    bitfile = out / "zcu104_mini_os.bit"
    if args.program and not bitfile.is_file():
        parser.error("Run make vivado-zcu104 before --program")
    fd = os.open(args.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    original = termios.tcgetattr(fd)
    proc = None
    data = bytearray()
    capture_error = None
    try:
        attrs = termios.tcgetattr(fd)
        attrs[0] = attrs[1] = attrs[3] = 0
        attrs[2] = termios.CLOCAL | termios.CREAD | termios.CS8
        attrs[4] = attrs[5] = termios.B115200
        attrs[6][termios.VMIN] = 0
        attrs[6][termios.VTIME] = 0
        termios.tcsetattr(fd, termios.TCSANOW, attrs)
        termios.tcflush(fd, termios.TCIFLUSH)
        print(f"Listening on {args.port}: 115200 8-N-1, no flow control", flush=True)
        with (out / "hardware_program.log").open("w") as log:
            if args.program:
                proc = subprocess.Popen([
                    "vivado", "-mode", "batch", "-nojournal", "-nolog", "-source",
                    str(root / "scripts" / "program_zcu104.tcl"),
                ], cwd=root, stdout=log, stderr=subprocess.STDOUT)
            started = time.monotonic()
            capture_until = None if proc else started + args.seconds
            while True:
                now = time.monotonic()
                if proc and capture_until is None and proc.poll() is not None:
                    if proc.returncode != 0:
                        raise RuntimeError("Vivado programming failed; see hardware_program.log")
                    capture_until = now + args.seconds
                    print("Programming finished; collecting task output", flush=True)
                if capture_until is not None and now >= capture_until:
                    break
                if now - started > 120 + args.seconds:
                    raise RuntimeError("Programming/capture timeout")
                if select.select([fd], [], [], 0.1)[0]:
                    chunk = os.read(fd, 65536)
                    if not chunk:
                        raise RuntimeError("UART device disconnected")
                    data.extend(chunk)
    except Exception as exc:
        capture_error = str(exc)
    finally:
        if proc and proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=10)
        termios.tcsetattr(fd, termios.TCSANOW, original)
        os.close(fd)
        (out / "uart_capture.bin").write_bytes(data)
    banner = b"mini OS boot\n"
    start = data.rfind(banner)
    body = data[start + len(banner):] if start >= 0 else data
    counts = Counter(body)
    transitions = sum(a != b for a, b in zip(body, body[1:]))
    minifs_pass = has_interleaved_marker(body, b"[MiniFS] PASS")
    valid_uart = all(ch == 10 or 32 <= ch <= 126 for ch in body)
    passed = (capture_error is None and start >= 0 and all(counts[ch] >= 3 for ch in b"ABC")
              and transitions >= 6 and valid_uart and minifs_pass)
    result = dict(timestamp=time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                  programmed=args.program,
                  bitstream_sha256=(hashlib.sha256(bitfile.read_bytes()).hexdigest()
                                    if args.program else None),
                  port=args.port, bytes=len(data), boot_banner=start >= 0,
                  task_counts={chr(ch): counts[ch] for ch in b"ABC"},
                  task_transitions=transitions, minifs_pass=minifs_pass,
                  error=capture_error, passed=passed)
    (out / "uart_result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(bytes(data[:200]).decode("ascii", errors="backslashreplace"))
    print(json.dumps(result, indent=2))
    if not passed:
        if capture_error:
            print("Capture error:", capture_error)
        raise SystemExit("FAIL: expected boot banner, MiniFS PASS, interleaved A/B/C, no corrupt bytes")
    print("PASS: real ZCU104 UART Mini OS, MiniFS demo, and A/B/C task output")


if __name__ == "__main__":
    main()
