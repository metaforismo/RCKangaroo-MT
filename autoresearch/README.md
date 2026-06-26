# Autoresearch for RCKangaroo-MT

This folder contains a fixed-gate experiment runner for improving the macOS/Apple Silicon path.

Run the baseline:

```sh
python3 autoresearch/runner.py --experiment baseline --budget-sec 5
```

The runner executes correctness checks before benchmarks. Experiments may set `sample_runs`; when present, the runner executes the benchmark target repeatedly and records median `ops_per_sec` plus `ops_per_sec_min`, `ops_per_sec_max`, and `runner_sample_count` in `autoresearch/benchmarks.jsonl`.

Benchmark rows append `-dirty` to the short commit label whenever `git status --porcelain` is non-empty, so uncommitted candidates cannot be confused with reproducible clean commits.

Use a paired baseline when local CPU load is noisy and a candidate should be compared against a fresh build of another ref in the same run:

```sh
python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi_small --budget-sec 5 --paired-baseline-ref main
```

With `--paired-baseline-ref`, the runner creates a temporary detached worktree for that ref, runs the same correctness checks, then alternates each baseline benchmark sample with the matching candidate sample. The JSON row records `paired_baseline_ref`, `paired_baseline_ops_per_sec`, and `paired_speedup`; keep/discard uses the paired baseline when it is correct and not skipped, otherwise it falls back to previous kept rows.

Experiments usually name a Make target with `bench_target`. For parameterized
probes that should not grow the Makefile, an experiment may instead set
`build_target` plus `bench_command`; the runner builds once per sample set with
`make <build_target>`, then runs the explicit command for each sample and parses
its final JSON line. Paired runs build each side once, then alternate the same
benchmark command in the baseline and candidate worktrees. The core CPU
kangaroo walk gates and the Metal field add, multiply, square, fused
square-mul, and stable DP8 stream gates use this form so experiments do not
pay a phony Make rebuild before every timing sample.

Architecture probes that introduce a new command may also set
`paired_baseline_command`. Paired runs then build both worktrees once, run the
baseline command only in the baseline worktree, and run `bench_command` in the
candidate worktree. This keeps comparisons reproducible when a candidate
cannot be invoked from the baseline ref.

For especially noisy Metal candidates, require repeated full decisions before a keep can enter the ledger:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_jump_walk_dp --budget-sec 10 --paired-baseline-ref main --confirm-runs 3
```

With `--confirm-runs N`, the runner runs the complete benchmark decision `N` times and appends all rows only after applying confirmation policy. A provisional keep is downgraded to `discard` unless every confirmation run also keeps it; JSON rows include `raw_status`, `confirmation_status`, `confirmation_runs`, and `confirmation_index` for auditability.

Large Metal XYZZ experiments also report `validation_workers`, the CPU worker
count used by the replay oracle. By default this follows
`std::thread::hardware_concurrency()` with the existing per-sample cap. Set
`RCK_VALIDATION_WORKERS=N` only for explicit reproducibility or thermal-control
experiments; it never changes the Metal dispatch timing window or the
correctness oracle.

Sparse-DP XYZZ probes keep the promoted DP8 packet specialization intact,
specialize DP12/DP16 with hardcoded masks, and leave other DP densities on the
runtime `ProjectiveDpMask(dp_bits)` path on the same replay oracle:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_dp12_steps512 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_dp16_steps512 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_chain_packets4_steps512 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_persistent_chain_dp12_steps512 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_persistent_chain_dp16_steps512 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_steps512 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_lookup_tg512 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_gpu_filter25m --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_target_lookup_tag32_persistent_tg1024 --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_target_lookup_tag32_filter_exact256 --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_target_lookup_tag32_filter_persistent --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_target_lookup_tag16_hash_filter_persistent_dispatch --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_target_lookup_exact256 --budget-sec 10
```

The affine-scan experiment is a solver-facing bridge: Metal writes final XYZZ
state plus one packet distance per walker, then the host batch-normalizes with
one inversion over `ZZ*ZZZ` products and scans affine `x` low bits. It reports
`dp_tracking=affine_x_limb0_cpu_batch`, `affine_scan_seconds`, and
`gpu_ops_per_sec`. The target-lookup follow-up feeds those real affine DP keys
into the exact tag32 multi-target lookup gate, reporting `dp_query_count`,
`injected_hits`, `lookup_seconds`, `lookups_per_sec`, and
`target_lookup_checksum` separately from walk throughput.

