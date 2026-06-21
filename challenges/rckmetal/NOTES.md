# RCKangaroo-MT Metal Lab Notes

This file holds compact, shareable notes for the Benchforge lab. Local
Benchforge notes under `.benchforge/notes.jsonl` are useful scratchpad data, but
they are intentionally ignored by git.

## Baseline

- Baseline commit: `0db51db` (`perf: record implicit Metal index promotion gain`).
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
  - post-steps8-kernel local score: `30,268,511.454293 ops/sec`
  - post-steps8-kernel local run: `run_1c90c406-7301-469b-a144-dd203ea596fb`
  - post-constant-jump-tables local score: `29,124,706.165467 ops/sec`
  - post-constant-jump-tables local run: `run_98e0ea38-a9a0-44eb-9fc4-600aba32883f`
  - post-constant-jump-tables submission:
    `sub_d9c6e3d1-0fac-4bcb-976f-f6666d6c0ae1`
  - post-constant-jump-tables candidate score: `27,172,647.361592 ops/sec`
  - post-constant-jump-tables accepted run:
    `run_fc9f395a-c183-4244-b226-41fbeb5ef80b`
  - post-constant-jump-tables accepted score: `54,784,037.786312 ops/sec`
  - post-constant-jump-tables receipt hash:
    `7a08ba74222ac812ea60b6304bda7c1c2d6dae26293a67e9899708f46ce24901`
  - post-constant-inputs local score: `33,031,083.688596 ops/sec`
  - post-constant-inputs local run: `run_8870aa52-bfec-40c7-a7df-3b9c43d2b4cb`
  - post-constant-indices local score: `32,108,338.507637 ops/sec`
  - post-constant-indices local run: `run_75dcc47e-ccf9-438f-8e1b-1e803adc04cc`
  - post-point-base-shift local score: `28,672,074.856923 ops/sec`
  - post-point-base-shift local run: `run_c5a5a65e-57cf-415e-8109-d73e56025160`
  - post-packed-indices local score: `32,162,529.860699 ops/sec`
  - post-packed-indices local run: `run_e99acb33-7e12-4a6c-9ddc-053bf0cf8a7c`
  - post-implicit-index-promotion local score: `25,075,671.624407 ops/sec`
  - post-implicit-index-promotion local run: `run_8fa7d17c-c78f-4dc6-a97a-4031ded46410`
  - post-packed-dp-flags local score: `44,407,980.061147 ops/sec`
  - post-packed-dp-flags local run: `run_a17dda9a-908e-419d-b7cd-aa6dd1aa5b80`
  - post-packed-dp-flags submission:
    `sub_859a9153-49dd-45a6-8ce2-1d57d94917a1`
  - post-packed-dp-flags candidate score: `29,644,751.288810 ops/sec`
  - post-packed-dp-flags accepted run:
    `run_bbdd8e57-765e-4e33-8eb7-22d8368abaf2`
  - post-packed-dp-flags accepted score: `46,030,890.793385 ops/sec`
  - post-packed-dp-flags receipt hash:
    `c82e916e46c716176f8249efd94d588fc688e3e7140dd1134d6af950990b216f`
  - post-packed-output-infinity local score: `30,850,023.207186 ops/sec`
  - post-packed-output-infinity local run: `run_f12c7906-0ac7-438d-99a5-457667f6a481`
  - post-packed-output-infinity submission:
    `sub_ad6ff479-06af-443a-9e56-8e6bedc8df35`
  - post-packed-output-infinity candidate score: `33,331,836.865438 ops/sec`
  - post-packed-output-infinity accepted run:
    `run_71aa84e7-10d5-46dc-b004-cda5c6e2bbd7`
  - post-packed-output-infinity accepted score: `30,688,533.740618 ops/sec`
  - post-packed-output-infinity receipt hash:
    `2cd2841869233b6c7c63b3222980494ee548dbd85bf3c3f12539cf1d89aabd3c`
  - post-packed-combined-flags local score: `28,442,924.884774 ops/sec`
  - post-packed-combined-flags local run: `run_d86d82b9-3098-45ec-ad65-fc0159ad121c`
  - post-packed-combined-flags submission:
    `sub_817d243e-89a6-4bf4-b441-b31aaba2de8c`
  - post-packed-combined-flags candidate score: `33,013,511.325726 ops/sec`
  - post-packed-combined-flags accepted run:
    `run_98dfbad3-63fb-4970-b293-fa3f3449e6e3`
  - post-packed-combined-flags accepted score: `25,244,587.273860 ops/sec`
  - post-packed-combined-flags receipt hash:
    `ae763283a4d56d46d814c157dfe7eee632e9b84a2d9b1b05425adf8837f926c5`
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
- `7acdc28` adds a Metal jump-table kernel specialized for
  `steps_per_sample == 8`, while preserving the generic fallback for all other
  step counts. Paired autoresearch kept it with candidate median
  `38,243,083.846592 ops/sec` versus paired baseline median
  `34,828,506.038031 ops/sec`; distance and DP checksums were unchanged.
