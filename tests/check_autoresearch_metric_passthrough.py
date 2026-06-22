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

paired_row = runner.build_benchmark_row(
    experiment=experiment,
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
assert paired_row["paired_baseline_ops_per_sec"] == 80.0
assert paired_row["paired_speedup"] == 1.05

samples = [
    dict(metrics, iterations=5, seconds=0.10, ops_per_sec=50.0),
    dict(metrics, iterations=10, seconds=0.10, ops_per_sec=100.0),
    dict(metrics, iterations=15, seconds=0.10, ops_per_sec=150.0),
]
aggregated = runner.aggregate_metric_samples(samples)
assert aggregated["ops_per_sec"] == 100.0
assert aggregated["ops_per_sec_min"] == 50.0
assert aggregated["ops_per_sec_max"] == 150.0
assert aggregated["runner_sample_count"] == 3
assert aggregated["iterations"] == 10
assert aggregated["correctness"] is True

jump_walk_experiment = runner.load_experiment("jacobian_jump_walk")
assert int(jump_walk_experiment.get("sample_runs", 1)) >= 3

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
