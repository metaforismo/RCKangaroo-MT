---
name: rckmetal
description: Work on the RCKangaroo-MT Metal Lab Benchforge challenge. Use when optimizing the macOS/Metal path, running rckmetal benchmarks, recording notes, packaging submissions, verifying verifier-result JSON, or maintaining leaderboard artifacts.
---

# RCKangaroo-MT Metal Lab

You are working inside a Benchforge challenge whose root is the repository root.

Objective: maximize `ops_per_sec` while preserving correctness for the Metal
Jacobian jump-table walk with projective DP candidate flags.

## Editable Paths

Only optimize paths declared in root `challenge.json`.

Do not edit:

- `.benchforge/`
- `challenge.json`
- `challenges/rckmetal/harness/`
- `tools/benchforge/`
- stored leaderboard, verifier, or submission artifacts

## Required Loop

```bash
node ./challenges/rckmetal/bin/rckmetal.js doctor --run
node ./challenges/rckmetal/bin/rckmetal.js run
node ./challenges/rckmetal/bin/rckmetal.js submit --verify --bundle-output .benchforge/latest.bundle.json --output .benchforge/verifier-result.json
node ./challenges/rckmetal/bin/rckmetal.js leaderboard
```

Before claiming an improvement, report:

- local score
- accepted verifier score
- run id
- submission id
- whether `verifier.trusted` is true
- hardware track and environment metrics

## Correctness Oracle

The public score harness requires:

- `correctness:true`
- `skipped:false`
- `distance_checksum=0xa45f471493cace2f`
- `dp_count=1000`
- `dp_checksum=0x30a7914972cba014`

The verifier also runs `make macos-check` and a second Metal benchmark shape.

## Trust Language

Never call a local or accepted score public proof. Use `verified`, `promoted`,
or `replicated` only when a trusted external runner reproduces the result.

Record failed ideas with:

```bash
node ./challenges/rckmetal/bin/rckmetal.js notes add "Tried <approach>; rejected because <reason>."
```
