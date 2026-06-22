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
  - post-threadgroup-dispatch local score: `32,143,846.853718 ops/sec`
  - post-threadgroup-dispatch local run:
    `run_746218ad-dd52-4184-b5d3-75ea50e62374`
  - post-threadgroup-dispatch submission:
    `sub_f1185649-8a26-491b-a047-ec0604c7afbd`
  - post-threadgroup-dispatch candidate score: `30,203,700.190622 ops/sec`
  - post-threadgroup-dispatch accepted run:
    `run_0e8d35ad-7f60-4cf7-a9b6-87cf9a5f7b0a`
  - post-threadgroup-dispatch accepted score: `33,847,318.071380 ops/sec`
  - post-threadgroup-dispatch receipt hash:
    `5e899e1312baca831593e1f54f9873bd35d56a0d669b0d2794a8000ee411d1db`
  - post-steps8-dp4 local score: `56,820,932.004814 ops/sec`
  - post-steps8-dp4 local run:
    `run_e9c0a155-6944-486b-9d5f-21685f819024`
  - post-steps8-dp4 submission:
    `sub_3f950cfc-630e-4eef-a97f-bd12c1aa58a5`
  - post-steps8-dp4 candidate score: `20,963,326.693395 ops/sec`
  - post-steps8-dp4 accepted run:
    `run_e62fa172-6ae2-4fa4-acdf-9e108d0f274c`
  - post-steps8-dp4 accepted score: `46,317,921.229795 ops/sec`
  - post-steps8-dp4 receipt hash:
    `f1cccd47b625caecc8b16c2cdac1204f935ca5382513c2e4ac12571abac49a82`
  - post-dp4-packed-input-infinity local score: `18,060,317.733834 ops/sec`
  - post-dp4-packed-input-infinity local run:
    `run_171b8a17-908c-4e9d-b673-f7df024bfe4f`
  - post-dp4-packed-input-infinity submission:
    `sub_1cc10e05-76a9-4108-994d-949042388cfc`
  - post-dp4-packed-input-infinity candidate score:
    `41,426,588.802440 ops/sec`
  - post-dp4-packed-input-infinity accepted run:
    `run_64462ed9-026e-4823-a8f7-9c1041946409`
  - post-dp4-packed-input-infinity accepted score:
    `32,680,850.854894 ops/sec`
  - post-dp4-packed-input-infinity receipt hash:
    `2b9a4a74a2d58cf3013bcf90af215088f8c6cdf4f64371888acd4491b4d03942`
  - verifier trust: `false`
  - post-dp4-q-struct-row local score: `23,466,689.498479 ops/sec`
  - post-dp4-q-struct-row local run:
    `run_244bebf3-88f3-4b86-ac20-084f3a6c9645`
  - post-dp4-q-struct-row submission:
    `sub_1f7c17e0-e64d-4615-a3a8-d3da2bb695e2`
  - post-dp4-q-struct-row candidate score:
    `54,973,825.283380 ops/sec`
  - post-dp4-q-struct-row accepted run:
    `run_24328eb8-3d5b-47b4-984a-4fa1b5892cc4`
  - post-dp4-q-struct-row accepted score:
    `25,303,719.636362 ops/sec`
  - post-dp4-q-struct-row receipt hash:
    `7eb945dd814a1040bfd4124247a831c62e9cfd17de6f80208aee75b37c0a40a5`
  - post-dp4-q-struct-row verifier trust: `false`
  - post-dp4-q-struct-row main-promotion local score:
    `20,169,076.743132 ops/sec`
  - post-dp4-q-struct-row main-promotion local run:
    `run_fbe39459-05d1-4d79-870f-f15d2ec56fc4`
  - post-dp4-q-struct-row main-promotion submission:
    `sub_594c881c-bfc1-46e2-a715-85eab35f40fe`
  - post-dp4-q-struct-row main-promotion candidate score:
    `33,564,016.478581 ops/sec`
  - post-dp4-q-struct-row main-promotion accepted run:
    `run_03374691-b656-4c42-a5b4-7447490b9786`
  - post-dp4-q-struct-row main-promotion accepted score:
    `29,436,926.035583 ops/sec`
  - post-dp4-q-struct-row main-promotion receipt hash:
    `187438c75b6b9bb8266be499f1e552922a71723eda995c116f8c99ecb2e255fe`
  - post-dp4-q-struct-row main-promotion verifier trust: `false`
- Treat these as local iteration baselines, not public proof.

## Accepted Optimization Notes

- `macos-metal-dynamic-dp8-stream-local-jump-row` makes the accepted DP8 sparse
  stream kernel load `q_xy[jump_index]` once into a local `AffineJumpValue`
  before choosing the infinity or finite mixed-add path. Paired autoresearch
  kept it with candidate median `62,611,858.275279 ops/sec` versus paired
  baseline median `56,207,874.481378 ops/sec`; `emitted_records=61`,
  `dp_checksum=0xab1c2cd29cd70a84`, and
  `dp_distance_checksum=0x822e141de4770a0b` were unchanged.
- `macos-metal-dynamic-dp8-stream-no-overflow-branch` removes the in-kernel
  `slot < dp_capacity` / `out_overflow` branch from the accepted DP8 sparse
  stream specialization. The host still allocates capacity equal to sample
  count and still rejects impossible `emitted_raw > dp_capacity`, while the
  kernel relies on the one-record-per-sample invariant. Paired autoresearch
  kept it with candidate median `55,340,023.527875 ops/sec` versus paired
  baseline median `35,628,876.688184 ops/sec`; `paired_speedup=1.553235`,
  `emitted_records=61`, `dp_checksum=0xab1c2cd29cd70a84`, and
  `dp_distance_checksum=0x822e141de4770a0b` were unchanged.
- `macos-metal-dynamic-dp8-stream-no-steps-arg` removes the unused
  `steps [[buffer(7)]]` argument and `(void)steps` marker from the fixed
  `steps=8` DP8 sparse stream specialization. The host still binds the shared
  steps buffer for the other stream kernels; the DP8 function simply no longer
  consumes it. A two-run paired confirmation kept the candidate:
  `45,448,401.334809` versus `39,873,314.502482` steps/sec
  (`paired_speedup=1.139820`) and `42,203,534.028814` versus
  `37,060,740.353657` (`paired_speedup=1.138767`). The DP8 oracle stayed
  unchanged.
- `macos-metal-dynamic-dp4-stream-local-jump-row` applies the same explicit
  affine row reuse to the DP4 sparse stream kernel. Paired autoresearch kept it
  with candidate median `65,061,282.305496 ops/sec` versus paired baseline
  median `52,181,168.524837 ops/sec`; `emitted_records=1017`,
  `dp_checksum=0xbfd3b2319760e774`, and
  `dp_distance_checksum=0x19e43ca50eec2a74` were unchanged.
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
- `4d1cc10` dispatches the Metal jump-walk grid with explicit
  `dispatchThreadgroups` instead of `dispatchThreads`, using a ceiling
  `threadgroup_count` and the existing kernel-side `id >= count` guard. Paired
  autoresearch kept it with candidate median `37,756,893.905525 ops/sec`
  versus paired baseline median `25,763,516.307986 ops/sec`; distance and DP
  checksums were unchanged. A `sample_count=9` micro-benchmark also returned
  `correctness=true`, covering non-multiple grid sizes. The local-public
  verifier accepted run `run_0e8d35ad-7f60-4cf7-a9b6-87cf9a5f7b0a` at
  `33,847,318.071380 ops/sec` with `trusted=false`.
- `604dd55` adds a steps8 + `dp_bits=4` Metal kernel that hardcodes the public
  DP mask test while leaving all other shapes on the previous fallback kernels.
  Paired autoresearch kept it twice: first candidate median
  `42,692,418.310915 ops/sec` versus baseline `41,388,708.608987 ops/sec`,
  then confirmation median `46,781,458.735324 ops/sec` versus baseline
  `45,497,141.628023 ops/sec`; distance and DP checksums were unchanged. The
  local-public verifier accepted run `run_e62fa172-6ae2-4fa4-acdf-9e108d0f274c`
  at `46,317,921.229795 ops/sec` with `trusted=false`.
- `a4939c6` splits the Metal mixed-add helper into a finite-input hot path and
  a generic infinity wrapper, then uses the finite path only in the public
  steps8 + `dp_bits=4` kernel with an explicit `if (inf)` fallback. Paired
  autoresearch kept it twice: first candidate median
  `35,262,056.952682 ops/sec` versus baseline `30,045,324.607249 ops/sec`,
  then confirmation median `54,586,707.150623 ops/sec` versus baseline
  `47,025,523.463550 ops/sec`; public and second-shape checksums were
  unchanged. The local-public verifier accepted
  `sub_75c994e5-e6d5-4b4d-a1d3-fdd377b52dfc` as
  `run_781dfd20-c53c-42f3-8fd6-3262ca9b520a` at
  `54,982,200.626369 ops/sec`, receipt
  `691f72beed81ae9327ed39d656e0e3a82c78948469fd94d277fe5d17a30f1983`,
  `trusted=false`. This accepted run is now the strongest local-public
  verified baseline; the only higher leaderboard entry is an older local-only
  run.
- `3a79ce6` changes only the public steps8 + `dp_bits=4` kernel's accumulator
  infinity state from `uint` to `bool`, leaving fallback kernels and packed
  output flags unchanged. Paired autoresearch kept it twice: first candidate
  median `49,171,211.386386 ops/sec` versus baseline
  `38,955,739.382442 ops/sec`, then confirmation median
  `46,633,123.492816 ops/sec` versus baseline `41,583,067.031963 ops/sec`;
  public and second-shape checksums were unchanged. The local-public verifier
  accepted `sub_5ec7721c-abb8-4c18-a0f7-c5a2a1ad47b4` as
  `run_7f39c568-be4a-4e9e-9acd-a003112c79b1` at
  `51,293,294.688826 ops/sec`, receipt
  `3a06339d0adfef0a2da552afae54e5a0706539201350089eb113895536794d2f`,
  `trusted=false`.
