# macOS native tools

RCKangaroo-MT still uses NVIDIA CUDA for the full high-performance kangaroo solver, but the `macos/` folder now provides native Apple Silicon tooling for target preparation, secp256k1 correctness checks, tiny-range CPU solves, CPU field arithmetic, benchmarks, Metal runtime smoke tests, and early Metal field arithmetic.

## Build and Check

```sh
make macos-check
```

This builds `macos/rck_macos`, runs host secp256k1 vector checks, validates target parsing, runs the native CPU selftest, checks CPU field arithmetic, and runs the Metal field-add/sub/double/mul4/neg/mul/square checks when Metal is visible.

The default macOS build uses `-O3` plus ThinLTO (`MACOS_LTO_FLAGS=-flto=thin`). ThinLTO lets clang optimize the Jacobian and secp256k1 field call graph across translation units, which is especially useful for the CPU fallback on Apple Silicon. Override or disable it when needed:

```sh
make macos-check MACOS_CXXFLAGS="-std=c++17 -O0 -g -I."
make macos-check MACOS_LTO_FLAGS=
```

Run a tiny-range CPU solve:

```sh
./macos/rck_macos solve-small --range 8 --start 0 --pubkey 025CBDF0646E5DB4EAA398F365F2EA7A0E3D419B7E0330E39CE92BDDEDCAC4F9BC
./macos/rck_macos jacobian-kangaroo-small --range 8 --start 0 --pubkey 025CBDF0646E5DB4EAA398F365F2EA7A0E3D419B7E0330E39CE92BDDEDCAC4F9BC --jumps 8 --dp-bits 0 --max-steps 4096
./macos/rck_macos jacobian-kangaroo-multi-small --range 8 --start 2 --targets tests/jacobian_kangaroo_multi_targets.txt --jumps 8 --dp-bits 0 --max-steps 4096
```

`jacobian-kangaroo-small` is a bounded toy solver for tiny ranges. It runs tame/wild walks with a deterministic jump table, keeps walk states in Jacobian coordinates, passes field RHS values and Jacobian step points by const reference (`field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`), batch-converts the tame/wild pair to affine with one field inversion per loop (`affine_conversion=batch`), records distinguished points in a reusable compressed point-key open-addressed table (`dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`) with a sqrt-range reserve estimate (`dp_reserve=sqrt_range_estimate`), a two-thirds max-load capacity target (`dp_capacity=max_load_2of3`), the first DP stored inline in each bucket (`dp_bucket_storage=inline_first`), and empty-overflow clear avoidance (`dp_clear=empty_guard`), avoids unnecessary point copies in hot checks (`point_passing=const_ref`), reports the DP table size as `dp_count`, and proves collision-derived candidates from cross-side full affine point equality plus a range check (`candidate_verification=full_point_collision`). It is intended for correctness and architecture experiments only; it is not the full CUDA/Metal kangaroo engine.

`jacobian-kangaroo-multi-small` loads a target file with the shared target parser and runs one bounded tame walk plus one wild walk per target in the same Jacobian kangaroo loop. The tame distinguished-point table is shared across all wild targets and indexed by a reusable linear-probing table (`dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `dp_reserve=sqrt_range_estimate`, `dp_capacity=max_load_2of3`, `dp_bucket_storage=inline_first`, `dp_clear=empty_guard`) so collision checks only scan DPs for the same compressed point key while the common one-DP-per-key case avoids per-record vector allocation. The hash mixes a few point limbs for the probe start, and x-plus-y-parity equality still guards exact affine point identity. A cross-side full-point collision proves the candidate after range and target-index checks (`candidate_verification=full_point_collision`), so the hot tiny solver does not re-run `MultiplyG` after every solved collision. The reserve estimate uses sqrt(range) and `dp_bits` to avoid large mostly empty tables when `max_steps` is much larger than the tiny test range; the table targets a denser two-thirds max load and still rehashes if needed. Hot point arguments, field RHS values, Jacobian step points, and affine-vector reads use const references (`point_passing=const_ref`, `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `affine_z_access=const_ref`). The batch affine path trusts the maintained infinity flag for Z validity (`affine_z_check=infinity_flag`), uses in-place field multiplications for prefix and coordinate conversion (`affine_field_ops=inplace`), reuses vector storage, has an all-active fast path for the normal tame-plus-wild loop, handles the all-active reverse-loop index zero outside the loop (`affine_reverse_loop=split_zero`), and skips the unused final reverse-pass tail update (`affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`, `affine_tail_update=skip_final`). The CLI reports target counts, active tame/wild state counts, and DP table size. This is still tiny-range CPU code for correctness and architecture experiments; it is not the full CUDA/Metal engine.

Both tiny kangaroo solvers report `affine_initial_conversion=unit_z_copy`. At solver step zero the tame and wild Jacobian states were just created from affine points, so their `Z` coordinate is exactly one and the first affine view can copy `x/y` without a field inversion. Later steps still use `affine_conversion=batch`; the DP predicate, collision verification, range checks, target-index checks, and jump schedule are unchanged.

Run a CPU benchmark:

```sh
make macos-bench
make macos-point-bench
./macos/rck_macos point-bench --iterations 256 --min-ms 50
make macos-jacobian-point-bench
./macos/rck_macos jacobian-point-bench --iterations 256 --min-ms 50
make macos-jacobian-batch-affine-bench
./macos/rck_macos jacobian-batch-affine-bench --iterations 256 --min-ms 50 --points 17
make macos-jacobian-walk-bench
./macos/rck_macos jacobian-walk-bench --iterations 256 --min-ms 50 --jumps 16
make macos-jacobian-kangaroo-small-bench
./macos/rck_macos jacobian-kangaroo-small-bench --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096
make macos-jacobian-kangaroo-multi-small-bench
./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 4 --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096
make macos-jacobian-kangaroo-multi16-small-bench
./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096
./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 50 --range 20 --jumps 4 --dp-bits 4 --max-steps 500000 --jump-schedule scaled4-balanced
./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 0 --range 20 --jumps 4 --dp-bits 4 --max-steps 2000000 --jump-schedule scaled4-balanced --key-offset 524288
./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 0 --range 20 --jumps 4 --dp-bits 4 --max-steps 2000000 --jump-schedule scaled4-probe-power2 --key-offset 900000
```

