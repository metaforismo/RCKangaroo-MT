# Autoresearch for RCKangaroo-MT

This folder contains a fixed-gate experiment runner for improving the macOS/Apple Silicon path.

Run the baseline:

```sh
python3 autoresearch/runner.py --experiment baseline --budget-sec 5
```

The runner executes correctness checks before benchmarks:

```sh
make macos-check
make macos-bench
```

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

This records `macos_cpu` `jacobian_jump_walk` throughput. The benchmark precomputes affine jump points, keeps the walk state in Jacobian coordinates, tracks scalar distance in parallel, and checks the final point against a scalar oracle. It is a deterministic walk-core benchmark, not a full DP/collision kangaroo solver yet.

Run the CPU single-target tiny kangaroo experiment:

```sh
python3 autoresearch/runner.py --experiment jacobian_kangaroo_small --budget-sec 5
```

This records `macos_cpu` `jacobian_kangaroo_small` solves per second. The benchmark generates one deterministic synthetic target, precomputes the deterministic jump table once per run, reuses scratch storage across measured solves, and reports `architecture=single_target`, `dp_lookup=hash`, `affine_conversion=batch`, `jump_table=precomputed`, `scratch=reused`, tame/wild state counts, and DP table size.

Run the CPU shared-tame tiny multi-target kangaroo experiment:

```sh
python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi_small --budget-sec 5
```

This records `macos_cpu` `jacobian_kangaroo_multi_small` solves per second. The benchmark generates deterministic synthetic targets, places one solvable target at the final index, precomputes the deterministic jump table once per run, reuses scratch storage across measured solves, and reports `architecture=shared_tame`, `dp_lookup=hash`, `affine_conversion=batch`, `jump_table=precomputed`, `scratch=reused`, target count, tame/wild state counts, DP table size, and same-parameter single-target comparison fields: `single_target_ops_per_sec`, `speedup_vs_single`, and `target_throughput_vs_single`.

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

Run the CPU field multiplication experiment:

```sh
python3 autoresearch/runner.py --experiment cpu_field_mul --budget-sec 5
```

This records `macos_cpu` `field_mul_mod_p` throughput and includes `EcInt` reference throughput plus `speedup_vs_ecint` in `autoresearch/benchmarks.jsonl`. The default make target uses `--min-ms 50`, so the native timing loop repeats the deterministic sample set long enough to reduce microbenchmark noise.

Results are written to:

- `autoresearch/results.tsv`
- `autoresearch/benchmarks.jsonl`

The current CPU baseline metric is `multiply_g` operations per second. CPU affine point-add walk, CPU Jacobian mixed-add walk, CPU Jacobian jump-table walk, CPU single-target tiny kangaroo, CPU shared-tame tiny multi-target kangaroo, CPU field multiplication, and Metal field addition/multiplication are tracked as separate fixed-gate experiments.
