# RCKangaroo-MT Metal Lab Notes

This file holds compact, shareable notes for the Benchforge lab. Local
Benchforge notes under `.benchforge/notes.jsonl` are useful scratchpad data, but
they are intentionally ignored by git.

## Baseline

- Baseline commit: `e41de58` (`perf: record Metal q-base shift gain`).
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
  - post-output-base local score: `50,841,692.181350 ops/sec`
  - post-output-base local run: `run_1a28f784-579d-4177-a089-db2af80d3d9e`
  - post-q-base-shift local score: `28,639,753.915254 ops/sec`
  - post-q-base-shift local run: `run_4df90d72-1f08-437d-b6d8-e5a1eef4e1e5`
  - verifier trust: `false`
- Treat these as local iteration baselines, not public proof.

## Accepted Optimization Notes

- `d8f0c79` precomputes the Metal jump-index base once per GPU thread. Paired
  autoresearch kept it with candidate median `36,123,063.713799 ops/sec`
  versus paired baseline median `29,592,623.352879 ops/sec`; distance and DP
  checksums were unchanged.
- `52c88e3` reuses the packed Jacobian input base as the output base in the
  Metal jump-table kernel. Paired autoresearch kept it with candidate median
  `32,951,131.617042 ops/sec` versus paired baseline median
  `29,806,708.480270 ops/sec`; distance and DP checksums were unchanged.
- `e41de58` makes affine jump-table base addressing explicit with
  `jump_index << 3` instead of `jump_index * 8`. Paired autoresearch kept it
  with candidate median `26,896,574.393133 ops/sec` versus paired baseline
  median `20,301,093.835039 ops/sec`; distance and DP checksums were
  unchanged.

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
