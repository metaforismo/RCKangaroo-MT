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
        if data.get("name") == "metal_jacobian_jump_walk_dp" and sample_runs < 5:
            failures.append(f"{path.relative_to(ROOT)} sample_runs={sample_runs}, expected >= 5 for primary Metal DP gate")

    stable_path = EXPERIMENTS / "metal_jacobian_jump_walk_dp_stable.json"
    if not stable_path.exists():
        failures.append(f"{stable_path.relative_to(ROOT)} missing stable Metal DP gate")
    else:
        stable = json.loads(stable_path.read_text(encoding="utf-8"))
        if stable.get("bench_target") != "macos-metal-jacobian-jump-walk-dp-stable-bench":
            failures.append(f"{stable_path.relative_to(ROOT)} bench_target should use the stable Metal DP make target")
        if int(stable.get("sample_runs", 0)) < 3:
            failures.append(f"{stable_path.relative_to(ROOT)} sample_runs={stable.get('sample_runs')}, expected >= 3")

    if failures:
        sys.stdout.write("\n".join(failures) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
