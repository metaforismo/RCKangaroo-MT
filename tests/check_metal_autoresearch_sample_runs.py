#!/usr/bin/env python3
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPERIMENTS = ROOT / "autoresearch" / "experiments"


def main() -> int:
    failures: list[str] = []
    for path in sorted(EXPERIMENTS.glob("metal_*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        sample_runs = int(data.get("sample_runs", 0))
        if sample_runs < 3:
            failures.append(f"{path.relative_to(ROOT)} sample_runs={sample_runs}, expected >= 3")

    if failures:
        sys.stdout.write("\n".join(failures) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
