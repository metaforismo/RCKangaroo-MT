#!/usr/bin/env python3
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPERIMENTS = ROOT / "autoresearch" / "experiments"


def check_command_backed_gate(
    failures: list[str],
    filename: str,
    command: list[str],
) -> None:
    path = EXPERIMENTS / filename
    if not path.exists():
        failures.append(f"{path.relative_to(ROOT)} missing command-backed Metal gate")
        return
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("build_target") != "macos-build":
        failures.append(f"{path.relative_to(ROOT)} build_target should use macos-build")
    if data.get("bench_command") != command:
        failures.append(f"{path.relative_to(ROOT)} bench_command should run the direct Metal CLI")
    if int(data.get("sample_runs", 0)) < 3:
        failures.append(f"{path.relative_to(ROOT)} sample_runs={data.get('sample_runs')}, expected >= 3")


def main() -> int:
    failures: list[str] = []
    for path in sorted(EXPERIMENTS.glob("metal_*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        sample_runs = int(data.get("sample_runs", 0))
        if sample_runs < 3:
            failures.append(f"{path.relative_to(ROOT)} sample_runs={sample_runs}, expected >= 3")
        if data.get("name") == "metal_jacobian_jump_walk_dp" and sample_runs < 5:
            failures.append(f"{path.relative_to(ROOT)} sample_runs={sample_runs}, expected >= 5 for primary Metal DP gate")

    check_command_backed_gate(
        failures,
        "metal_field_add.json",
        ["./macos/rck_macos", "metal-field-bench", "--iterations", "1048576", "--min-ms", "50"],
    )
    check_command_backed_gate(
        failures,
        "metal_field_mul.json",
        ["./macos/rck_macos", "metal-field-mul-bench", "--iterations", "1048576", "--min-ms", "50"],
    )
    check_command_backed_gate(
        failures,
        "metal_field_square.json",
        ["./macos/rck_macos", "metal-field-square-bench", "--iterations", "1048576", "--min-ms", "50"],
    )
    check_command_backed_gate(
        failures,
        "metal_field_square_mul.json",
        ["./macos/rck_macos", "metal-field-square-mul-bench", "--iterations", "1048576", "--min-ms", "50"],
    )

    stable_path = EXPERIMENTS / "metal_jacobian_jump_walk_dp_stable.json"
    if not stable_path.exists():
        failures.append(f"{stable_path.relative_to(ROOT)} missing stable Metal DP gate")
    else:
        stable = json.loads(stable_path.read_text(encoding="utf-8"))
        expected_command = [
            "./macos/rck_macos",
            "metal-jacobian-jump-walk-bench",
            "--iterations",
            "16384",
            "--steps",
            "8",
            "--jumps",
            "16",
            "--dp-bits",
            "4",
            "--min-ms",
            "200",
        ]
        if stable.get("build_target") != "macos-build":
            failures.append(f"{stable_path.relative_to(ROOT)} build_target should use macos-build")
        if stable.get("bench_command") != expected_command:
            failures.append(f"{stable_path.relative_to(ROOT)} bench_command should run the stable Metal DP CLI")
        if int(stable.get("sample_runs", 0)) < 3:
            failures.append(f"{stable_path.relative_to(ROOT)} sample_runs={stable.get('sample_runs')}, expected >= 3")

    dynamic_stable_path = EXPERIMENTS / "metal_jacobian_dynamic_walk_dp_stable.json"
    if not dynamic_stable_path.exists():
        failures.append(f"{dynamic_stable_path.relative_to(ROOT)} missing stable Metal dynamic DP gate")
    else:
        dynamic_stable = json.loads(dynamic_stable_path.read_text(encoding="utf-8"))
        if dynamic_stable.get("bench_target") != "macos-metal-jacobian-dynamic-walk-stable-bench":
            failures.append(f"{dynamic_stable_path.relative_to(ROOT)} bench_target should use the stable Metal dynamic make target")
        if int(dynamic_stable.get("sample_runs", 0)) < 3:
            failures.append(f"{dynamic_stable_path.relative_to(ROOT)} sample_runs={dynamic_stable.get('sample_runs')}, expected >= 3")

    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    if "macos-metal-jacobian-dynamic-walk-stable-bench:" not in makefile:
        failures.append("Makefile missing macos-metal-jacobian-dynamic-walk-stable-bench target")

    compact_dynamic_path = EXPERIMENTS / "metal_jacobian_dynamic_compact_dp.json"
    if not compact_dynamic_path.exists():
        failures.append(f"{compact_dynamic_path.relative_to(ROOT)} missing compact dynamic DP gate")
    else:
        compact_dynamic = json.loads(compact_dynamic_path.read_text(encoding="utf-8"))
        if compact_dynamic.get("bench_target") != "macos-metal-jacobian-dynamic-compact-dp-stable-bench":
            failures.append(f"{compact_dynamic_path.relative_to(ROOT)} bench_target should use the stable compact dynamic DP make target")
        if int(compact_dynamic.get("sample_runs", 0)) < 3:
            failures.append(f"{compact_dynamic_path.relative_to(ROOT)} sample_runs={compact_dynamic.get('sample_runs')}, expected >= 3")

    if "macos-metal-jacobian-dynamic-compact-dp-stable-bench:" not in makefile:
        failures.append("Makefile missing macos-metal-jacobian-dynamic-compact-dp-stable-bench target")

    stream_dynamic_path = EXPERIMENTS / "metal_jacobian_dynamic_dp_stream.json"
    if not stream_dynamic_path.exists():
        failures.append(f"{stream_dynamic_path.relative_to(ROOT)} missing dynamic DP stream gate")
    else:
        stream_dynamic = json.loads(stream_dynamic_path.read_text(encoding="utf-8"))
        if stream_dynamic.get("bench_target") != "macos-metal-jacobian-dynamic-dp-stream-stable-bench":
            failures.append(f"{stream_dynamic_path.relative_to(ROOT)} bench_target should use the stable dynamic DP stream make target")
        if int(stream_dynamic.get("sample_runs", 0)) < 3:
            failures.append(f"{stream_dynamic_path.relative_to(ROOT)} sample_runs={stream_dynamic.get('sample_runs')}, expected >= 3")

    if "macos-metal-jacobian-dynamic-dp-stream-stable-bench:" not in makefile:
        failures.append("Makefile missing macos-metal-jacobian-dynamic-dp-stream-stable-bench target")

    stream_dynamic_dp8_path = EXPERIMENTS / "metal_jacobian_dynamic_dp_stream_dp8.json"
    if not stream_dynamic_dp8_path.exists():
        failures.append(f"{stream_dynamic_dp8_path.relative_to(ROOT)} missing dynamic DP stream dp8 gate")
    else:
        stream_dynamic_dp8 = json.loads(stream_dynamic_dp8_path.read_text(encoding="utf-8"))
        expected_command = [
            "./macos/rck_macos",
            "metal-jacobian-dynamic-dp-stream-bench",
            "--iterations",
            "16384",
            "--steps",
            "8",
            "--jumps",
            "16",
            "--dp-bits",
            "8",
            "--min-ms",
            "200",
        ]
        if stream_dynamic_dp8.get("build_target") != "macos-build":
            failures.append(f"{stream_dynamic_dp8_path.relative_to(ROOT)} build_target should use macos-build")
        if stream_dynamic_dp8.get("bench_command") != expected_command:
            failures.append(f"{stream_dynamic_dp8_path.relative_to(ROOT)} bench_command should run the DP8 stream CLI")
        if int(stream_dynamic_dp8.get("sample_runs", 0)) < 3:
            failures.append(f"{stream_dynamic_dp8_path.relative_to(ROOT)} sample_runs={stream_dynamic_dp8.get('sample_runs')}, expected >= 3")

    stream_dynamic_dp10_path = EXPERIMENTS / "metal_jacobian_dynamic_dp_stream_dp10.json"
    if not stream_dynamic_dp10_path.exists():
        failures.append(f"{stream_dynamic_dp10_path.relative_to(ROOT)} missing command-backed dynamic DP stream dp10 gate")
    else:
        stream_dynamic_dp10 = json.loads(stream_dynamic_dp10_path.read_text(encoding="utf-8"))
        expected_command = [
            "./macos/rck_macos",
            "metal-jacobian-dynamic-dp-stream-bench",
            "--iterations",
            "16384",
            "--steps",
            "8",
            "--jumps",
            "16",
            "--dp-bits",
            "10",
            "--min-ms",
            "200",
        ]
        if stream_dynamic_dp10.get("build_target") != "macos-build":
            failures.append(f"{stream_dynamic_dp10_path.relative_to(ROOT)} build_target should use macos-build")
        if stream_dynamic_dp10.get("bench_command") != expected_command:
            failures.append(f"{stream_dynamic_dp10_path.relative_to(ROOT)} bench_command should run the DP10 stream CLI")
        if int(stream_dynamic_dp10.get("sample_runs", 0)) < 3:
            failures.append(f"{stream_dynamic_dp10_path.relative_to(ROOT)} sample_runs={stream_dynamic_dp10.get('sample_runs')}, expected >= 3")

    count_dynamic_dp8_path = EXPERIMENTS / "metal_jacobian_dynamic_dp_count_dp8.json"
    if not count_dynamic_dp8_path.exists():
        failures.append(f"{count_dynamic_dp8_path.relative_to(ROOT)} missing dynamic DP count dp8 gate")
    else:
        count_dynamic_dp8 = json.loads(count_dynamic_dp8_path.read_text(encoding="utf-8"))
        if count_dynamic_dp8.get("bench_target") != "macos-metal-jacobian-dynamic-dp-count-dp8-stable-bench":
            failures.append(f"{count_dynamic_dp8_path.relative_to(ROOT)} bench_target should use the stable dynamic DP count dp8 make target")
        if int(count_dynamic_dp8.get("sample_runs", 0)) < 3:
            failures.append(f"{count_dynamic_dp8_path.relative_to(ROOT)} sample_runs={count_dynamic_dp8.get('sample_runs')}, expected >= 3")

    if "macos-metal-jacobian-dynamic-dp-count-dp8-stable-bench:" not in makefile:
        failures.append("Makefile missing macos-metal-jacobian-dynamic-dp-count-dp8-stable-bench target")

    stream_dynamic_dp12_path = EXPERIMENTS / "metal_jacobian_dynamic_dp_stream_dp12.json"
    if not stream_dynamic_dp12_path.exists():
        failures.append(f"{stream_dynamic_dp12_path.relative_to(ROOT)} missing command-backed dynamic DP stream dp12 gate")
    else:
        stream_dynamic_dp12 = json.loads(stream_dynamic_dp12_path.read_text(encoding="utf-8"))
        expected_command = [
            "./macos/rck_macos",
            "metal-jacobian-dynamic-dp-stream-bench",
            "--iterations",
            "16384",
            "--steps",
            "8",
            "--jumps",
            "16",
            "--dp-bits",
            "12",
            "--min-ms",
            "200",
        ]
        if stream_dynamic_dp12.get("build_target") != "macos-build":
            failures.append(f"{stream_dynamic_dp12_path.relative_to(ROOT)} build_target should use macos-build")
        if stream_dynamic_dp12.get("bench_command") != expected_command:
            failures.append(f"{stream_dynamic_dp12_path.relative_to(ROOT)} bench_command should run the DP12 stream CLI")
        if int(stream_dynamic_dp12.get("sample_runs", 0)) < 3:
            failures.append(f"{stream_dynamic_dp12_path.relative_to(ROOT)} sample_runs={stream_dynamic_dp12.get('sample_runs')}, expected >= 3")

    if "macos-metal-jacobian-dynamic-dp-stream-dp12-stable-bench:" not in makefile:
        failures.append("Makefile missing macos-metal-jacobian-dynamic-dp-stream-dp12-stable-bench target")

    inplace_stream_path = EXPERIMENTS / "metal_jacobian_dynamic_dp_stream_inplace.json"
    if not inplace_stream_path.exists():
        failures.append(f"{inplace_stream_path.relative_to(ROOT)} missing command-backed in-place DP8 stream gate")
    else:
        inplace_stream = json.loads(inplace_stream_path.read_text(encoding="utf-8"))
        expected_command = [
            "./macos/rck_macos",
            "metal-jacobian-dynamic-dp-stream-inplace-bench",
            "--iterations",
            "16384",
            "--steps",
            "8",
            "--jumps",
            "16",
            "--dp-bits",
            "8",
            "--min-ms",
            "200",
        ]
        if inplace_stream.get("build_target") != "macos-build":
            failures.append(f"{inplace_stream_path.relative_to(ROOT)} build_target should use macos-build")
        if inplace_stream.get("bench_command") != expected_command:
            failures.append(f"{inplace_stream_path.relative_to(ROOT)} bench_command should run the in-place DP8 stream CLI")
        if int(inplace_stream.get("sample_runs", 0)) < 3:
            failures.append(f"{inplace_stream_path.relative_to(ROOT)} sample_runs={inplace_stream.get('sample_runs')}, expected >= 3")

    inplace_steps16_path = EXPERIMENTS / "metal_jacobian_dynamic_dp_stream_inplace_steps16.json"
    if not inplace_steps16_path.exists():
        failures.append(f"{inplace_steps16_path.relative_to(ROOT)} missing command-backed in-place DP8 stream steps16 gate")
    else:
        inplace_steps16 = json.loads(inplace_steps16_path.read_text(encoding="utf-8"))
        expected_command = [
            "./macos/rck_macos",
            "metal-jacobian-dynamic-dp-stream-inplace-bench",
            "--iterations",
            "16384",
            "--steps",
            "16",
            "--jumps",
            "16",
            "--dp-bits",
            "8",
            "--min-ms",
            "200",
        ]
        if inplace_steps16.get("build_target") != "macos-build":
            failures.append(f"{inplace_steps16_path.relative_to(ROOT)} build_target should use macos-build")
        if inplace_steps16.get("bench_command") != expected_command:
            failures.append(f"{inplace_steps16_path.relative_to(ROOT)} bench_command should run the in-place DP8 stream steps16 CLI")
        if int(inplace_steps16.get("sample_runs", 0)) < 3:
            failures.append(f"{inplace_steps16_path.relative_to(ROOT)} sample_runs={inplace_steps16.get('sample_runs')}, expected >= 3")

    stream_dynamic_dp14_path = EXPERIMENTS / "metal_jacobian_dynamic_dp_stream_dp14.json"
    if not stream_dynamic_dp14_path.exists():
        failures.append(f"{stream_dynamic_dp14_path.relative_to(ROOT)} missing command-backed dynamic DP stream dp14 gate")
    else:
        stream_dynamic_dp14 = json.loads(stream_dynamic_dp14_path.read_text(encoding="utf-8"))
        expected_command = [
            "./macos/rck_macos",
            "metal-jacobian-dynamic-dp-stream-bench",
            "--iterations",
            "16384",
            "--steps",
            "8",
            "--jumps",
            "16",
            "--dp-bits",
            "14",
            "--min-ms",
            "200",
        ]
        if stream_dynamic_dp14.get("build_target") != "macos-build":
            failures.append(f"{stream_dynamic_dp14_path.relative_to(ROOT)} build_target should use macos-build")
        if stream_dynamic_dp14.get("bench_command") != expected_command:
            failures.append(f"{stream_dynamic_dp14_path.relative_to(ROOT)} bench_command should run the DP14 stream CLI")
        if int(stream_dynamic_dp14.get("sample_runs", 0)) < 3:
            failures.append(f"{stream_dynamic_dp14_path.relative_to(ROOT)} sample_runs={stream_dynamic_dp14.get('sample_runs')}, expected >= 3")

    stream_dynamic_dp16_large_path = EXPERIMENTS / "metal_jacobian_dynamic_dp_stream_dp16_large.json"
    if not stream_dynamic_dp16_large_path.exists():
        failures.append(f"{stream_dynamic_dp16_large_path.relative_to(ROOT)} missing command-backed dynamic DP stream dp16 large gate")
    else:
        stream_dynamic_dp16_large = json.loads(stream_dynamic_dp16_large_path.read_text(encoding="utf-8"))
        expected_command = [
            "./macos/rck_macos",
            "metal-jacobian-dynamic-dp-stream-bench",
            "--iterations",
            "65536",
            "--steps",
            "8",
            "--jumps",
            "16",
            "--dp-bits",
            "16",
            "--min-ms",
            "200",
        ]
        if stream_dynamic_dp16_large.get("build_target") != "macos-build":
            failures.append(f"{stream_dynamic_dp16_large_path.relative_to(ROOT)} build_target should use macos-build")
        if stream_dynamic_dp16_large.get("bench_command") != expected_command:
            failures.append(f"{stream_dynamic_dp16_large_path.relative_to(ROOT)} bench_command should run the DP16 large stream CLI")
        if int(stream_dynamic_dp16_large.get("sample_runs", 0)) < 3:
            failures.append(f"{stream_dynamic_dp16_large_path.relative_to(ROOT)} sample_runs={stream_dynamic_dp16_large.get('sample_runs')}, expected >= 3")

    if failures:
        sys.stdout.write("\n".join(failures) + "\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
