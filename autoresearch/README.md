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

With `--paired-baseline-ref`, the runner creates a temporary detached worktree for that ref, runs the same correctness checks, then alternates each baseline benchmark sample with the matching candidate sample. The JSON row records `paired_baseline_ref`, `paired_baseline_ops_per_sec`, and `paired_speedup`; keep/discard uses the paired baseline when it is correct and not skipped, otherwise it falls back to previous kept rows.

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

This records `macos_cpu` `jacobian_jump_walk` throughput. The experiment runs three paired samples and records median/min/max throughput to reduce scheduler noise in this very short walk-core benchmark. The benchmark precomputes affine jump points, keeps the walk state in Jacobian coordinates, passes the Jacobian step point by const reference (`jacobian_step_passing=const_ref`), reports the shared integer carry path as `ecint_carry_impl` and the final `MulModP` reduction mode as `ecint_mul_final_sub`, selects jumps with a bit mask when `jump_count` is a power of two (`jump_index=power2_mask`, otherwise `modulo`), tracks scalar distance in parallel, and checks the final point against a scalar oracle. It is a deterministic walk-core benchmark, not a full DP/collision kangaroo solver yet.

Run the CPU Jacobian batch-to-affine conversion experiment:

```sh
python3 autoresearch/runner.py --experiment jacobian_batch_affine --budget-sec 5
```

This records `macos_cpu` `jacobian_batch_affine` batch conversions per second and affine points per second for a deterministic tame-plus-wild batch. It isolates the conversion primitive used by the shared-tame multi-target kangaroo loop and reports `field_rhs_passing=const_ref`, `affine_z_access=const_ref`, `affine_z_check=infinity_flag`, `affine_field_ops=inplace`, `affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`, `affine_reverse_loop=split_zero`, and `affine_tail_update=skip_final`, so future changes to field-copy avoidance, z-validity checks, field-op temporaries, inversion batching, affine buffer layout, reverse-loop branching, or reverse-pass tail work can be measured without DP lookup and walk-step noise.

Run the CPU single-target tiny kangaroo experiment:

```sh
python3 autoresearch/runner.py --experiment jacobian_kangaroo_small --budget-sec 5
```

This records `macos_cpu` `jacobian_kangaroo_small` solves per second. The benchmark generates one deterministic synthetic target, precomputes the deterministic jump table and range/tame-start context once per run, reuses scratch storage across measured solves, and reports `architecture=single_target`, `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `ecint_carry_impl`, `ecint_mul_final_sub`, `dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `candidate_verification=full_point_collision`, `dp_reserve=sqrt_range_estimate`, `dp_capacity=max_load_2of3`, `dp_bucket_storage=inline_first`, `dp_clear=empty_guard`, `point_passing=const_ref`, `affine_conversion=batch`, `jump_index`, `jump_table=precomputed`, `scratch=reused`, `range_context=precomputed`, tame/wild state counts, and DP table size.

Run the CPU shared-tame tiny multi-target kangaroo experiment:

```sh
python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi_small --budget-sec 5
```

This records `macos_cpu` `jacobian_kangaroo_multi_small` solves per second. The benchmark generates deterministic synthetic targets, places one solvable target at the final index, precomputes the deterministic jump table and range/tame-start context once per run, reuses scratch storage across measured solves, and reports `architecture=shared_tame`, `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `ecint_carry_impl`, `ecint_mul_final_sub`, `dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `candidate_verification=full_point_collision`, `dp_reserve=sqrt_range_estimate`, `dp_capacity=max_load_2of3`, `dp_bucket_storage=inline_first`, `dp_clear=empty_guard`, `point_passing=const_ref`, `affine_conversion=batch`, `affine_z_access=const_ref`, `affine_z_check=infinity_flag`, `affine_field_ops=inplace`, `affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`, `affine_reverse_loop=split_zero`, `affine_tail_update=skip_final`, `jump_index`, `jump_table=precomputed`, `scratch=reused`, `range_context=precomputed`, target count, tame/wild state counts, DP table size, and same-parameter single-target comparison fields: `single_target_ops_per_sec`, `speedup_vs_single`, and `target_throughput_vs_single`. The DP hash uses a partial-limb mix for the open-address probe start; compressed `x+parity(y)` equality guards point identity and proves candidates after range and target-index checks. The DP reserve estimate starts from sqrt(range), applies `dp_bits`, targets a denser two-thirds max load, and still rehashes if a run needs more slots.

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

