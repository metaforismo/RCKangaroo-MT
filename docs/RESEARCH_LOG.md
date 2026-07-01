# RCKangaroo-MT Research Log

This file is the compact running record for optimization work. Keep it factual:
what changed, what was measured, what was rejected, and which correctness gate
was used. Do not treat an experiment as an improvement unless the oracle passes
and the metric beats the configured baseline gate.

## Current Ground Rules

- Correctness comes before throughput. Every solver or kernel benchmark must
  report `correctness:true` or a clean `skipped:true` when hardware is not
  visible.
- The default local gate is `make macos-check`.
- CPU kangaroo performance candidates use:
  `python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi16_small --budget-sec 5 --paired-baseline-ref main`.
- Metal candidates must be tested on a real Apple Silicon Metal runtime, not
  only inside the restricted sandbox, because sandboxed runs may report
  `no Metal device available`.
- Merge only `keep` results. Remove or leave isolated any experiment that is
  incorrect, slower than the gate, or only noisy.
- Once a candidate passes all required gates, fast-forward it into `main` and
  push it. The next experiment must branch from that updated `main`, making the
  proven result the new baseline.
- Keep rejected work isolated until its lesson is recorded here or in
  `autoresearch/benchmarks.jsonl`.

## Hardware Reference

The local target machine is a MacBook Air M3 with 16 GB RAM and a 10-core Apple
M3 GPU. Metal is available outside the sandbox. CUDA remains NVIDIA-only; macOS
GPU work should use Metal.

## Recent Rejected Or Inconclusive Experiments

### 2026-06-23 Metal Arithmetic And Scheduling Probes

- Rejected a `reduce512_mod_p` normalization shortcut that replaced the final
  loop with two conditional subtractions. Field, Jacobian, `make macos-check`,
  and the public `rckmetal` oracle stayed correct, but paired public DP4
  confirmation ended at about `0.59x`; keep the looped reducer.
- Rejected a public DP4 common-thread no-exception mixed-add helper. The direct
  DP4 checksum oracle stayed correct, but `make macos-check` source gates
  rejected the changed hot-path shape and a longer direct run regressed to about
  `21.2M` ops/sec versus a prior stable baseline around `34.7M`.
- Rejected a square cross-term accumulator that doubled each 128-bit product
  and propagated carry once instead of calling `add128_to_512` twice.
  Correctness and `make macos-check` passed, but paired `metal_field_square`
  confirmation ended at about `0.845x`; keep the two-add spelling.
- Rejected public DP4 implicit distance (`distance += 1UL << jump_index`).
  The public runtime checksum stayed correct, but source gates intentionally
  require the accepted distance-table load shape, and related dynamic/XYZZ
  implicit-distance probes were already slower.
- Rejected promoting a `917504`-state XYZZ `steps512` peak batch. One direct
  scout reached `126.2M` steps/sec, but alternating checks against the
  documented `524288` large batch were not robust; a repeat fell to
  `105.8M`. Keep `524288` as the large-batch probe.
- Rejected promoting a `1048576`-state XYZZ `steps512` peak batch after a fresh
  direct M3 check. It preserved correctness
  (`dp_count=3998`, `dp_distance_checksum=0x5e1ab2b8182ac280`,
  `dp_checksum=0xdc0c6a9f6ce14e9e`, histogram `408 ppm`) and measured
  `122.1M` steps/sec, but the same build's `524288` large batch measured
  `121.6M` with roughly half the validation wall time. The `1.0045x` kernel
  gain is below the promotion threshold; keep `524288`.
- Rejected a fresh XYZZ `steps512` large-batch threadgroup retune. At
  `524288` samples, default `threadgroup_limit=128` measured `121.6M`
  steps/sec with `dp_distance_checksum=0x7325bd945494b7be` and
  `dp_checksum=0x390f891179fdcbea`; `--tg-limit 256` measured `121.2M`, and
  `--tg-limit 64` measured `120.8M` with the same oracle. Keep `128`.
- Rejected a full-threadgroup-only XYZZ `steps512` kernel variant that removed
  the `id >= count` guard and was selected only when the sample count was an
  exact multiple of the chosen threadgroup width. Correctness held for both the
  full batch and a non-multiple fallback (`524288` and `524287` samples), but
  fullgroups measured `120.6M` and `120.5M` steps/sec while the near-identical
  fallback measured `121.0M`. The guard is not the bottleneck; keep the single
  guarded kernel.
- Rejected promoting intermediate XYZZ `steps512` batch sizes. `655360`
  samples preserved correctness
  (`dp_distance_checksum=0x43d27ba89808145e`,
  `dp_checksum=0x4d4affa22a48e388`) and initially measured `122.3M` steps/sec
  versus a same-binary `524288` check at `121.9M`, but a repeat fell to
  `121.3M`; `786432` measured `121.9M`. Keep the established `524288`
  large-batch gate.
- Accepted an explicit experimental `scaled4-balanced` jump schedule for bench
  exploration. The schedule uses four jumps `{1, 2, 8192, 8193}`, preserving
  gcd `1` and roughly the same mean scalar advance as the 16-entry power-of-two
  schedule. It is opt-in via `--jump-schedule scaled4-balanced`; default
  behavior remains `power2`. CPU tiny multi-target probes with
  `target_count=16`, `range=20`, `dp_bits=4`, `jumps=4` preserved correctness
  and reduced `avg_dp_count` to `7611` versus `191461` for `jumps=16 power2` on
  the same deterministic fixture. Autoresearch kept the first CPU schedule
  benchmark at median `31.011318 ops/sec`; a same-code repeat preserved
  correctness but was marked discard at median `30.433391 ops/sec`, so do not
  claim CPU throughput from this probe yet. The Metal XYZZ large-batch schedule
  benchmark also preserved correctness
  (`dp_distance_checksum=0x3ea0b5a3cd958a70`,
  `dp_checksum=0x564364b08c72a1da`) with kept medians
  `123,234,598.455869` and `125,874,951.286111` steps/sec, roughly
  kernel-parity to slightly above the nearby `jumps=16 power2` checks. Treat
  this primarily as a solver-facing math/schedule candidate, not as a proven
  per-step GPU micro-optimization. A clean 2026-06-25 repeat at commit
  `f53621c` preserved the same Metal oracle but was discarded at median
  `117,076,522.598601` steps/sec, reinforcing that `scaled4-balanced` should
  not be promoted as a raw M3 walk-throughput win.
- Rejected a temporary `xorfold` XYZZ 512-step jump mixer probe. The idea was
  to replace the per-step avalanche multiply with shifts/xors while keeping the
  CPU replay oracle identical. It preserved correctness and had acceptable jump
  balance (`528 ppm` for `jumps=16 power2`, `83 ppm` for `scaled4-balanced`),
  but measured only `119.2M` steps/sec for `jumps=16 power2` and `122.4M`
  steps/sec for `scaled4-balanced`, below the nearby avalanche64 runs
  (`~124-126M`). The partition mixer is not the current M3 bottleneck.
- Rejected changing the `scaled4-balanced` XYZZ 512-step default threadgroup
  cap from `128` to `32`. A sequential sweep found one high `tg=32` sample at
  `127.7M` steps/sec, but repeats landed at `124.2M` and `125.7M`; `tg=64`,
  `96`, `128`, and `160` were all in the same noisy band. Keep the inherited
  `128` default and use explicit `--tg-limit` only for local tuning.
- Rejected alternate four-jump CPU schedule probes around `scaled4-balanced`.
  `{1,2,4096,4097}` preserved correctness but exploded the 16-target
  `range=20`, `dp_bits=4` oracle to `avg_dp_count=291801`; `{1,2,16384,16385}`
  preserved correctness but measured `22885`; `{1,2,12288,12289}` failed the
  single-target reference; `{1,1024,4096,11267}` was close but still worse at
  `8216`; `{1,512,4096,11779}` was much worse at `171387`. Keep
  `{1,2,8192,8193}` as the best tested four-jump schedule.
- Accepted `--key-offset` for CPU kangaroo bench fixtures so schedule probes no
  longer depend only on the historical near-lower-bound key `0x7`. The option
  clamps the requested offset inside the bounded range and reports the actual
  `key_offset` in JSON. While adding it, the multi-target single-reference
  oracle was corrected to use the same `start` and fallback offset as the
  multi-target fixture instead of anchoring the reference at scalar zero. A
  varied-position sweep with `target_count=16`, `range=20`, `dp_bits=4`,
  `max_steps=2000000` preserved correctness for `scaled4-balanced` at offsets
  `5`, `262144`, `524288`, and `786432`, measuring `avg_dp_count` `7611`,
  `37409`, `3032`, and `3081`. The same offsets with `jumps=16 power2`
  measured `191461`, `268652`, `14001`, and `53811`. This supports
  `scaled4-balanced` as a real schedule candidate beyond the original `0x7`
  fixture, while also showing strong phase sensitivity in the walk.
- Accepted `--jump-schedule` plumbing for Metal XYZZ chain and persistent-chain
  benches so the solver-facing cumulative-distance GPU paths can validate the
  same schedules as the single-packet XYZZ bench. Defaults remain `power2`;
  `scaled4-balanced` is still gated to `--jumps 4` and is reported in JSON.
  Correctness held for `steps=512`, `packets=2`, `dp_bits=8`, `tg=128` chain
  and for the matching persistent-chain `packets=2`, `rounds=2` probe. Do not
  promote it as a chain throughput win: chain measured `123.7M` steps/sec for
  `jumps=16 power2` versus `120.1M` for `scaled4-balanced`, and
  persistent-chain measured `126.6M` versus `118.8M`. The useful result is
  broader schedule correctness coverage plus a measured negative speed result.
- Rejected treating smaller jump tables as a solver improvement from raw Metal
  throughput alone. On the synthetic XYZZ kernel benchmark, `jumps=4` measured
  `125.4M` steps/sec versus `jumps=16` around `121.9M`, with correctness
  intact. However the current distances are `1 << i`, so `jumps=4` has a much
  smaller average scalar advance than `jumps=16`; this is not a fair
  time-to-solution improvement. The promising follow-up is a small table with a
  scaled distance/point schedule, validated by a solver oracle, not a raw
  `steps/sec` promotion.
- Retested persistent XYZZ schedule `packets x rounds` at total four packets.
  `1 x 4` and `2 x 2` preserved identical DP count/checksums, but timings
  flipped by run order (`2 x 2` then `1 x 4`: `123.6M` vs `125.1M`; reverse:
  `124.1M` vs `124.8M`). Keep the balanced `2 x 2` default.
- Rejected CPU tiny multi-target implicit jump distance after paired
  autoresearch confirmation. Replacing the jump-distance table load with
  `1 << jump_index` preserved all small single/multi-target correctness oracles,
  but the final paired result was only `1.000604x` and confirmation discarded
  the candidate. Keep the explicit table load, which also leaves room for
  non-power-of-two jump schedules.
- Rejected Metal XYZZ chain cumulative-distance early load. Moving
  `cumulative_distances[id]` before the 256/512-step inner loop preserved
  `emitted_records=2016`,
  `dp_distance_checksum=0x7a221c62b92a5ed3`, and
  `dp_checksum=0x23509000c8141686`, but the paired chain512 scout measured
  `0.979056x`. The extra long-lived scalar likely increases register pressure;
  keep the late cumulative-distance load/store.
- Rejected CPU distinguished-point table hash no-avalanche. Returning the base
  `KangarooPointKeyHash` directly preserved the tiny multi-target oracle and one
  raw paired run showed `1.013091x`, but the three-run confirmation still
  discarded it as non-durable. Keep the secondary avalanche in `IndexHash` for
  stable probe distribution.
- Rejected CPU kangaroo precomputed jump-mode metadata. Adding `count`, `mask`,
  and `power_of_two` to the jump table and using them in `KangarooStep`
  preserved single/multi-target correctness (`found_private_key=0x7`,
  `found_target_index=3`, `last_dp_count=84`), but the three-run paired
  confirmation discarded the candidate. The final visible run was only
  `1.010945x`, and earlier confirmation medians missed the 1% gate or
  regressed. Keep the simpler `JacobianJumpIndex(..., jumps.points.size())`
  path.
- Rejected CPU specialized `SqrModP` for Jacobian field squares. A 10-product
  square accumulator with explicit carry propagation matched `MulModP(a)` in a
  direct selftest and preserved the multi-target oracle, but paired
  autoresearch ended at `0.993911x` versus `main`. The reduction in limb
  products did not pay for the added carry-propagation/codegen shape on the M3
  CPU; keep square as `MulModP` with a copied operand.

## Accepted Results

### CUDA Per-Thread LoopTable Indexing

Accepted: 2026-06-30.

- Fixed `KernelB` loop-history load/store indexing from `BLOCK_X` to
  `THREAD_X` for the final `LoopTable` lane offset.
- The `LoopTable` layout is block, group-pair, history slot, and thread lane.
  Using the CUDA block index as the final lane made threads inside a block
  share a small set of loop-history slots instead of preserving independent
  per-kangaroo history. That can create races and weaken loop detection on the
  real CUDA solver path.
- This does not change jump distances, distinguished-point selection,
  target-id propagation, collision equations, host DB filtering, or final
  full-point verification. It repairs per-thread state ownership in the kernel.
- Added a source gate and a CPU-only structural layout test so the CUDA loop
  table cannot regress back to block-index lane addressing. Runtime throughput
  still needs NVIDIA replication before claiming a measured GKeys/s, MKeys/s,
  or solved-targets-per-hour gain.

### CUDA Multi-Target Active Window Cycling

Accepted: 2026-06-30.

- Added opt-in `-target-cycle-rounds N` for huge CUDA multi-target runs where
  `target_count` exceeds the active WILD1/WILD2 population. After every `N`
  CUDA rounds, each GPU regenerates kangaroo start points and `target_id`
  assignments for the next active target window.
- This is a production solver-path feature, not a benchmark-only change. It
  uses the existing `KernelGen` start-point path, leaves collision equations,
  distinguished-point records, host DB storage, target-aware filtering, and
  final full-point verification unchanged, and resets only per-GPU loop history
  for the newly generated starts.
- A follow-up tightened the cycle reset so it preserves the universal tame
  walks and copies only the WILD1/WILD2 start ranges for later target windows.
  `KernelGen` still rebuilds coherent points from the device distances, but the
  cycle no longer replaces tame distances or abandons tame coverage just to
  move the wild target window.
- A second follow-up passed a `wild_only` flag into `KernelGen`, so cycle
  resets skip the tame kangaroo range inside the CUDA start-point kernel instead
  of spending scalar-multiplication work on tame points that are already
  continuing correctly on the GPU.
- A third follow-up added a CUDA wild-loop-state reset kernel for target
  cycling. Cycle resets now clear only WILD1/WILD2 `L1S2` bits and `LoopTable`
  history, leaving tame loop history intact along with tame points and
  distances. The host layout test models the `KernelB` kangaroo permutation for
  both new-GPU and old-GPU geometry so this selective reset cannot silently miss
  or duplicate a kangaroo partition.
- Already collected DPs remain in the host DB because wild DPs carry the target
  id that was active when they were emitted. This keeps old target evidence
  valid while future windows cover target ids that would otherwise remain
  inactive in a single start cycle.
- Added pure mapping helpers
  `MapCycledActiveWildTargetId` and `CoverageCycleCount` plus host tests for
  divisible and non-divisible target windows. The source gate now verifies that
  the CLI option, `SolvePoint -> Prepare` plumbing, and GPU reset path remain
  wired together.
- This does not claim a measured MKeys/s gain. It improves real target-file
  coverage for large multi-target runs; the best `N` depends on DP value, range,
  GPU speed, and restart overhead and still needs NVIDIA replication before
  making throughput claims.

### CUDA Multi-GPU Multi-Target Sharding

Accepted: 2026-06-30.

- Production CUDA multi-target starts now compute global WILD1 and WILD2 active
  target offsets across enabled GPUs and pass those offsets into
  `RCGpuKang::Prepare`. `RCGpuKang::Start` maps each wild start through
  `TTargetSet::MapActiveWildTargetId`, so multi-GPU runs shard active target
  assignment instead of repeating each GPU's local target slice.
- This is a solver-path change, not a benchmark-only optimization. It affects
  the normal `SolvePoint -> Prepare -> Start` CUDA path used by `-targets`.
  Single-GPU target assignment is unchanged, and the collision equations,
  `target_id` propagation, DP table, and final full-point verification remain
  unchanged.
- The startup log now reports `Multi-target active shard coverage`. If the
  target file exceeds the active WILD1/WILD2 population, the log explicitly
  says that only the deterministic active shard is covered in the current start
  cycle; target cycling/reassignment is the next real solver improvement for
  target files much larger than the active wild population.
- Correctness gates added: `check-target-assignment` verifies the host mapping
  invariants, and `tests/check_multi_target_sharding_source.py` verifies that
  the production CUDA path still computes/passes sharding offsets. CUDA
  throughput must still be replicated on NVIDIA hardware before making a
  measured MKeys/s or solved-targets-per-hour claim.

### CPU Kangaroo Unit-Z First-Step Affine Conversion

Accepted: 2026-06-23.

- The bounded CPU tiny kangaroo solvers now special-case step zero when
  converting Jacobian walk states to affine. Tame and wild states are created
  directly from affine points, so their Jacobian `Z` coordinate is exactly
  one; the first affine view can therefore copy `x/y` directly instead of
  spending an inversion or a batch inversion setup.
- This does not change the kangaroo walk, distinguished-point predicate,
  DP table, collision verification, range checks, target-index checks, jump
  table, or later batch-affine conversions. From step one onward the existing
  batch conversion remains the active path.
- The solvers and benchmarks now report
  `affine_initial_conversion=unit_z_copy` alongside the existing
  `affine_conversion=batch` marker.
- Correctness gates passed:
  `sh tests/check_jacobian_kangaroo_small_cli.sh`,
  `sh tests/check_jacobian_kangaroo_multi_small_cli.sh`,
  `sh tests/check_jacobian_kangaroo_small_bench_cli.sh`,
  `sh tests/check_jacobian_kangaroo_multi_small_bench_cli.sh`, and
  `make macos-check`.
- Paired autoresearch against `main` kept the candidate on the local M3 Air:
  `jacobian_kangaroo_multi_small --budget-sec 8 --confirm-runs 3` ended at
  `35740.492125` candidate ops/sec versus `34767.542094` baseline
  (`paired_speedup=1.027984`, `confirmation_status=keep`,
  `found_private_key=0x7`, `found_target_index=3`, `last_dp_count=84`);
  `jacobian_kangaroo_multi16_small --budget-sec 8 --confirm-runs 3` ended at
  `16135.468515` candidate ops/sec versus `15768.725361` baseline
  (`paired_speedup=1.023258`, `confirmation_status=keep`,
  `found_private_key=0x7`, `found_target_index=15`, `last_dp_count=288`).

### Quality Gates

- Added `docs/QUALITY_GATES.md` and `docs/QUALITY_GATES.it.md`.
- Added `tests/check_quality_gates.sh`.
- Wired quality-gate checks into `make macos-check`.
- The gate now documents target, allowed edits, correctness oracle, performance
  metric, baseline comparison, hidden tests, reproducibility, logging,
  submission, and rollback.

### Metal Benchmark Stabilization

- Metal field benchmarks accept `--min-ms`.
- JSON reports `sample_count`, `min_ms`, total `iterations`, `ops_per_sec`,
  `correctness`, and `skipped`.
- This reduces short-dispatch timing noise and lets CI skip cleanly when Metal
  is not visible.
- Added `metal_jacobian_jump_walk_dp_stable`, a long-window autoresearch gate
  for the public Metal DP shape. It keeps the same correctness oracle as the
  primary DP gate but runs `--min-ms 200` through
  `macos-metal-jacobian-jump-walk-dp-stable-bench` for close or noisy
  candidates.
- Seeded stable baseline at `90697f5`: median `40,350,062.636594 ops/sec`,
  `status=keep`, `runner_sample_count=3`, public checksum/DP oracle preserved.
- Command-backed autoresearch probes now build once per sample set. Paired
  confirmation runs build the baseline and candidate worktrees once for the
  whole confirmation series, then alternate benchmark commands. This does not
  change any solver math or oracle; it reduces phony Make rebuild time, heat,
  and scheduling noise before the measured Metal dispatches.
- Autoresearch experiments now support `cooldown_sec`, sleeping between
  samples without sleeping after the last sample. The long XYZZ persistent-chain
  gate sets `cooldown_sec=10` after M3 Air runs showed severe thermal
  throttling on immediate repeats. This improves reproducibility of future
  paired decisions and does not affect benchmark commands, JSON oracles, or
  solver code.
- First cooled control run for
  `metal_jacobian_dynamic_dp_stream_xyzz_persistent_chain_steps512` at
  `ebd6cb6` recorded `status=discard`: persistent-chain median
  `56,698,747.713128` steps/sec versus paired generic-chain baseline
  `63,930,187.480298`, with `cooldown_sec=10` and unchanged
  `dp_distance_checksum=0x30e91a5edffed133` /
  `dp_checksum=0x950a1186dae66384`. Treat this as a reproducibility warning for
  the long validation-heavy gate, not as an automatic rollback of the accepted
  persistent-chain command; use shorter paired probes or repeated cooled
  confirmations before changing defaults.
- Converted the public stable DP gate to `build_target=macos-build` plus an
  explicit `bench_command`, so future stable paired runs use the build-once
  path without adding one-off Make targets.
- Converted the core Metal field add, multiply, square, and fused square-mul
  autoresearch gates to the same command-backed build-once path. A
  `metal_field_add` smoke run on the local M3 built once, ran three direct
  samples, kept the CPU oracle (`correctness=true`), and recorded median
  `225,377,938.159104 ops/sec`.
- Converted the stable DP8 dynamic stream gate to `build_target=macos-build`
  plus an explicit `bench_command`. The first smoke run preserved the DP8
  stream oracle (`emitted_records=61`,
  `dp_distance_checksum=0x822e141de4770a0b`,
  `dp_checksum=0xab1c2cd29cd70a84`) and recorded median
  `67,169,019.394725` steps/sec with one build followed by three direct
  samples.
- Accepted `macos-metal-dp-stream-emitted-copy`: the host DP stream readers now
  copy only the dense emitted prefix from Metal output buffers instead of the
  full `dp_capacity` arrays, preserving overflow handling and the sparse stream
  oracle. This is a host-side cleanup, not a kernel speed claim. On a copy-bound
  sparse case (`metal-jacobian-dynamic-dp-stream-bench --iterations 1048576
  --steps 8 --jumps 8 --dp-bits 16 --min-ms 1`), baseline/candidate real times
  were `0.67s/0.52s` and `0.54s/0.51s`; both preserved
  `emitted_records=20`, `dp_distance_checksum=0x922cdf80931679e6`, and
  `dp_checksum=0xb2b3088fcf6ad384`. On the persistent XYZZ `131072 x 512 x 4`
  case, checksums were unchanged but validation time stayed dominated by CPU
  replay, so this is promoted as less host memory traffic for sparse streams.
- Added `metal_jacobian_dynamic_dp_stream_inplace`, a DP8 Metal stream kernel
  that updates each Jacobian state in-place on the GPU while emitting only
  sparse DP records. The oracle verifies both the DP stream and the final raw
  Jacobian `x/y/z/inf` state against CPU replay. Autoresearch recorded median
  `67,315,699.992225` steps/sec with `correctness=true`,
  `emitted_records=61`,
  `dp_distance_checksum=0x822e141de4770a0b`, and
  `dp_checksum=0xab1c2cd29cd70a84`. Manual alternating probes versus DP8
  `dynamic-walk` full-output measured `1.125972x` paired median over three
  pairs, `1.099271x` paired median over five noisier pairs, and `1.866489x`
  paired median over three `--min-ms 500` pairs. Against pure DP8 stream,
  absolute median was near parity (`0.986428x`) and paired median was noisy, so
  treat this as a state-preserving primitive for persistent GPU walks, not a
  replacement for pure sparse-stream scoring.
- Added `metal_jacobian_dynamic_dp_stream_inplace_steps16`, a second in-place
  DP8 stream packet that performs 16 dynamic Jacobian jumps per Metal thread
  before storing the state and checking/emitting a DP record. This amortizes the
  same state load/store over more group operations while preserving the CPU
  replay oracle for both the emitted DP stream and final `x/y/z/inf` state.
  Autoresearch ran three confirmation groups with three samples each and kept
  the candidate at median `76,531,591.057923` steps/sec,
  `correctness=true`, `emitted_records=67`,
  `dp_distance_checksum=0x68fbd251ce4fd08e`, and
  `dp_checksum=0xdd7021cb96f924c0`. A same-binary alternating comparison
  against the existing in-place `steps=8` packet measured `1.085387x` median
  speedup over five `--min-ms 200` pairs; a longer three-pair `--min-ms 500`
  probe was noisy but still positive at `1.087669x` median, with one negative
  pair. Treat `steps16` as a longer packet-size option for persistent walks; it
  checks the DP predicate at the packet boundary, not at every intermediate
  step.
- Added `metal_jacobian_dynamic_dp_stream_inplace_steps32`, extending the same
  state-preserving packet idea to 32 dynamic jumps per Metal thread. The CPU
  oracle verifies the 32-step DP stream and final state. Three autoresearch
  confirmation groups kept the candidate at median `78,549,463.782889`
  steps/sec, `correctness=true`, `emitted_records=61`,
  `dp_distance_checksum=0xa31eaba41f549318`, and
  `dp_checksum=0x751402be27e58082`. Alternating comparison against the accepted
  `steps16` packet measured `1.080838x` median speedup over five `--min-ms
  200` pairs and `1.475099x` median over three `--min-ms 500` pairs. Treat
  `steps32` as the faster local packet-size option so far, with the same
  packet-boundary DP sampling semantics as `steps16`.
- Added `metal_jacobian_dynamic_dp_stream_inplace_steps64`, extending the
  packet-size ladder to 64 dynamic jumps per Metal thread. Three autoresearch
  confirmation groups kept it at median `90,119,567.579470` steps/sec,
  `correctness=true`, `emitted_records=54`,
  `dp_distance_checksum=0x132b1b39482c3732`, and
  `dp_checksum=0xc4c55fe6a6308d32`. Alternating comparison against `steps32`
  measured `1.085726x` median speedup over five `--min-ms 200` pairs and
  `1.094047x` median over three `--min-ms 500` pairs. `steps64` is the fastest
  local in-place DP8 packet so far, still with DP predicate checks only at
  packet boundaries.
- Added `metal_jacobian_dynamic_dp_stream_inplace_steps128`, a larger packet
  probe that is now close to the local plateau. Autoresearch kept it with
  `correctness=true`, `emitted_records=68`,
  `dp_distance_checksum=0x2b611389e103e188`,
  `dp_checksum=0xc9e5a3440ffdb698`, and final median
  `90,611,211.497293` steps/sec. Paired comparison against `steps64` measured
  `1.013988x` median over five `--min-ms 200` pairs and `1.022074x` median
  over five `--min-ms 500` pairs. This is a valid packet-size option, but the
  gain over `steps64` is modest; further packet increases should be treated as
  plateau probes, not assumed wins.
- Added `metal_jacobian_dynamic_dp_stream_inplace_steps256`, continuing the
  packet-size ladder as a plateau probe with the same packet-boundary DP
  semantics. Autoresearch kept three confirmation groups with
  `correctness=true`, `emitted_records=57`,
  `dp_distance_checksum=0x0ab81bcdffe988ca`,
  `dp_checksum=0xbb961e8e4fffeeb0`, and final median
  `89,960,529.450509` steps/sec. Same-binary comparison against `steps128`
  measured `1.054086x` median over five `--min-ms 200` pairs and `1.058103x`
  median over three `--min-ms 500` pairs. Because the raw autoresearch median
  sits slightly below the noisy `steps128` median, treat `steps256` as an
  accepted packet-size option and evidence of the plateau, not as an
  unconditional new fastest default.
- Tuned the in-place DP8 packet dispatch default: `steps=16` and larger now
  use `threadgroup_limit=128` unless `--tg-limit` is provided. Direct sweeps on
  the accepted code showed 128 beating 256 for `steps16` (`1.082003x`),
  `steps32` (`1.048231x`), `steps64` (`1.083769x`), `steps128`
  (`1.089415x`), and `steps256` (`1.095482x`), while `steps8` stayed too noisy
  and remains on the 256 default. Paired autoresearch against `main` kept the
  `steps256` candidate with the same oracle (`emitted_records=57`,
  `dp_distance_checksum=0x0ab81bcdffe988ca`,
  `dp_checksum=0xbb961e8e4fffeeb0`, `correctness=true`) and final median
  `98,057,706.925364` candidate versus `91,099,934.341126` baseline steps/sec
  (`paired_speedup=1.076375`, `threadgroup_limit=128`).

### Metal Dispatch Size Tuning

Commit: `bbde2c8` (`perf: tune Metal field dispatch size`)

- Changed Metal field dispatches from one execution-width group to a larger
  SIMD-aligned threadgroup, capped at 256 threads.
- Benchmarks now report:
  `threadgroup_limit`, `thread_execution_width`,
  `max_threads_per_threadgroup`, `threads_per_threadgroup`.
- On the local M3 run, Metal reported `thread_execution_width=32`,
  `max_threads_per_threadgroup=1024`, and `threads_per_threadgroup=256`.
- Paired autoresearch against `main`:
  - `metal_field_square`: `120,182,161.633272 ops/sec`, `1.054411x`,
    `status=keep`, `correctness=true`.
  - `metal_field_mul`: `110,169,933.604968 ops/sec`, `1.127512x`,
    `status=keep`, `correctness=true`.
  - A second `metal_field_mul` paired rerun under noisier conditions still kept
    the candidate: `107,181,958.674000 ops/sec`, `1.045700x`,
    `status=keep`, `correctness=true`.

### Fused Square-Mul Field Kernel

Commit: `bbde2c8` (`perf: tune Metal field dispatch size`)

- Added `field_square_mul_mod_p`, computing `(a * a) * b mod p` in one Metal
  dispatch.
- Added CLI commands:
  - `metal-field-square-mul-test`
  - `metal-field-square-mul-bench --iterations N [--min-ms N]`
- Added `autoresearch/experiments/metal_field_square_mul.json`.
- Autoresearch first record:
  - `116,411,049.047869 ops/sec`
  - `status=keep`
  - `correctness=true`
  - `skipped=false`
- Early pre-tuning measurements showed that fusing alone was not automatically
  faster. The useful result is the combination of a real fused oracle plus the
  larger threadgroup dispatch shape.

### Metal Jacobian-Plus-Affine Add Kernel

Commit: `07615a1` (`feat: add Metal Jacobian affine add kernel`)

- Added the first point-level Apple Silicon GPU primitive,
  `jacobian_add_affine`.
- The kernel consumes packed Jacobian `x/y/z` plus an input infinity flag and
  affine `x/y`, then emits packed Jacobian `x/y/z` plus an output infinity flag.
- The self-test and benchmark cover generic additions, `p` infinity, doubling
  (`h=0,r=0`), and point-at-infinity (`h=0,r!=0`) branches.
- Added CLI commands:
  - `metal-jacobian-add-test`
  - `metal-jacobian-add-bench --iterations N [--min-ms N] [--tg-limit N]`
- Added `autoresearch/experiments/metal_jacobian_add.json` with three runner
  samples.
- Local M3 autoresearch result:
  - median `18,987,732.357266 ops/sec`
  - min `16,122,729.006089 ops/sec`
  - max `23,145,877.471189 ops/sec`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Fixed-Step Metal Jacobian Walk Kernel

Commit: `74d6dad` (`feat: add Metal fixed-step Jacobian walk`)

- Added `jacobian_affine_walk_fixed`, a walk-core Metal primitive that keeps one
  Jacobian state inside a GPU thread and applies the same affine mixed-add step
  repeatedly before writing the final state.
- This is not a full kangaroo kernel yet: it intentionally excludes variable
  jump selection, distinguished-point filtering, and collision-table work.
- Added CLI commands:
  - `metal-jacobian-walk-test`
  - `metal-jacobian-walk-bench --iterations N [--steps N] [--min-ms N] [--tg-limit N]`
- Added `autoresearch/experiments/metal_jacobian_walk.json` with three runner
  samples.
- Local M3 autoresearch result with `steps_per_sample=8`:
  - median `43,635,268.698477 mixed-add steps/sec`
  - min `39,216,303.440935 mixed-add steps/sec`
  - max `43,712,057.290467 mixed-add steps/sec`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Metal Jacobian Jump-Table Walk Kernel

Commit: `2c2c9b5` (`feat: add Metal Jacobian jump-table walk`)

- Added `jacobian_affine_walk_jump_table`, a variable-jump walk primitive that
  keeps one Jacobian state inside each Metal thread, reads a deterministic
  per-sample and per-step jump index, selects from an affine jump table, and
  writes the final Jacobian state.
- Added CPU replay oracle for the exact same jump-index sequence, so the
  benchmark verifies correctness rather than only measuring dispatch speed.
- This is still not a full kangaroo kernel: it intentionally excludes
  distinguished-point filtering, scalar-distance accumulation, and
  collision-table writes. Those are the next correctness surfaces.
- Added CLI commands:
  - `metal-jacobian-jump-walk-test`
  - `metal-jacobian-jump-walk-bench --iterations N [--steps N] [--jumps N] [--min-ms N] [--tg-limit N]`
- Added `autoresearch/experiments/metal_jacobian_jump_walk.json` with three
  runner samples.
- Local M3 autoresearch result with `steps_per_sample=8` and `jump_count=16`:
  - median `29,322,230.463689 mixed-add steps/sec`
  - min `24,300,650.024927 mixed-add steps/sec`
  - max `37,278,370.994648 mixed-add steps/sec`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Direct Metal Jump Indices

Commit: `c41c6d7` (`perf: use direct Metal jump indices`)

- Removed the per-step `% jump_count` from the Metal jump-table walk hot loop.
- Kept correctness strict by validating on the host that every generated
  `jump_indices` entry is already inside the affine jump table before dispatch.
- Updated the Metal source gate so future changes do not accidentally reinsert
  a modulo in the kernel loop.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk`, `steps_per_sample=8`, `jump_count=16`:
  - candidate median `38,210,997.361683 mixed-add steps/sec`
  - paired baseline median `35,711,313.723010 mixed-add steps/sec`
  - paired speedup `1.069997x`
  - min `25,910,772.852663 mixed-add steps/sec`
  - max `39,764,446.199153 mixed-add steps/sec`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Metal Jump-Walk Distance Accumulation

Commit: `1d8455d` (`feat: track Metal jump-walk distances`)

- Added a 64-bit jump-distance table and per-sample distance output to
  `jacobian_affine_walk_jump_table`.
- The CPU oracle now verifies both the final Jacobian point and accumulated
  scalar distance for the exact same jump-index sequence.
- Bench JSON includes `distance_tracking=uint64` and `distance_checksum`, so
  future Metal changes cannot silently drop distance state while preserving
  point output.
- This removes one blocker for a full Metal kangaroo loop. Distinguished-point
  filtering and collision-table writes are still intentionally outside this
  kernel.
- Local M3 autoresearch result with `steps_per_sample=8` and `jump_count=16`:
  - median `30,127,453.595735 mixed-add steps/sec`
  - min `24,629,646.294400 mixed-add steps/sec`
  - max `37,741,158.058549 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Metal Projective DP Candidate Flags

Commit: `31c38cf` (`feat: emit Metal jump-walk DP candidates`)

- Added optional `--dp-bits N` to the Metal jump-table walk benchmark.
- The kernel emits one projective distinguished-point candidate flag per final
  walk state using low bits of projective `x[0]`.
- The CPU oracle verifies point, distance, and the exact same projective DP
  predicate. This is intentionally not yet an affine DP key or collision-table
  insert path.
- Bench JSON includes `dp_tracking=projective_x_limb0`, `dp_bits`,
  `dp_count`, and `dp_checksum`.
- Local M3 autoresearch result with `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - median `35,573,689.248061 mixed-add steps/sec`
  - min `29,957,098.382191 mixed-add steps/sec`
  - max `36,883,132.894670 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Precomputed Metal DP Mask

Commit: `99ea964` (`perf: precompute Metal DP mask`)

- Moved the projective distinguished-point mask calculation out of the
  `jacobian_affine_walk_jump_table` kernel and into the host dispatch path.
- Buffer 10 now carries a precomputed `uint64_t`/Metal `ulong` mask instead of
  `dp_bits`, preserving the `dp_bits=0` semantics where every finite point is a
  candidate while removing a branch and shift from every GPU thread.
- The CPU oracle uses the same `ProjectiveDpMask` helper, so GPU output and
  verification remain locked to the same predicate.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `36,056,697.229186 mixed-add steps/sec`
  - paired baseline median `33,537,315.709809 mixed-add steps/sec`
  - paired speedup `1.075122x`
  - candidate min `27,685,884.633058 mixed-add steps/sec`
  - candidate max `38,595,363.397466 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Precomputed Metal Jump Index Base

Commit: `2ba6704` (`perf: precompute Metal jump index base`)

- Moved `id * steps` out of the `jacobian_affine_walk_jump_table` loop and
  reused `jump_base + step` for each jump-index load.
- The source gate now rejects reintroducing the per-step `id * steps + step`
  address calculation while also preserving the no-hot-modulo and precomputed
  DP-mask checks.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `36,123,063.713799 mixed-add steps/sec`
  - paired baseline median `29,592,623.352879 mixed-add steps/sec`
  - paired speedup `1.220678x`
  - candidate min `23,157,880.850366 mixed-add steps/sec`
  - candidate max `46,746,041.618214 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`
  - Note: this run was noisy, but the paired median still cleared the configured
    keep gate.

### Reused Metal Output Base

Commit: `048c827` (`perf: reuse Metal output base`)

- Reused `p_base` as `out_base` inside `jacobian_affine_walk_jump_table` because
  the packed input and output Jacobian layouts use the same 12-limb stride.
- The Metal source gate now rejects a second `id * 12` calculation in the jump
  walk kernel while keeping the previous jump-index and DP-mask hot-path guards.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `32,951,131.617042 mixed-add steps/sec`
  - paired baseline median `29,806,708.480270 mixed-add steps/sec`
  - paired speedup `1.105494x`
  - candidate min `23,577,104.868518 mixed-add steps/sec`
  - candidate max `39,231,627.754174 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`
  - Note: measured throughput is still noisy on the local MacBook Air, but this
    candidate cleared the paired keep gate and preserved every oracle field.

### Shifted Metal Q-Table Base

Commit: `dc2d1dd` (`perf: use shift for Metal q base`)

- Changed the affine jump-table base calculation from `jump_index * 8` to
  `jump_index << 3` inside `jacobian_affine_walk_jump_table`.
- This is mathematically identical for the packed affine table stride, but the
  source gate now makes the intended power-of-two addressing explicit.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `26,896,574.393133 mixed-add steps/sec`
  - paired baseline median `20,301,093.835039 mixed-add steps/sec`
  - paired speedup `1.324883x`
  - candidate min `23,151,973.252512 mixed-add steps/sec`
  - candidate max `27,558,986.411632 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`
  - Note: absolute throughput was lower than some earlier local runs, but the
    paired median kept the candidate and all oracle fields matched.

### Specialized Metal Steps8 Jump-Walk Kernel

Commit: `7acdc28` (`perf: add Metal steps8 jump-walk kernel`)

- Added `jacobian_affine_walk_jump_table_steps8`, selected only when
  `steps_per_sample == 8`. Other step counts keep using the generic
  `jacobian_affine_walk_jump_table` kernel.
- The specialized kernel preserves the same buffer layout and oracle fields,
  but uses a fixed 8-step hot loop and `id << 3` for the jump-index base.
- The Metal source gate now requires both the generic fallback and the
  specialized fixed-step path, including distance accumulation and projective
  DP flag checks.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `38,243,083.846592 mixed-add steps/sec`
  - paired baseline median `34,828,506.038031 mixed-add steps/sec`
  - paired speedup `1.098040x`
  - candidate min `36,303,991.961639 mixed-add steps/sec`
  - candidate max `42,489,642.760573 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Metal Steps4 Autoresearch Gate

Commit: `ed85c67` (`feat: add Metal steps4 autoresearch gate`)

- Added `metal_jacobian_jump_walk_dp_steps4` as a dedicated autoresearch
  experiment for `--steps 4`, keeping it separate from the primary Benchforge
  `--steps 8` score path.
- This lets shorter-walk specializations be judged with a paired baseline
  instead of relying on incidental CLI smoke numbers.
- Initial local M3 baseline:
  - median `21,861,586.351139 mixed-add steps/sec`
  - min `16,544,339.465934 mixed-add steps/sec`
  - max `23,467,683.404390 mixed-add steps/sec`
  - `distance_checksum=0xb1541b7a21f2fdb4`
  - `dp_count=1030`
  - `dp_checksum=0x1943a969ca1127a0`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Constant Metal Jump Tables

Commit: `ba91503` (`perf: use constant Metal jump tables`)

- Changed the jump-walk kernels to read the small affine jump table (`q_xy`) and
  jump-distance table from Metal `constant` address space.
- Kept `jump_indices` in `device const` because it is large and varies by
  sample/step; this experiment only targets the compact read-only tables.
- The source gate now requires the constant table buffers while preserving the
  existing hot-loop guards for output base reuse, jump-base precompute,
  q-table shift addressing, precomputed DP masks, and no modulo in the kernel.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `36,426,708.294932 mixed-add steps/sec`
  - paired baseline median `30,769,379.445330 mixed-add steps/sec`
  - paired speedup `1.183862x`
  - candidate min `24,616,405.367771 mixed-add steps/sec`
  - candidate max `41,279,674.800365 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Constant Metal Jump-Walk Inputs

Commit: `68b8e3b` (`perf: use constant Metal jump-walk inputs`)

- Changed the jump-walk kernels to read the initial packed Jacobian state
  (`p_xyz`) and infinity flags (`p_infinity`) from Metal `constant` address
  space.
- This extends the previous constant-table experiment to the per-sample
  read-only inputs while keeping `jump_indices` in `device const` and all output
  buffers in `device`.
- The source gate now requires constant address space for the read-only input
  buffers, the affine jump table, and the distance table while preserving every
  existing hot-loop guard.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `38,249,530.679262 mixed-add steps/sec`
  - paired baseline median `23,474,473.066685 mixed-add steps/sec`
  - paired speedup `1.629410x`
  - candidate min `23,407,514.435039 mixed-add steps/sec`
  - candidate max `45,292,938.764546 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Constant Metal Jump Indices

Commit: `cbfff2e` (`perf: use constant Metal jump indices`)

- Changed `jump_indices` from `device const` to Metal `constant` address space
  in the jump-walk kernels.
- This makes all read-only jump-walk buffers use `constant` while outputs remain
  `device`. The source gate now protects that contract.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `25,302,152.157760 mixed-add steps/sec`
  - paired baseline median `24,651,050.122097 mixed-add steps/sec`
  - paired speedup `1.026413x`
  - candidate min `19,269,715.464176 mixed-add steps/sec`
  - candidate max `27,091,847.302376 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`
  - Note: the margin is small and local Metal timings remain noisy, but the
    paired median cleared the configured keep gate.

### Shifted Metal Point Base

Commit: `c876663` (`perf: use shift for Metal point base`)

- Changed the packed Jacobian point base in the jump-walk kernels from
  `id * 12` to `(id << 3) + (id << 2)`, matching the 12-limb stride as an
  explicit shift-add.
- This only touches `jacobian_affine_walk_jump_table` and
  `jacobian_affine_walk_jump_table_steps8`; the standalone add and fixed-walk
  kernels keep their previous form.
- The source gate now rejects reintroducing `id * 12` in the jump-walk hot
  kernels while preserving the output-base reuse check.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `40,420,143.199132 mixed-add steps/sec`
  - paired baseline median `25,079,930.894718 mixed-add steps/sec`
  - paired speedup `1.611653x`
  - candidate min `28,374,309.720436 mixed-add steps/sec`
  - candidate max `55,671,451.511221 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Packed Metal Jump Indices

Commit: `b7122fb` (`perf: pack Metal jump indices to uint8`)

- Kept the CPU oracle and generator using `uint32_t` jump indices, but packed a
  `uint8_t` copy for the Metal buffer.
- This is safe for the current Metal benchmark surface because
  `NormalizeMetalJumpCount` caps `jump_count` at 32.
- The Metal kernels now read `constant uchar* jump_indices` and cast each loaded
  byte to `uint` before indexing the affine jump table and distance table.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `43,384,425.365437 mixed-add steps/sec`
  - paired baseline median `42,198,113.596848 mixed-add steps/sec`
  - paired speedup `1.028113x`
  - candidate min `25,070,894.921654 mixed-add steps/sec`
  - candidate max `43,685,276.246207 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`
  - Note: this is a small-margin keep, but it reduces jump-index bandwidth in
    the Metal dispatch path without changing the CPU oracle surface.

### Implicit Metal Uchar Index Promotion

Commit: `505a654` (`perf: rely on Metal uchar index promotion`)

- Removed the explicit `(uint)` cast when loading packed `uchar` jump indices in
  the jump-walk kernels.
- The destination variable remains `uint`, so the semantic value is unchanged;
  this only tests the generated Metal code shape.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `32,889,067.186241 mixed-add steps/sec`
  - paired baseline median `25,877,502.674679 mixed-add steps/sec`
  - paired speedup `1.270952x`
  - candidate min `28,617,488.562270 mixed-add steps/sec`
  - candidate max `36,398,807.719108 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Packed Metal DP Flags

Commit: `7feecd6` (`perf: pack Metal DP flags to uint8`)

- Changed the jump-walk DP flag output buffer from `device uint*` to
  `device uchar*` in both `jacobian_affine_walk_jump_table` and
  `jacobian_affine_walk_jump_table_steps8`.
- The public host/oracle surface still returns `std::vector<uint32_t>`; the
  host copies the compact Metal output into a `uint8_t` vector and expands each
  flag back to `0/1` `uint32_t` values before validation.
- This keeps the DP candidate semantics unchanged while reducing one output
  write and host copy from 4 bytes to 1 byte per state.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `37,830,025.643327 mixed-add steps/sec`
  - paired baseline median `28,696,541.249467 mixed-add steps/sec`
  - paired speedup `1.318278x`
  - candidate min `31,418,999.719122 mixed-add steps/sec`
  - candidate max `38,065,009.331453 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Packed Metal Output Infinity Flags

Commit: `e7b28c1` (`perf: pack Metal output infinity flags to uint8`)

- Changed only the jump-walk `out_infinity` buffers from `device uint*` to
  `device uchar*`; the `p_infinity` input remains `constant uint*` because
  packing that input was measured and rejected.
- Added a byte-output store helper for the jump-walk kernels while leaving the
  standalone Jacobian add and fixed-walk kernels on their existing `uint32_t`
  output contract.
- The host now keeps separate input/output infinity byte counts:
  `p_inf_bytes` for the `uint32_t` input flags and `out_inf_bytes` for the
  compact Metal output flags, then expands output flags back to `uint32_t`
  before calling the CPU oracle unpacker.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `33,349,832.725909 mixed-add steps/sec`
  - paired baseline median `25,793,902.178919 mixed-add steps/sec`
  - paired speedup `1.292935x`
  - candidate min `30,558,799.942895 mixed-add steps/sec`
  - candidate max `37,426,626.285881 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`

### Packed Metal Combined Output Flags

Commit: `f266242` (`perf: pack Metal output flags into one byte`)

- Combined the jump-walk output infinity flag and DP candidate flag into one
  Metal `uchar` output buffer: bit 0 stores infinity and bit 1 stores the DP
  candidate flag.
- Removed the separate `out_dp_flags` Metal buffer from the jump-walk kernel
  signatures. The host decodes the packed byte back into `std::vector<uint32_t>`
  infinity and DP flag vectors before calling the existing CPU oracle checks.
- This keeps the external correctness surface unchanged while reducing one
  output buffer binding, one output allocation, one device write stream, and one
  host copy.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `38,176,865.912089 mixed-add steps/sec`
  - paired baseline median `34,031,160.092524 mixed-add steps/sec`
  - paired speedup `1.121821x`
  - candidate min `17,725,221.967109 mixed-add steps/sec`
  - candidate max `42,261,342.487773 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`
  - Note: local Metal timing remained noisy, but the paired median cleared the
    configured keep gate.

### Metal Jump-Walk Threadgroup Dispatch

Commit: `4d1cc10` (`perf: dispatch Metal jump walk by threadgroups`)

- Changed only the jump-walk host dispatch from `dispatchThreads` to explicit
  `dispatchThreadgroups`, using
  `(count + threads_per_threadgroup - 1) / threads_per_threadgroup` and keeping
  the existing `id >= count` guard in the Metal kernels.
- Kernel math, buffer layout, packed jump indices, combined output flags,
  distance tracking, and DP predicate are unchanged.
- The source gate now rejects reintroducing `dispatchThreads` in
  `RunJacobianJumpWalkKernel` while preserving the existing packed-buffer
  checks.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - candidate median `37,756,893.905525 mixed-add steps/sec`
  - paired baseline median `25,763,516.307986 mixed-add steps/sec`
  - paired speedup `1.465518x`
  - candidate min `28,708,135.305072 mixed-add steps/sec`
  - candidate max `39,217,770.951406 mixed-add steps/sec`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`
  - A non-multiple micro-benchmark with `sample_count=9` also returned
    `correctness=true`, covering the ceiling dispatch shape.
- Local-public Benchforge verifier accepted submission
  `sub_f1185649-8a26-491b-a047-ec0604c7afbd` as run
  `run_0e8d35ad-7f60-4cf7-a9b6-87cf9a5f7b0a` with score
  `33,847,318.071380 ops/sec`, receipt hash
  `5e899e1312baca831593e1f54f9873bd35d56a0d669b0d2794a8000ee411d1db`,
  `verifier.trusted=false`, `platform=darwin`, `arch=arm64`, `cpus=Apple M3`.
  The local run before submission was
  `run_746218ad-dd52-4184-b5d3-75ea50e62374` at
  `32,143,846.853718 ops/sec`.

### Metal Steps8 DP4 Specialized Mask

Commit: `604dd55` (`perf: specialize Metal steps8 dp4 mask`)

- Added `jacobian_affine_walk_jump_table_steps8_dp4`, selected only when
  `steps_per_sample == 8` and `dp_bits == 4`. All other shapes keep the
  previous `steps8` or generic kernels.
- The specialized kernel keeps point math, jump indices, distance tracking, and
  packed output flags unchanged, but hardcodes the public DP mask test as
  `(x0 & 0xFUL) == 0` for the primary gate.
- The source gate now requires the dp4 specialization and the fallback
  selection so the verifier shape with `steps=7`, `jumps=9`, `dp_bits=3` stays
  on the generic path.
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - first candidate median `42,692,418.310915 mixed-add steps/sec`
  - first paired baseline median `41,388,708.608987 mixed-add steps/sec`
  - first paired speedup `1.031499x`
  - confirmation candidate median `46,781,458.735324 mixed-add steps/sec`
  - confirmation paired baseline median `45,497,141.628023 mixed-add steps/sec`
  - confirmation paired speedup `1.028229x`
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - `status=keep`
  - `correctness=true`
  - `threadgroup_limit=256`
  - `threads_per_threadgroup=256`
- `make macos-check` passed on `main` after the fast-forward merge.
- Local-public Benchforge verifier accepted submission
  `sub_3f950cfc-630e-4eef-a97f-bd12c1aa58a5` as run
  `run_e62fa172-6ae2-4fa4-acdf-9e108d0f274c` with score
  `46,317,921.229795 ops/sec`, receipt hash
  `f1cccd47b625caecc8b16c2cdac1204f935ca5382513c2e4ac12571abac49a82`,
  `verifier.trusted=false`, `platform=darwin`, `arch=arm64`, `cpus=Apple M3`.
  The local run before submission was
  `run_e9c0a155-6944-486b-9d5f-21685f819024` at
  `56,820,932.004814 ops/sec`.

### Metal DP4 Finite Add Hot Path

Commit: `a4939c6` (`perf: split Metal dp4 finite add path`)

- Split the Metal mixed-add helper into a finite-input hot path and a generic
  wrapper that still handles `p_infinity`.
- The public `steps_per_sample == 8` and `dp_bits == 4` kernel now calls the
  finite helper for normal points and falls back to the generic wrapper only
  when the current accumulator is at infinity. The generic and non-dp4 fallback
  kernels remain on the shared wrapper.
- The source gate now requires the finite helper, the wrapper's infinity
  delegation, and the dp4 kernel's explicit `if (inf)` fallback.
- Public oracle checks before promotion:
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - second verifier shape:
    `distance_checksum=0xbab72b58ebefa9dc`, `dp_count=249`,
    `dp_checksum=0x4a7f2853a4a9f546`
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - first candidate median `35,262,056.952682 mixed-add steps/sec`
  - first paired baseline median `30,045,324.607249 mixed-add steps/sec`
  - first paired speedup `1.173629x`
  - confirmation candidate median `54,586,707.150623 mixed-add steps/sec`
  - confirmation paired baseline median `47,025,523.463550 mixed-add steps/sec`
  - confirmation paired speedup `1.160789x`
  - `status=keep`
  - `correctness=true`
- `make macos-check` passed on `main` after the fast-forward merge.
- Benchforge doctor passed with only the expected `hosted-api` warning. Local
  run `run_fa38be32-e38b-431c-a231-6a6d4f624450` scored
  `53,659,825.908594 ops/sec`.
- Local-public Benchforge verifier accepted submission
  `sub_75c994e5-e6d5-4b4d-a1d3-fdd377b52dfc` as run
  `run_781dfd20-c53c-42f3-8fd6-3262ca9b520a` with score
  `54,982,200.626369 ops/sec`, receipt hash
  `691f72beed81ae9327ed39d656e0e3a82c78948469fd94d277fe5d17a30f1983`,
  `verifier.trusted=false`, `platform=darwin`, `arch=arm64`, `cpus=Apple M3`.
  The local leaderboard placed this accepted run second, behind the older local
  non-verified `56,820,932.004814 ops/sec` run.

### Metal DP4 Bool Infinity State

Commit: `3a79ce6` (`perf: use bool Metal dp4 infinity state`)

- Changed only the public `steps_per_sample == 8` and `dp_bits == 4` Metal
  kernel's accumulator infinity state from `uint` to `bool`, while preserving
  the generic fallback kernels and the host-visible packed flag format.
- The source gate now requires the dp4 kernel to initialize
  `bool inf = p_infinity[id] != 0` and update it with `inf = out.inf != 0`,
  while leaving other kernels on their existing `uint` state.
- Public oracle checks before promotion:
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - second verifier shape:
    `distance_checksum=0xbab72b58ebefa9dc`, `dp_count=249`,
    `dp_checksum=0x4a7f2853a4a9f546`
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - first candidate median `49,171,211.386386 mixed-add steps/sec`
  - first paired baseline median `38,955,739.382442 mixed-add steps/sec`
  - first paired speedup `1.262233x`
  - confirmation candidate median `46,633,123.492816 mixed-add steps/sec`
  - confirmation paired baseline median `41,583,067.031963 mixed-add steps/sec`
  - confirmation paired speedup `1.121445x`
  - `status=keep`
  - `correctness=true`
- `make macos-check` passed on `main` after the fast-forward merge.
- Benchforge doctor passed with only the expected `hosted-api` warning. Local
  run `run_1d2fc1a8-cd5b-4e2c-aa76-d5dde54c0138` scored
  `32,555,994.114175 ops/sec`.
- Local-public Benchforge verifier accepted submission
  `sub_5ec7721c-abb8-4c18-a0f7-c5a2a1ad47b4` as run
  `run_7f39c568-be4a-4e9e-9acd-a003112c79b1` with score
  `51,293,294.688826 ops/sec`, receipt hash
  `3a06339d0adfef0a2da552afae54e5a0706539201350089eb113895536794d2f`,
  `verifier.trusted=false`, `platform=darwin`, `arch=arm64`, `cpus=Apple M3`.
  This accepted run landed fifth on the local leaderboard at measurement time.

### Metal DP4 Direct Bool Infinity State

Commit: `b8e1120` (`perf: use direct bool Metal dp4 infinity state`)

- Simplified only the public `steps_per_sample == 8` and `dp_bits == 4` Metal
  kernel's bool accumulator state by assigning `p_infinity[id]` and `out.inf`
  directly, instead of comparing each value with zero. The fallback kernels and
  packed output flags are unchanged.
- The source gate now requires direct bool initialization/update and rejects
  reintroducing `!= 0` in this dp4 state path.
- Public oracle checks before promotion:
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - second verifier shape:
    `distance_checksum=0xbab72b58ebefa9dc`, `dp_count=249`,
    `dp_checksum=0x4a7f2853a4a9f546`
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - first candidate median `34,425,602.601131 mixed-add steps/sec`
  - first paired baseline median `22,144,004.281751 mixed-add steps/sec`
  - first paired speedup `1.554624x`
  - confirmation candidate median `29,895,632.602187 mixed-add steps/sec`
  - confirmation paired baseline median `25,779,267.617206 mixed-add steps/sec`
  - confirmation paired speedup `1.159677x`
  - `status=keep`
  - `correctness=true`
- `make macos-check` passed on `main` after the fast-forward merge.
- Benchforge doctor passed with only the expected `hosted-api` warning. Local
  run `run_5290138c-2fe6-46f2-bb39-3a4465e5e93f` scored
  `32,963,590.095748 ops/sec`.
- Local-public Benchforge verifier accepted submission
  `sub_c2a9e691-40cd-4233-954f-6414743d46ba` as run
  `run_43524297-43bd-4606-8686-2807aaa1d3f3` with score
  `25,910,107.039113 ops/sec`, receipt hash
  `f275a21f5df06fe288b6f527b7206a2b0a09036c3004e5af4325e001bb86a7cf`,
  `verifier.trusted=false`, `platform=darwin`, `arch=arm64`, `cpus=Apple M3`.
  The local-public score was lower than earlier accepted baselines in this
  noisy/thermal window; the promotion is based on two paired `keep` runs.

### Metal DP4 Q-Base Before Distance

Commit: `21d2cb4` (`perf: schedule q base before Metal dp4 distance`)

- Reordered only the public `steps_per_sample == 8` and `dp_bits == 4` Metal
  kernel so `uint q_base = jump_index << 3` is computed before
  `distance += jump_distances[jump_index]`. Arithmetic, masks, fallback kernels,
  and output formats are unchanged.
- The source gate now requires this q-base-first ordering in the dp4 hot path.
- Public oracle checks before promotion:
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
  - second verifier shape:
    `distance_checksum=0xbab72b58ebefa9dc`, `dp_count=249`,
    `dp_checksum=0x4a7f2853a4a9f546`
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp`, `steps_per_sample=8`, `jump_count=16`,
  and `dp_bits=4`:
  - first candidate median `38,940,533.391902 mixed-add steps/sec`
  - first paired baseline median `35,722,986.288468 mixed-add steps/sec`
  - first paired speedup `1.090069x`
  - confirmation candidate median `38,149,612.617702 mixed-add steps/sec`
  - confirmation paired baseline median `32,974,113.574544 mixed-add steps/sec`
  - confirmation paired speedup `1.156956x`
  - `status=keep`
  - `correctness=true`
- `make macos-check` passed on `main` after the fast-forward merge.
- Benchforge doctor passed with only the expected `hosted-api` warning. Local
  run `run_aa478e72-6891-4dfa-b306-12b0f5245995` scored
  `48,168,274.540102 ops/sec`.
- Local-public Benchforge verifier accepted submission
  `sub_ff829389-58e9-4493-af15-ed00ac22a0ab` as run
  `run_81f56a78-8985-4261-9a14-4c198053c97c` with score
  `51,884,059.915813 ops/sec`, receipt hash
  `e8065d2aeb3548d29c8a133fb777b4e6be2ee8d751f4d65ae874cbbc9498b112`,
  `verifier.trusted=false`, `platform=darwin`, `arch=arm64`, `cpus=Apple M3`.
  The local leaderboard placed this accepted run fifth at measurement time.

### Metal DP4 Packed Input Infinity

Commit: `a963a4d` (`perf: pack Metal dp4 infinity input`)

- Changed only the public `steps_per_sample == 8` and `dp_bits == 4` Metal
  kernel's input infinity buffer from `constant uint*` to `constant uchar*`.
  The host now packs `p_infinity` to one byte per sample only when selecting
  `jacobian_affine_walk_jump_table_steps8_dp4`; generic and verifier fallback
  shapes keep the existing `uint32_t` input buffer.
- The source gates now require the dp4 packed input path, the direct bool
  infinity state, the q-base-before-distance ordering, and the generic
  fallback path for non-public shapes.
- Public oracle checks before promotion:
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp_stable`, `steps_per_sample=8`,
  `jump_count=16`, and `dp_bits=4`:
  - confirmation 1 speedup `1.190133x`
  - confirmation 2 speedup `1.081899x`
  - confirmation 3 speedup `1.432397x`
  - `confirmation_status=keep`
  - `status=keep`
  - `correctness=true`
- Candidate worktree verification passed:
  - `python3 tests/check_metal_dp4_uchar_infinity_source.py`
  - `sh tests/check_metal_kernels.sh`
  - `make macos-check`
- `make macos-check` passed on `main` after the fast-forward merge.
- Benchforge doctor passed with only the expected `hosted-api` warning. Local
  run `run_171b8a17-908c-4e9d-b673-f7df024bfe4f` scored
  `18,060,317.733834 ops/sec`.
- Local-public Benchforge verifier accepted submission
  `sub_1cc10e05-76a9-4108-994d-949042388cfc` as run
  `run_64462ed9-026e-4823-a8f7-9c1041946409` with score
  `32,680,850.854894 ops/sec`, receipt hash
  `2b9a4a74a2d58cf3013bcf90af215088f8c6cdf4f64371888acd4491b4d03942`,
  `verifier.trusted=false`, `platform=darwin`, `arch=arm64`, `cpus=Apple M3`.
  The candidate submission's local pre-verifier score was
  `41,426,588.802440 ops/sec`.

### Metal DP4 Struct-Row Q Table

Commit: `3311412` (`perf: view Metal dp4 q table as struct rows`)

- Changed only the public `steps_per_sample == 8` and `dp_bits == 4` Metal
  kernel's affine jump-table view from scalar `constant ulong* q_xy` plus
  `q_base = jump_index << 3` indexing to a binary-compatible
  `constant AffineJumpValue*` row view. The host buffer layout stays the same
  eight 64-bit limbs per jump; generic and verifier fallback kernels keep the
  previous scalar table indexing.
- The source gates now require the public DP4 struct-row table view, reject the
  removed `q_base` calculation in the public DP4 kernel, and keep checking that
  generic/fallback kernels still use scalar `constant ulong* q_xy`.
- Public oracle checks before promotion:
  - `distance_checksum=0xa45f471493cace2f`
  - `dp_count=1000`
  - `dp_checksum=0x30a7914972cba014`
- Paired M3 autoresearch against `main` for
  `metal_jacobian_jump_walk_dp_stable`, `steps_per_sample=8`,
  `jump_count=16`, and `dp_bits=4`:
  - confirmation 1 speedup `1.184193x`
  - confirmation 2 speedup `2.200985x`
  - confirmation 3 speedup `1.045283x`
  - `confirmation_status=keep`
  - `status=keep`
  - `correctness=true`
- Candidate worktree verification passed:
  - `python3 tests/check_metal_dp4_q_struct_row_source.py`
  - `python3 tests/check_metal_dp4_uchar_infinity_source.py`
  - `sh tests/check_metal_kernels.sh`
  - `make macos-check`
- `make macos-check` passed on `main` after the fast-forward merge.
- Benchforge doctor passed with only the expected `hosted-api` warning. Local
  run `run_244bebf3-88f3-4b86-ac20-084f3a6c9645` scored
  `23,466,689.498479 ops/sec`.
- Local-public Benchforge verifier accepted submission
  `sub_1f7c17e0-e64d-4615-a3a8-d3da2bb695e2` as run
  `run_24328eb8-3d5b-47b4-984a-4fa1b5892cc4` with score
  `25,303,719.636362 ops/sec`, receipt hash
  `7eb945dd814a1040bfd4124247a831c62e9cfd17de6f80208aee75b37c0a40a5`,
  `verifier.trusted=false`, `platform=darwin`, `arch=arm64`, `cpus=Apple M3`.
  The candidate submission's local pre-verifier score was
  `54,973,825.283380 ops/sec`. The accepted verifier score was noisy and lower
  than older local-public accepted runs, so this promotion relies on the paired
  three-confirmation autoresearch gate plus unchanged public oracle fields.
- A fresh post-promotion Benchforge loop on `main` accepted submission
  `sub_594c881c-bfc1-46e2-a715-85eab35f40fe` as run
  `run_03374691-b656-4c42-a5b4-7447490b9786` with score
  `29,436,926.035583 ops/sec`, receipt hash
  `187438c75b6b9bb8266be499f1e552922a71723eda995c116f8c99ecb2e255fe`,
  `verifier.trusted=false`, `platform=darwin`, `arch=arm64`, `cpus=Apple M3`.

## Rejected Or Non-Merged Experiments

These did not pass the performance gate or had a correctness/architecture issue:

- `macos-metal-dp4-affine-pair2`: attempted a larger mathematical jump by
  precomputing all 16x16 affine pair sums `Q_i + Q_j`, then replacing the
  public eight-step DP4 kernel with four mixed-adds against composite pairs.
  This is correct only at the affine curve-point level. It failed the public
  stable oracle because the benchmark intentionally compares raw Jacobian
  `x/y/z` coordinates and the DP bit is taken from projective `x[0]`; changing
  the addition grouping changes the `Z` representation and therefore the raw
  projective coordinates. Observed failure: `correctness=false`, zeroed
  checksum fields, and vector-0 Jacobian mismatch. Do not retry affine
  composite jumps unless the API/oracle is explicitly changed to affine
  equivalence and affine DP semantics.
- `macos-metal-dp4-pair-distance`: kept the exact eight public DP4 mixed-adds
  but accumulated scalar distances through a precomputed 16x16 pair-distance
  table, reducing distance loads from eight to four while preserving raw
  Jacobian coordinates and oracle fields. Correctness stayed intact, but paired
  autoresearch discarded it: `0.850786x`, `1.047350x`, `1.956234x`, therefore
  `confirmation_status=discard`. The one strong run was not reproducible enough
  to promote; keep per-step distance accumulation.
- `macos-metal-dp4-z1-first-step`: specialized only the first public DP4
  mixed-add for an initial `Z=1`, skipping the generic `Z^2`/`Z^3` work while
  preserving exact raw Jacobian semantics and falling back to the normal
  edge/doubling paths. `make macos-check` and the full stable DP oracle passed,
  but paired autoresearch discarded it: `1.723581x`, `1.342978x`,
  `0.891806x`, therefore `confirmation_status=discard`. The candidate can
  spike high, but the signal was not durable enough to promote; keep the
  compact uniform DP4 loop.
- `macos-metal-dp4-xyzz-state`: maintained per-thread `Z^2` and `Z^3` state
  in the public DP4 kernel so the finite mixed-add path could use cached
  `ZZ/ZZZ` for `U2/S2`, while updating exact raw `Z`, `ZZ`, and `ZZZ` after
  each step. Source gates, `make macos-check`, and the stable DP oracle passed,
  but paired autoresearch discarded it: `1.024585x`, `0.824733x`,
  `0.548792x`, therefore `confirmation_status=discard`. The extra coordinate
  state and register pressure outweighed the dependency reduction on M3; keep
  the compact Jacobian DP4 state.
- `macos-metal-dp4-index-word`: packed the public DP4 kernel's eight
  per-sample jump-index bytes into one `uint64_t` host word and extracted each
  index with shifts inside the loop, reducing index-buffer loads from eight to
  one per thread. Source gates, `make macos-check`, and the public DP oracle
  passed, but direct runs were gross regressions: `1,234,220.937488 ops/sec`
  and `15,541,034.229553 ops/sec`. Do not promote to paired autoresearch; keep
  byte-per-step index loads because the `ulong` extraction path hurts the M3
  compiled DP4 kernel shape.
- `macos-metal-bool-jacobian-inf`: changed the internal Metal
  `JacobianValue.inf` field from `uint` to `bool` while preserving external
  `uint`/`uchar` buffers and the public DP4 bool accumulator. Source gates,
  `make macos-check`, and the full stable DP oracle passed, but paired
  autoresearch discarded it: `0.756774x`, `1.006789x`, `1.413763x`, therefore
  `confirmation_status=discard`. The late strong run was not durable enough;
  keep the current `uint` struct field because the bool result shape introduced
  large low-tail variance on M3.
- `macos-metal-mixed-add-h-normal-first`: moving the finite mixed-add normal
  `H != 0` path before the rare `H == 0` doubling/infinity edge path preserved
  `make macos-check`, the infinity-tail selftest, and the full stable DP
  oracle, but failed paired confirmation. Stable DP speedups were `0.797689x`,
  `1.444925x`, and `0.701535x`, therefore `confirmation_status=discard`.
  Keep the existing edge-first helper order; the normal-first source shape was
  too unstable on M3.
- `macos-metal-dp4-finite-inplace`: adding a DP4-only finite mixed-add helper
  that updates the local Jacobian limbs in place, instead of returning a
  `JacobianValue`, preserved `make macos-check` and the full stable DP oracle,
  but failed paired confirmation. Stable DP speedups were `0.614190x`,
  `0.894849x`, and `1.371729x`, therefore `confirmation_status=discard`.
  Keep the current compiler-shaped `JacobianValue` return on the finite DP4
  path; the attempted register-pressure reduction was not durable on M3.
- `macos-metal-dp4-uchar-flag-cast`: adding an explicit `uchar` cast around
  the public DP4 packed flag-store expression preserved `make macos-check` and
  the full stable DP oracle, but failed paired confirmation. Stable DP speedups
  were `1.020047x`, `1.099344x`, and `0.894179x`, therefore
  `confirmation_status=discard`. Keep the implicit narrowing store.
- `macos-metal-dp4-u32-accum`: narrowing only the public DP4 kernel's scalar
  distance accumulator to `uint`, with a host safety guard and a `ulong` output
  cast, preserved `make macos-check` and the full stable DP oracle, but failed
  paired confirmation. Stable DP speedups were `0.950121x`, `1.200329x`, and
  `0.991690x`, therefore `confirmation_status=discard`. Keep the promoted
  `ulong` accumulator in the DP4 kernel.
- `macos-metal-dp4-uchar-state`: changing the public DP4 kernel's local
  infinity state from `bool` to `uchar` after the packed input-infinity win
  preserved `make macos-check` and the full stable DP oracle, but failed paired
  confirmation. Stable DP speedups were `0.858733x`, `0.633437x`, and
  `0.627012x`, therefore `confirmation_status=discard`. Keep the promoted
  `bool` local state fed by the packed `uchar` input buffer.
- `macos-affine-prefix-split-tame`: speedup `0.995234`; discarded.
- `macos-dp-combined-record`: speedup `0.987156`; discarded.
- `macos-affine-jump-index-reuse`: incorrect behavior for the gate shape
  (`avg_dp_count` changed from `288` to `1172`); discarded.
- `macos-field-self-ops-v2`: speedup `0.993284`; discarded.
- `macos-native-cpu-flags-v3`: speedup `1.001949`, below gate; discarded.
- `macos-metal-square-generic`: correct but slower/unstable; not merged.
- `macos-metal-tg512`: correct and sometimes faster for
  `field_mul_mod_p`, but rejected because `field_square_mod_p` regressed badly
  in direct Metal runs. Keep the current 256-thread cap as the baseline until a
  broader Metal benchmark shows a consistent cross-kernel win.
- `--tg-limit N` is now available on Metal field benchmark commands for
  reproducible sweeps. The default remains 256 unless an experiment proves a
  better cross-kernel cap.
- A direct sweep with `--tg-limit` found `384` promising for some `mul` and
  `square` runs, but a repeat square comparison flipped back in favor of 256.
  Treat 384 as inconclusive, not as a new baseline.
- Metal field autoresearch experiments use three runner samples so keep/discard
  decisions are based on median throughput instead of a single noisy GPU run.
- `macos-metal-jacobian-tg512`: a single direct run suggested a possible win
  for the point-level `jacobian_add_affine` kernel, but paired autoresearch
  rejected it. Candidate tg512 median was `15,788,868.363001 ops/sec` versus
  baseline tg256 `23,401,670.068526 ops/sec`, `paired_speedup=0.674690`,
  `status=discard`, `correctness=true`. Keep Jacobian add at the current
  256-thread default until a broader retest shows a stable win.
- `macos-metal-q-limb-preload`: explicitly preloading the 8 affine jump-table
  limbs before `jacobian_add_affine_values` preserved all oracle fields but
  failed the paired gate. Candidate median was `32,121,834.312940 ops/sec`
  versus baseline `42,950,885.665018 ops/sec`, `paired_speedup=0.747874`,
  `status=discard`, `correctness=true`. Avoid this shape unless a future
  register-pressure or occupancy change alters the tradeoff.
- `macos-metal-steps8-unroll`: explicitly unrolling all eight fixed steps in
  `jacobian_affine_walk_jump_table_steps8` preserved all oracle fields but
  failed the paired gate. Candidate median was `27,823,058.415239 ops/sec`
  versus baseline `36,861,665.504647 ops/sec`, `paired_speedup=0.754797`,
  `status=discard`, `correctness=true`. Keep the compact fixed-loop kernel;
  avoid manual unroll unless later register-pressure data changes the tradeoff.
  A post-threadgroup-dispatch retest at candidate commit `56302e5` with the
  tightened five-sample Metal DP gate also discarded the idea: candidate median
  `30,216,489.417128 ops/sec` versus baseline `30,308,267.513455 ops/sec`,
  `paired_speedup=0.996972`, `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`.
- `macos-metal-steps4-kernel`: adding a compact fixed-loop
  `jacobian_affine_walk_jump_table_steps4` preserved all oracle fields but
  failed the dedicated `steps=4` paired gate. Candidate median was
  `22,541,817.038062 ops/sec` versus baseline `23,428,800.951795 ops/sec`,
  `paired_speedup=0.962141`, `status=discard`, `correctness=true`. Keep
  `steps=4` on the generic kernel; the `steps=8` specialization does not
  automatically generalize to shorter batches.
- `macos-metal-steps8-no-steps-arg`: removing the unused `steps` buffer
  argument from `jacobian_affine_walk_jump_table_steps8` preserved all oracle
  fields but failed the paired gate. Candidate median was
  `25,295,762.625885 ops/sec` versus baseline `32,273,831.165649 ops/sec`,
  `paired_speedup=0.783786`, `status=discard`, `correctness=true`. Keep the
  current specialized kernel signature; the unused bound buffer is not the
  limiting factor and removing it changed the compiled shape unfavorably.
- `macos-metal-u8-infinity`: packing Metal input infinity flags from
  `uint32_t` to `uint8_t` preserved all oracle fields but failed the paired
  gate. Candidate median was `30,786,695.889088 ops/sec` versus baseline
  `37,781,409.120807 ops/sec`, `paired_speedup=0.814864`,
  `status=discard`, `correctness=true`. Keep input infinity flags as
  `uint32_t`; unlike jump indices, this single read per thread does not
  justify the changed compiled or buffer shape.
- `macos-metal-direct-store-base`: removing the explicit `out_base = p_base`
  variable in the jump-walk kernels and passing `p_base` directly to the output
  store helper preserved all oracle fields but failed the paired gate.
  Candidate median was `31,164,051.209361 ops/sec` versus baseline
  `38,970,988.924523 ops/sec`, `paired_speedup=0.799673`,
  `status=discard`, `correctness=true`. Keep the explicit output-base alias;
  this small source simplification changed the compiled shape unfavorably.
- `macos-metal-u32-distances`: packing the Metal jump-distance table from
  `uint64_t` to `uint32_t`, while keeping the scalar accumulator and CPU oracle
  at `uint64_t`, preserved all oracle fields but failed the paired gate.
  Candidate median was `26,179,407.033794 ops/sec` versus baseline
  `27,571,898.407642 ops/sec`, `paired_speedup=0.949496`,
  `status=discard`, `correctness=true`. Keep the distance table as `ulong`;
  the narrower load did not offset the changed compiled/buffer shape.
- `macos-metal-pow2-distances`: adding a steps=8-only Metal kernel that
  replaced `distance += jump_distances[jump_index]` with
  `distance += (1UL << jump_index)` when the host verified
  `jump_distances[i] == (1ULL << i)` preserved all oracle fields but failed the
  paired gate. Candidate median was `25,415,526.957227 ops/sec` versus baseline
  `30,676,662.025047 ops/sec`, `paired_speedup=0.828497`,
  `status=discard`, `correctness=true`. Keep the table-load steps8 kernel; on
  this M3 run the shift-specialized compiled shape was slower than the existing
  read-only distance table.
- `macos-metal-distance-packed-flags`: packing the steps=8 infinity and DP
  flags into bits 62-63 of `out_distances[id]` preserved all oracle fields and
  initially passed the paired gate (`29,118,843.516504 ops/sec` versus
  `27,517,848.433568 ops/sec`, `paired_speedup=1.058180`), but the
  local-public verifier accepted it at only `26,835,812.014708 ops/sec` and a
  confirmation paired run against pre-candidate commit `72dfb4a` rejected it.
  Confirmation median was `34,780,120.656735 ops/sec` versus baseline
  `40,132,591.380091 ops/sec`, `paired_speedup=0.866630`,
  `status=discard`, `correctness=true`. The candidate was reverted; keep the
  separate `out_flags` byte for the steps=8 kernel unless a future broader
  repeat shows the high-bit packing win is stable.
- `macos-metal-pipeline-multiple-width`: creating the jump-walk pipeline via
  `MTLComputePipelineDescriptor` with
  `threadGroupSizeIsMultipleOfThreadExecutionWidth = YES` preserved all oracle
  fields but failed the paired gate. Candidate median was
  `20,661,731.632643 ops/sec` versus baseline `34,840,104.647447 ops/sec`,
  `paired_speedup=0.593044`, `status=discard`, `correctness=true`. Keep the
  direct `newComputePipelineStateWithFunction` path for jump-walk kernels; the
  descriptor hint changed the compiled shape unfavorably on this M3 run.
- `macos-metal-setbytes-scalars`: binding `count`, `steps`, and `dp_mask` with
  `setBytes:length:atIndex:` instead of three tiny shared `MTLBuffer` objects
  preserved all oracle fields but failed the paired gate. Candidate median was
  `31,316,123.200994 ops/sec` versus baseline `37,435,388.026000 ops/sec`,
  `paired_speedup=0.836538`, `status=discard`, `correctness=true`. Keep the
  existing scalar buffers; the inline binding did not improve the dispatch
  shape for this kernel.
- `macos-metal-branchless-flags`: replacing the final output-flag ternaries
  with explicit `is_inf`, `dp_flag`, and `uchar(is_inf | (dp_flag << 1))`
  preserved all oracle fields but failed the paired gate. Candidate median was
  `26,399,879.312075 ops/sec` versus baseline `36,600,758.926891 ops/sec`,
  `paired_speedup=0.721293`, `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep the compact ternary store; the manual
  branchless spelling changed the compiled shape unfavorably.
- `macos-metal-untracked-buffers`: creating the jump-walk buffers with
  `MTLResourceStorageModeShared | MTLResourceHazardTrackingModeUntracked`
  preserved all oracle fields but failed the paired gate. Candidate median was
  `20,388,792.013228 ops/sec` versus baseline `22,815,429.774553 ops/sec`,
  `paired_speedup=0.893640`, `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep the default tracked shared buffers for
  this single-dispatch benchmark; opting out did not reduce measured GPU time
  on this M3 run.
- `macos-metal-steps8-dp4-firstinf`: adding a host guard for the benchmark
  pattern where only point 0 starts at infinity, then selecting a steps8 +
  `dp_bits=4` Metal kernel that replaces `p_infinity[id]` with
  `id == 0 ? 1U : 0U`, preserved all oracle fields but did not pass
  confirmation. The first paired run kept it at candidate median
  `43,313,091.164017 ops/sec` versus baseline `34,911,331.312607 ops/sec`,
  `paired_speedup=1.240660`; the immediate confirmation discarded it at
  `43,163,082.615191 ops/sec` versus baseline `43,781,915.905634 ops/sec`,
  `paired_speedup=0.985866`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Do not promote this first-infinity
  specialization without a broader, repeatable gain; the removed buffer read is
  not a stable win on this M3 run.
- `macos-metal-steps8-dp4-tgcache`: adding a steps8 + `dp_bits=4` + 16-jump
  Metal kernel that preloads the affine jump table and scalar distances into
  threadgroup memory preserved all oracle fields and fallback correctness, but
  failed the paired gate. Candidate median was `39,023,071.164210 ops/sec`
  versus baseline `42,888,813.210105 ops/sec`, `paired_speedup=0.909866`,
  `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep using the constant-buffer jump table on
  M3; the threadgroup preload and barrier cost more than the repeated cached
  reads in this math-heavy kernel.
- `macos-metal-dp4-drop-steps`: removing the dead `steps` kernel argument from
  `jacobian_affine_walk_jump_table_steps8_dp4` preserved all oracle fields but
  failed the paired gate. Candidate median was `28,385,107.764488 ops/sec`
  versus baseline `35,725,191.654110 ops/sec`, `paired_speedup=0.794540`,
  `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep the apparently redundant `steps`
  binding in the dp4 kernel; removing it changes the Metal function shape
  unfavorably on this M3 run.
- `macos-metal-reduce-single-sub`: replacing the final `while` in
  `reduce512_mod_p` with a single conditional `sub_p5` preserved correctness
  across `make macos-check`, field selftests, the public DP checksum, and the
  verifier's second shape. A Python model of the current Metal reduction over
  200k random field products plus edge cases saw at most one final subtract.
  The microbenchmarks improved (`metal_field_square` paired speedup
  `1.345393`, `metal_field_mul` paired speedup `1.194649`), but the actual
  target did not pass: first DP paired run was `30,186,670.513289 ops/sec`
  versus baseline `44,007,021.060713`, `paired_speedup=0.685951`; a repeat was
  effectively neutral at `38,297,493.616744 ops/sec` versus
  `38,246,490.390202`, `paired_speedup=1.001334`, still `status=discard`.
  Manual alternating `--min-ms 200` runs showed strong warmup/order effects and
  no reliable target win. Keep the looped reducer for the Jacobian kernel; a
  future candidate may isolate single-sub to a smaller field microkernel, but it
  is not the base for the DP target.
- `macos-metal-dp4-max-tg256`: adding
  `[[max_total_threads_per_threadgroup(256)]]` to the public dp4 kernel was
  accepted by the runtime compiler and changed reported
  `max_threads_per_threadgroup` from `1024` to `256`, but it failed the paired
  target gate. Candidate median was `35,188,997.363215 ops/sec` versus baseline
  `41,028,548.928926 ops/sec`, `paired_speedup=0.857671`,
  `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep the unconstrained dp4 kernel; the
  explicit max threadgroup attribute worsened the compiled shape on M3.
- `macos-metal-dp4-vector-stores`: adding a `store_jacobian_xyz_only_vec4`
  helper and using three `ulong4` stores for the dp4 kernel's final Jacobian
  output preserved all oracle fields but failed the paired target gate.
  Candidate median was `42,347,381.165201 ops/sec` versus baseline
  `45,468,279.360450 ops/sec`, `paired_speedup=0.931361`,
  `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep scalar limb stores; the vector store
  spelling did not improve this kernel on M3.
- `macos-metal-dp4-q-locals`: loading the eight affine jump-table limbs into
  `qx*`/`qy*` locals once per dp4 step, then passing those locals to both the
  generic infinity fallback and finite hot path, preserved all oracle fields but
  failed the paired target gate. Candidate median was
  `51,269,848.158566 ops/sec` versus baseline `53,225,235.044224 ops/sec`,
  `paired_speedup=0.963262`, `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep the direct `q_xy[q_base + n]`
  operands in the promoted dp4 finite-hot-path kernel; the explicit locals did
  not help this M3 compiler shape.
- `macos-metal-dp4-inline-inf`: inlining the dp4 infinity fallback as direct
  affine assignment (`x/y=q`, `z=1`, `inf=0`) preserved all oracle fields but
  failed the paired target gate. Candidate median was
  `53,801,243.066193 ops/sec` versus baseline `57,431,762.259068 ops/sec`,
  `paired_speedup=0.936786`, `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep the promoted generic-wrapper fallback
  shape; the explicit assignment worsened the compiled dp4 kernel on M3.
- `macos-metal-dp4-flag-ternary`: simplifying the dp4 final packed-flag store
  from `(inf ? 1 : 0) | ((!inf && dp) ? 2 : 0)` to `inf ? 1 : (dp ? 2 : 0)`
  preserved all oracle fields but failed the paired target gate. Candidate
  median was `28,602,135.384033 ops/sec` versus baseline
  `36,034,276.125311 ops/sec`, `paired_speedup=0.793748`,
  `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep the promoted OR/`!inf` flag spelling;
  the direct ternary hurt the dp4 kernel shape on M3.
- `macos-metal-add-always-inline`: adding
  `__attribute__((always_inline))` to both Metal mixed-add helpers compiled and
  preserved all oracle fields, but failed the paired target gate. Candidate
  median was `29,906,975.938509 ops/sec` versus baseline
  `36,536,871.605632 ops/sec`, `paired_speedup=0.818542`,
  `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep plain `static inline`; forcing inline
  worsened the compiled large Jacobian kernel on M3.
- `macos-metal-dp4-finite-first`: changing the dp4 branch order to test
  `if (!inf)` and place the finite hot path before the generic infinity
  fallback preserved all oracle fields but failed the paired target gate.
  Candidate median was `27,998,203.739620 ops/sec` versus baseline
  `28,161,283.758521 ops/sec`, `paired_speedup=0.994209`,
  `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep the promoted `if (inf)` fallback-first
  spelling from `b8e1120`; the compiler did not reward the likely-path order on
  this M3 run.
- `macos-metal-dp4-uchar-index`: narrowing the dp4 loop's local jump index to
  `uchar` and casting back to `uint` for `jump_distances` and `q_base`
  preserved all oracle fields, but did not survive confirmation. The first
  paired run kept it: candidate median `38,098,881.915015 ops/sec` versus
  baseline `27,330,823.387611 ops/sec`, `paired_speedup=1.393990`. The
  confirmation discarded it: candidate median `30,444,886.448562 ops/sec`
  versus baseline `33,237,046.959255 ops/sec`, `paired_speedup=0.915993`.
  `correctness=true`, `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  and `dp_checksum=0x30a7914972cba014` in both runs. Treat this as unstable and
  keep the promoted `uint jump_index` spelling until a stronger repeated signal
  appears.
- `macos-metal-dp4-step-ne`: changing the public dp4 fixed loop from
  `step < 8` to `step != 8` preserved all oracle fields but failed the paired
  target gate. Candidate median was `31,734,147.843923 ops/sec` versus
  baseline `36,197,526.932618 ops/sec`, `paired_speedup=0.876694`,
  `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep the promoted `< 8` loop spelling.
- `macos-metal-dp4-const-jump-locals`: marking the public dp4 loop's
  `jump_index` and `q_base` locals as `const uint` preserved all oracle fields
  but failed the paired target gate. Two sandboxed runner attempts were
  recorded as `status=skip` because the sandboxed Python runner could not see
  Metal; the elevated paired run measured correctly. Candidate median was
  `43,098,694.269856 ops/sec` versus baseline `49,646,792.344200 ops/sec`,
  `paired_speedup=0.868106`, `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep mutable `uint` locals in the promoted
  q-base-first dp4 kernel.
- `macos-metal-dp4-distance-late`: moving the public dp4 loop's
  `distance += jump_distances[jump_index]` from before the mixed-add branch to
  immediately after `inf = out.inf` preserved all oracle fields but failed the
  paired target gate. Candidate median was `35,979,020.969423 ops/sec` versus
  baseline `38,080,155.698501 ops/sec`, `paired_speedup=0.944823`,
  `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep the promoted q-base-first distance
  load/add position before the mixed-add block.
- `macos-metal-dp4-branch-local-out`: declaring `JacobianValue out` inside
  each dp4 branch and duplicating the state update preserved all oracle fields,
  but the performance signal did not survive confirmation. Three paired runs
  measured `42,681,923.754455` versus `25,846,773.075579 ops/sec`
  (`1.651344x`, `keep`), then `20,418,005.034635` versus
  `19,749,595.911307 ops/sec` (`1.033844x`, `keep`), then
  `19,989,883.202345` versus `38,528,020.636069 ops/sec` (`0.518840x`,
  `discard`). `correctness=true`, `distance_checksum=0xa45f471493cace2f`,
  `dp_count=1000`, and `dp_checksum=0x30a7914972cba014` in all runs. Treat the
  idea as unstable/rejected and keep the promoted shared post-branch update.
- `macos-metal-dp4-reuse-jump-base`: moving `uint jump_base = id << 3` before
  `p_base` and deriving `p_base = jump_base + (id << 2)` preserved all oracle
  fields but failed the paired target gate. Candidate median was
  `27,479,586.125938 ops/sec` versus baseline `39,064,201.289996 ops/sec`,
  `paired_speedup=0.703447`, `status=discard`, `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`. Keep the promoted separate `p_base`
  expression followed by the later `jump_base` declaration.
- `macos-metal-dp4-default-tg512`: defaulting only the public
  `steps_per_sample=8`, `dp_bits=4` jump-walk shape to threadgroup limit `512`
  preserved all oracle fields and still honored explicit `--tg-limit 256`, but
  failed the paired target gate. Candidate median was
  `30,497,177.022142 ops/sec` versus baseline `42,867,189.634848 ops/sec`,
  `paired_speedup=0.711434`, `status=discard`, `correctness=true`,
  `threadgroup_limit=512`, `distance_checksum=0xa45f471493cace2f`,
  `dp_count=1000`, `dp_checksum=0x30a7914972cba014`. Keep default `256` for the
  dp4 score path unless a broader repeated sweep overturns this result.
- `macos-metal-dp4-exact-count`: adding a separate public dp4 kernel without
  the `id >= count` guard and selecting it only when `count` is divisible by the
  effective threadgroup size preserved all oracle fields, including a
  non-multiple fallback check with `sample_count=9`, but failed confirmation.
  `--confirm-runs 3` recorded `confirmation_status=discard`: run 1 was a raw
  keep at `41,921,077.695352 ops/sec` versus baseline
  `34,056,101.299761 ops/sec` (`1.230942x`), run 2 discarded at
  `31,295,093.179597` versus `34,738,943.749887 ops/sec` (`0.900865x`), and
  run 3 was a raw keep at `40,742,624.570094` versus
  `38,913,847.475444 ops/sec` (`1.046996x`). `correctness=true`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`, and
  `dp_checksum=0x30a7914972cba014` in all runs. Keep the guarded dp4 kernel.
- `macos-metal-dp4-first-generic-rest-finite`: splitting the public dp4 kernel
  into a generic first step followed by finite-only tail steps passed the public
  checksum oracle but failed a new direct Metal selftest when the first jump
  intentionally sends a lane to infinity and the next jump must resume from an
  affine point. The candidate returned infinity with `distance=15`; the CPU
  oracle returned a finite point. Do not remove the tail `if (inf)` guard unless
  a replacement is proven against this infinity-tail oracle.
- `macos-metal-dp4-j16-threadgroup-table`: adding a public-shape specialization
  for `steps=8`, `dp_bits=4`, `jump_count=16` that stages the 16-point jump
  table and 16 distances into `threadgroup` memory preserved correctness,
  including the infinity-tail selftest, but failed the paired target gate.
  Candidate median was `30,095,459.840316 ops/sec` versus baseline
  `37,579,388.005384 ops/sec`, `paired_speedup=0.800850`, `status=discard`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`, and
  `dp_checksum=0x30a7914972cba014`. On M3 Air the staging barrier and local
  memory traffic outweighed any benefit over constant-buffer reads.
- `macos-metal-dp4-inline-inf-affine`: inlining the `p.infinity + affine q`
  fallback directly inside the public dp4 branch preserved all oracle fields,
  including the infinity-tail selftest, but failed the paired target gate.
  Candidate median was `40,274,694.606662 ops/sec` versus baseline
  `44,267,553.613436 ops/sec`, `paired_speedup=0.909802`, `status=discard`,
  `distance_checksum=0xa45f471493cace2f`, `dp_count=1000`, and
  `dp_checksum=0x30a7914972cba014`. Keep the wrapper-based fallback branch unless
  a future compiler/code-shape experiment shows a confirmed win.
- `macos-metal-field-single-sub-micro-all`: adding single-final-subtraction
  reducer helpers for the isolated Metal field multiply, square, and
  square-multiply microbenchmarks produced promising first paired samples:
  `field_mul` was `84,087,327.209258 ops/sec` versus
  `83,249,704.275571` (`1.010062x`), `field_square` was
  `164,356,831.613348` versus `144,975,816.742231` (`1.133684x`), and
  `field_square_mul` was `118,354,164.489191` versus
  `103,833,541.695033` (`1.139845x`). The stable dp4 walk oracle also stayed
  intact (`distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`), but the required
  `metal_field_mul --confirm-runs 3` check discarded the candidate after runs
  of `1.021127x`, `1.647003x`, and `0.897910x`. Keep the shared looped reducer
  for multiply paths.
- `macos-metal-field-single-sub-square-only`: narrowing the single-subtraction
  reducer to square-only micro paths, while keeping `field_mul_mod_p` and
  Jacobian kernels on the shared looped reducer, passed correctness and source
  isolation gates. It still failed repeated confirmation:
  `metal_field_square --confirm-runs 3` recorded `confirmation_status=discard`
  with a raw keep at `1.173994x`, then discards at `0.893533x` and
  `0.958969x`. Do not promote the single-sub square reducer until it survives
  repeated paired confirmation on this M3 Air.
- `macos-metal-dp4-pragma-unroll`: adding `#pragma unroll` to only the public
  `steps=8`, `dp_bits=4` loop compiled and preserved the full public oracle
  (`distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`), but failed the stable paired confirmation
  gate. `--confirm-runs 3` recorded `confirmation_status=discard`: run 1 was a
  raw discard at `41,325,489.856177 ops/sec` versus baseline
  `46,336,900.254131` (`0.891848x`), while runs 2 and 3 were raw keeps at
  `1.151186x` and `1.046198x`. Keep the compiler-shaped dp4 loop; a pragma
  hint is too noisy to promote on this M3 Air. A 2026-06-22 retest after
  build-once paired probes first looked promising with two raw keeps
  (`1.244234x`, `1.109164x`), but the stricter three-run confirmation again
  discarded it (`0.721059x`, `0.656319x`, `0.979125x`). Keep the rejection.
- `macos-metal-dp4-q-vec4-loads`: changing only the public dp4 kernel's affine
  jump-table argument from scalar `ulong*` indexing to two `ulong4` loads per
  jump preserved the full public oracle, including `distance_checksum`,
  `dp_count=1000`, and `dp_checksum=0x30a7914972cba014`, but failed repeated
  paired confirmation. `--confirm-runs 3` recorded `confirmation_status=discard`
  with raw runs of `1.098654x`, `0.945560x`, and `1.202391x`. Keep the scalar
  q-table load shape; the vector load version is not durable enough on this M3
  Air.
- `macos-metal-dp4-p-vec4-loads`: changing only the public dp4 kernel's initial
  Jacobian state input from scalar `ulong*` indexing to three `ulong4` loads
  preserved the full public oracle, but failed stable paired confirmation.
  `--confirm-runs 3` recorded `confirmation_status=discard` with raw runs of
  `1.121251x`, `0.764312x`, and `0.921588x`. Keep scalar initial-state loads;
  the vector load spelling increased variance and did not survive the gate.
- `macos-metal-field-mul4-shift`: replacing the standalone Metal `4*x mod p`
  kernel's two modular doublings with a direct two-bit shift plus secp256k1
  high-limb fold preserved correctness, but failed confirmation. The standard
  `metal_field_mul4 --confirm-runs 3` gate recorded raw runs of `1.168038x`,
  `0.867882x`, and `1.489125x`, therefore `confirmation_status=discard`. A
  separate longer-window direct check with `--min-ms 200` measured candidate
  median `242,236,576.685757 ops/sec` versus baseline
  `266,806,848.581355 ops/sec` (`0.907910x`). Keep the existing two-doubling
  spelling for this microkernel on M3 Air.
- `macos-metal-field-neg-branchless`: replacing the standalone Metal
  `field_neg_mod_p` zero-input early return with a `nonzero_mask` preserved the
  field-neg correctness oracle and `make macos-check`, but failed the paired
  confirmation gate. `metal_field_neg --confirm-runs 3` recorded raw speedups
  of `0.998645x`, `1.126949x`, and `1.834335x`, so
  `confirmation_status=discard`. Follow-up direct checks remained too noisy:
  `--min-ms 200` median was `205,671,822.569883 ops/sec` versus baseline
  `183,243,136.099982 ops/sec` (`1.122399x`), but the stricter 5-pair
  `--min-ms 500` check had absolute median `1.008415x` and pairwise median
  `0.947659x`. Keep the current early-return spelling unless a stable gate
  proves a durable win.
- `macos-metal-branchless-addsubdouble`: replacing the conditional add/sub
  branches in `field_add_values`, `field_sub_values`, and
  `field_double_values` with masked limb selection preserved all public Metal
  DP oracle fields (`distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`) and `make macos-check`, but failed stable
  paired confirmation. `metal_jacobian_jump_walk_dp_stable --confirm-runs 3`
  recorded raw runs of `1.429238x`, `0.518187x`, and `1.961694x`, therefore
  `confirmation_status=discard`. A 5-pair `--min-ms 500` direct check measured
  absolute median `0.809660x` and pairwise median `0.974441x`. Keep the current
  branched field add/sub/double helpers; the branchless spelling appears to add
  register/ALU cost without a durable M3 Air win.
- `macos-metal-mixed-add-efd`: replacing the finite mixed-add helper with an
  EFD-style doubled-variable formula was rejected by correctness before
  benchmarking. The candidate compiled and was source-gated, but
  `metal-jacobian-add-test`, `metal-jacobian-walk-test`, and
  `metal-jacobian-jump-walk-test` all failed raw Jacobian coordinate checks.
  Root cause: the formula produces an affine-equivalent but differently scaled
  Jacobian representative, while this challenge's checksum and hidden tests
  require the exact raw coordinate representation emitted by the existing CPU
  oracle. Do not swap mixed-add formulas unless the output representative is
  proven byte-for-byte compatible or the checksum contract is intentionally
  redesigned.
- `macos-metal-zout-early`: scheduling the raw-compatible mixed-add `Z*H`
  output multiply before the `Y3` multiply preserved `make macos-check` and the
  full stable DP oracle (`distance_checksum=0xa45f471493cace2f`,
  `dp_count=1000`, `dp_checksum=0x30a7914972cba014`), but failed paired
  confirmation. `metal_jacobian_jump_walk_dp_stable --confirm-runs 3` recorded
  raw speedups of `0.956924x`, `1.002591x`, and `0.940893x`, so
  `confirmation_status=discard`. Keep the existing source order; moving the
  independent `Z*H` multiply earlier did not improve the M3 compiled kernel.
- `macos-metal-mixed-add-reuse-temps`: reusing dead pre-branch temporaries
  (`z20/z30/u20/s20`) for `HH/HHH/V/X3` in the finite mixed-add helper
  preserved `make macos-check` and the full stable DP oracle, but failed
  paired confirmation. Stable DP speedups were `1.028006x`, `1.074308x`, and
  `0.833597x`, therefore `confirmation_status=discard`. Keep the explicit
  post-branch temporaries; the source-level lifetime reduction did not survive
  repeated M3 confirmation.
- `macos-metal-dp4-scalar-stores-first`: moving the specialized DP4 kernel's
  scalar `out_distances`/`out_flags` stores before the bulk XYZ store preserved
  `make macos-check` and the full stable DP oracle, but failed paired
  confirmation. Stable DP speedups were `0.954509x`, `1.177914x`, and
  `0.608038x`, therefore `confirmation_status=discard`. Keep the existing
  XYZ-first store order; the source-level store scheduling did not produce a
  durable M3 Metal win.
- `macos-metal-dp4-skip-dpmask-buffer`: avoiding the unused host-side
  `dp_mask_buffer` allocation and encoder bind when dispatching the
  `steps=8`, `dp_bits=4` specialized Metal kernel preserved `make macos-check`
  and the public DP oracle (`distance_checksum=0xa45f471493cace2f`,
  `dp_count=1000`, `dp_checksum=0x30a7914972cba014`), but failed stable paired
  confirmation. Raw runs were `1.001230x`, `0.968218x`, and `2.089115x`,
  therefore `confirmation_status=discard`. A 5-pair `--min-ms 500` direct
  check measured absolute median `1.000162x`, pairwise median `1.026724x`,
  and two pairs below `1.0x`; this is effectively a tie, not a durable win.
  Keep the simpler always-bind host path unless future dispatch-heavy tests
  show a stable benefit.
- `macos-wild-resize-fill-main`: replacing `clear` + `push_back` initialization
  of multi-target wild state scratch with `resize` + indexed fill preserved the
  4-target and 16-target correctness oracles (`found_private_key=0x7`,
  `last_dp_count=84/288`) and `make macos-check`, but failed paired
  confirmation. `jacobian_kangaroo_multi16_small --confirm-runs 3` recorded
  raw runs of `0.859027x`, `0.937430x`, and `1.028493x`; the 4-target gate
  recorded `0.915628x`, `0.699428x`, and `1.046553x`, so both ended with
  `confirmation_status=discard`. A direct 5-pair `--min-ms 200` check on the
  4-target shape measured absolute median `0.967105x` and pairwise median
  `0.972254x`. Keep the existing `clear` + `push_back` initialization.
- `macos-affine-defer-active-resize`: moving `active.resize(point_count)` out
  of the all-active Jacobian batch-to-affine fast path preserved
  `make macos-check`, the batch affine checksum oracle, and the 16-target
  multi-target correctness oracle (`found_private_key=0x7`,
  `last_dp_count=288`), but failed paired confirmation. `jacobian_batch_affine`
  recorded raw speedups of `0.989579x`, `0.900283x`, and `1.585928x`, therefore
  `confirmation_status=discard`; the 16-target kangaroo gate recorded
  `0.953983x`, `0.998116x`, and `0.907080x`. Keep the current active-buffer
  resize placement unless a broader batch-affine rewrite proves a durable win.
- `macos-metal-dp4-nounroll`: adding
  `#pragma clang loop unroll(disable)` to only the public `steps=8`,
  `dp_bits=4` Metal loop preserved `make macos-check` and the full DP oracle,
  but failed stable paired confirmation. The stable gate recorded raw speedups
  of `0.794078x`, `0.966583x`, and `1.016373x`, therefore
  `confirmation_status=discard`. Keep the current compiler-shaped dp4 loop;
  neither forced unroll nor forced no-unroll has produced a durable M3 win.
- `macos-metal-dp4-private-inputs`: uploading the public DP4 read-only inputs
  into `MTLResourceStorageModePrivate` buffers before the timed compute, while
  leaving output buffers shared, preserved `make macos-check` and the full DP
  oracle but failed stable paired confirmation. Raw speedups were `0.532957x`,
  `1.216758x`, and `0.729656x`, therefore `confirmation_status=discard`.
  Keep shared input buffers for this benchmark; private storage plus blit
  staging produced too much variance and no durable M3 target win.
- `macos-fused-dp-record`: fusing kangaroo DP collision check and record into
  one `FindOrInsert` probe preserved `make macos-check`, the multi16 oracle
  (`found_private_key=0x7`, `found_target_index=15`, `last_dp_count=288`), and
  the exact collision-verification semantics, but failed paired confirmation.
  `jacobian_kangaroo_multi16_small --confirm-runs 3` recorded raw speedups of
  `0.978479x`, `0.999931x`, and `1.057456x`, therefore
  `confirmation_status=discard`. Keep the existing separate lookup/record path
  unless a larger DP-table rewrite proves a durable gain.
- `macos-lazy-dp-overflow`: replacing each DP bucket's embedded overflow
  vector with a lazy `unique_ptr` preserved `make macos-check` and the multi16
  oracle (`found_private_key=0x7`, `found_target_index=15`,
  `last_dp_count=288`), but failed paired confirmation. Raw speedups were
  `0.975124x`, `0.902597x`, and `1.004439x`, therefore
  `confirmation_status=discard`. Keep the embedded overflow vector; reducing
  slot footprint did not offset pointer indirection/allocation noise.
- `macos-kangaroo-collision-unlikely`: adding a portable `RCK_UNLIKELY` branch
  hint around the single-target and multi-target collision-found checks
  preserved `make macos-check` and the multi16 oracle
  (`found_private_key=0x7`, `found_target_index=15`, `last_dp_count=288`), but
  failed paired confirmation. Raw multi16 speedups were `0.984887x`,
  `0.997734x`, and `1.008084x`, therefore `confirmation_status=discard`. Keep
  the unhinted collision branches; the hint is neutral-to-slightly negative on
  this M3 Air gate.
- `macos-split-tame-wild-dp-tables`: split CPU multi-target DP storage into
  separate tame and wild open-addressed tables, so each distinguished point
  looked up only the opposite side before recording itself. Correctness and
  `make macos-check` stayed intact; the multi16 oracle was preserved
  (`found_private_key=0x7`, `found_target_index=15`, `last_dp_count=288`).
  Paired confirmation discarded it with raw speedups of `1.025170x`,
  `0.985937x`, and `1.005892x`, therefore `confirmation_status=discard`. Keep
  the single shared DP table; split storage helped one run but did not survive
  confirmation.
- `macos-small-affine-scratch`: tried persistent 65-entry scratch arrays for
  the CPU multi-target batch-affine outputs, prefixes, and active flags, using
  them whenever `tame + targets <= 65` while keeping the vector fallback for
  larger API calls. Correctness and `make macos-check` stayed intact; the
  multi16 oracle was preserved (`found_private_key=0x7`,
  `found_target_index=15`, `last_dp_count=288`). Paired confirmation discarded
  it with raw speedups of `0.975740x`, `0.992597x`, and `0.871779x`, therefore
  `confirmation_status=discard`. Keep the current reused vectors; the fixed
  scratch arrays add object footprint and did not produce a durable tiny-gate
  win.
- `macos-metal-dynamic-jump-walk`: added a separate Metal walk architecture
  that computes the kangaroo jump index inside the kernel from the current
  Jacobian state, matching the CPU `x/y/z` mixer and supporting both
  `power2_mask` and `modulo` jump counts. The path has its own CLI
  (`metal-jacobian-dynamic-walk-test` and
  `metal-jacobian-dynamic-walk-bench`), CPU replay oracle, distance checksum,
  DP checksum, source gate, and `steps=8`, `dp_bits=4` specialization with
  packed infinity flags plus struct-row jump-table access. `make macos-check`
  passes. This is a correctness-preserving architecture step toward a real
  GPU kangaroo walk, not a public score-path replacement: a 1-second M3 Air
  check measured dynamic `steps=8`, `jumps=16`, `dp_bits=4` at
  `44,774,506.250851 ops/sec` versus the precomputed-index public path at
  `63,690,640.815902 ops/sec`.
- `macos-metal-dynamic-pow2-dp4`: added a branchless power-of-two
  specialization for the dynamic Metal `steps=8`, `dp_bits=4` walk. The new
  kernel receives `jump_mask = jump_count - 1` and computes
  `jump_index = mixed & jump_mask`, avoiding the generic dynamic kernel's
  per-step power-of-two branch/modulo choice. It preserves the dynamic walk
  CPU replay oracle and `make macos-check`; the `jumps=16` checksum surface
  remained `distance_checksum=0x9ac6c2b53e09365b`, `dp_count=2000`,
  `dp_checksum=0x04df71e7a6aaf936` on the 32768-sample local gate. Manual M3
  paired runs were noisy (`0.544x`, `1.646x`, `1.605x` at 1s; `0.878x` and
  `1.487x` with reversed 3s ordering), so treat this as a low-risk dynamic
  architecture specialization, not a public score claim.
- `macos-metal-dynamic-j16-dp4`: tried an exact dynamic `steps=8`,
  `dp_bits=4`, `jumps=16` kernel using `jump_index = mixed & 0xf` instead of
  the runtime `jump_mask`. Correctness stayed intact with `make macos-check`
  and the dynamic 16384-sample oracle (`distance_checksum=0x5c36c706ffa2cbaa`,
  `dp_count=1017`, `dp_checksum=0xbfd3b2319760e774`), but paired
  autoresearch confirmation discarded it: `0.548550x`, `0.803677x`,
  `1.115114x`, therefore `confirmation_status=discard`. Keep the power-of-two
  `jump_mask` specialization; do not add the exact j16 kernel.
- `macos-metal-dynamic-q-row-local`: tried loading `AffineJumpValue q =
  q_xy[jump_index]` once per step in the dynamic `steps=8`, `dp_bits=4`
  kernels, then passing `q.x*`/`q.y*` into the mixed-add helper. Correctness
  stayed intact with `make macos-check`, the dynamic selftest, pow2/modulo
  smoke runs, and the stable dynamic oracle
  (`distance_checksum=0x5c36c706ffa2cbaa`, `dp_count=1017`,
  `dp_checksum=0xbfd3b2319760e774`), but paired autoresearch confirmation
  discarded it: `1.075168x`, `1.071071x`, `0.991099x`, therefore
  `confirmation_status=discard`. The first two runs were promising, but the
  third missed the 1% gate; keep direct `q_xy[jump_index].field` accesses for
  now.
- `macos-metal-dynamic-u32-mask`: tried computing the dynamic pow2 DP4 jump
  index as `((uint)mixed) & jump_mask` instead of
  `(uint)(mixed & (ulong)jump_mask)`. This is equivalent for the supported
  `jumps <= 32` dynamic path, and correctness stayed intact with
  `make macos-check`, the dynamic selftest, pow2/modulo smoke runs, and the
  stable dynamic oracle (`distance_checksum=0x5c36c706ffa2cbaa`,
  `dp_count=1017`, `dp_checksum=0xbfd3b2319760e774`), but paired
  autoresearch confirmation discarded it: `0.684326x`, `1.196446x`,
  `1.062018x`, therefore `confirmation_status=discard`. Keep the current
  64-bit mask spelling until a broader compiler-shape change makes this stable.
- `macos-metal-dynamic-tg512-default`: tried changing only the dynamic Metal
  walk default threadgroup limit from 256 to 512 while preserving explicit
  `--tg-limit` overrides. A short 4096-sample, 100 ms sweep made 512 look
  promising (`36.837M ops/sec` at 512 versus `14.946M ops/sec` at 256), but the
  stable paired gate rejected it. Correctness stayed intact with
  `make macos-check`, the dynamic CLI test, explicit-override smoke testing,
  and the stable dynamic oracle (`distance_checksum=0x5c36c706ffa2cbaa`,
  `dp_count=1017`, `dp_checksum=0xbfd3b2319760e774`), but confirmation
  recorded raw speedups of `0.453954x`, `0.945385x`, and `0.938971x`, therefore
  `confirmation_status=discard`. Keep the default 256-thread limit for dynamic
  runs; 512 can be explored manually with `--tg-limit` but is not a durable
  default on this M3 gate.
- `macos-metal-dynamic-implicit-distance`: tried replacing the dynamic pow2 DP4
  kernel's scalar-distance table load with `distance += (1UL << jump_index)`.
  This is mathematically equivalent for the current dynamic jump-distance table
  (`distance[i] = 2^i`) and kept the generic modulo path unchanged. Correctness
  stayed intact with `make macos-check`, pow2/modulo dynamic smoke runs, and the
  stable dynamic oracle (`distance_checksum=0x5c36c706ffa2cbaa`,
  `dp_count=1017`, `dp_checksum=0xbfd3b2319760e774`), but paired confirmation
  discarded it with raw speedups of `1.120441x`, `0.898834x`, and `0.900900x`,
  therefore `confirmation_status=discard`. Keep the distance-table load; the
  implicit shift won one noisy run and then lost the stable gate.
- `macos-metal-dynamic-limbfold-mixer`: tried replacing the dynamic Metal
  in-kernel jump selector's 64-bit avalanche multiply with a lightweight
  32-bit limb-fold/xorshift mixer over shifted `x/y/z` limbs, while adding a
  temporary JSON `jump_mixer` marker and jump-bucket histogram oracle so the
  faster partition function could not hide obvious skew. Correctness stayed
  intact with source gates, `make macos-check`, the dynamic CLI test, and a
  stable-shape smoke run; the 16384-sample histogram was reasonably balanced
  (`min=7938`, `max=8359`, `max_deviation_ppm=31006`) and produced
  `distance_checksum=0x0d545b572884b45e`, `dp_count=1003`, and
  `dp_checksum=0xda21c96e8974048a`. Stable paired confirmation discarded it:
  raw speedups were `1.028646x`, `0.690314x`, and `1.119847x`, therefore
  `confirmation_status=discard`. Keep the current 64-bit avalanche mixer until
  a lighter partition function wins all stable confirmations and has a durable
  distribution-quality gate.
- Added `metal_jacobian_dynamic_walk_dp_stable` plus the
  `macos-metal-jacobian-dynamic-walk-stable-bench` target so future dynamic
  Metal candidates can use the same three-sample autoresearch discipline as
  the public precomputed DP gate.
- `macos-metal-dynamic-jump-quality-metrics`: promoted the useful oracle
  surface from the rejected limbfold experiment without changing the dynamic
  jump algorithm or measured Metal kernel. Dynamic benchmark JSON now reports
  `jump_mixer=avalanche64`, `jump_histogram_min_bucket`,
  `jump_histogram_max_bucket`, and `jump_histogram_max_deviation_ppm` from the
  CPU replay oracle. `make macos-check` stayed intact and the stable-shape
  smoke run preserved the existing dynamic oracle
  (`distance_checksum=0x5c36c706ffa2cbaa`, `dp_count=1017`,
  `dp_checksum=0xbfd3b2319760e774`) while reporting histogram quality
  (`min=8082`, `max=8336`, `max_deviation_ppm=17578`). Future lightweight
  mixers now have to expose partition quality as well as speed.
- `macos-metal-dynamic-compact-dp-emission`: added a separate dynamic Metal
  `steps=8`, `dp_bits=4`, power-of-two jump-count kernel for compact
  distinguished-point emission. The new kernel keeps the same in-kernel
  `avalanche64` jump mixer and CPU replay oracle as the full dynamic walk, but
  emits only packed flags, 64-bit scalar distance, and a compact DP checksum
  term instead of copying the final 96-byte Jacobian state. The benchmark JSON
  reports `output_layout=dp_compact` and `output_bytes_per_sample=17` while
  preserving the dynamic oracle (`distance_checksum=0x5c36c706ffa2cbaa`,
  `dp_count=1017`, `dp_checksum=0xbfd3b2319760e774`) plus histogram quality
  (`min=8082`, `max=8336`, `max_deviation_ppm=17578`). Correctness stayed
  intact with `make macos-check`. Initial M3 direct timing was noisy: one
  50 ms paired shape favored compact (`23.032M` versus `15.323M` steps/sec),
  one 200 ms alternating check was neutral/slightly slower (`32.470M` versus
  `32.655M`), and a later warmed stable compact run reached `51.621M`. Treat
  this as promoted layout/correctness infrastructure for future GPU-side DP
  candidate emission, not yet proof that compact emission is always faster than
  the full dynamic final-state oracle. Clean autoresearch on commit `1a03888`
  recorded `status=keep`, median `54,351,372.121311` steps/sec across three
  stable samples (`min=41,407,648.422616`, `max=58,936,405.734283`), with the
  same dynamic oracle and `output_bytes_per_sample=17`.
- `macos-metal-dynamic-compact-dp-tg512`: rejected a compact-DP-only
  threadgroup cap increase from 256 to 512. A first direct sweep looked
  ambiguous (`128=33.200M`, `256=37.218M`, `512=38.891M` steps/sec), but an
  alternating 256/512 sequence favored the current 256 cap. The three 256 runs
  were `29.174M`, `37.518M`, and `32.654M` steps/sec; the three 512 runs were
  `29.076M`, `31.289M`, and `28.083M`, with identical compact dynamic oracle
  fields throughout. Keep the inherited 256 default for compact dynamic DP.
- `macos-metal-dynamic-dp-stream-emission`: added a separate dynamic Metal
  `steps=8`, `dp_bits=4`, power-of-two jump-count kernel that emits only
  actual DP records through a Metal atomic counter. Each stream record is
  `(sample_index, distance, dp_term)`, so runtime JSON reports
  `output_layout=dp_stream`, `output_bytes_per_record=20`, `emitted_records`,
  `dp_capacity`, `dp_stream_overflow`, and `dp_distance_checksum`. The stream
  order is intentionally treated as nondeterministic; host verification
  reconstructs per-sample DP flags and compares every emitted record against
  CPU replay. `make macos-check` passed, and the 16384-sample DP4 smoke run
  emitted `1017` records (`20,340` logical output bytes) with
  `dp_checksum=0xbfd3b2319760e774`, histogram `min=8082`, `max=8336`,
  `max_deviation_ppm=17578`, and no overflow. DP4 direct timing was slower
  than compact/full dynamic in one 200 ms comparison (`35.652M` stream versus
  `43.512M` compact and `54.579M` full dynamic steps/sec), so keep this as a
  sparse-emission architecture probe for higher `dp_bits`, not a DP4 speed win.
  Clean autoresearch on commit `f3599da` recorded `status=keep`, median
  `41,222,124.404033` steps/sec across three stable samples
  (`min=32,638,499.393993`, `max=56,276,112.414753`), with
  `output_bytes_total=20340`, `emitted_records=1017`, and no stream overflow.
- `macos-metal-dynamic-dp-stream-runtime-mask`: added a second sparse-stream
  Metal kernel for `steps=8` and power-of-two jump counts that keeps DP4 on the
  hardcoded stream specialization but uses runtime `ProjectiveDpMask(dp_bits)`
  for non-DP4 shapes. This lets DP8/DP12 sparse-emission probes run without
  changing the dynamic walk mixer or the CPU replay oracle. The new DP8 smoke
  gate and selftest validate emitted `(sample_index, distance, dp_term)`
  records against the same oracle. A direct M3 stable run for `iterations=16384`,
  `steps=8`, `jumps=16`, `dp_bits=8`, and `min_ms=200` emitted `61` records
  (`1,220` logical output bytes), preserved `correctness=true`, reported
  `dp_checksum=0xab1c2cd29cd70a84`, `dp_distance_checksum=0x822e141de4770a0b`,
  histogram `min=8082`, `max=8336`, `max_deviation_ppm=17578`, and measured
  `59.347M` steps/sec. The adjacent DP4 stream check kept the existing oracle
  (`emitted_records=1017`, `output_bytes_total=20340`,
  `dp_checksum=0xbfd3b2319760e774`, `dp_distance_checksum=0x19e43ca50eec2a74`)
  and measured `48.429M` steps/sec in that run. Treat this as an accepted
  sparse-emission capability and a better high-`dp_bits` measurement surface;
  it does not change the underlying kangaroo search complexity. Clean
  autoresearch on commit `0bf960d` recorded `status=keep`, median
  `37,013,170.931979` steps/sec across three stable samples
  (`min=36,486,346.807153`, `max=61,356,369.208598`), with
  `output_bytes_total=1220`, `emitted_records=61`, and no stream overflow.
  Post-merge direct probes on the same shape showed why higher `dp_bits` needs
  repeated sampling before optimization claims: DP12 emitted only `3` records
  (`60` logical output bytes) but measured `30.911M` steps/sec, while DP16
  emitted `0` records and measured `60.199M` steps/sec. The oracle stayed
  correct in both cases, but the spread points to dispatch/scheduler noise and
  arithmetic-walk cost once atomic pressure is mostly gone.
- `macos-metal-dynamic-dp-stream-u32-distance`: added a guarded non-DP4 sparse
  stream kernel that keeps the external distance stream as `uint64_t` but uses
  a 32-bit internal distance accumulator when the host proves
  `max_jump_distance * steps_per_sample <= UINT32_MAX`. DP4 remains on the
  promoted hardcoded DP4 stream kernel. Clean autoresearch on commit `62c5298`
  recorded `status=keep`, median `56,977,760.954224` DP8 steps/sec across
  three stable samples (`min=38,851,216.280614`,
  `max=57,571,900.124877`) versus the previous DP8 stream baseline median
  `37,013,170.931979`. The oracle stayed unchanged:
  `emitted_records=61`, `output_bytes_total=1220`, no overflow,
  `dp_checksum=0xab1c2cd29cd70a84`, and
  `dp_distance_checksum=0x822e141de4770a0b`.
- `macos-metal-dynamic-dp8-stream-const-mask`: added a DP8-specific sparse
  stream kernel that keeps the accepted 32-bit internal distance accumulator
  and hardcodes the DP predicate as `(x0 & 0xFF) == 0`, avoiding the runtime
  `dp_mask` buffer for the common DP8 probe. Clean autoresearch on commit
  `f878edc` recorded `status=keep`, median `58,596,783.649305` DP8 steps/sec
  across three stable samples (`min=41,535,061.854930`,
  `max=63,616,563.008358`) versus the previous DP8 stream baseline median
  `56,977,760.954224`. The oracle stayed unchanged:
  `emitted_records=61`, `output_bytes_total=1220`, no overflow,
  `dp_checksum=0xab1c2cd29cd70a84`, and
  `dp_distance_checksum=0x822e141de4770a0b`.
- `macos-metal-dynamic-dp8-stream-local-jump-row`: updated the accepted DP8
  sparse stream const-mask kernel to load `q_xy[jump_index]` into one local
  `AffineJumpValue` before the infinity/finite mixed-add branch. This keeps
  the exact walk, DP predicate, output layout, and CPU replay oracle unchanged
  while making row reuse explicit for the Metal compiler. Paired autoresearch
  against `main` kept the candidate with median `62,611,858.275279` DP8
  steps/sec (`min=49,232,473.114760`, `max=74,206,989.027034`) versus paired
  baseline median `56,207,874.481378`, `paired_speedup=1.113934`. The oracle
  stayed unchanged: `emitted_records=61`, `output_bytes_total=1220`, no
  overflow, `dp_checksum=0xab1c2cd29cd70a84`, and
  `dp_distance_checksum=0x822e141de4770a0b`. Treat this as a local DP8 stream
  code-generation win, not a new mathematical walk.
- `macos-metal-dynamic-dp8-stream-no-overflow-branch`: removed the DP8 sparse
  stream specialization's in-kernel `slot < dp_capacity` branch and
  `out_overflow` write. This keeps the output layout and host-visible
  `dp_stream_overflow` field unchanged: the host allocates capacity equal to
  sample count, each sample can emit at most one record, and validation still
  rejects impossible `emitted_raw > dp_capacity`. Paired autoresearch against
  `main` kept the candidate with median `55,340,023.527875` DP8 steps/sec
  (`min=40,201,575.992859`, `max=55,936,507.627110`) versus paired baseline
  median `35,628,876.688184`, `paired_speedup=1.553235`. The oracle stayed
  unchanged: `emitted_records=61`, `output_bytes_total=1220`, no overflow,
  `dp_checksum=0xab1c2cd29cd70a84`, and
  `dp_distance_checksum=0x822e141de4770a0b`. Treat this as a DP8-specific
  control-flow reduction guarded by the stream-capacity invariant; keep the
  generic and DP4 stream overflow branches for now.
- `macos-metal-dynamic-dp8-stream-no-steps-arg`: removed the unused
  `steps [[buffer(7)]]` argument and `(void)steps` marker from the fixed
  `steps=8` DP8 sparse stream specialization. This leaves host buffer binding
  shared with the other stream kernels, while the DP8 function signature no
  longer exposes an unused constant argument to the Metal compiler. A direct
  paired run kept the candidate, and a stricter two-run confirmation also
  kept it. Confirmation run 1 recorded candidate median `45,448,401.334809`
  DP8 steps/sec (`min=20,729,618.822593`, `max=49,388,484.655344`) versus
  paired baseline `39,873,314.502482`, `paired_speedup=1.139820`.
  Confirmation run 2 recorded candidate median `42,203,534.028814`
  (`min=39,831,980.594591`, `max=55,623,670.472829`) versus paired baseline
  `37,060,740.353657`, `paired_speedup=1.138767`,
  `confirmation_status=keep`. The oracle stayed unchanged:
  `emitted_records=61`, `output_bytes_total=1220`, no overflow,
  `dp_checksum=0xab1c2cd29cd70a84`, and
  `dp_distance_checksum=0x822e141de4770a0b`.
- `macos-metal-dynamic-dp4-stream-local-jump-row`: applied the same local
  `AffineJumpValue jump = q_xy[jump_index]` row reuse to the accepted DP4
  sparse stream kernel. Paired autoresearch against `main` kept the candidate
  with median `65,061,282.305496` DP4 steps/sec (`min=41,003,406.661886`,
  `max=67,393,074.821646`) versus paired baseline median
  `52,181,168.524837`, `paired_speedup=1.246835`. The oracle stayed unchanged:
  `emitted_records=1017`, `output_bytes_total=20340`, no overflow,
  `dp_checksum=0xbfd3b2319760e774`, and
  `dp_distance_checksum=0x19e43ca50eec2a74`. This suggests explicit affine
  row reuse is a useful Metal code-generation pattern for stream kernels when
  it does not change the walk or DP predicate.
- `macos-metal-dynamic-dp-count-probe`: added a count-only Metal diagnostic for
  the same dynamic `steps=8`, power-of-two jump walk. It runs the runtime
  `ProjectiveDpMask(dp_bits)` predicate and increments only one atomic
  `dp_count`, writing no stream records, distances, or DP checksum terms.
  Runtime JSON reports `output_layout=dp_count`, `output_bytes_total=4`, and
  `distance_tracking=none`; host correctness compares the GPU count against
  CPU replay. This is a measurement surface, not a candidate-emission path.
  Clean autoresearch on commit `4b4014c` recorded `status=keep`, median
  `53,546,106.476522` steps/sec across three DP8 stable samples
  (`min=30,340,248.668051`, `max=56,088,173.485608`), with `dp_count=61`.
  A same-worktree DP8 stream rerun recorded median `39,287,501.787886`
  steps/sec (`min=22,269,031.791864`, `max=40,036,781.483343`) while preserving
  `emitted_records=61`, `output_bytes_total=1220`, and
  `dp_checksum=0xab1c2cd29cd70a84`. The count-only probe suggests record writes
  are visible at DP8, but the wide spread still says the arithmetic walk and
  local Metal scheduling dominate; do not treat count-only as a replacement for
  stream emission.
- `macos-metal-dynamic-dp-count-first-inf`: rejected a count-only specialization
  for the benchmark sample shape where only `p[0]` starts at infinity. The
  prototype guarded the specialized kernel behind a host-side
  `HasOnlyFirstInfinity(p)` check and used finite mixed-add for all other lanes,
  while keeping the generic count kernel as fallback. Source and CLI smoke
  checks passed, and direct DP8 probing preserved `correctness=true` with
  `dp_count=61`, but clean autoresearch discarded the candidate: median
  `41,917,696.770121` steps/sec across three samples
  (`min=39,051,687.094501`, `max=59,087,644.282271`) versus the existing
  count-only DP8 baseline median `53,546,106.476522`. Do not promote this
  specialization; the first-infinity branch is not the next useful bottleneck
  on the local M3 profile.
- `macos-metal-dynamic-dp-stream-group-reserve`: rejected a stream-emission
  variant that used threadgroup-local DP counting plus one global reservation
  per threadgroup, then wrote each DP record into that reserved block. The
  oracle stayed intact (`emitted_records=61`,
  `dp_checksum=0xab1c2cd29cd70a84`,
  `dp_distance_checksum=0x822e141de4770a0b`, no overflow), but the final clean
  DP8 autoresearch run on commit `e48ade7` discarded it: median
  `34,241,001.868863` steps/sec across three samples
  (`min=30,214,085.775297`, `max=56,510,398.787670`) versus the existing DP8
  stream baseline median `37,013,170.931979`. A preliminary DP4 run with the
  same group-reserve strategy also discarded at median `38,666,572.600191`
  steps/sec. Keep the simple per-record global atomic path; the extra
  threadgroup synchronization is not a durable win on this M3 profile.
- `macos-metal-dynamic-dp-stream-u32-pow2-distance`: rejected a follow-up to
  the accepted DP8 u32-distance stream kernel that replaced the guarded
  `jump_distances[jump_index]` load with `1U << jump_index` when the host
  verified the power-of-two distance table. Correctness stayed intact
  (`emitted_records=61`, `dp_checksum=0xab1c2cd29cd70a84`,
  `dp_distance_checksum=0x822e141de4770a0b`, no overflow), but clean
  autoresearch on commit `413b1cb` discarded it: median `40,186,882.764342`
  steps/sec across three DP8 samples (`min=32,100,455.469615`,
  `max=58,747,215.509733`) versus the promoted u32-distance baseline median
  `56,977,760.954224`. Keep the table-load u32-distance kernel; the shift form
  is too low-tail-heavy on this M3 profile.
- `macos-metal-dynamic-compact-dp8-u32`: rejected adding a dense compact-output
  runtime-mask DP8 kernel with guarded 32-bit internal distance accumulation.
  The oracle stayed intact (`dp_count=61`,
  `dp_checksum=0xab1c2cd29cd70a84`, `distance_checksum=0x5c36c706ffa2cbaa`),
  but three direct stable samples measured `35,048,956.794514`,
  `35,537,101.509200`, and `37,826,360.142984` steps/sec. Median
  `35,537,101.509200` is far below the promoted sparse stream DP8 median
  `56,977,760.954224`, so do not add a dense compact DP8 speed path; on this
  M3 profile, the sparse stream with per-record atomics still wins at DP8.
- `macos-metal-dynamic-compact-dp-local-jump-row`: rejected applying the local
  affine row-reuse pattern to the DP4 compact-output kernel. The oracle stayed
  intact (`distance_checksum=0x5c36c706ffa2cbaa`, `dp_count=1017`,
  `dp_checksum=0xbfd3b2319760e774`), but paired autoresearch discarded it:
  candidate median `28,896,380.858909` steps/sec (`min=28,120,992.430797`,
  `max=38,095,787.769098`) versus paired baseline median
  `54,829,695.882427`, `paired_speedup=0.527021`. Keep the row-reuse pattern
  limited to sparse stream kernels unless a compact-output candidate
  independently wins.
- `macos-metal-dynamic-walk-local-jump-row`: rejected applying the same local
  affine row-reuse pattern to the DP4 full-output dynamic walk kernel. The
  point/distance/DP oracle stayed intact (`distance_checksum=
  0x5c36c706ffa2cbaa`, `dp_count=1017`,
  `dp_checksum=0xbfd3b2319760e774`), but paired autoresearch discarded it:
  candidate median `37,929,646.083412` steps/sec (`min=31,352,106.536932`,
  `max=53,617,873.109935`) versus paired baseline median
  `49,708,107.924197`, `paired_speedup=0.763047`. Keep explicit local affine
  row reuse scoped to sparse stream kernels for now.
- `macos-metal-dynamic-dp-count-local-jump-row`: rejected applying the local
  affine row-reuse pattern to the DP8 count-only kernel. Correctness stayed
  intact (`dp_count=61`), but paired autoresearch discarded it: candidate
  median `31,386,712.313105` steps/sec (`min=27,381,736.631399`,
  `max=53,030,510.888202`) versus paired baseline median
  `38,552,397.853331`, `paired_speedup=0.814131`. This keeps the row-reuse
  rule scoped to sparse stream kernels; in count-only, register/codegen cost
  outweighs removing repeated row references.
- `macos-metal-dynamic-u32-stream-local-jump-row`: rejected applying local
  affine row reuse to the generic runtime-mask u32-distance stream kernel for
  non-DP4/non-DP8 sparse cases. A direct alternating baseline/candidate probe
  preserved the DP stream oracle for DP6, DP10, and DP12, but the median signal
  was not generally positive: DP6 candidate `31,739,129.323942` steps/sec
  versus baseline `30,740,222.068791` (`1.032495x`), DP10 candidate
  `27,665,051.593804` versus baseline `35,628,935.854107` (`0.776477x`),
  and DP12 candidate `39,021,049.148668` versus baseline
  `40,364,460.030482` (`0.966718x`). Keep the generic u32 stream's direct
  `q_xy[jump_index]` row references; local row reuse remains limited to the
  dedicated DP4 and DP8 sparse stream kernels.
- `macos-metal-dynamic-dp8-stream-j16-mask`: rejected hardcoding the DP8 stream
  jump mask to `0xF` behind a `jumps.size()==16` host guard. The prototype
  removed the runtime `jump_mask` constant from the DP8+j16 kernel while
  keeping the same u32 internal distance accumulator and DP8 predicate.
  Correctness stayed intact (`emitted_records=61`,
  `dp_checksum=0xab1c2cd29cd70a84`,
  `dp_distance_checksum=0x822e141de4770a0b`, no overflow), and an initial
  direct sample reached `59,100,828.090287` steps/sec. Clean autoresearch
  discarded the candidate, however: median `48,463,423.411911` steps/sec
  (`min=29,267,546.773174`, `max=56,335,643.461168`) versus the promoted DP8
  const-mask stream median `58,596,783.649305`. Keep the runtime `jump_mask`
  buffer in the accepted DP8 stream path; the hardcoded j16 variant worsened
  the low tail on this M3 profile.
- `macos-metal-dynamic-dp8-stream-tg64-default`: rejected changing only the
  DP8 sparse stream default threadgroup size from 256 to 64 while preserving
  explicit `--tg-limit` overrides and leaving DP4 defaults unchanged. The
  direct smoke sample looked promising at `60,580,026.523581` steps/sec with
  the same DP8 stream oracle (`emitted_records=61`,
  `dp_checksum=0xab1c2cd29cd70a84`,
  `dp_distance_checksum=0x822e141de4770a0b`), but paired autoresearch against
  `main` discarded it. The paired candidate median was
  `32,422,230.207947` steps/sec (`min=28,376,163.880242`,
  `max=65,260,356.568942`) versus paired baseline median
  `60,342,525.488163`, for `paired_speedup=0.537303`. Keep the accepted 256
  default for DP8 stream; a smaller threadgroup worsens low-tail stability even
  when it occasionally spikes higher.
- `macos-metal-dynamic-x0-mixer`: rejected replacing the dynamic Metal and CPU
  replay jump mixer with direct low bits of projective `x0`. This is a
  mathematically natural partition function and removes the 64-bit avalanche
  multiply from every dynamic step, but the paired gate did not support it.
  The DP8 stream oracle stayed self-consistent with CPU replay and the
  histogram remained reasonable (`min=8039`, `max=8347`,
  `max_deviation_ppm=18921`), but it changed the walk shape
  (`emitted_records=66`, `dp_checksum=0x641ef713d473d79e`,
  `dp_distance_checksum=0x7157e1d08c6afc2b`) and paired autoresearch
  discarded it: candidate median `29,799,267.712366` steps/sec
  (`min=27,603,086.503402`, `max=33,348,152.912071`) versus paired baseline
  median `31,783,403.981837`, `paired_speedup=0.937573`. Keep the current
  `avalanche64` mixer until a cheaper partition function wins paired
  confirmation and preserves distribution quality.
- `macos-metal-dp8-stream-firstinf`: rejected specializing the DP8 sparse
  stream kernel for the benchmark shape where only `p[0]` starts at infinity.
  The prototype removed the `p_infinity[id]` buffer load and used
  `bool inf = id == 0` behind a host guard equivalent to
  `HasOnlyFirstInfinity(p)`. Correctness stayed intact
  (`emitted_records=61`, `dp_checksum=0xab1c2cd29cd70a84`,
  `dp_distance_checksum=0x822e141de4770a0b`, no overflow), but direct samples
  were already poor (`2,059,055.018133` and `2,239,296.581508` steps/sec).
  Paired autoresearch against `main` discarded it with candidate median
  `910,556.434373` steps/sec (`min=836,748.733737`,
  `max=1,191,971.044843`) versus paired baseline median
  `1,799,640.261424`, `paired_speedup=0.505966`. Do not remove the tiny
  `p_infinity` load in this path; the first-lane special case appears to hurt
  generated code or lane behavior far more than it saves on this M3 profile.
- `macos-metal-dp8-stream-finite-tail`: rejected splitting the DP8 sparse
  stream path into a branch-free finite-tail kernel for samples `p[1..]` plus a
  CPU append for `p[0]`. The prototype was guarded by “only first infinity” and
  a CPU precheck that no tail sample reaches infinity during the eight-step
  walk, so correctness stayed intact (`emitted_records=61`,
  `dp_checksum=0xab1c2cd29cd70a84`,
  `dp_distance_checksum=0x822e141de4770a0b`, no overflow). Direct samples were
  `32,662,656.237789` and `33,962,257.983414` steps/sec. Paired autoresearch
  discarded the candidate with median `34,715,854.003069` steps/sec
  (`min=34,590,529.131153`, `max=34,834,754.705358`) versus paired baseline
  median `50,834,993.140300`, `paired_speedup=0.682913`. Keep the accepted
  single-kernel DP8 stream path; removing the infinity branch makes the kernel
  shape worse on this M3 profile.
- `autoresearch-command-backed-experiments`: accepted runner infrastructure for
  parameterized probes that should not grow the Makefile. Experiments can now
  set `build_target` plus `bench_command`; paired baselines run the same
  command in both worktrees and still parse the final benchmark JSON line. The
  first command-backed gate is
  `metal_jacobian_dynamic_dp_stream_dp10`, which recorded a clean same-code
  paired DP10 stream row at commit `9aae4d3`: candidate median
  `30,209,443.482633` steps/sec (`min=26,595,828.945919`,
  `max=46,241,502.977642`) versus paired baseline median
  `33,775,886.308299`, `paired_speedup=0.894409`, `status=discard`. The oracle
  was stable (`emitted_records=15`,
  `dp_distance_checksum=0xb6973c2035ff6351`,
  `dp_checksum=0xcbfdc2badaf0e57a`); treat this as harness coverage and a DP10
  baseline record, not a solver-code promotion.
- `macos-metal-dynamic-dp10-stream-specialization`: rejected adding a dedicated
  DP10 sparse stream kernel with hardcoded `0x3FF` predicate, u32 internal
  distance, and local affine row reuse. The prototype preserved the DP10 stream
  oracle (`emitted_records=15`,
  `dp_distance_checksum=0xb6973c2035ff6351`,
  `dp_checksum=0xcbfdc2badaf0e57a`), but command-backed paired autoresearch
  discarded it: candidate median `54,324,631.189670` steps/sec
  (`min=31,337,310.278256`, `max=59,913,902.741406`) versus paired baseline
  median `57,359,097.012105`, `paired_speedup=0.947097`. Keep DP10 on the
  generic runtime-mask u32-distance stream path; DP4/DP8 remain the only
  accepted const-mask stream specializations.
- `macos-metal-dynamic-dp10-stream-tg64-default`: rejected changing only the
  DP10 sparse stream default threadgroup size from 256 to 64 while preserving
  explicit `--tg-limit` overrides. A direct sweep showed a promising tg64
  sample, and the oracle stayed intact (`emitted_records=15`,
  `dp_distance_checksum=0xb6973c2035ff6351`,
  `dp_checksum=0xcbfdc2badaf0e57a`), but command-backed paired autoresearch
  discarded it: candidate median `55,120,744.100756` steps/sec
  (`min=44,358,197.083863`, `max=61,234,592.955097`) versus paired baseline
  median `57,341,488.499819`, `paired_speedup=0.961272`. Keep the DP10 stream
  default at the shared 256 threadgroup limit.
- `macos-metal-dynamic-dp6-stream-specialization`: added a command-backed DP6
  sparse stream gate, then rejected a dedicated DP6 const-mask/local-row
  kernel. The prototype preserved the DP6 stream oracle
  (`emitted_records=248`,
  `dp_distance_checksum=0xcd602d19c5edfa05`,
  `dp_checksum=0xb302d085b993018a`), but paired autoresearch discarded it:
  candidate median `39,834,931.340750` steps/sec
  (`min=30,115,365.114382`, `max=59,170,008.949403`) versus paired baseline
  median `55,663,782.861444`, `paired_speedup=0.715635`. Keep DP6 on the
  generic runtime-mask u32-distance stream path; the new DP6 gate remains for
  future density-intermediate experiments.
- `macos-metal-dynamic-dp8-stream-u32-output-distance`: rejected narrowing the
  DP8 sparse stream record distance output from 64 to 32 bits. The prototype
  reduced `output_bytes_per_record` from `20` to `16` and preserved the DP8
  oracle (`emitted_records=61`,
  `dp_distance_checksum=0x822e141de4770a0b`,
  `dp_checksum=0xab1c2cd29cd70a84`), but paired autoresearch discarded it:
  candidate median `32,233,487.865141` steps/sec
  (`min=31,206,309.497131`, `max=53,615,043.294360`) versus paired baseline
  median `38,353,440.458919`, `paired_speedup=0.840433`. Keep DP8 stream
  record distances as 64-bit host-visible output; the saved output bytes do
  not offset the extra host/path complexity on this M3 profile.
- `macos-metal-dynamic-dp4-stream-no-overflow-branch`: rejected applying the
  accepted DP8 no-overflow branch idea to the denser DP4 sparse stream
  specialization. The prototype preserved the DP4 stream oracle
  (`emitted_records=1017`, `output_bytes_total=20340`,
  `dp_distance_checksum=0x19e43ca50eec2a74`,
  `dp_checksum=0xbfd3b2319760e774`), but paired autoresearch discarded it:
  candidate median `31,405,650.680564` steps/sec
  (`min=27,107,472.594526`, `max=58,509,134.530611`) versus paired baseline
  median `41,006,978.823522`, `paired_speedup=0.765861`. Keep the overflow
  branch in the DP4 sparse stream kernel; branch removal is currently a
  DP8-specific win, not a general stream rule.
- `macos-metal-dynamic-u32-stream-no-overflow-branch`: rejected removing the
  `slot < dp_capacity` / `out_overflow` branch from the shared runtime-mask
  u32-distance stream kernel. Correctness stayed intact for DP10
  (`emitted_records=15`, `dp_distance_checksum=0xb6973c2035ff6351`,
  `dp_checksum=0xcbfdc2badaf0e57a`) and DP6 (`emitted_records=248`,
  `dp_distance_checksum=0xcd602d19c5edfa05`,
  `dp_checksum=0xb302d085b993018a`). Performance split by density: DP10 kept
  with candidate median `42,278,414.551117` steps/sec
  (`min=26,790,936.748830`, `max=57,431,328.740594`) versus paired baseline
  median `29,964,798.774474`, `paired_speedup=1.410936`, while DP6 discarded
  with candidate median `50,415,308.939320` steps/sec
  (`min=33,340,118.517518`, `max=56,064,889.448233`) versus paired baseline
  median `59,073,704.479935`, `paired_speedup=0.853431`. Keep the generic
  u32 stream overflow branch; test any sparse DP10 no-overflow idea as a
  dedicated specialization rather than a shared-path change.
- `macos-metal-dynamic-dp10-stream-no-overflow-specialization`: rejected the
  follow-up dedicated DP10 const-mask/no-overflow kernel. It avoided the
  runtime DP-mask buffer and the stream overflow branch while keeping direct
  `q_xy[jump_index]` row access, so it did not repeat the previously rejected
  DP10 local-row specialization. Correctness stayed intact:
  `emitted_records=15`, `output_bytes_total=300`,
  `dp_distance_checksum=0xb6973c2035ff6351`, and
  `dp_checksum=0xcbfdc2badaf0e57a`. Two paired confirmation runs both
  discarded the candidate: run 1 median `50,590,171.559774` steps/sec
  (`min=38,859,111.868345`, `max=54,102,926.810683`) versus paired baseline
  `57,834,567.954473`, `paired_speedup=0.874739`; run 2 median
  `36,257,628.573029` steps/sec (`min=34,276,813.257650`,
  `max=54,091,492.986425`) versus paired baseline `56,053,192.101321`,
  `paired_speedup=0.646843`, `confirmation_status=discard`. Do not promote a
  DP10 no-overflow specialization from the earlier single-run keep signal.
- `macos-metal-dynamic-dp4-stream-no-steps-arg`: rejected applying the
  accepted DP8 no-steps-argument cleanup to the fixed `steps=8` DP4 sparse
  stream specialization. Correctness stayed intact:
  `emitted_records=1017`, `output_bytes_total=20340`,
  `dp_distance_checksum=0x19e43ca50eec2a74`, and
  `dp_checksum=0xbfd3b2319760e774`. Paired autoresearch discarded it with
  candidate median `49,544,294.377036` DP4 steps/sec
  (`min=41,430,851.669889`, `max=57,349,092.786802`) versus paired baseline
  median `50,583,214.355980`, `paired_speedup=0.979461`. Keep the DP4 stream
  kernel signature unchanged; the removed unused `steps` argument remains a
  DP8-specific codegen win.
- `macos-metal-dynamic-dp8-stream-u32-jump-distances`: rejected packing the
  DP8 sparse stream jump-distance table as `uint32_t` and switching the DP8
  kernel argument from `constant ulong* jump_distances` to
  `constant uint* jump_distances`. Correctness stayed intact:
  `emitted_records=61`, `output_bytes_total=1220`,
  `dp_distance_checksum=0x822e141de4770a0b`, and
  `dp_checksum=0xab1c2cd29cd70a84`. Paired autoresearch discarded the
  candidate with median `40,455,982.284936` DP8 steps/sec
  (`min=34,922,296.143458`, `max=59,280,850.861247`) versus paired baseline
  median `54,871,015.351268`, `paired_speedup=0.737292`. Keep the DP8 stream
  distance table as 64-bit host data with the explicit in-kernel cast to
  `uint`; the narrower table changes the compiled/buffer shape unfavorably on
  this M3 profile.
- `macos-metal-dynamic-dp8-stream-j16-mask-after-no-steps`: rejected a
  dedicated `jumps=16` DP8 sparse stream kernel after the accepted DP8
  no-overflow and no-steps-argument changes. The candidate hardcoded the jump
  mask to `0xF` while preserving the DP8 no-capacity/overflow shape, but paired
  autoresearch showed a large regression. Correctness stayed intact:
  `emitted_records=61`, `output_bytes_total=1220`,
  `dp_distance_checksum=0x822e141de4770a0b`, and
  `dp_checksum=0xab1c2cd29cd70a84`. Candidate median was
  `20,232,288.968150` DP8 steps/sec (`min=19,756,963.738793`,
  `max=32,213,287.036171`) versus paired baseline median
  `52,397,986.361443`, `paired_speedup=0.386127`. Keep the shared DP8
  `jump_mask` specialization for `jumps=16`; the extra entry point/codegen
  shape is not favorable on this M3 profile.
- `macos-metal-dynamic-dp8-count-specialization`: rejected a dedicated DP8
  count-only kernel that hardcoded the DP mask to `0xFF` and removed the
  unused `steps` plus runtime `dp_mask` arguments from the dispatch. Correctness
  stayed intact for both variants (`output_layout=dp_count`, `dp_count=61`,
  `distance_tracking=none`, `correctness=true`). The first variant used a local
  `AffineJumpValue` row and was borderline but still below baseline: candidate
  median `43,773,240.202096` steps/sec (`min=37,157,424.295935`,
  `max=48,847,567.549002`) versus paired baseline median
  `44,442,548.274759`, `paired_speedup=0.984940`. The follow-up variant kept
  direct `q_xy[jump_index]` loads like the generic count kernel and regressed
  more: candidate median `50,394,707.554658` steps/sec
  (`min=42,322,353.086826`, `max=69,338,828.177601`) versus paired baseline
  median `68,896,134.342987`, `paired_speedup=0.731459`. Keep the generic
  runtime-mask count kernel for DP8; the DP8 stream-specific signature cleanup
  does not transfer to the count-only diagnostic path.
- `macos-metal-dynamic-dp-count-no-steps-arg`: rejected the more conservative
  shared count-only cleanup that removed only the unused `steps` kernel
  argument and host buffer binding while keeping the generic runtime DP mask
  path. Correctness stayed intact (`output_layout=dp_count`, `dp_count=61`,
  `distance_tracking=none`, `correctness=true`), but paired autoresearch
  discarded it with candidate median `36,757,514.206820` steps/sec
  (`min=20,607,438.290084`, `max=58,109,926.786046`) versus paired baseline
  median `40,073,503.015154`, `paired_speedup=0.917252`. Keep the count-only
  `steps` argument even though the DP8 sparse stream kernel benefits from
  removing its unused `steps` argument.
- `macos-metal-dynamic-dp-count-tg128-default`: rejected changing the default
  threadgroup cap for the DP8 count-only diagnostic path from 256 to 128. A
  manual one-pass sweep was suggestive but not decisive: tg64
  `37,886,894.946852`, tg128 `47,358,509.954244`, tg256
  `45,933,576.464768`, tg512 `39,650,554.258312`, and tg1024
  `37,105,598.948840` steps/sec, all with `dp_count=61` and
  `correctness=true`. The default-128 candidate preserved correctness and the
  JSON reported `threadgroup_limit=128`, but confirmation was contradictory:
  initial paired run kept with `42,541,651.351471` versus baseline
  `41,943,177.109020` (`paired_speedup=1.014269`); confirmation run 1
  discarded with `36,984,641.449378` versus `41,255,140.214432`
  (`paired_speedup=0.896486`); confirmation run 2 kept with
  `56,888,060.463320` versus `42,842,463.991402`
  (`paired_speedup=1.327843`), but overall `confirmation_status=discard`.
  Keep the shared default threadgroup cap at 256 for count-only.
- `macos-metal-dynamic-dp12-stream-gate`: added a command-backed autoresearch
  gate and Makefile stable target for the very sparse DP12 stream shape
  (`--steps 8 --jumps 16 --dp-bits 12 --min-ms 200`). The initial baseline
  preserved the stream oracle with `emitted_records=3`, `output_bytes_total=60`,
  `dp_distance_checksum=0xfb58c602127bde02`, and
  `dp_checksum=0xccdf6d15eaf2c6b0`; median was `39,603,303.230057` steps/sec
  (`min=32,723,053.250208`, `max=39,707,503.885942`). Use this gate for DP12
  sparse-stream experiments instead of ad hoc CLI runs.
- `macos-metal-dynamic-dp12-stream-no-overflow`: rejected a dedicated DP12
  sparse stream kernel that hardcoded the DP predicate to `x0 & 0xFFF`,
  removed the runtime `dp_mask`, and removed the in-kernel
  `slot < dp_capacity` / overflow branch while keeping direct
  `q_xy[jump_index]` row loads. Correctness stayed intact:
  `emitted_records=3`, `output_bytes_total=60`,
  `dp_distance_checksum=0xfb58c602127bde02`, and
  `dp_checksum=0xccdf6d15eaf2c6b0`. Paired autoresearch discarded it with
  candidate median `35,307,732.434448` steps/sec (`min=33,279,343.640396`,
  `max=43,014,286.776302`) versus paired baseline median
  `39,646,497.326093`, `paired_speedup=0.890564`. Keep DP12 on the generic
  runtime-mask u32-distance stream kernel.
- `macos-metal-dynamic-dp12-stream-tg128-default`: accepted changing only the
  default threadgroup cap for the sparse DP12 stream shape from 256 to 128 when
  `--tg-limit` is omitted. Explicit `--tg-limit` overrides remain preserved.
  A sequential manual sweep first suggested the shape: tg64
  `39,758,545.634387`, tg128 `43,101,368.645947`, tg256
  `38,769,840.616246`, tg512 `38,922,032.447806`, and tg1024
  `33,594,476.616126` DP12 steps/sec. The accepted candidate kept the DP12
  stream oracle unchanged (`emitted_records=3`, `output_bytes_total=60`,
  `dp_distance_checksum=0xfb58c602127bde02`,
  `dp_checksum=0xccdf6d15eaf2c6b0`, `correctness=true`). Paired autoresearch
  against `main` first kept candidate median `22,566,572.599272` versus
  baseline `21,412,443.160846` (`paired_speedup=1.053900`), then a two-run
  confirmation kept candidate median `21,793,968.794878` versus baseline
  `19,686,379.815135` (`paired_speedup=1.107058`,
  `confirmation_status=keep`). This is a narrow host scheduling default, not a
  math/kernel rewrite.
- `macos-metal-dynamic-dp10-stream-tg512-default`: rejected changing only the
  sparse DP10 stream default threadgroup cap from 256 to 512. A forward
  explicit sweep was order-sensitive and favored larger caps (tg64
  `46,775,513.979123`, tg128 `38,834,797.847844`, tg256
  `44,277,287.550557`, tg512 `59,385,113.753600`, tg1024
  `64,249,919.740382` steps/sec), while the reverse sweep contradicted that
  shape (tg1024 `42,969,570.860115`, tg512 `57,849,625.265317`, tg256
  `69,624,658.624707`, tg128 `74,849,551.868420`, tg64
  `74,568,413.740722`). The candidate preserved the DP10 stream oracle
  (`emitted_records=15`, `output_bytes_total=300`,
  `dp_distance_checksum=0xb6973c2035ff6351`,
  `dp_checksum=0xcbfdc2badaf0e57a`, `correctness=true`) and the first paired
  run kept it at candidate median `27,932,757.086802` versus baseline
  `26,237,218.701084` (`paired_speedup=1.064623`), but the two-run
  confirmation discarded it with candidate median `19,095,076.656232` versus
  baseline `20,268,925.094271` (`paired_speedup=0.942086`,
  `confirmation_status=discard`). Keep DP10 on the shared 256 default.
- `macos-metal-dynamic-dp6-stream-tg128-default`: rejected changing only the
  sparse DP6 stream default threadgroup cap from 256 to 128. Manual sweeps
  made 128 look plausible despite order sensitivity: forward tg64
  `34,107,852.997397`, tg128 `36,102,616.034815`, tg256
  `19,761,247.664927`, tg512 `5,075,094.262499`, tg1024
  `10,690,580.915218`; reverse tg1024 `32,946,087.816687`, tg512
  `25,425,808.259383`, tg256 `27,995,725.568597`, tg128
  `36,303,745.785860`, tg64 `22,677,577.871633`. The candidate preserved the
  DP6 stream oracle (`emitted_records=248`, `output_bytes_total=4960`,
  `dp_distance_checksum=0xcd602d19c5edfa05`,
  `dp_checksum=0xb302d085b993018a`, `correctness=true`) and the first paired
  run kept it at candidate median `23,221,999.015625` versus baseline
  `20,744,125.284209` (`paired_speedup=1.119449`). Confirmation was unstable:
  one run discarded candidate median `22,611,569.767587` versus baseline
  `28,144,092.643342`, while the next kept candidate median
  `41,127,821.914115` versus baseline `37,804,523.817718`; overall
  `confirmation_status=discard`. Keep DP6 on the shared 256 default.
- `macos-metal-public-dp4-stable-baseline-refresh`: recorded a same-code
  stable public score-path baseline after the DP stream experiments. No code
  changed. The gate preserved the public oracle
  (`distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`, `correctness=true`) with median
  `27,922,343.656972` mixed-add steps/sec (`min=20,150,535.194783`,
  `max=34,517,404.415027`). A same-turn Benchforge local run at
  `18,036,840.326574` ops/sec was lower, so treat single local Benchforge runs
  as noisy and keep using paired/stable gates for promotion decisions.
- `macos-metal-dynamic-dp16-large-stream-gate`: accepted a command-backed
  autoresearch gate for very sparse DP16 stream experiments using
  `--iterations 65536 --steps 8 --jumps 16 --dp-bits 16 --min-ms 200`. The
  smaller `sample_count=16384` DP16 shape emitted zero records and is not a
  useful stream gate. The large shape emits one record and preserved the oracle:
  `emitted_records=1`, `output_bytes_total=20`,
  `dp_distance_checksum=0x9e3779b97f4bab4a`,
  `dp_checksum=0xebe643771995a1fa`, and `correctness=true`. Baseline median at
  the shared 256 default was `52,989,830.333319` DP16 steps/sec
  (`min=32,678,324.080216`, `max=70,280,067.920733`). Manual sweeps did not
  justify a default change: DP14 was order-sensitive with one emitted record,
  and DP16-large kept 256/512 close enough that a 512 default would be another
  noisy scheduling bet rather than a confirmed improvement.
- `macos-metal-dynamic-dp14-stream-gate`: accepted a command-backed
  autoresearch gate between the DP12 and DP16 sparse stream shapes using
  `--iterations 16384 --steps 8 --jumps 16 --dp-bits 14 --min-ms 200`. This
  shape emits one record without needing the larger DP16 sample count, giving
  future sparse-stream experiments a middle-density oracle. Baseline median was
  `34,457,601.167211` DP14 steps/sec (`min=34,358,055.162337`,
  `max=44,057,552.043881`) with `emitted_records=1`,
  `output_bytes_total=20`, `dp_distance_checksum=0x9e3779b97f4b39c1`,
  `dp_checksum=0x252996ea8a0dca38`, and `correctness=true`.
- `macos-metal-dynamic-dp8-stream-tg-sweep-after-no-overflow`: recorded a
  manual explicit `--tg-limit` sweep after accepting the DP8 no-overflow
  branch. No production code changed. The DP8 stream oracle stayed unchanged
  for all samples (`emitted_records=61`, `output_bytes_total=1220`,
  `dp_distance_checksum=0x822e141de4770a0b`,
  `dp_checksum=0xab1c2cd29cd70a84`). One 200 ms sweep measured tg64
  `47,760,021.663871`, tg128 `62,608,992.429817`, tg256
  `65,340,428.908829`, tg512 `63,549,730.568347`, and tg1024
  `64,773,844.447836` DP8 steps/sec. Keep the existing 256 default; the
  accepted no-overflow branch does not justify reopening the previously
  rejected tg64 default.
- `macos-metal-dynamic-dp16-stream-no-overflow-specialization`: rejected a
  dedicated DP16 const-mask/no-overflow stream kernel. The candidate preserved
  the sparse DP16-large oracle (`emitted_records=1`, `output_bytes_total=20`,
  `dp_distance_checksum=0x9e3779b97f4bab4a`,
  `dp_checksum=0xebe643771995a1fa`, `correctness=true`), but the paired
  autoresearch gate discarded it: candidate median `58,886,361.624760` versus
  baseline median `81,212,851.782611` DP16 steps/sec
  (`paired_speedup=0.725087`). Keep DP16 on the generic runtime-mask
  u32-distance stream kernel; the DP8 no-overflow success does not transfer to
  very sparse DP16 on this M3 Air.
- `macos-metal-dp4-soa-input-layout`: rejected changing the public
  `steps=8`, `dp_bits=4` jump-walk input layout from 12-limb AoS to a
  structure-of-arrays buffer while keeping the final output AoS and the
  fallback paths unchanged. Smoke tests preserved both the public oracle
  (`distance_checksum=0xa45f471493cace2f`, `dp_count=1000`,
  `dp_checksum=0x30a7914972cba014`) and the verifier fallback shape
  (`distance_checksum=0xbab72b58ebefa9dc`, `dp_count=249`,
  `dp_checksum=0x4a7f2853a4a9f546`). The first paired gate kept it at
  candidate median `31,361,809.164586` versus baseline
  `27,944,840.858156` ops/sec (`paired_speedup=1.122275`), but the immediate
  confirmation discarded it at candidate median `19,168,913.507147` versus
  baseline `20,875,904.079754` ops/sec (`paired_speedup=0.918232`). Keep the
  promoted AoS input layout for the public DP4 path; initial memory-coalescing
  wins are not stable enough to offset the changed compiler/kernel shape.
- `macos-metal-public-dp4-local-jump-row`: rejected loading
  `AffineJumpValue jump = q_xy[jump_index]` once per public DP4 step. The
  public smoke oracle stayed intact (`distance_checksum=0xa45f471493cace2f`,
  `dp_count=1000`, `dp_checksum=0x30a7914972cba014`) and the verifier fallback
  shape stayed intact (`distance_checksum=0xbab72b58ebefa9dc`, `dp_count=249`,
  `dp_checksum=0x4a7f2853a4a9f546`), but stable paired confirmation discarded
  it. Raw speedups were `0.485932x` and `0.716055x`; final candidate median
  was `21,962,885.587314` versus baseline `30,672,067.959967` ops/sec. Keep
  the current direct `q_xy[jump_index].x*/y*` spelling for the public DP4
  precomputed-index kernel.
- `macos-metal-dynamic-dp14-stream-no-overflow-specialization`: rejected a
  DP14-only const-mask/no-overflow stream kernel. The candidate preserved the
  DP14 stream oracle (`emitted_records=1`, `output_bytes_total=20`,
  `dp_distance_checksum=0x9e3779b97f4b39c1`,
  `dp_checksum=0x252996ea8a0dca38`, `correctness=true`), but two-run paired
  confirmation discarded it. Run 1 regressed at candidate median
  `54,206,138.221190` versus baseline `67,608,653.796270` DP14 steps/sec
  (`paired_speedup=0.801763`); run 2 was a noisy raw keep at
  `44,341,838.079041` versus `40,366,739.951844` steps/sec
  (`paired_speedup=1.098475`) but did not rescue the confirmation. Keep DP14
  on the generic runtime-mask u32-distance stream kernel.
- `macos-precomputed-wild-starts-retest`: rejected precomputing CPU
  multi-target wild starts once per benchmark run and copying them into solve
  scratch. The candidate preserved the full-point collision oracle for both
  4-target (`found_private_key=0x7`, `found_target_index=3`,
  `last_dp_count=84`) and 16-target (`found_private_key=0x7`,
  `found_target_index=15`, `last_dp_count=288`) shapes, and `make
  macos-check` passed before the performance gate. Paired confirmation against
  `main` discarded both gates: 4-target ended at candidate
  `31,808.178173` versus baseline `33,120.321230` ops/sec
  (`paired_speedup=0.960383`), while 16-target ended at candidate
  `15,252.475344` versus baseline `15,200.985999` ops/sec
  (`paired_speedup=1.003387`, below gate). Keep the current inline
  `clear/reserve/push_back(JacobianFromAffine(...))` initialization; the
  precompute path changes memory/copy shape more than it removes useful work.
- `macos-kangaroo-dp0-fast-path`: rejected a dedicated CPU multi-target
  `dp_bits=0` path that skipped `IsDistinguished(...)` checks and labeled the
  benchmark `dp_predicate=all_points_fast_path`. The candidate preserved the
  full-point collision oracle (`found_private_key=0x7`; 4-target
  `found_target_index=3`, `last_dp_count=84`; 16-target
  `found_target_index=15`, `last_dp_count=288`) and `make macos-check`
  passed. Paired confirmation still discarded both gates: 4-target ended at
  candidate `33,463.770072` versus baseline `33,420.950058` ops/sec
  (`paired_speedup=1.001281`, below gate), and 16-target ended at candidate
  `15,674.827307` versus baseline `15,710.691415` ops/sec
  (`paired_speedup=0.997717`). Keep the unified predicate path; the DP0 branch
  specialization adds code shape without moving the bottleneck.
- `macos-metal-field-add-x4`: rejected a separate Metal `field_add_mod_p_x4`
  kernel that processed four field additions per Metal thread and dispatched
  `ceil(count / 4)` threads. The candidate preserved the CPU field-add oracle,
  including a non-multiple-of-four smoke shape, but paired autoresearch
  discarded it decisively. The final confirmation measured candidate
  `125,737,724.391583` versus baseline `223,386,636.821191` ops/sec
  (`paired_speedup=0.562870`, `confirmation_status=discard`). Keep one field
  element per Metal thread for add; reducing thread-level parallelism costs
  more than it saves on this M3 Air memory/ALU mix.
- `macos-metal-dp8-inplace-emit-before-store`: rejected moving DP record
  emission before the final in-place Jacobian state stores in
  `jacobian_affine_walk_dynamic_dp_stream_inplace_steps8_dp8_pow2_u32_distance`.
  The candidate preserved the in-place DP8 stream oracle (`emitted_records=61`,
  `dp_distance_checksum=0x822e141de4770a0b`,
  `dp_checksum=0xab1c2cd29cd70a84`, `correctness=true`) and
  `tests/check_metal_dynamic_dp_stream_inplace_source.py` passed during the
  experiment, but paired confirmation discarded it. The three raw paired
  speedups were `0.907874x`, `0.955029x`, and `0.807249x`; final median was
  candidate `54,676,152.869964` versus baseline `67,731,465.636918`
  steps/sec. Keep the accepted state-store-before-DP-emit order.
- `macos-metal-dp8-inplace-steps512`: rejected a 512-step packet variant for
  `jacobian_affine_walk_dynamic_dp_stream_inplace`. The candidate preserved the
  512-step CPU replay oracle (`emitted_records=64`,
  `output_bytes_total=1280`,
  `dp_distance_checksum=0x9edbacbfba811d14`,
  `dp_checksum=0x1d74ff586fee3e54`, `correctness=true`) and raw autoresearch
  confirmation ended at `90,061,456.584152` steps/sec, but paired comparison
  against the accepted `steps256` packet was not strong enough. Five
  `--min-ms 200` same-binary pairs had median `1.010153x` with one negative
  pair; five `--min-ms 500` pairs fell below the promotion gate at median
  `1.009593x` with range `0.975577x..1.025456x`. The packet ladder appears to
  be at a local plateau on this M3 Air; keep `steps256` as the largest accepted
  packet for now.
  A later retest after the accepted `steps16+ -> threadgroup_limit=128` policy
  tried `steps512` again and found `--tg-limit 64` as the best 512-step cap in
  a short sweep. The oracle stayed unchanged (`emitted_records=64`,
  `dp_distance_checksum=0x9edbacbfba811d14`,
  `dp_checksum=0x1d74ff586fee3e54`, `correctness=true`), and one 7-pair
  `--min-ms 1000` confirmation reached median `1.010289x` versus
  `steps256/tg128`, but a second independent 7-pair run fell to median
  `1.003748x` with a `0.915072x` outlier. Keep `steps512` rejected until a
  broader kernel-shape change moves it clearly past the gate.
- `macos-metal-dp8-inplace-u32-distances`: rejected changing the in-place
  packet kernels' jump-distance buffer from `constant ulong*` to
  `constant uint*`. The candidate preserved the accepted `steps256` oracle
  (`emitted_records=57`, `dp_distance_checksum=0x0ab81bcdffe988ca`,
  `dp_checksum=0xbb961e8e4fffeeb0`, `correctness=true`) and added a host
  distance-fit guard, but paired autoresearch against `main` discarded it:
  candidate median `89,514,131.722479` versus baseline
  `91,969,442.817225` steps/sec (`paired_speedup=0.973303`). Keep the 64-bit
  distance table; this buffer is too small/cached to justify the changed
  kernel shape.
- `macos-metal-dp8-inplace-steps16-tg160`: rejected defaulting only the
  `steps16` in-place DP8 packet to `threadgroup_limit=160`. The candidate
  preserved the `steps16` sparse-stream oracle (`emitted_records=67`,
  `dp_distance_checksum=0x68fbd251ce4fd08e`,
  `dp_checksum=0xdd7021cb96f924c0`, `correctness=true`), but paired
  autoresearch confirmation discarded it. The first two confirmation groups
  regressed at roughly `0.820x` and `0.734x`; the third group was positive at
  candidate `67,980,915.994864` versus baseline `62,417,739.448993` steps/sec
  (`paired_speedup=1.089128`) but did not satisfy the all-confirmations keep
  policy. Keep the accepted in-place DP8 packet default at 128 threads for
  `steps16+`.
- `macos-metal-dp8-inplace-steps192`: rejected a non-power-of-two packet-size
  probe between accepted `steps128` and `steps256`. The prototype preserved
  the sparse-stream/final-state oracle (`emitted_records=74`,
  `dp_distance_checksum=0x72cf07344a308edc`,
  `dp_checksum=0x69bfc127c31638b0`, `correctness=true`). A quick cap sweep
  found the best `steps192` median at `--tg-limit 96`, but it was still below
  accepted `steps256 --tg-limit 128` (`0.984702x` in the two-run sweep). Five
  `--min-ms 500` same-binary pairs confirmed the rejection: ratios were
  `0.951722x`, `0.966900x`, `0.919687x`, `0.965682x`, and `0.971917x`
  (median `0.965682x`). Keep `steps256/tg128` as the packet-size plateau.
- `macos-metal-dp8-inplace-pipeline-cache`: rejected caching the in-place DP8
  runner's Metal device, library, command queue, and specialized pipeline.
  The prototype preserved the accepted `steps256` oracle
  (`emitted_records=57`, `dp_distance_checksum=0x0ab81bcdffe988ca`,
  `dp_checksum=0xbb961e8e4fffeeb0`, `correctness=true`), but the benchmark
  timer starts around command-buffer commit, so pipeline setup is outside the
  official `ops_per_sec` metric. Paired autoresearch against `main` discarded
  the candidate: confirmation speedups were `0.994935x`, `0.973389x`, and
  `1.004171x` (`confirmation_status=discard`). Keep the explicit per-run
  pipeline setup unless a future wall-clock metric is added and gated.
- `macos-metal-dp8-inplace-steps256-no-unroll`: rejected pinning the accepted
  `steps256` packet loop with `#pragma clang loop unroll(disable)`. The
  candidate preserved the accepted oracle (`emitted_records=57`,
  `dp_distance_checksum=0x0ab81bcdffe988ca`,
  `dp_checksum=0xbb961e8e4fffeeb0`, `correctness=true`), but paired
  autoresearch discarded it. Confirmation groups were approximately
  `0.965x`, `1.003x`, and final `0.993241x` versus `main`. Keep the compiler's
  default loop-shaping for the 256-step packet.
- `macos-metal-dp8-xyzz-packet`: accepted a separate 256-step DP8 dynamic
  packet kernel using `X,Y,ZZ,ZZZ` state instead of Jacobian `X,Y,Z`. This is
  the first promoted coordinate-system change in the Metal packet path. The
  XYZZ mixed-add formula avoids recomputing `Z^2` and `Z^3` from `Z` on every
  jump; it updates `ZZ *= H^2` and `ZZZ *= H^3` directly, while keeping a full
  CPU XYZZ replay oracle, a rare-case XYZZ doubling path, DP stream
  validation, final-state validation, and jump-bucket histogram reporting. The
  partition mixer remains the same avalanche structure but uses `ZZ0` in place
  of unavailable `Z0`, so the walk is reported as its own operation
  (`jacobian_affine_walk_dynamic_dp_stream_xyzz`) rather than silently
  replacing the accepted Jacobian packet. Correctness was stable:
  `emitted_records=66`,
  `dp_distance_checksum=0x8c7a04f6c070c09d`,
  `dp_checksum=0x7dbd6d4ef9312f92`, `dp_stream_overflow=false`,
  `jump_histogram_max_deviation_ppm=2800`, and `correctness=true`.
  Autoresearch now supports `paired_baseline_command`, allowing new commands to
  compare against an accepted baseline command. Three paired confirmations
  against `main` in-place `steps256` all kept the candidate: `108,430,652.959344`
  vs `97,116,935.449139` steps/sec (`1.116496x`), `109,797,276.536427`
  vs `99,516,980.914828` (`1.103302x`), and `109,205,454.549881`
  vs `98,548,542.510903` (`1.108139x`). Use
  `metal-jacobian-dynamic-dp-stream-xyzz-bench --steps 256 --jumps 16
  --dp-bits 8 --min-ms 200` as the new architecture probe and keep the older
  Jacobian in-place packet as the direct same-walk baseline.
- `macos-metal-dp8-xyzz-steps512`: accepted a 512-step specialization for the
  XYZZ DP8 packet path. This deliberately reopens a packet-size question that
  was rejected for the older Jacobian in-place layout: the coordinate-system
  change shifts enough work out of the hot loop for a larger packet to clear
  the paired gate on this M3 Air. The same CPU XYZZ replay oracle validated the
  sparse stream and final state with `emitted_records=76`,
  `dp_distance_checksum=0x59171fb04821054e`,
  `dp_checksum=0x979de1728771393c`, `dp_stream_overflow=false`,
  `jump_histogram_max_deviation_ppm=2724`, and `correctness=true`.
  Autoresearch compared the candidate command against accepted XYZZ
  `steps256`; all three confirmation groups kept the candidate:
  `105,678,664.660821` vs `102,653,102.552273` steps/sec (`1.029474x`),
  `105,831,859.880228` vs `102,675,656.563845` (`1.030740x`), and
  `107,388,329.480794` vs `103,951,832.856458` (`1.033059x`). Use
  `metal-jacobian-dynamic-dp-stream-xyzz-bench --steps 512 --jumps 16
  --dp-bits 8 --min-ms 200` as the current XYZZ packet plateau while keeping
  `--steps 256` available for direct architecture regression checks.
- `macos-metal-dp8-xyzz-steps512-tg32`: rejected a runtime-only threadgroup
  cap change for the accepted XYZZ `steps512` packet. A first sweep made
  `--tg-limit 32` look promising (`1.037175x` over the inherited 128-thread
  default), but seven alternating `--min-ms 500` same-binary pairs did not
  replicate: ratios were `1.002442x`, `0.987582x`, `0.987945x`, `0.992929x`,
  `1.004826x`, `0.984890x`, and `1.008734x` (median `0.992929x`). Correctness
  and the XYZZ `steps512` checksums stayed unchanged. Keep the default
  `threadgroup_limit=128` for XYZZ `steps512` until a broader policy beats the
  paired gate.
- `macos-metal-dp8-xyzz-steps1024`: rejected extending the XYZZ DP8 packet
  plateau from 512 to 1024 steps. The prototype preserved the CPU XYZZ replay
  oracle (`emitted_records=58`,
  `dp_distance_checksum=0xfa394db495b731df`,
  `dp_checksum=0x1124055174f18a38`, `dp_stream_overflow=false`,
  `jump_histogram_max_deviation_ppm=1918`, and `correctness=true`), and quick
  same-binary runs looked promising. Paired autoresearch against accepted XYZZ
  `steps512` did not satisfy the all-confirmations policy: the final decision
  was `discard`, with final candidate `109,543,181.205134` versus baseline
  `108,843,325.105267` steps/sec (`1.006430x`). Keep `steps512` as the current
  promoted XYZZ packet plateau.
- `macos-metal-dp8-xyzz-steps768`: rejected the midpoint packet between
  accepted `steps512` and rejected `steps1024`. The prototype stayed correct
  (`emitted_records=66`,
  `dp_distance_checksum=0xf9f6596d8b5e37da`,
  `dp_checksum=0xb0b7efeef3f178a8`, `dp_stream_overflow=false`,
  `jump_histogram_max_deviation_ppm=1461`, and `correctness=true`), but five
  alternating same-binary `--min-ms 500` pairs against `steps512` gave ratios
  `0.994181x`, `1.013145x`, `1.010970x`, `0.996255x`, and `0.995709x`
  (median `0.996255x`, mean `1.002052x`). Do not promote a non-power-of-two
  XYZZ packet unless it clears paired autoresearch, not just a quick run.
- `macos-metal-dp8-xyzz-finite-add`: rejected splitting the XYZZ mixed-add into
  a finite-state helper plus an explicit packet-loop branch for the rare
  infinity case. This mirrored a useful Jacobian pattern, but on the XYZZ
  packet kernels it likely increased inlined code/branch pressure more than it
  saved. Correctness and the accepted `steps512` oracle stayed unchanged
  (`emitted_records=76`,
  `dp_distance_checksum=0x59171fb04821054e`,
  `dp_checksum=0x979de1728771393c`, `dp_stream_overflow=false`,
  `jump_histogram_max_deviation_ppm=2724`, and `correctness=true`).
  Paired autoresearch against `main` discarded the candidate; the final
  decision row measured `107,116,303.469940` versus baseline
  `110,658,142.122193` steps/sec (`0.967993x`). Keep the compact generic XYZZ
  add wrapper in the packet loop.
- `macos-metal-dp8-xyzz-state-struct`: rejected rewriting the XYZZ packet state
  buffer from raw `ulong*` indexing to a `XyzzStateValue` struct-row view. The
  binary layout was kept identical and correctness/checksums matched accepted
  `steps512`, but the compiler did not turn the cleaner address expression into
  a speedup. Paired autoresearch discarded the candidate with final
  `106,925,077.911796` versus baseline `107,860,427.099762` steps/sec
  (`0.991328x`). Keep the raw contiguous limb buffer for XYZZ state.
- `macos-metal-dp8-xyzz-implicit-distance`: rejected replacing the per-step
  `jump_distances[jump_index]` load with `1U << jump_index` inside the XYZZ
  `steps256/steps512` kernels. The benchmark jump-distance table is
  `distance[i] = 2^i`, so the candidate preserved the accepted `steps512`
  oracle (`emitted_records=76`,
  `dp_distance_checksum=0x59171fb04821054e`,
  `dp_checksum=0x979de1728771393c`, `dp_stream_overflow=false`,
  `jump_histogram_max_deviation_ppm=2724`, and `correctness=true`). Paired
  autoresearch still discarded it: final candidate `105,641,474.264747`
  versus baseline `107,077,069.857827` steps/sec (`0.986593x`). Keep the
  distance-table load in the promoted XYZZ packet path.
- `macos-metal-dp8-packet-u32-distance-guard`: accepted a correctness guard
  for packet kernels that accumulate per-dispatch scalar distance in `uint32`.
  The accepted in-place `steps256` and XYZZ `steps512` paths are valid at
  `jumps=16`, but `jumps=32` can make
  `max_jump_distance * steps_per_sample` exceed `UINT32_MAX`. Small benchmark
  samples can hide this because no distinguished-point record is emitted, so
  the bench wrappers now reject the configuration before dispatch with
  `correctness=false` and an explicit reason. The hidden-test shape
  `xyzz --iterations 128 --steps 512 --jumps 32 --dp-bits 8` reports
  `reason="XYZZ dynamic dp stream packet distance exceeds uint32 accumulator"`;
  the in-place shape `--iterations 128 --steps 256 --jumps 32 --dp-bits 8`
  reports the analogous in-place reason. This is a correctness-surface
  promotion, not a speed claim.
- `macos-metal-dp8-xyzz-j16-mask`: rejected adding separate XYZZ
  `steps256/steps512` kernels that hardcode the promoted `jumps=16` mask as
  `mixed & 15UL` and skip the runtime `jump_mask` buffer. Correctness and the
  accepted `steps512` oracle stayed unchanged (`emitted_records=76`,
  `dp_distance_checksum=0x59171fb04821054e`,
  `dp_checksum=0x979de1728771393c`, `dp_stream_overflow=false`, and
  `correctness=true`), but five same-command `--min-ms 500` pairs against
  `main` did not clear the promotion gate. Ratios were `1.006607x`,
  `0.988901x`, `0.994980x`, `1.031375x`, and `1.002726x` (median
  `1.002726x`, mean `1.004918x`). Keep the runtime mask buffer in the
  promoted XYZZ packet path; it is not a replicated bottleneck on this M3 Air.
- `macos-metal-dp8-xyzz-xlow-mixer`: rejected replacing the XYZZ avalanche
  partition mixer with `jump_index = X0 & jump_mask` in a separate
  `xlow64` command. This was mathematically plausible because secp256k1
  `X` low bits should be close to uniform; the prototype confirmed a healthy
  jump histogram (`jump_histogram_max_deviation_ppm=2279` versus the accepted
  avalanche `2724`) and preserved Metal/CPU oracle agreement with
  `correctness=true`. The walk changed, as expected
  (`emitted_records=67`, `dp_distance_checksum=0xdcf4f89bc6d258f7`,
  `dp_checksum=0xc431afb25d71088e`), but five `--min-ms 500` pairs against
  accepted XYZZ `steps512` did not replicate a speedup: ratios were
  `1.026622x`, `1.019740x`, `0.994033x`, `0.999157x`, and `0.996267x`
  (median `0.999157x`, mean `1.007164x`). Keep `avalanche64`; the partition
  mixer is not the next limiting cost for the XYZZ packet kernel.
- `macos-metal-dp8-xyzz-saturated-batch`: accepted a separate operational
  benchmark for the promoted XYZZ `steps512` packet using a 262144-state batch.
  This is not a new mathematical shortcut and not a packet-size comparison; it
  records the batch size needed to saturate the M3 Air GPU more consistently.
  Three-run `--min-ms 500` medians rose from `110,036,117.399121` steps/sec at
  `iterations=16384` to `118,510,442.585526` at `65536`,
  `121,601,740.083494` at `131072`, and `121,797,922.693007` at `262144`.
  The largest run stayed oracle-clean with `dp_count=1015`,
  `output_bytes_total=20300`, `jump_histogram_max_deviation_ppm=759`, and
  `correctness=true`. At this saturated batch size, `steps512` and `steps256`
  were near parity in three alternating pairs (median `1.001235x`, mean
  `1.010083x`), so keep the historical `steps512@16384` experiment as the fair
  packet-size gate and use
  `macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-saturated-bench` for
  peak-throughput Mac benchmarking. A broader runtime-only threadgroup sweep
  also failed to beat the default 128-thread cap (`tg64` median `0.995565x`,
  `tg96` median `0.982280x`), so leave the cap unchanged.
- `macos-metal-dp8-xyzz-large-batch`: accepted an optional large-batch
  throughput probe for the same promoted XYZZ `steps512` kernel at
  `iterations=524288`. Three alternating pairs against the 262144-state
  saturated target were all correct and non-regressing: `1.017095x`,
  `1.005806x`, and `1.011536x` (median `1.011536x`, mean `1.011479x`).
  Candidate median throughput was `124,792,320.056530` steps/sec with
  `dp_count=1976`, `output_bytes_total=39520`,
  `jump_histogram_max_deviation_ppm=553`, and `correctness=true`.
  Autoresearch also kept the standalone large-batch gate with runner median
  `124,648,214.520876` steps/sec (`min=123,393,739.713153`,
  `max=124,996,719.967963`). A single 1048576-state scout stayed correct and
  reached
  `125,056,788.093871` steps/sec with `dp_count=3998` and histogram deviation
  `408 ppm`, but it is not promoted yet because the extra wall-clock validation
  cost is large and the measured gain over 524288 was marginal. Use
  `macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-large-batch-bench` for
  peak-throughput exploration, while keeping the 262144-state saturated target
  as the standard repeatable Mac gate.
- `macos-metal-dp8-xyzz-parallel-oracle`: accepted parallel CPU replay for the
  dynamic DP stream validators. This does not change Metal `seconds` or
  `ops_per_sec`; it preserves full per-sample replay and only splits expected
  state/DP generation across CPU cores, reducing the wall-clock cost of large
  Mac gates. On the 524288-state XYZZ `steps512` large-batch command, the
  previous serial oracle took `81.46s` wall-clock (`user=76.70s`) and the new
  parallel oracle took `16.55s` wall-clock (`user=101.39s`), a `4.92x`
  end-to-end benchmark/oracle speedup. The outputs matched exactly:
  `dp_count=1976`, `dp_distance_checksum=0x7325bd945494b7be`,
  `dp_checksum=0x390f891179fdcbea`,
  `jump_histogram_max_deviation_ppm=553`, and `correctness=true`. XYZZ JSON now
  reports `validation_seconds` separately (`14.248229s` in the measured
  large-batch run) so future speedups cannot hide inside kernel throughput.
- `macos-metal-dp8-xyzz-fused-oracle`: accepted fusing the XYZZ DP-stream and
  final-state CPU replay into one per-sample oracle pass. This preserves the
  same stream index/duplicate/missing-record checks and the same final
  `X,Y,ZZ,ZZZ` state comparison, but avoids replaying the 512-step walk twice.
  On the same 524288-state command, wall-clock dropped again from the
  parallel-only `16.55s` to `9.57s` (`user=50.53s`), for an `8.51x` improvement
  over the original serial oracle. The fused run reported
  `validation_seconds=7.298625`, `dp_count=1976`,
  `dp_distance_checksum=0x7325bd945494b7be`,
  `dp_checksum=0x390f891179fdcbea`,
  `jump_histogram_max_deviation_ppm=553`, and `correctness=true`; Metal
  throughput remained a normal kernel measurement (`seconds=2.157509`,
  `ops_per_sec=124,419,135.327658`).
- Rejected follow-up `macos-metal-dp8-xyzz-sparse-oracle`: replacing the fused
  oracle's dense per-sample DP arrays with sparse expected/output DP records
  preserved correctness (`dp_count=1976`,
  `dp_distance_checksum=0x7325bd945494b7be`,
  `dp_checksum=0x390f891179fdcbea`, `correctness=true`), but regressed the
  same large-batch command from `9.57s` wall-clock and
  `validation_seconds=7.298625` to `11.89s` wall-clock and
  `validation_seconds=9.597125`. The sort/vector overhead outweighed the lower
  dense-array memory footprint for DP8, so keep the fused dense validation
  layout as the base.
- Rejected follow-up `macos-metal-dp8-xyzz-u32-distances`: packing the XYZZ
  DP8 jump-distance table as `uint32_t` and changing the XYZZ packet kernels
  to read `constant uint* jump_distances` preserved the large-batch oracle
  (`dp_count=1976`, `dp_distance_checksum=0x7325bd945494b7be`,
  `dp_checksum=0x390f891179fdcbea`, `correctness=true`), but paired
  autoresearch against `main` discarded it. The candidate median was
  `112,618,477.633033` steps/sec versus paired baseline
  `118,540,009.154867` (`paired_speedup=0.950046`), despite one direct scout
  at `124,929,059.823944` steps/sec. Keep the XYZZ distance table as `ulong`
  with the explicit in-kernel cast to `uint`; the narrower buffer changes the
  compiled shape unfavorably on this M3 profile.
- Rejected follow-up `macos-metal-dp8-xyzz-hybrid-expected-stores`: keeping
  dense expected DP arrays but only writing expected distance/term values for
  DP samples preserved the large-batch oracle (`dp_count=1976`,
  `dp_distance_checksum=0x7325bd945494b7be`,
  `dp_checksum=0x390f891179fdcbea`, `correctness=true`), but did not improve
  fused validation. The same 524288-state command measured
  `validation_seconds=7.984267` and `10.18s` wall-clock versus the accepted
  fused-oracle reference of `validation_seconds=7.298625` and `9.57s`
  wall-clock. Keep the current straight-line dense writes; the branch does not
  pay for itself at DP8.
- `macos-metal-dp8-xyzz-chain-cumulative`: accepted as a solver-facing
  architecture probe, not as a replacement for the single-packet throughput
  baseline. It adds a separate
  `metal-jacobian-dynamic-dp-stream-xyzz-chain-bench` command and separate
  Metal kernels that keep `X,Y,ZZ,ZZZ`, infinity flags, and a per-sample
  cumulative distance buffer resident across multiple packet dispatches inside
  one command buffer. DP records use `packet_sample_u32` stream indexing and
  report `distance_tracking=dp_stream_cumulative_uint64`, so repeated DPs from
  the same walker at different packet boundaries remain distinguishable and
  carry the total scalar distance. The CPU oracle replays every packet boundary,
  validates the final XYZZ state, checks duplicate/missing/non-DP stream
  records, and mixes checksums over the packet/sample key space. Manual
  sequential large-batch comparison on M3: the accepted single-packet
  `524288 x 512` command measured `128,772,847.144853` steps/sec with
  `validation_seconds=9.005047`; the chain `262144 x 512 x 2` command measured
  `127,143,171.998521` steps/sec with `validation_seconds=8.819867`,
  `dp_count=2016`, `dp_distance_checksum=0x7a221c62b92a5ed3`,
  `dp_checksum=0x23509000c8141686`, and `correctness=true`. A larger
  `524288 x 512 x 2` chain run measured `128,817,519.152652` steps/sec with
  `dp_count=4033`. The autoresearch gate
  `metal_jacobian_dynamic_dp_stream_xyzz_chain_steps512` was kept as the first
  row for this new operation, but the long three-sample runner was thermally
  noisy (`52,054,794.687903` median steps/sec); treat it as a reproducibility
  row for the cumulative-distance operation, not as a peak-throughput record.
- `macos-metal-dp8-xyzz-chain-packets4`: added a dedicated autoresearch gate
  for the four-packet cumulative chain shape that beat persistent-chain in the
  paired promotion check. The new experiment runs
  `262144 x 512 x 4`, uses `--min-ms 0`, and cools down between samples. The
  first clean run at commit `d4398d9` preserved the cumulative oracle
  (`dp_count=4037`, `dp_distance_checksum=0x30e91a5edffed133`,
  `dp_checksum=0x950a1186dae66384`) and kept at median
  `92,484,157.517172` steps/sec. Because the same shape measured
  `126,396,922.377779` in the paired baseline immediately before this run,
  future packet/round decisions should use paired comparisons against this
  command rather than standalone peak claims.
- `macos-metal-dp8-xyzz-persistent-chain-rounds`: accepted as the next
  solver-facing host architecture after the cumulative chain. It adds
  `metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench`, where
  `--packets` is the number of packet kernels encoded per command buffer and
  `--rounds` is the number of command buffers submitted against the same
  resident XYZZ state, cumulative-distance buffer, DP stream buffers, Metal
  library, and pipeline. The JSON reports
  `setup_mode=reuse_pipeline_buffers`,
  `state_persistence=round_cumulative_xyzz`,
  `packets_per_round`, `round_count`, and
  `stream_indexing=round_packet_sample_u32`. The CPU oracle validates it as a
  single chain of `packets * rounds` packets, so the DP checksums are directly
  comparable with an exact total-packet chain. Manual M3 exact comparison:
  on `131072 x 512 x 4`, the generic one-command-buffer chain measured
  `119,965,179.870176` steps/sec while persistent `packets=2, rounds=2`
  measured `122,385,639.887796`, with matching
  `dp_count=2042`, `dp_distance_checksum=0x2fc17b9313fc0204`, and
  `dp_checksum=0x2b1728330fd9cdc6`. On the larger
  `262144 x 512 x 4` comparison, the generic chain measured
  `122,150,581.472696` steps/sec and persistent `2 x 2` measured
  `127,964,289.140597`, preserving `dp_count=4037`,
  `dp_distance_checksum=0x30e91a5edffed133`,
  `dp_checksum=0x950a1186dae66384`, and `correctness=true`. This promotes
  command-buffer-level persistence as a real Mac path: it is not a new ECDLP
  shortcut, but it removes host-side reinitialization pressure while preserving
  full cumulative-distance correctness. A clean 2026-06-25 autoresearch
  refresh at commit `2cc50c2` kept the same `262144 x 512 x 4` persistent
  shape at median `124,755,147.554164` steps/sec with the same DP count and
  checksums. The follow-up paired gate at commit `d6a07ff` rejected promotion
  against the generic four-packet chain: persistent median
  `74,788,530.478310` steps/sec versus paired baseline
  `126,396,922.377779` (`paired_speedup=0.591696`) with identical DP count and
  checksums. Keep persistent-chain as an architecture probe, not the default
  M3 multi-packet throughput path.
- Follow-up schedule sweep for `macos-metal-dp8-xyzz-persistent-chain-rounds`
  kept the accepted `packets=2, rounds=2` experiment as the best reproducible
  default, but recorded useful boundaries. With total packets fixed at four,
  `131072 x 512 x 4` measured `125,342,185.195233` steps/sec for
  `packets=4, rounds=1`, `126,121,211.306114` for `2 x 2`, and
  `125,943,165.019040` for `1 x 4`, all preserving
  `dp_distance_checksum=0x2fc17b9313fc0204` and
  `dp_checksum=0x2b1728330fd9cdc6`. The larger `262144 x 512 x 4` sweep
  measured `127,101,881.500963` for `4 x 1`,
  `127,628,765.359548` for `2 x 2`, and `128,037,092.166447` for `1 x 4`;
  a repeat of `1 x 4` measured `127,507,413.942529`, while a later `2 x 2`
  repeat fell to `101,328,031.629917` under clear thermal/noise conditions.
  All large runs preserved `dp_distance_checksum=0x30e91a5edffed133` and
  `dp_checksum=0x950a1186dae66384`. Conclusion: total-packet scheduling is a
  local tuning knob, but the current `2 x 2` autoresearch gate remains the
  most balanced default.
- Rejected follow-up `macos-metal-dp8-xyzz-queued-rounds`: queuing all
  persistent command-buffer rounds before waiting was correct, but did not
  produce a robust speedup. On `131072 x 512 x 4`, serial `1 x 4` measured
  `123,817,482.493016` steps/sec and queued `1 x 4` measured
  `124,551,373.729465`, with the same `dp_count=2042`,
  `dp_distance_checksum=0x2fc17b9313fc0204`, and
  `dp_checksum=0x2b1728330fd9cdc6`. On `262144 x 512 x 4`, serial `1 x 4`
  measured `126,415,616.859633` and queued `1 x 4` measured
  `126,594,415.394061`, with the same `dp_count=4037`,
  `dp_distance_checksum=0x30e91a5edffed133`, and
  `dp_checksum=0x950a1186dae66384`. The `2 x 2` shape regressed on the small
  paired check (`124,467,804.420946` serial versus `120,508,486.723988`
  queued). The marginal `1 x 4` gain is below the promotion threshold and the
  mixed result adds API surface, so keep serial per-round waits.
- Rejected follow-up `macos-metal-dp8-xyzz-chain2-fused-kernel`: fusing the
  common `steps=512, packets=2` chain into one Metal kernel kept correctness
  and produced the same cumulative-chain oracle values (`dp_count=2016`,
  `dp_distance_checksum=0x7a221c62b92a5ed3`,
  `dp_checksum=0x23509000c8141686`, `correctness=true`), but regressed
  throughput. The fused candidate measured `123,091,730.623771` steps/sec at
  the default 128-thread cap and `123,841,752.582641` steps/sec at
  `--tg-limit 256`, while a temporary `b324ce9` baseline worktree measured the
  generic two-dispatch chain at `127,967,260.451385` steps/sec on the same
  `262144 x 512 x 2` command. The likely cause is reduced occupancy/register
  pressure from serializing 1024 dynamic jumps in one thread; keep the generic
  packet chain as the base and pursue persistent-state improvements without
  doubling the per-thread packet body.
- Rejected follow-up `macos-metal-dp8-xyzz-chain-u32-cumulative`: storing the
  chain's per-sample cumulative distance state as `uint32_t` while preserving
  `uint64_t` DP stream distances was correct but much slower. The same
  `262144 x 512 x 2` command preserved `dp_count=2016`,
  `dp_distance_checksum=0x7a221c62b92a5ed3`,
  `dp_checksum=0x23509000c8141686`, and `correctness=true`, but measured only
  `106,452,461.969635` steps/sec at the default 128-thread cap and
  `112,562,977.345142` at `--tg-limit 256`, versus the generic `ulong`
  cumulative baseline at `127,967,260.451385`. As with the rejected u32 jump
  distance table, the narrower device type appears to worsen the M3 Metal
  kernel shape more than it saves memory bandwidth; keep the cumulative state
  as `ulong`.
- Rejected follow-up `macos-metal-dp8-xyzz-steps512-tg256-default`: a targeted
  attempt to promote `--tg-limit 256` as the default only for the single XYZZ
  `steps=512` packet was too noisy to keep. Sequential M3 sweep on
  `262144 x 512`: default/128 measured `122,329,483.687279`, then explicit 64
  measured `120,995,659.976640`, 256 measured `122,905,172.380591`, 512
  measured `109,615,654.426453`, a repeat of 128 measured
  `122,894,659.561174`, and a repeat of 256 measured `124,000,810.433201`.
  After implementing the candidate and rebuilding, the fresh default-256 run
  measured `123,444,698.882605`, while explicit 128 in the same pass measured
  `124,983,727.140317` and another explicit 256 measured
  `124,355,526.442211`. The chain check also favored 128:
  `262144 x 512 x 2` measured `124,077,279.673762` at 128 versus
  `122,837,859.768948` at 256, preserving
  `dp_distance_checksum=0x7a221c62b92a5ed3` and
  `dp_checksum=0x23509000c8141686`. Keep the 128 long-step default; allow
  manual `--tg-limit 256` only as a local tuning knob, not as a promoted
  default.
- Rejected follow-up `macos-metal-dp8-xyzz-chain512-threadgroup-jumps`: caching
  the 16 affine jump points and jump distances in threadgroup memory for the
  specialized `steps=512, dp8, pow2` XYZZ chain kernel preserved correctness but
  did not produce a stable win. Paired baseline/candidate checks on the M3 kept
  the same `dp_count`, `dp_distance_checksum`, and `dp_checksum`: at
  `131072 x 512 x 4`, baseline measured `127,167,485.779238` steps/sec versus
  candidate `125,503,008.316048`; at `262144 x 512 x 4`, baseline measured
  `126,235,013.656556` versus candidate `126,255,966.259504`. The large result
  is effectively noise while the small case regresses, so keep direct constant
  jump-table reads and avoid the extra threadgroup copy/barrier in the promoted
  kernel.
- Rejected follow-up `macos-metal-dp8-xyzz-normal-first-mixed-add`: moving the
  XYZZ mixed-add helper's common `H != 0` path before the rare
  doubling/infinity edge path preserved the persistent-chain DP checksums but
  regressed the first paired M3 check. On `131072 x 512 x 4`, baseline measured
  `100,388,887.681252` steps/sec and the candidate measured
  `78,739,589.676166`, both with `dp_count=2042`,
  `dp_distance_checksum=0x2fc17b9313fc0204`, and
  `dp_checksum=0x2b1728330fd9cdc6`. A follow-up baseline repeat was dominated
  by thermal throttling (`20,652,861.141964`) and was not used for promotion.
  This mirrors the earlier non-XYZZ normal-first rejection; keep the existing
  edge-first helper shape.
- Accepted follow-up `macos-metal-xyzz-runtime-dp-mask`: the XYZZ packet,
  chain, and persistent-chain paths now keep the promoted DP8 hardcoded
  `0xFF` kernels but select separate runtime-mask kernels for non-DP8
  `ProjectiveDpMask(dp_bits)` probes up to 32 bits. This preserves the DP8
  fast path while making DP10/DP12/DP16 sparse-stream shapes available on the
  same CPU XYZZ replay oracle. Fresh M3 checks preserved correctness:
  `262144 x 512` DP8 packet measured `124,656,463.095272` steps/sec with
  `dp_count=1015`, `dp_distance_checksum=0xdf5ba046e663f744`, and
  `dp_checksum=0x65d61f2aa446682c`; the same packet with DP12 measured
  `113,783,621.442092` steps/sec with `dp_count=69`,
  `dp_distance_checksum=0x7d3a2fdc136996be`, and
  `dp_checksum=0x86abc2c890e57c88`. Do not treat packet DP12 as a speed
  promotion over DP8 because the DP density changed and the generic mask path
  is slower in that single-packet shape.
- Accepted follow-up `macos-metal-xyzz-runtime-dp-persistent-chain`: on the
  solver-facing persistent chain, runtime DP masks reduce stream pressure
  without hurting arithmetic throughput in the measured shape. On
  `131072 x 512 x 4`, DP8 measured `124,352,386.831228` steps/sec with
  `dp_count=2042`, `dp_distance_checksum=0x2fc17b9313fc0204`, and
  `dp_checksum=0x2b1728330fd9cdc6`; DP12 measured
  `124,448,355.789433` steps/sec with only `dp_count=132`,
  `dp_distance_checksum=0xe885b9216531a8b2`, and
  `dp_checksum=0x62d6817b35ede52a`. DP16 at the same shape emitted only
  `10` records and measured `124,647,237.795156` steps/sec when forced to
  `--tg-limit 128`, compared with `123,472,739.196919` at the previous
  automatic 256-thread cap. The long-step dynamic-DP threadgroup policy now
  uses 128 threads for `steps>=256` independent of DP density; explicit
  `--tg-limit` still overrides it. Clean autoresearch on commit `7ceb57c`
  kept `metal_jacobian_dynamic_dp_stream_xyzz_persistent_chain_dp12_steps512`
  with three correct samples and median `123,851,132.746183` steps/sec
  (`min=123,076,360.919518`, `max=124,366,353.036694`).
- Accepted follow-up `macos-metal-xyzz-dp12-hardcoded-mask`: DP12 now has
  hardcoded `0xFFF` XYZZ packet and chain kernels, while DP10/DP16 and other
  non-DP8/DP12 shapes stay on the runtime `ProjectiveDpMask(dp_bits)` path.
  This preserves the DP8 fast path and the generic sparse-mask capability, but
  removes the runtime DP-mask buffer from the solver-useful DP12 shape. The
  single-packet `262144 x 512` DP12 probe preserved
  `dp_count=69`, `dp_distance_checksum=0x7d3a2fdc136996be`, and
  `dp_checksum=0x86abc2c890e57c88`, improving from the previous runtime-mask
  measurement of `113,783,621.442092` steps/sec to
  `122,945,894.692246` steps/sec. Clean autoresearch on commit `7ee5643`
  kept `metal_jacobian_dynamic_dp_stream_xyzz_dp12_steps512` with three
  correct samples and median `125,987,056.586718` steps/sec
  (`min=125,830,515.853641`, `max=126,012,896.972671`). The
  persistent-chain `131072 x 512 x 4`
  DP12 probe remained in the same plateau, measuring
  `123,570,962.092489` steps/sec with `dp_count=132`,
  `dp_distance_checksum=0xe885b9216531a8b2`, and
  `dp_checksum=0x62d6817b35ede52a`; treat this as neutral for the chain
  throughput gate, not a new chain speed claim.
- Rejected follow-up `macos-metal-xyzz-total-packet8-geometry`: increasing
  persistent-chain total packet count from four to eight did not show a stable
  geometry win. A first parallel scout was contaminated and used only for
  checksum equality; all four shapes (`8x1`, `4x2`, `2x4`, `1x8`) preserved
  `dp_count=2050`, `dp_distance_checksum=0xd9b169a1e66faa75`, and
  `dp_checksum=0x6839425f67cccc42`. Sequential extremes on
  `65536 x 512 x 8` measured `121,784,499.848321` steps/sec for `1x8` and
  `121,209,250.733544` for `8x1`, both correct and within noise. Keep the
  existing total-packet-four persistent experiments as the base until a paired
  run shows a real advantage.
- Accepted follow-up `macos-metal-xyzz-dp16-hardcoded-mask`: DP16 now has
  hardcoded `0xFFFF` XYZZ packet and chain kernels, matching the DP8/DP12
  specialization pattern while leaving DP10 and other densities on the runtime
  `ProjectiveDpMask(dp_bits)` path. The change removes the runtime DP-mask
  buffer from very sparse DP16 table-pressure probes without changing the walk
  mixer, distance accounting, DP term, or replay oracle. A fresh detached
  worktree at `df4bc51` measured the runtime-mask persistent-chain baseline
  with three correct samples and median `122,318,871.862145` steps/sec
  (`min=122,231,092.631304`, `max=122,955,909.345437`), preserving
  `dp_count=10`, `dp_distance_checksum=0xb1c940ae7864db0e`, and
  `dp_checksum=0xeb0822497a41aca2`. Clean autoresearch on commit `88816b7`
  measured the hardcoded DP16 candidate at `123,257,579.364915` steps/sec with
  the same checksums (`min=123,215,222.207105`,
  `max=123,441,127.302035`), a local paired lift of about `0.77%` on the
  solver-facing `131072 x 512 x 4` persistent-chain gate. All three clean
  candidate samples were above the maximum detached-baseline sample, so keep
  the specialization despite the modest effect size.
  A same-shape packet smoke preserved `dp_count=3`,
  `dp_distance_checksum=0xfb58c604140b6d33`, and
  `dp_checksum=0x7a3ee32278528fba`; treat the packet result as coverage, not a
  separate speed claim until the new DP16 packet autoresearch experiment is run
  on a clean commit. A small DP16 threadgroup sweep was deliberately not
  promoted: `tg=256` helped a single packet in one run, while `tg=64` helped
  persistent-chain and `tg=256` hurt it, so the shared 128-thread long-step
  default remains the safer base.
- Rejected follow-up `macos-metal-xyzz-dp16-tg64-default`: after the DP16
  hardcoded-mask commit, a single explicit `--tg-limit 64` persistent-chain
  scout jumped to `127,439,454.404249` steps/sec with matching checksums, but
  the result did not reproduce. Three immediate cooled samples measured
  `108,553,915.612407`, `107,914,485.017660`, and `122,912,031.041083`
  steps/sec, while the clean 128-thread default remained at
  `123,257,579.364915` median and an explicit `--tg-limit 256` scout measured
  `122,606,149.149497`. Keep the default at 128 threads for DP16
  persistent-chain until a paired autoresearch gate separates cleanly.
- Rejected follow-up `macos-metal-xyzz-dp10-hardcoded-mask`: adding DP10
  hardcoded `0x3FF` XYZZ packet and chain kernels preserved correctness and
  checksums, but regressed the measured shapes. The runtime-mask packet
  baseline measured `122,301,207.928573` steps/sec with `dp_count=266`,
  `dp_distance_checksum=0x1c7a1858b9c7c122`, and
  `dp_checksum=0xfac35953988d0260`; the hardcoded DP10 packet measured only
  `117,134,900.908589` with the same checksums. The runtime-mask
  persistent-chain baseline measured `124,488,630.318995` steps/sec with
  `dp_count=490`, `dp_distance_checksum=0xe68a4fceb16626c9`, and
  `dp_checksum=0x6782b304a4b7c1d0`; the hardcoded DP10 persistent-chain
  measured `121,248,208.745216` with the same checksums. Keep DP10 on the
  runtime `ProjectiveDpMask(dp_bits)` path unless a different specialization
  changes register pressure or instruction scheduling enough to beat this
  negative gate.
- Rejected follow-up `macos-metal-xyzz-dp14-hardcoded-mask`: adding DP14
  hardcoded `0x3FFF` XYZZ packet and chain kernels preserved the persistent
  chain oracle but did not reproduce as a speedup. A small smoke on
  `2048 x 512 x 4` returned `correctness=true`, `dp_count=2`,
  `dp_distance_checksum=0xcd94bf3eb529e946`, and
  `dp_checksum=0xd286f3bac8ebdb4a`. The paired autoresearch gate against
  clean `main` then kept identical `131072 x 512 x 4` DP14 checksums
  (`dp_count=34`, `dp_distance_checksum=0x5cb70f4effb5ad6f`,
  `dp_checksum=0xc662777588781698`) but discarded both confirmation runs:
  candidate `51,417,088.435783` vs baseline `116,310,256.764624`
  steps/sec (`paired_speedup=0.442068`) and candidate
  `52,570,949.918239` vs baseline `119,890,117.177222`
  (`paired_speedup=0.438493`). Keep DP14 on the runtime
  `ProjectiveDpMask(dp_bits)` path; the accepted sparse-mask hardcodes remain
  DP12 and DP16 only.
- Rejected follow-up `macos-metal-xyzz-dp16-scaled4-persistent`: the
  `scaled4-balanced` four-jump schedule remained correct for the hardcoded
  DP16 persistent-chain path and produced a very balanced jump histogram
  (`68 ppm` max deviation), but the scout measured only
  `121,928,780.219342` steps/sec with `dp_count=7`,
  `dp_distance_checksum=0x7ec7b709e671d790`, and
  `dp_checksum=0xb5691c80f1d5a82e`, below the power-of-two DP16 clean median
  of `123,257,579.364915`. Keep `scaled4-balanced` as schedule coverage and
  CPU tiny-solver research, not as the current Metal persistent-chain
  throughput default.
- Accepted probe `macos-metal-xyzz-affine-scan-gate`: added a solver-facing
  XYZZ packet benchmark that keeps the accepted register-resident XYZZ
  mixed-add plateau, writes one GPU packet distance per walker, then performs a
  CPU batched affine distinguished-point scan at the packet boundary. The scan
  normalizes `X,Y,ZZ,ZZZ` with one batch inversion over per-point
  `ZZ*ZZZ` products, deriving `X/ZZ` and `Y/ZZZ` without per-step inversion.
  Runtime JSON marks this as `output_layout=affine_dp_scan`,
  `affine_scan_mode=cpu_batch_prod_zz_zzz`,
  `distance_tracking=packet_distance_uint64`, and
  `dp_tracking=affine_x_limb0_cpu_batch`. Clean autoresearch on commit
  `0b9a406` kept the saturated `262144 x 512` gate with three correct samples:
  median end-to-end throughput `124,390,543.442828` steps/sec
  (`min=122,916,540.587774`, `max=125,536,737.093264`), median raw GPU walk
  throughput `126,283,290.989389` steps/sec, `affine_scan_seconds=0.016172`
  versus `seconds=1.062830`, `dp_count=1057`,
  `dp_distance_checksum=0xf0dc88ed68b2ff64`, and
  `dp_checksum=0x9dba4a07ebbb8e14`. A same-shape projective DP stream sample
  measured `119,810,339.931442` steps/sec with `dp_count=1015`, confirming that
  projective and affine DP surfaces differ while the affine scan cost is about
  `1.52%` of the dispatch time in the clean median. This is not yet a full
  collision table, but it gives future GPU batch-normalization work a
  reproducible oracle and non-cheating metric.
- Inconclusive follow-up `macos-metal-xyzz-affine-scan-tg-sweep`: explicit
  threadgroup probes on the saturated affine-scan gate preserved
  `dp_count=1057`, `dp_distance_checksum=0xf0dc88ed68b2ff64`, and
  `dp_checksum=0x9dba4a07ebbb8e14`. `tg=256` was clearly worse
  (`119,308,438.468156` end-to-end steps/sec), but `tg=64` and `tg=128`
  overlapped across sequential samples (`126,051,033.790371` then
  `125,064,123.237407` for `tg=64`; `124,825,972.726648` then
  `125,677,075.402889` for `tg=128`). Keep the inherited 128-thread default
  for the affine-scan gate until a paired/confirmed run separates the two.
- Accepted architecture probe `macos-metal-affine-scan-target-lookup-tag32`:
  added an integrated benchmark that feeds real affine DP candidates from the
  XYZZ packet-boundary scan into the accepted exact tag32 multi-target lookup
  gate. The scan can now emit full affine `x256` plus `y` parity for each DP;
  the host injects a controlled number of those keys into a tag32 target table,
  runs `target_lookup_tag32_exact256`, and validates every returned index
  against an exact `x256_y_parity` oracle. This does not claim a faster
  mixed-add kernel; it closes the first non-cheating multi-target join metric
  for the macOS path while keeping walk, affine scan, and lookup timings
  separate. A direct M3 scout on `262144 x 512`, `dp_bits=8`,
  `target_count=1048576`, and `hits=64` preserved the accepted affine DP oracle
  (`dp_count=1057`, `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `dp_checksum=0x9dba4a07ebbb8e14`) and produced `hit_count=64`,
  `miss_count=993`, `bytes_per_target=56.000000`,
  `target_lookup_checksum=0x25249bb63bf646d9`, `lookup_seconds=0.001760`,
  `gpu_ops_per_sec=122,269,515.376937`, and end-to-end
  `ops_per_sec=118,758,130.954171`. Clean autoresearch on commit `436d252`
  kept the gate with median `121,827,155.136391` end-to-end ops/sec across
  three correct samples (`min=120,643,386.557275`,
  `max=123,887,745.866683`) and the same DP and target-lookup checksums.
- Follow-up batching probe `macos-metal-affine-scan-target-lookup-tag32-bulk1024`:
  added `--lookup-repeat N` to the integrated affine-DP target-lookup bench.
  The option repeats the real affine-DP query batch before the Metal tag32
  lookup and repeats the expected exact target-index oracle by the same factor,
  so the hit/miss proof remains exact while the lookup dispatch sees a larger
  DP batch. This tests a solver architecture question rather than a faster
  mixed-add formula: dispatching lookup for about one thousand DP keys
  underfills the GPU, while accumulating packet-boundary DPs can expose the
  accepted tag32 lookup kernel throughput. Direct M3 scouts on the same
  `262144 x 512`, `dp_bits=8`, `target_count=1048576`, `hits=64` shape
  preserved `dp_count=1057`, `dp_distance_checksum=0xf0dc88ed68b2ff64`, and
  `dp_checksum=0x9dba4a07ebbb8e14`. With `--lookup-repeat 128`, the run used
  `query_count=135296`, `hit_count=8192`, `miss_count=127104`,
  `lookup_seconds=0.002578`, and `lookups_per_sec=52,478,448.484848`.
  With `--lookup-repeat 1024`, the run used `query_count=1082368`,
  `hit_count=65536`, `miss_count=1016832`, `lookup_seconds=0.004705`, and
  `lookups_per_sec=230,052,445.601637`. Clean autoresearch on commit
  `40b6387` then kept the dedicated
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_bulk1024`
  gate with median `338,447,087.311549` lookups/sec across three correct
  samples (`min=228,103,021.990759`, `max=619,854,011.588818`), preserving
  `dp_count=1057`, `query_count=1082368`, `hit_count=65536`,
  `miss_count=1016832`, and `target_lookup_checksum=0x342aa518f1adaed1`.
  In `autoresearch/results.tsv`, the value is stored in the `ops_per_sec`
  column because the runner aliases the selected metric; for this experiment
  that selected metric is `lookups_per_sec`.
- Accepted follow-up `macos-metal-affine-scan-target-lookup-tag32-distinct-misses1024`:
  added `--lookup-query-mode distinct-misses` for the integrated affine-DP
  target-lookup bench. The default repeat mode is useful for measuring dispatch
  saturation, but it repeats the same DP query keys and can be too cache
  friendly. The distinct-miss mode keeps one real affine-DP query batch with
  its exact injected hits, then fills the remaining bulk query slots with
  deterministic keys that the host first verifies as misses against the tag32
  target table. A direct M3 scout on the `1024x` shape preserved the accepted
  DP oracle and produced `query_count=1082368`, `hit_count=64`,
  `miss_count=1082304`, `lookup_seconds=0.005001`, and
  `lookups_per_sec=216,442,951.678042`. Clean autoresearch on commit
  `49c539d` kept the dedicated
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_distinct_misses1024`
  gate with median `332,746,255.341113` lookups/sec across three correct
  samples (`min=255,305,578.488029`, `max=443,464,765.141918`), preserving
  `dp_count=1057`, `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `dp_checksum=0x9dba4a07ebbb8e14`, `query_count=1082368`, `hit_count=64`,
  `miss_count=1082304`, and `target_lookup_checksum=0x8b2568562837af7f`.
  This strengthens the batching conclusion: the macOS GPU lookup remains
  high-throughput on a mostly-miss batch, not only on repeated DP keys.
- Rejected follow-up `macos-metal-affine-scan-target-lookup-tag32-hits-only`:
  tested a hits-only tag32 output architecture for the same mostly-miss
  integrated DP lookup shape. The idea was to avoid writing one miss sentinel
  per query and instead emit only compact hit records, while still using tag32
  only as a prefilter and verifying every candidate by exact `x256 + y_parity`
  equality. The candidate preserved the accepted DP oracle
  (`dp_count=1057`, `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `dp_checksum=0x9dba4a07ebbb8e14`), `query_count=1082368`, `hit_count=64`,
  and `miss_count=1082304`, but autoresearch measured only
  `265,142,720.522149` lookups/sec (`min=215,334,137.876015`,
  `max=272,134,116.001853`) versus the accepted full-output
  `distinct_misses1024` median of `332,746,255.341113` lookups/sec. A single
  immediate full-vs-hits scout had looked promising (`306,898,734.033649` vs
  `354,066,901.126250` lookups/sec), but the three-sample gate rejected it.
  Do not promote hits-only output until a paired/confirmed variant beats the
  full-output distinct-miss gate.
- Accepted probe `macos-metal-target-lookup-exact256`: added an exact Metal
  multi-target lookup gate for packet-boundary affine DP candidates. The kernel
  probes a deterministic open-addressed table keyed by full affine `x` plus
  `y` parity (`target_key=x256_y_parity`,
  `lookup_layout=open_address_exact256`) and confirms candidates with exact key
  equality, not a fingerprint or probabilistic filter. A one-million target,
  one-million query smoke with 4096 known hits measured
  `80,834,482.287167` exact lookups/sec at the promoted 64-thread default,
  preserved `hit_count=4096`, `miss_count=1044480`,
  `target_table_buckets=2097152`, `target_table_bytes=100663296`,
  `bytes_per_target=96.000000`, and
  `target_lookup_checksum=0x4f62d3a7170b250a`. Clean autoresearch on commit
  `2fe9034` kept the gate with median `125,616,200.459179` lookups/sec across
  three correct samples (`min=108,509,735.324471`,
  `max=143,301,714.266811`) and the same checksum. Earlier sequential scouts showed
  why this should be documented conservatively: the old 256-ish default was
  around `70,816,077.316200` lookups/sec, explicit `tg=64` reached
  `87,588,904.438702` and later `97,733,301.268179`, while `tg=32` was noisy
  (`113,458,390.662137` then `81,032,565.214847`). This improves the
  multi-target join layer that follows affine DP extraction; it is not a
  kangaroo per-step GKeys/s claim, and the core XYZZ mixed-add walk remains the
  main throughput bottleneck.
- Accepted probe `macos-metal-target-lookup-compact-exact256`: replaced the
  full-key-per-bucket lookup table with a compact `hash64 + target_index`
  bucket plus a separate full target-key array. The kernel still verifies full
  affine `x256 + y_parity` equality after the hash prefilter
  (`candidate_verification=hash64_prefilter_then_exact_key_equality`), so the
  hash is only a memory/locality gate, not a correctness oracle. For
  one million targets and one million queries, table memory dropped from
  `100,663,296` bytes to `75,497,472` bytes (`96.000000` to `72.000000`
  bytes/target) while preserving `hit_count=4096`, `miss_count=1044480`, and
  `target_lookup_checksum=0x4f62d3a7170b250a`. Clean paired autoresearch on
  commit `de7323f` kept the gate: compact median `156,975,200.176937`
  lookups/sec (`min=153,101,277.578787`, `max=159,416,087.646262`) versus paired
  exact-layout baseline median `114,033,683.880847` lookups/sec, for
  `paired_speedup=1.376569`. This is a real multi-target DP-join improvement
  and lowers memory pressure for large target sets; it still sits after packet
  affine-DP extraction, so walk-core GKeys/s/MKeys/s must be measured separately.
- Accepted probe `macos-metal-target-lookup-tag32-exact256`: compressed the
  target lookup bucket again to an 8-byte `tag32 + target_index` row. The tag is
  the high 32 bits of the same deterministic hash; the low hash bits still pick
  the open-addressed slot. A tag match only triggers a fetch from the separate
  full-key array, and correctness still requires exact affine `x256 + y_parity`
  equality (`candidate_verification=tag32_prefilter_then_exact_key_equality`).
  For the same one-million target/query gate, table memory dropped to
  `58,720,256` bytes (`56.000000` bytes/target) while preserving
  `hit_count=4096`, `miss_count=1044480`, and
  `target_lookup_checksum=0x4f62d3a7170b250a`. Clean paired autoresearch on
  commit `1d0e147` kept the gate against compact64: tag32 median
  `201,502,401.315374` lookups/sec (`min=142,309,882.030769`,
  `max=232,128,339.039737`) versus compact64 baseline median
  `152,753,533.069305` lookups/sec, `paired_speedup=1.319134`. The run was
  noisy, but both memory and median throughput moved in the right direction, so
  tag32 becomes the promoted exact lookup layout for the multi-target DP join
  benchmark.
- Rejected probe `macos-metal-xyzz-affine-scan-xorfold-mixer`: prototyped an
  explicit `xorfold64` jump mixer only for the affine-scan distance kernel,
  keeping `avalanche64` as the default and validating the alternate walk with
  full CPU replay. The alternate mixer was correct and had a healthy jump
  histogram (`735 ppm` max deviation versus `759 ppm` for avalanche on the
  saturated `262144 x 512` gate), but it did not separate from noise. Sequential
  same-shape end-to-end ratios were approximately `1.000x`, `1.046x`, and
  `0.969x`; the median was neutral and the last pair regressed. Checksums
  changed as expected for a different walk (`dp_distance_checksum`
  `0x3c64d09f19f97adf`, `dp_checksum=0x3f5ba264076581a0`, `dp_count=957`),
  so the path was reverted instead of adding a non-default code surface with no
  demonstrated throughput win.
- Rejected probe `macos-metal-field-mul32-u32x8`: tested a first-principles
  idea that Apple GPU integer throughput might prefer an 8x32-limb secp256k1
  field multiplication over the current 4x64 path. The prototype added an
  isolated `field_mul32_mod_p` benchmark only, kept the solver and XYZZ walk
  untouched, and validated every output against the existing `CpuFieldMul`
  oracle. It was correct but slower in the paired autoresearch run against
  `main`: five real-Metal samples gave candidate median
  `151,867,984.149860` mul/s versus baseline median `177,148,234.231316`
  mul/s (`paired_speedup=0.857293`, status `discard`). Explicit threadgroup
  scouts did not rescue it: `tg=128` measured `90,192,662.852857` mul/s and
  `tg=512` measured `64,951,613.243122` mul/s, both correct and both worse.
  The dirty sandbox autoresearch attempt also produced a `no Metal device
  available` skip row before the authorized GPU run; that row was removed with
  the discarded experiment ledger entries. The prototype was reverted and only
  this note was kept. A future 32-bit arithmetic attempt should not repeat this
  direct 8x32 Comba/fold design; it would need a meaningfully different
  representation such as a lower-radix carry-save form, vectorized paired
  limbs, or a point-formula-level redesign that reduces reductions rather than
  merely swapping limb width.
- Rejected probe `macos-metal-target-lookup-tag32-packed-exact256`: tested
  whether packing the accepted 8-byte `tag32 + target_index` bucket into one
  `ulong` load would improve the multi-target DP join gate on Apple Silicon.
  The prototype preserved the exact target oracle: the 32-bit tag remained only
  a prefilter, and every candidate still required full `x256 + y_parity`
  equality against the target-key array. `make macos-check` passed, including
  the new packed source/CLI checks, and the checksum stayed
  `0x4f62d3a7170b250a`. The clean commit benchmark on `a48e913` against
  `HEAD~1` rejected it: packed median `135,664,964.776392` lookups/sec versus
  tag32 baseline median `150,200,076.394806` lookups/sec
  (`paired_speedup=0.903228`, status `discard`). Keep the accepted two-`uint`
  tag32 bucket. Future lookup work should target fewer probes, better query
  locality, batched DP stream integration, or a materially different table
  layout instead of repacking the same 8-byte row.
- Rejected probe `macos-metal-target-lookup-tag32-halfload-highload`: tested
  whether the tag32 lookup should use a stricter half-load bucket table for
  non-power-of-two multi-target counts. The motivation was linear probing:
  large target files can land near the old 3/4 load threshold, and miss-heavy
  DP joins can pay several extra probes. The candidate changed only tag32
  bucket sizing, kept exact `x256 + y_parity` verification, and passed
  `make macos-check`. A high-load paired benchmark at `target_count=1,572,864`
  rejected it: candidate median `137,879,070.930129` lookups/sec with
  `4,194,304` buckets and `61.333333` bytes/target versus baseline median
  `152,250,947.577372` lookups/sec with `2,097,152` buckets and `50.666667`
  bytes/target (`paired_speedup=0.905604`, status `discard`). The checksum was
  identical (`0xe2b09e38dc85a153`). Keep the existing 3/4 tag32 load policy;
  on this Apple Silicon shape, doubling the bucket table hurts cache behavior
  more than it helps probe count.
- Rejected probe `macos-metal-target-lookup-tag32-sentinel-simplified`: removed
  the redundant `target_index != empty` condition from the tag32 kernel after
  the preceding empty-bucket `break`. The oracle surface was unchanged:
  `tag32` still only filtered candidates before exact full-key equality, and
  `make macos-check` passed. One clean paired run on commit `768b93a` looked
  promising (`245,435,616.929923` lookups/sec versus baseline
  `240,104,595.314191`, `paired_speedup=1.022203`, status `keep`), but the
  required confirmation rejected it. Two confirmation runs produced discard
  rows; the final confirmation median was `159,995,387.777540` lookups/sec
  versus baseline `170,733,796.380747`
  (`paired_speedup=0.937104`, `confirmation_status=discard`). Keep the original
  explicit sentinel guard shape. This is a concrete example of why small
  Metal lookup wins need confirmation before promotion.
- Rejected scout `macos-metal-affine-target-dp10-dp12-large-target-soa`:
  tested whether sparser affine DP settings or a split `tag32`/`target_index`
  lookup table could move the macOS multi-target path toward the 25M-target
  transcript shape. Same-binary direct M3 runs of the integrated affine-scan
  target lookup at `262144 x 512`, one million targets, `lookup_repeat=1024`,
  and distinct misses stayed correct but did not improve the DP8 baseline:
  DP12 measured `117,196,934.111233` end-to-end ops/sec with `dp_count=56`,
  `dp_distance_checksum=0x7d0ee76b8500af2c`, and
  `target_lookup_checksum=0xc5734459b21ca1fc`; DP10 measured
  `114,535,731.414219` ops/sec with `dp_count=252` and
  `target_lookup_checksum=0x6351a7af74e4b2d7`; a same-sequence DP8 control
  measured `117,860,338.540384` ops/sec with the promoted affine DP checksum
  and `target_lookup_checksum=0x8b2568562837af7f`. A 25,005,000-target direct
  integrated run proved the current tag32 table fits and remains exact on a
  MacBook Air M3 16GB shape: `target_table_bytes=1268635456`,
  `bytes_per_target=50.735271`, `dp_count=1057`, `hit_count=64`,
  `target_lookup_checksum=0x25249bb63bf646d9`, and
  `ops_per_sec=101,775,521.235792` for the tiny 1057-query lookup batch.
  Accumulating queries with `lookup_repeat=1024` kept the same affine DP
  oracle and improved end-to-end to `105,475,085.926833` ops/sec while lookup
  throughput reached `7,360,095.669929` lookups/sec on the large table, far
  below the one-million-target cache-friendly gate. A local split-array SoA
  prototype kept exact checksums but was not retained: on 25,005,000 targets
  and 1,082,368 mostly-miss queries, the existing tag32 bucket measured
  `8,285,211.878742` then `7,390,754.552319` lookups/sec, while SoA measured
  `7,470,301.945639` then `5,743,682.460318`; on one million targets, a clean
  sequential repeat also favored the current bucket
  (`175,834,760.507273` versus `130,997,626.097783`). Conclusion: keep the
  promoted two-`uint` bucket; for very large multi-target files, the real next
  target is batching and locality across packet-boundary DP queries, not
  splitting the existing 8-byte row.
- Kept `macos-cpu-tag32-large-target-lookup-engine`: added a host CPU lookup
  engine for the exact tag32 target table and exposed it as
  `target-lookup-tag32-cpu-bench` plus `--lookup-engine cpu` on the integrated
  affine-scan target-lookup benchmark. The GPU walker and affine DP scan remain
  unchanged; only the final exact `x256 + y_parity` target lookup can be routed
  through CPU. This matches the MacBook Air M3 multi-target cost model: for a
  huge 25,005,000-target table and only 1057 DP queries, the Metal lookup
  dispatch plus random table access dominates. A 50ms standalone CPU run kept
  `target_table_bytes=1268635456`, `hit_count=64`,
  `target_lookup_checksum=0x923e3284a866bb64`, and measured
  `87,452,788.580860` lookups/sec. Two same-binary integrated 25,005,000-target
  pairs at `262144 x 512`, `dp_bits=8`, `hits=64`, and `lookup_repeat=1`
  preserved `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `dp_checksum=0x9dba4a07ebbb8e14`, and
  `target_lookup_checksum=0x25249bb63bf646d9`: GPU lookup measured
  `110,545,500.668632` then `108,992,407.143044` ops/sec, while CPU lookup
  measured `120,335,696.839228` then `121,373,018.665758` ops/sec. A larger
  `lookup_repeat=1024` distinct-miss run also stayed exact with
  `target_lookup_checksum=0x8b2568562837af7f`; CPU measured
  `111,191,892.977335` ops/sec and `7,949,552.399940` lookups/sec versus GPU
  `105,302,699.290370` ops/sec and `5,860,746.294648` lookups/sec in the
  current binary. Keep the default engine as `gpu` for continuity, but use
  `--lookup-engine cpu` for large target tables and small or moderate DP query
  batches on Apple Silicon.
- Kept `macos-affine-target-lookup-auto-engine`: added optional
  `--lookup-engine auto` for the integrated affine-scan target-lookup
  benchmark. The JSON keeps the requested value in `lookup_engine` and reports
  the selected path as `lookup_engine_effective`, so the policy remains
  auditable. The current conservative rule chooses CPU only for target tables
  at or above 1,048,576 entries with at most 4,194,304 lookup queries; otherwise
  it keeps the GPU path. Same-binary MacBook Air M3 16GB checks on the
  25,005,000-target shape preserved `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `dp_checksum=0x9dba4a07ebbb8e14`, and the exact target lookup checksums. For
  `lookup_repeat=1`, `auto` selected CPU and measured
  `125,323,517.815323` ops/sec with
  `target_lookup_checksum=0x25249bb63bf646d9`; explicit CPU measured
  `125,234,973.039893` ops/sec, while explicit GPU measured
  `110,527,752.815878` ops/sec. For `lookup_repeat=1024` with distinct misses,
  `auto` selected CPU and measured `109,918,547.568889` ops/sec and
  `7,490,893.889728` lookups/sec with
  `target_lookup_checksum=0x8b2568562837af7f`; explicit GPU measured
  `102,166,231.452873` ops/sec and `4,679,826.418619` lookups/sec. This is a
  pragmatic routing improvement, not a new discrete-log algorithm: it preserves
  the GPU walk and affine scan, then avoids Metal dispatch/random-memory cost
  for large multi-target joins where the host lookup is already faster.
- Kept `macos-affine-target-lookup-tg-split`: added `--lookup-tg-limit` to the
  integrated affine-scan target-lookup benchmark so the final Metal tag32 join
  can use a different threadgroup cap from the XYZZ walk. This preserves the
  exact `x256 + y_parity` oracle and keeps the JSON fields separate:
  `threadgroup_limit` describes the walk, while `lookup_threadgroup_limit`
  describes the target join. The motivating 25,005,000-target M3 sweep with
  `lookup_repeat=1024`, `distinct-misses`, and explicit GPU lookup kept
  `target_lookup_checksum=0x8b2568562837af7f`. With the walk left at its
  default 128-thread cap, lookup-only caps measured `5,702,767.902107`
  lookups/sec at 64, `14,438,608.208282` at 128,
  `20,822,511.200607` at 256, and `32,476,723.426600` at 512 in the first
  sweep. A second pass kept 512 high on lookup throughput
  (`29,861,242.368694` and `30,914,421.587039` lookups/sec), while 1024 did
  not improve end-to-end stability. The clean autoresearch gate
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_lookup_tg512`
  then kept the one-million-target benchmark with median
  `263,692,100.648384` lookups/sec, min `236,813,978.914094`, max
  `294,625,404.461812`, and the same
  `target_lookup_checksum=0x8b2568562837af7f`. Do not make 512 the global
  default yet: walk timing and thermals still dominate total `ops_per_sec`, so
  this is a benchmark-gated GPU lookup tuning knob plus an autoresearch
  experiment, not an automatic policy change.
- Kept follow-up `macos-affine-target-lookup-auto-bulk-gpu`: after the
  lookup-only threadgroup split, the original `--lookup-engine auto` policy was
  too conservative for cache-friendly target tables with large accumulated
  query batches. It chose CPU on the one-million-target,
  `lookup_repeat=1024` distinct-miss gate and measured only about
  `19,964,824.421849` lookups/sec in the target join. The policy now sends
  target tables up to 4,194,304 entries with at least 1,048,576 lookup queries
  to GPU and, when no explicit `--lookup-tg-limit` is supplied, uses a
  512-thread lookup cap. A direct verification run selected
  `lookup_engine_effective=gpu`, reported `lookup_threadgroup_limit=512`,
  preserved `target_lookup_checksum=0x8b2568562837af7f`, and measured
  `333,853,890.188310` lookups/sec on the one-million-target gate. The
  25,005,000-target bulk gate still selected CPU and preserved the same
  checksum, keeping the large-table host routing from the earlier auto policy.
- Rejected widening `auto` GPU routing to 25,005,000-target bulk joins: after
  `--lookup-tg-limit 512` improved cache-friendlier target tables, an
  alternating 25,005,000-target test compared explicit CPU with explicit GPU
  plus lookup cap 512 on the same `lookup_repeat=1024`, `distinct-misses`
  gate. Both paths preserved `target_lookup_checksum=0x8b2568562837af7f`.
  CPU measured `6,860,398.930175` then `7,519,044.362895` lookups/sec with
  `71,783,918.844038` then `70,273,916.262432` ops/sec. GPU+512 measured
  `6,905,762.055189` then `6,333,109.526422` lookups/sec with
  `70,297,193.197471` then `69,908,211.625927` ops/sec. Conclusion: keep
  25M-target bulk auto routing on CPU until a paired cooled run shows a clear,
  repeatable GPU win.
- Rejected `macos-cpu-tag32-bucket-prefetch`: tested a one-bucket-ahead
  `__builtin_prefetch` inside the host CPU tag32 open-addressing probe loop.
  The oracle stayed exact on the 25,005,000-target, 1,082,368-query mostly-miss
  benchmark (`target_lookup_checksum=0x9b23e560b9fdfe29`), but throughput
  dropped from baseline samples of `8,011,398.668428` and
  `8,385,287.330512` lookups/sec to `6,584,104.078200` and
  `7,068,039.110085` lookups/sec. Conclusion: Apple Silicon hardware
  prefetching and the short probe chains already handle this pattern better
  than explicit prefetch hints; do not add bucket prefetch to the CPU tag32
  lookup loop.
- Kept diagnostic benchmark `macos-metal-target-lookup-tag32-persistent`:
  added `metal-target-lookup-tag32-persistent-bench` to separate Metal setup
  cost from repeated dispatch cost for the exact tag32 target lookup. It
  creates the device pipeline and `target_keys`/bucket/query buffers once,
  repeats dispatches for `--min-ms`, and reports both `metal_setup_seconds`
  and `dispatch_seconds`; `seconds` and `lookups_per_sec` include setup, while
  `dispatch_lookups_per_sec` isolates the warmed dispatch loop. This is useful
  for understanding device-resident target-table economics, but it must not be
  read as a solver win when `--min-ms` repeats the same query set and warms
  cache. Same-binary M3 probes stayed exact. On one million targets with one
  million queries and `min_ms=500`, the old per-call buffer path measured
  `101,048,711.053541` lookups/sec, while persistent measured
  `629,993,688.283748` lookups/sec including setup and
  `687,238,232.934819` dispatch-only, with
  `target_lookup_checksum=0x4f62d3a7170b250a`. On the 25,005,000-target,
  1057-query tiny batch, persistent improved the old GPU path only modestly
  (`77,016.523835` total lookups/sec and `610,879.173568` dispatch-only versus
  `53,436.540847` old GPU), still far below CPU
  (`83,196,783.500529` lookups/sec). On 25,005,000 targets with 1,082,368
  queries, persistent repeated-dispatch measured `30,149,298.733013` total and
  `122,171,279.437910` dispatch-only, but a single dispatch showed the honest
  setup penalty: `metal_setup_seconds=0.743334`, `dispatch_seconds=0.148893`,
  and `1,213,108.039165` total lookups/sec. Conclusion: persistent Metal
  buffers are promising for long-lived, device-resident multi-target tables and
  large fresh batches, but the production decision should be gated by a future
  integrated benchmark that reuses the target table while feeding fresh DP
  query batches.
- Kept follow-up `macos-metal-target-lookup-tag32-persistent-tg1024`: the
  persistent Metal tag32 lookup now keeps the historical 64-thread default for
  tables below 16,777,216 targets, but uses a 1024-thread cap for larger
  diagnostic tables unless `--tg-limit` is explicit. This is deliberately
  scoped to the standalone persistent benchmark; integrated affine lookup and
  `--lookup-engine auto` routing are unchanged. Several candidates were noisy:
  an early sweep made 128/256 look attractive, but later alternating runs
  showed 256 outliers and 128 setup spikes. The stable large-table head-to-head
  on 25,005,000 targets, 1,082,368 queries, `hits=64`, and `min_ms=700`
  compared old `--tg-limit 64` against the new default 1024. Both preserved
  `target_lookup_checksum=0x9b23e560b9fdfe29`. The old 64-thread cap measured
  `201,386,356.101149`, `218,208,323.440100`, and `101,037,320.822952`
  lookups/sec; the 1024-thread cap measured `221,510,357.829906`,
  `218,161,668.783517`, and `221,515,019.875647` lookups/sec. The median
  setup-inclusive improvement is about `1.10x`, with 1024 also keeping warmed
  dispatch throughput near `266M` lookups/sec in all three runs. The 1M-target
  command remains on 64 because its short smoke checks did not justify a
  default change there. Clean paired autoresearch on commit `5a27649` against
  `main^` with two confirmation decisions also kept the gate. Confirmation 1
  recorded median `193,850,878.038308` lookups/sec versus paired baseline
  `184,805,207.139682` (`1.048947x`); confirmation 2 recorded median
  `175,132,519.820510` versus `169,434,696.493505` (`1.033628x`). Both rows
  preserved `correctness=true`, `confirmation_status=keep`, `threadgroup_limit=1024`,
  and `target_lookup_checksum=0x9b23e560b9fdfe29`.
- Rejected integrated probe `macos-metal-affine-target-lookup-gpu-persistent`:
  tested reusing the Metal tag32 target table and pipeline in the integrated
  affine-scan target-lookup path while allocating fresh query/output buffers
  per DP batch. It preserved exact checksums but was slower setup-inclusive on
  the MacBook Air M3 shape. At 25,005,000 targets with `lookup_repeat=1`, it
  measured `81,433,053.501561` ops/sec with
  `target_lookup_checksum=0x25249bb63bf646d9`, behind the prior same-shape
  default GPU pair (`110,545,500.668632` then `108,992,407.143044` ops/sec)
  and CPU pair (`120,335,696.839228` then `121,373,018.665758` ops/sec). With
  `lookup_repeat=1024` and distinct misses, it measured
  `63,685,540.617618` ops/sec and `1,845,679.529534` lookups/sec with
  `target_lookup_checksum=0x8b2568562837af7f`, behind the current CPU/GPU
  baselines. A contended `min_ms=300` scout also favored CPU
  (`46,461,716.600766` ops/sec) over gpu-persistent
  (`38,249,841.037901` ops/sec) with the same checksum. Conclusion: keep the
  standalone persistent Metal lookup benchmark as a diagnostic, but do not add
  an integrated `gpu-persistent` engine until the solver can keep the target
  table resident across genuinely long-lived batches and amortize setup without
  repeating the same query set.
- Accepted direct probe `macos-metal-target-lookup-tag32-filter-exact256`:
  replaced the GPU-side exact tag32 bucket row with a 4-byte filter tag and a
  compact positive-query list, then kept exact verification on CPU against the
  full `x256 + y_parity` target keys. The filter tag is derived from the same
  high hash bits as the exact tag32 prefilter, with zero reserved as the empty
  bucket sentinel, so it can introduce false positives but not false negatives.
  This changes the large-table memory economy without changing the correctness
  oracle: the final `target_lookup_checksum` and `correctness=true` still come
  from exact key equality. On the 25,005,000-target, 1,082,368-query,
  `hits=64`, mostly-miss standalone shape, two direct M3 scouts preserved
  `target_lookup_checksum=0x9b23e560b9fdfe29`, produced
  `filter_positive_count=64`, `filter_false_positive_count=0`, and reduced the
  GPU table bytes from `1,268,635,456` to `134,217,728`. The filter path
  measured `75,078,857.365323` and `77,918,623.497528` lookups/sec, versus CPU
  exact lookup at `7,983,948.410868` and `7,703,140.841793` lookups/sec on the
  same generated table. The old exact Metal tag32 path was noisy on this shape
  (`1,628,976.934645` then `11,962,461.472999` lookups/sec), which reinforces
  the conclusion that the breakthrough is fewer random bytes per probe, not a
  threadgroup scheduling tweak. Keep the standalone `metal-target-lookup-tag32-filter-bench`
  gate as an accepted lookup-only improvement. Clean paired autoresearch on
  commit `feb9db3` against `main^` with two confirmation decisions kept the
  gate: confirmation 1 recorded median `81,824,789.519815` lookups/sec versus
  paired exact Metal baseline `7,906,908.934311` (`10.348518x`), and
  confirmation 2 recorded median `90,535,388.113438` versus
  `12,925,222.416170` (`7.004552x`). Both rows preserved
  `target_lookup_checksum=0x9b23e560b9fdfe29`, `correctness=true`,
  `filter_positive_count=64`, `filter_false_positive_count=0`, and
  `confirmation_status=keep`.
- Direct scout `macos-metal-target-lookup-tag32-filter-persistent`: added a
  persistent version of the accepted tag32 filter lookup, keeping the compact
  filter table, query buffer, positive-index output, and Metal pipeline
  resident while still verifying compact positives on CPU with exact
  `x256 + y_parity` equality after each dispatch. The no-setup
  `dispatch_lookups_per_sec` includes exact CPU verification time, not only GPU
  dispatch time. A 25,005,000-target, 1,082,368-query, `hits=64`,
  `min_ms=700` direct sweep preserved
  `target_lookup_checksum=0x9b23e560b9fdfe29`, `correctness=true`,
  `filter_positive_count=64`, and `filter_false_positive_count=0` for all
  variants. Non-persistent filter measured `42,529,328.877982` lookups/sec at
  the default 64-thread cap and `61,674,769.263690` with `--tg-limit 1024`.
  Persistent filter measured `481,602,631.287665` at 64 threads,
  `502,568,498.005001` at 512 threads, and `416,378,732.454942` at 1024
  threads, so the large-table persistent-filter default is 512 threads on M3.
  Clean paired autoresearch on commit `bf01557` against `main^` kept the gate
  across two confirmations. Confirmation 1 recorded median
  `336,974,086.813292` lookups/sec versus non-persistent filter baseline
  `56,761,507.658097` (`5.936666x`); confirmation 2 recorded median
  `433,107,771.320567` versus `83,397,796.618923` (`5.193276x`). Both rows
  preserved `target_lookup_checksum=0x9b23e560b9fdfe29`, `correctness=true`,
  `threadgroup_limit=512`, `filter_positive_count=64`,
  `filter_false_positive_count=0`, and `confirmation_status=keep`.
- Kept `macos-metal-target-lookup-tag16-filter-persistent`: changed the
  persistent filter row from a 4-byte tag32 bucket to a 2-byte tag16 bucket
  while leaving final verification on exact CPU `x256 + y_parity` equality.
  The smaller resident filter halves the GPU filter table from 134,217,728 to
  67,108,864 bytes on the 25,005,000-target shape. It intentionally allows
  extra tag collisions; the 1,082,368-query, `hits=64`, mostly-miss gate
  reported `filter_positive_count=311` and `filter_false_positive_count=247`,
  with `hit_count=64`, `miss_count=1082304`, `correctness=true`, and
  `target_lookup_checksum=0x9b23e560b9fdfe29`. Clean paired autoresearch on
  commit `209a31c` against `main^` tag32 persistent baseline with two
  confirmation decisions kept the gate. Confirmation 1 recorded median
  `484,056,946.155764` lookups/sec versus paired baseline
  `452,953,236.815958` (`1.068669x`); confirmation 2 recorded median
  `480,486,002.881186` versus `381,489,141.634999` (`1.259501x`). The
  no-cheat boundary is unchanged: tag16 is only a memory filter, and every
  reported hit is still decided by full target-key equality.
- Kept `macos-metal-target-lookup-tag16-hash-filter-persistent`: kept the
  accepted tag16 resident filter but changed the GPU query input from full
  `TargetLookupKey` rows to precomputed `hash64` values. The Metal filter still
  only emits compact positive query indices; final correctness still comes from
  CPU exact `x256 + y_parity` equality against the full target table. On the
  same 25,005,000-target, 1,082,368-query, `hits=64` shape, the gate preserved
  `target_lookup_checksum=0x9b23e560b9fdfe29`, `correctness=true`,
  `filter_positive_count=311`, `filter_false_positive_count=247`,
  `target_filter_bucket_bytes=67108864`, and added
  `target_query_hash_bytes=8658944`. Clean paired autoresearch on commit
  `1a29d64` against `main^` tag16 baseline with two confirmation decisions
  kept the gate. Confirmation 1 had a noisy low outlier but median candidate
  still recorded `587,549,574.555683` lookups/sec versus paired baseline
  `413,622,377.497074` (`1.420498x`); confirmation 2 recorded
  `679,964,381.462716` versus `509,095,163.925694` (`1.335633x`). Conclusion:
  after tag16 found the useful filter-width knee, the next durable win is
  reducing query-side GPU bandwidth and hash work without changing candidate
  semantics.
- Kept the inherited 512-thread large-table default for
  `macos-metal-target-lookup-tag16-hash-filter-persistent`: a direct
  25,005,000-target, 1,082,368-query scout with `min_ms=300` preserved
  correctness and checksum for all caps, but did not justify a default change.
  `--tg-limit 64`, `128`, and `256` measured `22,468,677.594189`,
  `13,207,985.528788`, and `22,676,290.324094` lookups/sec in that noisy
  sweep; `512` measured `441,719,452.250274`, and `1024` measured
  `394,760,645.293742`. Conclusion: keep the existing 512-thread large-filter
  default for the prehashed kernel too.
- Rejected and reverted tag16 zero-only sentinel remap for
  `macos-metal-target-lookup-tag16-hash-filter-persistent`: the idea was to
  replace the old `tag | 1` encoding, which folds all even tags into odd tags,
  with a mapping that preserves every nonzero 16-bit tag and remaps only zero
  to the nonzero sentinel. Deterministically, this reduced compact positives on
  the 25,005,000-target, 1,082,368-query, `hits=64` shape from
  `filter_positive_count=311` and `filter_false_positive_count=247` to
  `190` and `126`, while preserving `correctness=true` and
  `target_lookup_checksum=0x9b23e560b9fdfe29`. Throughput did not pass the
  paired gate. The first ternary version had one isolated raw keep
  (`45,353,378.397795` versus `44,244,407.017188`, `1.025065x`) and one
  discard (`53,724,312.532616` versus `80,314,447.239320`, `0.668925x`).
  The branchless `tag | (tag == 0)` version had one very noisy raw keep
  (`648,259,973.315809` versus `105,861,805.836167`, `6.123644x`) and one
  discard (`93,387,661.680901` versus `584,292,117.657674`, `0.159830x`).
  Both confirmation sets ended with `confirmation_status=discard`, so the code
  was reverted and only the experiment/ledger entries were kept. Conclusion:
  lower false positives alone are not enough on this mostly-miss M3 shape; do
  not reintroduce tag16 remapping unless it is tied to a workload where CPU
  exact-positive verification dominates and the paired gate keeps.
- Rejected `macos-metal-target-lookup-tag8-filter-persistent`: a local
  25,005,000-target, 1,082,368-query scout kept exact correctness and the same
  `target_lookup_checksum=0x9b23e560b9fdfe29`, but the 1-byte filter created
  too many compact positives for the CPU exact resolver. The tag16 baseline in
  the same scout measured `426,395,117.864425` lookups/sec with
  `filter_positive_count=311`, `filter_false_positive_count=247`, and
  `exact_verify_seconds=0.005822`; tag8 measured only
  `51,660,928.817672` lookups/sec with `filter_positive_count=55624`,
  `filter_false_positive_count=55560`, and `exact_verify_seconds=0.216984`.
  Conclusion: the useful memory/filter-width knee for this mostly-miss M3
  shape is tag16, not tag8. No tag8 code or autoresearch gate was kept.
- Kept explicit engine but rejected auto promotion
  `macos-metal-affine-target-lookup-gpu-filter25m`: added
  `--lookup-engine gpu-filter` for the 25,005,000-target, `lookup_repeat=1024`,
  distinct-miss integrated gate. The walk, affine scan, injected hits, and final
  exact key equality remain unchanged; only the final multi-target join uses
  the compact GPU filter plus CPU exact verification of positives. Two direct
  M3 scouts preserved `target_lookup_checksum=0x8b2568562837af7f`,
  `correctness=true`, `filter_positive_count=64`, and
  `filter_false_positive_count=0`. CPU routing measured
  `110,421,412.238887` and `110,213,461.114858` ops/sec. The filter path
  measured `120,674,390.799366` and `119,031,056.396993` ops/sec through
  `auto` before the policy was reverted, and explicit `gpu-filter` measured
  `122,315,209.631509` and `117,012,102.624015` ops/sec. Clean paired
  autoresearch on commit `9a88e7e` against `main^` with two confirmations
  rejected automatic promotion: confirmation 1 had candidate median
  `118,192,117.838356` ops/sec versus paired CPU baseline
  `107,945,031.651480` (`1.094929x`, raw keep), but confirmation 2 had
  candidate median `64,324,197.141042` versus paired CPU baseline
  `64,245,663.646454` (`1.001222x`, raw discard). Both rows preserved
  `correctness=true`, `lookup_engine_effective=gpu_filter`,
  `filter_positive_count=64`, `filter_false_positive_count=0`, and the same
  checksum. Conclusion: keep `--lookup-engine gpu-filter` and the standalone
  filter benchmark, but do not route `--lookup-engine auto` to the filter on
  this shape until a future paired gate keeps across confirmations.
- Kept explicit integrated `gpu-filter16-hash` for the same 25,005,000-target,
  `lookup_repeat=1024`, distinct-miss affine-scan gate. This imports the
  accepted standalone tag16 hash filter into the final DP target join: the
  walk, affine scan, injected hits, target key, and final CPU exact
  `x256 + y_parity` equality are unchanged, while the lookup filter table drops
  from 134,217,728 bytes to 67,108,864 bytes and Metal reads precomputed
  `hash64` query input (`target_query_hash_bytes=8658944`). False positives are
  expected and explicit: the kept rows reported `filter_positive_count=280`,
  `filter_false_positive_count=216`, `hit_count=64`, `correctness=true`, and
  `target_lookup_checksum=0x8b2568562837af7f`. Clean paired autoresearch on
  commit `f19bf60` against `main^`, using `--lookup-tg-limit 512` for both
  candidate and tag32-filter baseline, kept across two confirmations.
  Confirmation 1 recorded median `110,796,227.320140` ops/sec versus
  `97,896,085.677205` (`1.131774x`); confirmation 2 recorded
  `97,927,206.806094` versus `90,575,505.666126` (`1.081167x`). A stricter
  follow-up CPU gate on commit `1e2ca77` kept the same explicit engine against
  CPU routing across both confirmations: `118,623,733.699262` versus
  `107,559,765.934095` (`1.102863x`) and `110,765,603.652636` versus
  `106,798,322.172981` (`1.037147x`). Both rows preserved
  `correctness=true`, `filter_positive_count=280`,
  `filter_false_positive_count=216`, and the same checksum. A separate
  attempt to promote `--lookup-engine auto` to `gpu_filter16_hash` for this
  25M-target shape on commit `43974c5` was rejected and reverted: the two
  confirmations measured only `0.442977x` and `0.869524x` versus the old auto
  baseline. Conclusion: keep `gpu-filter16-hash` as an explicit integrated
  engine, but keep `--lookup-engine auto` conservative until more target counts
  and DP densities pass paired gates.
- Rejected sparse full-output validation for integrated filter engines. Commit
  `87d8025` kept the exact checksum (`0x8b2568562837af7f`) and correctness, but
  paired autoresearch against `main^` discarded both confirmations:
  `29,442,389.766506` ops/sec versus `32,451,339.308134` (`0.907278x`) and
  `26,769,370.789497` versus `33,207,078.010911` (`0.806134x`). The idea was
  to compute the expected checksum while building the mostly-miss oracle and
  validate only compact filter positives, but the affine-scan throughput metric
  already excludes the final full-output validation pass. Conclusion: do not
  spend complexity on sparse validation in this benchmark path; target query
  generation, hashing, lookup dispatch, and XYZZ walk economics are better
  optimization surfaces.
- Rejected changing the large integrated `gpu-filter16-hash` default lookup
  threadgroup cap from 512 to 128. A direct scout suggested better
  lookup-only throughput at 128, but paired autoresearch on commit `314e461`
  against the old default was mixed and therefore discarded by confirmation
  policy: confirmation 1 was a raw keep (`29,668,582.042430` versus
  `26,502,836.838557`, `1.119449x`), while confirmation 2 regressed
  (`28,114,725.754939` versus `33,063,506.770770`, `0.850325x`). Both rows
  preserved `correctness=true` and `target_lookup_checksum=0x8b2568562837af7f`.
  Conclusion: keep the 512-thread default for now; revisit 128 only with a
  lookup-metric-specific gate or a less noisy lookup-isolated benchmark.
- Rejected changing the isolated persistent tag16 hash-filter lookup default
  cap from 512 to 256 on the 25M-target gate. Direct scouts alternated between
  apparent 256 wins and 512 wins with the same checksum, so commit `ba4a706`
  was tested against an explicit old `--tg-limit 512` baseline. The paired
  confirmation discarded it: confirmation 1 was already below baseline
  (`384,244,831.768039` versus `403,094,013.250482`, `0.953239x`), and
  confirmation 2 collapsed after a high setup-time sample
  (`23,582,491.610644` versus `94,876,091.595852`, `0.248561x`). Both rows
  preserved `correctness=true`,
  `target_lookup_checksum=0x9b23e560b9fdfe29`, `hit_count=64`, and
  `filter_positive_count=311`. Conclusion: keep 512 as the persistent
  hash-filter large-target default; future lookup tuning needs a setup-excluded
  decision metric or a solver-resident table harness.
- Added a dispatch-only diagnostic gate for persistent tag16 hash-filter lookup
  so prehashed query input can be judged on `dispatch_lookups_per_sec` without
  setup allocation noise deciding the result. The first paired run at commit
  `3f502b5` still rejected the prehash path against the in-kernel tag16 filter:
  confirmation 1 was a raw keep (`460,269,790.538310` versus
  `412,656,845.592278`, `1.115381x`) but confirmation policy discarded it after
  confirmation 2 regressed (`431,249,765.064511` versus
  `530,756,126.382268`, `0.812520x`). Both rows preserved `correctness=true`,
  `target_lookup_checksum=0x9b23e560b9fdfe29`, `hit_count=64`, and
  `filter_positive_count=311`. Conclusion: keep the dispatch-only gate as a
  useful microscope, but do not treat prehashed query input as a durable GPU
  lookup win on this M3 run.
- Added `gpu_dispatch_lookups_per_sec` to the persistent filter lookup JSON so
  future gates can score only Metal dispatch time instead of setup or exact CPU
  verification. A first paired run at commit `d97bd05` kept the prehashed
  tag16 hash-filter path by this new metric (`641,785,601.889930` versus
  `40,184,259.839965`, then `260,477,452.934580` versus `22,885,559.034950`)
  with `correctness=true` and the same
  `target_lookup_checksum=0x9b23e560b9fdfe29`. Caveat: this is not yet a
  solver-speed claim, because the persistent filter loop still stops its
  `--min-ms` window on dispatch plus exact CPU verification; the next harness
  change should make the timing window dispatch-bound before promoting
  prehashed queries as a durable GPU win.
- Accepted the follow-up harness fix at commit `af8096c`: persistent tag32,
  tag16, and tag16-hash filter lookup benches now keep their `--min-ms` timing
  window bounded by accumulated Metal dispatch time, while still reporting
  exact CPU verification separately. Re-running the GPU-only prehash gate after
  this fix kept the tag16 hash-filter path over in-kernel hashing with much
  more realistic paired speedups: `40,407,764.739561` versus
  `39,265,863.585433` (`1.029081x`), then `44,839,716.146274` versus
  `36,432,369.467395` (`1.230766x`). Both rows preserved
  `correctness=true`, `target_lookup_checksum=0x9b23e560b9fdfe29`,
  `hit_count=64`, and `filter_positive_count=311`. Treat this as a real
  GPU-filter diagnostic win for prehashed query input, not yet as an
  end-to-end kangaroo solver speedup.
- Rejected changing the long XYZZ 512-step packet default threadgroup cap from
  128 to 512. A local scout sometimes showed higher lookup-free packet
  throughput at 384/512, but paired autoresearch on commit `d8f05f4` against
  the old default was mixed and discarded: confirmation 1 was a raw keep
  (`54,922,712.642899` versus `48,229,183.416788`, `1.138786x`), while
  confirmation 2 regressed (`41,442,869.888584` versus `47,356,402.122712`,
  `0.875127x`). Both rows preserved `correctness=true` and
  `dp_checksum=0x390f891179fdcbea`. Conclusion: keep the 128-thread long
  packet default; any future occupancy tuning needs either a less noisy Metal
  timing harness or a different metric than end-to-end `ops_per_sec`.
- Added solver-facing lookup diagnostics to the integrated affine-scan
  target-lookup JSON. The command now reports `lookup_hash_seconds`,
  `lookup_gpu_seconds`, `lookup_exact_seconds`, and
  `gpu_lookup_lookups_per_sec` in addition to the existing inclusive
  `lookup_seconds` and end-to-end `ops_per_sec`. The fields do not change
  lookup routing or the oracle; they expose whether a candidate is spending
  time in host prehash, Metal filter dispatch, or exact CPU positive
  verification. A small smoke run with `gpu-filter16-hash` preserved
  `correctness=true` and `target_lookup_checksum=0x012a6e4dc9194ecd`.
- Ran unpaired 25M-target scouts with the new diagnostics. The explicit
  tag16 hash-filter at `--lookup-tg-limit 512` preserved
  `target_lookup_checksum=0x8b2568562837af7f`, with
  `lookup_seconds=0.055200`, split into `lookup_hash_seconds=0.009200`,
  `lookup_gpu_seconds=0.045851`, and `lookup_exact_seconds=0.000149`;
  end-to-end throughput was `93,194,798.792308 ops/sec`. The matching CPU
  lookup control preserved the same checksum with `lookup_seconds=0.135615`
  and `81,088,040.074308 ops/sec`. This single comparison is encouraging but
  not enough to promote `--lookup-engine auto`, because earlier paired
  confirmations for the same large class were mixed.
- Added
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_tg256_gpu_lookup`
  as a diagnostic autoresearch gate comparing explicit lookup threadgroup 256
  against 512 on the 25M-target tag16 hash-filter shape. Dirty local scouts
  suggested 256 may be better (`gpu_lookup_lookups_per_sec=134,544,100.295499`,
  `ops_per_sec=115,559,189.799480`) than 384
  (`54,027,452.887182`, `105,784,276.376713`) or later thermal-affected
  512/128 controls (`43,589,238.536233` / `30,113,247.967282` GPU lookup/s).
  All runs preserved `correctness=true`, `target_lookup_checksum=0x8b2568562837af7f`,
  `hit_count=64`, and `filter_positive_count=280`. Treat this as a candidate
  for paired confirmation only; no default threadgroup or `auto` routing policy
  has been changed.
- Paired autoresearch rejected that tg256 candidate on commit `f74a2c5`
  against the same code at `HEAD`, using tg512 as `paired_baseline_command` and
  scoring `gpu_lookup_lookups_per_sec`. Confirmation 1 had candidate median
  `72,371,560.585994` versus baseline `116,195,207.278346` (`0.622845x`);
  confirmation 2 had candidate median `32,413,870.036723` versus baseline
  `63,839,412.471301` (`0.507741x`). Both confirmations preserved
  `correctness=true`, `target_lookup_checksum=0x8b2568562837af7f`,
  `hit_count=64`, and `filter_positive_count=280`. Conclusion: keep the
  explicit 25M tag16 hash-filter gate on tg512 for now, and do not change the
  integrated default or `auto` routing from the unpaired tg256 scouts.
- Rejected parallelizing the host query-hash builder for the integrated 25M
  tag16 hash-filter path. A dirty paired run against serial commit `e7a52db`
  used the same tg512 command on both sides and scored inclusive
  `lookups_per_sec`; the candidate median was `12,982,593.203088` versus
  baseline `28,929,781.596945` (`0.448762x`). The candidate preserved
  `correctness=true`, `target_lookup_checksum=0x8b2568562837af7f`,
  `hit_count=64`, and `filter_positive_count=280`, but the thread overhead and
  memory traffic did not pay for this batch shape. The production hash builder
  remains serial; the experiment descriptor is kept only as a future
  code-vs-code gate for different hash-build designs.
- Rejected `gpu-filter16-fast`, an integrated affine-scan lookup candidate
  that kept full `x256 + y_parity` query rows on the GPU side, computed a
  lightweight `key40_fast_hash` inside the Metal kernel, probed a 2-byte tag16
  filter, and still accepted candidates only through the unchanged CPU exact
  equality resolver over compact positives. The prototype preserved
  `correctness=true`, `target_lookup_checksum=0x8b2568562837af7f`,
  `hit_count=64`, `filter_positive_count=313`, and
  `filter_false_positive_count=249`, but did not pass the paired gates.
  Dirty paired end-to-end autoresearch scored `52,920,937.138620`
  `ops_per_sec` versus the explicit `gpu-filter16-hash` baseline at
  `59,441,584.434450` (`0.890302x`). A follow-up lookup-only gate was highly
  unstable: an earlier single confirmation kept it at `88,517,644.638092`
  versus `26,851,353.739957` `lookups_per_sec` (`3.296580x`), but the stricter
  two-confirmation run discarded it. Confirmation 1 had candidate median
  `23,354,516.791140` versus baseline `26,384,687.341231` (`0.885155x`);
  confirmation 2 had candidate median `78,110,309.682183` versus baseline
  `12,251,668.020419` (`6.375484x`), producing
  `confirmation_status=discard`. Conclusion: do not keep the engine, do not
  promote `auto`, and treat this as evidence that query-hash placement is a
  promising but very noisy axis requiring a more stable kernel/timing design.
- Rejected promoting `--lookup-engine auto` to `gpu_filter16_hash` for the
  25,005,000-target `lookup_repeat=4096` distinct-miss shape. Direct scouts
  looked promising: explicit `gpu-filter16-hash` preserved
  `correctness=true`, `target_lookup_checksum=0x78c54b7ab782db0e`,
  `hit_count=64`, `filter_positive_count=964`, and
  `filter_false_positive_count=900`, while measuring `114,501,711.697336`
  ops/sec versus explicit CPU at `81,511,342.555743` and old auto exact-GPU at
  `104,387,015.748636`. The paired auto-vs-auto gate still discarded the
  policy change. Confirmation 1 was a raw keep: candidate auto routed to
  `gpu_filter16_hash` and scored `116,490,697.814699` ops/sec versus old auto
  routed to exact GPU at `91,841,252.102085` (`1.268392x`). Confirmation 2
  regressed: candidate median `76,155,652.639750` versus baseline
  `82,761,070.389746` (`0.920187x`). All rows preserved the checksum and hit
  counts. Conclusion: keep `auto` unchanged; larger accumulated DP batches are
  a promising multi-target axis, but the current M3 timing is too noisy for an
  automatic policy without a more stable resident-table or dispatch-only gate.
- Kept thresholded parallel host query-hash building for explicit integrated
  `gpu-filter16-hash` on large accumulated batches. The implementation keeps
  the old serial builder below `kMinParallelTargetLookupHashQueries=2097152`
  query rows, then fills the precomputed `hash64` query buffer with
  `ParallelForSamples` above that threshold. It does not change the tag16
  filter table, Metal lookup kernel, compact-positive resolver, exact CPU
  `x256 + y_parity` equality oracle, or `--lookup-engine auto` policy. The
  first accepted gate used the 25,005,000-target `lookup_repeat=4096`
  distinct-miss shape (`query_count=4,329,472`,
  `target_query_hash_bytes=34,635,776`) and scored `lookups_per_sec` against
  the old serial builder at `HEAD`. Both confirmations preserved
  `correctness=true`,
  `target_lookup_checksum=0x78c54b7ab782db0e`, `hit_count=64`,
  `filter_positive_count=964`, and `filter_false_positive_count=900`.
  Confirmation 1 kept with candidate median `21,675,244.226311` lookups/sec
  versus baseline `10,124,044.254344` (`2.140967x`); confirmation 2 kept with
  candidate median `45,893,820.612292` versus baseline `29,851,024.943759`
  (`1.537429x`). A threshold-edge repeat2048 gate also kept against serial
  commit `040bed7`: confirmation 1 measured `56,763,210.855813` versus
  `46,262,580.174655` (`1.226979x`), and confirmation 2 measured
  `71,661,607.645005` versus `57,162,103.373041` (`1.253656x`), preserving
  `target_lookup_checksum=0x90b9fdeac531859a`, `hit_count=64`,
  `filter_positive_count=508`, and `filter_false_positive_count=444`.
  Conclusion: keep the thresholded parallel hash builder for large explicit
  tag16 hash-filter lookup batches, but keep smaller `lookup_repeat=1024`
  batches on the serial path that was previously faster.
- Rejected an integrated `gpu-filter16` full-key in-kernel hash candidate for
  the 25,005,000-target `lookup_repeat=2048` distinct-miss shape. The idea was
  to remove host `lookup_hash_seconds` and `target_query_hash_bytes` by sending
  full `x256+y_parity` query rows to the existing Metal tag16 filter kernel,
  while keeping the same tag16 table and exact CPU positive resolver. The
  smoke test preserved exactness (`target_query_hash_bytes=0`,
  `lookup_hash_seconds=0`, expected hit/miss counts), but paired confirmation
  against the accepted prehashed `gpu-filter16-hash` path was unstable and
  failed the gate. Confirmation 1 discarded with candidate median
  `82,195,149.234095` lookups/sec versus baseline `95,111,599.063584`
  (`0.864205x`); confirmation 2 was only a raw keep at
  `79,706,397.253435` versus `76,693,431.864349` (`1.039286x`). Both rows
  preserved `target_lookup_checksum=0x90b9fdeac531859a`, `hit_count=64`,
  `filter_positive_count=508`, and `filter_false_positive_count=444`, but
  `confirmation_status=discard`. Conclusion: do not add an integrated
  full-key tag16 filter engine yet; keep the prehashed path plus visible
  `lookup_hash_seconds`, and only revisit if a resident solver design can avoid
  the full-query traffic without hiding exact verification.
- Rejected `CpuXyzzBatchAffineDpScan` thread-local scratch reuse for the
  262,144-walker `steps=512` affine-scan gate. The candidate reused the
  `prefixes`, `products`, and `active` vector capacity across dispatches while
  preserving the same batch-inversion math and DP checksum. Correctness stayed
  intact (`dp_count=1057`, `dp_checksum=0x9dba4a07ebbb8e14`), but paired
  confirmation against the previous local baseline failed: confirmation 1 was
  a raw discard at `116,679,627.739438` versus `116,980,249.552503`
  (`0.997430x`), and confirmation 2 regressed to `104,102,988.908292` versus
  `108,253,765.898680` (`0.961657x`). Conclusion: keep the local vector
  allocation shape for the affine scan; the dominant plateau remains GPU walk
  timing and batch-normalization arithmetic, not host vector capacity reuse.
- Rejected `CpuXyzzBatchAffineDpScan` all-active fast path for the same
  affine-scan gate. The prototype avoided allocating/writing the `active`
  bitmap and skipped the reverse-loop `active[i]` branch when every GPU-returned
  XYZZ point had nonzero `ZZ/ZZZ`, falling back to the original bitmap path for
  invalid points. The source gate, `make macos-check`, and a specific
  affine-scan smoke run preserved correctness (`dp_count=1057`,
  `dp_checksum=0x9dba4a07ebbb8e14`,
  `dp_distance_checksum=0xf0dc88ed68b2ff64`). Paired confirmation against
  `HEAD` was mixed and therefore discarded: confirmation 1 measured candidate
  `65,169,523.543836` versus baseline `64,876,935.235559` (`1.004510x`, raw
  discard below the 1% gate), while confirmation 2 measured candidate
  `32,371,999.861737` versus baseline `27,156,148.855221` (`1.192069x`, raw
  keep). Conclusion: do not keep the branchy duplicated host scan shape; the
  apparent gain is not reproducible enough to justify larger code surface.
- Kept integrated affine-scan target lookup without materializing unused DP
  distances. The target-lookup path only needs affine `x256 + y_parity` DP
  keys; the previous call also asked `CpuXyzzBatchAffineDpScan` to append
  matching DP distances, but those distances were never consumed by the exact
  tag32 lookup or checksum oracle. A source gate now prevents this regression by
  requiring the integrated target lookup to request only `dp_keys`. `make
  macos-check` and a smoke run preserved exactness. Paired confirmation on
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_distinct_misses1024`
  against `HEAD` kept twice while scoring `lookups_per_sec`: confirmation 1
  measured `67,643,945.591011` versus baseline `61,035,360.390512`
  (`1.108275x`), and confirmation 2 measured `61,105,278.350280` versus
  `42,658,539.548974` (`1.432428x`). Both confirmations preserved
  `correctness=true`, `dp_count=1057`, `dp_checksum=0x9dba4a07ebbb8e14`,
  `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `target_lookup_checksum=0x8b2568562837af7f`, `hit_count=64`,
  `miss_count=1082304`, and full-key exact verification.
- Rejected a follow-up `CpuXyzzBatchAffineDpScan` DP-output reserve estimate.
  The prototype reserved DP key/distance output capacity from
  `active_count / 2^dp_bits` plus a small floor before the reverse affine scan,
  aiming to reduce `push_back` reallocations for the integrated target-lookup
  path. Correctness and full-key exact verification stayed intact
  (`dp_count=1057`, `dp_checksum=0x9dba4a07ebbb8e14`,
  `target_lookup_checksum=0x8b2568562837af7f`, `hit_count=64`), but paired
  confirmation against commit `46f7054` discarded it: confirmation 1 regressed
  to `39,470,130.649849` versus baseline `62,278,431.485371` (`0.633769x`),
  while confirmation 2 was only a raw keep at `50,170,407.826926` versus
  `31,241,567.175757` (`1.605886x`). Conclusion: keep the simpler no-reserve
  DP-output path; the allocation change is not a reproducible win on this
  thermally noisy target-lookup gate.
- Kept formula-based expected-index validation for integrated affine-scan target
  lookup. The previous integrated gate materialized `lookup_expected_indices`
  for every repeated query even though the expected target index is
  deterministic: in `distinct_misses`, only the first DP batch can contain the
  injected hits; in repeat mode, it is `query_index % dp_query_count` for the
  injected prefix and empty otherwise. The new `ValidateAffineTargetLookupOutputs`
  computes this oracle on the fly and preserves the same checksum mixer, full
  `x256 + y_parity` exactness, hit counts, and query-count guard. Smoke tests
  covered both `distinct_misses` and `repeat`. Paired confirmation on
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_distinct_misses1024`
  against `HEAD` kept twice while scoring `lookups_per_sec`: confirmation 1
  measured `44,495,886.454849` versus baseline `33,843,081.152192`
  (`1.314771x`), and confirmation 2 measured `51,322,297.101063` versus
  `28,022,533.434118` (`1.831465x`). Both confirmations preserved
  `correctness=true`, `dp_count=1057`, `dp_checksum=0x9dba4a07ebbb8e14`,
  `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `target_lookup_checksum=0x8b2568562837af7f`, `hit_count=64`,
  `miss_count=1082304`, and full-key exact verification.
- Kept single-pass measured exact-output fill for integrated GPU-filter lookup
  engines. The `gpu_filter` and `gpu_filter16_hash` branches previously called
  `ResolveTargetLookupTag32FilterCandidates` once without filling outputs and
  then a second time to fill `out_indices` for the checksum oracle; the second
  pass was outside the measured `lookup_exact_seconds`. The new path resolves
  positives once with output fill enabled, so exact CPU verification and
  checksum output generation are part of the same measured pass. Source gates
  prevent reintroducing `fill_reason` or an unmeasured `resolve(..., false)`
  pass in the integrated target-lookup body. Small smokes covered both
  `gpu-filter` and `gpu-filter16-hash`, preserving
  `target_lookup_checksum=0x1689e4cefc1763b8`, `hit_count=8`, and
  `miss_count=48`. The large paired gate
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_parallel_hash_repeat2048`
  against `HEAD` kept across both confirmations while scoring
  `lookups_per_sec`: confirmation 1 measured `71,075,351.161621` versus
  baseline `47,898,394.694751` (`1.483878x`), and confirmation 2 measured
  `92,529,528.533838` versus `65,946,694.802480` (`1.403096x`). Both
  confirmations preserved `correctness=true`, `dp_count=1057`,
  `dp_checksum=0x9dba4a07ebbb8e14`,
  `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `target_lookup_checksum=0x90b9fdeac531859a`, `hit_count=64`,
  `miss_count=2164672`, `filter_positive_count=508`, and
  `filter_false_positive_count=444`.
- Rejected narrow `--lookup-engine auto` promotion of the 25M-target
  repeat2048 corridor to `gpu_filter16_hash`. The policy was deliberately
  scoped to `target_count >= 16,777,216` and
  `2,097,152 <= query_count <= 4,194,304`, so it would catch the accepted
  explicit repeat2048 shape while leaving smaller batches and the previously
  rejected repeat4096 shape alone. The red source gate, policy branch, and
  temporary autoresearch experiment were reverted after the confirmation gate
  discarded the candidate: confirmation 1 measured candidate
  `67,074,784.442296` versus baseline `73,749,600.661159` (`0.909494x`),
  and confirmation 2 measured `63,533,516.652801` versus
  `54,927,320.816796` (`1.156683x`; raw keep but confirmation discard).
  Both confirmations preserved `correctness=true`, `dp_count=1057`,
  `dp_checksum=0x9dba4a07ebbb8e14`,
  `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `target_lookup_checksum=0x90b9fdeac531859a`, `hit_count=64`,
  `miss_count=2164672`, `filter_positive_count=508`, and
  `filter_false_positive_count=444`. Conclusion: keep the explicit
  `gpu-filter16-hash` path for proven large batches, but do not route `auto`
  there until the end-to-end policy beats CPU under paired confirmation rather
  than only under lookup-focused or favorable samples.
- Rejected x-first exact target-key equality ordering in the Metal target
  lookup helper. The candidate compared `x[0..3]` before `parity`, based on the
  hypothesis that after a tag32 hit the x limbs are the more discriminating
  fields and begin at offset zero. The red source gate and kernel change were
  reverted after the paired gate failed. Smoke checks preserved exactness
  (`target_lookup_tag32_exact256` small case: `hit_count=32`, `miss_count=224`,
  `target_lookup_checksum=0xe5b07eeeadaf6670`; integrated small case:
  `hit_count=8`, `miss_count=48`,
  `target_lookup_checksum=0x1689e4cefc1763b8`). The real integrated gate
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_distinct_misses1024`
  against `HEAD` discarded both confirmations while preserving
  `correctness=true`, `dp_count=1057`, `dp_checksum=0x9dba4a07ebbb8e14`,
  `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `target_lookup_checksum=0x8b2568562837af7f`, `hit_count=64`, and
  `miss_count=1082304`: confirmation 1 measured `142,566,912.539515` versus
  baseline `194,717,221.721902` (`0.732174x`), and confirmation 2 measured
  `112,839,230.097606` versus `139,371,914.209570` (`0.809627x`). Conclusion:
  keep the current parity-first equality order for Apple M3 Metal tag32 lookup.
- Rejected a `gpu-filter32-hash` target-lookup engine for the 25M-target
  repeat2048 gate. The candidate reused the prehashed query stream from the
  accepted tag16 hash-filter path, but stored full 32-bit filter tags in the
  open-addressed filter table. It achieved the intended correctness shape:
  both confirmations preserved `correctness=true`, `dp_count=1057`,
  `dp_checksum=0x9dba4a07ebbb8e14`,
  `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `target_lookup_checksum=0x90b9fdeac531859a`, `hit_count=64`,
  `miss_count=2164672`, `filter_positive_count=64`, and
  `filter_false_positive_count=0`. It still lost to the accepted tag16
  hash-filter baseline: confirmation 1 measured `32,732,057.537667` versus
  `40,842,245.276745` (`0.801426x`), and confirmation 2 measured
  `17,326,534.079118` versus `50,197,164.421003` (`0.345170x`). Conclusion:
  eliminating 444 tag16 false positives is not enough to pay for the doubled
  filter table (`134,217,728` bytes, `5.367636` bytes/target); future lookup
  work should reduce traffic/residency cost or reuse device-resident state,
  rather than widening the filter tag alone.
- Promoted host-side derivation of tag32/tag16 filter tables from the
  already-built exact tag32 bucket table. The old path rebuilt each filter by
  rehashing every `x256+y_parity` target and replaying the same open-address
  probe sequence; the new path copies the exact table's slot geometry, stores
  `bucket.tag | 1` for tag32, and stores `(bucket.tag >> 16) | 1` for tag16.
  This changes setup only: Metal still receives the same filter bytes, and CPU
  exact verification of compact positives is unchanged. A dedicated host setup
  benchmark now compares the legacy rehash/probe builders against the derived
  builders in the same process and fails unless both filter tables are
  byte-identical. On the 25,005,000-target gate it preserved
  `tag32_byte_equal=true`, `tag16_byte_equal=true`,
  `tag32_filter_checksum=0x42b1584566f30df0`, and
  `tag16_filter_checksum=0x8ba16d0e4799e611`. Autoresearch kept both
  confirmations with `metric=speedup`: confirmation 1 median `15.982389x`
  (`legacy_seconds=4.023798`, `derived_seconds=0.251764`), and confirmation 2
  median `15.456900x` (`legacy_seconds=6.699196`,
  `derived_seconds=0.433411`). The small integrated Metal smoke still preserved
  `target_lookup_checksum=0xf5b847eb31e6644b`, `hit_count=12`,
  `miss_count=3`, `filter_positive_count=12`, and
  `filter_false_positive_count=0`.
- Rejected one-pass `reserve` + `push_back` construction for the derived
  tag32/tag16 filter builders. The idea was to avoid zero-filling the whole
  filter vector before rewriting occupied slots, but paired autoresearch
  against the accepted derived-builder baseline discarded it despite preserving
  byte equality and the same filter checksums. Confirmation 1 measured
  candidate `speedup=13.313918` versus baseline `17.005541`
  (`0.782916x`), and confirmation 2 measured `9.860456` versus `12.887176`
  (`0.765137x`). Conclusion: keep the simpler `assign` + indexed-write
  derived builders; Apple libc++/allocator behavior and contiguous indexed
  stores beat the attempted one-pass push path under noisy 25M-target setup
  runs.
- Kept parallel bucket scans for the derived tag32/tag16 filter builders. The
  change keeps the accepted `assign` + indexed-write table layout, but splits
  the already-built tag32 bucket table across CPU workers for large 25M-target
  setup runs. It does not change filter semantics: both derived tables are
  still byte-compared against the legacy rehash/probe builders, and every
  measured row preserved `tag32_byte_equal=true`, `tag16_byte_equal=true`,
  `tag32_filter_checksum=0x42b1584566f30df0`, and
  `tag16_filter_checksum=0x8ba16d0e4799e611`. A direct 25,005,000-target
  smoke measured derived build time `0.129628s` versus legacy `2.297284s`
  (`speedup=17.722170`). Paired autoresearch against clean `main` kept both
  confirmations with `metric=speedup`: confirmation 1 measured candidate
  `38.214781` versus baseline `15.140577` (`2.523998x`), and confirmation 2
  measured `32.164942` versus `15.875932` (`2.026019x`). This improves
  multi-target setup throughput for the tag32/tag16 filter path without
  changing GPU lookup kernels or exact target-key verification.
- Kept repeat-mode query-hash reuse for the integrated
  `gpu-filter16-hash` affine-DP target lookup. In `lookup_query_mode=repeat`,
  the benchmark intentionally duplicates the same affine DP key batch
  `lookup_repeat` times; the old path also recomputed `TargetLookupHash` for
  every duplicate query. The new path hashes the base `dp_keys` once, repeats
  the 64-bit hash stream in the same order, and leaves the full
  `lookup_queries` vector in place for exact CPU positive verification and the
  checksum oracle. Other query modes still use the full parallel hash builder.
  A small repeat smoke preserved
  `target_lookup_checksum=0xf5b847eb31e6644b`, `hit_count=12`,
  `miss_count=3`, `filter_positive_count=12`, and
  `filter_false_positive_count=0`; a distinct-misses smoke stayed exact with
  `target_lookup_checksum=0xe2b5e9f9599b0da4`, `hit_count=4`, and
  `miss_count=11`. Paired autoresearch on the 25,005,000-target repeat-mode
  2048 gate kept both confirmations while scoring `lookups_per_sec`:
  confirmation 1 measured `62,891,277.208879` versus baseline
  `54,985,101.284367` (`1.143788x`), and confirmation 2 measured
  `87,016,838.867127` versus `76,126,484.968390` (`1.143056x`). Both
  confirmations preserved `correctness=true`,
  `target_lookup_checksum=0x5b746bd07e35a252`, `hit_count=131072`,
  `miss_count=2033664`, `filter_positive_count=133120`, and
  `filter_false_positive_count=2048`. A separate accidental
  `distinct-misses` control run of the previous repeat2048 gate was discarded;
  that is expected because this helper is not used outside repeat mode.
- Rejected repeat-mode exact-positive cache for integrated
  `gpu-filter16-hash`. The idea was to resolve each positive base DP query once
  and reuse the exact full-key result across repeated query copies, while still
  filling the complete `out_indices` array and preserving the checksum oracle.
  Correctness held in smoke runs and paired autoresearch preserved
  `target_lookup_checksum=0x5b746bd07e35a252`, `hit_count=131072`,
  `miss_count=2033664`, `filter_positive_count=133120`, and
  `filter_false_positive_count=2048`, but confirmation was not stable:
  confirmation 1 regressed to `64,783,036.996344` versus baseline
  `78,322,500.113066` (`0.827132x`), while confirmation 2 improved to
  `100,152,806.017785` versus `57,097,018.715837` (`1.754081x`). The runner
  correctly marked the experiment `confirmation_status=discard`. Conclusion:
  do not add repeat-only exact-resolution caching unless a future gate can
  reduce variance or prove a durable wall-clock benefit.
- Kept explicit repeat-indexed GPU hash input for the 25M-target repeat-mode
  integrated tag16 hash-filter lookup. The accepted engine is deliberately
  named `gpu_filter16_hash_repeat` and is rejected outside
  `lookup_query_mode=repeat`; it is not an `auto` routing change. A first 1D
  kernel variant read `base_query_hashes[id % base_query_count]` and preserved
  `target_lookup_checksum=0x5b746bd07e35a252`, `hit_count=131072`,
  `miss_count=2033664`, `filter_positive_count=133120`, and
  `filter_false_positive_count=2048`, but paired confirmation was mixed:
  confirmation 1 regressed to `84,374,198.785846` lookups/sec versus
  `99,307,597.127335` (`0.849625x`), while confirmation 2 improved to
  `105,466,757.793263` versus `51,790,678.320998` (`2.036404x`). The kept
  version removes that non-power-of-two modulo and dispatches a 2D Metal grid
  over `(base_query, repeat)`, reconstructing the full logical query index for
  exact-output filling. Small repeat smokes preserved
  `target_lookup_checksum=0x10dfe66a4c7bbd2f`, `hit_count=12`, and
  `filter_false_positive_count=0`; the 25,005,000-target scout preserved
  `target_lookup_checksum=0x5b746bd07e35a252`, `hit_count=131072`, and reduced
  `target_query_hash_bytes` from `17,317,888` to `8,456`. Paired autoresearch
  with alternate order and two confirmations kept the 2D candidate: confirmation
  1 measured `102,783,898.346530` versus baseline `72,816,861.692210`
  (`1.411540x`), and confirmation 2 measured `104,205,982.345402` versus
  `52,019,102.782842` (`2.003225x`). Correctness stayed true throughout, with
  exact CPU `x256 + y_parity` verification over compact positives unchanged.
- Rejected exact-positive caching on top of the accepted repeat-indexed engine.
  The cache resolved each positive base DP query once and reused that exact
  tag32 result across repeated logical query slots, preserving full output
  filling and exact checksum validation. It reduced some `lookup_exact_seconds`
  samples, and all paired runs preserved `correctness=true`,
  `target_lookup_checksum=0x5b746bd07e35a252`, `hit_count=131072`,
  `miss_count=2033664`, `filter_positive_count=133120`, and
  `filter_false_positive_count=2048`; however total `lookups_per_sec` did not
  survive confirmation against the accepted repeat-indexed baseline. Confirmation
  1 measured candidate `99,367,810.533474` versus baseline
  `108,781,840.533811` (`0.913460x`), while confirmation 2 measured
  `73,292,478.204763` versus `56,780,394.048385` (`1.290806x`) and was
  recorded as a discarded provisional keep. Conclusion: keep exact verification
  simple until a lookup-timing harness with lower variance proves this cache
  matters to wall-clock throughput.
- Rejected `--lookup-tg-limit 768` for the 25M-target repeat-mode integrated
  tag16 hash-filter lookup. A single sweep looked promising (`tg=768` measured
  `91,586,723.001839` lookups/sec and `202,675,625.803370` GPU-only
  lookups/sec versus a same-sweep `tg=512` at `57,469,278.459948` and
  `154,846,591.975965`), but paired confirmation against the accepted 512 cap
  failed. Confirmation 1 measured candidate GPU-only
  `89,231,127.530542` versus baseline `123,208,709.647144` (`0.724227x`);
  confirmation 2 measured `167,726,637.169006` versus `79,346,311.916685`
  (`2.113855x`). Correctness and
  `target_lookup_checksum=0x5b746bd07e35a252` held throughout, but the
  confirmation policy correctly discarded the knob. Conclusion: keep the
  repeat-mode integrated lookup gate at `--lookup-tg-limit 512`; do not chase
  isolated high `768` samples without a stronger cooled protocol.
- Rejected a compressed repeat-mode GPU filter probe on top of the accepted
  repeat-indexed engine. The idea was to launch the tag16 hash-filter once per
  base DP hash and expand positive base hits across the repeated logical query
  slots, reducing duplicate GPU probes while keeping exact CPU full-key
  verification and the full checksum oracle. Small repeat smokes preserved
  `target_lookup_checksum=0x10dfe66a4c7bbd2f`, `hit_count=12`, and
  `filter_false_positive_count=0`; the 25,005,000-target scout also preserved
  `target_lookup_checksum=0x5b746bd07e35a252`, `hit_count=131072`,
  `miss_count=2033664`, `filter_positive_count=133120`, and
  `filter_false_positive_count=2048`. It was slower than the accepted 2D
  repeat-indexed kernel: direct scout `lookups_per_sec=46,024,265.463599`
  with `lookup_gpu_seconds=0.034567` and
  `lookup_exact_seconds=0.012455`, while same-session accepted-engine scouts at
  `--lookup-tg-limit 512` reached `97,515,207.695785` lookup-only and
  `152,161,793.931497` in the integrated control. Conclusion: do not keep the
  compressed repeat engine; expansion and positive-output traffic are costlier
  than the saved duplicate probes on the M3 gate.
- Rejected lazy logical-index materialization inside
  `target_lookup_tag16_hash_filter_repeat2d256`. The candidate moved
  `query_count = base_query_count * repeat_count` and
  `query_id = repeat_id * base_query_count + base_query_id` from the top of the
  repeat-indexed kernel into the positive tag-match branch, hoping to remove
  multiplications from the miss-heavy path. Correctness held in the small smoke
  and in the 25,005,000-target paired gate:
  `target_lookup_checksum=0x5b746bd07e35a252`, `hit_count=131072`,
  `miss_count=2033664`, `filter_positive_count=133120`, and
  `filter_false_positive_count=2048`. Same-command paired confirmation against
  `main` discarded it: confirmation 1 measured candidate
  `115,218,567.003350` lookups/sec versus baseline
  `155,764,888.801967` (`0.739695x`), while confirmation 2 measured
  `89,733,396.716742` versus `79,942,366.526497` (`1.122476x`) and was
  downgraded by `confirmation_status=discard`. Conclusion: keep the eager
  logical-index arithmetic; the compiler/scheduler and lookup variance erase
  this micro-optimization.
- Rejected removing the exact-grid bounds check from
  `target_lookup_tag16_hash_filter_repeat2d256`. The hypothesis was that
  `dispatchThreads` launches exactly the `(base_query_count, repeat_count)`
  grid, making the in-kernel
  `base_query_id >= base_query_count || repeat_id >= repeat_count` guard
  redundant. A small non-multiple-x smoke preserved correctness, and the
  25,005,000-target paired gate preserved
  `target_lookup_checksum=0x5b746bd07e35a252`, `hit_count=131072`,
  `miss_count=2033664`, `filter_positive_count=133120`, and
  `filter_false_positive_count=2048`. Confirmation still discarded it:
  confirmation 1 measured candidate `48,365,567.273739` lookups/sec versus
  baseline `119,687,116.861217` (`0.404091x`), while confirmation 2 measured
  `102,910,335.958366` versus `70,879,864.899926` (`1.451898x`) and was
  downgraded by `confirmation_status=discard`. Conclusion: keep the explicit
  guard; removing it is not a stable M3 win and weakens the safety shape.
- Kept chunked parallel CPU batch-affine scan for large XYZZ packet outputs.
  The math is still Montgomery batch inversion with one field inversion over
  all `ZZ*ZZZ` products, but large scans now split the product chain into CPU
  worker chunks: each worker builds local prefixes/products, the host batch
  inverts the chunk products once, workers recover per-point `1/(ZZ*ZZZ)` in
  parallel, and a final serial pass preserves the previous reverse-order
  checksum and `dp_keys` order. Small scans keep the old serial path. Smoke
  checks preserved the small repeat target lookup
  `target_lookup_checksum=0xf5b847eb31e6644b`; the large repeat-mode lookup
  preserved `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `dp_checksum=0x9dba4a07ebbb8e14`,
  `target_lookup_checksum=0x5b746bd07e35a252`, `dp_count=1057`, and
  `hit_count=131072`. Paired autoresearch on
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_steps512` kept both
  confirmations while scoring end-to-end `ops_per_sec`: confirmation 1
  measured `123,103,088.658516` versus baseline `119,589,154.173552`
  (`1.029383x`), and confirmation 2 measured `114,555,979.282060` versus
  `103,616,298.999303` (`1.105579x`). Candidate `affine_scan_seconds` medians
  landed around `0.008168s` and `0.010773s`, versus baseline medians around
  `0.019359s` and `0.032114s`.
- Rejected split `ZZ` plus sparse-`ZZZ` affine normalization. The idea was to
  batch-invert `ZZ` for all active packet outputs, test the affine-`x` DP
  predicate, then batch-invert `ZZZ` only for the sparse DP subset to recover
  `y`/parity. This preserved correctness in smoke tests
  (`dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `dp_checksum=0x9dba4a07ebbb8e14`, and the large repeat lookup
  `target_lookup_checksum=0x5b746bd07e35a252`), but paired autoresearch on
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_steps512` discarded it
  against the accepted parallel `ZZ*ZZZ` path. Confirmation 1 looked positive
  (`125,438,897.308717` versus `123,189,340.961610`, `1.018259x`), but
  confirmation 2 reversed under thermal/noise pressure
  (`99,779,103.449835` versus `102,551,705.591218`, `0.972964x`). Conclusion:
  do not keep the split host path; the extra pass and second inversion do not
  beat the current chunked single-inversion design reliably on this M3 gate.
- Kept the affine-scan-only `steps=1024, dp_bits=7` packet cadence. This adds
  a distance-only XYZZ Metal packet kernel for 1024 steps and enables it for
  affine-scan and affine-scan target-lookup benches, while leaving the DP stream
  kernels and defaults at their accepted 256/512 shapes. The comparison uses
  `dp_bits=7` rather than `dp_bits=8` so the packet-boundary DP check cadence
  stays roughly comparable per walked step to the accepted `steps=512,
  dp_bits=8` affine-scan gate. Paired autoresearch on
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_steps1024_dp7` kept both
  confirmations against the 512/dp8 cadence: confirmation 1 measured
  `128,058,444.947777` versus `125,609,000.001448` (`1.019500x`), and
  confirmation 2 measured `127,715,945.975739` versus `124,991,147.125391`
  (`1.021800x`). All candidate rows preserved `correctness=true`,
  `dp_distance_checksum=0x33b34eda684bc0e5`,
  `dp_checksum=0x08b06faea04109e6`, `dp_count=1999`, and the same jump
  histogram bounds for the candidate. A 25,005,000-target repeat1024 smoke with
  `gpu-filter16-hash` also preserved exact lookup
  `target_lookup_checksum=0x4bfc0bfe896fe3ad`, `hit_count=65536`,
  `filter_positive_count=65536`, and `filter_false_positive_count=0`, but
  measured only `102,979,586.897959` end-to-end ops/sec because lookup time
  dominated. Conclusion: keep 1024/dp7 as an explicit affine-scan cadence
  option, not as a blanket target-lookup or solver default.
- Rejected changing the 1024/dp7 affine-scan threadgroup default from `128` to
  `64`. A direct sweep made `tg=64` look plausible, but paired confirmation
  against the accepted default discarded it. Confirmation 1 was already below
  the gate (`99,625,768.379018` versus `124,916,919.058623`, `0.797554x`),
  and confirmation 2 collapsed under thermal pressure (`60,161,520.073026`
  versus `105,542,058.430188`, `0.570024x`). All rows preserved
  `dp_distance_checksum=0x33b34eda684bc0e5`,
  `dp_checksum=0x08b06faea04109e6`, and `dp_count=1999`. Conclusion: keep the
  inherited `128` threadgroup default for the 1024/dp7 affine-scan path; use
  explicit `--tg-limit` only for local diagnostics.
- Rejected changing the 1024/dp7 repeat-mode tag16 hash-filter 25M-target lookup
  cap from `--lookup-tg-limit 512` to `256`. A direct scout showed `256` could
  look faster in isolation, but paired confirmation using `metric=lookups_per_sec`
  was unstable: confirmation 1 barely passed raw scoring (`78,033,668.777845`
  versus `73,736,777.295463`, `1.058273x`), then confirmation 2 failed hard
  (`25,905,527.445064` versus `147,194,749.421910`, `0.175995x`). All rows
  preserved `dp_distance_checksum=0x33b34eda684bc0e5`,
  `dp_checksum=0x08b06faea04109e6`, `dp_count=1999`, and
  `target_lookup_checksum=0x4bfc0bfe896fe3ad`. Conclusion: keep `512` as the
  lookup cap for this large repeat-mode path.
- Rejected splitting the accepted `1024`/`dp_bits=7` affine-scan GPU packet
  into two in-kernel 512-step loop segments. The candidate preserved the same
  state transition, summed the two packet distances, and kept the same CPU
  affine-scan oracle. All paired rows preserved `correctness=true`,
  `dp_distance_checksum=0x33b34eda684bc0e5`,
  `dp_checksum=0x08b06faea04109e6`, `dp_count=1999`, and identical jump
  histograms, but it did not beat the monolithic 1024-step helper reliably.
  Confirmation 1 measured candidate `108,854,143.391471` ops/sec versus
  baseline `114,291,668.491710` (`0.952424x`), while confirmation 2 was only
  a raw keep at `99,513,137.154800` versus `91,527,877.090034`
  (`1.087244x`), so the runner marked the experiment
  `confirmation_status=discard`. Keep the single 1024-step helper call; the
  split loop shape adds scheduling/register-pressure variance instead of a
  durable M3 GPU win.
- Rejected adding a `2048`-step XYZZ affine-scan packet cadence with `dp_bits=6`
  against the accepted `1024`/`dp_bits=7` cadence. The idea preserved roughly
  the same packet-boundary DP density per operation and passed small runtime
  smoke tests, but paired confirmation discarded it: confirmation 1 median was
  `73,816,871.471887` versus baseline `124,567,872.702391` (`0.592584x`), and
  confirmation 2 median was `66,896,871.301844` versus `123,864,112.622089`
  (`0.540083x`). Correctness stayed true with `dp_count=4121`,
  `dp_distance_checksum=0xc92fd9a5364bd81c`, and
  `dp_checksum=0x53bb3a95a8af1270`, but the longer per-thread packet increased
  thermal/register-pressure risk instead of improving throughput. Conclusion:
  keep `1024`/`dp_bits=7` as the longest accepted affine-scan cadence.
- Accepted an autoresearch methodology improvement for thermally sensitive
  Metal experiments: paired benchmark rows now record `paired_order`, and
  experiments may set `paired_order: "alternate"` to run odd samples
  candidate-first. The default remains `baseline_first` so old experiments keep
  their exact behavior, but future close M3 GPU decisions can reduce systematic
  second-run heat bias without changing benchmark commands, correctness
  oracles, or keep/discard thresholds.
- Kept `macos-metal-affine-target-lookup-tag16-repeat-packed-positive`: the
  repeat-mode tag16 hash-filter path now emits packed positive indices as
  `(repeat_id, base_query_id)` when both dimensions fit in 16 bits, then the
  host exact resolver reconstructs the logical query index only after a compact
  positive survives the Metal tag16 filter. This removes resolver-side
  division/modulo over the repeated logical query index while leaving the
  correctness boundary unchanged: every reported hit still requires exact CPU
  `x256 + y_parity` equality against the full target table, and larger shapes
  automatically fall back to the old logical-index output. Runtime JSON reports
  the selected path as `repeat_positive_index_encoding`. The accepted
  25,005,000-target, `lookup_repeat=2048`, `--lookup-query-mode repeat`,
  `--lookup-engine gpu-filter16-hash-repeat`, `--lookup-tg-limit 512` paired
  gate preserved `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `dp_checksum=0x9dba4a07ebbb8e14`,
  `target_lookup_checksum=0x5b746bd07e35a252`, `hit_count=131072`,
  `miss_count=2033664`, `filter_positive_count=133120`,
  `filter_false_positive_count=2048`, `target_query_hash_bytes=8456`, and
  `correctness=true`. Confirmation 1 measured `83,647,823.749505`
  lookups/sec versus paired baseline `41,714,940.175022` (`2.005225x`);
  confirmation 2 measured `185,840,186.793453` versus `70,263,768.598678`
  (`2.644894x`). Treat this as a lookup/resolver efficiency win for
  repeat-mode accumulated multi-target batches, not as a new discrete-log
  algorithm or a per-step kangaroo throughput claim.
- Rejected repeat-mode base-once GPU filtering on top of the accepted packed
  positive path. The candidate exploited the synthetic `repeat` query mode more
  aggressively: it probed the Metal tag16 hash filter only once per base DP
  query, then expanded exact positives across all repeats on the host while
  preserving full `x256 + y_parity` equality, complete output filling, and the
  checksum oracle. It stayed correct with
  `target_lookup_checksum=0x5b746bd07e35a252`, `hit_count=131072`,
  `miss_count=2033664`, `filter_positive_count=133120`,
  `filter_false_positive_count=2048`, and
  `repeat_positive_index_encoding=base_once_logical_expand`, but paired
  confirmation did not keep. Confirmation 1 was a raw keep:
  `79,812,067.404552` lookups/sec versus packed-positive baseline
  `36,303,815.503278` (`2.198448x`). Confirmation 2 rejected it:
  `127,166,925.799653` versus `157,742,708.556192` (`0.806167x`), so the
  runner marked both rows with `confirmation_status=discard`. The code and
  experiment descriptor were reverted. Conclusion: reducing repeated GPU
  probes is a plausible idea, but this base-once host expansion is too noisy on
  the current 25M-target M3 gate to replace the accepted packed 2D repeat path.
- Rejected changing the accepted repeat-indexed tag16 hash-filter threadgroup
  from the current `512 x 1` shape to 2D threadgroup shapes inside the already
  2D `(base_query, repeat)` dispatch. Direct dirty scouts tried `64 x 8`,
  `128 x 4`, and `256 x 2` while preserving the full oracle:
  `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `dp_checksum=0x9dba4a07ebbb8e14`,
  `target_lookup_checksum=0x5b746bd07e35a252`, `hit_count=131072`,
  `filter_positive_count=133120`, `filter_false_positive_count=2048`, and
  `correctness=true`. All three variants were slower on the 25M-target
  repeat2048 gate; representative `lookups_per_sec` values were about
  `126.7M`, `92.4M`, and `49.7M`, below the accepted packed-positive corridor.
  Keep the 1D threadgroup shape for this repeat-indexed kernel.
- Rejected a targeted Metal library/pipeline cache scout for the integrated
  XYZZ distance walk plus repeat-indexed tag16 hash-filter helpers. The idea
  was to reduce real wall-clock setup that is mostly outside JSON
  `dispatch_seconds`; correctness stayed intact on small and 25M target smokes
  with the same DP and target-lookup checksums. The direct 25M scout did not
  improve observed real time or lookup timing, and added global Objective-C
  object lifetime complexity, so the code was reverted. Revisit only with a
  setup-inclusive benchmark that isolates library compile, pipeline creation,
  buffer allocation, validation, and dispatch time separately.
- Rejected `macos-metal-xyzz-finite-wrapper-split`: split the Metal XYZZ
  mixed-add helper into a finite-input hot helper plus the existing
  infinity-aware wrapper, then routed the DP8 `steps256`/`steps512`, chain, and
  affine-scan distance loops through the finite helper whenever the current
  accumulator was not infinity. Correctness and checksums were preserved on
  small smokes and on the paired `262144 x 512` affine-scan gate:
  `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `dp_checksum=0x9dba4a07ebbb8e14`, and `dp_count=1057`. Confirmation 1
  measured candidate `86,880,043.232946` ops/sec versus baseline
  `86,441,247.177342` (`1.005076x`), below the 1% keep threshold.
  Confirmation 2 measured `87,343,594.418012` versus `86,177,005.971957`
  (`1.013537x`), but the two-run policy marked the result
  `confirmation_status=discard`. The code was reverted. Conclusion: pulling
  the infinity wrapper out of the normal XYZZ loop is mathematically safe but
  not a stable M3 speedup; future kernel work should remove arithmetic,
  memory traffic, or CPU replay rather than reshuffle this branch.
- Kept `target_lookup_tag32_build_from_keys`: the host builder for injected
  multi-target tag32 tables now precomputes target hashes, fills deterministic
  non-injected targets in parallel, and inserts from the prehashed stream while
  retaining the legacy builder as an exact oracle. If a generated filler key
  actually duplicates an injected key, the implementation falls back to the
  legacy path, preserving the old target-key order and table semantics. The new
  CLI gate
  `target-lookup-tag32-build-from-keys-bench --target-count 25005000
  --injected-count 64 --iterations 1` compares legacy versus prehashed tables
  field-for-field and reports matching checksum `0x0875f90b516f7503`.
  Autoresearch kept the candidate across two confirmations:
  confirmation 1 samples measured speedups `1.722704`, `1.674158`, and
  `2.202740`; confirmation 2 measured `1.815670`, `1.410222`, and `1.435882`,
  with `table_equal=true` and `correctness=true` throughout. Treat this as a
  25M-target host setup/mapping win for multi-target runs, not as a new
  kangaroo step-throughput claim.
- Kept `target_lookup_tag32_parallel_insert`: after prehashing, the tag32
  target table insertion now uses parallel 64-bit CAS over packed
  `(target_index, tag32)` buckets. The first accepted version unpacked a
  temporary packed bucket vector back into the existing host/GPU bucket layout;
  the in-place follow-up below removes that extra pass. This deliberately
  changes the bucket collision order, so the
  oracle is semantic rather than field-for-field: target-key order must match
  the serial builder and every target key must be found at its own index through
  the normal `TargetLookupTag32Find` path. The 25,005,000-target gate with
  `--injected-count 64` kept across two confirmations. Confirmation 1 samples
  measured speedups `0.928064`, `0.880974`, and `1.496382`; confirmation 2
  measured `1.252302`, `2.044074`, and `1.883752`. All samples reported
  `target_keys_equal=true`, `all_keys_found=true`, and `correctness=true`.
  The parallel table checksum varies across runs because successful CAS order
  inside collision clusters is scheduler-dependent; exact lookup semantics and
  downstream target-lookup checksums remain the correctness boundary.
- Kept the in-place tag32 parallel insert follow-up: `TargetLookupTag32BucketHost`
  is now 8-byte aligned with offset assertions for `{tag, target_index}`, so
  the 8-byte CAS writes directly into the final bucket vector and skips the
  temporary packed-vector unpack pass. Small target counts fall back to the
  prehashed serial builder instead of paying parallel CAS overhead. The first
  paired autoresearch run
  exposed a protocol issue: using `speedup = serial_seconds / parallel_seconds`
  as the experiment metric discarded the candidate because serial timing noise
  moved the ratio. The experiment gate now optimizes
  `parallel_targets_per_sec` and alternates paired baseline/candidate order.
  With that corrected gate, paired autoresearch against `main` kept the change
  across two confirmations: median candidate `parallel_targets_per_sec`
  `15828741.937858` versus paired baseline `14350653.726053`
  (`paired_speedup=1.102998`), then `23960212.926636` versus
  `20969760.948071` (`paired_speedup=1.142608`). All samples reported
  `target_keys_equal=true`, `all_keys_found=true`, and `correctness=true`.
  Integrated 25,005,000-target affine-scan lookup confirmations preserved
  `dp_distance_checksum=0xf0dc88ed68b2ff64`,
  `dp_checksum=0x9dba4a07ebbb8e14`,
  `target_lookup_checksum=0x5b746bd07e35a252`, and `correctness=true`, with
  observed `target_build_seconds` dropping from the pre-change accounting
  sample `1.835799` to `0.659700`, `0.890003`, and `0.902095` on follow-up
  runs.
- Rejected a fused target-key generation/hash/final-bucket CAS variant for
  `target_lookup_tag32_parallel_insert`. The candidate removed the
  `target_hashes` staging vector and inserted each generated key directly into
  the final bucket table, but paired autoresearch against `main` discarded it:
  median candidate `parallel_targets_per_sec=25595577.431431` versus paired
  baseline `28562957.937294` (`paired_speedup=0.896111`). Correctness stayed
  true (`target_keys_equal=true`, `all_keys_found=true`), so this was a real
  performance rejection, likely from worse CAS scheduling/cache behavior rather
  than an oracle failure. Keep the staged hash stream plus in-place bucket CAS.
- Kept
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_steps1024_dp7_setup`:
  for the 25M-target repeat-mode tag16 hash-filter integrated gate, the
  explicit `steps=1024, dp_bits=7, lookup_repeat=1024` cadence now has a
  setup-inclusive paired gate against the accepted
  `steps=512, dp_bits=8, lookup_repeat=2048` path. This is a target-lookup
  regime gate, not a universal default. It preserves
  `dp_distance_checksum=0x33b34eda684bc0e5`,
  `dp_checksum=0x08b06faea04109e6`,
  `target_lookup_checksum=0x4bfc0bfe896fe3ad`, `hit_count=65536`,
  `filter_positive_count=65536`, `filter_false_positive_count=0`, and
  `correctness=true`. Paired autoresearch with
  `metric=setup_inclusive_ops_per_sec` kept both confirmations:
  `91131253.131533` versus baseline `60597677.652709`
  (`paired_speedup=1.503874`), then `83374247.889218` versus
  `63081803.186278` (`paired_speedup=1.321685`). Keep it as the promoted
  explicit 25M setup-inclusive gate for accumulated repeat-mode multi-target
  batches.
- Rejected the adjacent
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_steps1024_dp6_repeat512_setup`
  density tradeoff. The candidate kept the same `steps=1024` packet but used
  `dp_bits=6` and `lookup_repeat=512`, producing a similar logical query count
  while doubling base DP density and halving repeat positives. Correctness held
  with `dp_distance_checksum=0xf69a64423518f298`,
  `dp_checksum=0xbc67ab38fa84d2de`,
  `target_lookup_checksum=0x23977ac85d5ac9f0`, `dp_count=4005`,
  `hit_count=32768`, `filter_positive_count=33280`,
  `filter_false_positive_count=512`, and `correctness=true`, but paired
  autoresearch against the accepted `1024/dp7/repeat1024` setup gate discarded
  it: median setup-inclusive throughput was `84162048.224048` versus baseline
  `85400915.406033` (`paired_speedup=0.985494`). Keep `1024/dp7/repeat1024`
  as the 25M setup-inclusive gate; lower DP bits only make sense if a future
  solver-level collision-latency metric justifies the extra DP pressure.
- Rejected a dirty sparse cached repeat-output validation prototype. The idea
  was to avoid materializing the full repeated `out_indices` vector for the
  packed repeat tag16 path, verify each compact positive exactly, cache exact
  finds per base DP query, and compute the same full-query checksum from the
  expected repeat pattern. Small repeat smoke preserved
  `target_lookup_checksum=0xf5b847eb31e6644b`, and the 25M
  `1024/dp7/repeat1024` scout preserved
  `target_lookup_checksum=0x4bfc0bfe896fe3ad`, `hit_count=65536`,
  `filter_positive_count=65536`, `filter_false_positive_count=0`, and
  `correctness=true`. It was much slower in the dirty scout
  (`setup_inclusive_ops_per_sec=24658320.224050`,
  `lookup_exact_seconds=0.019804`), likely because the checksum loop and cache
  bookkeeping did not remove the real bottleneck. The code was reverted; keep
  the full-output validation path until a lower-level checksum design can prove
  an actual win.
- Kept `target_lookup_tag32_parallel_insert_workers6`: on the local Apple
  Silicon track, running the 25M tag32 parallel-insert setup gate with
  `RCK_VALIDATION_WORKERS=6` beat the default worker count in two paired
  confirmations while preserving the semantic table oracle. Candidate command
  is `env RCK_VALIDATION_WORKERS=6 ./macos/rck_macos
  target-lookup-tag32-parallel-insert-bench --target-count 25005000
  --injected-count 64 --iterations 1`. Confirmation 1 measured
  `parallel_targets_per_sec=39543696.391783` versus baseline
  `29517720.814066` (`paired_speedup=1.339660`); confirmation 2 measured
  `26108366.758003` versus `17709310.747145`
  (`paired_speedup=1.474273`). All rows preserved `target_keys_equal=true`,
  `all_keys_found=true`, and `correctness=true`. Treat this as an Apple
  Silicon host setup tuning knob, not as a global default yet; use the explicit
  env var when reproducing M3 Air setup-heavy gates.
- Rejected `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_steps1024_dp7_setup_workers6`:
  the worker-count win above did not transfer to the integrated Metal 25M
  target-lookup gate when the only changed variable was
  `RCK_VALIDATION_WORKERS=6`. The candidate preserved
  `dp_distance_checksum=0x33b34eda684bc0e5`,
  `dp_checksum=0x08b06faea04109e6`,
  `target_lookup_checksum=0x4bfc0bfe896fe3ad`, `hit_count=65536`,
  `filter_positive_count=65536`, `filter_false_positive_count=0`, and
  `correctness=true`, but paired confirmations discarded it. Confirmation 1
  measured `setup_inclusive_ops_per_sec=25890541.312106` versus baseline
  `34477728.502830` (`paired_speedup=0.750935`); confirmation 2 measured
  `74730044.051988` versus `80588312.832022`
  (`paired_speedup=0.927306`). Keep `RCK_VALIDATION_WORKERS=6` as an isolated
  target-table setup recipe only; leave the integrated gate on the default
  worker count until a new end-to-end paired gate proves otherwise.
- Kept `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_steps2048_dp6_setup`:
  added a 2048-step XYZZ distance packet specialization for the affine-scan
  path and used the same cadence rule as the prior keep: double packet length,
  reduce DP bits by one, and keep the repeat-mode target join visible in
  `setup_inclusive_ops_per_sec`. The candidate runs `--iterations 131072
  --steps 2048 --dp-bits 6 --lookup-repeat 1024` against the accepted
  `--iterations 262144 --steps 1024 --dp-bits 7 --lookup-repeat 1024` gate.
  Correctness held in the small smoke and all 25M rows with
  `dp_distance_checksum=0xf31d7766e1607041`,
  `dp_checksum=0x54ccada61fd1edbc`,
  `target_lookup_checksum=0x197ac7fed54a4156`, `dp_count=2087`,
  `query_count=2137088`, `hit_count=65536`,
  `filter_positive_count=65536`, `filter_false_positive_count=0`, and
  `correctness=true`. The first paired keep measured
  `setup_inclusive_ops_per_sec=89036615.161581` versus baseline
  `80299073.391548` (`paired_speedup=1.108812`). Two confirmation rows then
  kept it at `75814186.065546` versus `67936112.806331`
  (`paired_speedup=1.115963`) and `70379199.180135` versus
  `62540628.754942` (`paired_speedup=1.125336`). Promote 2048/dp6 as the new
  local 25M repeat-mode setup-inclusive plateau, but keep the exact affine DP
  key and CPU exact-positive verification gates unchanged.
- Rejected `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_steps4096_dp5_setup`:
  added a 4096-step XYZZ distance packet specialization to test the next
  cadence-preserving point after 2048/dp6. The candidate used `--iterations
  65536 --steps 4096 --dp-bits 5 --lookup-repeat 1024` against the accepted
  `--iterations 131072 --steps 2048 --dp-bits 6 --lookup-repeat 1024`. Small
  smokes and both 25M confirmations preserved
  `dp_distance_checksum=0xb75d72c71a05e4ad`,
  `dp_checksum=0x1277ccb107e05a36`,
  `target_lookup_checksum=0x7714f2accdb9fd49`, `dp_count=2112`,
  `query_count=2162688`, `hit_count=65536`,
  `filter_positive_count=65536`, `filter_false_positive_count=0`, and
  `correctness=true`. Confirmation 1 discarded it at
  `setup_inclusive_ops_per_sec=75314077.842822` versus baseline
  `78564303.900017` (`paired_speedup=0.958630`). Confirmation 2 was a narrow
  keep at `64790787.951621` versus `63073497.832969`
  (`paired_speedup=1.027227`), but confirmation policy requires every run to
  keep, so the overall result is discard. Keep 4096/dp5 as a reproducible
  boundary probe only; 2048/dp6 remains the promoted local plateau.

## Next Research Targets

- Move from isolated field kernels toward Jacobian point kernels on Metal.
- Build on the accepted XYZZ chain probe: use runtime `dp_bits` to tune solver
  table pressure versus collision latency, reduce cumulative-distance
  overhead, tune packet count versus walker count, and explore affine
  recovery/collision verification from `X,Y,ZZ,ZZZ` without reintroducing a
  per-step `Z` dependency.
- Treat `dp_tracking=projective_x_limb0` as a throughput probe, not a complete
  solver collision-table key. The projective `X` limb is not invariant under
  equivalent Jacobian/XYZZ scalings, so a production DP table needs either an
  affine DP predicate/key, an invariant homogeneous predicate, or a batched
  normalization design that amortizes inversions at packet boundaries without
  discarding the accepted XYZZ arithmetic plateau.
- Extend the accepted affine-scan gate toward a device-side batch-normalization
  design: keep GPU packet distances resident, avoid CPU replay, and compare
  `gpu_ops_per_sec` versus end-to-end `ops_per_sec` before moving any collision
  table work onto Metal.
- Extend the exact target-lookup gate from synthetic hit/miss probes toward the
  affine DP scan output, preserving exact full-key verification and separating
  `lookups_per_sec` from walk-step throughput.
- Keep CPU tiny-range kangaroo as the correctness oracle while GPU kernels are
  introduced one layer at a time.
- Prefer fused kernels only when paired benchmarks show a real win. The fused
  operation must still expose an oracle and a reproducible benchmark.
- Explore Metal memory layout for point batches before attempting full
  distinguished-point table work on GPU.
- Keep multi-target CPU architecture unchanged unless a candidate beats the
  paired autoresearch gate and preserves full collision verification.
- Broaden the benchmark-gated `--lookup-engine auto` policy only with paired
  data across more target counts, DP density, and `lookup_repeat`; do not make
  CPU the default globally from one hardware class.
- Build on the accepted tag32 filter path: tune positive compaction, measure
  false-positive-heavy synthetic cases, and only consider moving exact
  verification back onto GPU if it beats compact-positive CPU verification
  without losing full-key equality.
- Revisit GPU persistent lookup only as a long-lived solver-level design: keep
  the target table resident across many fresh packet-boundary DP batches, avoid
  rebuilding query/output resources where possible, and score setup-inclusive
  and setup-excluded metrics separately.
- Rejected a dirty repeat-mode exact-resolver cache for
  `gpu-filter16-hash-repeat`. The idea cached each base DP query's exact
  `TargetLookupTag32Find` result, then expanded repeated positives back to the
  same logical output indices. It preserved the exact full-key oracle in all
  scouts: for `steps=2048`, `dp_bits=6`, `target_count=25005000`,
  `lookup_repeat=1024`, the paired dirty run kept
  `dp_distance_checksum=0xf31d7766e1607041`,
  `dp_checksum=0x54ccada61fd1edbc`,
  `target_lookup_checksum=0x197ac7fed54a4156`, `hit_count=65536`, and
  `filter_false_positive_count=0`, but confirmation discarded it on
  `ops_per_sec` (`118709682.938361` then `43137775.235818`). A larger
  `lookup_repeat=4096` scout initially kept `lookups_per_sec`
  (`207220633.884313` vs `175064121.659721`, speedup `1.183684`) with
  `target_lookup_checksum=0xa2cd0ae701083735`, `hit_count=262144`, and
  `filter_false_positive_count=0`; the required two-run confirmation then
  discarded it (`126730884.616311` vs `131362546.004964`, speedup
  `0.964741`). Conclusion: the exact-resolver cache is mathematically safe, but
  it did not produce stable integrated throughput on the local M3, so the code
  patch was not kept. Raw rows remain in `autoresearch/benchmarks.jsonl` and
  `autoresearch/results.tsv` under the dirty experiment names
  `repeat_resolver_cache` and `repeat4096_resolver_cache`.
- Rejected a dirty fused target-builder attempt that generated filler keys and
  atomically inserted tag32 buckets in one pass to avoid the 25M-entry
  `target_hashes` vector. The semantic oracle held (`target_keys_equal=true`,
  `all_keys_found=true`, `correctness=true`), but the decisive 25,005,000-target
  scout slowed the parallel builder from `1.384983` seconds to `1.568174`
  seconds. Conclusion: the existing prehash-then-parallel-insert path is still
  better on the local M3 for this load factor; the fused code patch was not
  kept.
- Rejected a dirty `steps=1536` XYZZ affine-scan specialization. The wrapper
  was mathematically valid and preserved the CPU oracle in smoke tests
  (`dp_distance_checksum=0x58792af1132a1b59`,
  `target_lookup_checksum=0xdba3b6a52770ca15` on the small target lookup), but
  same-operation walk scouts were mixed: `1536` first measured
  `127796822.007213` ops/sec versus `2048` at `126371371.617911`, then fell to
  `126252505.609474` versus `126545796.756480`. The integrated 25M scout was
  worse than the 2048 plateau even with roughly matched query volume:
  `steps=1536`, `dp_bits=6`, `lookup_repeat=768`, `hits=85` measured
  `72798970.094865` setup-inclusive ops/sec with `filter_false_positive_count=768`,
  while the immediate `steps=2048`, `lookup_repeat=1024`, `hits=64` baseline
  measured `86083133.409830` with zero false positives. Conclusion: do not add
  a 1536-step wrapper unless a future gate finds a stronger cadence.
- Kept `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_scaled4_j4_setup`:
  the 25,005,000-target, `steps=2048`, `dp_bits=6`, repeat-mode
  `gpu-filter16-hash-repeat` gate now has a paired schedule probe comparing
  `--jumps 4 --jump-schedule scaled4-balanced` against the accepted 16-jump
  `power2` baseline. Correctness stayed exact in both confirmations:
  `dp_distance_checksum=0xad580a14bfda5cf8`,
  `dp_checksum=0x58d7138663a105aa`,
  `target_lookup_checksum=0x52efac244f7b11f3`, `hit_count=65536`,
  `filter_false_positive_count=0`, and `jump_histogram_max_deviation_ppm=68`
  for the candidate. Paired confirmation kept the candidate on
  `setup_inclusive_ops_per_sec`: confirmation 1 median `93508028.064667`
  versus baseline `59826653.984800`; confirmation 2 median `57402367.574511`
  versus baseline `46863993.301787` (final paired speedup `1.224871`,
  `confirmation_status=keep`). Conclusion: promote this as a local
  reproducible schedule gate, but do not make it a universal default until
  other Apple Silicon machines confirm the same behavior.
- Rejected the follow-up 4-jump schedule-isolation gate comparing
  `--jumps 4 --jump-schedule scaled4-balanced` against
  `--jumps 4 --jump-schedule power2` on the same 25,005,000-target,
  `steps=2048`, `dp_bits=6`, repeat-mode `gpu-filter16-hash-repeat` command.
  Correctness stayed exact for `scaled4-balanced`
  (`dp_distance_checksum=0xad580a14bfda5cf8`,
  `dp_checksum=0x58d7138663a105aa`,
  `target_lookup_checksum=0x52efac244f7b11f3`, `hit_count=65536`,
  `filter_false_positive_count=0`, `jump_histogram_max_deviation_ppm=68`), but
  the paired confirmation discarded it on `setup_inclusive_ops_per_sec`.
  Confirmation 1 was only a marginal raw keep before the two-run policy
  (`89145487.327852` versus `87022562.367405`, speedup `1.024395`), and
  confirmation 2 was a clear discard (`55752350.612289` versus
  `75648578.254959`, speedup `0.736991`; final
  `confirmation_status=discard`). Conclusion: the accepted local win is more
  likely from reducing the jump table from 16 entries to 4 than from a stable
  standalone advantage of the `{1, 2, 8192, 8193}` distance schedule. Keep the
  4-jump idea alive, but do not claim the scaled4 distance distribution itself
  is a reproducible breakthrough.
- Rejected a second 4-jump isolation gate comparing `--jumps 4
  --jump-schedule power2` against the accepted `--jumps 16
  --jump-schedule power2` baseline on the same 25,005,000-target,
  `steps=2048`, `dp_bits=6`, repeat-mode `gpu-filter16-hash-repeat` command.
  Correctness stayed exact for the 4-jump power2 candidate
  (`dp_distance_checksum=0x271ee73d4839b420`,
  `dp_checksum=0x444def74a8413f00`,
  `target_lookup_checksum=0x7b006ccd0f00dc3b`, `hit_count=65536`,
  `filter_false_positive_count=1024`, `jump_histogram_max_deviation_ppm=116`),
  but both confirmations discarded it on `setup_inclusive_ops_per_sec`:
  `63460011.180716` versus `72944791.530690` (speedup `0.869973`), then
  `44460373.620674` versus `47576894.508189` (speedup `0.934495`; final
  `confirmation_status=discard`). Conclusion: the accepted `scaled4_j4` gate is
  not explained by jump-table size alone. Future 4-jump work should test
  distance schedules as first-class candidates and must track DP density,
  false positives, and setup-inclusive timing together.
- Rejected a dirty `scaled8-balanced` Metal-only schedule with distances
  `{1, 2, 4, 8, 8192, 8193, 8194, 8196}`. The intent was to preserve roughly
  the 16-jump `power2` mean jump distance while halving the jump table and
  giving more index entropy than `scaled4-balanced`. A small smoke confirmed
  the Metal path was correct and that `scaled8-balanced` was rejected unless
  `--jumps 8`; the CPU tiny-range kangaroo solver path was intentionally not
  kept because those large jumps are inappropriate for its small oracle ranges.
  The 25,005,000-target paired gate stayed semantically correct for the
  candidate (`dp_distance_checksum=0x616e355d19541c00`,
  `dp_checksum=0x2b7aeff167cc0692`,
  `target_lookup_checksum=0x356d2bd0a459b4a1`, `hit_count=65536`,
  `filter_false_positive_count=0`, `jump_histogram_max_deviation_ppm=356`),
  but the two-run confirmation discarded it: confirmation 1 lost
  (`83880983.784617` versus `90987263.956026`, speedup `0.921898`), while
  confirmation 2 won (`41081001.458294` versus `36418203.819580`, speedup
  `1.128035`; final `confirmation_status=discard`). Conclusion: the
  average-preserving 8-jump idea is mathematically plausible but too noisy to
  keep. Do not expose `scaled8-balanced` without a stronger setup-stable gate.
- Ran direct hardware/parameter scouts on the accepted `scaled4_j4` command
  without promoting any new experiment. Walk `--tg-limit 256` preserved
  correctness but was slower than `128` (`gpu_ops_per_sec=115346559.848742`
  versus `123958184.280779`, setup-inclusive `87738450.303711` versus
  `89022237.700288`). Smaller/nonstandard walk groups were also worse:
  `--tg-limit 64` reached setup-inclusive `80677722.372601`, and
  `--tg-limit 96` reached `76093263.819737`. Lookup threadgroup changes did
  not produce an integrated win: `--lookup-tg-limit 256` reached
  setup-inclusive `86703397.380656`, while `1024` improved lookup-only rates
  but collapsed total walk throughput (setup-inclusive `40579960.698937`).
  Doubling the batch to `--iterations 262144` slightly beat a throttled
  immediate 131k setup-inclusive scout (`58289789.201938` versus
  `57243594.194233`) but lowered `gpu_ops_per_sec` and introduced
  `filter_false_positive_count=1024`, so it was not promoted. CPU/auto exact
  lookup on the same profile preserved the checksum
  (`target_lookup_checksum=0x52efac244f7b11f3`) but was slower than
  `gpu-filter16-hash-repeat`: `cpu` setup-inclusive `54653921.809506`, `auto`
  setup-inclusive `67531812.211342`, versus the immediate GPU-filter scout at
  `74366891.303314`. Conclusion: keep the accepted walk group 128,
  lookup group 512, 131k-sample, GPU-filter repeat profile as the local base.
- Rejected a `min_ms=5000` steady-state follow-up on the accepted `scaled4_j4`
  command. A direct scout looked attractive because the command reused the
  target table/filter across repeated dispatches and measured
  `setup_inclusive_ops_per_sec=113355099.742690` with
  `target_lookup_checksum=0x52efac244f7b11f3` and zero false positives, versus
  an immediate cold `min_ms=500` scout at `82833667.486211`. The paired gate
  against the same `min_ms=5000` 16-jump power2 baseline did not confirm:
  confirmation 1 was a raw keep (`103992785.327127` versus `45963566.197120`,
  speedup `2.262505`), while confirmation 2 discarded it (`56480003.605877`
  versus `64994848.031781`, speedup `0.868992`; final
  `confirmation_status=discard`). The candidate remained semantically exact
  (`dp_distance_checksum=0xad580a14bfda5cf8`,
  `dp_checksum=0x58d7138663a105aa`,
  `target_lookup_checksum=0x52efac244f7b11f3`, `hit_count=65536`,
  `filter_false_positive_count=0`). Conclusion: target-table amortization is a
  real direction, but the existing `min_ms` loop is too noisy and repeats the
  same batch; do not promote it. A fair next benchmark needs fixed explicit
  rounds with distinct walk batches and one reused target table.
- Added a dirty fixed-round target lookup benchmark prototype to remove that
  `min_ms` ambiguity: `metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench`
  runs deterministic distinct walk batches, injects hits from every round,
  builds one target table/filter, and validates each round with exact target
  offsets. A small smoke was correct (`round_count=2`, `hit_count=16`,
  `target_lookup_checksum=0x2648544e2748f45e`) and rejected schedule mismatch
  as expected. The decisive 25,005,000-target, two-round manual paired scout
  did not support a speed claim: the `scaled4_j4` candidate remained exact
  (`dp_distance_checksum=0x4b7a8e04a1b34c9e`,
  `dp_checksum=0x23ddf9863ade346f`,
  `target_lookup_checksum=0x9d6f1e5663211884`, `hit_count=131072`) but had
  median `ops_per_sec=68007451.764749` versus the 16-jump power2 baseline at
  `87996887.228211` (manual paired speedup `0.772839`). It also carried
  `filter_false_positive_count=1024` versus baseline zero. Conclusion: distinct
  rounds are the right anti-cheat benchmark shape, but `scaled4_j4` is not a
  steady-compute win under this stricter two-round oracle.
- Reworked the fixed-round target lookup probe to concatenate all round DP
  keys and launch one aggregate `gpu_filter16_hash_repeat` lookup dispatch
  against the shared target table/filter, with a per-query expected target-index
  vector preserving exact round offsets. The small two-round oracle remained
  exact (`hit_count=9`, `filter_false_positive_count=0`,
  `target_lookup_checksum=0x4d668f8d29797461`). A 25,005,000-target three-pair
  scout still did not promote `scaled4_j4`: aggregate 16-jump power2 baseline
  median `ops_per_sec=87877738.630874`, setup-inclusive median
  `69269242.521751`, `target_lookup_checksum=0x923b46f156f9d59b`, zero false
  positives; aggregate `scaled4_j4` median `ops_per_sec=76438848.057118`,
  setup-inclusive median `54043838.855151`,
  `target_lookup_checksum=0x6aaec4659e60b735`, and
  `filter_false_positive_count=1024`. Conclusion: keep the aggregate lookup
  architecture because it is the fairer steady-state multi-round shape, but do
  not claim a speedup for `scaled4_j4`.
- Added an explicit `--lookup-filter-bits 16|32` diagnostic to the fixed-round
  target lookup probe. The new `gpu_filter32_hash_repeat` path reuses the same
  base-query hash repeat grid and exact CPU `x256 + y_parity` resolver, but
  stores a 4-byte tag32 filter instead of the default 2-byte tag16 filter. The
  small two-round smoke was exact and matched the tag16 checksum
  (`hit_count=9`, `filter_false_positive_count=0`,
  `target_lookup_checksum=0x4d668f8d29797461`). On the 25,005,000-target
  `scaled4_j4` gate, tag32 removed the tag16 false positives
  (`0` versus `1024`) and preserved the checksum
  (`0x6aaec4659e60b735`), but was slower: tag16 median
  `ops_per_sec=120614034.655459`, setup-inclusive
  `97949282.064089`, `gpu_lookup_lookups_per_sec=167449478.360079`;
  tag32 median `ops_per_sec=117565011.784014`, setup-inclusive
  `92242659.552484`, `gpu_lookup_lookups_per_sec=104405254.787158`.
  Conclusion: keep tag32 as a collision diagnostic and do not promote it as the
  default; the 1024 tag16 false positives are too cheap compared with doubling
  filter bandwidth. A fresh 25,005,000-target two-pair schedule check again
  rejected `scaled4_j4` versus `power2_j16`: power2 median
  `ops_per_sec=105210079.585389`, setup-inclusive `85064945.004492`, checksum
  `0x923b46f156f9d59b`, zero false positives; scaled4 median
  `ops_per_sec=88225563.491974`, setup-inclusive `71299666.505170`, checksum
  `0x6aaec4659e60b735`, and `1024` false positives. A lookup-threadgroup scout
  was also mixed: `--lookup-tg-limit 256` improved isolated lookup seconds in
  some runs, but did not beat `512` on total/setup-inclusive throughput, so the
  default remains unchanged.
- Added an explicit `--lookup-filter-mode tag16|tag16-mix|tag32` diagnostic.
  The `tag16-mix` mode keeps the same 2-byte-per-bucket memory footprint as the
  default tag16 filter, but uses `low16(tag32 ^ (tag32 >> 16)) | 1` instead of
  only the top 16 hash bits. It is still only a prefilter: every positive is
  resolved by the existing exact CPU `x256 + y_parity` equality. Small smoke
  remained exact (`hit_count=9`, `filter_false_positive_count=0`,
  `target_lookup_checksum=0x4d668f8d29797461`). On the 25,005,000-target
  `scaled4_j4` gate, tag16-mix preserved the checksum
  (`0x6aaec4659e60b735`) and removed the default tag16 false positives
  (`0` versus `1024`) with the same 67,108,864-byte filter. The paired scout
  showed better lookup-only medians for tag16-mix
  (`lookup_seconds=0.0435815`, `gpu_lookup_lookups_per_sec=176542772.553031`)
  than tag16 (`lookup_seconds=0.0666645`,
  `gpu_lookup_lookups_per_sec=110574403.365121`), while total throughput stayed
  noisy (`ops_per_sec` median `59781157.750603` versus `57968854.063746`, but
  setup-inclusive median `45869560.032271` versus `49352291.469171`). A
  power2/j16 guardrail run was exact with zero false positives and the same
  checksum (`0x923b46f156f9d59b`), with better lookup-only numbers
  (`lookup_seconds=0.024841` versus `0.034691`). Conclusion: keep tag16-mix as
  a promising same-memory lookup mode, but do not change the default until a
  lower-noise confirmation shows end-to-end improvement, not only lookup-stage
  improvement.
- Added explicit `--lookup-repeat-mode full|dedup` for the fixed-round
  aggregate target-lookup benchmark. The default remains full repeat. The new
  `dedup` mode filters each base DP hash once, resolves exact positives with
  the same CPU `x256 + y_parity` equality, expands outputs back to the full
  logical repeat shape, and records `physical_query_count` plus
  `physical_filter_positive_count` so lookup rates cannot silently count
  synthetic repeated queries as physical work. The small two-round smoke stayed
  exact with unchanged checksum (`target_lookup_checksum=0x4d668f8d29797461`,
  `query_count=9`, `physical_query_count=3`, `hit_count=9`).
- Scout results: on the 1,048,576-target two-round shape
  (`steps=1024, dp_bits=6, lookup_repeat=256`), repeat and dedup both preserved
  `target_lookup_checksum=0x5eca43d3bfad103c`, with dedup reporting
  `query_count=269568`, `physical_query_count=1053`, and
  `physical_filter_positive_count=32`. Timing was noisy, but the exact-output
  expansion fix reduced dedup `lookup_exact_seconds` to about `0.000037`.
  On the 25,005,000-target fixed-round power2 shape
  (`steps=2048, dp_bits=6, lookup_repeat=1024`), repeat and dedup both
  preserved `target_lookup_checksum=0x923b46f156f9d59b` and zero false
  positives. Avoiding full logical output materialization and validating the
  repeated checksum from the base output reduced dedup lookup time to
  `0.007150` seconds (`lookup_exact_seconds=0.000083`,
  `physical_query_count=4121`, `physical_filter_positive_count=128`) versus
  full repeat at `0.045586` seconds in a later same-session guardrail run.
  Earlier full-repeat and dedup scouts in the same session were `0.029466` and
  `0.013328` seconds respectively before the no-materialization validator.
  Conclusion: keep dedup as a non-default repeated-query upper-bound diagnostic
  and a future optimization target, not as a distinct-query throughput claim.
- Added conservative `auto` routing for large M3 repeat-mode target joins. The
  previous `auto` policy could choose the host CPU whenever a large target table
  produced only a small DP query batch, even if the logical repeat expansion was
  large enough for the repeat-indexed Metal hash filter to win. A direct local
  M3 scout on `iterations=8192`, `steps=512`, `dp_bits=6`,
  `target_count=16777216`, `lookup_repeat=8192`,
  `lookup_query_mode=repeat` preserved the exact same
  `target_lookup_checksum=0xb87fc40ba6652a4f`, `dp_count=125`, and
  `hit_count=131072`. It was a lookup-stage win (`cpu lookup_seconds=0.009043`,
  `gpu-filter16-hash-repeat lookup_seconds=0.005014`), but paired
  end-to-end `ops_per_sec` later discarded the 1.024M-logical-query threshold
  once target-filter setup was counted. A 4.096M-logical-query scout also kept
  the checksum (`0x5103c731ae1429a0`) and improved lookup time
  (`0.038443` CPU versus `0.017617` GPU), but still missed end-to-end. At
  16.384M logical queries (`lookup_repeat=131072`), the same checksum oracle
  passed (`0x86ec0110960785f8`, `hit_count=2097152`) and the repeat-indexed
  Metal path beat CPU with setup included: CPU measured
  `ops_per_sec=16581135`, `setup_inclusive_ops_per_sec=6772869`, and
  `lookup_seconds=0.197659`; GPU measured `ops_per_sec=38197808`,
  `setup_inclusive_ops_per_sec=10084276`, and `lookup_seconds=0.036280`.
  Therefore the new route only promotes `auto` to `gpu_filter16_hash_repeat`
  for repeat-mode joins with `lookup_repeat > 1`, target count at least the
  large-target threshold, and at least 16,000,000 logical repeated queries. This
  changes default routing only where the M3 profile paid for the GPU filter
  setup without changing the exact hit/miss oracle, checksum, or explicit
  CPU/GPU engine controls. The final paired autoresearch check against
  `HEAD=e01d29c` kept the updated `auto` route on the 16.384M-query gate:
  candidate median `ops_per_sec=45756095.881506`, paired CPU baseline
  `20155261.342318`, `paired_speedup=2.270181`, and
  `target_lookup_checksum=0x86ec0110960785f8`.
- Tested a wider packed repeat-positive encoding for the same M3 auto-repeat
  shape. A generic dynamic shift and then a fixed 8-bit base shift both
  preserved `target_lookup_checksum=0x86ec0110960785f8`, but neither improved
  the full path; the extra kernel shape made the GPU side slower enough to
  offset the resolver savings. Rejected that direction.
- Promoted sparse exact resolution for the repeat-indexed integrated lookup.
  The old path filled a full logical `out_indices` vector, including repeated
  misses that a real kangaroo join does not need. The new path resolves only
  compact filter positives with exact CPU `x256 + y_parity` equality, rejects
  any exact hit outside the injected target prefix, and then computes the same
  repeat checksum oracle without materializing all misses. Manual M3 smoke on
  the 16.384M-query auto-repeat gate kept `target_lookup_checksum=0x86ec0110960785f8`
  and zero false positives; `lookup_exact_seconds` dropped to about `0.014568`
  in one run. A same-command paired autoresearch check against `HEAD=25a76bc`
  kept the candidate: median `ops_per_sec=52838131.057009`, paired baseline
  `40899473.572020`, `paired_speedup=1.291902`, same checksum
  `0x86ec0110960785f8`.
- Added an exact-result cache inside the sparse repeat resolver for the local
  M3 large-repeat gate. Earlier full-output repeat caches were rejected because
  they did not survive noisy paired confirmation. This version applies only
  after repeated miss materialization has already been removed: each compact
  positive decodes its base DP query, the resolver calls `TargetLookupTag32Find`
  once per repeated base query, and every logical repeat still increments the
  exact hit or false-positive counter. The single-smoke gate kept
  `target_lookup_checksum=0x86ec0110960785f8`, `hit_count=2097152`, and zero
  false positives while reducing `lookup_exact_seconds` from about `0.029274`
  to `0.007722`. Two paired autoresearch confirmations against `HEAD=95ac546`
  both kept the candidate; the final median was
  `ops_per_sec=65898116.327166` versus paired baseline
  `53650264.971400`, `paired_speedup=1.228291`, with the same checksum.
- Promoted base-index positive encoding for the integrated sparse repeat
  resolver when the 16-bit packed positive encoding is unavailable. The Metal
  grid still runs every logical `(base_query, repeat)` probe and still emits
  one compact positive per logical positive, but the emitted payload is the
  base DP query index instead of the full logical index. The sparse resolver
  already validates against the base DP key and expected repeat checksum, so
  this removes resolver-side logical-index modulo without changing hit/miss
  semantics. A smoke run on the 16.384M-query M3 gate reported
  `repeat_positive_index_encoding=base_query_index_repeated`,
  `target_lookup_checksum=0x86ec0110960785f8`, `hit_count=2097152`, and zero
  false positives. Two paired autoresearch confirmations against `HEAD=e5892e2`
  both kept the candidate. The first kept median was
  `ops_per_sec=53328905.600368` versus paired baseline `46870638.585665`
  (`paired_speedup=1.137789`). The final kept median was
  `ops_per_sec=41034435.022514` versus paired baseline `33622719.474270`
  (`paired_speedup=1.220438`), with the same checksum. This is a real
  integrated-path improvement, not a benchmark shortcut: `query_count`,
  `filter_positive_count`, exact CPU equality, and the repeat checksum oracle
  remain unchanged.
- Promoted fused tag16 target-filter setup for the integrated M3 sparse-repeat
  hash-filter path. The target table builder now optionally fills the 2-byte
  tag16 filter bucket at the same slot where it inserts each tag32 target
  bucket, so the normal tag16 path avoids a separate post-build bucket scan.
  The fused value is exactly `(tag32 >> 16) | 1`, matching the derived filter
  builder; tag32 bucket layout, tag16 bytes, exact CPU `x256 + y_parity`
  equality, logical query count, compact positive count, and checksum oracle
  stay unchanged. If duplicate filler generation falls back to the conservative
  builder, the fused vector stays empty and the old derived-filter builder is
  used. On the JSON surface, `target_filter_build_seconds=0` means the filter
  setup was fused into `target_build_seconds`, not skipped; compare
  `setup_inclusive_ops_per_sec` for honest end-to-end scoring. Smoke on the
  16.384M-query M3 auto-repeat gate reported
  `repeat_positive_index_encoding=base_query_index_repeated`,
  `target_lookup_checksum=0x86ec0110960785f8`, `hit_count=2097152`, and zero
  false positives. The companion rounds smoke kept
  `target_lookup_checksum=0x5ea18a42bc519039`, `hit_count=8192`, and zero false
  positives. Two paired autoresearch confirmations against `HEAD=d16d3fd` both
  kept the candidate on setup-inclusive throughput: confirmation 1 measured
  `setup_inclusive_ops_per_sec=5059542.988443` versus paired baseline
  `4518461.033311` (`paired_speedup=1.119749`); confirmation 2 measured
  `5103671.503285` versus `4925686.310904` (`paired_speedup=1.036134`), with
  the same checksum and hit oracle.
- Promoted per-base positive counting in the sparse repeat exact resolver. The
  repeat-indexed Metal filter still probes every logical `(base_query, repeat)`
  pair and still emits every compact positive, but the CPU exact resolver now
  first counts positives by base DP query, runs `TargetLookupTag32Find` once per
  positive base query, then adds the positive count to hit or false-positive
  totals. This preserves the same logical query count, compact positive count,
  exact `x256 + y_parity` equality, expected injected-target guard, hit count,
  false-positive count, and repeat checksum while removing the per-positive
  cache-state branch. A smoke run on the 16.384M-query M3 auto-repeat gate kept
  `target_lookup_checksum=0x86ec0110960785f8`, `hit_count=2097152`, and zero
  false positives while dropping `lookup_exact_seconds` to about `0.001979`.
  Two paired autoresearch confirmations against `HEAD=99581a8` both kept the
  candidate on runtime `ops_per_sec`: confirmation 1 measured
  `ops_per_sec=41317942.907647` versus paired baseline `35704953.032364`
  (`paired_speedup=1.157205`); confirmation 2 measured
  `51789496.856066` versus `42452416.355267` (`paired_speedup=1.219942`), with
  the same checksum and hit oracle.
- Rejected two follow-on repeat-filter GPU scouts after preserving the
  checksum oracle. A `base_query_expand` repeat kernel emitted one positive
  per base query and expanded counts on the CPU; it kept
  `target_lookup_checksum=0x86ec0110960785f8`, `hit_count=2097152`, and zero
  false positives, but the 500 ms guardrail lost to the accepted sparse exact
  path (`ops_per_sec=71527275.349346`, `lookup_seconds=0.139999`) versus the
  default (`ops_per_sec=72362967.315323`, `lookup_seconds=0.110338`). It was
  also structurally under-occupied for the 125-base-query shape, so it is not
  a real-world solver win. A separate default-threadgroup scout tried routing
  the large repeat hash filter to 768 threads per threadgroup. A direct sweep
  looked promising, but paired autoresearch confirmation against `HEAD=e5892e2`
  discarded it: final median `ops_per_sec=56615931.341812` versus paired
  baseline `59226315.668816`, `paired_speedup=0.955925`, with the same
  checksum. Keep the raw rows as negative evidence; do not promote either
  change.
- Rejected grouped threadgroup compaction and default `768` lookup-threadgroup
  promotion on the M3 auto repeat gate, then promoted GPU base-count positive
  output. The grouped compaction candidate kept
  `target_lookup_checksum=0x86ec0110960785f8`, `hit_count=2097152`, and zero
  false positives, but paired confirmation discarded it at
  `ops_per_sec=30022289.683890` versus paired baseline `39907839.933016`
  (`paired_speedup=0.752291`). A direct explicit `--lookup-tg-limit 768` sweep
  looked promising, but the real default-vs-`HEAD` gate discarded promotion:
  final `ops_per_sec=34205080.912293` versus paired baseline
  `40962800.191419` (`paired_speedup=0.835028`). The accepted path replaces
  repeated base-index positive copies with GPU-emitted per-base positive
  counts (`repeat_positive_index_encoding=base_query_count_repeated`). It still
  probes every logical `(base_query, repeat)` pair, validates the total compact
  positive count, resolves exact `x256 + y_parity` once per positive base
  query, and counts every logical hit or false positive. Smoke kept the same
  checksum, `hit_count=2097152`, and zero false positives while dropping
  `lookup_exact_seconds` to about `0.000011`. Two paired confirmations against
  `HEAD=a5cb61a` kept the candidate: confirmation 1 measured
  `ops_per_sec=67353853.133572` versus baseline `53144408.728376`
  (`paired_speedup=1.267374`); confirmation 2 measured
  `71787238.321406` versus `69363382.005319` (`paired_speedup=1.034944`).
- Rejected two post-base-count M3 GPU probes while keeping their correctness
  evidence. A 2D threadgroup dispatch for the base-count kernel kept
  `target_lookup_checksum=0x86ec0110960785f8`, `hit_count=2097152`, and zero
  false positives, but paired confirmation was mixed and ended as discard:
  confirmation 1 measured `ops_per_sec=75097791.714684` versus baseline
  `73169519.919926` (`paired_speedup=1.026353`), while confirmation 2 measured
  `72047891.025586` versus `73874758.195050`
  (`paired_speedup=0.975271`). The launcher was reverted. A separate
  `tag16-mix` integrated lookup diagnostic was added behind
  `--lookup-filter-mode tag16-mix`, including a fused mixed tag16 filter setup
  and a mixed base-count Metal kernel. It preserves the same logical repeat
  probes, base-count positive encoding, exact CPU `x256 + y_parity` resolver,
  checksum, hit count, and false-positive count, but the setup-inclusive paired
  M3 gate discarded it: final `setup_inclusive_ops_per_sec=15462762.638213`
  versus baseline `17646576.051489` (`paired_speedup=0.876247`). Keep
  `tag16-mix` as an explicit diagnostic for collision-distribution probes; do
  not promote it as a default or speed claim.
- Promoted by-base threadgroup reduction for the repeat-indexed tag16
  base-count Metal kernel. The old base-count kernel probed every logical
  `(base_query, repeat)` pair but used global atomics for every filter
  positive. The new kernel dispatches as `(repeat, base_query)`, still runs one
  probe per logical repeat, reduces positives inside each threadgroup, then
  performs one global add per block/base. It keeps
  `repeat_positive_index_encoding=base_query_count_repeated`, exact CPU
  `x256 + y_parity` resolution, `target_lookup_checksum=0x86ec0110960785f8`,
  `hit_count=2097152`, and zero false positives. Two paired M3 confirmations
  against `HEAD=73adb7f` kept the candidate on runtime `ops_per_sec`:
  confirmation 1 measured `75494801.824354` versus baseline
  `72939819.645629` (`paired_speedup=1.035029`); confirmation 2 measured
  `77881634.196628` versus baseline `73789843.671519`
  (`paired_speedup=1.055452`). This is a lookup-kernel win, not target setup
  hiding; target build and filter setup fields remain visible separately.
- Promoted the same base-count positive representation into the stricter
  fixed-round 25M target lookup benchmark. This path uses distinct deterministic
  walk batches, one reused target table/filter, and the same repeated lookup
  oracle, but reports large standard tag16 repeat positives as
  `base_query_count_repeated` instead of expanded packed positive indices. It
  still probes every logical repeat on Metal and preserves exact CPU
  `x256 + y_parity` resolution. The smoke gate kept
  `query_count=16384000`, `hit_count=2097152`, zero false positives, and
  `target_lookup_checksum=0x86ec0110960785f8`. The full fixed-round paired gate
  kept correctness with `target_lookup_checksum=0x923b46f156f9d59b`,
  `hit_count=131072`, `filter_false_positive_count=0`, `dp_count=4121`, and
  `physical_query_count=4219904`. Two paired confirmations against
  `HEAD=9399a02` kept the candidate on runtime `ops_per_sec`: confirmation 1
  measured `55355964.432093` versus baseline `48038763.096163`
  (`paired_speedup=1.152319`); confirmation 2 measured `64727322.948725`
  versus baseline `57414054.969548` (`paired_speedup=1.127378`). This promotes a
  real fixed-round solver-path improvement, not a dedup-repeat diagnostic.
- Promoted fixed-round batched Metal walk dispatch. The previous fixed-round
  benchmark launched the XYZZ distance kernel separately for each deterministic
  round. The new path still builds distinct round starts, but concatenates them
  into one larger Metal walk dispatch, then slices the outputs back into
  per-round affine scans, target offsets, expected hit injection, repeat lookup,
  and exact CPU `x256 + y_parity` validation. A small smoke preserved
  `correctness=true`, `repeat_positive_index_encoding=packed16_base_repeat`,
  `target_lookup_checksum=0x4d668f8d29797461`, and zero false positives. The
  full 25M fixed-round smoke preserved `target_lookup_checksum=0x923b46f156f9d59b`,
  `dp_checksum=0x7f111e78c67b5c18`, `dp_distance_checksum=0x894123b96acf0de5`,
  `dp_count=4121`, `query_count=4219904`, `physical_query_count=4219904`,
  `hit_count=131072`, and `filter_false_positive_count=0`, while measuring
  `ops_per_sec=125880811.007822` in a direct run. The paired autoresearch gate
  against `HEAD=d06499f` kept both confirmations on runtime `ops_per_sec`:
  confirmation 1 measured `109395855.173225` versus baseline
  `78109003.815734` (`paired_speedup=1.400554`); confirmation 2 measured
  `59926669.794161` versus baseline `52718596.332662`
  (`paired_speedup=1.136727`). The M3 Air samples were thermally noisy, including
  one slower internal candidate sample, so report this as a confirmed local
  fixed-round dispatch-shape win, not a guaranteed cross-machine multiplier.
- Post-promotion scouts after `f252993` did not justify another default change.
  Explicit fixed-round 25M walk threadgroup scouts all preserved
  `target_lookup_checksum=0x923b46f156f9d59b`, `dp_checksum=0x7f111e78c67b5c18`,
  `hit_count=131072`, and zero false positives, but did not separate enough to
  beat the current 128-thread default: `--tg-limit 32` measured
  `ops_per_sec=126318260.344232`, `64` measured `126489753.560562`, `128`
  measured `126405382.893416`, and `256` regressed to `121046091.255387`.
  A post-batched `scaled4-balanced` fixed-round scout stayed correct, with
  `dp_checksum=0x23ddf9863ade346f`, `target_lookup_checksum=0x6aaec4659e60b735`,
  and `hit_count=131072`, but measured only `124842555.334704` and carried
  `filter_false_positive_count=1024`, so the prior fixed-round rejection still
  stands. A same-cadence `4096/dp5` direct scout with `lookup_repeat=512`
  preserved correctness and measured `128136100.370204`, but this is too close
  to the 2048/dp6 direct scouts and has previous setup-gate discard history; it
  needs a dedicated paired fixed-round gate before any claim.
- Rejected additional post-batched fixed-round scouts rather than tuning to one
  lucky sample. A no-infinity affine-add fast path preserved
  `target_lookup_checksum=0x923b46f156f9d59b`, `hit_count=131072`, and zero
  false positives, but its direct 25M run measured only
  `125377290.345938 ops/sec`, below the current direct plateau, so it was
  reverted. Same-operation cadence probes also stayed correct but did not justify
  promotion: `4096/dp5` with half repeat measured `117981446.931567 ops/sec`,
  `1024/dp7` measured `125220469.005635 ops/sec` with
  `filter_false_positive_count=1024`, and `512/dp8` measured
  `125305714.106584 ops/sec` with `filter_false_positive_count=2048`. Keep
  `2048/dp6` as the fixed-round local plateau until a paired gate beats it.
- Promoted a compact exact target table for the large standard fixed-round
  tag16 base-count repeat path. The table stores only affine `x` in the host key
  array (`TargetLookupXOnlyHost`, 32 bytes per target) and moves the `y` parity
  bit into the high bit of the tag32 bucket index. The exact resolver still
  validates full compressed identity (`x256 + y_parity`) before counting hits,
  and the path is limited to `base_query_count_repeated` fixed-round batches;
  tag32 diagnostics, tag16-mix diagnostics, dedup-repeat, and packed/full output
  modes keep the original full-key table. A 4096-target smoke reported
  `target_key_bytes=131072`, `repeat_positive_index_encoding=base_query_count_repeated`,
  `target_lookup_checksum=0x6bc66af2c4c40f7b`, and zero false positives. The
  direct 25M fixed-round run preserved `target_lookup_checksum=0x923b46f156f9d59b`,
  `dp_checksum=0x7f111e78c67b5c18`, `dp_count=4121`, `hit_count=131072`, and
  `filter_false_positive_count=0`, while reducing `target_key_bytes` from
  `1000200000` to `800160000` and `exact_host_table_bytes` from `1268635456` to
  `1068595456`; direct throughput measured `126676125.573514 ops/sec`. The
  paired fixed-round gate against clean `HEAD=147f940` kept both confirmations:
  confirmation 1 measured `120293962.488858` versus baseline
  `67114963.416265` (`paired_speedup=1.792357`), and confirmation 2 measured
  `59628720.520350` versus baseline `58353738.362171`
  (`paired_speedup=1.021849`). Treat this as a real memory/setup efficiency win
  with a kept noisy M3 throughput gate, not as a mathematical sqrt-step
  breakthrough or cross-machine speed guarantee.
- Followed the compact fixed-round target table with a streaming host builder.
  The previous x-only builder still materialized 25,005,000 `uint64_t` hashes
  plus 25,005,000 parity bytes before insertion; the new builder writes the
  x-only target key and atomically inserts the tag32/parity bucket in the same
  pass, removing about `225045000` bytes of temporary setup allocation on the
  25M gate. A direct 25M fixed-round run preserved
  `target_lookup_checksum=0x923b46f156f9d59b`, `dp_checksum=0x7f111e78c67b5c18`,
  `dp_count=4121`, `hit_count=131072`, `filter_false_positive_count=0`,
  `target_key_bytes=800160000`, and `exact_host_table_bytes=1068595456`, with
  `target_build_seconds=0.838866` and `ops_per_sec=126279608.929799`. Treat this
  as a deterministic peak-memory reduction and same-plateau setup result, not a
  separate throughput promotion.
- Promoted an uninitialized x-only target buffer for the compact fixed-round
  target table builder. The previous streaming builder still used
  `target_x_keys.resize(target_count)`, which value-initialized about
  `800160000` bytes on the 25,005,000-target gate before immediately overwriting
  every x-only key. The new RAII malloc-backed buffer avoids that setup write,
  fills every slot before exact lookup, and leaves the tag32/parity bucket
  insertion and CPU `x256 + y_parity` resolver unchanged. A direct 25M
  fixed-round run preserved `target_lookup_checksum=0x923b46f156f9d59b`,
  `dp_checksum=0x7f111e78c67b5c18`, `dp_count=4121`, `hit_count=131072`,
  `filter_false_positive_count=0`, `target_key_bytes=800160000`, and
  `exact_host_table_bytes=1068595456`, with `target_build_seconds=0.714661`,
  `setup_inclusive_ops_per_sec=108420139.501535`, and
  `ops_per_sec=126707072.573335`. The new setup-inclusive paired gate against
  clean `HEAD=b5864aa` kept both confirmations: confirmation 1 measured
  `setup_inclusive_ops_per_sec=109975306.448799` versus baseline
  `105596316.168534` (`paired_speedup=1.041469`), and confirmation 2 measured
  `62857296.634462` versus baseline `55923899.198912`
  (`paired_speedup=1.123979`). In `autoresearch/results.tsv`, the selected
  experiment metric is still stored in the common `ops_per_sec` column, so those
  rows are aliases for `setup_inclusive_ops_per_sec`. Treat this as a real
  target setup and memory-bandwidth improvement, not as a new GPU walk-throughput
  claim.
- Rejected a zero-sentinel/calloc parity-bucket follow-up for the compact
  fixed-round table. The candidate recoded the parity bucket empty marker from
  `0xffffffff` to zero by storing `target_index + 1`, then used a calloc-backed
  bucket buffer so untouched empty buckets did not need an explicit vector fill.
  The idea preserved the exact oracle in both the 4096-target smoke
  (`target_lookup_checksum=0x6bc66af2c4c40f7b`) and the 25M gate
  (`target_lookup_checksum=0x923b46f156f9d59b`, `dp_checksum=0x7f111e78c67b5c18`,
  `hit_count=131072`, `filter_false_positive_count=0`), but it did not improve
  setup consistently. A direct 25M scout measured
  `target_build_seconds=0.714034` and
  `setup_inclusive_ops_per_sec=104879966.369781`, essentially no better than the
  accepted builder. The paired setup-inclusive gate against clean `HEAD=6e8f49f`
  discarded the candidate: confirmation 1 measured
  `104431906.564908` versus baseline `110311024.032910`
  (`paired_speedup=0.946704`), while confirmation 2 measured
  `87372372.474576` versus baseline `85013762.668708`
  (`paired_speedup=1.027744`). Because both confirmations must keep, the code was
  reverted; raw rows remain in `autoresearch/benchmarks.jsonl` and
  `autoresearch/results.tsv`.
- Added fixed-round wall-clock telemetry for the Metal walk and lookup stages,
  then kept only the safe no-copy optimization for the large tag16 base-count
  lookup buffers. New JSON fields report `walk_wall_seconds`,
  `walk_buffer_seconds`, `lookup_wall_seconds`, `lookup_buffer_seconds`,
  `setup_inclusive_wall_seconds`, and `setup_inclusive_wall_ops_per_sec`, so
  future gates can see host/Metal setup costs that `seconds` and
  `lookup_seconds` intentionally exclude. The retained code uses
  `newBufferWithBytesNoCopy` with a `newBufferWithBytes` fallback only inside
  `RunTargetLookupTag16HashFilterRepeatBaseCountKernel`; the diagnostic
  `RCK_METAL_DISABLE_NOCOPY=1` flag forces the copy path for A/B checks. On the
  final reduced candidate, a direct 25M fixed-round run preserved
  `target_lookup_checksum=0x923b46f156f9d59b`, `dp_checksum=0x7f111e78c67b5c18`,
  `dp_count=4121`, `hit_count=131072`, and `filter_false_positive_count=0`, with
  `lookup_gpu_seconds=0.006008`, `lookup_wall_seconds=0.007314`,
  `walk_wall_seconds=4.301978`, and
  `setup_inclusive_wall_ops_per_sec=107225416.977237`. A same-binary 25M
  copy-disabled scout before trimming the walk candidate had measured the lookup
  copy path at `lookup_gpu_seconds=0.017072` and
  `lookup_wall_seconds=0.023977`, while the no-copy lookup path measured
  `lookup_gpu_seconds=0.009458` and `lookup_wall_seconds=0.010637`; treat this
  as a real lookup-component win, not a full solver-throughput breakthrough.
  A broader candidate that also routed the XYZZ walk state buffers through
  no-copy was rejected: the paired setup-inclusive gate against clean
  `HEAD=24c0458` ended with `confirmation_status=discard` despite one noisy
  confirmation showing improvement, so the walk no-copy code was removed.
- Rejected a Metal XYZZ distance-only specialization for the fixed-round
  `jump_schedule=power2`, `jump_count=16` path. The candidate added separate
  `*_j16_power2_u32_distance` kernels that replaced the constant-memory
  `jump_distances[jump_index]` load with `1U << jump_index`, guarded by a host
  predicate and an A/B kill switch. It preserved correctness on smoke tests and
  on the 25M multi-target gate: both on/off runs kept
  `target_lookup_checksum=0x923b46f156f9d59b`,
  `dp_checksum=0x7f111e78c67b5c18`, `dp_count=4121`, `hit_count=131072`, and
  `filter_false_positive_count=0`. It was slower in the same-binary 25M
  comparison, with the disabled baseline at `seconds=4.229600`,
  `setup_inclusive_wall_ops_per_sec=108819740.194160`, and
  `ops_per_sec=126390406.970705`, versus the specialization at
  `seconds=4.289734`, `setup_inclusive_wall_ops_per_sec=107641119.847796`, and
  `ops_per_sec=124637827.081943`. The candidate was removed; the result suggests
  that the constant-distance load is not the bottleneck on M3 for this kernel,
  and the shift/codegen path can be worse than the cached table read.
- Rejected a local `-mcpu=native` macOS build-flag promotion for the fixed-round
  25M gate. The native build preserved the standard oracle
  (`target_lookup_checksum=0x923b46f156f9d59b`,
  `dp_checksum=0x7f111e78c67b5c18`, `hit_count=131072`, and zero false
  positives), but the direct M3 run regressed to
  `setup_inclusive_wall_ops_per_sec=103730446.451354` and
  `ops_per_sec=124753607.454484`, below the same-session default-build baseline.
  Keep the portable `-O3 -flto=thin` macOS build flags unless a paired gate
  proves a machine-specific target.
- Rejected a no-copy range refactor for fixed-round per-round scan/validation
  slices. The candidate avoided creating temporary `std::vector` copies for
  each round after the batched Metal walk, and preserved the full 25M oracle
  (`target_lookup_checksum=0x923b46f156f9d59b`,
  `dp_checksum=0x7f111e78c67b5c18`, `dp_count=4121`, `hit_count=131072`, zero
  false positives). It did not clear the promotion gate: paired autoresearch
  against clean `main` measured candidate
  `setup_inclusive_wall_ops_per_sec=106910092.849915` versus baseline
  `106621267.427845`, only `paired_speedup=1.002709` under the required 1%
  threshold. The code was removed and the discard row is retained in
  `autoresearch/results.tsv` and `autoresearch/benchmarks.jsonl`.
- Accepted a small fixed-round host setup cleanup and benchmark honesty patch.
  For `round > 0`, fixed-round setup previously called
  `BuildJacobianAddSamplesFrom(...)` with a throwaway affine `q` vector, causing
  deterministic affine samples to be generated and then discarded before the
  Metal walk. The retained code factors sample generation through
  `BuildJacobianSampleAt(...)` and uses `BuildJacobianPointSamplesFrom(...)`
  for later rounds, preserving the original `p/q` builder for call sites that
  still need both point streams. The JSON now reports
  `round_sample_build_seconds` and includes it in both
  `setup_inclusive_seconds` and `setup_inclusive_wall_seconds`, so fixed-round
  metrics include this real host-side preparation cost instead of hiding it
  before the walk timer. The 25M fixed-round gate preserved
  `target_lookup_checksum=0x923b46f156f9d59b`,
  `dp_checksum=0x7f111e78c67b5c18`, `dp_count=4121`, `hit_count=131072`, and
  `filter_false_positive_count=0`. The measured candidate reported
  `round_sample_build_seconds=0.003361`,
  `setup_inclusive_wall_ops_per_sec=104582819.875260`,
  `ops_per_sec=126136486.532603`, and external `/usr/bin/time` `real=23.88s`.
  A same-session uninstrumented baseline comparison measured `real=23.35s`,
  but its walk timing was thermally/noise affected, so this should be treated as
  a correctness-preserving cleanup and stricter metric, not as a promoted solver
  throughput breakthrough.
- Accepted an injected-hash prefilter for host target-table builders. The
  target builders still sort injected hashes and still call the exact
  `TargetLookupHashMatchesInjected(...)` check whenever a filler hash may match;
  the new `InjectedHashFilter` only skips that binary-search/exact path when two
  hash-derived filter bits prove the filler hash cannot be one of the injected
  hashes. This keeps the no-false-negative correctness contract while reducing
  repeated injected-hash probes during large deterministic filler generation.
  The isolated `target-lookup-tag32-parallel-insert-bench --target-count
  25005000 --injected-count 128 --iterations 1` improved in a direct scout from
  `parallel_seconds=1.124707` to `0.628557`, with `target_keys_equal=true`,
  `all_keys_found=true`, and `correctness=true`. The integrated 25M fixed-round
  run preserved the full oracle (`target_lookup_checksum=0x923b46f156f9d59b`,
  `dp_checksum=0x7f111e78c67b5c18`, `dp_count=4121`, `hit_count=131072`, zero
  false positives) and measured `target_build_seconds=0.706725` in the direct
  candidate run. A paired autoresearch gate against clean `main=7b4423e` using
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_rounds_setup_wall`
  kept both confirmations despite strong M3 Air thermal noise:
  confirmation 1 measured `setup_inclusive_wall_ops_per_sec=102762281.417187`
  versus baseline `101650514.686968` (`paired_speedup=1.010937`), and
  confirmation 2 measured `78462642.066908` versus baseline
  `77106310.387503` (`paired_speedup=1.017590`). Treat the win as a
  target-build/setup improvement; the GPU walk kernel itself is unchanged.
- Refined the injected-hash prefilter bit selection to use low/high slices of
  the already mixed 64-bit target hash instead of two extra `TargetLookupMix`
  calls per filler. The no-false-negative contract is unchanged because any
  exact hash match sets and tests the same two bit positions before falling back
  to exact key comparison. The paired
  `target_lookup_tag32_parallel_insert` gate against clean `main=1a4e22a` kept
  both confirmations: confirmation 1 measured `parallel_targets_per_sec`
  `32901579.175273` versus baseline `32478416.212303`, and confirmation 2
  measured `57394495.386564` versus baseline `54632043.996412`
  (`paired_speedup=1.050565`). A direct integrated 25M fixed-round check kept
  `target_lookup_checksum=0x923b46f156f9d59b`,
  `dp_checksum=0x7f111e78c67b5c18`, `hit_count=131072`, zero false positives,
  and measured `target_build_seconds=0.593294` with
  `setup_inclusive_wall_ops_per_sec=108085496.663599`.
- Rejected a smaller 64-word injected-hash prefilter scout. The direct
  `target-lookup-tag32-parallel-insert-bench --target-count 25005000` probes
  stayed correct for `--injected-count 64` and `--injected-count 128`, but
  measured `parallel_seconds=1.380848` and `1.385115`, clearly worse than the
  accepted 256-word filter shape. The change was reverted without promotion.
- Rejected an XYZZ in-place step helper scout. The candidate replaced the hot
  `XyzzValue` return in selected Metal walk paths with scalar reference updates
  while preserving the exceptional cases. Source checks, Metal build, DP-stream
  CLI, and a small fixed-round target lookup all stayed correct, but the paired
  walk gates did not improve: 2048-step affine-scan candidate runs measured
  roughly `77.0M`, `74.8M`, and `64.4M ops/s`, while clean baseline runs in the
  same session measured roughly `77.8M`, `82.5M`, and `80.5M ops/s`.
  DP-stream 256 was likewise neutral-to-worse. The scout was discarded.
- Rejected a no-avalanche XYZZ jump selector scout. Removing the avalanche mix
  from the fixed-round XYZZ jump index preserved correctness and even kept a
  sane 2048-step jump histogram (`jump_histogram_max_deviation_ppm=1869` in the
  scout), but it did not produce a stable speed win (`gpu_ops_per_sec` varied
  from `61.8M` to `80.1M` against recent clean baselines around `78M` to
  `82M`). Because this changes walk trajectories and weakens the documented
  `jump_mixer=avalanche64` contract without a clear performance win, it was
  reverted.
- Accepted no-copy backing for the fixed-round XYZZ distance wrapper on macOS.
  `RunJacobianDynamicXyzzDistanceKernel(...)` now creates the mutable `p_xyzz`
  and infinity Metal buffers through `NewSharedMetalBufferNoCopyFallback(...)`,
  then parses the updated backing vectors directly and moves the packet
  distance vector instead of copying it. The existing
  `RCK_METAL_DISABLE_NOCOPY=1` escape hatch can still force the copy-backed
  path for A/B checks; the wrapper tracks whether the helper actually returned
  no-copy storage and copies back only on fallback. This removes full host-side
  state buffer copies without changing the Metal kernel, jump schedule, affine
  DP scan, target lookup, or exact equality oracle. The 25M fixed-round gate preserved
  `target_lookup_checksum=0x923b46f156f9d59b`,
  `dp_checksum=0x7f111e78c67b5c18`, `dp_count=4121`, `hit_count=131072`, and
  zero false positives. A same-session paired check measured candidate
  `setup_inclusive_wall_ops_per_sec=112827538.813821` versus clean baseline
  `110323392.381208` (`paired_speedup=1.022699`), with a second candidate
  confirmation at `111743508.178081` (`paired_speedup=1.012874` versus the same
  baseline). Treat this as a real macOS host-buffer/setup improvement; GPU walk
  arithmetic throughput is intentionally unchanged. After adding fallback-state
  tracking, `RCK_METAL_DISABLE_NOCOPY=1` was also checked on the same 25M gate
  and preserved the full oracle; in that same-bin comparison no-copy measured
  `setup_inclusive_wall_ops_per_sec=110604004.595908` and forced-copy measured
  `108859529.906798`, with similar `walk_buffer_seconds` and visible
  target-build/lookup noise. Keep treating this as a modest macOS host-buffer
  reduction, not as a mathematical walk-speed breakthrough.
- Rejected a Metal `mulhi` field-arithmetic scout. Replacing the portable
  32-bit-split `mul64` helper with `lo = a * b; hi = mulhi(a, b);` compiled on
  the M3 Metal runtime and preserved `metal-field-mul-test` plus
  `metal-field-square-test`. Isolated field benches looked tempting:
  500 ms square runs rose to roughly `204M` to `224M ops/s`, while field-mul
  remained noisy around `144M` to `198M ops/s`. The solver-facing XYZZ
  affine-scan gate rejected it: baseline `steps=2048, dp_bits=8` runs measured
  about `83.2M` to `85.2M ops/s`, while the `mulhi` candidate measured only
  about `79.1M` to `80.8M ops/s` with identical DP checksums and correctness.
  The change was reverted because it improves isolated arithmetic scheduling
  but slows the real walk kernel on the MacBook Air M3 shape.
- Rejected a Metal packet-loop `#pragma unroll 2` scout for
  `xyzz_walk_pow2_u32_distance`. The pragma compiled on the M3 runtime and
  preserved the XYZZ DP stream test, affine-scan DP checksums, fixed-round
  `target_lookup_checksum=0x923b46f156f9d59b`, `dp_checksum=0x7f111e78c67b5c18`,
  `hit_count=131072`, and zero false positives. The performance did not clear
  the real gate: `steps=2048, dp_bits=8` affine-scan runs landed around
  `82.6M` to `83.2M ops/s`, below the clean same-session baseline corridor of
  about `83.2M` to `85.2M ops/s`. A 25M fixed-round run was also slower, with
  `setup_inclusive_wall_ops_per_sec=105316950.886088` versus the preceding
  clean direct run at `107088262.970406`, and walk wall time rising from
  about `4.499s` to `4.555s`. The loop-control overhead is not the bottleneck;
  keep the current compiler scheduling.
- Rejected a Metal XYZZ branch-hint scout. Adding `__builtin_expect` around the
  rare `p_infinity` and `h == 0` mixed-add branches compiled on the M3 runtime
  and preserved the XYZZ DP stream test, affine-scan checksums, the 25M
  fixed-round `target_lookup_checksum=0x923b46f156f9d59b`,
  `dp_checksum=0x7f111e78c67b5c18`, `hit_count=131072`, and zero false
  positives. The small 2048-step affine-scan gate was neutral at roughly
  `83.6M` to `83.8M ops/s`. A direct 25M candidate run looked high at
  `setup_inclusive_wall_ops_per_sec=114310632.488466`, but the immediately
  rebuilt baseline measured `115571607.177231` on the same command with the
  same oracle. Treat the apparent win as run-state noise; keep the unhinted
  branch shape.
- Added schedule-distance throughput metrics to the integrated affine-scan
  target-lookup JSON. The benchmark now reports `mean_jump_distance`,
  `gpu_distance_per_sec`, `distance_per_sec`,
  `setup_inclusive_distance_per_sec`, and
  `setup_inclusive_wall_distance_per_sec`. These fields multiply the existing
  group-operation rates by the exact mean jump distance for `power2` and
  `scaled4-balanced` schedules, making schedule experiments compare effective
  kangaroo distance covered per second instead of raw operation rate alone.
  This is a benchmark-honesty improvement, not a solver speed claim. Small
  runtime smokes preserved correctness and showed `mean_jump_distance=31.875`
  for `--jumps 8 --jump-schedule power2` and `4097.0` for
  `--jumps 4 --jump-schedule scaled4-balanced`. Invalid `scaled4-balanced`
  jump counts report zero distance throughput alongside the existing
  correctness failure instead of exposing a misleading schedule metric.
- Added a physical `distinct-misses` mode to the fixed-round 25M target-lookup
  gate. The previous fixed-round gate could stress lookup throughput only by
  repeating the same real DP batch; the new mode keeps the real DP keys once,
  fills the remaining physical query batch with deterministic keys verified as
  exact misses, runs the non-repeat tag16 hash-filter kernel, and validates the
  full output against explicit expected indices. This is a benchmark-honesty
  and real-stream modeling improvement: it checks whether repeat-mode wins
  survive mostly-miss distinct DP traffic instead of silently exploiting
  repeated base queries. The path also reuses the compact x-only-plus-parity
  target table and a new non-repeat parity resolver, so exact verification
  remains `x256 + y_parity` while avoiding the full-key host table. Small
  runtime smoke preserved `target_lookup_checksum=0xb107a63c69100191` with
  `repeat_positive_index_encoding=physical_query_index`. The 25M fixed-round
  distinct-misses gate preserved the walk oracle
  (`dp_checksum=0x7f111e78c67b5c18`, `dp_count=4121`) and lookup oracle
  (`target_lookup_checksum=0x5c90bdf7f12141b9`, `hit_count=128`,
  `filter_false_positive_count=870`), with `physical_query_count=4219904`,
  `target_key_bytes=800160000`, `exact_host_table_bytes=1068595456`, and
  `setup_inclusive_wall_distance_per_sec=448341422373.053650`. A repeat-mode
  guardrail on the same 25M command kept the established checksum
  `0x923b46f156f9d59b`, `hit_count=131072`, and zero false positives. The
  saved autoresearch recipe
  `metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_rounds_distinct_misses_distance`
  kept three samples on `setup_inclusive_wall_distance_per_sec`, with median
  `440854462579.940979`, min `434461529030.060547`, max
  `444661566891.730347`, and the same distinct checksum
  `0x5c90bdf7f12141b9`.
- Rejected several follow-up speed scouts on the fixed-round distinct-miss gate,
  while keeping one diagnostic path. The new non-repeat
  `target_lookup_tag16_mixed_hash_filter256` Metal kernel allows
  `--lookup-query-mode distinct-misses --lookup-filter-mode tag16-mix` to run
  through the same compact x-only-plus-parity exact resolver and explicit
  expected-index oracle. It is not a speed win on the MacBook Air M3 25M gate:
  the mixed run preserved `target_lookup_checksum=0x5c90bdf7f12141b9` and
  `dp_checksum=0x7f111e78c67b5c18`, but measured
  `filter_false_positive_count=955` and
  `setup_inclusive_wall_distance_per_sec=437922068026.285522`, versus an
  adjacent standard tag16 run at `filter_false_positive_count=870` and
  `442680658255.041443`. A lookup threadgroup sweep kept the existing
  `--lookup-tg-limit 512` default: same-checksum samples measured roughly
  `443.9B`, `464.4B`, `453.2B`, and `463.7B` distance/sec for lookup caps
  `256`, `512`, `768`, and `1024`, respectively, so `512` remained the best
  tested cap and `1024` was only close. A walk threadgroup sweep likewise kept
  the existing 128-thread walk cap: `64`, `128`, `256`, and `512` measured
  roughly `428.1B`, `464.9B`, `447.9B`, and `440.2B` setup-inclusive wall
  distance/sec. A `jumps=4 --jump-schedule scaled4-balanced` distinct run was
  correct but slower than the adjacent power-of-two path
  (`443109577739.199829` distance/sec with checksum
  `0x302b660f00b7f972`). A DP-density scout showed why high `dp_bits` should
  not be accepted as a default speed win without solver-level policy: `dp8`
  briefly reached `451496782620.7065` distance/sec with only `1015` DPs, but
  `dp9` and `dp10` slowed sharply and `dp11+` underfilled the requested
  64-hit-per-round oracle. A cached Metal-library setup scout was also
  rejected: one 25M standard distinct sample reached
  `452658472970.062134`, but the next fell to `423174123107.479248` with the
  same checksum, so the extra process-global Objective-C cache was removed as
  noise rather than kept as an optimization.
- Accepted a narrow fixed-round host-copy reduction, with a conservative speed
  interpretation. The fixed-round target-lookup command no longer materializes
  per-round `std::vector` slices for the already-batched Jacobian starts, XYZZ
  Metal outputs, and packet distances before affine DP scan and validation.
  Instead, `CpuXyzzBatchAffineDpScanRange(...)` and
  `ValidateDynamicXyzzStateDistanceOutputsRange(...)` consume pointer/count
  views into the existing batched buffers; the public vector wrappers remain in
  place for the other commands. Small repeat, distinct, and distinct tag16-mix
  smokes preserved their exact checksums, including distinct
  `target_lookup_checksum=0xb107a63c69100191`. The 25M distinct gate preserved
  `target_lookup_checksum=0x5c90bdf7f12141b9`,
  `dp_checksum=0x7f111e78c67b5c18`, `dp_count=4121`, and `hit_count=128`.
  A same-session worktree-paired whole-process check favored the candidate:
  candidate samples measured `421371706662.81537` and
  `437184125632.8725` setup-inclusive wall distance/sec, while the clean
  baseline between them measured `403170649366.641`; elapsed wall was roughly
  `20.686s`, `22.171s`, and `21.762s`. Treat this as a real host allocation
  and memory-traffic cleanup, not a GPU arithmetic breakthrough. The canonical
  autoresearch metric still recorded `status=discard` with
  `419382208002.396973`, because that metric excludes the old pre-scan slice
  copy overhead and the M3 Air run was thermally noisy; keep both facts visible
  when comparing future changes.
- Added sparse exact validation for physical `distinct-misses` lookup and a
  diagnostic blocked Bloom64 GPU filter. The accepted part is the sparse
  distinct resolver: after the GPU emits positive physical query indices, the
  CPU exact resolver now checks each positive against the expected prefix
  indices directly, and `ValidateDistinctTargetLookupSparseOutputsWithExpected`
  computes the same checksum from the expected prefix plus implicit miss suffix.
  This removes the full `distinct_expected_indices` allocation and avoids
  filling a multi-million-entry output vector in the distinct path. Small tag16
  and Bloom64 smokes both preserved `target_lookup_checksum=0xb107a63c69100191`;
  the 25M tag16 gate preserved `target_lookup_checksum=0x5c90bdf7f12141b9`,
  `dp_checksum=0x7f111e78c67b5c18`, `dp_count=4121`, and `hit_count=128`, with
  `lookup_exact_seconds=0.000345` to `0.000580` in candidate runs versus
  `0.001736` in an adjacent clean `4d17076` baseline. Setup-inclusive wall
  distance/sec stayed noisy but favored the candidate in the sandwich
  (`448914572235.917664`, baseline `413672125515.746338`,
  candidate `455370090782.347961`). Treat this as a correctness-preserving host
  allocation/exact-resolver cleanup, not as a GPU arithmetic breakthrough. The
  canonical autoresearch gate kept the same checksum and oracle on three
  samples (`440858189444.951538`, `447840335155.647644`,
  `439183237405.765137` setup-inclusive wall distance/sec), but recorded
  `status=discard` because the metric did not beat the existing 25M gate by the
  configured threshold. The optional `--lookup-filter-mode bloom64` path uses a
  one-word blocked
  Bloom filter and the same exact resolver. It is not promoted for the 25M M3
  gate: the Bloom64 run was correct with the same checksum, but produced
  `filter_false_positive_count=21745`, `lookup_exact_seconds=0.026213`, and
  `setup_inclusive_wall_distance_per_sec=432166775347.620728`, behind the
  adjacent tag16 run at `filter_false_positive_count=880`,
  `lookup_exact_seconds=0.001583`, and
  `setup_inclusive_wall_distance_per_sec=444669824372.268311`. Bloom64 looked
  mildly useful on a 1M-target diagnostic (`475900359808.846436` versus
  `473042432573.026917` setup-inclusive wall distance/sec), so the mode and
  reproducible autoresearch recipe are kept as a diagnostic, not as the default
  multi-target filter.
- Added compact physical-miss sources and no-copy Metal buffers for the
  fixed-round `distinct-misses` hash-filter path. The distinct benchmark no
  longer materializes the full physical `TargetLookupKeyHost` query vector
  (`4219904 * 40 = 168796160` bytes at the 25M gate). Instead it stores the
  real DP prefix plus one compact `uint64_t` nonce/salt source per synthetic
  miss (`4215783 * 8 = 33726264` bytes) and reconstructs only GPU-positive
  keys for exact `x256 + y_parity` validation. The non-repeat tag16 and Bloom64
  hash-filter kernels now use `NewSharedMetalBufferNoCopyFallback` for their
  large filter/hash inputs on Apple unified memory, matching the existing
  repeat base-count path. Small distinct tag16 and Bloom64 smokes preserved
  `target_lookup_checksum=0xb107a63c69100191`; the 25M tag16 gate preserved
  `target_lookup_checksum=0x5c90bdf7f12141b9`,
  `dp_checksum=0x7f111e78c67b5c18`, `dp_count=4121`, and `hit_count=128`.
  A same-session clean `d636653` sandwich showed a real lookup transfer win but
  only a small whole-gate gain: candidate samples measured
  `451052909577.432922` and `451985201396.679932` setup-inclusive distance/sec
  around a clean baseline at `447232494661.439087`. Lookup wall time improved
  from the baseline `0.077735s` to `0.046888s` and `0.040415s`, with
  `lookup_buffer_seconds` falling from `0.027118s` to roughly `0.000878s` and
  `0.001356s`. The canonical autoresearch gate remained honest and recorded
  `status=discard` on setup-inclusive wall distance/sec (`440817525593.280823`,
  `439827907194.731995`, `446454740412.935791`), so this is promoted as a
  memory/UMA transfer efficiency improvement for multi-target lookup, not as a
  kangaroo arithmetic breakthrough.

## Cleanup Policy

- After a feature is merged to `main` and pushed, remove only its clean accepted
  worktree and delete only its merged local branch.
- Do not remove dirty or rejected worktrees until their useful findings have
  been recorded and any wanted diff has been intentionally saved.
- Keep README files focused on user-facing commands. Keep detailed experiment
  history here and raw metrics in `autoresearch/results.tsv` plus
  `autoresearch/benchmarks.jsonl`.
