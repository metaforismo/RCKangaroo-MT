# Autoresearch for RCKangaroo-MT

This folder contains a fixed-gate experiment runner for improving the macOS/Apple Silicon path.

Run the baseline:

```sh
python3 autoresearch/runner.py --experiment baseline --budget-sec 5
```

The runner executes correctness checks before benchmarks. Experiments may set `sample_runs`; when present, the runner executes the benchmark target repeatedly and records median `ops_per_sec` plus `ops_per_sec_min`, `ops_per_sec_max`, and `runner_sample_count` in `autoresearch/benchmarks.jsonl`.

Use a paired baseline when local CPU load is noisy and a candidate should be compared against a fresh build of another ref in the same run:

```sh
python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi_small --budget-sec 5 --paired-baseline-ref main
```

With `--paired-baseline-ref`, the runner creates a temporary detached worktree for that ref, runs the same correctness checks and benchmark target there, then runs the candidate benchmark. The JSON row records `paired_baseline_ref`, `paired_baseline_ops_per_sec`, and `paired_speedup`; keep/discard uses the paired baseline when it is correct and not skipped, otherwise it falls back to previous kept rows.

```sh
make macos-check
make macos-bench
```

`macos-check` builds with ThinLTO by default through `MACOS_LTO_FLAGS=-flto=thin`, so paired runs compare the same source with the candidate's current macOS build policy. Disable it for a diagnostic run with `make macos-check MACOS_LTO_FLAGS=`.

Run the CPU point-add walk experiment:

```sh
python3 autoresearch/runner.py --experiment point_add_g --budget-sec 5
```

This records `macos_cpu` `point_add_g` throughput. The benchmark starts from `2G`, repeatedly adds `G`, and checks the final point against `MultiplyG(n+2)` so it tracks a point-operation primitive closer to kangaroo walk cost.

Run the CPU Jacobian mixed-add walk experiment:

```sh
python3 autoresearch/runner.py --experiment jacobian_point_add_g --budget-sec 5
```

This records `macos_cpu` `jacobian_point_add_g` throughput and compares it against an affine point-add reference sample via `speedup_vs_affine`. It is the first macOS path that avoids one field inversion per walk step.

Run the CPU Jacobian jump-table walk experiment:

```sh
python3 autoresearch/runner.py --experiment jacobian_jump_walk --budget-sec 5
```

This records `macos_cpu` `jacobian_jump_walk` throughput. The benchmark precomputes affine jump points, keeps the walk state in Jacobian coordinates, selects jumps with a bit mask when `jump_count` is a power of two (`jump_index=power2_mask`, otherwise `modulo`), tracks scalar distance in parallel, and checks the final point against a scalar oracle. It is a deterministic walk-core benchmark, not a full DP/collision kangaroo solver yet.

Run the CPU Jacobian batch-to-affine conversion experiment:

```sh
python3 autoresearch/runner.py --experiment jacobian_batch_affine --budget-sec 5
```

This records `macos_cpu` `jacobian_batch_affine` batch conversions per second and affine points per second for a deterministic tame-plus-wild batch. It isolates the conversion primitive used by the shared-tame multi-target kangaroo loop, so future changes to inversion batching or affine buffer layout can be measured without DP lookup and walk-step noise.

Run the CPU single-target tiny kangaroo experiment:

```sh
python3 autoresearch/runner.py --experiment jacobian_kangaroo_small --budget-sec 5
```

This records `macos_cpu` `jacobian_kangaroo_small` solves per second. The benchmark generates one deterministic synthetic target, precomputes the deterministic jump table and range/tame-start context once per run, reuses scratch storage across measured solves, and reports `architecture=single_target`, `dp_lookup=hash`, `dp_bucket_storage=inline_first`, `point_passing=const_ref`, `affine_conversion=batch`, `jump_index`, `jump_table=precomputed`, `scratch=reused`, `range_context=precomputed`, tame/wild state counts, and DP table size.

Run the CPU shared-tame tiny multi-target kangaroo experiment:

```sh
python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi_small --budget-sec 5
```