Run the Metal Jacobian-plus-affine add experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_add --budget-sec 5
```

This records `metal` `jacobian_add_affine` throughput for the first point-level Apple Silicon GPU primitive. The benchmark emits `x/y/z` plus an infinity flag, validates each output against the CPU Jacobian formula oracle, includes generic additions plus `p` infinity, doubling, and point-at-infinity branch cases, and uses three runner samples by default.

Run the fixed-step Metal Jacobian walk experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_walk --budget-sec 5
```

This records `metal` `jacobian_affine_walk_fixed` throughput. Each Metal thread keeps one Jacobian state in registers, applies the same affine mixed-add step a fixed number of times, emits the final `x/y/z` plus infinity flag, and validates against the CPU oracle loop. It is a walk-core layer before variable jump selection and distinguished-point handling.

Run the jump-table Metal Jacobian walk experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_jump_walk --budget-sec 5
```

This records `metal` `jacobian_affine_walk_jump_table` throughput. Each Metal thread keeps one Jacobian state in registers, reads a deterministic per-sample jump-index sequence, selects from an affine jump table, accumulates the corresponding 64-bit scalar distance, emits the final `x/y/z` plus infinity flag and distance, and validates against the CPU oracle that replays the same indices. It is still below full kangaroo scope because it does not yet include distinguished-point filtering or collision table writes.

Run the distance-aware Metal Jacobian jump-walk experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_jump_walk_distance --budget-sec 5
```

This records the same Metal jump-table walk while treating scalar-distance accumulation as part of the gate. The JSON includes `distance_tracking=uint64` and a deterministic `distance_checksum`, so future changes cannot keep point correctness while silently dropping distance state.

Run the projective-DP-candidate Metal Jacobian jump-walk experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_jump_walk_dp --budget-sec 5
```

This records the same distance-aware Metal jump-table walk with `--dp-bits 4`. The kernel emits `dp_tracking=projective_x_limb0`, `dp_count`, and `dp_checksum`, and the CPU oracle verifies the same projective low-bit predicate. This is a cheap GPU-side candidate filter, not yet the affine distinguished-point key required for final collision-table matching.

Run the `steps=4` projective-DP-candidate Metal Jacobian jump-walk experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_jump_walk_dp_steps4 --budget-sec 5
```

This uses the same oracle surface as `metal_jacobian_jump_walk_dp`, but changes the benchmark shape to `--steps 4`. Use it for candidates that specialize shorter walk batches without changing the primary Benchforge `steps=8` score path.

Run the CPU field multiplication experiment:

```sh
python3 autoresearch/runner.py --experiment cpu_field_mul --budget-sec 5
```

This records `macos_cpu` `field_mul_mod_p` throughput and includes `carry_impl`, `ecint_mul_final_sub`, `EcInt` reference throughput, and `speedup_vs_ecint` in `autoresearch/benchmarks.jsonl`. On Apple Clang, `carry_impl=clang_builtin` means add/sub carry chains use `__builtin_addcll` and `__builtin_subcll`; other compilers use the portable `unsigned __int128` fallback. The default make target uses `--min-ms 50`, so the native timing loop repeats the deterministic sample set long enough to reduce microbenchmark noise.

Results are written to:

- `autoresearch/results.tsv`
- `autoresearch/benchmarks.jsonl`

The current CPU baseline metric is `multiply_g` operations per second. CPU affine point-add walk, CPU Jacobian mixed-add walk, CPU Jacobian jump-table walk, CPU single-target tiny kangaroo, CPU shared-tame tiny multi-target kangaroo at 4 and 16 targets, CPU field multiplication, Metal field addition/subtraction/doubling/mul4/negation/multiplication/squaring, Metal Jacobian-plus-affine add, fixed-step Metal Jacobian walk, Metal jump-table Jacobian walk, Metal distance-aware jump-table Jacobian walk, and Metal projective-DP-candidate jump-table walk are tracked as separate fixed-gate experiments.