- `b8e1120` assigns the dp4 bool infinity state directly from `p_infinity[id]`
  and `out.inf`, removing the `!= 0` comparisons while leaving fallback kernels
  and packed output flags unchanged. Paired autoresearch kept it twice: first
  candidate median `34,425,602.601131 ops/sec` versus baseline
  `22,144,004.281751 ops/sec`, then confirmation median
  `29,895,632.602187 ops/sec` versus baseline `25,779,267.617206 ops/sec`;
  public and second-shape checksums were unchanged. The local-public verifier
  accepted `sub_c2a9e691-40cd-4233-954f-6414743d46ba` as
  `run_43524297-43bd-4606-8686-2807aaa1d3f3` at
  `25,910,107.039113 ops/sec`, receipt
  `f275a21f5df06fe288b6f527b7206a2b0a09036c3004e5af4325e001bb86a7cf`,
  `trusted=false`; this local-public run was noisy/lower than earlier accepted
  baselines, so keep paired autoresearch as the promotion signal.
- `21d2cb4` schedules the dp4 q-table base calculation before distance
  accumulation while leaving arithmetic and outputs unchanged. Paired
  autoresearch kept it twice: first candidate median
  `38,940,533.391902 ops/sec` versus baseline `35,722,986.288468 ops/sec`,
  then confirmation median `38,149,612.617702 ops/sec` versus baseline
  `32,974,113.574544 ops/sec`; public and second-shape checksums were
  unchanged. The local-public verifier accepted
  `sub_ff829389-58e9-4493-af15-ed00ac22a0ab` as
  `run_81f56a78-8985-4261-9a14-4c198053c97c` at
  `51,884,059.915813 ops/sec`, receipt
  `e8065d2aeb3548d29c8a133fb777b4e6be2ee8d751f4d65ae874cbbc9498b112`,
  `trusted=false`; it ranked fifth on the local leaderboard at measurement
  time.
- `a963a4d` packs the public steps8 + `dp_bits=4` input infinity buffer to
  one byte per sample while leaving generic/verifier fallback shapes on the
  existing `uint32_t` input buffer. This is narrower than the older rejected
  generic `macos-metal-u8-infinity` experiment. Stable paired autoresearch kept
  it across three confirmations: `1.190133x`, `1.081899x`, `1.432397x`;
  public checksum and DP counts were unchanged. The local-public verifier
  accepted `sub_1cc10e05-76a9-4108-994d-949042388cfc` as
  `run_64462ed9-026e-4823-a8f7-9c1041946409` at `32,680,850.854894 ops/sec`,
  receipt `2b9a4a74a2d58cf3013bcf90af215088f8c6cdf4f64371888acd4491b4d03942`,
  `trusted=false`.
- `3311412` views the public DP4 affine jump table as binary-compatible
  `AffineJumpValue` rows instead of scalar `q_xy[q_base + limb]` loads, while
  keeping the host buffer layout and generic/verifier fallback scalar indexing
  unchanged. Stable paired autoresearch kept it across three confirmations:
  `1.184193x`, `2.200985x`, `1.045283x`; public checksum and DP counts were
  unchanged. The local-public verifier accepted
  `sub_1f7c17e0-e64d-4615-a3a8-d3da2bb695e2` as
  `run_24328eb8-3d5b-47b4-984a-4fa1b5892cc4` at `25,303,719.636362 ops/sec`,
  receipt `7eb945dd814a1040bfd4124247a831c62e9cfd17de6f80208aee75b37c0a40a5`,
  `trusted=false`. The accepted verifier score was noisy/lower than older
  accepted local-public runs; judge the change by paired autoresearch plus
  unchanged public oracle fields.

## Rejected Retest Notes

- `macos-metal-dp4-affine-pair2` precomputed all 16x16 affine pair sums and
  tried to replace eight public DP4 mixed-adds with four composite mixed-adds.
  It is not a valid optimization for this lab oracle: affine point equivalence
  is insufficient because correctness compares raw Jacobian `x/y/z`, and DP is
  defined on projective `x[0]`. The target bench returned `correctness=false`
  with vector-0 Jacobian mismatch and zero checksum fields. Keep exact
  step-by-step Jacobian semantics for the Metal DP4 path.
- `macos-metal-dp4-pair-distance` kept the same eight DP4 mixed-adds but used
  a 16x16 table for pairwise scalar-distance accumulation. Oracle fields stayed
  intact, but paired confirmation discarded it: `0.850786x`, `1.047350x`,
  `1.956234x`. Treat the last run as noise; keep per-step distance loads.
- `macos-metal-dp4-z1-first-step` added a raw-compatible first-step helper for
  initial `Z=1`, skipping `Z^2`/`Z^3` only when the loaded Jacobian state is
  exactly affine. Source gates, `make macos-check`, and the stable DP oracle
  passed, but paired confirmation discarded it: `1.723581x`, `1.342978x`,
  `0.891806x`. Keep the uniform DP4 loop; the z=1 branch/code-size effect is
  too unstable on M3.
- `macos-metal-dp4-xyzz-state` kept `Z^2` and `Z^3` as live DP4 state to avoid
  per-step recomputation in `U2/S2` while preserving byte-for-byte raw
  Jacobian output. Source gates, `make macos-check`, and the stable DP oracle
  passed, but paired confirmation discarded it: `1.024585x`, `0.824733x`,
  `0.548792x`. Keep the compact Jacobian state; the extra live limbs are too
  expensive for this M3 kernel shape.
- `macos-metal-dp4-index-word` packed each sample's eight DP4 jump-index bytes
  into one `uint64_t` and unpacked with shifts in the Metal loop. Correctness,
  source gates, and `make macos-check` passed, but direct public-shape runs
  regressed to `1,234,220.937488` and `15,541,034.229553 ops/sec`. Keep the
  byte-per-step constant-buffer loads; the packed-word extraction shape is much
  slower on M3.
- `macos-metal-bool-jacobian-inf` changed the internal `JacobianValue.inf`
  result field to `bool`, leaving external buffers unchanged. Correctness,
  source gates, and `make macos-check` passed, but paired confirmation
  discarded it: `0.756774x`, `1.006789x`, `1.413763x`. Keep the `uint` result
  field; the bool-shaped helper result has too much low-tail variance on M3.
- `8b3d413` added an explicit `uchar` cast around the public DP4 packed
  flag-store expression. Correctness and the stable DP oracle stayed intact,
  but paired confirmation discarded it: `1.020047x`, `1.099344x`,
  `0.894179x`. Keep the implicit narrowing store.
- `03ed392` narrowed the public DP4 distance accumulator from `ulong` to
  `uint` with a host safety guard and cast back to `ulong` on output.
  Correctness and the stable DP oracle stayed intact, but paired confirmation
  discarded it: `0.950121x`, `1.200329x`, `0.991690x`. Keep the `ulong`
  accumulator in the promoted DP4 kernel.
- `d04021e` changed the public DP4 local infinity state from `bool` to
  `uchar` after packing the input infinity buffer. Correctness and the stable
  DP oracle stayed intact, but paired confirmation discarded it: `0.858733x`,
  `0.633437x`, `0.627012x`. Keep the promoted `bool` local state fed by the
  packed `uchar` input.
- `56302e5` retried manual unrolling of all eight fixed steps in
  `jacobian_affine_walk_jump_table_steps8` after the threadgroup-dispatch win
  and after tightening the primary Metal DP gate to five samples. Correctness
  stayed intact (`distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`), but paired autoresearch still discarded
  it: candidate median `30,216,489.417128 ops/sec` versus baseline
  `30,308,267.513455 ops/sec`, `paired_speedup=0.996972`. Keep the compact
  fixed-loop steps8 kernel.
- `5a8b985` replaced the final jump-walk flag ternaries with explicit
  branchless `is_inf` and `dp_flag` arithmetic. The public oracle fields stayed
  intact, but paired autoresearch discarded it: candidate median
  `26,399,879.312075 ops/sec` versus baseline `36,600,758.926891 ops/sec`,
  `paired_speedup=0.721293`. Keep the compact ternary flag store.
- `d735b6d` created jump-walk buffers with shared storage plus
  `MTLResourceHazardTrackingModeUntracked`. Correctness stayed intact, but
  paired autoresearch discarded it: candidate median `20,388,792.013228
  ops/sec` versus baseline `22,815,429.774553 ops/sec`,
  `paired_speedup=0.893640`. Keep the default tracked shared buffers.
- `12261fd` added a guarded steps8 + `dp_bits=4` first-infinity Metal kernel
  that avoids reading `p_infinity[id]` when only point 0 starts at infinity.
  Correctness stayed intact, but the result did not confirm: first paired run
  kept it at `43,313,091.164017 ops/sec` versus baseline
  `34,911,331.312607 ops/sec`, while the immediate confirmation discarded it at
  `43,163,082.615191 ops/sec` versus baseline `43,781,915.905634 ops/sec`,
  `paired_speedup=0.985866`. Keep the existing dp4 kernel as the base.
- `889a959` cached the 16-entry affine jump table and distances in threadgroup
  memory for the public steps8 + `dp_bits=4` kernel. Correctness and fallback
  shapes stayed intact, but paired autoresearch discarded it: candidate median
  `39,023,071.164210 ops/sec` versus baseline `42,888,813.210105 ops/sec`,
  `paired_speedup=0.909866`. Keep the constant-buffer table; threadgroup preload
  and barrier overhead were not worth it on M3.
- `983c7c3` removed the dead `steps` argument from the public dp4 Metal kernel.
  Correctness stayed intact, but paired autoresearch discarded it: candidate
  median `28,385,107.764488 ops/sec` versus baseline
  `35,725,191.654110 ops/sec`, `paired_speedup=0.794540`. Keep the current
  dp4 kernel signature.
- `b6eec70` replaced the final reduction loop with a single conditional
  subtract. Field microbenchmarks improved (`square` `1.345393x`, `mul`
  `1.194649x`), but the DP target rejected it twice: first `0.685951x`, then
  neutral `1.001334x` below threshold. Keep the looped reducer for the target;
  the microbench win does not translate reliably into the large Jacobian kernel.
- `108737d` capped the public dp4 Metal kernel with
  `max_total_threads_per_threadgroup(256)`. Runtime reported the lower max, but
  paired autoresearch discarded it: candidate median `35,188,997.363215
  ops/sec` versus baseline `41,028,548.928926 ops/sec`,
  `paired_speedup=0.857671`. Keep the uncapped kernel.
- `7c1416e` used three `ulong4` vector stores for the dp4 kernel's final
  Jacobian output. Correctness stayed intact, but paired autoresearch discarded
  it: candidate median `42,347,381.165201 ops/sec` versus baseline
  `45,468,279.360450 ops/sec`, `paired_speedup=0.931361`. Keep scalar stores.
