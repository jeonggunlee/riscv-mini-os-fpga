#!/usr/bin/env python3
"""Convert a raw little-endian RV32 binary to $readmemh 32-bit words."""

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path, help="raw input binary")
    parser.add_argument("output", type=Path, help="$readmemh output file")
    parser.add_argument(
        "--max-bytes",
        type=lambda value: int(value, 0),
        default=8192,
        help="fail if the image exceeds this size (default: 8192)",
    )
    args = parser.parse_args()

    data = args.input.read_bytes()
    if len(data) > args.max_bytes:
        raise SystemExit(
            f"image is {len(data)} bytes, larger than {args.max_bytes}-byte memory"
        )

    data += bytes((-len(data)) % 4)
    words = (
        int.from_bytes(data[offset : offset + 4], "little")
        for offset in range(0, len(data), 4)
    )
    args.output.write_text("".join(f"{word:08x}\n" for word in words), encoding="ascii")


if __name__ == "__main__":
    main()
