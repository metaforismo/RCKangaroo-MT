#!/usr/bin/env python3
from __future__ import annotations

import contextlib
import importlib.util
import io
import subprocess
import tempfile
from pathlib import Path


root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("runner", root / "autoresearch" / "runner.py")
runner = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(runner)

experiment = {
    "name": "jacobian_kangaroo_multi_small",
    "description": "test experiment",
    "min_improvement_ratio": 0.02,
}
metrics = {
    "backend": "macos_cpu",
    "operation": "jacobian_kangaroo_multi_small",
    "iterations": 8,
    "sample_count": 1,
    "min_ms": 50,
    "seconds": 0.1,
    "ops_per_sec": 80.0,
    "correctness": True,
    "skipped": False,
    "reason": "",
    "single_target_ops_per_sec": 20.0,
    "speedup_vs_single": 4.0,
    "target_throughput_vs_single": 16.0,
}

row = runner.build_benchmark_row(
    experiment=experiment,
    metrics=metrics,
    budget_sec=5,
    commit="abc123",
    machine="test-machine",
    previous=70.0,
    paired_baseline=None,
    paired_baseline_ref="",
    timestamp="2026-01-01T00:00:00Z",
)

assert row["status"] == "keep"
assert row["single_target_ops_per_sec"] == 20.0
assert row["speedup_vs_single"] == 4.0
assert row["target_throughput_vs_single"] == 16.0
assert row["commit"] == "abc123"
assert row["machine"] == "test-machine"
assert row["cooldown_sec"] == 0.0

git_call_args: list[list[str]] = []


def fake_dirty_git_command(args: list[str], timeout: int, cwd: Path = runner.ROOT) -> subprocess.CompletedProcess[str]:
    git_call_args.append(args)
    if args == ["git", "rev-parse", "--short", "HEAD"]:
        return subprocess.CompletedProcess(args, 0, stdout="abc123\n")
    if args == ["git", "status", "--porcelain"]:
        return subprocess.CompletedProcess(args, 0, stdout=" M autoresearch/runner.py\n")
    raise AssertionError(f"unexpected git command: {args!r}")


original_run_command = runner.run_command
runner.run_command = fake_dirty_git_command
try:
    assert runner.git_commit(Path("/tmp/rck-dirty")) == "abc123-dirty"
finally:
    runner.run_command = original_run_command

assert git_call_args == [
    ["git", "rev-parse", "--short", "HEAD"],
    ["git", "status", "--porcelain"],
]

same_tree_git_calls: list[tuple[Path, list[str]]] = []
same_tree_dirty = False


def fake_same_tree_git_command(args: list[str], timeout: int, cwd: Path = runner.ROOT) -> subprocess.CompletedProcess[str]:
    same_tree_git_calls.append((cwd, args))
    if args == ["git", "status", "--porcelain"]:
        return subprocess.CompletedProcess(args, 0, stdout=" M touched.cpp\n" if same_tree_dirty else "")
    if args == ["git", "rev-parse", "HEAD^{tree}"]:
        return subprocess.CompletedProcess(args, 0, stdout="same-tree\n")
    raise AssertionError(f"unexpected same-tree git command: {args!r}")


runner.run_command = fake_same_tree_git_command
try:
    assert runner.same_clean_tree(Path("/tmp/baseline"), Path("/tmp/candidate")) is True
    same_tree_dirty = True
    assert runner.same_clean_tree(Path("/tmp/baseline"), Path("/tmp/candidate")) is False
finally:
    runner.run_command = original_run_command

assert same_tree_git_calls == [
    (Path("/tmp/candidate"), ["git", "status", "--porcelain"]),
    (Path("/tmp/baseline"), ["git", "rev-parse", "HEAD^{tree}"]),
    (Path("/tmp/candidate"), ["git", "rev-parse", "HEAD^{tree}"]),
    (Path("/tmp/candidate"), ["git", "status", "--porcelain"]),
]

paired_row = runner.build_benchmark_row(
    experiment=dict(experiment, cooldown_sec=3),
    metrics=dict(metrics, ops_per_sec=84.0),
    budget_sec=5,
    commit="abc124",
    machine="test-machine",
    previous=100.0,
    paired_baseline=dict(metrics, ops_per_sec=80.0),
    paired_baseline_ref="main",
    timestamp="2026-01-01T00:00:01Z",
)
assert paired_row["status"] == "keep"
assert paired_row["paired_baseline_ref"] == "main"
assert paired_row["paired_order"] == "baseline_first"
assert paired_row["paired_baseline_ops_per_sec"] == 80.0
assert paired_row["paired_speedup"] == 1.05
assert paired_row["cooldown_sec"] == 3.0

