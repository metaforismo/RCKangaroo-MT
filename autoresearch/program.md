# RCKangaroo-MT Autoresearch Program

This is a fixed-gate research loop for improving RCKangaroo-MT on macOS and Apple Silicon.

## Purpose

Autoresearch exists to discover real optimizations. It is not a demo loop. An experiment is useful only if it passes correctness gates and improves a measured metric.

## Ground Rules

- Do not modify correctness tests to make an experiment pass.
- Do not change benchmark parsing during a run.
- Do not keep a result with `"correctness": false`.
- Do not compare Apple Silicon CPU/Metal results to NVIDIA CUDA as if they were the same hardware class.
- Keep early mutations narrow: config files, isolated experiment modules, or clearly named backend experiments.
- Prefer simple changes when scores are close.

## Fixed Commands

Run a baseline or candidate through:

```sh
python3 autoresearch/runner.py --experiment baseline --budget-sec 5
```

The runner always executes:

```sh
make macos-check
make macos-bench
```

## Current Metric

The current baseline metric is `ops_per_sec` for CPU `multiply_g`.

Future experiments may add:

- field multiplication/sec;
- point addition/sec;
- Metal smoke and arithmetic kernel throughput, including field add, multiply, and square;
- tiny-range solve/sec;
- distinguished points/sec.

Each added metric must have a correctness gate before it can become a keep/discard target.

## Keep/Discard Rule

The runner compares an experiment against previous kept rows for the same backend and operation. A result is kept only when:

1. correctness is true;
2. ops/sec improves by the configured margin;
3. the run exits cleanly.

The first valid baseline is kept.

For noisy local performance work, run with a paired ref:

```sh
python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi_small --budget-sec 5 --paired-baseline-ref main
```

When the paired baseline is correct, keep/discard compares against that fresh same-run baseline and records `paired_baseline_ops_per_sec` plus `paired_speedup` in `benchmarks.jsonl`.

## Results

- `autoresearch/results.tsv`: human-readable experiment ledger.
- `autoresearch/benchmarks.jsonl`: append-only machine-readable benchmark data.

Review both files after each run. A breakthrough is a row that remains correct and reproducibly improves the metric.
