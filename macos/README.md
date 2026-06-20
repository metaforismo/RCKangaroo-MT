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

`jacobian-kangaroo-small` is a bounded toy solver for tiny ranges. It runs tame/wild walks with a deterministic jump table, keeps walk states in Jacobian coordinates, passes field RHS values and Jacobian step points by const reference (`field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`), batch-converts the tame/wild pair to affine with one field inversion per loop (`affine_conversion=batch`), records distinguished points in a reusable compressed point-key open-addressed table (`dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`) with a sqrt-range reserve estimate (`dp_reserve=sqrt_range_estimate`) and the first DP stored inline in each bucket (`dp_bucket_storage=inline_first`), avoids unnecessary point copies in hot checks (`point_passing=const_ref`), reports the DP table size as `dp_count`, and proves collision-derived candidates from cross-side full affine point equality plus a range check (`candidate_verification=full_point_collision`). It is intended for correctness and architecture experiments only; it is not the full CUDA/Metal kangaroo engine.

`jacobian-kangaroo-multi-small` loads a target file with the shared target parser and runs one bounded tame walk plus one wild walk per target in the same Jacobian kangaroo loop. The tame distinguished-point table is shared across all wild targets and indexed by a reusable linear-probing table (`dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `dp_reserve=sqrt_range_estimate`, `dp_bucket_storage=inline_first`) so collision checks only scan DPs for the same compressed point key while the common one-DP-per-key case avoids per-record vector allocation. The hash mixes a few point limbs for the probe start, and x-plus-y-parity equality still guards exact affine point identity. A cross-side full-point collision proves the candidate after range and target-index checks (`candidate_verification=full_point_collision`), so the hot tiny solver does not re-run `MultiplyG` after every solved collision. The reserve estimate uses sqrt(range) and `dp_bits` to avoid large mostly empty tables when `max_steps` is much larger than the tiny test range; the table still rehashes if needed. Hot point arguments, field RHS values, Jacobian step points, and affine-vector reads use const references (`point_passing=const_ref`, `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `affine_z_access=const_ref`). The batch affine path reuses vector storage and has an all-active fast path for the normal tame-plus-wild loop (`affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`). The CLI reports target counts, active tame/wild state counts, and DP table size. This is still tiny-range CPU code for correctness and architecture experiments; it is not the full CUDA/Metal engine.

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
```

`macos-bench` measures scalar `MultiplyG` throughput. `macos-point-bench` measures a serialized affine point-add walk: it starts at `2G`, repeatedly adds `G`, and validates the final point against a single `MultiplyG(n+2)` oracle. This is still CPU affine arithmetic, not the final Metal/Jacobian solver path, but it is closer to kangaroo walk cost than isolated field operations.

`macos-jacobian-point-bench` keeps the walk point in Jacobian coordinates and performs mixed Jacobian-plus-affine additions of `G`, moving the expensive field inversion out of the inner loop. The JSON includes an affine reference throughput and `speedup_vs_affine` so improvements are measured against the simpler point-add baseline.

`macos-jacobian-batch-affine-bench` isolates the batch inversion path used by the shared-tame multi-target solver. It builds one tame Jacobian point plus configurable wild Jacobian points, converts the full batch to affine with one field inversion per iteration, validates every affine point against scalar references, reports `field_rhs_passing=const_ref`, `affine_z_access=const_ref`, `affine_buffer=resize_reuse`, and `affine_active_path=all_active_fast`, and reports batch conversions per second plus affine points per second.

`macos-jacobian-walk-bench` uses a deterministic jump table of affine points and applies mixed Jacobian additions selected from the current projective state. It passes the projective step point by const reference (`jacobian_step_passing=const_ref`). For power-of-two jump counts it selects jumps with a bit mask instead of integer modulo (`jump_index=power2_mask`, falling back to `modulo` otherwise). It tracks scalar distance in parallel and validates the final point against a scalar oracle. This is a walk-core benchmark, not yet a full kangaroo solver with distinguished points or collision handling.

`macos-jacobian-kangaroo-small-bench` generates one deterministic synthetic target and measures tiny single-target kangaroo solves per second with the open-addressed DP lookup. It precomputes the deterministic jump table and range/tame-start context once per benchmark run, reuses scratch storage across measured solves, and reports `architecture=single_target`, `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `candidate_verification=full_point_collision`, `dp_reserve=sqrt_range_estimate`, `dp_bucket_storage=inline_first`, `point_passing=const_ref`, `affine_conversion=batch`, `jump_index`, `jump_table=precomputed`, `scratch=reused`, `range_context=precomputed`, tame/wild state counts, and DP table size so it can be compared directly with the shared-tame multi-target benchmark.