same_tree_paired_row = runner.build_benchmark_row(
    experiment=dict(experiment, cooldown_sec=3),
    metrics=dict(metrics, ops_per_sec=840.0, same_tree_paired_baseline=True),
    budget_sec=5,
    commit="abc124",
    machine="test-machine",
    previous=100.0,
    paired_baseline=dict(metrics, ops_per_sec=80.0),
    paired_baseline_ref="HEAD",
    timestamp="2026-01-01T00:00:01Z",
)
assert same_tree_paired_row["status"] == "discard"
assert same_tree_paired_row["same_tree_paired_baseline"] is True
assert same_tree_paired_row["paired_speedup"] == 10.5
assert "same clean candidate tree" in same_tree_paired_row["reason"]

samples = [
    dict(metrics, iterations=5, seconds=0.10, ops_per_sec=50.0),
    dict(metrics, iterations=10, seconds=0.10, ops_per_sec=100.0),
    dict(metrics, iterations=15, seconds=0.10, ops_per_sec=150.0),
]
aggregated = runner.aggregate_metric_samples(samples)
assert aggregated["ops_per_sec"] == 100.0
assert aggregated["ops_per_sec_min"] == 50.0
assert aggregated["ops_per_sec_max"] == 150.0
assert aggregated["sample_metric"] == "ops_per_sec"
assert aggregated["sample_metric_values"] == [50.0, 100.0, 150.0]
assert aggregated["sample_spread_ratio"] == 3.0
assert aggregated["runner_sample_count"] == 3
assert aggregated["iterations"] == 10
assert aggregated["correctness"] is True

spread_row = runner.build_benchmark_row(
    experiment=dict(experiment, max_sample_spread_ratio=2.0),
    metrics=aggregated,
    budget_sec=5,
    commit="abc126",
    machine="test-machine",
    previous=70.0,
    paired_baseline=None,
    paired_baseline_ref="",
    timestamp="2026-01-01T00:00:04Z",
)
assert spread_row["status"] == "discard"
assert spread_row["max_sample_spread_ratio"] == 2.0
assert "sample spread ratio 3.000000 exceeds max 2.000000" in spread_row["reason"]

paired_baseline_spread_row = runner.build_benchmark_row(
    experiment=dict(experiment, max_sample_spread_ratio=2.0),
    metrics=dict(metrics, ops_per_sec=110.0, sample_spread_ratio=1.0),
    budget_sec=5,
    commit="abc127",
    machine="test-machine",
    previous=None,
    paired_baseline=dict(metrics, ops_per_sec=100.0, sample_spread_ratio=3.0),
    paired_baseline_ref="main",
    timestamp="2026-01-01T00:00:05Z",
)
assert paired_baseline_spread_row["status"] == "discard"
assert paired_baseline_spread_row["paired_speedup"] == 1.1
assert paired_baseline_spread_row["paired_baseline_sample_spread_ratio"] == 3.0
assert "paired baseline sample spread ratio 3.000000 exceeds max 2.000000" in paired_baseline_spread_row["reason"]

required_metric_row = runner.build_benchmark_row(
    experiment=dict(
        experiment,
        required_metrics={
            "target_lookup_checksum": "0xabc",
            "dp_count": 1053,
            "jump_histogram_max_deviation_ppm": {"max": 1000},
        },
    ),
    metrics=dict(
        metrics,
        target_lookup_checksum="0xdef",
        dp_count=990,
        jump_histogram_max_deviation_ppm=1200,
    ),
    budget_sec=5,
    commit="abc128",
    machine="test-machine",
    previous=None,
    paired_baseline=None,
    paired_baseline_ref="",
    timestamp="2026-01-01T00:00:06Z",
)
assert required_metric_row["status"] == "crash"
assert required_metric_row["correctness"] is False
assert required_metric_row["benchmark_correctness"] is True
assert required_metric_row["required_metrics_passed"] is False
assert "required metric target_lookup_checksum expected 0xabc got 0xdef" in required_metric_row["reason"]
assert "required metric dp_count expected 1053 got 990" in required_metric_row["reason"]
assert "required metric jump_histogram_max_deviation_ppm expected <= 1000 got 1200" in required_metric_row["reason"]

