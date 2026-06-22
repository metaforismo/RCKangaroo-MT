#!/usr/bin/env python3
"""Fixed-gate benchmark runner for RCKangaroo-MT autoresearch."""

from __future__ import annotations

import argparse
import json
import platform
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "autoresearch" / "results.tsv"
BENCHMARKS = ROOT / "autoresearch" / "benchmarks.jsonl"


def run_command(args: list[str], timeout: int, cwd: Path = ROOT) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=cwd,
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


def aggregate_metric_samples(samples: list[dict]) -> dict:
    if not samples:
        raise ValueError("at least one benchmark sample is required")

    ops_values = [float(sample.get("ops_per_sec", 0.0)) for sample in samples]
    sorted_samples = sorted(samples, key=lambda sample: float(sample.get("ops_per_sec", 0.0)))
    median_sample = dict(sorted_samples[len(sorted_samples) // 2])
    median_ops = float(statistics.median(ops_values))

    median_sample.update(
        {
            "ops_per_sec": median_ops,
            "ops_per_sec_min": min(ops_values),
            "ops_per_sec_max": max(ops_values),
            "runner_sample_count": len(samples),
            "correctness": all(bool(sample.get("correctness")) for sample in samples),
            "skipped": all(bool(sample.get("skipped")) for sample in samples),
        }
    )
    if not median_sample["correctness"] and not median_sample["skipped"]:
        reasons = sorted({str(sample.get("reason", "")) for sample in samples if sample.get("reason")})
        if reasons:
            median_sample["reason"] = "; ".join(reasons)
    return median_sample


def git_commit(cwd: Path = ROOT) -> str:
    proc = run_command(["git", "rev-parse", "--short", "HEAD"], timeout=10, cwd=cwd)
    if proc.returncode != 0:
        return "unknown"
    commit = proc.stdout.strip()
    if not commit:
        return "unknown"

    status = run_command(["git", "status", "--porcelain"], timeout=10, cwd=cwd)
    if status.returncode != 0 or status.stdout.strip():
        return f"{commit}-dirty"
    return commit


def best_previous(experiment_name: str, backend: str, operation: str) -> float | None:
    if not RESULTS.exists():
        return None
    best: float | None = None
    for line in RESULTS.read_text(encoding="utf-8").splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) < 9:
            continue
        _, _, prev_experiment, prev_backend, prev_operation, _, ops, correctness, status = parts[:9]
        if prev_experiment != experiment_name:
            continue
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


def confirmation_status(rows: list[dict]) -> str:
    if not rows:
        raise ValueError("at least one confirmation row is required")
    statuses = [str(row.get("status", "")) for row in rows]
    if any(status == "crash" for status in statuses):
        return "crash"
    if all(status == "skip" for status in statuses):
        return "skip"
    if all(status == "keep" for status in statuses):
        return "keep"
    return "discard"


def apply_confirmation_policy(rows: list[dict]) -> None:
    status = confirmation_status(rows)
    run_count = len(rows)
    for index, row in enumerate(rows, start=1):
        raw_status = str(row.get("status", ""))
        row["raw_status"] = raw_status
        row["confirmation_status"] = status
        row["confirmation_runs"] = run_count
        row["confirmation_index"] = index
        if status != "keep" and raw_status == "keep":
            row["status"] = "discard"


def build_benchmark_row(
    *,
    experiment: dict,
    metrics: dict,
    budget_sec: int,
    commit: str,
    machine: str,
    previous: float | None,
    paired_baseline: dict | None,
    paired_baseline_ref: str,
    timestamp: str,
) -> dict:
    skipped = bool(metrics.get("skipped"))
    correctness = bool(metrics.get("correctness"))
    backend = str(metrics.get("backend", "unknown"))
    operation = str(metrics.get("operation", "unknown"))
    ops_per_sec = float(metrics.get("ops_per_sec", 0.0))
    min_ratio = float(experiment.get("min_improvement_ratio", 0.0))
    paired_ops: float | None = None
    paired_usable = False
    if paired_baseline is not None:
        paired_ops = float(paired_baseline.get("ops_per_sec", 0.0))
        paired_usable = (
            bool(paired_baseline.get("correctness"))
            and not bool(paired_baseline.get("skipped"))
            and paired_ops > 0.0
        )

    if skipped:
        status = "skip"
    elif not correctness:
        status = "crash"
    elif paired_usable:
        status = "keep" if ops_per_sec > paired_ops * (1.0 + min_ratio) else "discard"
    elif previous is None:
        status = "keep"
    elif ops_per_sec > previous * (1.0 + min_ratio):
        status = "keep"
    else:
        status = "discard"

    row = dict(metrics)
    row.update(
        {
            "timestamp": timestamp,
            "commit": commit,
            "experiment": experiment["name"],
            "description": experiment.get("description", ""),
            "budget_sec": budget_sec,
            "backend": backend,
            "operation": operation,
            "iterations": int(metrics.get("iterations", 0)),
            "sample_count": int(metrics.get("sample_count", 0)),
            "min_ms": int(metrics.get("min_ms", 0)),
            "seconds": float(metrics.get("seconds", 0.0)),
            "ops_per_sec": ops_per_sec,
            "correctness": correctness,
            "skipped": skipped,
            "reason": str(metrics.get("reason", "")),
            "status": status,
            "machine": machine,
        }
    )
    if paired_baseline is not None:
        row.update(
            {
                "paired_baseline_ref": paired_baseline_ref,
                "paired_baseline_ops_per_sec": paired_ops or 0.0,
                "paired_speedup": (ops_per_sec / paired_ops) if paired_ops else 0.0,
            }
        )
    return row


def experiment_bench_command(experiment: dict) -> list[str]:
    if "bench_command" not in experiment:
        return ["make", str(experiment.get("bench_target", "macos-bench"))]

    command = experiment["bench_command"]
    if not isinstance(command, list) or not command:
        raise ValueError("bench_command must be a non-empty list of strings")
    if not all(isinstance(part, str) and part for part in command):
        raise ValueError("bench_command must contain only non-empty strings")
    return command


def build_experiment(experiment: dict, timeout: int, cwd: Path) -> None:
    build_target = experiment.get("build_target", "")
    if build_target:
        build = run_command(["make", str(build_target)], timeout=timeout, cwd=cwd)
        print(build.stdout, end="")
        if build.returncode != 0:
            raise RuntimeError(f"build target failed with status {build.returncode}")


def run_experiment_sample(experiment: dict, timeout: int, cwd: Path, *, build: bool = True) -> dict:
    if build:
        build_experiment(experiment, timeout, cwd)

    bench = run_command(experiment_bench_command(experiment), timeout=timeout, cwd=cwd)
    print(bench.stdout, end="")
    if bench.returncode != 0:
        raise RuntimeError(f"benchmark command failed with status {bench.returncode}")

    return parse_last_json(bench.stdout)


def run_experiment_samples(experiment: dict, timeout: int, cwd: Path) -> dict:
    sample_runs = max(1, int(experiment.get("sample_runs", 1)))
    metric_samples: list[dict] = []
    build_experiment(experiment, timeout, cwd)
    for sample_index in range(sample_runs):
        if sample_runs > 1:
            print(f"sample {sample_index + 1}/{sample_runs}:")
        metric_samples.append(run_experiment_sample(experiment, timeout, cwd, build=False))

    return aggregate_metric_samples(metric_samples)


def run_paired_experiment_samples(experiment: dict, timeout: int, baseline_cwd: Path, candidate_cwd: Path, *, build: bool = True) -> tuple[dict, dict]:
    sample_runs = max(1, int(experiment.get("sample_runs", 1)))
    baseline_samples: list[dict] = []
    candidate_samples: list[dict] = []
    if build:
        build_experiment(experiment, timeout, baseline_cwd)
        build_experiment(experiment, timeout, candidate_cwd)
    for sample_index in range(sample_runs):
        if sample_runs > 1:
            print(f"paired sample {sample_index + 1}/{sample_runs} baseline:")
        baseline_samples.append(run_experiment_sample(experiment, timeout, baseline_cwd, build=False))
        if sample_runs > 1:
            print(f"paired sample {sample_index + 1}/{sample_runs} candidate:")
        candidate_samples.append(run_experiment_sample(experiment, timeout, candidate_cwd, build=False))

    return aggregate_metric_samples(baseline_samples), aggregate_metric_samples(candidate_samples)


def run_paired_baseline_and_candidate(experiment: dict, timeout: int, ref: str, candidate_cwd: Path) -> tuple[dict, dict]:
    return run_paired_baseline_and_candidate_confirmations(experiment, timeout, ref, candidate_cwd, 1)[0]


def run_paired_baseline_and_candidate_confirmations(experiment: dict, timeout: int, ref: str, candidate_cwd: Path, confirm_runs: int) -> list[tuple[dict, dict]]:
    with tempfile.TemporaryDirectory(prefix="rck-paired-baseline-") as tmp:
        worktree_path = Path(tmp) / "baseline"
        add = run_command(["git", "worktree", "add", "--detach", str(worktree_path), ref], timeout=timeout)
        if add.returncode != 0:
            raise RuntimeError(add.stdout)
        try:
            check = run_command(["make", "macos-check"], timeout=timeout, cwd=worktree_path)
            if check.returncode != 0:
                raise RuntimeError(check.stdout)
            print(f"paired baseline ref {ref} ({git_commit(worktree_path)}):")
            build_experiment(experiment, timeout, worktree_path)
            build_experiment(experiment, timeout, candidate_cwd)
            confirmation_metrics: list[tuple[dict, dict]] = []
            for confirmation_index in range(max(1, confirm_runs)):
                if confirm_runs > 1:
                    print(f"confirmation run {confirmation_index + 1}/{confirm_runs}:")
                confirmation_metrics.append(run_paired_experiment_samples(experiment, timeout, worktree_path, candidate_cwd, build=False))
            return confirmation_metrics
        finally:
            remove = run_command(["git", "worktree", "remove", "--force", str(worktree_path)], timeout=timeout)
            if remove.returncode != 0:
                print(remove.stdout, file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a fixed-gate RCKangaroo-MT experiment.")
    parser.add_argument("--experiment", required=True, help="Experiment name under autoresearch/experiments.")
    parser.add_argument("--budget-sec", type=int, default=60, help="Experiment budget metadata and timeout hint.")
    parser.add_argument("--paired-baseline-ref", default="", help="Optional git ref to benchmark in a temporary paired baseline worktree.")
    parser.add_argument("--confirm-runs", type=int, default=1, help="Repeat the full benchmark decision this many times before appending results; keep survives only when every confirmation keeps.")
    args = parser.parse_args()

    experiment = load_experiment(args.experiment)
    timeout = max(60, args.budget_sec * 12)
    confirm_runs = max(1, args.confirm_runs)

    check = run_command(["make", "macos-check"], timeout=timeout)
    if check.returncode != 0:
        print(check.stdout)
        return check.returncode

    rows: list[dict] = []
    try:
        if args.paired_baseline_ref:
            paired_runs = run_paired_baseline_and_candidate_confirmations(experiment, timeout, args.paired_baseline_ref, ROOT, confirm_runs)
            for paired_baseline, metrics in paired_runs:
                backend = str(metrics.get("backend", "unknown"))
                operation = str(metrics.get("operation", "unknown"))
                previous = best_previous(experiment["name"], backend, operation)
                now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                rows.append(
                    build_benchmark_row(
                        experiment=experiment,
                        metrics=metrics,
                        budget_sec=args.budget_sec,
                        commit=git_commit(),
                        machine=platform.platform(),
                        previous=previous,
                        paired_baseline=paired_baseline,
                        paired_baseline_ref=args.paired_baseline_ref,
                        timestamp=now,
                    )
                )
        else:
            for confirmation_index in range(confirm_runs):
                if confirm_runs > 1:
                    print(f"confirmation run {confirmation_index + 1}/{confirm_runs}:")
                metrics = run_experiment_samples(experiment, timeout, ROOT)
                backend = str(metrics.get("backend", "unknown"))
                operation = str(metrics.get("operation", "unknown"))
                previous = best_previous(experiment["name"], backend, operation)
                now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
                rows.append(
                    build_benchmark_row(
                        experiment=experiment,
                        metrics=metrics,
                        budget_sec=args.budget_sec,
                        commit=git_commit(),
                        machine=platform.platform(),
                        previous=previous,
                        paired_baseline=None,
                        paired_baseline_ref=args.paired_baseline_ref,
                        timestamp=now,
                    )
                )
    except Exception as exc:
        print(f"failed to parse benchmark JSON: {exc}", file=sys.stderr)
        return 1

    if confirm_runs > 1:
        apply_confirmation_policy(rows)

    for row in rows:
        append_results(row)
        append_benchmark(row)

    row = rows[-1]
    paired = ""
    if args.paired_baseline_ref:
        paired = f" paired_baseline_ops_per_sec: {row['paired_baseline_ops_per_sec']:.6f} paired_speedup: {row['paired_speedup']:.6f}"
    confirmation = ""
    if confirm_runs > 1:
        confirmation = f" confirmation_status: {row['confirmation_status']} confirmation_runs: {row['confirmation_runs']}"
    print(f"status: {row['status']} ops_per_sec: {row['ops_per_sec']:.6f}{paired}{confirmation}")
    return 0 if all(row["correctness"] or row["skipped"] for row in rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