This records `macos_cpu` `jacobian_kangaroo_multi_small` solves per second. The benchmark generates deterministic synthetic targets, places one solvable target at the final index, precomputes the deterministic jump table and range/tame-start context once per run, reuses scratch storage across measured solves, and reports `architecture=shared_tame`, `dp_lookup=hash`, `dp_bucket_storage=inline_first`, `point_passing=const_ref`, `affine_conversion=batch`, `jump_index`, `jump_table=precomputed`, `scratch=reused`, `range_context=precomputed`, target count, tame/wild state counts, DP table size, and same-parameter single-target comparison fields: `single_target_ops_per_sec`, `speedup_vs_single`, and `target_throughput_vs_single`.

Run the CPU shared-tame tiny 16-target kangaroo experiment:

```sh
python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi16_small --budget-sec 5
```

This records the same `jacobian_kangaroo_multi_small` operation with `target_count=16`, so larger multi-target behavior can be tracked separately from the default 4-target gate.

Run the Metal field-add experiment:

```sh
python3 autoresearch/runner.py --experiment metal_field_add --budget-sec 5
```

If a Metal device is not visible, the experiment records `status=skip` instead of failing. On Apple Silicon with device access, it runs the `field_add_mod_p` Metal microkernel and compares every output against the CPU oracle.

Run the Metal field multiplication experiment:

```sh
python3 autoresearch/runner.py --experiment metal_field_mul --budget-sec 5
```

Like field-add, this records `status=skip` when no Metal device is visible. On Apple Silicon with device access, it runs `field_mul_mod_p` and compares every output against the CPU field oracle.

Run the Metal field subtraction experiment:

```sh
python3 autoresearch/runner.py --experiment metal_field_sub --budget-sec 5
```

Like the other Metal field gates, this records `status=skip` when no Metal device is visible. On Apple Silicon with device access, it runs `field_sub_mod_p`, checks every result against the CPU field oracle, and covers the modular subtraction primitive used by Jacobian point formulas.

Run the Metal field doubling experiment:

```sh
python3 autoresearch/runner.py --experiment metal_field_double --budget-sec 5
```

Like the other Metal field gates, this records `status=skip` when no Metal device is visible. On Apple Silicon with device access, it runs `field_double_mod_p`, checks every result against the CPU field oracle, and tracks the modular doubling primitive used by Jacobian point formulas.

Run the Metal field multiply-by-4 experiment:

```sh
python3 autoresearch/runner.py --experiment metal_field_mul4 --budget-sec 5
```

Like the other Metal field gates, this records `status=skip` when no Metal device is visible. On Apple Silicon with device access, it runs `field_mul4_mod_p`, checks every result against the CPU field oracle, and tracks constant multiplication by four without a second kernel dispatch.

Run the Metal field negation experiment:

```sh
python3 autoresearch/runner.py --experiment metal_field_neg --budget-sec 5
```

Like the other Metal field gates, this records `status=skip` when no Metal device is visible. On Apple Silicon with device access, it runs `field_neg_mod_p`, checks every result against the CPU field oracle, and tracks canonical modular negation.

Run the Metal field square experiment:

```sh
python3 autoresearch/runner.py --experiment metal_field_square --budget-sec 5
```

Like the other Metal field gates, this records `status=skip` when no Metal device is visible. On Apple Silicon with device access, it runs `field_square_mod_p`, checks every result against the CPU field oracle, and tracks the specialized 10-product squaring primitive used heavily by Jacobian point formulas.

Run the CPU field multiplication experiment:

```sh
python3 autoresearch/runner.py --experiment cpu_field_mul --budget-sec 5
```

This records `macos_cpu` `field_mul_mod_p` throughput and includes `EcInt` reference throughput plus `speedup_vs_ecint` in `autoresearch/benchmarks.jsonl`. The default make target uses `--min-ms 50`, so the native timing loop repeats the deterministic sample set long enough to reduce microbenchmark noise.

Results are written to:

- `autoresearch/results.tsv`
- `autoresearch/benchmarks.jsonl`

The current CPU baseline metric is `multiply_g` operations per second. CPU affine point-add walk, CPU Jacobian mixed-add walk, CPU Jacobian jump-table walk, CPU single-target tiny kangaroo, CPU shared-tame tiny multi-target kangaroo at 4 and 16 targets, CPU field multiplication, and Metal field addition/subtraction/doubling/mul4/negation/multiplication/squaring are tracked as separate fixed-gate experiments.
