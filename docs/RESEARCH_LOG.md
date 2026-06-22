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