paired_baseline_required_metric_row = runner.build_benchmark_row(
    experiment=dict(
        experiment,
        required_metrics={
            "target_lookup_checksum": "0xabc",
            "dp_count": 1053,
        },
    ),
    metrics=dict(metrics, ops_per_sec=200.0, target_lookup_checksum="0xabc", dp_count=1053),
    budget_sec=5,
    commit="abc129",
    machine="test-machine",
    previous=None,
    paired_baseline=dict(metrics, ops_per_sec=100.0, target_lookup_checksum="0xdef", dp_count=1053),
    paired_baseline_ref="main",
    timestamp="2026-01-01T00:00:07Z",
)
assert paired_baseline_required_metric_row["status"] == "discard"
assert paired_baseline_required_metric_row["paired_speedup"] == 2.0
assert paired_baseline_required_metric_row["paired_baseline_required_metrics_passed"] is False
assert "paired baseline failed required metrics" in paired_baseline_required_metric_row["reason"]
assert "required metric target_lookup_checksum expected 0xabc got 0xdef" in paired_baseline_required_metric_row["reason"]

lookup_samples = [
    dict(metrics, operation="target_lookup_exact256", lookups_per_sec=10.0, ops_per_sec=0.0),
    dict(metrics, operation="target_lookup_exact256", lookups_per_sec=20.0, ops_per_sec=0.0),
    dict(metrics, operation="target_lookup_exact256", lookups_per_sec=30.0, ops_per_sec=0.0),
]
lookup_aggregated = runner.aggregate_metric_samples(lookup_samples, metric_name="lookups_per_sec")
assert lookup_aggregated["lookups_per_sec"] == 20.0
assert lookup_aggregated["lookups_per_sec_min"] == 10.0
assert lookup_aggregated["lookups_per_sec_max"] == 30.0
assert lookup_aggregated["sample_metric"] == "lookups_per_sec"
assert lookup_aggregated["ops_per_sec"] == 20.0

zero_spread = runner.aggregate_metric_samples([
    dict(metrics, ops_per_sec=0.0),
    dict(metrics, ops_per_sec=10.0),
])
assert zero_spread["sample_spread_ratio"] == 1.0e300

jump_walk_experiment = runner.load_experiment("jacobian_jump_walk")
assert int(jump_walk_experiment.get("sample_runs", 1)) >= 3
assert jump_walk_experiment.get("build_target") == "macos-build"
assert runner.experiment_bench_command(jump_walk_experiment) == [
    "./macos/rck_macos",
    "jacobian-walk-bench",
    "--iterations",
    "256",
    "--min-ms",
    "50",
    "--jumps",
    "16",
]

kangaroo_experiment_commands = {
    "jacobian_kangaroo_small": [
        "./macos/rck_macos",
        "jacobian-kangaroo-small-bench",
        "--iterations",
        "1",
        "--min-ms",
        "50",
        "--range",
        "8",
        "--jumps",
        "8",
        "--dp-bits",
        "0",
        "--max-steps",
        "4096",
    ],
    "jacobian_kangaroo_multi_small": [
        "./macos/rck_macos",
        "jacobian-kangaroo-multi-small-bench",
        "--target-count",
        "4",
        "--iterations",
        "1",
        "--min-ms",
        "50",
        "--range",
        "8",
        "--jumps",
        "8",
        "--dp-bits",
        "0",
        "--max-steps",
        "4096",
    ],
    "jacobian_kangaroo_multi16_small": [
        "./macos/rck_macos",
        "jacobian-kangaroo-multi-small-bench",
        "--target-count",
        "16",
        "--iterations",
        "1",
        "--min-ms",
        "50",
        "--range",
        "8",
        "--jumps",
        "8",
        "--dp-bits",
        "0",
        "--max-steps",
        "4096",
    ],
}
for experiment_name, expected_command in kangaroo_experiment_commands.items():
    loaded = runner.load_experiment(experiment_name)
    assert loaded.get("build_target") == "macos-build"
    assert runner.experiment_bench_command(loaded) == expected_command

call_order: list[str] = []
baseline_cwd = Path("/tmp/rck-baseline")
candidate_cwd = Path("/tmp/rck-candidate")
sample_ops = {
    "baseline": [80.0, 100.0, 120.0],
    "candidate": [84.0, 105.0, 126.0],
}


def fake_run_command(args: list[str], timeout: int, cwd: Path = runner.ROOT) -> subprocess.CompletedProcess[str]:
    assert args == ["make", "fake-bench"]
    label = "baseline" if cwd == baseline_cwd else "candidate"
    call_order.append(label)
    ops = sample_ops[label].pop(0)
    payload = dict(metrics, ops_per_sec=ops, iterations=int(ops))
    return subprocess.CompletedProcess(args, 0, stdout=f"{runner.json.dumps(payload)}\n")