`macos-bench` measures scalar `MultiplyG` throughput. `macos-point-bench` measures a serialized affine point-add walk: it starts at `2G`, repeatedly adds `G`, and validates the final point against a single `MultiplyG(n+2)` oracle. This is still CPU affine arithmetic, not the final Metal/Jacobian solver path, but it is closer to kangaroo walk cost than isolated field operations.

`macos-jacobian-point-bench` keeps the walk point in Jacobian coordinates and performs mixed Jacobian-plus-affine additions of `G`, moving the expensive field inversion out of the inner loop. The JSON includes an affine reference throughput and `speedup_vs_affine` so improvements are measured against the simpler point-add baseline.

`macos-jacobian-batch-affine-bench` isolates the batch inversion path used by the shared-tame multi-target solver. It builds one tame Jacobian point plus configurable wild Jacobian points, converts the full batch to affine with one field inversion per iteration, validates every affine point against scalar references, reports `field_rhs_passing=const_ref`, `affine_z_access=const_ref`, `affine_z_check=infinity_flag`, `affine_field_ops=inplace`, `affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`, `affine_reverse_loop=split_zero`, and `affine_tail_update=skip_final`, and reports batch conversions per second plus affine points per second.

`macos-jacobian-walk-bench` uses a deterministic jump table of affine points and applies mixed Jacobian additions selected from the current projective state. It passes the projective step point by const reference (`jacobian_step_passing=const_ref`) and reports `ecint_carry_impl` plus `ecint_mul_final_sub` so carry-chain and final-reduction changes in the shared `EcInt` path are visible in the JSON. For power-of-two jump counts it selects jumps with a bit mask instead of integer modulo (`jump_index=power2_mask`, falling back to `modulo` otherwise). It tracks scalar distance in parallel and validates the final point against a scalar oracle. This is a walk-core benchmark, not yet a full kangaroo solver with distinguished points or collision handling.

`macos-jacobian-kangaroo-small-bench` generates one deterministic synthetic target and measures tiny single-target kangaroo solves per second with the open-addressed DP lookup. It precomputes the deterministic jump table and range/tame-start context once per benchmark run, reuses scratch storage across measured solves, and reports `architecture=single_target`, `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `ecint_carry_impl`, `ecint_mul_final_sub`, `dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `candidate_verification=full_point_collision`, `dp_reserve=sqrt_range_estimate`, `dp_capacity=max_load_2of3`, `dp_bucket_storage=inline_first`, `dp_clear=empty_guard`, `point_passing=const_ref`, `affine_conversion=batch`, `affine_initial_conversion=unit_z_copy`, `jump_index`, `jump_table=precomputed`, `scratch=reused`, `range_context=precomputed`, tame/wild state counts, and DP table size so it can be compared directly with the shared-tame multi-target benchmark.

`macos-jacobian-kangaroo-multi-small-bench` generates deterministic synthetic targets, places one solvable target at the final index, precomputes the deterministic jump table and range/tame-start context once per benchmark run, reuses scratch storage across measured solves, and measures tiny shared-tame multi-target solves per second with the open-addressed DP lookup. The multi solver reports `affine_conversion=batch` because it batch-converts tame plus wild Jacobian states with one field inversion per loop after the step-zero `affine_initial_conversion=unit_z_copy` fast path, and the benchmark reports `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `ecint_carry_impl`, `ecint_mul_final_sub`, `dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `candidate_verification=full_point_collision`, `dp_reserve=sqrt_range_estimate`, `dp_capacity=max_load_2of3`, `dp_bucket_storage=inline_first`, `dp_clear=empty_guard`, `point_passing=const_ref`, `affine_z_access=const_ref`, `affine_z_check=infinity_flag`, `affine_field_ops=inplace`, `affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`, `affine_reverse_loop=split_zero`, `affine_tail_update=skip_final`, `jump_index`, `jump_table=precomputed`, `scratch=reused`, and `range_context=precomputed`. It also runs a same-parameter single-target baseline and reports `single_target_ops_per_sec`, `speedup_vs_single`, and `target_throughput_vs_single`; the last field multiplies multi solves per second by target count before comparing with the single-target baseline. Use `--target-count` to compare 1, 2, 4, 8, or larger target sets while keeping the same bounded range and jump parameters. The Makefile also exposes `macos-jacobian-kangaroo-multi16-small-bench` and the matching autoresearch experiment to track 16-target behavior separately from the default 4-target gate.

Benchmark commands accept `--jump-schedule power2` by default. The experimental `--jump-schedule scaled4-balanced` mode is valid only with `--jumps 4` and uses distances `{1, 2, 8192, 8193}`. It keeps gcd `1` while matching the mean scalar advance of the 16-entry power-of-two schedule, so it is a solver-facing schedule probe rather than a raw per-step kernel optimization. JSON output includes `jump_schedule` so autoresearch rows can separate default and experimental walks.

The CPU tiny kangaroo benchmarks also accept opt-in `--jump-schedule scaled4-probe-power2` with `--jumps 4`. This is a solver-level portfolio probe: it first runs a short `scaled4-balanced` attempt, by default `min(max_steps, max(10000, max_steps / 200))` steps, then falls back to a 16-jump `power2` table if the probe does not solve. Use `--portfolio-probe-steps N` to sweep that first-stage budget explicitly. JSON reports `portfolio_probe_max_steps`, `portfolio_probe_hits`, `portfolio_fallback_runs`, `last_portfolio_probe_dp_count`, and the fallback jump table fields so the probe cost is not hidden. This path is for schedule research on tiny CPU oracles; it is not the default Metal gate.

The CPU kangaroo bench commands also accept `--key-offset N` to place the synthetic solvable key at a chosen offset inside the bounded range. Without it, the historical fixtures are preserved (`0x7` for the single-target bench and `start + 5` for the multi-target bench). JSON output includes the clamped `key_offset`, which is useful for schedule sweeps across lower, middle, and upper interval positions.

Run CPU secp256k1 field arithmetic checks and the multiplication benchmark:

```sh
./macos/rck_macos cpu-field-test
make macos-cpu-field-bench
./macos/rck_macos cpu-field-bench --iterations 4096 --min-ms 50
```

