#!/usr/bin/env python3
"""Fixed-gate benchmark runner for RCKangaroo-MT autoresearch."""

from __future__ import annotations

import argparse
import json
import os
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


def host_load_snapshot(phase: str = "start") -> dict:
    if phase not in {"start", "end"}:
        raise ValueError(f"unsupported host-load phase: {phase}")
    logical_cpus = max(1, int(os.cpu_count() or 1))
    try:
        load_1m = float(os.getloadavg()[0])
    except (AttributeError, OSError):
        load_1m = 0.0
    return {
        f"host_load_1m_{phase}": load_1m,
        "host_logical_cpu_count": logical_cpus,
        f"host_load_per_cpu_{phase}": load_1m / logical_cpus,
    }


def host_load_failure(experiment: dict, snapshot: dict, phase: str = "start") -> str:
    max_load_per_cpu = float(experiment.get("max_host_load_per_cpu", 0.0) or 0.0)
    actual = float(snapshot.get(f"host_load_per_cpu_{phase}", 0.0) or 0.0)
    if max_load_per_cpu > 0.0 and actual > max_load_per_cpu:
        return f"host load per CPU at {phase} {actual:.3f} exceeds max {max_load_per_cpu:.3f}"
    return ""


def apply_host_load_end_policy(rows: list[dict], experiment: dict, snapshot: dict) -> None:
    failure = host_load_failure(experiment, snapshot, phase="end")
    for row in rows:
        row.update(snapshot)
        if not failure or row.get("status") in {"crash", "skip"}:
            continue
        reason = str(row.get("reason", ""))
        row["reason"] = f"{reason}; {failure}" if reason else failure
        row["status"] = "discard"