- `ba91503` moves the compact read-only affine jump table and distance table to
  Metal `constant` address space while leaving per-sample jump indices in
  `device const`. Paired autoresearch kept it with candidate median
  `36,426,708.294932 ops/sec` versus paired baseline median
  `30,769,379.445330 ops/sec`; distance and DP checksums were unchanged.
- `68b8e3b` moves the initial packed Jacobian state and infinity flags to Metal
  `constant` address space as read-only inputs. Paired autoresearch kept it with
  candidate median `38,249,530.679262 ops/sec` versus paired baseline median
  `23,474,473.066685 ops/sec`; distance and DP checksums were unchanged.
- `cbfff2e` moves per-sample jump indices to Metal `constant` address space.
  Paired autoresearch kept it with candidate median `25,302,152.157760 ops/sec`
  versus paired baseline median `24,651,050.122097 ops/sec`; distance and DP
  checksums were unchanged. This was a small-margin keep, so treat it as a
  modest local gain rather than a broad architectural rule.
- `c876663` makes the 12-limb packed Jacobian point base explicit as
  `(id << 3) + (id << 2)` in the two jump-walk kernels. Paired autoresearch kept
  it with candidate median `40,420,143.199132 ops/sec` versus paired baseline
  median `25,079,930.894718 ops/sec`; distance and DP checksums were unchanged.
- `b7122fb` packs the Metal jump-index buffer to `uint8_t` while keeping the CPU
  oracle sequence as `uint32_t`. Paired autoresearch kept it with candidate
  median `43,384,425.365437 ops/sec` versus paired baseline median
  `42,198,113.596848 ops/sec`; distance and DP checksums were unchanged.
- `505a654` relies on implicit Metal promotion from packed `uchar` jump indices
  to `uint` destination variables instead of an explicit cast. Paired
  autoresearch kept it with candidate median `32,889,067.186241 ops/sec` versus
  paired baseline median `25,877,502.674679 ops/sec`; distance and DP checksums
  were unchanged.
- `7feecd6` packs the Metal DP flag output buffer to `uint8_t` while expanding
  back to `uint32_t` on the host before oracle comparison. Paired autoresearch
  kept it with candidate median `37,830,025.643327 ops/sec` versus paired
  baseline median `28,696,541.249467 ops/sec`; distance and DP checksums were
  unchanged. The local-public verifier accepted run
  `run_bbdd8e57-765e-4e33-8eb7-22d8368abaf2` at
  `46,030,890.793385 ops/sec` with `trusted=false`.
- `e7b28c1` packs only the jump-walk Metal output infinity flags to `uint8_t`
  while keeping input infinity flags as `uint32_t`. Paired autoresearch kept it
  with candidate median `33,349,832.725909 ops/sec` versus paired baseline
  median `25,793,902.178919 ops/sec`; distance and DP checksums were unchanged.
  The local-public verifier accepted run
  `run_71aa84e7-10d5-46dc-b004-cda5c6e2bbd7` at
  `30,688,533.740618 ops/sec` with `trusted=false`.
- `f266242` combines output infinity and DP candidate flags into one Metal
  `uint8_t` bitfield, decoded back into two `uint32_t` host vectors before the
  oracle. Paired autoresearch kept it with candidate median
  `38,176,865.912089 ops/sec` versus paired baseline median
  `34,031,160.092524 ops/sec`; distance and DP checksums were unchanged. The
  local-public verifier accepted run
  `run_98dfbad3-63fb-4970-b293-fa3f3449e6e3` at
  `25,244,587.273860 ops/sec` with `trusted=false`, so treat the local
  leaderboard effect as noisy.

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