The target-lookup experiment is an exact multi-target join gate for the output
of an affine DP scan. It builds a deterministic open-addressed Metal table of
full affine `x` plus `y` parity keys, probes known hit/miss queries, validates
exact key equality, and records `lookups_per_sec` as the primary metric. The
runner also aliases the median custom metric into `ops_per_sec` for ledger
compatibility, but comparisons should read the explicit
`lookups_per_sec_min/max` fields because this is not a kangaroo walk-step
throughput gate.

The `metal_target_lookup_tag16_hash_filter_persistent_dispatch` gate is a
diagnostic multi-target GPU metric. It compares prehashed query input against
in-kernel query hashing with the same exact CPU verification path, but scores
`gpu_dispatch_lookups_per_sec` so setup allocation and CPU exact-verification
noise do not decide whether the Metal filter kernel itself is worth further
work. Persistent filter lookup commands keep exact verification visible in
`exact_verify_seconds` and `dispatch_lookups_per_sec`, while their `--min-ms`
window is bounded by Metal dispatch time for the GPU-only metric.

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
Use `--paired-baseline-ref main --confirm-runs 3` before promoting a noisy local keep from this primary Metal DP gate.

Run the `steps=4` projective-DP-candidate Metal Jacobian jump-walk experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_jump_walk_dp_steps4 --budget-sec 5
```

This uses the same oracle surface as `metal_jacobian_jump_walk_dp`, but changes the benchmark shape to `--steps 4`. Use it for candidates that specialize shorter walk batches without changing the primary Benchforge `steps=8` score path.

Run the dynamic in-kernel jump-selection Metal experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_walk_dp_stable --budget-sec 10 --paired-baseline-ref main --confirm-runs 3
```

This records `metal` `jacobian_affine_walk_dynamic_jump_table` throughput with
the jump index derived inside the Metal kernel from the current Jacobian state.
The JSON reports `jump_mixer`, `jump_histogram_min_bucket`,
`jump_histogram_max_bucket`, and `jump_histogram_max_deviation_ppm` alongside
the distance and projective-DP checksums, so future partition-function changes
must preserve correctness and expose distribution quality before promotion.

Run the compact dynamic DP-emission Metal experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_compact_dp --budget-sec 10
```

This records `metal` `jacobian_affine_walk_dynamic_dp_compact` throughput with
the same dynamic jump mixer and CPU replay oracle as the full dynamic walk, but
the Metal kernel emits only packed flags, scalar distance, and a compact DP
checksum term. The JSON reports `output_layout=dp_compact` and
`output_bytes_per_sample=17` while preserving `distance_checksum`, `dp_count`,
`dp_checksum`, and jump-histogram quality fields. Treat it as a future
GPU-side DP-emission layout gate; the full dynamic walk remains the final-state
correctness oracle.

Run the sparse dynamic DP-stream Metal experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream --budget-sec 10
```

This records `metal` `jacobian_affine_walk_dynamic_dp_stream` throughput. The
kernel reserves stream slots with a Metal atomic counter and writes only actual
DP records as sample index, scalar distance, and compact DP term. The JSON
reports `output_layout=dp_stream`, `output_bytes_per_record=20`,
`emitted_records`, `dp_capacity`, `dp_stream_overflow`, and a
`dp_distance_checksum`. Use it to measure sparse GPU-side DP emission; DP4 may
be slower than per-sample compact output because atomics are visible at this
density.

Run the runtime-mask DP8 sparse stream experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_dp8 --budget-sec 10
```

This records the same dynamic DP-stream architecture with `dp_bits=8`. The DP4
shape keeps its hardcoded kernel, while DP8 and other non-DP4 shapes use a
runtime `ProjectiveDpMask(dp_bits)` Metal kernel. Use this gate to test whether
rarer distinguished-point emission reduces atomic pressure and output traffic
without changing the CPU replay oracle.

Run the in-place DP8 sparse stream state-update experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_inplace --budget-sec 10
```

This records `metal` `jacobian_affine_walk_dynamic_dp_stream_inplace`
throughput. The kernel updates each Jacobian state in the input buffer, then
emits only sparse DP records. The oracle validates both the emitted stream and
the final raw Jacobian state against CPU replay. Use it for persistent GPU-walk
experiments where state must survive the batch; it is not a replacement for the
pure DP8 stream benchmark when final state is not needed.

Run the 16-step in-place DP8 sparse stream packet experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_inplace_steps16 --budget-sec 10
```

This records the same in-place DP8 stream architecture with `--steps 16`. The
kernel performs 16 dynamic Jacobian jumps per thread before storing the updated
state and checking/emitting a DP record, so it amortizes state memory traffic
over a larger work packet. The CPU oracle validates the 16-step DP stream and
final state. Use this gate when testing persistent walks or packet-size tuning;
it samples the DP predicate at the 16-step packet boundary, not at each
intermediate step.

Run the 32-step in-place DP8 sparse stream packet experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_inplace_steps32 --budget-sec 10
```

