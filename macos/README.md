# macOS native tools

RCKangaroo-MT still uses NVIDIA CUDA for the full high-performance kangaroo solver, but the `macos/` folder now provides native Apple Silicon tooling for target preparation, secp256k1 correctness checks, tiny-range CPU solves, benchmarks, and Metal runtime smoke tests.

## Build and Check

```sh
make macos-check
```

This builds `macos/rck_macos`, runs host secp256k1 vector checks, validates target parsing, and runs the native CPU selftest.

Run a tiny-range CPU solve:

```sh
./macos/rck_macos solve-small --range 8 --start 0 --pubkey 025CBDF0646E5DB4EAA398F365F2EA7A0E3D419B7E0330E39CE92BDDEDCAC4F9BC
```

Run a CPU benchmark:

```sh
make macos-bench
```

Run the Metal smoke test:

```sh
./macos/rck_macos metal-smoke
```

If no Metal device is visible in the current execution environment, the command reports a skip instead of failing. On a normal Apple Silicon runtime with device access, it compiles and runs a minimal Metal compute kernel.

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
```

If you want to generate tames for the full solver, do that on the CUDA host. With multi-target mode, existing tames must already exist; generate them separately before using `-targets`.