runner.run_command = fake_run_command
try:
    with contextlib.redirect_stdout(io.StringIO()):
        paired_baseline_metrics, paired_candidate_metrics = runner.run_paired_experiment_samples(
            dict(experiment, bench_target="fake-bench", sample_runs=3),
            timeout=10,
            baseline_cwd=baseline_cwd,
            candidate_cwd=candidate_cwd,
        )
finally:
    runner.run_command = original_run_command

assert call_order == ["baseline", "candidate", "baseline", "candidate", "baseline", "candidate"]
assert paired_baseline_metrics["ops_per_sec"] == 100.0
assert paired_candidate_metrics["ops_per_sec"] == 105.0

alternate_call_order: list[str] = []
alternate_sample_ops = {
    "baseline": [80.0, 100.0, 120.0, 140.0],
    "candidate": [84.0, 105.0, 126.0, 147.0],
}


def fake_alternate_run_command(args: list[str], timeout: int, cwd: Path = runner.ROOT) -> subprocess.CompletedProcess[str]:
    assert args == ["make", "fake-bench"]
    label = "baseline" if cwd == baseline_cwd else "candidate"
    alternate_call_order.append(label)
    ops = alternate_sample_ops[label].pop(0)
    payload = dict(metrics, ops_per_sec=ops, iterations=int(ops))
    return subprocess.CompletedProcess(args, 0, stdout=f"{runner.json.dumps(payload)}\n")


runner.run_command = fake_alternate_run_command
try:
    with contextlib.redirect_stdout(io.StringIO()):
        alternate_baseline_metrics, alternate_candidate_metrics = runner.run_paired_experiment_samples(
            dict(experiment, bench_target="fake-bench", sample_runs=4, paired_order="alternate"),
            timeout=10,
            baseline_cwd=baseline_cwd,
            candidate_cwd=candidate_cwd,
        )
finally:
    runner.run_command = original_run_command

assert alternate_call_order == [
    "baseline",
    "candidate",
    "candidate",
    "baseline",
    "baseline",
    "candidate",
    "candidate",
    "baseline",
]
assert alternate_baseline_metrics["ops_per_sec"] == 110.0
assert alternate_candidate_metrics["ops_per_sec"] == 115.5

command_calls: list[tuple[Path, list[str]]] = []


def fake_command_experiment_runner(args: list[str], timeout: int, cwd: Path = runner.ROOT) -> subprocess.CompletedProcess[str]:
    command_calls.append((cwd, args))
    if args == ["make", "macos-build"]:
        return subprocess.CompletedProcess(args, 0, stdout="built\n")
    if args == ["./macos/rck_macos", "fake-bench", "--dp-bits", "10"]:
        payload = dict(metrics, ops_per_sec=123.0, iterations=123)
        return subprocess.CompletedProcess(args, 0, stdout=f"noise\n{runner.json.dumps(payload)}\n")
    raise AssertionError(f"unexpected command-backed experiment command: {args!r}")


runner.run_command = fake_command_experiment_runner
try:
    with contextlib.redirect_stdout(io.StringIO()):
        command_metrics = runner.run_experiment_sample(
            dict(
                experiment,
                build_target="macos-build",
                bench_command=["./macos/rck_macos", "fake-bench", "--dp-bits", "10"],
            ),
            timeout=10,
            cwd=candidate_cwd,
        )
finally:
    runner.run_command = original_run_command

assert command_calls == [
    (candidate_cwd, ["make", "macos-build"]),
    (candidate_cwd, ["./macos/rck_macos", "fake-bench", "--dp-bits", "10"]),
]
assert command_metrics["ops_per_sec"] == 123.0

build_once_calls: list[tuple[Path, list[str]]] = []
build_once_ops = [101.0, 103.0, 105.0]


def fake_build_once_runner(args: list[str], timeout: int, cwd: Path = runner.ROOT) -> subprocess.CompletedProcess[str]:
    build_once_calls.append((cwd, args))
    if args == ["make", "macos-build"]:
        return subprocess.CompletedProcess(args, 0, stdout="built once\n")
    if args == ["./macos/rck_macos", "fake-bench"]:
        ops = build_once_ops.pop(0)
        payload = dict(metrics, ops_per_sec=ops, iterations=int(ops))
        return subprocess.CompletedProcess(args, 0, stdout=f"{runner.json.dumps(payload)}\n")
    raise AssertionError(f"unexpected build-once command: {args!r}")


runner.run_command = fake_build_once_runner
try:
    with contextlib.redirect_stdout(io.StringIO()):
        build_once_metrics = runner.run_experiment_samples(
            dict(
                experiment,
                build_target="macos-build",
                bench_command=["./macos/rck_macos", "fake-bench"],
                sample_runs=3,
            ),
            timeout=10,
            cwd=candidate_cwd,
        )
