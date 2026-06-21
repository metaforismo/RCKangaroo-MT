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
