#!/usr/bin/env python3
import sys
from pathlib import Path


FNV64_OFFSET = 0xCBF29CE484222325
FNV64_PRIME = 0x100000001B3


def fnv1a64(data: bytes) -> int:
    value = FNV64_OFFSET
    for byte in data:
        value ^= byte
        value = (value * FNV64_PRIME) & 0xFFFFFFFFFFFFFFFF
    return value


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: write_metal_library_meta.py METAL_SOURCE METAL_FLAGS OUTPUT_META", file=sys.stderr)
        return 2

    source_path = Path(sys.argv[1])
    metal_flags = sys.argv[2]
    output_path = Path(sys.argv[3])
    source = source_path.read_bytes()
    output_path.write_text(
        f"source_fnv64=0x{fnv1a64(source):016x}\n"
        f"metal_flags={metal_flags}\n"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
