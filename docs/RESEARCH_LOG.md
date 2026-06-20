# RCKangaroo-MT Research Log

This file is the compact running record for optimization work. Keep it factual:
what changed, what was measured, what was rejected, and which correctness gate
was used. Do not treat an experiment as an improvement unless the oracle passes
and the metric beats the configured baseline gate.

## Current Ground Rules

- Correctness comes before throughput. Every solver or kernel benchmark must
  report `correctness:true` or a clean `skipped:true` when hardware is not
  visible.
- The default local gate is `make macos-check`.
- CPU kangaroo performance candidates use:
  `python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi16_small --budget-sec 5 --paired-baseline-ref main`.
- Metal candidates must be tested on a real Apple Silicon Metal runtime, not
  only inside the restricted sandbox, because sandboxed runs may report
  `no Metal device available`.
- Merge only `keep` results. Remove or leave isolated any experiment that is
  incorrect, slower than the gate, or only noisy.
- Once a candidate passes all required gates, fast-forward it into `main` and
  push it. The next experiment must branch from that updated `main`, making the
  proven result the new baseline.
- Keep rejected work isolated until its lesson is recorded here or in
  `autoresearch/benchmarks.jsonl`.

## Hardware Reference

The local target machine is a MacBook Air M3 with 16 GB RAM and a 10-core Apple
M3 GPU. Metal is available outside the sandbox. CUDA remains NVIDIA-only; macOS
GPU work should use Metal.

## Accepted Results

### Quality Gates

- Added `docs/QUALITY_GATES.md` and `docs/QUALITY_GATES.it.md`.
- Added `tests/check_quality_gates.sh`.
- Wired quality-gate checks into `make macos-check`.
- The gate now documents target, allowed edits, correctness oracle, performance
  metric, baseline comparison, hidden tests, reproducibility, logging,
  submission, and rollback.

### Metal Benchmark Stabilization

- Metal field benchmarks accept `--min-ms`.
- JSON reports `sample_count`, `min_ms`, total `iterations`, `ops_per_sec`,
  `correctness`, and `skipped`.
- This reduces short-dispatch timing noise and lets CI skip cleanly when Metal
  is not visible.

### Metal Dispatch Size Tuning

Commit: `bbde2c8` (`perf: tune Metal field dispatch size`)

- Changed Metal field dispatches from one execution-width group to a larger
  SIMD-aligned threadgroup, capped at 256 threads.
- Benchmarks now report:
  `threadgroup_limit`, `thread_execution_width`,
  `max_threads_per_threadgroup`, `threads_per_threadgroup`.
- On the local M3 run, Metal reported `thread_execution_width=32`,
  `max_threads_per_threadgroup=1024`, and `threads_per_threadgroup=256`.
- Paired autoresearch against `main`:
  - `metal_field_square`: `120,182,161.633272 ops/sec`, `1.054411x`,
    `status=keep`, `correctness=true`.
  - `metal_field_mul`: `110,169,933.604968 ops/sec`, `1.127512x`,
    `status=keep`, `correctness=true`.
  - A second `metal_field_mul` paired rerun under noisier conditions still kept
    the candidate: `107,181,958.674000 ops/sec`, `1.045700x`,
    `status=keep`, `correctness=true`.

### Fused Square-Mul Field Kernel

Commit: `bbde2c8` (`perf: tune Metal field dispatch size`)

- Added `field_square_mul_mod_p`, computing `(a * a) * b mod p` in one Metal
  dispatch.
- Added CLI commands:
  - `metal-field-square-mul-test`
  - `metal-field-square-mul-bench --iterations N [--min-ms N]`
- Added `autoresearch/experiments/metal_field_square_mul.json`.
- Autoresearch first record:
  - `116,411,049.047869 ops/sec`
  - `status=keep`
  - `correctness=true`
  - `skipped=false`
- Early pre-tuning measurements showed that fusing alone was not automatically
  faster. The useful result is the combination of a real fused oracle plus the
  larger threadgroup dispatch shape.

### Metal Jacobian-Plus-Affine Add Kernel

Commit: `07615a1` (`feat: add Metal Jacobian affine add kernel`)

- Added the first point-level Apple Silicon GPU primitive,
  `jacobian_add_affine`.
- The kernel consumes packed Jacobian `x/y/z` plus an input infinity flag and
  affine `x/y`, then emits packed Jacobian `x/y/z` plus an output infinity flag.
- The self-test and benchmark cover generic additions, `p` infinity, doubling
  (`h=0,r=0`), and point-at-infinity (`h=0,r!=0`) branches.
- Added CLI commands:
  - `metal-jacobian-add-test`
  - `metal-jacobian-add-bench --iterations N [--min-ms N] [--tg-limit N]`
- Added `autoresearch/experiments/metal_jacobian_add.json` with three runner
  samples.
- Local M3 autoresearch result:
  - median `18,987,732.357266 ops/sec`
  - min `16,122,729.006089 ops/sec`
  - max `23,145,877.471189 ops/sec`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

## Rejected Or Non-Merged Experiments

These did not pass the performance gate or had a correctness/architecture issue:

- `macos-affine-prefix-split-tame`: speedup `0.995234`; discarded.
- `macos-dp-combined-record`: speedup `0.987156`; discarded.
- `macos-affine-jump-index-reuse`: incorrect behavior for the gate shape
  (`avg_dp_count` changed from `288` to `1172`); discarded.
- `macos-field-self-ops-v2`: speedup `0.993284`; discarded.
- `macos-native-cpu-flags-v3`: speedup `1.001949`, below gate; discarded.
- `macos-metal-square-generic`: correct but slower/unstable; not merged.
- `macos-metal-tg512`: correct and sometimes faster for
  `field_mul_mod_p`, but rejected because `field_square_mod_p` regressed badly
  in direct Metal runs. Keep the current 256-thread cap as the baseline until a
  broader Metal benchmark shows a consistent cross-kernel win.
- `--tg-limit N` is now available on Metal field benchmark commands for
  reproducible sweeps. The default remains 256 unless an experiment proves a
  better cross-kernel cap.
- A direct sweep with `--tg-limit` found `384` promising for some `mul` and
  `square` runs, but a repeat square comparison flipped back in favor of 256.
  Treat 384 as inconclusive, not as a new baseline.
- Metal field autoresearch experiments use three runner samples so keep/discard
  decisions are based on median throughput instead of a single noisy GPU run.

## Next Research Targets

- Move from isolated field kernels toward Jacobian point kernels on Metal.
- Keep CPU tiny-range kangaroo as the correctness oracle while GPU kernels are
  introduced one layer at a time.
- Prefer fused kernels only when paired benchmarks show a real win. The fused
  operation must still expose an oracle and a reproducible benchmark.
- Explore Metal memory layout for point batches before attempting full
  distinguished-point table work on GPU.
- Keep multi-target CPU architecture unchanged unless a candidate beats the
  paired autoresearch gate and preserves full collision verification.

## Cleanup Policy

- After a feature is merged to `main` and pushed, remove only its clean accepted
  worktree and delete only its merged local branch.
- Do not remove dirty or rejected worktrees until their useful findings have
  been recorded and any wanted diff has been intentionally saved.
- Keep README files focused on user-facing commands. Keep detailed experiment
  history here and raw metrics in `autoresearch/results.tsv` plus
  `autoresearch/benchmarks.jsonl`.
