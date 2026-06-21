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

## Accepted Results

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

## Rejected Or Non-Merged Experiments

These did not pass the performance gate or had a correctness/architecture issue:

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
  hint is too noisy to promote on this M3 Air.
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

## Next Research Targets

- Move from isolated field kernels toward Jacobian point kernels on Metal.
- Keep CPU tiny-range kangaroo as the correctness oracle while GPU kernels are
  introduced one layer at a time.
- Prefer fused kernels only when paired benchmarks show a real win. The fused
  operation must still expose an oracle and a reproducible benchmark.
- Explore Metal memory layout for point batches before attempting full
  distinguished-point table work on GPU.
- Keep multi-target CPU architecture unchanged unless a candidate beats the
  paired autoresearch gate and preserves full collision verification.

## Cleanup Policy

- After a feature is merged to `main` and pushed, remove only its clean accepted
  worktree and delete only its merged local branch.
- Do not remove dirty or rejected worktrees until their useful findings have
  been recorded and any wanted diff has been intentionally saved.
- Keep README files focused on user-facing commands. Keep detailed experiment
  history here and raw metrics in `autoresearch/results.tsv` plus
  `autoresearch/benchmarks.jsonl`.