finally:
    runner.run_command = original_run_command

assert build_once_calls == [
    (candidate_cwd, ["make", "macos-build"]),
    (candidate_cwd, ["./macos/rck_macos", "fake-bench"]),
    (candidate_cwd, ["./macos/rck_macos", "fake-bench"]),
    (candidate_cwd, ["./macos/rck_macos", "fake-bench"]),
]
assert build_once_metrics["ops_per_sec"] == 103.0

cooldown_calls: list[float] = []
cooldown_command_calls: list[tuple[Path, list[str]]] = []
cooldown_ops = [101.0, 103.0, 105.0]


def fake_cooldown_runner(args: list[str], timeout: int, cwd: Path = runner.ROOT) -> subprocess.CompletedProcess[str]:
    cooldown_command_calls.append((cwd, args))
    if args == ["./macos/rck_macos", "fake-bench"]:
        ops = cooldown_ops.pop(0)
        payload = dict(metrics, ops_per_sec=ops, iterations=int(ops))
        return subprocess.CompletedProcess(args, 0, stdout=f"{runner.json.dumps(payload)}\n")
    raise AssertionError(f"unexpected cooldown command: {args!r}")


original_sleep = runner.time.sleep
runner.run_command = fake_cooldown_runner
runner.time.sleep = lambda seconds: cooldown_calls.append(seconds)
try:
    with contextlib.redirect_stdout(io.StringIO()):
        cooldown_metrics = runner.run_experiment_samples(
            dict(
                experiment,
                bench_command=["./macos/rck_macos", "fake-bench"],
                sample_runs=3,
                cooldown_sec=2.5,
            ),
            timeout=10,
            cwd=candidate_cwd,
        )
finally:
    runner.run_command = original_run_command
    runner.time.sleep = original_sleep

assert cooldown_command_calls == [
    (candidate_cwd, ["./macos/rck_macos", "fake-bench"]),
    (candidate_cwd, ["./macos/rck_macos", "fake-bench"]),
    (candidate_cwd, ["./macos/rck_macos", "fake-bench"]),
]
assert cooldown_calls == [2.5, 2.5]
assert cooldown_metrics["ops_per_sec"] == 103.0

paired_build_once_calls: list[tuple[Path, list[str]]] = []
paired_build_once_ops = {
    "baseline": [90.0, 100.0, 110.0],
    "candidate": [95.0, 105.0, 115.0],
}


def fake_paired_build_once_runner(args: list[str], timeout: int, cwd: Path = runner.ROOT) -> subprocess.CompletedProcess[str]:
    paired_build_once_calls.append((cwd, args))
    if args == ["make", "macos-build"]:
        return subprocess.CompletedProcess(args, 0, stdout="paired built once\n")
    if args == ["./macos/rck_macos", "fake-bench"]:
        label = "baseline" if cwd == baseline_cwd else "candidate"
        ops = paired_build_once_ops[label].pop(0)
        payload = dict(metrics, ops_per_sec=ops, iterations=int(ops))
        return subprocess.CompletedProcess(args, 0, stdout=f"{runner.json.dumps(payload)}\n")
    raise AssertionError(f"unexpected paired build-once command: {args!r}")


runner.run_command = fake_paired_build_once_runner
try:
    with contextlib.redirect_stdout(io.StringIO()):
        paired_build_baseline_metrics, paired_build_candidate_metrics = runner.run_paired_experiment_samples(
            dict(
                experiment,
                build_target="macos-build",
                bench_command=["./macos/rck_macos", "fake-bench"],
                sample_runs=3,
            ),
            timeout=10,
            baseline_cwd=baseline_cwd,
            candidate_cwd=candidate_cwd,
        )
finally:
    runner.run_command = original_run_command

assert paired_build_once_calls == [
    (baseline_cwd, ["make", "macos-build"]),
    (candidate_cwd, ["make", "macos-build"]),
    (baseline_cwd, ["./macos/rck_macos", "fake-bench"]),
    (candidate_cwd, ["./macos/rck_macos", "fake-bench"]),
    (baseline_cwd, ["./macos/rck_macos", "fake-bench"]),
    (candidate_cwd, ["./macos/rck_macos", "fake-bench"]),
    (baseline_cwd, ["./macos/rck_macos", "fake-bench"]),
    (candidate_cwd, ["./macos/rck_macos", "fake-bench"]),
]
assert paired_build_baseline_metrics["ops_per_sec"] == 100.0
assert paired_build_candidate_metrics["ops_per_sec"] == 105.0

