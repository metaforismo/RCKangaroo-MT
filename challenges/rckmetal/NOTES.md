# RCKangaroo-MT Metal Lab Notes

This file holds compact, shareable notes for the Benchforge lab. Local
Benchforge notes under `.benchforge/notes.jsonl` are useful scratchpad data, but
they are intentionally ignored by git.

## Baseline

- Baseline commit: `d8f0c79` (`perf: record Metal jump index base gain`).
- Hardware track: Apple Silicon M3 Metal, 10-core GPU, 16 GB RAM.
- Score command: `metal-jacobian-jump-walk-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 50`.
- Local Benchforge runs observed after adding the lab:
  - feature-worktree `local` score: `51,386,885.672530 ops/sec`
  - feature-worktree `accepted` score: `40,641,396.061969 ops/sec`
  - main-worktree candidate score: `31,709,050.052550 ops/sec`
  - main-worktree `accepted` score: `25,722,311.096430 ops/sec`
  - main-worktree submission: `sub_071211c2-eedb-4692-ad99-9bf0e9de876f`
  - main-worktree accepted run: `run_d53dea0b-08b6-4f5f-a1ac-ba6ecd371a23`
  - post-jump-base local score: `30,990,357.579458 ops/sec`
  - post-jump-base local run: `run_22aed968-ccae-440b-b02e-face51b800c0`
  - verifier trust: `false`
- Treat these as local iteration baselines, not public proof.

## Accepted Optimization Notes

- `d8f0c79` precomputes the Metal jump-index base once per GPU thread. Paired
  autoresearch kept it with candidate median `36,123,063.713799 ops/sec`
  versus paired baseline median `29,592,623.352879 ops/sec`; distance and DP
  checksums were unchanged.

## Current Correctness Surface

- Public score requires:
  - `correctness=true`
  - `skipped=false`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
- Verifier command also runs `make macos-check` plus a second Metal shape:
  - `--iterations 2048 --steps 7 --jumps 9 --dp-bits 3 --min-ms 20`
  - `distance_checksum=0xbab72b58ebefa9dc`
  - `dp_count=249`
  - `dp_checksum=0x4a7f2853a4a9f546`

## Handoff Rules

- Use `node ./challenges/rckmetal/bin/rckmetal.js notes add ...` for local
  scratch notes.
- Promote durable findings into this file or `docs/RESEARCH_LOG.md`.
- Do not call a result `verified`, `promoted`, or `replicated` unless a trusted
  external runner reproduces it.