- `2a0d783` loaded dp4 affine jump-table limbs into `qx*`/`qy*` locals before
  the infinity branch so both branches reuse the same operands. Correctness
  stayed intact, but paired autoresearch discarded it: candidate median
  `51,269,848.158566 ops/sec` versus baseline `53,225,235.044224 ops/sec`,
  `paired_speedup=0.963262`. Keep direct `q_xy[q_base + n]` operands in the
  promoted finite-hot-path dp4 kernel.
- `2d1f373` inlined the dp4 infinity fallback as direct affine assignment
  (`x/y=q`, `z=1`, `inf=0`) instead of calling the generic wrapper. Correctness
  stayed intact, but paired autoresearch discarded it: candidate median
  `53,801,243.066193 ops/sec` versus baseline `57,431,762.259068 ops/sec`,
  `paired_speedup=0.936786`. Keep the promoted generic-wrapper fallback shape.
- `f7cda6f` simplified the dp4 final packed-flag store to
  `inf ? 1 : (dp ? 2 : 0)`. Correctness stayed intact, but paired autoresearch
  discarded it: candidate median `28,602,135.384033 ops/sec` versus baseline
  `36,034,276.125311 ops/sec`, `paired_speedup=0.793748`. Keep the promoted
  OR/`!inf` flag expression with bool infinity state.
- `186669e` forced `__attribute__((always_inline))` on the Metal mixed-add
  wrapper and finite helper. It compiled and preserved correctness, but paired
  autoresearch discarded it: candidate median `29,906,975.938509 ops/sec`
  versus baseline `36,536,871.605632 ops/sec`, `paired_speedup=0.818542`.
  Keep plain `static inline` helpers.
- `9c751f6` reordered the public dp4 branch as `if (!inf)` so the finite hot
  path appeared before the generic infinity fallback. Correctness stayed
  intact, but paired autoresearch discarded it: candidate median
  `27,998,203.739620 ops/sec` versus baseline `28,161,283.758521 ops/sec`,
  `paired_speedup=0.994209`. Keep the promoted `b8e1120` fallback-first branch
  shape.
- `da3086d` narrowed the public dp4 loop's `jump_index` local to `uchar` and
  cast it back to `uint` for distance and q-table indexing. Correctness stayed
  intact, but the signal was unstable: first paired run kept it at
  `38,098,881.915015 ops/sec` versus baseline `27,330,823.387611 ops/sec`
  (`1.393990x`), while confirmation discarded it at `30,444,886.448562
  ops/sec` versus baseline `33,237,046.959255 ops/sec` (`0.915993x`). Do not
  promote without stronger repeated evidence; keep the `uint jump_index`
  baseline.
- `6fe1f43` changed the public dp4 loop condition from `step < 8` to
  `step != 8`. Correctness stayed intact, but paired autoresearch discarded it:
  candidate median `31,734,147.843923 ops/sec` versus baseline
  `36,197,526.932618 ops/sec`, `paired_speedup=0.876694`. Keep the promoted
  `< 8` loop spelling.
- `8c25d98` marked the public dp4 `jump_index` and `q_base` locals as
  `const uint`. Correctness stayed intact, but paired autoresearch discarded it:
  candidate median `43,098,694.269856 ops/sec` versus baseline
  `49,646,792.344200 ops/sec`, `paired_speedup=0.868106`. Two earlier
  sandboxed runner attempts were `skip` because the sandbox could not see
  Metal; keep the elevated run as the performance signal and keep mutable
  `uint` locals.
- `04d9064` moved the public dp4 distance accumulation to after the mixed-add
  branch's `inf = out.inf` update. Correctness stayed intact, but paired
  autoresearch discarded it: candidate median `35,979,020.969423 ops/sec`
  versus baseline `38,080,155.698501 ops/sec`,
  `paired_speedup=0.944823`. Keep the promoted q-base-first baseline with the
  distance load/add before the mixed-add block.
- `b93fb81` declared the dp4 `JacobianValue out` inside each branch and
  duplicated the post-add state update. Correctness stayed intact, but three
  paired autoresearch runs were unstable: `1.651344x keep`, `1.033844x keep`,
  then `0.518840x discard`. Do not promote this shape; keep the shared
  post-branch output update.
- `074d8a9` derived the dp4 point base from the already-needed
  `jump_base = id << 3`. Correctness stayed intact, but paired autoresearch
  discarded it: candidate median `27,479,586.125938 ops/sec` versus baseline
  `39,064,201.289996 ops/sec`, `paired_speedup=0.703447`. Keep the promoted
  separate `p_base` expression and later `jump_base` declaration.
- `cbd1493` defaulted only the public dp4 score path to threadgroup limit 512.
  Correctness stayed intact and explicit `--tg-limit 256` still worked, but
  paired autoresearch discarded it: candidate median
  `30,497,177.022142 ops/sec` versus baseline `42,867,189.634848 ops/sec`,
  `paired_speedup=0.711434`. Keep default 256 for the score path.
- `69a724c` added an exact-count dp4 kernel without the `id >= count` guard and
  selected it only when the sample count was divisible by the effective
  threadgroup size. Correctness stayed intact, including a `sample_count=9`
  fallback run, but `--confirm-runs 3` produced `confirmation_status=discard`:
  raw keep `1.230942x`, discard `0.900865x`, raw keep `1.046996x`. Keep the
  guarded dp4 kernel.
- `macos-metal-dp4-first-generic-rest-finite` split the public dp4 kernel into
  a generic first step and finite-only tail steps. The public checksum oracle
  passed, but a direct Metal edge oracle that forces the first jump to infinity
  failed: the candidate stayed at infinity after the next affine jump while the
  CPU oracle returned a finite point. Keep the tail `if (inf)` guard unless a
  new formulation passes this infinity-tail selftest.
- `4013057` specialized public `steps=8`, `dp_bits=4`, `jump_count=16` by
  staging the jump table and distances in `threadgroup` memory. Correctness
  stayed intact, including the infinity-tail selftest, but paired autoresearch
  discarded it: candidate median `30,095,459.840316 ops/sec` versus baseline
  `37,579,388.005384 ops/sec`, `paired_speedup=0.800850`. Keep constant-buffer
  table reads for the dp4 score path.
- `33a9a83` inlined the dp4 infinity fallback as direct affine assignment
  (`out = q, z = 1`) instead of calling the generic wrapper in the `if (inf)`
  branch. Correctness stayed intact, including the infinity-tail selftest, but
  paired autoresearch discarded it: candidate median `40,274,694.606662 ops/sec`
  versus baseline `44,267,553.613436 ops/sec`, `paired_speedup=0.909802`. Keep
  the wrapper-based fallback branch for now.
- A quick direct threadgroup-limit sweep on the promoted public dp4 kernel did
  not justify a new default candidate. `--min-ms 200 --tg-limit 256` measured
  `38,451,966.417140 ops/sec`; `--tg-limit 1024` measured
  `33,660,654.336534 ops/sec`, with matching public checksums. Keep default
  `256`.
- `b6316fe` tried single-final-subtraction reducer helpers for isolated Metal
  field multiply, square, and square-multiply microbenchmarks. First paired
  samples looked interesting (`field_mul 1.010062x`, `field_square 1.133684x`,
  `field_square_mul 1.139845x`) and the stable dp4 oracle stayed intact, but
  `metal_field_mul --confirm-runs 3` discarded it after runs of `1.021127x`,
  `1.647003x`, and `0.897910x`. Keep the shared looped reducer for multiply
  paths.
- `43bf724` narrowed the single-subtraction reducer to square-only micro paths
  and kept multiply/Jacobian paths isolated on the shared reducer. Correctness
  stayed intact, but `metal_field_square --confirm-runs 3` discarded it:
  `1.173994x`, `0.893533x`, `0.958969x`. Keep the current square reducer until
  a repeated paired run proves a durable win.
- `85f9fdb` added `#pragma unroll` only to the public `steps=8`, `dp_bits=4`
  Metal loop. The runtime compiler accepted it and the full DP oracle stayed
  intact, but stable paired confirmation discarded it: `0.891848x`,
  `1.151186x`, `1.046198x`. Keep the current compiler-shaped dp4 loop.
- `373d008` changed the public dp4 affine jump-table reads to two `ulong4`
  loads per step. Correctness and the full DP oracle stayed intact, but stable
  paired confirmation discarded it: `1.098654x`, `0.945560x`, `1.202391x`.
  Keep scalar q-table loads.
- `4fdac33` changed the public dp4 initial Jacobian state reads to three
  `ulong4` loads. Correctness and the full DP oracle stayed intact, but stable
  paired confirmation discarded it: `1.121251x`, `0.764312x`, `0.921588x`.
  Keep scalar initial-state loads.
- `959e118` added a DP4-only finite mixed-add helper that writes the local
  Jacobian limbs and infinity flag in place instead of returning a
  `JacobianValue`. Correctness and the full DP oracle stayed intact, but stable
  paired confirmation discarded it: `0.614190x`, `0.894849x`, `1.371729x`.
  Keep the current finite-path struct-return spelling; the M3 compiler appears
  to schedule it better than the larger in-place helper.
- `c6b63f4` moved the finite mixed-add normal `H != 0` path before the rare
  `H == 0` doubling/infinity edge path. Correctness, the infinity-tail
  selftest, and the full DP oracle stayed intact, but stable paired
  confirmation discarded it: `0.797689x`, `1.444925x`, `0.701535x`. Keep the
  current edge-first helper order.
- `9247265` changed standalone Metal `field_mul4_mod_p` from two modular
  doublings to a direct two-bit shift plus secp256k1 high-limb fold.
  Correctness stayed intact, but confirmation discarded it: `1.168038x`,
  `0.867882x`, `1.489125x`. A longer direct `--min-ms 200` check also lost
  on median (`0.907910x`). Keep the two-doubling spelling.
- `f0301ef` changed standalone Metal `field_neg_mod_p` from a zero-input
  early return to a `nonzero_mask`. Correctness and `make macos-check` stayed
  intact, but confirmation discarded it: `0.998645x`, `1.126949x`,
  `1.834335x`. Longer checks did not clear the bar: `--min-ms 200` median was
  `1.122399x`, but 5 paired `--min-ms 500` samples had absolute median
  `1.008415x` and pairwise median `0.947659x`. Keep the early-return spelling.
- `c313c94` made `field_add_values`, `field_sub_values`, and
  `field_double_values` use masked branchless conditional add/sub helpers.
  `make macos-check` and the public DP oracle stayed intact
  (`distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`), but stable confirmation discarded it:
  `1.429238x`, `0.518187x`, `1.961694x`. A 5-pair `--min-ms 500` direct check
  was also below the bar (`0.809660x` absolute median, `0.974441x` pairwise
  median). Keep the current branched field helpers.
