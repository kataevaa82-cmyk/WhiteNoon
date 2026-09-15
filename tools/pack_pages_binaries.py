"""Pack a binary file into RGB pixels for connector-safe GitHub upload."""

from __future__ import annotations

import argparse
import math
import struct
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--width", type=int, default=4096)
    args = parser.parse_args()

    payload = args.input.read_bytes()
    framed = b"WNPG" + struct.pack("<I", len(payload)) + payload
    pixel_count = math.ceil(len(framed) / 3)
    height = math.ceil(pixel_count / args.width)
    padded = framed + bytes(args.width * height * 3 - len(framed))
    image = Image.frombytes("RGB", (args.width, height), padded)
    image.save(args.output, format="PNG", compress_level=1, optimize=False)
    print(f"{args.input.name}: {len(payload)} bytes -> {args.output.name} {image.width}x{image.height}")


if __name__ == "__main__":
    main()
