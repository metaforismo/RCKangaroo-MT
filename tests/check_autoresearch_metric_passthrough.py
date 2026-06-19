#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
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
