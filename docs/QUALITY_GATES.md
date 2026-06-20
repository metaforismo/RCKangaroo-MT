# Quality Gates

This project optimizes CUDA, CPU, and Metal kangaroo components only when correctness and reproducibility stay intact. Every optimization is a candidate until it passes the gates below.

## Required Checklist

- target: state the exact target path, command, benchmark, and platform being changed.
- allowed edits: keep edits scoped to the target; do not mix unrelated refactors, docs, or generated logs into performance changes.
- correctness oracle: name the oracle before editing. Examples: `make macos-check`, CPU scalar oracle, EcInt reference, Metal CPU oracle, known target/private-key fixtures.
- performance metric: name the metric before editing. Examples: `ops_per_sec`, `paired_speedup`, `correctness`, `avg_dp_count`, `last_dp_count`.
- baseline gate: compare against `main` with a paired baseline when performance is the reason for the change. A candidate below the gate is discarded.
- hidden tests: assume unlisted tests will cover CLI shape, JSON markers, target parsing, skip behavior, and edge cases. Preserve public output contracts.
- reproducibility: record command, branch, commit, hardware/runtime, arguments, and whether Metal/CUDA access was sandboxed or native.
- logging: append official `autoresearch` logs only for accepted results. Remove discarded candidate rows from append-only result files before leaving the branch.
- submission: commit only after source checks, CLI checks, and relevant benchmark gates pass. Merge fast-forward to `main`, rerun the required suite on `main`, then push.
- rollback: if correctness fails, performance regresses, output contracts change unexpectedly, or the evidence is noisy, do not merge. Leave the failed worktree isolated or delete it after explicit cleanup.

## Mac Metal Rules

- The MacBook Air M3 has an Apple GPU exposed through Metal, not CUDA.
- A sandbox can hide the Metal device. Treat `no Metal device available` as a runtime skip, then rerun GPU benchmarks with native Metal access before making GPU claims.
- Metal kernel changes must keep CPU oracle checks and skip behavior intact.
- GPU throughput alone is not enough: correctness, output schema, reproducible commands, and stable logs are part of the result.

## Accepted Evidence

- `make macos-check`
- Targeted source checks for the edited subsystem
- Targeted CLI checks for changed commands or JSON markers
- `python3 autoresearch/runner.py --experiment <name> --budget-sec 5 --paired-baseline-ref main` for performance candidates
- Native Metal benchmark output when the target is a Metal kernel