The CPU field path uses four little-endian 64-bit limbs. On Apple Clang, add/sub carry chains use `__builtin_addcll` and `__builtin_subcll`; other compilers keep the portable `unsigned __int128` fallback. The benchmark reports `field_mul_mod_p` throughput, `carry_impl`, `ecint_mul_final_sub`, and an `EcInt` reference throughput for comparison. The shared `EcInt` wrappers used by the Jacobian walk and kangaroo paths report their own mode as `ecint_carry_impl`. `--iterations` controls the deterministic sample set size; `--min-ms` repeats that sample set until the native measurement has run for at least that many milliseconds, which gives autoresearch less noisy timing data.

Run the Metal smoke test:

```sh
./macos/rck_macos metal-smoke
```

If no Metal device is visible in the current execution environment, the command reports a skip instead of failing. On a normal Apple Silicon runtime with device access, it compiles and runs a minimal Metal compute kernel.

Run the Metal secp256k1 field-add, field-sub, field-double, field-mul4, field-neg, field-mul, field-square, and fused field-square-mul checks and benchmarks:

```sh
./macos/rck_macos metal-field-test
make macos-metal-field-bench
make macos-metal-target-lookup-bench
./macos/rck_macos metal-target-lookup-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500
make macos-metal-target-lookup-compact-bench
./macos/rck_macos metal-target-lookup-compact-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500
make macos-metal-target-lookup-tag32-bench
./macos/rck_macos metal-target-lookup-tag32-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500
make macos-metal-target-lookup-tag32-filter-bench
./macos/rck_macos metal-target-lookup-tag32-filter-bench --target-count 25005000 --query-count 1082368 --hits 64 --min-ms 500
make macos-metal-target-lookup-tag32-filter-persistent-bench
./macos/rck_macos metal-target-lookup-tag32-filter-persistent-bench --target-count 25005000 --query-count 1082368 --hits 64 --min-ms 700
make macos-metal-target-lookup-tag16-filter-persistent-bench
./macos/rck_macos metal-target-lookup-tag16-filter-persistent-bench --target-count 25005000 --query-count 1082368 --hits 64 --min-ms 700
make macos-metal-target-lookup-tag16-hash-filter-persistent-bench
./macos/rck_macos metal-target-lookup-tag16-hash-filter-persistent-bench --target-count 25005000 --query-count 1082368 --hits 64 --min-ms 700
make macos-metal-target-lookup-tag32-persistent-bench
./macos/rck_macos metal-target-lookup-tag32-persistent-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500
./macos/rck_macos metal-target-lookup-tag32-persistent-bench --target-count 25005000 --query-count 1082368 --hits 64 --min-ms 700
./macos/rck_macos target-lookup-tag32-cpu-bench --target-count 25005000 --query-count 1057 --hits 64 --min-ms 50
RCK_TARGET_SETUP_WORKERS=6 ./macos/rck_macos target-lookup-tag32-parallel-insert-bench --target-count 25005000 --injected-count 64 --iterations 1
./macos/rck_macos metal-field-sub-test
make macos-metal-field-sub-bench
./macos/rck_macos metal-field-double-test
make macos-metal-field-double-bench
./macos/rck_macos metal-field-mul4-test
make macos-metal-field-mul4-bench
./macos/rck_macos metal-field-neg-test
make macos-metal-field-neg-bench
./macos/rck_macos metal-field-mul-test
make macos-metal-field-mul-bench
./macos/rck_macos metal-field-square-test
make macos-metal-field-square-bench
./macos/rck_macos metal-field-square-mul-test
make macos-metal-field-square-mul-bench
./macos/rck_macos metal-jacobian-add-test
make macos-metal-jacobian-add-bench
./macos/rck_macos metal-jacobian-walk-test
make macos-metal-jacobian-walk-bench
./macos/rck_macos metal-jacobian-jump-walk-test
make macos-metal-jacobian-jump-walk-bench
make macos-metal-jacobian-jump-walk-dp-bench
./macos/rck_macos metal-jacobian-dynamic-walk-test
make macos-metal-jacobian-dynamic-walk-bench
make macos-metal-jacobian-dynamic-walk-stable-bench
./macos/rck_macos metal-jacobian-dynamic-compact-dp-test
make macos-metal-jacobian-dynamic-compact-dp-bench
make macos-metal-jacobian-dynamic-compact-dp-stable-bench
./macos/rck_macos metal-jacobian-dynamic-dp-stream-test
make macos-metal-jacobian-dynamic-dp-stream-bench
make macos-metal-jacobian-dynamic-dp-stream-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-dp8-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-inplace-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-inplace-steps16-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-inplace-steps32-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-inplace-steps64-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-inplace-steps128-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-inplace-steps256-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-xyzz-steps256-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-stable-bench
make macos-metal-jacobian-dynamic-dp-stream-xyzz-chain-steps512-bench
make macos-metal-jacobian-dynamic-dp-count-dp8-stable-bench
make macos-metal-kernels-check
```