This records the same in-place DP8 stream architecture with `--steps 32`.
It is the larger packet-size gate for persistent-walk tuning: the kernel
performs 32 dynamic Jacobian jumps per thread before storing state and checking
the DP predicate. The CPU oracle validates the 32-step DP stream and final
state. Use it when comparing packet sizes; it does not observe intermediate DP
states inside the packet.

Run the 64-step in-place DP8 sparse stream packet experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_inplace_steps64 --budget-sec 10
```

This records the same in-place DP8 stream architecture with `--steps 64`.
It is currently the largest built-in packet-size gate. The CPU oracle validates
the 64-step DP stream and final state, while the benchmark measures whether the
larger packet amortizes state traffic without losing too much occupancy. As
with the other packet gates, DP candidates are sampled only at the packet
boundary.

Run the 128-step in-place DP8 sparse stream packet experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_inplace_steps128 --budget-sec 10
```

This records the same in-place DP8 stream architecture with `--steps 128`.
Use it as a plateau probe for the packet-size ladder. It preserves the CPU
oracle for the 128-step sparse DP stream and final state, but it samples DP
candidates only at the packet boundary.

Run the 256-step in-place DP8 sparse stream packet experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_inplace_steps256 --budget-sec 10
```

This records the same in-place DP8 stream architecture with `--steps 256`.
Use it as a plateau probe and persistent-walk packet option. It preserves the
CPU oracle for the 256-step sparse DP stream and final state, but it samples
DP candidates only at the packet boundary. Same-binary local comparisons beat
the 128-step packet, while raw autoresearch medians are close enough that this
should be treated as packet tuning evidence rather than a guaranteed fastest
default. The accepted macOS default uses a 128-thread cap for in-place DP8
packet sizes `steps=16` and larger; pass `--tg-limit N` through the direct CLI
when retesting dispatch size.

Run the command-backed DP6 sparse stream experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_dp6 --budget-sec 10 --paired-baseline-ref main
```

This records the generic runtime-mask sparse stream path with `dp_bits=6`.
Use it for density-between-DP4-and-DP8 candidates, where record emission is
still common enough to stress atomics but sparse enough to differ from the DP4
score path.

Run the command-backed DP10 sparse stream experiment:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_dp10 --budget-sec 10 --paired-baseline-ref main
```

This records the same sparse stream path with `dp_bits=10` through
`bench_command` instead of a dedicated Make target. It keeps generic
runtime-mask DP behavior measurable for experiments that should not touch the
promoted DP4 and DP8 specializations.

Run the runtime-mask DP8 count-only diagnostic:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_count_dp8 --budget-sec 10
```

This records `metal` `jacobian_affine_walk_dynamic_dp_count` throughput. The
kernel runs the same dynamic walk and DP predicate as the sparse stream path,
but only increments a DP counter and writes no record payloads. Use it to
separate record-write overhead from the arithmetic walk cost; it is a
diagnostic benchmark, not a replacement for `dp_stream` candidate emission.

Run the integrated affine-DP scan plus exact tag32 target-lookup gate:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32 --budget-sec 10
```

This records the macOS integrated multi-target join path with `metric=ops_per_sec`.
The Metal XYZZ packet walk and CPU affine-DP scan produce real packet-boundary
`x256+y_parity` DP keys, the benchmark injects a controlled subset into a
tag32 target table, and the Metal target lookup verifies candidates by exact
key equality after the tag prefilter. Use this gate for end-to-end packet walk
throughput where lookup is included but the default query batch is still the
single DP batch emitted by one scan.

Run the batched affine-DP scan plus exact tag32 target-lookup gate:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_bulk1024 --budget-sec 10
```

This uses the same real DP keys and exact oracle, but passes
`--lookup-repeat 1024` and records `metric=lookups_per_sec`. It is a target
lookup batching gate, not a claim that the mixed-add walk became faster. Use it
to decide whether a solver should accumulate many packet-boundary DPs before
launching the GPU multi-target join instead of dispatching a lookup for each
small DP batch.

