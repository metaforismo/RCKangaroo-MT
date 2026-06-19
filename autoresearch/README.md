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

Results are written to:

- `autoresearch/results.tsv`
- `autoresearch/benchmarks.jsonl`

The current baseline metric is CPU `multiply_g` operations per second. Metal arithmetic and tiny-range solve metrics can be added after their correctness gates exist.