The field kernels use four little-endian 64-bit limbs modulo the secp256k1 prime and compare Metal output against CPU oracles. `field_sub_mod_p` handles modular underflow by adding the secp256k1 prime after a borrowed subtraction. `field_double_mod_p` computes modular doubling with one input load and the same conditional reduction used by addition, which gives Jacobian formulas a cheaper path for explicit `2*x` terms. `field_mul4_mod_p` computes `4*x mod p` by applying the same in-kernel doubling helper twice, avoiding two separate kernel dispatches for formulas with explicit `4*x` terms. `field_neg_mod_p` computes canonical modular negation, keeping zero as zero and using `p - x` for nonzero inputs. `field_mul_mod_p` uses 32-bit decomposition internally for portable 64x64 multiplication inside Metal; `field_square_mod_p` uses a symmetric square accumulator with 10 limb products before the shared reducer, matching the Jacobian formulas that square field elements heavily. `field_square_mul_mod_p` fuses `a*a*b mod p` into one dispatch and validates against the same CPU oracle composition, giving future Jacobian Metal work a lower-overhead benchmark for adjacent square/multiply terms. `target_lookup_exact256` is an exact multi-target join gate for packet-boundary affine DP candidates: it probes a deterministic open-addressed table keyed by full affine `x` plus `y` parity, uses exact key equality for candidate verification, and reports `lookup_layout=open_address_exact256`, `target_key=x256_y_parity`, `target_table_bytes`, `bytes_per_target`, `lookups_per_sec`, and `target_lookup_checksum`. `target_lookup_compact_exact256` keeps the same exact `x256+y_parity` verification but stores a 64-bit hash plus target index in the open-address table and keeps full keys in a separate target-key array; `target_lookup_tag32_exact256` stores only a 32-bit high-hash tag plus target index in each bucket, then fetches and compares the full target key on tag match. JSON reports `target_key_bytes`, `target_bucket_bytes`, and reduced `bytes_per_target` for the compact layouts. The target lookup default threadgroup cap is 64 threads on M3; explicit `--tg-limit N` overrides it for sweeps. `jacobian_add_affine` is the first point-level Metal primitive: it computes a batch of Jacobian-plus-affine additions, emits an infinity flag with `x/y/z`, covers the generic path plus `p` infinity, doubling, and point-at-infinity branches, and validates each result against the CPU Jacobian formula oracle. `jacobian_affine_walk_fixed` keeps each Jacobian state inside one Metal thread for a fixed number of repeated mixed-add steps, then validates the final state against the same CPU oracle loop; this is a walk-core layer before variable jump tables and DP handling. `jacobian_affine_walk_jump_table` keeps the same register-resident Jacobian state but reads a host-validated deterministic per-sample, per-step jump index and selects from an affine jump table without a modulo in the kernel loop, accumulates the matching 64-bit scalar distance, optionally emits a projective `x[0]` low-bit DP candidate flag, and validates final point plus distance plus flag against a CPU oracle that replays the exact index sequence. The DP flag is a cheap projective candidate filter, not an affine collision-table key. The public `steps=8`, `dp_bits=4` Metal specialization uses packed byte input for infinity flags and a binary-compatible struct-row view of the affine jump table while generic fallback shapes keep the wider host format and scalar table indexing. Metal dispatches default to a larger SIMD-aligned threadgroup capped at 256 threads instead of a single execution-width group. Benchmarks report `threadgroup_limit`, `thread_execution_width`, `max_threads_per_threadgroup`, and `threads_per_threadgroup` for reproducibility. Metal benchmarks accept `--min-ms`; the Makefile uses `--min-ms 50` so short dispatch overhead is smoothed while JSON still reports `sample_count`, `min_ms`, total `iterations`, `distance_checksum`, `dp_count`, `dp_checksum`, and `ops_per_sec`. Use `--tg-limit N` on Metal bench commands to test an alternate threadgroup cap without changing the default. In restricted CI or sandboxed sessions without a visible Metal device, runtime checks report a clean skip. `macos-metal-kernels-check` compiles the extracted Metal source when the Metal Toolchain is installed; otherwise it reports a clean toolchain skip.

`make macos-build` also tries to build an ignored sidecar library at `macos/rck_macos.metallib` plus `macos/rck_macos.metallib.meta` from the same `MetalFieldKernels.h` source when `xcrun metal` and `xcrun metallib` are available. The sidecar is compiled with `MACOS_METAL_FLAGS ?= -finline-functions`, which can be overridden for toolchain experiments. At runtime, the sidecar is auto-loaded only when its metadata hash matches the embedded Metal source; stale or missing metadata falls back to runtime source compilation. To test a sidecar deliberately even without matching metadata, run with `RCK_METAL_USE_PRECOMPILED=1`; to load a specific library, set `RCK_METAL_FIELD_LIB=/path/to/rck_macos.metallib`; to force the source path, set `RCK_METAL_DISABLE_PRECOMPILED=1`. If the Metal Toolchain is unavailable, the build removes stale sidecars and the binary keeps using the runtime source fallback.

`jacobian_affine_walk_dynamic_jump_table` is a separate Metal walk architecture that computes the kangaroo jump index inside the kernel from the current Jacobian state, using the same `x/y/z` mixer as the CPU kangaroo path. It supports both power-of-two mask and modulo jump counts, tracks 64-bit distance and projective DP candidates, and has a `steps=8`, `dp_bits=4` specialization with packed infinity flags plus struct-row jump table access. This path is closer to a real GPU kangaroo walk than the synthetic precomputed-index benchmark, but it is reported separately and is not used for the public precomputed DP score path.
For power-of-two jump counts, the dynamic `steps=8`, `dp_bits=4` path uses a branchless `jump_mask` specialization. Non-power-of-two jump counts stay on the generic dynamic kernel so modulo behavior remains covered by the same CPU replay oracle.
The in-place DP8 stream path also has `steps=16`, `steps=32`, `steps=64`, `steps=128`, and `steps=256` packet specializations. They perform more dynamic jumps per thread, store the updated Jacobian state back to the input buffer, and validate the sparse DP stream plus final state against CPU replay. These modes are useful for persistent GPU-walk packet tuning because they amortize state load/store traffic over more group operations; they check the DP predicate only at the packet boundary. The 256-step packet is a plateau probe: local paired comparisons beat 128 steps, but raw autoresearch medians remain close enough that callers should choose the packet size deliberately instead of assuming the largest packet is always fastest. In-place DP8 packet sizes `steps=16` and larger default to a 128-thread cap on M3 because paired testing beat the shared 256-thread cap; `steps=8` keeps the shared default, and explicit `--tg-limit N` still overrides both.

`jacobian_affine_walk_dynamic_dp_stream_xyzz` is a separate packet architecture that stores state as `X,Y,ZZ,ZZZ` instead of `X,Y,Z`. It updates `ZZ` and `ZZZ` directly in the mixed-add formula, avoiding a per-step recomputation of `Z^2` and `Z^3`, and validates both the sparse DP stream and final XYZZ state against a CPU XYZZ replay oracle. Because the state no longer stores `Z`, the jump mixer uses the same avalanche structure with `ZZ0` in place of `Z0`; the operation is reported separately from the Jacobian in-place packet. DP8 uses the hardcoded `0xFF` packet specialization for the promoted fast path, DP12 has a hardcoded `0xFFF` specialization for sparse solver probes, DP16 has a hardcoded `0xFFFF` specialization for very sparse table-pressure probes, and the remaining values use a runtime `ProjectiveDpMask(dp_bits)` kernel so DP10 and other shapes can still be measured on the same XYZZ oracle without changing the mathematics. The 256-step kernel is the coordinate-system baseline, and paired autoresearch on M3 kept the 512-step specialization as the current XYZZ packet plateau. Run it with `metal-jacobian-dynamic-dp-stream-xyzz-bench --steps 512 --jumps 16 --dp-bits 8` for the promoted plateau, or change `--dp-bits` for sparsity probes.

`metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-bench` is the first packet-boundary affine-DP probe. The Metal kernel performs the XYZZ dynamic walk and writes one 64-bit packet distance per walker; the host then batch-normalizes `X,Y,ZZ,ZZZ` with one inversion over the `ZZ*ZZZ` products, scans low bits of affine `x`, and reports `dp_tracking=affine_x_limb0_cpu_batch`. Large batches split the batch-product and affine-recovery work across CPU workers while preserving one global inversion and the same reverse-order DP checksum/key output. This keeps the DP predicate solver-facing without adding per-step inversions. JSON separates raw GPU throughput (`gpu_ops_per_sec`) from end-to-end packet-plus-affine-scan throughput (`ops_per_sec`) and records `affine_scan_seconds`, so future work can move the normalization onto Metal without hiding the cost. The affine-scan path also supports `--steps 1024` with `--dp-bits 7`, `--steps 2048` with `--dp-bits 6`, and a reproducibility-only `--steps 4096` with `--dp-bits 5` probe. Paired local results keep 2048/dp6 as the plateau and discard 4096/dp5. For that 2048/dp6 plateau, a local setup-inclusive gate accepted `--jumps 4 --jump-schedule scaled4-balanced` against the 16-jump `power2` schedule; treat it as a reproducible schedule probe until more machines confirm it.

The affine-scan JSON also reports `dp_sampling=packet_endpoint` and `dp_normalization=host_batch_affine`. These labels are intentional anti-cheat telemetry: current fast gates normalize packet endpoints, not every internal step, so future per-step or full-state DP pipelines must report a different sampling scope.

`metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench` connects that affine DP surface to the exact compact multi-target lookup gate. The host scan emits full affine `x256` plus `y` parity for real packet-boundary DP candidates, injects a controlled number of those keys into a tag32 target table, and runs the Metal `target_lookup_tag32_exact256` kernel against the DP query set by default. Runtime JSON reports `output_layout=affine_dp_scan_target_lookup`, `dp_tracking=affine_x256_y_parity_cpu_batch`, `target_key=x256_y_parity`, `candidate_verification`, `dp_query_count`, `lookup_repeat`, `lookup_query_mode`, `lookup_engine`, `lookup_engine_effective`, `query_count`, `injected_hits`, `hit_count`, `miss_count`, `lookup_seconds`, `lookup_hash_seconds`, `lookup_gpu_seconds`, `lookup_exact_seconds`, `gpu_lookup_lookups_per_sec`, `lookups_per_sec`, and `target_lookup_checksum`. `--lookup-engine cpu` keeps the GPU walk and affine scan unchanged, but routes the final exact tag32 target join through the host CPU. `--lookup-engine gpu-filter` uses a 4-byte-per-bucket Metal tag filter and then verifies only compact positives on CPU with exact `x256 + y_parity` equality; JSON reports `lookup_layout=open_address_tag32_filter_exact256`, `filter_positive_count`, and `filter_false_positive_count`. `--lookup-engine gpu-filter16-hash` uses the 2-byte tag16 filter and precomputed 64-bit query hashes from the standalone target-lookup gate, then resolves compact positives with the same exact CPU equality; JSON reports `lookup_layout=open_address_tag16_hash_filter_exact256`, `query_input=hash64`, `target_query_hash_bytes`, and the same positive/false-positive counters. `--lookup-engine gpu-filter16-hash-repeat` is repeat-mode-only: it sends one base DP hash batch to Metal, dispatches a 2D `(base_query, repeat)` tag16 filter grid, and reports `query_input=hash64_repeat_indexed`; when base-query and repeat dimensions both fit 16 bits, the GPU emits packed `(repeat_id, base_query_id)` positives so the exact CPU resolver avoids logical-index division/modulo. Larger integrated sparse-repeat shapes can emit `base_query_count_repeated` base-count positives: the GPU still probes every logical repeat, while the sparse resolver receives per-base counts and still accounts every logical repeated hit or false positive. Full-output repeat paths keep logical indices. JSON records the chosen repeat positive index path as `repeat_positive_index_encoding`. For accumulated query batches of at least 2,097,152 rows, the host query-hash builder switches from serial to thresholded parallel hashing while keeping `lookup_hash_seconds` visible. `--lookup-engine auto` keeps the requested engine visible as `lookup_engine=auto`, then records the chosen path in `lookup_engine_effective`; the current policy keeps large bounded 25M-target batches on CPU until an end-to-end paired gate confirms the filter path, and still uses GPU with a 512-thread lookup cap for cache-friendlier target tables when the accumulated lookup batch reaches at least one million queries. `--lookup-tg-limit N` tunes only the final Metal target-lookup kernel, leaving the XYZZ walk threadgroup policy unchanged. `--lookup-repeat N` expands the real affine-DP query batch before lookup so the benchmark can model a solver that accumulates packet-boundary DPs before launching a larger target join. The default `--lookup-query-mode repeat` repeats the real DP batch and repeats the expected exact target indices by the same factor. `--lookup-query-mode distinct-misses` keeps one real DP batch, then fills the remaining bulk query slots with deterministic keys that are verified to miss the tag32 target table; this gives a more cache-realistic mostly-miss target-join probe while preserving an exact hit/miss oracle. The default `N=1` and `--lookup-engine gpu` keep the original end-to-end gate. The `bulk1024`, `distinct_misses1024`, `lookup_tg512`, `gpu_filter25m`, `tag16_hash_filter25m_tg256_gpu_lookup`, `tag16_hash_filter25m_parallel_hash_repeat4096`, `tag16_hash_filter25m_repeat_indexed2048`, `tag16_hash_filter25m_repeat_packed_positive2048`, `steps2048_dp6_setup`, and `scaled4_j4_setup` autoresearch gates intentionally separate lookup throughput from walk throughput. The companion `metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench` builds distinct deterministic walk batches for `--rounds`, batches those starts into one larger Metal walk dispatch, splits the output back into per-round affine scans and target offsets, injects per-round hits into one shared target table/filter, concatenates all round DP keys into one aggregate repeat lookup dispatch, and emits aggregate `round_count`, DP, lookup, hit, false-positive, and checksum fields; use it as the stricter steady-state anti-cheat probe before promoting multi-target speed claims. For large standard tag16 repeat batches it can use the same `base_query_count_repeated` output path as the integrated benchmark, so every logical repeat is still probed on Metal while repeated positives are returned as per-base counts and resolved against the exact CPU key table. Its `--lookup-filter-bits 16|32` and `--lookup-filter-mode tag16|tag16-mix|tag32` options keep the default 2-byte tag16 hash-repeat filter, test a same-size mixed tag16 hash-repeat filter, or switch to a 4-byte tag32 hash-repeat filter; every mode still resolves positives with exact CPU `x256 + y_parity` equality. `--lookup-repeat-mode dedup` is an explicit non-default diagnostic for repeated batches: it filters each base DP query once, expands exact outputs back to the same logical repeat oracle, and reports `physical_query_count` plus `physical_filter_positive_count`; compare it only as a repeated-query upper bound, not as distinct-query throughput. This is an integrated non-cheating multi-target join benchmark for the macOS path: walk throughput, affine scan cost, target filtering, jump-schedule distribution, and exact verification remain visible.