- `macos-metal-mixed-add-efd` tried an EFD-style doubled-variable replacement
  for the finite mixed-add helper. It compiled, but the Metal add, walk, and
  jump-walk tests failed raw Jacobian coordinate checks before benchmarking.
  The formula is affine-equivalent but emits a differently scaled Jacobian
  representative, which breaks the public checksum contract. Keep the current
  raw-representation-compatible mixed-add formula.
- `06562ce` moved the raw-compatible mixed-add `Z*H` output multiply before
  the `Y3` multiply. Correctness and the stable DP oracle stayed intact, but
  paired confirmation discarded it: `0.956924x`, `1.002591x`, `0.940893x`.
  Keep the current source order.
- `35b2a71` reused dead finite mixed-add temporaries to reduce source-level
  register lifetime. Correctness and the stable DP oracle stayed intact, but
  paired confirmation discarded it: `1.028006x`, `1.074308x`, `0.833597x`.
  Keep the explicit post-branch temporary variables.
- `0f35050` moved the specialized DP4 kernel's scalar `out_distances` and
  `out_flags` stores before the bulk XYZ store. Correctness and the stable DP
  oracle stayed intact, but paired confirmation discarded it: `0.954509x`,
  `1.177914x`, `0.608038x`. Keep the current XYZ-first store order.
- `b7d977e` skipped allocation/binding of the unused host-side `dp_mask_buffer`
  for the specialized `steps=8`, `dp_bits=4` Metal kernel. Correctness and the
  public DP oracle stayed intact, but stable confirmation discarded it:
  `1.001230x`, `0.968218x`, `2.089115x`. A 5-pair `--min-ms 500` direct check
  was effectively tied (`1.000162x` absolute median, `1.026724x` pairwise
  median, two pairs below `1.0x`). Keep the simpler always-bind host path.
- `1a62d47` changed multi-target CPU wild scratch initialization from
  `clear`/`push_back` to `resize`/indexed fill. Correctness stayed intact for
  4 and 16 targets (`found_private_key=0x7`, `last_dp_count=84/288`), but
  paired confirmation discarded it. Multi16 raw speedups were `0.859027x`,
  `0.937430x`, `1.028493x`; multi4 raw speedups were `0.915628x`,
  `0.699428x`, `1.046553x`. A 5-pair `--min-ms 200` multi4 check measured
  `0.967105x` absolute median and `0.972254x` pairwise median. Keep the
  current `clear`/`push_back` initialization.
- `bd5506c` moved the Jacobian batch-to-affine `active` scratch resize out of
  the all-active fast path. It preserved `make macos-check`, the batch affine
  checksum oracle, and the 16-target kangaroo oracle, but confirmation
  discarded it. Batch-affine speedups were `0.989579x`, `0.900283x`,
  `1.585928x`; multi16 speedups were `0.953983x`, `0.998116x`, `0.907080x`.
  Keep the existing active-buffer placement until a larger batch-affine change
  proves a stable win.
- `1a2e4f0` added `#pragma clang loop unroll(disable)` only to the public
  `steps=8`, `dp_bits=4` Metal loop. The full DP oracle and `make macos-check`
  stayed intact, but stable paired confirmation discarded it: `0.794078x`,
  `0.966583x`, `1.016373x`. Keep the current compiler-shaped dp4 loop; both
  explicit unroll and explicit no-unroll have now failed the M3 confirmation
  gate.
- `5ec7a80` uploaded the public DP4 read-only input buffers into
  `MTLResourceStorageModePrivate` via pre-compute blits while leaving outputs
  shared. Correctness, `make macos-check`, and the full DP oracle stayed
  intact, but stable paired confirmation discarded it: `0.532957x`,
  `1.216758x`, `0.729656x`. Keep shared inputs for the score path; private
  storage did not produce a repeatable M3 win.
- `715f4b7` fused CPU kangaroo DP collision check and DP recording into one
  open-addressed table probe. `make macos-check` and the multi16 oracle stayed
  intact (`found_private_key=0x7`, `found_target_index=15`,
  `last_dp_count=288`), but paired confirmation discarded it: `0.978479x`,
  `0.999931x`, `1.057456x`. Treat it as neutral noise; keep the existing
  separate lookup/record path.
- `0c3e25a` replaced each CPU DP bucket's embedded overflow vector with a lazy
  `unique_ptr`. Correctness and the multi16 oracle stayed intact, but paired
  confirmation discarded it: `0.975124x`, `0.902597x`, `1.004439x`. Keep the
  embedded overflow vector; the smaller slot did not repay pointer/allocation
  cost in the tiny multi-target gate.
- `macos-kangaroo-collision-unlikely` added `RCK_UNLIKELY` hints around the
  CPU kangaroo collision-found branches. Correctness and the multi16 oracle
  stayed intact, but paired confirmation discarded it: `0.984887x`,
  `0.997734x`, `1.008084x`. Keep the unhinted collision branches.
- `macos-split-tame-wild-dp-tables` split CPU multi-target DP storage into
  separate tame and wild open-addressed tables. Correctness, `make macos-check`,
  and the multi16 oracle stayed intact, but paired confirmation discarded it:
  `1.025170x`, `0.985937x`, `1.005892x`. Keep the single shared DP table; the
  split lookup shape was too noisy to promote.
- `macos-small-affine-scratch` tried persistent 65-entry CPU multi-target
  batch-affine scratch arrays for outputs, prefixes, and active flags.
  Correctness, `make macos-check`, and the multi16 oracle stayed intact, but
  paired confirmation discarded it: `0.975740x`, `0.992597x`, `0.871779x`.
  Keep reused vectors for this path.
- `macos-metal-dynamic-jump-walk` added a separate Metal benchmark that derives
  the jump index inside the kernel from the current Jacobian state using the
  same CPU `x/y/z` mixer. It preserves `make macos-check` and has its own
  oracle/checksum surface, including a `steps=8`, `dp_bits=4` dynamic
  specialization. Do not submit it as a replacement for the public
  precomputed-index DP score path: a 1-second local M3 Air check measured
  dynamic `jumps=16` at `44,774,506.250851 ops/sec` versus the public
  precomputed path at `63,690,640.815902 ops/sec`.
- `macos-metal-dynamic-pow2-dp4` added a dynamic-only branchless power-of-two
  DP4 specialization using `jump_mask` instead of the generic dynamic
  branch/modulo selector. Correctness and `make macos-check` stayed intact, but
  manual local timing remained noisy, with both wins and losses against the
  previous dynamic kernel. Treat it as dynamic-walk infrastructure; it does not
  change the public precomputed-index score path.
- `macos-metal-dynamic-j16-dp4` tried an exact dynamic `steps=8`, `dp_bits=4`,
  `jumps=16` kernel with `mixed & 0xf`. Correctness and `make macos-check`
  stayed intact, including the dynamic 16384-sample oracle
  (`distance_checksum=0x5c36c706ffa2cbaa`, `dp_count=1017`,
  `dp_checksum=0xbfd3b2319760e774`), but paired autoresearch confirmation
  discarded it: `0.548550x`, `0.803677x`, `1.115114x`. Keep the dynamic
  `jump_mask` specialization; there is no public score-path impact.
- `macos-metal-dynamic-q-row-local` tried caching each dynamic DP4
  `AffineJumpValue` row in a local `q` variable before the mixed-add call.
  Correctness and `make macos-check` stayed intact, including pow2/modulo smoke
  runs and the stable dynamic oracle, but paired autoresearch confirmation
  discarded it: `1.075168x`, `1.071071x`, `0.991099x`. Keep direct
  `q_xy[jump_index].field` access until a repeatable dynamic gain appears.
- `macos-metal-dynamic-u32-mask` tried `((uint)mixed) & jump_mask` in the
  dynamic pow2 DP4 kernel. Correctness and `make macos-check` stayed intact,
  including pow2/modulo smoke runs and the stable dynamic oracle, but paired
  autoresearch confirmation discarded it: `0.684326x`, `1.196446x`,
  `1.062018x`. Keep the current 64-bit mask spelling for now.
- `macos-metal-dynamic-tg512-default` tried making the dynamic Metal walk use
  512 threads per threadgroup by default while preserving explicit
  `--tg-limit` overrides. Correctness and the stable dynamic oracle stayed
  intact, but paired confirmation discarded it: `0.453954x`, `0.945385x`,
  `0.938971x`. Keep the 256 default; a short 512 sweep was not reproducible.
- `macos-metal-dynamic-implicit-distance` tried replacing the dynamic pow2 DP4
  distance-table load with `distance += (1UL << jump_index)`. Correctness and
  the stable dynamic oracle stayed intact, but paired confirmation discarded it:
  `1.120441x`, `0.898834x`, `0.900900x`. Keep the distance-table load.
- `macos-metal-dynamic-limbfold-mixer` tried a dynamic-only 32-bit shifted-limb
  xorshift mixer instead of the 64-bit avalanche multiply, with a temporary
  histogram oracle to check partition quality. Correctness, `make macos-check`,
  and the dynamic CLI gate stayed intact; the stable-shape histogram was
  balanced enough (`min=7938`, `max=8359`, `max_deviation_ppm=31006`), but
  paired confirmation discarded it: `1.028646x`, `0.690314x`, `1.119847x`.
  Keep the current dynamic avalanche mixer until a lighter selector wins every
  stable confirmation and keeps an explicit distribution-quality gate.
- `metal_jacobian_dynamic_walk_dp_stable` now exists as a stable autoresearch
  gate for the dynamic Metal walk. Use it for future in-kernel jump-selection
  experiments after the target exists on both candidate and baseline refs.
- `macos-metal-dynamic-jump-quality-metrics` kept the current dynamic
  `avalanche64` mixer and added permanent benchmark JSON fields for
  `jump_mixer`, `jump_histogram_min_bucket`, `jump_histogram_max_bucket`, and
  `jump_histogram_max_deviation_ppm`. The stable-shape smoke run preserved the
  dynamic oracle (`distance_checksum=0x5c36c706ffa2cbaa`, `dp_count=1017`,
  `dp_checksum=0xbfd3b2319760e774`) and reported `min=8082`, `max=8336`,
  `max_deviation_ppm=17578`, so future mixer attempts have a distribution
  quality surface in addition to speed and checksum correctness.