def aggregate_metric_samples(samples: list[dict], metric_name: str = "ops_per_sec") -> dict:
    if not samples:
        raise ValueError("at least one benchmark sample is required")

    ops_values = [float(sample.get(metric_name, 0.0)) for sample in samples]
    min_ops = min(ops_values)
    max_ops = max(ops_values)
    sample_spread_ratio = (max_ops / min_ops) if min_ops > 0.0 else (1.0 if max_ops == 0.0 else 1.0e300)
    sorted_samples = sorted(samples, key=lambda sample: float(sample.get(metric_name, 0.0)))
    median_sample = dict(sorted_samples[len(sorted_samples) // 2])
    median_ops = float(statistics.median(ops_values))

    median_sample.update(
        {
            "sample_metric": metric_name,
            "sample_metric_values": ops_values,
            "sample_spread_ratio": sample_spread_ratio,
            metric_name: median_ops,
            f"{metric_name}_min": min_ops,
            f"{metric_name}_max": max_ops,
            "ops_per_sec": median_ops,
            "ops_per_sec_min": min_ops,
            "ops_per_sec_max": max_ops,
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


def git_tree_id(cwd: Path = ROOT, ref: str = "HEAD") -> str:
    proc = run_command(["git", "rev-parse", f"{ref}^{{tree}}"], timeout=10, cwd=cwd)
    if proc.returncode != 0:
        return ""
    return proc.stdout.strip()


def git_worktree_dirty(cwd: Path = ROOT) -> bool:
    proc = run_command(["git", "status", "--porcelain"], timeout=10, cwd=cwd)
    return proc.returncode != 0 or bool(proc.stdout.strip())


def same_clean_tree(baseline_cwd: Path, candidate_cwd: Path) -> bool:
    if git_worktree_dirty(candidate_cwd):
        return False
    baseline_tree = git_tree_id(baseline_cwd)
    candidate_tree = git_tree_id(candidate_cwd)
    return bool(baseline_tree and candidate_tree and baseline_tree == candidate_tree)


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


def required_metric_failures(experiment: dict, metrics: dict) -> list[str]:
    required = experiment.get("required_metrics", {})
    if not isinstance(required, dict):
        raise ValueError("required_metrics must be an object")

    failures: list[str] = []
    for key, expected in required.items():
        actual = metrics.get(key)
        if isinstance(expected, dict):
            actual_value = float(actual) if actual is not None else None
            min_value = expected.get("min")
            max_value = expected.get("max")
            if min_value is not None and (actual_value is None or actual_value < float(min_value)):
                failures.append(f"required metric {key} expected >= {min_value} got {actual}")
            if max_value is not None and (actual_value is None or actual_value > float(max_value)):
                failures.append(f"required metric {key} expected <= {max_value} got {actual}")
        elif actual != expected:
            failures.append(f"required metric {key} expected {expected} got {actual}")
    return failures


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
    benchmark_correctness = bool(metrics.get("correctness"))
    required_failures = required_metric_failures(experiment, metrics)
    correctness = benchmark_correctness and not required_failures
    backend = str(metrics.get("backend", "unknown"))
    operation = str(metrics.get("operation", "unknown"))
    ops_per_sec = float(metrics.get("ops_per_sec", 0.0))
    min_ratio = float(experiment.get("min_improvement_ratio", 0.0))
    max_spread_ratio = float(experiment.get("max_sample_spread_ratio", 0.0) or 0.0)
    sample_spread_ratio = float(metrics.get("sample_spread_ratio", 1.0) or 1.0)
    spread_too_high = max_spread_ratio > 0.0 and sample_spread_ratio > max_spread_ratio
    same_tree_paired_baseline = bool(metrics.get("same_tree_paired_baseline"))
    paired_ops: float | None = None
    paired_usable = False
    paired_baseline_spread_too_high = False
    paired_baseline_spread_ratio = 1.0
    paired_baseline_required_failures: list[str] = []
    if paired_baseline is not None:
        paired_ops = float(paired_baseline.get("ops_per_sec", 0.0))
        paired_baseline_spread_ratio = float(paired_baseline.get("sample_spread_ratio", 1.0) or 1.0)
        paired_baseline_spread_too_high = max_spread_ratio > 0.0 and paired_baseline_spread_ratio > max_spread_ratio
        paired_baseline_required_failures = required_metric_failures(experiment, paired_baseline)
        paired_usable = (
            bool(paired_baseline.get("correctness"))
            and not bool(paired_baseline.get("skipped"))
            and paired_ops > 0.0
            and not paired_baseline_required_failures
        )

    if skipped:
        status = "skip"
    elif not correctness:
        status = "crash"
    elif spread_too_high:
        status = "discard"
    elif paired_baseline is not None and paired_baseline_required_failures:
        status = "discard"
    elif paired_usable and paired_baseline_spread_too_high:
        status = "discard"
    elif paired_usable and same_tree_paired_baseline:
        status = "discard"
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
            "cooldown_sec": cooldown_seconds(experiment),
            "correctness": correctness,
            "skipped": skipped,
            "reason": str(metrics.get("reason", "")),
            "status": status,
            "machine": machine,
        }
    )
    if max_spread_ratio > 0.0:
        row["max_sample_spread_ratio"] = max_spread_ratio
    if spread_too_high:
        reason = str(row.get("reason", ""))
        spread_reason = f"sample spread ratio {sample_spread_ratio:.6f} exceeds max {max_spread_ratio:.6f}"
        row["reason"] = f"{reason}; {spread_reason}" if reason else spread_reason
    if paired_baseline is not None and paired_baseline_spread_too_high:
        reason = str(row.get("reason", ""))
        spread_reason = f"paired baseline sample spread ratio {paired_baseline_spread_ratio:.6f} exceeds max {max_spread_ratio:.6f}"
        row["reason"] = f"{reason}; {spread_reason}" if reason else spread_reason
        row["paired_baseline_sample_spread_ratio"] = paired_baseline_spread_ratio
    if paired_baseline is not None and paired_baseline_required_failures:
        reason = str(row.get("reason", ""))
        required_reason = "paired baseline failed required metrics: " + "; ".join(paired_baseline_required_failures)
        row["reason"] = f"{reason}; {required_reason}" if reason else required_reason
        row["paired_baseline_required_metrics_passed"] = False
    if required_failures:
        reason = str(row.get("reason", ""))
        required_reason = "; ".join(required_failures)
        row["reason"] = f"{reason}; {required_reason}" if reason else required_reason
        row["benchmark_correctness"] = benchmark_correctness
        row["required_metrics_passed"] = False
    if paired_baseline is not None and same_tree_paired_baseline:
        reason = str(row.get("reason", ""))
        same_tree_reason = "paired baseline ref resolves to the same clean candidate tree and benchmark command; treating this row as a noise sentinel"
        row["reason"] = f"{reason}; {same_tree_reason}" if reason else same_tree_reason
        row["same_tree_paired_baseline"] = True
    if paired_baseline is not None:
        row.update(
            {
                "paired_baseline_ref": paired_baseline_ref,
                "paired_order": paired_order(experiment),
                "paired_baseline_ops_per_sec": paired_ops or 0.0,
                "paired_speedup": (ops_per_sec / paired_ops) if paired_ops else 0.0,
            }
        )
    return row


def experiment_bench_command(experiment: dict, key: str = "bench_command") -> list[str]:
    if key not in experiment:
        if key == "paired_baseline_command":
            return experiment_bench_command(experiment, "bench_command")
        if key == "bench_command":
            return ["make", str(experiment.get("bench_target", "macos-bench"))]
        raise ValueError(f"{key} must be present when requested")

    command = experiment[key]
    if not isinstance(command, list) or not command:
        raise ValueError(f"{key} must be a non-empty list of strings")
    if not all(isinstance(part, str) and part for part in command):
        raise ValueError(f"{key} must contain only non-empty strings")
    return command


def cooldown_seconds(experiment: dict) -> float:
    return max(0.0, float(experiment.get("cooldown_sec", 0.0) or 0.0))


def paired_order(experiment: dict) -> str:
    order = str(experiment.get("paired_order", "baseline_first"))
    if order not in {"baseline_first", "alternate"}:
        raise ValueError("paired_order must be baseline_first or alternate")
    return order


def cooldown_between_samples(experiment: dict, sample_index: int, sample_runs: int) -> None:
    cooldown = cooldown_seconds(experiment)
    if cooldown <= 0.0 or sample_index + 1 >= sample_runs:
        return
    print(f"cooldown {cooldown:g}s")
    time.sleep(cooldown)


def build_experiment(experiment: dict, timeout: int, cwd: Path) -> None:
    build_target = experiment.get("build_target", "")
    if build_target:
        build = run_command(["make", str(build_target)], timeout=timeout, cwd=cwd)
        print(build.stdout, end="")
        if build.returncode != 0:
            raise RuntimeError(f"build target failed with status {build.returncode}")


def run_experiment_sample(experiment: dict, timeout: int, cwd: Path, *, build: bool = True, command_key: str = "bench_command") -> dict:
    if build:
        build_experiment(experiment, timeout, cwd)

    bench = run_command(experiment_bench_command(experiment, command_key), timeout=timeout, cwd=cwd)
    print(bench.stdout, end="")
    if bench.returncode != 0:
        raise RuntimeError(f"benchmark command failed with status {bench.returncode}")

    return parse_last_json(bench.stdout)


def run_experiment_samples(experiment: dict, timeout: int, cwd: Path) -> dict:
    sample_runs = max(1, int(experiment.get("sample_runs", 1)))
    metric_name = str(experiment.get("metric", "ops_per_sec"))
    metric_samples: list[dict] = []
    build_experiment(experiment, timeout, cwd)
    for sample_index in range(sample_runs):
        if sample_runs > 1:
            print(f"sample {sample_index + 1}/{sample_runs}:")
        metric_samples.append(run_experiment_sample(experiment, timeout, cwd, build=False))
        cooldown_between_samples(experiment, sample_index, sample_runs)

    return aggregate_metric_samples(metric_samples, metric_name=metric_name)


def run_paired_experiment_samples(experiment: dict, timeout: int, baseline_cwd: Path, candidate_cwd: Path, *, build: bool = True) -> tuple[dict, dict]:
    sample_runs = max(1, int(experiment.get("sample_runs", 1)))
    metric_name = str(experiment.get("metric", "ops_per_sec"))
    order = paired_order(experiment)
    baseline_samples: list[dict] = []
    candidate_samples: list[dict] = []
    if build:
        build_experiment(experiment, timeout, baseline_cwd)
        build_experiment(experiment, timeout, candidate_cwd)
    for sample_index in range(sample_runs):
        def run_baseline_sample() -> None:
            if sample_runs > 1:
                print(f"paired sample {sample_index + 1}/{sample_runs} baseline:")
            baseline_samples.append(run_experiment_sample(experiment, timeout, baseline_cwd, build=False, command_key="paired_baseline_command"))

        def run_candidate_sample() -> None:
            if sample_runs > 1:
                print(f"paired sample {sample_index + 1}/{sample_runs} candidate:")
            candidate_samples.append(run_experiment_sample(experiment, timeout, candidate_cwd, build=False))

        if order == "alternate" and sample_index % 2 == 1:
            run_candidate_sample()
            run_baseline_sample()
        else:
            run_baseline_sample()
            run_candidate_sample()
        cooldown_between_samples(experiment, sample_index, sample_runs)

    return aggregate_metric_samples(baseline_samples, metric_name=metric_name), aggregate_metric_samples(candidate_samples, metric_name=metric_name)


def run_paired_baseline_and_candidate(experiment: dict, timeout: int, ref: str, candidate_cwd: Path) -> tuple[dict, dict]:
    return run_paired_baseline_and_candidate_confirmations(experiment, timeout, ref, candidate_cwd, 1)[0]


def run_paired_baseline_and_candidate_confirmations(experiment: dict, timeout: int, ref: str, candidate_cwd: Path, confirm_runs: int) -> list[tuple[dict, dict]]:
    with tempfile.TemporaryDirectory(prefix="rck-paired-baseline-") as tmp:
        worktree_path = Path(tmp) / "baseline"
        add = run_command(["git", "worktree", "add", "--detach", str(worktree_path), ref], timeout=timeout)
        if add.returncode != 0:
            raise RuntimeError(add.stdout)
        try:
            same_command_paired_baseline = experiment_bench_command(experiment, "paired_baseline_command") == experiment_bench_command(experiment)
            same_tree_paired_baseline = same_command_paired_baseline and same_clean_tree(worktree_path, candidate_cwd)
            if same_tree_paired_baseline:
                print("paired baseline resolves to the same clean candidate tree and command; rows will be discarded as noise sentinels")
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
                baseline_metrics, candidate_metrics = run_paired_experiment_samples(experiment, timeout, worktree_path, candidate_cwd, build=False)
                if same_tree_paired_baseline:
                    candidate_metrics["same_tree_paired_baseline"] = True
                confirmation_metrics.append((baseline_metrics, candidate_metrics))
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
    initial_load = host_load_snapshot()
    load_failure = host_load_failure(experiment, initial_load)
    if load_failure:
        print(f"host load gate: {load_failure}; no benchmark row written", file=sys.stderr)
        return 2

    check = run_command(["make", "macos-check"], timeout=timeout)
    if check.returncode != 0:
        print(check.stdout)
        return check.returncode

    start_load = host_load_snapshot()
    load_failure = host_load_failure(experiment, start_load)
    if load_failure:
        print(f"host load gate after correctness check: {load_failure}; no benchmark row written", file=sys.stderr)
        return 2

    rows: list[dict] = []
    try:
        if args.paired_baseline_ref:
            paired_runs = run_paired_baseline_and_candidate_confirmations(experiment, timeout, args.paired_baseline_ref, ROOT, confirm_runs)
            for paired_baseline, metrics in paired_runs:
                metrics.update(start_load)
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
                metrics.update(start_load)
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

    end_load = host_load_snapshot(phase="end")
    apply_host_load_end_policy(rows, experiment, end_load)

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