Target-lookup affine-scan JSON additionally reports `target_lookup_scope=packet_endpoint_dp_keys`, making clear that the compact multi-target join consumes the packet-endpoint DP keys emitted by the host affine scan.

The fixed-round command also accepts `--walk-round-mode independent|persistent`. The default `independent` mode keeps the promoted one-dispatch batching of distinct deterministic round starts. `persistent` advances the same walker states across rounds, writes each round boundary and cumulative distance directly from the Metal kernel, records `walk_round_mode=persistent` and `distance_tracking=round_cumulative_uint64`, and validates every boundary against a cumulative CPU replay oracle. Treat it as a solver-like architecture probe, not the current speed default: local M3 gates are close and noisy, so default promotion still requires the canonical paired 25M gate.

The target-lookup JSON also reports `mean_jump_distance`, `gpu_distance_per_sec`, `distance_per_sec`, `setup_inclusive_distance_per_sec`, and `setup_inclusive_wall_distance_per_sec`. These multiply the measured group-operation rates by the schedule's mean jump distance, so schedule probes can compare effective kangaroo distance covered per second instead of optimizing raw operation rate alone.

For fixed-round `--lookup-query-mode distinct-misses`, the tag16/Bloom64 hash-filter path can report `query_input=hash64_prefix_gpu_miss`. In that mode the host sends only the real DP-prefix hashes to Metal and lets the GPU derive deterministic suffix miss hashes inside the filter kernel. The CPU resolver exact-checks real DP-prefix positives and GPU filter-positive generated suffix misses; if a generated suffix unexpectedly resolves as an exact target, the code falls back to the raw physical hash-buffer retry path.

The fixed-round command also accepts `--lookup-query-mode distinct-misses`. In that mode it keeps the real DP keys once, fills the remaining physical query batch with deterministic keys verified to miss the exact compact x-only-plus-parity target table, runs the non-repeat tag16 hash-filter kernel against every physical query, resolves positives with exact `x256 + y_parity` equality, and validates the full output against explicit expected indices. The diagnostic `--lookup-filter-mode tag16-mix` is supported on the same distinct path, but it is not a default policy after the local M3 25M gate measured more false positives and no speed win. Use distinct-misses when checking whether a repeat-mode gain survives a more realistic mostly-miss DP stream; it is intentionally separate from `--lookup-repeat-mode dedup`, which remains only a repeated-query upper-bound diagnostic.

For standard tag16 integrated lookup paths, the tag16 target filter may be filled during tag32 table insertion. In JSON, `target_filter_build_seconds=0` means that setup was fused into `target_build_seconds`; use `setup_inclusive_ops_per_sec` when comparing setup-heavy runs.

For large sparse-repeat base-count outputs, the standard tag16 repeat kernel dispatches as `(repeat, base_query)` and reduces positives inside each threadgroup before one global add per block. It still probes every logical repeat and preserves `base_query_count_repeated`, but avoids the old per-positive global atomic pressure on the repeated-hit bases.

The standard integrated repeat lookup also accepts `--lookup-filter-mode tag16-mix` as an explicit diagnostic for the repeat-indexed tag16 hash filter. It keeps the same 2-byte filter footprint, fused setup path, base-count positive encoding, and exact CPU resolver, but local M3 paired confirmation discarded it against standard tag16 on setup-inclusive throughput, so it is not a default policy.

`metal-target-lookup-tag32-persistent-bench` keeps the Metal tag32 target table, keys, queries, output, and pipeline resident while repeating dispatches for the requested `--min-ms`. Its JSON separates `metal_setup_seconds`, warmed `dispatch_seconds`, setup-inclusive `lookups_per_sec`, and `dispatch_lookups_per_sec`. The default threadgroup cap remains 64 below 16,777,216 targets, but large diagnostic tables use 1024 by default on M3 after paired 25M-target checks; explicit `--tg-limit N` always overrides this adaptive default. This is a diagnostic for long-lived GPU target-table economics, not a replacement for the integrated affine-scan target-lookup gate.

On setup-heavy target-table runs, `RCK_TARGET_SETUP_WORKERS=N` is an explicit
reproducible tuning knob for table construction only. It does not change the
validation/replay worker count unless `RCK_VALIDATION_WORKERS` is also set. The
JSON reports `target_setup_workers` beside `validation_workers`, so paired gates
can tell whether a target-table tuning changed the real path. Local M3 checks
did not justify a new automatic worker default; leave the default worker count
alone unless a paired gate for the exact command proves otherwise.