- `macos-metal-dynamic-compact-dp-emission` added a separate dynamic
  `steps=8`, `dp_bits=4`, power-of-two jump-count kernel that emits packed
  flags, scalar distance, and one compact DP checksum term instead of copying
  the final full Jacobian state. It reports `output_layout=dp_compact` and
  `output_bytes_per_sample=17`, preserves the same dynamic oracle
  (`distance_checksum=0x5c36c706ffa2cbaa`, `dp_count=1017`,
  `dp_checksum=0xbfd3b2319760e774`), and passed `make macos-check`. Treat this
  as DP-emission layout infrastructure; the full dynamic walk remains the
  final-state correctness reference. Clean autoresearch on commit `1a03888`
  recorded `status=keep`, median `54,351,372.121311` steps/sec across three
  stable samples, with `output_bytes_per_sample=17`.
- `macos-metal-dynamic-compact-dp-tg512` was rejected by a direct alternating
  sweep. A single pass made 512 look competitive, but the 256/512 alternating
  sequence favored the existing 256 cap: 256 median `32.654M` steps/sec versus
  512 median `29.076M`, with identical compact dynamic oracle fields.
- `macos-metal-dynamic-dp-stream-emission` added a separate sparse stream
  architecture for dynamic DP candidates. The Metal kernel emits only actual
  DP records through an atomic counter, reporting `output_layout=dp_stream`,
  `output_bytes_per_record=20`, `emitted_records`, `dp_capacity`, and
  `dp_stream_overflow`. The DP4 smoke run emitted `1017` records
  (`20,340` logical output bytes), preserved `dp_checksum=0xbfd3b2319760e774`,
  and passed `make macos-check`; direct DP4 timing was slower than compact/full
  dynamic, so treat it as a high-`dp_bits` sparse-emission probe. Clean
  autoresearch on commit `f3599da` recorded `status=keep`, median
  `41,222,124.404033` steps/sec, `output_bytes_total=20340`, and no overflow.
- `macos-metal-dynamic-dp-stream-runtime-mask` keeps the DP4 sparse stream on
  the hardcoded kernel and adds a runtime-mask stream kernel for non-DP4
  `dp_bits`. The DP8 stable smoke shape (`steps=8`, `jumps=16`, `min_ms=200`)
  emitted `61` records (`1,220` logical output bytes), preserved
  `correctness=true`, `dp_checksum=0xab1c2cd29cd70a84`, and
  `dp_distance_checksum=0x822e141de4770a0b`, while the adjacent DP4 stream
  oracle stayed at `1017` records and `dp_checksum=0xbfd3b2319760e774`. Treat
  this as an accepted high-`dp_bits` measurement surface, not a change in
  kangaroo asymptotics. Clean autoresearch on commit `0bf960d` recorded
  `status=keep`, median `37,013,170.931979` steps/sec across three stable
  samples, `output_bytes_total=1220`, `emitted_records=61`, and no overflow.
- `macos-metal-dynamic-dp-stream-u32-distance` keeps DP4 on the promoted
  hardcoded stream kernel but lets non-DP4 stream shapes use a guarded 32-bit
  internal distance accumulator when the host proves the maximum scalar
  distance fits in `uint32_t`. The external stream and validator stay
  `uint64_t`. Clean autoresearch on commit `62c5298` kept it with median
  `56,977,760.954224` DP8 steps/sec (`min=38,851,216.280614`,
  `max=57,571,900.124877`) versus baseline `37,013,170.931979`, with
  `emitted_records=61`, `dp_checksum=0xab1c2cd29cd70a84`, and
  `dp_distance_checksum=0x822e141de4770a0b`.
- `macos-metal-dynamic-dp8-stream-const-mask` specializes that DP8 stream path
  further by hardcoding the DP predicate as `(x0 & 0xFF) == 0` and avoiding the
  runtime `dp_mask` buffer. Clean autoresearch on commit `f878edc` kept it
  with median `58,596,783.649305` DP8 steps/sec
  (`min=41,535,061.854930`, `max=63,616,563.008358`) versus baseline
  `56,977,760.954224`, with `emitted_records=61`,
  `dp_checksum=0xab1c2cd29cd70a84`, and
  `dp_distance_checksum=0x822e141de4770a0b`.
- `macos-metal-dynamic-dp-count-probe` added a count-only diagnostic kernel for
  the dynamic DP8 path. It uses the same runtime DP mask but only increments
  one atomic `dp_count`, writing no candidate records. Clean autoresearch on
  commit `4b4014c` recorded `status=keep`, median `53,546,106.476522`
  steps/sec with `dp_count=61`; a same-worktree stream DP8 rerun recorded
  median `39,287,501.787886` steps/sec with the full stream oracle
  (`emitted_records=61`, `dp_checksum=0xab1c2cd29cd70a84`). Treat this as a
  diagnostic for record-write overhead, not as a candidate-emission path.
- `macos-metal-dynamic-dp-count-first-inf` was rejected. It specialized the
  count-only DP8 kernel for the benchmark shape where only `p[0]` starts at
  infinity and used finite mixed-add for all other lanes. Source and CLI smoke
  checks passed, but clean autoresearch discarded it: median
  `41,917,696.770121` steps/sec (`min=39,051,687.094501`,
  `max=59,087,644.282271`) versus the count-only DP8 baseline median
  `53,546,106.476522`, with `dp_count=61`. Do not promote this specialization.
- `macos-metal-dynamic-dp-stream-group-reserve` was rejected. It used
  threadgroup-local DP counting and one global reservation per threadgroup
  before writing sparse DP stream records. Correctness stayed intact for DP8
  (`emitted_records=61`, `dp_checksum=0xab1c2cd29cd70a84`,
  `dp_distance_checksum=0x822e141de4770a0b`), but clean autoresearch on
  commit `e48ade7` discarded it: median `34,241,001.868863` steps/sec
  (`min=30,214,085.775297`, `max=56,510,398.787670`) versus DP8 stream
  baseline `37,013,170.931979`. A preliminary DP4 run also discarded at median
  `38,666,572.600191` steps/sec. Keep the simpler per-record global atomic.
- `macos-metal-dynamic-dp-stream-u32-pow2-distance` was rejected. It replaced
  the accepted u32-distance table load with `1U << jump_index` under a host
  power-of-two distance-table guard. Correctness stayed intact, but clean
  autoresearch on commit `413b1cb` discarded it: median
  `40,186,882.764342` DP8 steps/sec (`min=32,100,455.469615`,
  `max=58,747,215.509733`) versus promoted u32-distance baseline
  `56,977,760.954224`. Keep the table-load u32-distance kernel.
- `macos-metal-dynamic-compact-dp8-u32` was rejected. A dense compact-output
  runtime-mask DP8 prototype preserved correctness (`dp_count=61`,
  `dp_checksum=0xab1c2cd29cd70a84`, `distance_checksum=0x5c36c706ffa2cbaa`),
  but three direct stable samples had median `35,537,101.509200` steps/sec
  (`min=35,048,956.794514`, `max=37,826,360.142984`) versus promoted sparse
  stream DP8 median `56,977,760.954224`. Keep sparse stream for DP8.
- `macos-metal-dynamic-dp8-stream-j16-mask` was rejected. It hardcoded the
  DP8 stream jump mask to `0xF` for `jumps.size()==16`, preserving the stream
  oracle (`emitted_records=61`, `dp_checksum=0xab1c2cd29cd70a84`,
  `dp_distance_checksum=0x822e141de4770a0b`), but clean autoresearch discarded
  it: median `48,463,423.411911` steps/sec (`min=29,267,546.773174`,
  `max=56,335,643.461168`) versus promoted DP8 const-mask stream median
  `58,596,783.649305`. Keep the accepted runtime `jump_mask` DP8 path.
- `macos-metal-dynamic-dp8-stream-tg64-default` was rejected. It changed only
  the DP8 stream default threadgroup size from 256 to 64 and preserved explicit
  `--tg-limit` overrides. The DP8 stream oracle stayed unchanged, but paired
  autoresearch against `main` discarded it: candidate median
  `32,422,230.207947` steps/sec (`min=28,376,163.880242`,
  `max=65,260,356.568942`) versus paired baseline median
  `60,342,525.488163`, `paired_speedup=0.537303`. Keep default 256.
- `macos-metal-dynamic-x0-mixer` was rejected. It replaced the dynamic
  avalanche jump mixer with direct projective `x0` low bits. The DP8 stream
  replay oracle stayed self-consistent and histogram quality was close
  (`min=8039`, `max=8347`, `max_deviation_ppm=18921`), but paired autoresearch
  discarded it: candidate median `29,799,267.712366` steps/sec versus paired
  baseline `31,783,403.981837`, `paired_speedup=0.937573`. Keep `avalanche64`.
- `macos-metal-dp8-stream-firstinf` was rejected. It removed the DP8 sparse
  stream `p_infinity[id]` load for the common benchmark shape where only
  `p[0]` starts at infinity and used `id == 0` instead. The DP8 stream oracle
  stayed unchanged (`emitted_records=61`,
  `dp_checksum=0xab1c2cd29cd70a84`,
  `dp_distance_checksum=0x822e141de4770a0b`), but paired autoresearch
  discarded it: candidate median `910,556.434373` steps/sec versus paired
  baseline `1,799,640.261424`, `paired_speedup=0.505966`. Keep the current
  explicit infinity buffer in the DP8 stream path.
- `macos-metal-dp8-stream-finite-tail` was rejected. It split the DP8 sparse
  stream benchmark shape into a branch-free finite-tail kernel for `p[1..]`
  and a CPU append for `p[0]`, with a CPU precheck that the tail never reaches
  infinity. The oracle stayed unchanged, but paired autoresearch discarded it:
  candidate median `34,715,854.003069` steps/sec versus paired baseline
  `50,834,993.140300`, `paired_speedup=0.682913`. Keep the accepted single
  DP8 stream kernel.
- `macos-metal-dynamic-compact-dp-local-jump-row` was rejected. Applying local
  affine row reuse to the DP4 compact-output kernel preserved the oracle
  (`distance_checksum=0x5c36c706ffa2cbaa`, `dp_count=1017`,
  `dp_checksum=0xbfd3b2319760e774`) but paired autoresearch discarded it:
  candidate median `28,896,380.858909` steps/sec versus paired baseline
  `54,829,695.882427`, `paired_speedup=0.527021`. Keep the row-reuse pattern
  to sparse stream kernels for now.
