#!/usr/bin/env python3
import sys
from pathlib import Path


START = 'R"RCK_METAL('
END = ')RCK_METAL"'


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: extract_metal_kernels.py INPUT_HEADER OUTPUT_METAL", file=sys.stderr)
        return 2

    header_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])
    source = header_path.read_text()
    try:
        start = source.index(START) + len(START)
        end = source.rindex(END)
    except ValueError:
        print(f"failed to find Metal raw string in {header_path}", file=sys.stderr)
        return 1

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(source[start:end])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