`metal-target-lookup-tag32-filter-persistent-bench` keeps the compact 4-byte tag filter, query batch, positive-index output buffer, and pipeline resident, then verifies only the compact positives on CPU with exact `x256 + y_parity` equality after each dispatch. Its JSON reports `buffer_lifetime=persistent`, `filter_positive_count`, `filter_false_positive_count`, `metal_setup_seconds`, `dispatch_seconds`, `exact_verify_seconds`, setup-inclusive `lookups_per_sec`, no-setup `dispatch_lookups_per_sec`, and pure Metal `gpu_dispatch_lookups_per_sec`. The no-setup metric includes exact CPU verification time; the GPU metric is dispatch-only, and `--min-ms` is bounded by accumulated Metal dispatch time. Large filter tables use a 512-thread default on M3, while explicit `--tg-limit N` overrides it.

`metal-target-lookup-tag16-filter-persistent-bench` keeps the same persistent filter architecture but stores a 2-byte high-hash tag per GPU bucket. The smaller resident filter cuts large 25M-target filter memory in half, at the cost of extra tag collisions; correctness still comes only from the CPU exact `x256 + y_parity` equality over compact positives. JSON uses `lookup_layout=open_address_tag16_filter_exact256`, `candidate_verification=tag16_filter_then_cpu_exact_key_equality`, and reports false positives separately from true hits so the speedup cannot hide lost correctness.

`metal-target-lookup-tag16-hash-filter-persistent-bench` uses the same resident tag16 filter and exact CPU verification, but the Metal kernel reads precomputed 64-bit query hashes instead of full `TargetLookupKey` rows. JSON reports `query_input=hash64`, `target_query_hash_bytes`, `lookup_layout=open_address_tag16_hash_filter_exact256`, and `candidate_verification=tag16_hash_filter_then_cpu_exact_key_equality`. This is a query-bandwidth and hash-work probe; it does not change the target table, the positive-index resolver, or the final exact equality oracle.

`jacobian_affine_walk_dynamic_dp_stream_xyzz_chain` extends the XYZZ packet path into a solver-facing cumulative-distance probe. It keeps `X,Y,ZZ,ZZZ`, infinity flags, and a per-sample distance buffer resident across multiple packet dispatches in one Metal command buffer. Runtime JSON reports `packet_count`, `distance_tracking=dp_stream_cumulative_uint64`, `stream_indexing=packet_sample_u32`, and `jump_schedule`; this lets one walker emit multiple boundary DPs without confusing records from different packets. The host oracle replays every packet boundary, validates final XYZZ state, and checks sparse stream count, duplicates, missing DPs, distances, and DP terms. The chain and persistent-chain bench commands accept `--dp-bits` up to 32 bits with hardcoded DP8/DP12/DP16 and runtime masks for the other values; long-step packets default to a 128-thread cap on M3, and explicit `--tg-limit N` still overrides it. They also accept `--jump-schedule scaled4-balanced` with `--jumps 4` for schedule-correctness probes, while default behavior remains `power2`. This is an architecture probe for persistent GPU walks, not a replacement for the single-packet XYZZ throughput baseline.

`jacobian_affine_walk_dynamic_dp_compact` is a dynamic-only `steps=8`, `dp_bits=4`, power-of-two jump-count benchmark for future GPU-side distinguished-point emission. It uses the same in-kernel jump mixer and CPU replay oracle as the full dynamic walk, but emits only packed flags, 64-bit scalar distance, and a compact DP checksum term instead of copying the final 96-byte Jacobian state. Runtime JSON marks this as `output_layout=dp_compact` and `output_bytes_per_sample=17`; the full dynamic walk remains the exact final-state oracle and collision-verification reference.

`jacobian_affine_walk_dynamic_dp_stream` pushes the same idea further by using an atomic counter to emit only actual DP records as `(sample_index, distance, dp_term)`. Runtime JSON marks this as `output_layout=dp_stream`, `output_bytes_per_record=20`, `emitted_records`, `dp_capacity`, and `dp_stream_overflow`. The stream is unordered, so host verification reconstructs per-sample DP flags before comparing against the CPU replay oracle. The DP4 gate still uses the hardcoded DP4 kernel; other `dp_bits` values use a runtime `ProjectiveDpMask(dp_bits)` kernel so sparse DP8/DP12 shapes can be measured without changing the walk oracle. When the host proves the maximum eight-step scalar distance fits in `uint32_t`, the non-DP4 stream kernel uses a guarded 32-bit internal distance accumulator and casts back to the 64-bit stream output, preserving the `dp_stream_uint64` oracle. The DP8 stream shape additionally has a hardcoded `0xFF` mask specialization, avoiding a runtime DP-mask buffer while keeping the same emitted records and checksums. Because `dp_capacity` equals sample count and each sample can emit at most one record, that DP8 specialization omits the in-kernel overflow branch; the host still reports overflow if the final atomic count exceeds capacity. The very sparse DP12 stream shape defaults to a 128-thread cap after paired confirmation on M3, while DP6 and DP10 remain on the shared 256-thread default after noisy confirmation rejected smaller/larger caps. Explicit `--tg-limit N` always overrides these defaults. On the DP4 gate this reduces logical output volume sharply, but atomics can make it slower than per-sample compact output; treat it as a sparse-emission architecture probe for higher `dp_bits`, not as a replacement for the full final-state oracle.

`jacobian_affine_walk_dynamic_dp_count` is a count-only diagnostic for the same dynamic walk. It uses the runtime DP mask and an atomic counter, but writes no DP records, distances, or checksum terms. Runtime JSON marks this as `output_layout=dp_count`, `output_bytes_total=4`, and `distance_tracking=none`. Use it to estimate how much of a sparse-stream run is record-write overhead versus the arithmetic walk itself; it is not a collision-candidate output path.

Example threadgroup sweep commands:

