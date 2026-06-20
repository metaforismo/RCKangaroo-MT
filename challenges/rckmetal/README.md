# RCKangaroo-MT Metal Lab

This is a Benchforge challenge pack for the macOS/Metal optimization track.

The challenge root is the repository root, not this directory. That is
intentional: Benchforge submission verification copies the challenge root into a
temporary clean directory, so the root must include the real solver sources.

## Goal

Maximize `ops_per_sec` for:

```bash
./macos/rck_macos metal-jacobian-jump-walk-bench \
  --iterations 16384 \
  --steps 8 \
  --jumps 16 \
  --dp-bits 4 \
  --min-ms 50
```

The score harness runs three samples and records the median throughput. A run is
valid only when the Metal benchmark reports `correctness:true`, `skipped:false`,
the expected distance checksum, and the expected projective DP checksum.

## Commands

Initialize Benchforge if needed:

```bash
git submodule update --init tools/benchforge
```

Run the local loop:

```bash
make benchforge-rckmetal-doctor
make benchforge-rckmetal-run
make benchforge-rckmetal-submit
make benchforge-rckmetal-leaderboard
make benchforge-rckmetal-report
```

Equivalent direct CLI:

```bash
node ./challenges/rckmetal/bin/rckmetal.js doctor --run
node ./challenges/rckmetal/bin/rckmetal.js run
node ./challenges/rckmetal/bin/rckmetal.js submit --verify --bundle-output .benchforge/latest.bundle.json --output .benchforge/verifier-result.json
node ./challenges/rckmetal/bin/rckmetal.js leaderboard
node ./challenges/rckmetal/bin/rckmetal.js export-site
```

The static report is written to:

```text
.benchforge/site/index.html
.benchforge/site/leaderboard.json
```

## Trust

Local runs are useful for iteration, not public proof.

Benchforge status names are used literally:

- `local`: measured on the contributor machine.
- `candidate`: packaged as a replayable `benchforge.submission.v1` bundle.
- `accepted`: replayed by the local verifier.
- `verified`, `promoted`, `replicated`: reserved for trusted external runners.

Promotion should require an independent verifier on a declared hardware track.
For this repository the first track is Apple Silicon M3 Metal.

## Notes

Use notes to preserve lessons:

```bash
node ./challenges/rckmetal/bin/rckmetal.js notes add "Tried <idea>; result <summary>."
node ./challenges/rckmetal/bin/rckmetal.js notes search "Metal"
```

Keep detailed accepted/rejected optimization history in `docs/RESEARCH_LOG.md`.
Keep raw metric rows in `autoresearch/results.tsv` and
`autoresearch/benchmarks.jsonl`.