`macos-jacobian-kangaroo-multi-small-bench` generates deterministic synthetic targets, places one solvable target at the final index, precomputes the deterministic jump table and range/tame-start context once per benchmark run, reuses scratch storage across measured solves, and measures tiny shared-tame multi-target solves per second with the open-addressed DP lookup. The multi solver reports `affine_conversion=batch` because it batch-converts tame plus wild Jacobian states with one field inversion per loop, and the benchmark reports `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `candidate_verification=full_point_collision`, `dp_reserve=sqrt_range_estimate`, `dp_bucket_storage=inline_first`, `point_passing=const_ref`, `affine_z_access=const_ref`, `affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`, `jump_index`, `jump_table=precomputed`, `scratch=reused`, and `range_context=precomputed`. It also runs a same-parameter single-target baseline and reports `single_target_ops_per_sec`, `speedup_vs_single`, and `target_throughput_vs_single`; the last field multiplies multi solves per second by target count before comparing with the single-target baseline. Use `--target-count` to compare 1, 2, 4, 8, or larger target sets while keeping the same bounded range and jump parameters. The Makefile also exposes `macos-jacobian-kangaroo-multi16-small-bench` and the matching autoresearch experiment to track 16-target behavior separately from the default 4-target gate.

Run CPU secp256k1 field arithmetic checks and the multiplication benchmark:

```sh
./macos/rck_macos cpu-field-test
make macos-cpu-field-bench
./macos/rck_macos cpu-field-bench --iterations 4096 --min-ms 50
```

The CPU field path uses four little-endian 64-bit limbs. On Apple Clang, add/sub carry chains use `__builtin_addcll` and `__builtin_subcll`; other compilers keep the portable `unsigned __int128` fallback. The benchmark reports `field_mul_mod_p` throughput, `carry_impl`, and an `EcInt` reference throughput for comparison. `--iterations` controls the deterministic sample set size; `--min-ms` repeats that sample set until the native measurement has run for at least that many milliseconds, which gives autoresearch less noisy timing data.

Run the Metal smoke test:

```sh
./macos/rck_macos metal-smoke
```

If no Metal device is visible in the current execution environment, the command reports a skip instead of failing. On a normal Apple Silicon runtime with device access, it compiles and runs a minimal Metal compute kernel.

Run the Metal secp256k1 field-add, field-sub, field-double, field-mul4, field-neg, field-mul, and field-square checks and benchmarks:

```sh
./macos/rck_macos metal-field-test
make macos-metal-field-bench
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
make macos-metal-kernels-check
```

The field kernels use four little-endian 64-bit limbs modulo the secp256k1 prime and compare Metal output against CPU oracles. `field_sub_mod_p` handles modular underflow by adding the secp256k1 prime after a borrowed subtraction. `field_double_mod_p` computes modular doubling with one input load and the same conditional reduction used by addition, which gives Jacobian formulas a cheaper path for explicit `2*x` terms. `field_mul4_mod_p` computes `4*x mod p` by applying the same in-kernel doubling helper twice, avoiding two separate kernel dispatches for formulas with explicit `4*x` terms. `field_neg_mod_p` computes canonical modular negation, keeping zero as zero and using `p - x` for nonzero inputs. `field_mul_mod_p` uses 32-bit decomposition internally for portable 64x64 multiplication inside Metal; `field_square_mod_p` now uses a symmetric square accumulator with 10 limb products before the shared reducer, matching the Jacobian formulas that square field elements heavily. In restricted CI or sandboxed sessions without a visible Metal device, runtime checks report a clean skip. `macos-metal-kernels-check` compiles the extracted Metal source when the Metal Toolchain is installed; otherwise it reports a clean toolchain skip.

## Prepare a target list

```sh
python3 macos/prepare_targets.py stripped.txt -o targets.cleaned.txt
```

The script:

- accepts compressed `02...` / `03...` and uncompressed `04...` secp256k1 public keys;
- validates every point against the secp256k1 curve;
- removes blank lines, comment lines, and inline `# comments`;
- writes normalized compressed public keys by default;
- removes duplicate targets unless `--keep-duplicates` is used.

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
```

The `jacobian_jump_walk` experiment uses three runner samples and records median/min/max throughput, which makes walk-core comparisons less sensitive to short macOS scheduler spikes.

Autoresearch records Metal device absence as `status=skip`, not as a crash, so the same experiment can run on both local Apple Silicon and headless CI.

If you want to generate tames for the full solver, do that on the CUDA host. With multi-target mode, existing tames must already exist; generate them separately before using `-targets`.
