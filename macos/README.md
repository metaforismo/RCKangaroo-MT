# macOS native tools

RCKangaroo-MT still uses NVIDIA CUDA for the full high-performance kangaroo solver, but the `macos/` folder now provides native Apple Silicon tooling for target preparation, secp256k1 correctness checks, tiny-range CPU solves, CPU field arithmetic, benchmarks, Metal runtime smoke tests, and early Metal field arithmetic.

## Build and Check

```sh
make macos-check
```

This builds `macos/rck_macos`, runs host secp256k1 vector checks, validates target parsing, runs the native CPU selftest, checks CPU field arithmetic, and runs the Metal field-add check when Metal is visible.

The default macOS build uses `-O3`. Override it when needed:

```sh
make macos-check MACOS_CXXFLAGS="-std=c++17 -O0 -g -I."
```

Run a tiny-range CPU solve:

```sh
./macos/rck_macos solve-small --range 8 --start 0 --pubkey 025CBDF0646E5DB4EAA398F365F2EA7A0E3D419B7E0330E39CE92BDDEDCAC4F9BC
./macos/rck_macos jacobian-kangaroo-small --range 8 --start 0 --pubkey 025CBDF0646E5DB4EAA398F365F2EA7A0E3D419B7E0330E39CE92BDDEDCAC4F9BC --jumps 8 --dp-bits 0 --max-steps 4096
./macos/rck_macos jacobian-kangaroo-multi-small --range 8 --start 2 --targets tests/jacobian_kangaroo_multi_targets.txt --jumps 8 --dp-bits 0 --max-steps 4096
```

`jacobian-kangaroo-small` is a bounded toy solver for tiny ranges. It runs tame/wild walks with a deterministic jump table, keeps walk states in Jacobian coordinates, batch-converts the tame/wild pair to affine with one field inversion per loop (`affine_conversion=batch`), records distinguished points in raw point-key hash buckets (`dp_lookup=hash`) with the first DP stored inline in each bucket (`dp_bucket_storage=inline_first`), reports the DP table size as `dp_count`, and verifies any collision-derived candidate against `MultiplyG`. It is intended for correctness and architecture experiments only; it is not the full CUDA/Metal kangaroo engine.

`jacobian-kangaroo-multi-small` loads a target file with the shared target parser and runs one bounded tame walk plus one wild walk per target in the same Jacobian kangaroo loop. The tame distinguished-point table is shared across all wild targets and indexed by hash buckets (`dp_lookup=hash`, `dp_bucket_storage=inline_first`) so collision checks only scan DPs for the same point key while the common one-DP-per-key case avoids per-record vector allocation. Collision candidates are verified against the matching target index, and the CLI reports target counts, active tame/wild state counts, and DP table size. This is still tiny-range CPU code for correctness and architecture experiments; it is not the full CUDA/Metal engine.

Run a CPU benchmark:

```sh
make macos-bench
make macos-point-bench
./macos/rck_macos point-bench --iterations 256 --min-ms 50
make macos-jacobian-point-bench
./macos/rck_macos jacobian-point-bench --iterations 256 --min-ms 50
make macos-jacobian-walk-bench
./macos/rck_macos jacobian-walk-bench --iterations 256 --min-ms 50 --jumps 16
make macos-jacobian-kangaroo-small-bench
./macos/rck_macos jacobian-kangaroo-small-bench --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096
make macos-jacobian-kangaroo-multi-small-bench
./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 4 --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096
```

`macos-bench` measures scalar `MultiplyG` throughput. `macos-point-bench` measures a serialized affine point-add walk: it starts at `2G`, repeatedly adds `G`, and validates the final point against a single `MultiplyG(n+2)` oracle. This is still CPU affine arithmetic, not the final Metal/Jacobian solver path, but it is closer to kangaroo walk cost than isolated field operations.