Run the distinct-miss batched affine-DP scan plus exact tag32 target-lookup gate:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_distinct_misses1024 --budget-sec 10
```

This uses the same real DP keys and exact target table, passes
`--lookup-repeat 1024 --lookup-query-mode distinct-misses`, and records
`metric=lookups_per_sec`. Unlike the repeat gate, only the first real DP batch
contains target hits; the remaining bulk query slots are deterministic keys
that the host verifies as misses before launching the Metal lookup. Use this
gate to measure a more cache-realistic mostly-miss multi-target join while
keeping exact hit-count, miss-count, and output-index validation.

Run the large-table tag32 GPU filter lookup gate:

```sh
python3 autoresearch/runner.py --experiment metal_target_lookup_tag32_filter_exact256 --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
```

This keeps the final answer exact while changing the GPU memory layout: Metal
probes a 4-byte-per-bucket tag filter and emits only positive query indices,
then the host verifies those compact positives against the full `x256+y_parity`
target keys. The gate records `filter_positive_count`,
`filter_false_positive_count`, exact checksum, and `lookups_per_sec`, so a
false-positive-heavy candidate cannot hide behind a faster dispatch.

Run the persistent large-table tag32 GPU filter gate:

```sh
python3 autoresearch/runner.py --experiment metal_target_lookup_tag32_filter_persistent --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
```

This keeps the compact tag filter, query batch, positive-index output buffer,
and Metal pipeline resident while still verifying compact positives on CPU
with exact `x256+y_parity` equality after each dispatch. The paired baseline is
the non-persistent filter benchmark on the same 25,005,000-target shape. Use
this gate to decide whether a solver should keep the target filter resident
across repeated batches before trying to move exact verification back to GPU.

Run the persistent large-table tag16 GPU filter gate:

```sh
python3 autoresearch/runner.py --experiment metal_target_lookup_tag16_filter_persistent --budget-sec 30 --paired-baseline-ref main --confirm-runs 2
```

This compares a 2-byte-per-bucket resident GPU filter against the accepted
tag32 persistent filter. The final answer is still exact: Metal only emits
compact positives, and the host verifies those positives against the full
`x256+y_parity` target keys. The gate records `filter_positive_count`,
`filter_false_positive_count`, `exact_verify_seconds`, and the exact checksum
so the smaller filter can be kept only when the extra false positives stay
cheap enough.

Run the persistent large-table tag16 prehashed-query GPU filter gate:

```sh
python3 autoresearch/runner.py --experiment metal_target_lookup_tag16_hash_filter_persistent --budget-sec 30 --paired-baseline-ref main --confirm-runs 2
```

This keeps the accepted tag16 resident filter and final CPU exact
`x256+y_parity` verification, but sends precomputed 64-bit query hashes to
Metal instead of full query keys. The gate records `query_input=hash64`,
`target_query_hash_bytes`, `filter_positive_count`, false positives, exact
verification time, and checksum, so a query-bandwidth win cannot hide changed
candidate semantics.

Run the integrated large-table explicit GPU-filter gate:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_gpu_filter25m --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
```

This uses the 25,005,000-target, mostly-miss, `lookup_repeat=1024` shape and
records `metric=ops_per_sec`. The paired baseline is the same integrated
benchmark routed through `--lookup-engine cpu`; the candidate uses explicit
`--lookup-engine gpu-filter`. Treat this as the promotion gate before changing
`--lookup-engine auto`, not as a standalone lookup-only microbenchmark.

Run the CPU field multiplication experiment:

```sh
python3 autoresearch/runner.py --experiment cpu_field_mul --budget-sec 5
```

This records `macos_cpu` `field_mul_mod_p` throughput and includes `carry_impl`, `ecint_mul_final_sub`, `EcInt` reference throughput, and `speedup_vs_ecint` in `autoresearch/benchmarks.jsonl`. On Apple Clang, `carry_impl=clang_builtin` means add/sub carry chains use `__builtin_addcll` and `__builtin_subcll`; other compilers use the portable `unsigned __int128` fallback. The default make target uses `--min-ms 50`, so the native timing loop repeats the deterministic sample set long enough to reduce microbenchmark noise.

Results are written to:

- `autoresearch/results.tsv`
- `autoresearch/benchmarks.jsonl`

The current CPU baseline metric is `multiply_g` operations per second. CPU affine point-add walk, CPU Jacobian mixed-add walk, CPU Jacobian jump-table walk, CPU single-target tiny kangaroo, CPU shared-tame tiny multi-target kangaroo at 4 and 16 targets, CPU field multiplication, Metal field addition/subtraction/doubling/mul4/negation/multiplication/squaring, Metal Jacobian-plus-affine add, fixed-step Metal Jacobian walk, Metal jump-table Jacobian walk, Metal distance-aware jump-table Jacobian walk, Metal projective-DP-candidate jump-table walk, sparse DP stream, and in-place sparse DP stream state update are tracked as separate fixed-gate experiments.
