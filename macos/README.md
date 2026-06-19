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
```

Run a CPU benchmark:

```sh
make macos-bench
```

Run CPU secp256k1 field arithmetic checks and the multiplication benchmark:

```sh
./macos/rck_macos cpu-field-test
make macos-cpu-field-bench
```

The CPU field path uses four little-endian 64-bit limbs and `unsigned __int128` carry arithmetic. The benchmark reports `field_mul_mod_p` throughput and an `EcInt` reference throughput for comparison.

Run the Metal smoke test:

```sh
./macos/rck_macos metal-smoke
```

If no Metal device is visible in the current execution environment, the command reports a skip instead of failing. On a normal Apple Silicon runtime with device access, it compiles and runs a minimal Metal compute kernel.

Run the Metal secp256k1 field-add check and benchmark:

```sh
./macos/rck_macos metal-field-test
make macos-metal-field-bench
```

The field-add kernel uses four little-endian 64-bit limbs modulo the secp256k1 prime and compares Metal output against the CPU oracle. In restricted CI or sandboxed sessions without a visible Metal device, it reports a clean skip.

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
python3 autoresearch/runner.py --experiment cpu_field_mul --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_add --budget-sec 5
```

Autoresearch records Metal device absence as `status=skip`, not as a crash, so the same experiment can run on both local Apple Silicon and headless CI.

If you want to generate tames for the full solver, do that on the CUDA host. With multi-target mode, existing tames must already exist; generate them separately before using `-targets`.