- `macos-metal-dynamic-walk-local-jump-row` was rejected. Applying local affine
  row reuse to the DP4 full-output dynamic walk kernel preserved
  `distance_checksum=0x5c36c706ffa2cbaa`, `dp_count=1017`, and
  `dp_checksum=0xbfd3b2319760e774`, but paired autoresearch discarded it:
  candidate median `37,929,646.083412` steps/sec versus paired baseline
  `49,708,107.924197`, `paired_speedup=0.763047`.
- `macos-metal-dynamic-dp-count-local-jump-row` was rejected. It preserved
  `dp_count=61`, but paired autoresearch discarded it: candidate median
  `31,386,712.313105` steps/sec versus paired baseline
  `38,552,397.853331`, `paired_speedup=0.814131`. Keep row reuse scoped to
  sparse stream kernels.
- `macos-metal-dynamic-u32-stream-local-jump-row` was rejected. A direct
  alternating probe preserved the DP6/DP10/DP12 stream oracle, but only DP6
  improved (`1.032495x`); DP10 fell to `0.776477x` and DP12 to `0.966718x`.
  Keep generic runtime-mask u32 stream row access unchanged.
- `autoresearch-command-backed-experiments` was accepted for harness coverage.
  Experiments may now use `build_target` plus `bench_command` instead of a
  Makefile benchmark target. The first DP10 command-backed paired row preserved
  the stream oracle (`emitted_records=15`,
  `dp_distance_checksum=0xb6973c2035ff6351`,
  `dp_checksum=0xcbfdc2badaf0e57a`) and recorded `paired_speedup=0.894409`
  for same-code candidate/baseline, so it is a DP10 baseline record, not a
  solver-code promotion.
- The Metal field add/mul/square/square-mul autoresearch gates now also use
  `build_target=macos-build` plus direct benchmark commands. The first
  `metal_field_add` smoke row built once, preserved `correctness=true`, and
  recorded median `225,377,938.159104 ops/sec`; treat this as harness
  stabilization for future arithmetic experiments, not a solver-code speedup.
- The stable DP8 dynamic stream gate now uses the same build-once command path.
  The first smoke row preserved the DP8 stream oracle (`emitted_records=61`,
  `dp_distance_checksum=0x822e141de4770a0b`,
  `dp_checksum=0xab1c2cd29cd70a84`) and recorded median
  `67,169,019.394725` steps/sec. Use this cleaner DP8 baseline for future
  point-level experiments.
- `macos-metal-dp8-inplace-stream` was accepted as a state-preserving GPU walk
  primitive. It updates the Jacobian state buffer in place and emits sparse
  DP8 records; the oracle checks both the stream and final raw Jacobian state.
  Autoresearch recorded median `67,315,699.992225` steps/sec with
  `emitted_records=61`,
  `dp_distance_checksum=0x822e141de4770a0b`, and
  `dp_checksum=0xab1c2cd29cd70a84`. Alternating probes versus DP8
  full-output `dynamic-walk` kept a positive median signal (`1.125972x` over
  three pairs, `1.099271x` over five noisier pairs, `1.866489x` over three
  `--min-ms 500` pairs). A pure-stream comparison was near parity on absolute
  median (`0.986428x`) and noisy pairwise, so use this when persistent GPU
  state is required, not as a pure sparse-stream replacement.
- `macos-metal-dp8-inplace-emit-before-store` was rejected. Moving the sparse
  DP record emission before the final in-place state stores preserved the DP8
  stream oracle (`emitted_records=61`,
  `dp_distance_checksum=0x822e141de4770a0b`,
  `dp_checksum=0xab1c2cd29cd70a84`), but paired confirmation discarded it with
  raw speedups `0.907874x`, `0.955029x`, and `0.807249x`. Keep the accepted
  state-store-before-DP-emit order in the in-place stream kernel.
- `macos-metal-dynamic-dp10-stream-specialization` was rejected. A dedicated
  DP10 const-mask sparse stream kernel preserved the oracle, but paired
  autoresearch discarded it: candidate median `54,324,631.189670` steps/sec
  versus paired baseline `57,359,097.012105`, `paired_speedup=0.947097`.
  Keep DP10 on the generic runtime-mask u32-distance stream path.
- `macos-metal-dynamic-dp10-stream-tg64-default` was rejected. Changing only
  the DP10 sparse stream default threadgroup size to 64 preserved the oracle,
  but paired autoresearch discarded it: candidate median
  `55,120,744.100756` steps/sec versus paired baseline `57,341,488.499819`,
  `paired_speedup=0.961272`. Keep the shared 256 default.
- `macos-metal-dynamic-dp6-stream-specialization` was rejected, but the DP6
  command-backed gate was kept. The dedicated DP6 const-mask/local-row kernel
  preserved `emitted_records=248`,
  `dp_distance_checksum=0xcd602d19c5edfa05`, and
  `dp_checksum=0xb302d085b993018a`, but paired autoresearch discarded it:
  candidate median `39,834,931.340750` steps/sec versus paired baseline
  `55,663,782.861444`, `paired_speedup=0.715635`.
- `macos-metal-dynamic-dp8-stream-u32-output-distance` was rejected. Narrowing
  DP8 stream record distances to 32-bit reduced each emitted record from 20 to
  16 bytes and preserved the oracle, but paired autoresearch discarded it:
  candidate median `32,233,487.865141` steps/sec versus paired baseline
  `38,353,440.458919`, `paired_speedup=0.840433`.
- `macos-metal-dynamic-dp4-stream-no-overflow-branch` was rejected. Removing
  the DP4 sparse stream specialization's in-kernel `slot < dp_capacity` /
  `out_overflow` branch preserved `emitted_records=1017`,
  `dp_distance_checksum=0x19e43ca50eec2a74`, and
  `dp_checksum=0xbfd3b2319760e774`, but paired autoresearch discarded it:
  candidate median `31,405,650.680564` steps/sec versus paired baseline
  `41,006,978.823522`, `paired_speedup=0.765861`. Keep the DP4 overflow
  branch even though the DP8 variant benefits from removing it.
- `macos-metal-dynamic-u32-stream-no-overflow-branch` was rejected as a shared
  generic path change. Removing the overflow branch from the runtime-mask
  u32-distance stream kernel preserved both DP10 and DP6 oracles; DP10 showed
  a keep signal (`42,278,414.551117` versus `29,964,798.774474` steps/sec,
  `paired_speedup=1.410936`), but DP6 regressed (`50,415,308.939320` versus
  `59,073,704.479935`, `paired_speedup=0.853431`). Keep the generic u32
  overflow branch; a DP10-only specialization can be tested separately.
- `macos-metal-dynamic-dp10-stream-no-overflow-specialization` was tested
  separately and rejected. A dedicated DP10 const-mask/no-overflow kernel
  preserved `emitted_records=15`,
  `dp_distance_checksum=0xb6973c2035ff6351`, and
  `dp_checksum=0xcbfdc2badaf0e57a`, but two confirmation runs both discarded:
  `50,590,171.559774` versus `57,834,567.954473` steps/sec
  (`paired_speedup=0.874739`) and `36,257,628.573029` versus
  `56,053,192.101321` (`paired_speedup=0.646843`).
- `macos-metal-dynamic-dp4-stream-no-steps-arg` was rejected. Removing the
  unused `steps [[buffer(7)]]` argument from the fixed `steps=8` DP4 sparse
  stream specialization preserved `emitted_records=1017`,
  `dp_distance_checksum=0x19e43ca50eec2a74`, and
  `dp_checksum=0xbfd3b2319760e774`, but paired autoresearch discarded it:
  candidate median `49,544,294.377036` steps/sec versus paired baseline
  `50,583,214.355980`, `paired_speedup=0.979461`. Keep the DP4 signature
  unchanged; the no-steps-arg win is DP8-specific for now.
- `macos-metal-dynamic-dp8-stream-u32-jump-distances` was rejected. Packing
  the DP8 stream jump-distance table as `uint32_t` and reading it as
  `constant uint*` preserved `emitted_records=61`,
  `dp_distance_checksum=0x822e141de4770a0b`, and
  `dp_checksum=0xab1c2cd29cd70a84`, but paired autoresearch discarded it:
  candidate median `40,455,982.284936` steps/sec versus paired baseline
  `54,871,015.351268`, `paired_speedup=0.737292`. Keep the DP8 stream
  distance table as `ulong*` with an explicit cast to `uint`.
- `macos-metal-dynamic-dp8-stream-j16-mask-after-no-steps` was rejected. A
  dedicated post-no-overflow/no-steps DP8 kernel for `jumps=16` hardcoded
  `mixed & 0xF` and preserved `emitted_records=61`,
  `dp_distance_checksum=0x822e141de4770a0b`, and
  `dp_checksum=0xab1c2cd29cd70a84`, but paired autoresearch discarded it:
  candidate median `20,232,288.968150` steps/sec versus paired baseline
  `52,397,986.361443`, `paired_speedup=0.386127`. Keep the existing shared
  DP8 mask kernel for `jumps=16`.
- `macos-metal-dynamic-dp8-count-specialization` was rejected. A DP8 count-only
  kernel with hardcoded `x0 & 0xFF`, no `steps`, and no runtime `dp_mask`
  preserved `dp_count=61` and `correctness=true`, but did not beat the generic
  count kernel. The local-row variant measured `43,773,240.202096` steps/sec
  versus paired baseline `44,442,548.274759`, `paired_speedup=0.984940`; the
  direct-`q_xy` variant measured `50,394,707.554658` versus
  `68,896,134.342987`, `paired_speedup=0.731459`. Keep DP8 count-only on the
  shared runtime-mask kernel.
- `macos-metal-dynamic-dp-count-no-steps-arg` was rejected. Removing only the
  unused `steps` argument/buffer from the shared count-only kernel preserved
  `dp_count=61` and `correctness=true`, but paired autoresearch discarded it:
  candidate median `36,757,514.206820` steps/sec versus paired baseline
  `40,073,503.015154`, `paired_speedup=0.917252`. Keep the count-only
  signature unchanged.
- `macos-metal-dynamic-dp-count-tg128-default` was rejected. A one-pass
  `--tg-limit` sweep for DP8 count hinted that 128 might beat 256
  (`47,358,509.954244` versus `45,933,576.464768` steps/sec), but paired
  confirmation was unstable: initial `paired_speedup=1.014269`, confirmation
  run 1 `0.896486`, confirmation run 2 `1.327843`, with overall
  `confirmation_status=discard`. Keep count-only default threadgroup cap at
  256.
