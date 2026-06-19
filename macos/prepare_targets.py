#!/usr/bin/env python3
"""Validate and normalize secp256k1 public-key target lists for RCKangaroo-MT."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F


def _is_hex(value: str) -> bool:
    try:
        int(value, 16)
        return True
    except ValueError:
        return False


def _sqrt_mod_p(value: int) -> int:
    return pow(value, (P + 1) // 4, P)


def _parse_public_key(value: str) -> tuple[int, int]:
    value = value.strip()
    if len(value) == 66 and value[:2] in {"02", "03"} and _is_hex(value):
        x = int(value[2:], 16)
        if x >= P:
            raise ValueError("x coordinate is outside secp256k1 field")
        y2 = (pow(x, 3, P) + 7) % P
        y = _sqrt_mod_p(y2)
        if (y * y) % P != y2:
            raise ValueError("x coordinate is not on secp256k1")
        want_odd = value[:2] == "03"
        if bool(y & 1) != want_odd:
            y = P - y
        return x, y

    if len(value) == 130 and value[:2] == "04" and _is_hex(value):
        x = int(value[2:66], 16)
        y = int(value[66:], 16)
        if x >= P or y >= P:
            raise ValueError("coordinate is outside secp256k1 field")
        if (y * y - pow(x, 3, P) - 7) % P != 0:
            raise ValueError("point is not on secp256k1")
        return x, y

    raise ValueError("expected compressed 02/03... or uncompressed 04... public key")


def _compress(point: tuple[int, int]) -> str:
    x, y = point
    prefix = "03" if (y & 1) else "02"
    return f"{prefix}{x:064x}".upper()


def _uncompress(point: tuple[int, int]) -> str:
    x, y = point
    return f"04{x:064x}{y:064x}".upper()


def _clean_line(line: str) -> str:
    return line.split("#", 1)[0].strip()


def prepare_targets(args: argparse.Namespace) -> int:
    seen: set[str] = set()
    output: list[str] = []
    invalid: list[str] = []
    comments_or_blank = 0
    duplicates = 0

    for line_no, raw_line in enumerate(args.input.read_text(encoding="utf-8").splitlines(), start=1):
        value = _clean_line(raw_line)
        if not value:
            comments_or_blank += 1
            continue
        try:
            point = _parse_public_key(value)
        except ValueError as exc:
            invalid.append(f"line {line_no}: {exc}")
            if args.skip_invalid:
                continue
            continue

        normalized = _uncompress(point) if args.uncompressed else _compress(point)
        dedupe_key = _compress(point)
        if not args.keep_duplicates and dedupe_key in seen:
            duplicates += 1
            continue
        seen.add(dedupe_key)
        output.append(normalized)

    if invalid and not args.skip_invalid:
        print("Invalid target file:", file=sys.stderr)
        for item in invalid[:20]:
            print(f"  {item}", file=sys.stderr)
        if len(invalid) > 20:
            print(f"  ... {len(invalid) - 20} more", file=sys.stderr)
        return 1

    if not output:
        print("No valid targets found.", file=sys.stderr)
        return 1

    if not args.stats_only:
        args.output.write_text("\n".join(output) + "\n", encoding="utf-8")

    print(f"valid targets: {len(output)}")
    print(f"blank/comment lines: {comments_or_blank}")
    print(f"duplicates skipped: {duplicates}")
    print(f"invalid skipped: {len(invalid) if args.skip_invalid else 0}")
    if not args.stats_only:
        print(f"written: {args.output}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Prepare a target list for RCKangaroo-MT.")
    parser.add_argument("input", type=Path, help="Input text file with one public key per line.")
    parser.add_argument("-o", "--output", type=Path, default=Path("targets.cleaned.txt"), help="Output target file.")
    parser.add_argument("--uncompressed", action="store_true", help="Write uncompressed 04... public keys.")
    parser.add_argument("--keep-duplicates", action="store_true", help="Keep duplicate targets.")
    parser.add_argument("--skip-invalid", action="store_true", help="Skip invalid lines instead of failing.")
    parser.add_argument("--stats-only", action="store_true", help="Validate and print stats without writing output.")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if not args.input.exists():
        parser.error(f"input file does not exist: {args.input}")
    return prepare_targets(args)


if __name__ == "__main__":
    raise SystemExit(main())