`macos-jacobian-point-bench` keeps the walk point in Jacobian coordinates and performs mixed Jacobian-plus-affine additions of `G`, moving the expensive field inversion out of the inner loop. The JSON includes an affine reference throughput and `speedup_vs_affine` so improvements are measured against the simpler point-add baseline.

`macos-jacobian-walk-bench` uses a deterministic jump table of affine points and applies mixed Jacobian additions selected from the current projective state. It tracks scalar distance in parallel and validates the final point against a scalar oracle. This is a walk-core benchmark, not yet a full kangaroo solver with distinguished points or collision handling.

`macos-jacobian-kangaroo-small-bench` generates one deterministic synthetic target and measures tiny single-target kangaroo solves per second with the hash-bucket DP lookup. It precomputes the deterministic jump table and range/tame-start context once per benchmark run, reuses scratch storage across measured solves, and reports `architecture=single_target`, `dp_lookup=hash`, `dp_bucket_storage=inline_first`, `affine_conversion=batch`, `jump_table=precomputed`, `scratch=reused`, `range_context=precomputed`, tame/wild state counts, and DP table size so it can be compared directly with the shared-tame multi-target benchmark.

`macos-jacobian-kangaroo-multi-small-bench` generates deterministic synthetic targets, places one solvable target at the final index, precomputes the deterministic jump table and range/tame-start context once per benchmark run, reuses scratch storage across measured solves, and measures tiny shared-tame multi-target solves per second with the hash-bucket DP lookup. The multi solver reports `affine_conversion=batch` because it batch-converts tame plus wild Jacobian states with one field inversion per loop, and the benchmark reports `dp_bucket_storage=inline_first`, `jump_table=precomputed`, `scratch=reused`, and `range_context=precomputed`. It also runs a same-parameter single-target baseline and reports `single_target_ops_per_sec`, `speedup_vs_single`, and `target_throughput_vs_single`; the last field multiplies multi solves per second by target count before comparing with the single-target baseline. Use `--target-count` to compare 1, 2, 4, 8, or larger target sets while keeping the same bounded range and jump parameters.

Run CPU secp256k1 field arithmetic checks and the multiplication benchmark:

```sh
./macos/rck_macos cpu-field-test
make macos-cpu-field-bench
./macos/rck_macos cpu-field-bench --iterations 4096 --min-ms 50
```

The CPU field path uses four little-endian 64-bit limbs and `unsigned __int128` carry arithmetic. The benchmark reports `field_mul_mod_p` throughput and an `EcInt` reference throughput for comparison. `--iterations` controls the deterministic sample set size; `--min-ms` repeats that sample set until the native measurement has run for at least that many milliseconds, which gives autoresearch less noisy timing data.

Run the Metal smoke test:

```sh
./macos/rck_macos metal-smoke
```

If no Metal device is visible in the current execution environment, the command reports a skip instead of failing. On a normal Apple Silicon runtime with device access, it compiles and runs a minimal Metal compute kernel.

Run the Metal secp256k1 field-add and field-mul checks and benchmarks:

```sh
./macos/rck_macos metal-field-test
make macos-metal-field-bench
./macos/rck_macos metal-field-mul-test
make macos-metal-field-mul-bench
make macos-metal-kernels-check
```

The field kernels use four little-endian 64-bit limbs modulo the secp256k1 prime and compare Metal output against CPU oracles. `field_mul_mod_p` uses 32-bit decomposition internally for portable 64x64 multiplication inside Metal. In restricted CI or sandboxed sessions without a visible Metal device, runtime checks report a clean skip. `macos-metal-kernels-check` compiles the extracted Metal source when the Metal Toolchain is installed; otherwise it reports a clean toolchain skip.

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
python3 autoresearch/runner.py --experiment metal_field_mul --budget-sec 5
```

Autoresearch records Metal device absence as `status=skip`, not as a crash, so the same experiment can run on both local Apple Silicon and headless CI.

If you want to generate tames for the full solver, do that on the CUDA host. With multi-target mode, existing tames must already exist; generate them separately before using `-targets`.