- `macos-metal-dynamic-dp12-stream-gate` adds a reusable autoresearch gate for
  the sparse DP12 stream shape. Baseline median was `39,603,303.230057`
  steps/sec with `emitted_records=3`, `dp_distance_checksum=0xfb58c602127bde02`,
  and `dp_checksum=0xccdf6d15eaf2c6b0`.
- `macos-metal-dynamic-dp12-stream-no-overflow` was rejected. A dedicated DP12
  stream kernel hardcoded `x0 & 0xFFF` and removed the overflow/capacity branch
  while preserving the DP12 oracle, but paired autoresearch discarded it:
  candidate median `35,307,732.434448` steps/sec versus paired baseline
  `39,646,497.326093`, `paired_speedup=0.890564`. Keep DP12 on the generic
  runtime-mask u32-distance stream kernel.
- `macos-metal-dynamic-dp12-stream-tg128-default` was accepted. For the sparse
  DP12 stream path only, the default threadgroup cap is now 128 when no
  explicit `--tg-limit` is provided; explicit overrides still win. A sequential
  sweep measured tg64 `39,758,545.634387`, tg128 `43,101,368.645947`, tg256
  `38,769,840.616246`, tg512 `38,922,032.447806`, and tg1024
  `33,594,476.616126` DP12 steps/sec. The paired gate kept the candidate first
  at `paired_speedup=1.053900`, then kept a two-run confirmation at
  `paired_speedup=1.107058`. The DP12 oracle stayed unchanged:
  `emitted_records=3`, `dp_distance_checksum=0xfb58c602127bde02`,
  `dp_checksum=0xccdf6d15eaf2c6b0`, and `correctness=true`.
- `macos-metal-dynamic-dp10-stream-tg512-default` was rejected. Forward and
  reverse explicit sweeps were order-sensitive, and the paired gate confirmed
  the risk: first run kept the 512 default at `paired_speedup=1.064623`, but
  the two-run confirmation discarded it at `paired_speedup=0.942086`. The DP10
  oracle stayed unchanged (`emitted_records=15`,
  `dp_distance_checksum=0xb6973c2035ff6351`,
  `dp_checksum=0xcbfdc2badaf0e57a`, `correctness=true`). Keep DP10 on the
  shared 256 default.
- `macos-metal-dynamic-dp6-stream-tg128-default` was rejected. Explicit sweeps
  made 128 look plausible for the denser DP6 stream, but paired confirmation
  was unstable: first run kept at `paired_speedup=1.119449`, confirmation run 1
  discarded, confirmation run 2 kept, and overall `confirmation_status=discard`.
  The DP6 oracle stayed unchanged (`emitted_records=248`,
  `dp_distance_checksum=0xcd602d19c5edfa05`,
  `dp_checksum=0xb302d085b993018a`, `correctness=true`). Keep DP6 on the
  shared 256 default.
- Public dp4 stable baseline refresh after the stream experiments preserved the
  score-path oracle (`distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`) with median
  `27,922,343.656972` ops/sec over three 200 ms samples. A same-turn local
  Benchforge run measured `18,036,840.326574` ops/sec, confirming that single
  local score runs are too noisy for promotion decisions.
- `macos-metal-dynamic-dp16-large-stream-gate` adds a reusable gate for very
  sparse DP16 stream experiments. The ordinary `sample_count=16384` DP16 shape
  emitted zero records, so the gate uses `--iterations 65536` and emits one
  record with `dp_distance_checksum=0x9e3779b97f4bab4a`,
  `dp_checksum=0xebe643771995a1fa`, and `correctness=true`. Initial median was
  `52,989,830.333319` steps/sec at the existing 256 default. No DP16 default
  threadgroup change was promoted; manual 256/512 sweeps were too close/noisy.
- `macos-metal-dynamic-dp14-stream-gate` adds a middle-density sparse stream
  gate between DP12 and DP16. The `sample_count=16384`, `dp_bits=14` shape
  emits one record with `dp_distance_checksum=0x9e3779b97f4b39c1`,
  `dp_checksum=0x252996ea8a0dca38`, and `correctness=true`. Initial median was
  `34,457,601.167211` steps/sec at the existing 256 default. Use it when DP12
  is too dense but DP16-large is too sparse for a candidate's expected effect.
- A manual post-DP8-no-overflow `--tg-limit` sweep kept the existing 256
  default. With the accepted DP8 no-overflow kernel and unchanged oracle
  (`emitted_records=61`, `dp_checksum=0xab1c2cd29cd70a84`,
  `dp_distance_checksum=0x822e141de4770a0b`), one explicit sweep measured:
  tg64 `47,760,021.663871`, tg128 `62,608,992.429817`, tg256
  `65,340,428.908829`, tg512 `63,549,730.568347`, and tg1024
  `64,773,844.447836` steps/sec. Do not retune DP8 threadgroup default from
  this sample.
- `macos-metal-dynamic-dp16-stream-no-overflow-specialization` was rejected.
  A DP16-only const-mask/no-overflow kernel kept correctness
  (`emitted_records=1`, `output_bytes_total=20`,
  `dp_distance_checksum=0x9e3779b97f4bab4a`,
  `dp_checksum=0xebe643771995a1fa`) but lost badly in the paired gate:
  candidate `58,886,361.624760` versus baseline `81,212,851.782611`
  steps/sec (`paired_speedup=0.725087`). Keep sparse DP16 on the generic
  runtime-mask u32-distance stream kernel.
- `macos-metal-dp4-soa-input-layout` was rejected. Repacking the public DP4
  input Jacobian batch as SoA kept correctness for both score and verifier
  fallback oracles (`0xa45f471493cace2f`/`1000`/`0x30a7914972cba014` and
  `0xbab72b58ebefa9dc`/`249`/`0x4a7f2853a4a9f546`). The first paired run kept
  it (`31,361,809.164586` versus `27,944,840.858156`, `1.122275x`), but
  confirmation discarded it (`19,168,913.507147` versus `20,875,904.079754`,
  `0.918232x`). Keep the current 12-limb AoS input for the public score path.
- `macos-metal-public-dp4-local-jump-row` was rejected. Loading
  `AffineJumpValue jump = q_xy[jump_index]` once per step preserved the public
  and verifier fallback oracles, but stable paired confirmation discarded it:
  `0.485932x` and `0.716055x`. Keep direct `q_xy[jump_index].x*/y*` field
  operands in the public precomputed-index DP4 kernel; the local row spelling
  appears to worsen the M3 compiler/register shape here, despite helping some
  sparse stream kernels.
- `macos-metal-dynamic-dp14-stream-no-overflow-specialization` was rejected.
  A DP14-only const-mask/no-overflow stream kernel kept correctness
  (`emitted_records=1`, `output_bytes_total=20`,
  `dp_distance_checksum=0x9e3779b97f4b39c1`,
  `dp_checksum=0x252996ea8a0dca38`) but did not survive two-run paired
  confirmation: run 1 was `0.801763x`, run 2 was a noisy `1.098475x`, and the
  overall gate stayed `discard`. Keep DP14 on the generic runtime-mask
  u32-distance stream kernel.
- `macos-metal-dp4-pragma-unroll-retest` was rejected. Re-adding
  `#pragma unroll` to the public DP4 loop preserved the public oracle and a
  two-run paired probe looked positive (`1.244234x`, `1.109164x`), but the
  stricter three-run confirmation discarded it (`0.721059x`, `0.656319x`,
  `0.979125x`). Keep the compiler-shaped public DP4 loop.
- `macos-precomputed-wild-starts-retest` was rejected. Precomputing CPU
  multi-target wild starts once per benchmark run and copying them into solve
  scratch kept correctness for 4-target and 16-target kangaroo
  (`found_private_key=0x7`, target indexes `3`/`15`, DP counts `84`/`288`) and
  passed `make macos-check`, but paired confirmation discarded both gates. The
  4-target gate ended at `0.960383x`; the 16-target gate ended at `1.003387x`
  with `confirmation_status=discard`. Keep the existing inline
  `JacobianFromAffine` initialization; this precompute/copy split is too close
  to noise on the M3 Air.
- `macos-kangaroo-dp0-fast-path` was rejected. A dedicated CPU multi-target
  `dp_bits=0` solver path skipped `IsDistinguished(...)` and marked JSON with
  `dp_predicate=all_points_fast_path`; correctness and `make macos-check`
  passed for 4-target and 16-target shapes. Paired confirmation discarded it:
  4-target ended at `1.001281x` and 16-target ended at `0.997717x`. Keep the
  unified DP predicate path; the branch is not the current bottleneck.
- `macos-metal-field-add-x4` was rejected. A Metal field-add kernel that did
  four additions per thread preserved correctness, including a non-multiple-of
  four smoke case, but paired confirmation discarded it at `0.562870x`
  (`125,737,724.391583` versus `223,386,636.821191` ops/sec). Keep one field
  element per thread for add; x4 underutilizes the M3 GPU for this kernel.
- `macos-metal-dp8-inplace-steps16` was accepted as a longer in-place stream
  packet. It runs 16 dynamic Jacobian jumps per thread before storing the
  updated state and checking/emitting a DP record, while preserving CPU replay
  for both the sparse DP stream and final `x/y/z/inf` state. Autoresearch kept
  the candidate after three confirmation groups: median
  `76,531,591.057923` steps/sec, `emitted_records=67`,
  `dp_distance_checksum=0x68fbd251ce4fd08e`,
  `dp_checksum=0xdd7021cb96f924c0`, `correctness=true`. Alternating local
  comparison against the existing `steps=8` in-place packet measured
  `1.085387x` median over five `--min-ms 200` pairs; a three-pair
  `--min-ms 500` run stayed positive at `1.087669x` median but included one
  negative pair. Use it as a packet-size/throughput option, not as an
  every-intermediate-step DP checker.
- `macos-metal-dp8-inplace-steps32` was accepted as the next packet-size probe.
  It runs 32 dynamic Jacobian jumps per thread before state store and DP
  emission, preserving the sparse-stream and final-state CPU oracle. Three
  autoresearch confirmation groups kept it at median `78,549,463.782889`
  steps/sec with `emitted_records=61`,
  `dp_distance_checksum=0xa31eaba41f549318`,
  `dp_checksum=0x751402be27e58082`, `correctness=true`. Same-binary
  comparison against `steps16` measured `1.080838x` median over five
  `--min-ms 200` pairs and `1.475099x` median over three `--min-ms 500` pairs.
  It is the fastest local in-place DP8 packet so far, with DP sampling only at
  the packet boundary.