paired_cooldown_calls: list[float] = []
paired_cooldown_command_calls: list[tuple[Path, list[str]]] = []
paired_cooldown_ops = {
    "baseline": [90.0, 100.0, 110.0],
    "candidate": [95.0, 105.0, 115.0],
}


def fake_paired_cooldown_runner(args: list[str], timeout: int, cwd: Path = runner.ROOT) -> subprocess.CompletedProcess[str]:
    paired_cooldown_command_calls.append((cwd, args))
    if args == ["./macos/rck_macos", "fake-bench"]:
        label = "baseline" if cwd == baseline_cwd else "candidate"
        ops = paired_cooldown_ops[label].pop(0)
        payload = dict(metrics, ops_per_sec=ops, iterations=int(ops))
        return subprocess.CompletedProcess(args, 0, stdout=f"{runner.json.dumps(payload)}\n")
    raise AssertionError(f"unexpected paired cooldown command: {args!r}")


runner.run_command = fake_paired_cooldown_runner
runner.time.sleep = lambda seconds: paired_cooldown_calls.append(seconds)
try:
    with contextlib.redirect_stdout(io.StringIO()):
        paired_cooldown_baseline_metrics, paired_cooldown_candidate_metrics = runner.run_paired_experiment_samples(
            dict(
                experiment,
                bench_command=["./macos/rck_macos", "fake-bench"],
                sample_runs=3,
                cooldown_sec=7,
            ),
            timeout=10,
            baseline_cwd=baseline_cwd,
            candidate_cwd=candidate_cwd,
        )
finally:
    runner.run_command = original_run_command
    runner.time.sleep = original_sleep

assert paired_cooldown_command_calls == [
    (baseline_cwd, ["./macos/rck_macos", "fake-bench"]),
    (candidate_cwd, ["./macos/rck_macos", "fake-bench"]),
    (baseline_cwd, ["./macos/rck_macos", "fake-bench"]),
    (candidate_cwd, ["./macos/rck_macos", "fake-bench"]),
    (baseline_cwd, ["./macos/rck_macos", "fake-bench"]),
    (candidate_cwd, ["./macos/rck_macos", "fake-bench"]),
]
assert paired_cooldown_calls == [7.0, 7.0]
assert paired_cooldown_baseline_metrics["ops_per_sec"] == 100.0
assert paired_cooldown_candidate_metrics["ops_per_sec"] == 105.0

paired_baseline_command_calls: list[tuple[Path, list[str]]] = []
paired_baseline_command_ops = {
    "baseline": [100.0, 101.0, 102.0],
    "candidate": [110.0, 111.0, 112.0],
}


def fake_paired_baseline_command_runner(args: list[str], timeout: int, cwd: Path = runner.ROOT) -> subprocess.CompletedProcess[str]:
    paired_baseline_command_calls.append((cwd, args))
    if args == ["make", "macos-build"]:
        return subprocess.CompletedProcess(args, 0, stdout="paired built once\n")
    if args == ["./macos/rck_macos", "baseline-bench"]:
        ops = paired_baseline_command_ops["baseline"].pop(0)
        payload = dict(metrics, ops_per_sec=ops, iterations=int(ops))
        return subprocess.CompletedProcess(args, 0, stdout=f"{runner.json.dumps(payload)}\n")
    if args == ["./macos/rck_macos", "candidate-bench"]:
        ops = paired_baseline_command_ops["candidate"].pop(0)
        payload = dict(metrics, ops_per_sec=ops, iterations=int(ops))
        return subprocess.CompletedProcess(args, 0, stdout=f"{runner.json.dumps(payload)}\n")
    raise AssertionError(f"unexpected paired baseline-command args: {args!r}")


runner.run_command = fake_paired_baseline_command_runner
try:
    with contextlib.redirect_stdout(io.StringIO()):
        paired_baseline_command_metrics, paired_candidate_command_metrics = runner.run_paired_experiment_samples(
            dict(
                experiment,
                build_target="macos-build",
                paired_baseline_command=["./macos/rck_macos", "baseline-bench"],
                bench_command=["./macos/rck_macos", "candidate-bench"],
                sample_runs=3,
            ),
            timeout=10,
            baseline_cwd=baseline_cwd,
            candidate_cwd=candidate_cwd,
        )
finally:
    runner.run_command = original_run_command

