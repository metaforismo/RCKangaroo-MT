#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
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
    timestamp="2026-01-01T00:00:00Z",
)

assert row["status"] == "keep"
assert row["single_target_ops_per_sec"] == 20.0
assert row["speedup_vs_single"] == 4.0
assert row["target_throughput_vs_single"] == 16.0
assert row["commit"] == "abc123"
assert row["machine"] == "test-machine"

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
