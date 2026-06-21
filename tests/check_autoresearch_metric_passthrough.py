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


original_run_command = runner.run_command
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