assert paired_baseline_command_calls == [
    (baseline_cwd, ["make", "macos-build"]),
    (candidate_cwd, ["make", "macos-build"]),
    (baseline_cwd, ["./macos/rck_macos", "baseline-bench"]),
    (candidate_cwd, ["./macos/rck_macos", "candidate-bench"]),
    (baseline_cwd, ["./macos/rck_macos", "baseline-bench"]),
    (candidate_cwd, ["./macos/rck_macos", "candidate-bench"]),
    (baseline_cwd, ["./macos/rck_macos", "baseline-bench"]),
    (candidate_cwd, ["./macos/rck_macos", "candidate-bench"]),
]
assert paired_baseline_command_metrics["ops_per_sec"] == 101.0
assert paired_candidate_command_metrics["ops_per_sec"] == 111.0

paired_confirm_calls: list[tuple[Path, list[str]]] = []
paired_confirm_ops = {
    "baseline": [100.0, 110.0, 120.0, 130.0],
    "candidate": [105.0, 115.0, 125.0, 135.0],
}


def fake_paired_confirmation_runner(args: list[str], timeout: int, cwd: Path = runner.ROOT) -> subprocess.CompletedProcess[str]:
    paired_confirm_calls.append((cwd, args))
    if args[:3] == ["git", "worktree", "add"]:
        return subprocess.CompletedProcess(args, 0, stdout="added baseline\n")
    if args[:3] == ["git", "worktree", "remove"]:
        return subprocess.CompletedProcess(args, 0, stdout="removed baseline\n")
    if args == ["git", "status", "--porcelain"]:
        return subprocess.CompletedProcess(args, 0, stdout="")
    if args == ["git", "rev-parse", "HEAD^{tree}"]:
        label = "baseline" if cwd.name == "baseline" else "candidate"
        return subprocess.CompletedProcess(args, 0, stdout=f"{label}-tree\n")
    if args == ["make", "macos-check"]:
        return subprocess.CompletedProcess(args, 0, stdout="checked baseline\n")
    if args == ["make", "macos-build"]:
        return subprocess.CompletedProcess(args, 0, stdout="built once\n")
    if args == ["./macos/rck_macos", "fake-bench"]:
        label = "baseline" if cwd.name == "baseline" else "candidate"
        ops = paired_confirm_ops[label].pop(0)
        payload = dict(metrics, ops_per_sec=ops, iterations=int(ops))
        return subprocess.CompletedProcess(args, 0, stdout=f"{runner.json.dumps(payload)}\n")
    raise AssertionError(f"unexpected paired confirmation command: {args!r}")


original_git_commit = runner.git_commit
runner.run_command = fake_paired_confirmation_runner
runner.git_commit = lambda cwd=runner.ROOT: "base123"
try:
    with contextlib.redirect_stdout(io.StringIO()):
        paired_confirmation_metrics = runner.run_paired_baseline_and_candidate_confirmations(
            dict(
                experiment,
                build_target="macos-build",
                bench_command=["./macos/rck_macos", "fake-bench"],
                sample_runs=2,
            ),
            timeout=10,
            ref="main",
            candidate_cwd=candidate_cwd,
            confirm_runs=2,
        )
finally:
    runner.run_command = original_run_command
    runner.git_commit = original_git_commit

paired_confirm_command_args = [args for _, args in paired_confirm_calls]
assert paired_confirm_command_args.count(["make", "macos-check"]) == 1
assert paired_confirm_command_args.count(["make", "macos-build"]) == 2
assert paired_confirm_command_args.count(["./macos/rck_macos", "fake-bench"]) == 8
assert len(paired_confirmation_metrics) == 2
assert paired_confirmation_metrics[0][0]["ops_per_sec"] == 105.0
assert paired_confirmation_metrics[0][1]["ops_per_sec"] == 110.0
assert paired_confirmation_metrics[1][0]["ops_per_sec"] == 125.0
assert paired_confirmation_metrics[1][1]["ops_per_sec"] == 130.0

paired_command_diff_calls: list[tuple[Path, list[str]]] = []
paired_command_diff_ops = {
    "baseline": [100.0],
    "candidate": [120.0],
}


