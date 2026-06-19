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

Run the Metal field-add experiment:

```sh
python3 autoresearch/runner.py --experiment metal_field_add --budget-sec 5
```

If a Metal device is not visible, the experiment records `status=skip` instead of failing. On Apple Silicon with device access, it runs the `field_add_mod_p` Metal microkernel and compares every output against the CPU oracle.

Run the CPU field multiplication experiment:

```sh
python3 autoresearch/runner.py --experiment cpu_field_mul --budget-sec 5
```

This records `macos_cpu` `field_mul_mod_p` throughput and includes `EcInt` reference throughput plus `speedup_vs_ecint` in `autoresearch/benchmarks.jsonl`.

Results are written to:

- `autoresearch/results.tsv`
- `autoresearch/benchmarks.jsonl`

The current CPU baseline metric is `multiply_g` operations per second. CPU field multiplication and Metal field addition are tracked as separate fixed-gate experiments.
