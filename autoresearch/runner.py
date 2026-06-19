#!/usr/bin/env python3
"""Fixed-gate benchmark runner for RCKangaroo-MT autoresearch."""

from __future__ import annotations

import argparse
import json
import platform
import subprocess
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "autoresearch" / "results.tsv"
BENCHMARKS = ROOT / "autoresearch" / "benchmarks.jsonl"


def run_command(args: list[str], timeout: int) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
        check=False,
    )


def load_experiment(name: str) -> dict:
    path = ROOT / "autoresearch" / "experiments" / f"{name}.json"
    if not path.exists():
        raise SystemExit(f"experiment not found: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def parse_last_json(stdout: str) -> dict:
    for line in reversed(stdout.splitlines()):
        line = line.strip()
        if line.startswith("{") and line.endswith("}"):
            return json.loads(line)
    raise ValueError("benchmark output did not contain a JSON line")


def git_commit() -> str:
    proc = run_command(["git", "rev-parse", "--short", "HEAD"], timeout=10)
    if proc.returncode != 0:
        return "unknown"
    return proc.stdout.strip()


def best_previous(backend: str, operation: str) -> float | None:
    if not RESULTS.exists():
        return None
    best: float | None = None
    for line in RESULTS.read_text(encoding="utf-8").splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) < 9:
            continue
        _, _, _, prev_backend, prev_operation, _, ops, correctness, status = parts[:9]
        if prev_backend != backend or prev_operation != operation:
            continue
        if correctness != "true" or status != "keep":
            continue
        value = float(ops)
        if best is None or value > best:
            best = value
    return best


def append_results(row: dict) -> None:
    if not RESULTS.exists():
        RESULTS.write_text(
            "timestamp\tcommit\texperiment\tbackend\toperation\titerations\tops_per_sec\tcorrectness\tstatus\tdescription\n",
            encoding="utf-8",
        )
    with RESULTS.open("a", encoding="utf-8") as fp:
        fp.write(
            f"{row['timestamp']}\t{row['commit']}\t{row['experiment']}\t{row['backend']}\t"
            f"{row['operation']}\t{row['iterations']}\t{row['ops_per_sec']:.6f}\t"
            f"{str(row['correctness']).lower()}\t{row['status']}\t{row['description']}\n"
        )


def append_benchmark(row: dict) -> None:
    with BENCHMARKS.open("a", encoding="utf-8") as fp:
        fp.write(json.dumps(row, sort_keys=True) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a fixed-gate RCKangaroo-MT experiment.")
    parser.add_argument("--experiment", required=True, help="Experiment name under autoresearch/experiments.")
    parser.add_argument("--budget-sec", type=int, default=60, help="Experiment budget metadata and timeout hint.")
    args = parser.parse_args()

    experiment = load_experiment(args.experiment)
    timeout = max(60, args.budget_sec * 12)

    check = run_command(["make", "macos-check"], timeout=timeout)
    if check.returncode != 0:
        print(check.stdout)
        return check.returncode

    bench_target = experiment.get("bench_target", "macos-bench")
    bench = run_command(["make", bench_target], timeout=timeout)
    print(bench.stdout, end="")
    if bench.returncode != 0:
        return bench.returncode

    try:
        metrics = parse_last_json(bench.stdout)
    except Exception as exc:
        print(f"failed to parse benchmark JSON: {exc}", file=sys.stderr)
        return 1

    correctness = bool(metrics.get("correctness"))
    backend = str(metrics.get("backend", "unknown"))
    operation = str(metrics.get("operation", "unknown"))
    ops_per_sec = float(metrics.get("ops_per_sec", 0.0))
    previous = best_previous(backend, operation)
    min_ratio = float(experiment.get("min_improvement_ratio", 0.0))

    if not correctness:
        status = "crash"
    elif previous is None:
        status = "keep"
    elif ops_per_sec > previous * (1.0 + min_ratio):
        status = "keep"
    else:
        status = "discard"

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    row = {
        "timestamp": now,
        "commit": git_commit(),
        "experiment": experiment["name"],
        "description": experiment.get("description", ""),
        "budget_sec": args.budget_sec,
        "backend": backend,
        "operation": operation,
        "iterations": int(metrics.get("iterations", 0)),
        "seconds": float(metrics.get("seconds", 0.0)),
        "ops_per_sec": ops_per_sec,
        "correctness": correctness,
        "status": status,
        "machine": platform.platform(),
    }

    append_results(row)
    append_benchmark(row)
    print(f"status: {status} ops_per_sec: {ops_per_sec:.6f}")
    return 0 if correctness else 1


if __name__ == "__main__":
    raise SystemExit(main())