def fake_paired_command_diff_runner(args: list[str], timeout: int, cwd: Path = runner.ROOT) -> subprocess.CompletedProcess[str]:
    paired_command_diff_calls.append((cwd, args))
    if args[:3] == ["git", "worktree", "add"]:
        return subprocess.CompletedProcess(args, 0, stdout="added baseline\n")
    if args[:3] == ["git", "worktree", "remove"]:
        return subprocess.CompletedProcess(args, 0, stdout="removed baseline\n")
    if args == ["git", "status", "--porcelain"] or args == ["git", "rev-parse", "HEAD^{tree}"]:
        raise AssertionError("different paired commands should not run same-tree noise detection")
    if args == ["make", "macos-check"]:
        return subprocess.CompletedProcess(args, 0, stdout="checked baseline\n")
    if args == ["make", "macos-build"]:
        return subprocess.CompletedProcess(args, 0, stdout="built once\n")
    if args == ["./macos/rck_macos", "baseline-bench"]:
        ops = paired_command_diff_ops["baseline"].pop(0)
        payload = dict(metrics, ops_per_sec=ops, iterations=int(ops))
        return subprocess.CompletedProcess(args, 0, stdout=f"{runner.json.dumps(payload)}\n")
    if args == ["./macos/rck_macos", "candidate-bench"]:
        ops = paired_command_diff_ops["candidate"].pop(0)
        payload = dict(metrics, ops_per_sec=ops, iterations=int(ops))
        return subprocess.CompletedProcess(args, 0, stdout=f"{runner.json.dumps(payload)}\n")
    raise AssertionError(f"unexpected paired command-diff command: {args!r}")


runner.run_command = fake_paired_command_diff_runner
runner.git_commit = lambda cwd=runner.ROOT: "base123"
try:
    with contextlib.redirect_stdout(io.StringIO()):
        paired_command_diff_metrics = runner.run_paired_baseline_and_candidate_confirmations(
            dict(
                experiment,
                build_target="macos-build",
                paired_baseline_command=["./macos/rck_macos", "baseline-bench"],
                bench_command=["./macos/rck_macos", "candidate-bench"],
                sample_runs=1,
            ),
            timeout=10,
            ref="main",
            candidate_cwd=candidate_cwd,
            confirm_runs=1,
        )
finally:
    runner.run_command = original_run_command
    runner.git_commit = original_git_commit

assert len(paired_command_diff_metrics) == 1
assert paired_command_diff_metrics[0][0]["ops_per_sec"] == 100.0
assert paired_command_diff_metrics[0][1]["ops_per_sec"] == 120.0
assert "same_tree_paired_baseline" not in paired_command_diff_metrics[0][1]

confirmation_rows = [
    runner.build_benchmark_row(
        experiment=experiment,
        metrics=dict(metrics, ops_per_sec=110.0),
        budget_sec=5,
        commit="abc125",
        machine="test-machine",
        previous=100.0,
        paired_baseline=dict(metrics, ops_per_sec=100.0),
        paired_baseline_ref="main",
        timestamp="2026-01-01T00:00:02Z",
    ),
    runner.build_benchmark_row(
        experiment=experiment,
        metrics=dict(metrics, ops_per_sec=99.0),
        budget_sec=5,
        commit="abc125",
        machine="test-machine",
        previous=100.0,
        paired_baseline=dict(metrics, ops_per_sec=100.0),
        paired_baseline_ref="main",
        timestamp="2026-01-01T00:00:03Z",
    ),
]
runner.apply_confirmation_policy(confirmation_rows)
assert [row["status"] for row in confirmation_rows] == ["discard", "discard"]
assert confirmation_rows[0]["raw_status"] == "keep"
assert confirmation_rows[1]["raw_status"] == "discard"
assert confirmation_rows[0]["confirmation_status"] == "discard"
assert confirmation_rows[1]["confirmation_status"] == "discard"
assert confirmation_rows[0]["confirmation_runs"] == 2
assert confirmation_rows[0]["confirmation_index"] == 1
assert confirmation_rows[1]["confirmation_index"] == 2

with tempfile.TemporaryDirectory() as tmp:
    original_results = runner.RESULTS
    runner.RESULTS = Path(tmp) / "results.tsv"
    runner.RESULTS.write_text(
        "timestamp\tcommit\texperiment\tbackend\toperation\titerations\tops_per_sec\tcorrectness\tstatus\tdescription\n"
        "2026-01-01T00:00:00Z\told4\tjacobian_kangaroo_multi_small\tmacos_cpu\tjacobian_kangaroo_multi_small\t1\t13000.000000\ttrue\tkeep\tfour targets\n"
        "2026-01-01T00:00:01Z\told16\tjacobian_kangaroo_multi16_small\tmacos_cpu\tjacobian_kangaroo_multi_small\t1\t5000.000000\ttrue\tkeep\tsixteen targets\n",
        encoding="utf-8",
    )
    assert runner.best_previous("jacobian_kangaroo_multi16_small", "macos_cpu", "jacobian_kangaroo_multi_small") == 5000.0
    assert runner.best_previous("jacobian_kangaroo_multi_small", "macos_cpu", "jacobian_kangaroo_multi_small") == 13000.0
    runner.RESULTS = original_results
