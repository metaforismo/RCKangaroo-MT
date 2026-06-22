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
- `metal_jacobian_dynamic_walk_dp_stable` now exists as a stable autoresearch
  gate for the dynamic Metal walk. Use it for future in-kernel jump-selection
  experiments after the target exists on both candidate and baseline refs.

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
- Stable gate baseline at `90697f5`: `40,350,062.636594 ops/sec`,
  `runner_sample_count=3`, `status=keep`, public checksum/DP oracle preserved.

## Handoff Rules

- Use `node ./challenges/rckmetal/bin/rckmetal.js notes add ...` for local
  scratch notes.
- Promote durable findings into this file or `docs/RESEARCH_LOG.md`.
- Do not call a result `verified`, `promoted`, or `replicated` unless a trusted
  external runner reproduces it.