- `macos-metal-dp8-inplace-steps64` was accepted. It extends the packet ladder
  to 64 dynamic Jacobian jumps per thread before state store and DP emission.
  Three autoresearch confirmation groups kept it at median
  `90,119,567.579470` steps/sec with `emitted_records=54`,
  `dp_distance_checksum=0x132b1b39482c3732`,
  `dp_checksum=0xc4c55fe6a6308d32`, `correctness=true`. Same-binary comparison
  against `steps32` measured `1.085726x` median over five `--min-ms 200` pairs
  and `1.094047x` median over three `--min-ms 500` pairs. It is the fastest
  local in-place DP8 packet so far, with DP sampling only at the packet
  boundary.
- `macos-metal-dp8-inplace-steps128` was accepted as a plateau probe. It keeps
  the same sparse-stream/final-state oracle and recorded
  `emitted_records=68`, `dp_distance_checksum=0x2b611389e103e188`,
  `dp_checksum=0xc9e5a3440ffdb698`, `correctness=true`. Autoresearch ended at
  `90,611,211.497293` steps/sec, and same-binary comparison against `steps64`
  measured `1.013988x` median over five `--min-ms 200` pairs plus `1.022074x`
  median over five `--min-ms 500` pairs. Treat it as a valid packet-size
  option but recognize that the packet-size ladder is close to a local plateau.
- `macos-metal-dp8-inplace-steps256` was accepted as the next plateau probe. It
  preserves the sparse-stream/final-state CPU oracle and recorded
  `emitted_records=57`, `dp_distance_checksum=0x0ab81bcdffe988ca`,
  `dp_checksum=0xbb961e8e4fffeeb0`, `correctness=true`,
  `output_bytes_total=1140`, and a jump histogram range of `261599..262582`
  with `jump_histogram_max_deviation_ppm=2079`. Autoresearch kept three
  confirmation groups and ended at `89,960,529.450509` steps/sec. Alternating
  same-binary comparison against `steps128` stayed positive at `1.054086x`
  median over five `--min-ms 200` pairs and `1.058103x` median over three
  `--min-ms 500` pairs. The raw final median is slightly below the previous
  `steps128` autoresearch row, so treat `steps256` as a valid packet-size
  option and plateau datapoint, with DP sampling only at the packet boundary.
- `macos-metal-dp8-inplace-steps512` was rejected as a packet-size extension.
  The prototype preserved the 512-step sparse-stream/final-state oracle
  (`emitted_records=64`, `output_bytes_total=1280`,
  `dp_distance_checksum=0x9edbacbfba811d14`,
  `dp_checksum=0x1d74ff586fee3e54`, `correctness=true`) and raw autoresearch
  confirmation reached `90,061,456.584152` steps/sec. Same-binary paired
  checks against accepted `steps256` were too close to promote: five
  `--min-ms 200` pairs had median `1.010153x` with one negative pair, and five
  `--min-ms 500` pairs fell below the gate at median `1.009593x` with speedups
  from `0.975577x` to `1.025456x`. Keep the accepted ladder at 256 steps until
  a later change produces a clearer paired win.
  Retesting after the accepted `steps16+ -> threadgroup_limit=128` policy found
  `--tg-limit 64` as the best 512-step cap. Correctness stayed unchanged
  (`emitted_records=64`,
  `dp_distance_checksum=0x9edbacbfba811d14`,
  `dp_checksum=0x1d74ff586fee3e54`, `correctness=true`). One 7-pair
  `--min-ms 1000` comparison reached median `1.010289x` versus
  `steps256/tg128`, but a second independent 7-pair run fell to median
  `1.003748x` with a `0.915072x` outlier. Keep `steps512` rejected until it can
  clear the gate reproducibly.
- `macos-metal-dp8-inplace-u32-distances` was rejected. It changed only the
  in-place packet kernels' jump-distance table from `constant ulong*` to
  `constant uint*` and added a host distance-fit guard, while preserving the
  accepted `steps256` oracle (`emitted_records=57`,
  `dp_distance_checksum=0x0ab81bcdffe988ca`,
  `dp_checksum=0xbb961e8e4fffeeb0`, `correctness=true`). Paired autoresearch
  against `main` discarded the candidate: final median candidate
  `89,514,131.722479` versus baseline `91,969,442.817225` steps/sec
  (`paired_speedup=0.973303`). The tiny distance table is not the limiting
  memory path for this kernel family on the M3 Air.
- `macos-metal-dp8-inplace-tg128` was accepted. It keeps `steps8` on the
  shared 256-thread default, but defaults in-place DP8 packet sizes
  `steps16+` to `threadgroup_limit=128` unless `--tg-limit` is explicit. Quick
  direct sweeps showed 128 beating 256 for `steps16` (`1.082003x`), `steps32`
  (`1.048231x`), `steps64` (`1.083769x`), `steps128` (`1.089415x`), and
  `steps256` (`1.095482x`), while `steps8` stayed noisy/regressive. Paired
  autoresearch against `main` kept the `steps256` gate with the unchanged
  oracle (`emitted_records=57`,
  `dp_distance_checksum=0x0ab81bcdffe988ca`,
  `dp_checksum=0xbb961e8e4fffeeb0`, `correctness=true`): final candidate
  `98,057,706.925364` versus baseline `91,099,934.341126` steps/sec
  (`paired_speedup=1.076375`, `threadgroup_limit=128`).
- `macos-metal-dp8-inplace-steps16-tg160` was rejected. It tried a narrower
  policy change that defaulted only the `steps16` in-place DP8 packet to
  `threadgroup_limit=160`, keeping all other packet sizes unchanged. The
  oracle stayed intact (`emitted_records=67`,
  `dp_distance_checksum=0x68fbd251ce4fd08e`,
  `dp_checksum=0xdd7021cb96f924c0`, `correctness=true`), but paired
  autoresearch confirmation discarded it. The first two confirmation medians
  regressed at about `0.820x` and `0.734x`; only the final group kept the
  candidate at `67,980,915.994864` versus baseline `62,417,739.448993`
  steps/sec (`paired_speedup=1.089128`). Keep the accepted `steps16+` default
  at 128 threads.
- `macos-metal-dp8-inplace-steps192` was rejected. It inserted a
  non-power-of-two `steps192` kernel between accepted `steps128` and
  `steps256`. Correctness
  held (`emitted_records=74`,
  `dp_distance_checksum=0x72cf07344a308edc`,
  `dp_checksum=0x69bfc127c31638b0`, `correctness=true`). A two-run threadgroup
  sweep showed `--tg-limit 96` as the best `steps192` cap but still below
  accepted `steps256 --tg-limit 128` (`0.984702x`). Five longer
  `--min-ms 500` same-binary pairs measured speedup ratios `0.951722x`,
  `0.966900x`, `0.919687x`, `0.965682x`, and `0.971917x` (median
  `0.965682x`). Do not add `steps192` unless another kernel-shape change moves
  the plateau.
- `macos-metal-dp8-inplace-pipeline-cache` was rejected. It cached the in-place
  DP8 runner's Metal device, library, command queue, and specialized pipeline.
  Correctness stayed identical for the accepted `steps256` oracle
  (`emitted_records=57`,
  `dp_distance_checksum=0x0ab81bcdffe988ca`,
  `dp_checksum=0xbb961e8e4fffeeb0`, `correctness=true`), but paired
  autoresearch discarded the candidate because the official timing window is
  command-buffer execution, not host pipeline setup. Confirmation speedups were
  `0.994935x`, `0.973389x`, and `1.004171x`. Keep pipeline caching out of the
  score path unless the harness grows a separate wall-clock metric.
- `macos-metal-dp8-inplace-steps256-no-unroll` was rejected. It added
  `#pragma clang loop unroll(disable)` before the accepted `steps256` packet
  loop. Correctness and the accepted oracle stayed intact
  (`emitted_records=57`,
  `dp_distance_checksum=0x0ab81bcdffe988ca`,
  `dp_checksum=0xbb961e8e4fffeeb0`, `correctness=true`), but paired
  autoresearch discarded the candidate. Confirmation groups were about
  `0.965x`, `1.003x`, and final `0.993241x` versus `main`. Leave loop shaping
  to the Metal compiler for this packet.
- `macos-metal-dp8-xyzz-packet` was accepted as a separate architecture probe.
  It stores dynamic packet state as `X,Y,ZZ,ZZZ`, updates `ZZ` and `ZZZ`
  directly in the mixed-add formula, and validates against a full CPU XYZZ
  replay oracle rather than reusing the Jacobian oracle. Because the state no
  longer stores `Z`, the partition mixer uses the same avalanche finalizer with
  `ZZ0` in place of `Z0`; the command is reported separately as
  `jacobian_affine_walk_dynamic_dp_stream_xyzz`. Correctness held with
  `emitted_records=66`,
  `dp_distance_checksum=0x8c7a04f6c070c09d`,
  `dp_checksum=0x7dbd6d4ef9312f92`,
  `jump_histogram_max_deviation_ppm=2800`, and `correctness=true`. Paired
  autoresearch, using the new `paired_baseline_command` support to compare
  against main's accepted in-place `steps256` command, kept all three
  confirmations: `1.116496x`, `1.103302x`, and `1.108139x`. Command:
  `./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations
  16384 --steps 256 --jumps 16 --dp-bits 8 --min-ms 200`.

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
- Direct Metal selftest now includes a dp4 `steps=8` infinity-tail vector:
  first jump intentionally produces infinity, then the next affine jump must
  resume to the same finite point as the CPU oracle.
- Close/noisy Metal DP candidates can be rechecked with the stable gate:
  `python3 autoresearch/runner.py --experiment metal_jacobian_jump_walk_dp_stable --budget-sec 10 --paired-baseline-ref main`.
  This uses `--min-ms 200` while preserving the public DP checksum oracle.
- Command-backed autoresearch gates build once per sample set; paired
  confirmation runs build baseline and candidate once each for the whole
  confirmation series, then alternate benchmark commands. Prefer this shape for
  parameter sweeps because it removes repeated phony rebuilds from the timing
  window without changing the benchmark oracle.
- Stable gate baseline at `90697f5`: `40,350,062.636594 ops/sec`,
  `runner_sample_count=3`, `status=keep`, public checksum/DP oracle preserved.

## Handoff Rules

- Use `node ./challenges/rckmetal/bin/rckmetal.js notes add ...` for local
  scratch notes.
- Promote durable findings into this file or `docs/RESEARCH_LOG.md`.
- Do not call a result `verified`, `promoted`, or `replicated` unless a trusted
  external runner reproduces it.