```sh
./macos/rck_macos metal-field-mul-bench --iterations 1048576 --min-ms 50 --tg-limit 128
./macos/rck_macos metal-field-mul-bench --iterations 1048576 --min-ms 50 --tg-limit 256
./macos/rck_macos metal-field-mul-bench --iterations 1048576 --min-ms 50 --tg-limit 512
./macos/rck_macos metal-jacobian-add-bench --iterations 65536 --min-ms 50 --tg-limit 256
./macos/rck_macos metal-jacobian-walk-bench --iterations 16384 --steps 8 --min-ms 50 --tg-limit 256
./macos/rck_macos metal-jacobian-jump-walk-bench --iterations 16384 --steps 8 --jumps 16 --min-ms 50 --tg-limit 256
./macos/rck_macos metal-jacobian-jump-walk-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 50 --tg-limit 256
./macos/rck_macos metal-jacobian-dynamic-walk-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 50 --tg-limit 256
./macos/rck_macos metal-jacobian-dynamic-compact-dp-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 200 --tg-limit 256
./macos/rck_macos metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 200 --tg-limit 256
./macos/rck_macos metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 8 --min-ms 200 --tg-limit 256
./macos/rck_macos metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 12 --min-ms 200
./macos/rck_macos metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 12 --min-ms 200 --tg-limit 256
./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-chain-bench --iterations 262144 --steps 512 --packets 2 --jumps 16 --dp-bits 8 --min-ms 500
./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-chain-bench --iterations 262144 --steps 512 --packets 2 --jumps 4 --dp-bits 8 --min-ms 500 --jump-schedule scaled4-balanced
./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench --iterations 262144 --steps 512 --packets 2 --rounds 2 --jumps 16 --dp-bits 8
./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench --iterations 262144 --steps 512 --packets 2 --rounds 2 --jumps 4 --dp-bits 8 --jump-schedule scaled4-balanced
./macos/rck_macos metal-jacobian-dynamic-dp-count-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 8 --min-ms 200 --tg-limit 256
./macos/rck_macos metal-target-lookup-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500 --tg-limit 64
./macos/rck_macos metal-target-lookup-compact-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500 --tg-limit 64
./macos/rck_macos metal-target-lookup-tag32-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500 --tg-limit 64
```

## Prepare a target list

```sh
python3 macos/prepare_targets.py stripped.txt -o targets.cleaned.txt
```

The script:

- accepts compressed `02...` / `03...` and uncompressed `04...` secp256k1 public keys;
- validates every point against the secp256k1 curve;
- removes blank lines, comment lines, and inline `# comments`;
- writes normalized compressed public keys by default;
- removes duplicate targets unless `--keep-duplicates` is used;
- streams input and output, then atomically promotes the output after validation.

Useful options:

```sh
python3 macos/prepare_targets.py stripped.txt --stats-only
python3 macos/prepare_targets.py stripped.txt -o targets.cleaned.txt --skip-invalid
python3 macos/prepare_targets.py stripped.txt -o targets.uncompressed.txt --uncompressed
```

Then copy `targets.cleaned.txt` to the CUDA host and run:

```sh
./rckangaroo -dp 16 -range 84 -start 1000000000000000000000 -targets targets.cleaned.txt
```

To measure the shared target parser plus non-zero `-start` mapping path on the
Mac, run:

```sh
./macos/rck_macos target-set-load-bench --target-count 1048576 --start 2
./macos/rck_macos target-set-load-bench --target-count 1048576 --start 2 --key-format uncompressed
```

The command reports `operation=target_set_load` and `targets_per_sec`. It
isolates the startup phase that maps loaded public keys by subtracting
`start*G`; it is not a Metal kangaroo-walk or GKeys/s benchmark. It also
reports `target_record_bytes`, `target_storage_bytes`, `source_line_storage`,
`source_line_base`, and `explicit_source_line_bytes`. Dense stripped files use
`dense_index_plus_one`; files with only an initial header/comment offset use
`dense_index_plus_base`; files with non-dense source lines use `explicit_u32`
and preserve the old per-target line reporting exactly.

For very large target files, `--uncompressed` output can be faster to load even
though it is larger on disk:

```sh
python3 macos/prepare_targets.py stripped.txt -o targets.uncompressed.txt --uncompressed
```

If your input has already been deduplicated, add `--keep-duplicates` to avoid
the preparer's duplicate-tracking set and minimize memory use while streaming.
Without `--keep-duplicates`, duplicate removal is still exact and deterministic.

Compressed target files require the runtime loader to recover `y` with a field
square root for each key. Uncompressed files skip that step and only validate the
given point. On the MacBook Air M3 loader probe, the same 1,048,576 target
fixture mapped with identical checksums at about `2.47M` targets/sec
uncompressed versus about `198k` targets/sec compressed.

## Notes

The macOS script is intentionally pure Python and uses only the standard library. It does not need Homebrew, CUDA, OpenSSL, or third-party Python packages.

Use autoresearch from the repo root:

```sh
python3 autoresearch/runner.py --experiment baseline --budget-sec 5
python3 autoresearch/runner.py --experiment point_add_g --budget-sec 5
python3 autoresearch/runner.py --experiment jacobian_point_add_g --budget-sec 5
python3 autoresearch/runner.py --experiment jacobian_jump_walk --budget-sec 5
python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi_small --budget-sec 5
python3 autoresearch/runner.py --experiment cpu_field_mul --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_add --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_sub --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_double --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_mul4 --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_neg --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_mul --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_square --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_square_mul --budget-sec 5
python3 autoresearch/runner.py --experiment metal_target_lookup_exact256 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_target_lookup_compact_exact256 --budget-sec 10 --paired-baseline-ref main
python3 autoresearch/runner.py --experiment metal_target_lookup_tag32_exact256 --budget-sec 10 --paired-baseline-ref main
python3 autoresearch/runner.py --experiment metal_target_lookup_tag32_filter_exact256 --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_target_lookup_tag32_filter_persistent --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_target_lookup_tag16_filter_persistent --budget-sec 30 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_target_lookup_tag16_hash_filter_persistent --budget-sec 30 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_bulk1024 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_distinct_misses1024 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_gpu_filter25m --budget-sec 10 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_parallel_hash_repeat2048 --budget-sec 120 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_parallel_hash_repeat4096 --budget-sec 120 --paired-baseline-ref main --confirm-runs 2
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_scaled4_j4_setup --budget-sec 540 --paired-baseline-ref main --confirm-runs 2
```

The `jacobian_jump_walk` experiment uses three runner samples and records median/min/max throughput, which makes walk-core comparisons less sensitive to short macOS scheduler spikes.

Autoresearch records Metal device absence as `status=skip`, not as a crash, so the same experiment can run on both local Apple Silicon and headless CI.

If you want to generate tames for the full solver, do that on the CUDA host. With multi-target mode, existing tames must already exist; generate them separately before using `-targets`.
