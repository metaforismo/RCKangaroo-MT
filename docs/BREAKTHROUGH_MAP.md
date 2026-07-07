# Breakthrough Map

This file is the compact working map for real macOS/Apple Silicon kangaroo
improvements. It complements `docs/RESEARCH_LOG.md`, which keeps the detailed
experiment ledger.

## Canonical macOS Gate

Use the fixed-round physical distinct-miss multi-target gate before promoting
macOS Metal speed claims:

```sh
./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench \
  --iterations 131072 \
  --steps 2048 \
  --jumps 16 \
  --dp-bits 6 \
  --target-count 25005000 \
  --hits 64 \
  --lookup-repeat 1024 \
  --lookup-query-mode distinct-misses \
  --rounds 2 \
  --lookup-tg-limit 512 \
  --jump-schedule power2
```

The current oracle to preserve is:

- `target_lookup_checksum=0x5c90bdf7f12141b9`
- `dp_checksum=0x7f111e78c67b5c18`
- `dp_distance_checksum=0x894123b96acf0de5`
- `dp_count=4121`
- `hit_count=128`
- `correctness=true`

Primary score: `setup_inclusive_wall_distance_per_sec`.

Do not promote a change from `ops_per_sec`, `lookups_per_sec`, field
microbenchmarks, or repeat-mode-only wins unless it also survives this gate or a
clearly documented solver-equivalent gate.

Fast falsifier before spending the full 25M run:

```sh
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter1m_rounds_distinct_misses_distance \
  --budget-sec 180 \
  --paired-baseline-ref HEAD \
  --confirm-runs 2
```

This 1M-target gate keeps the same fixed-round `2048/dp6`, physical
distinct-miss lookup, exact target verification, and setup-inclusive wall
distance metric. It is a candidate filter, not a promotion gate.

Same-tree paired baseline rule: if `--paired-baseline-ref` resolves to the same
clean candidate tree and the paired baseline command is identical to the
candidate benchmark command, the runner must record the row as `discard` with
`same_tree_paired_baseline=true`. Such a row is a noise sentinel, not a speed
candidate, and must not become a best previous score. Same-tree command A/B
experiments remain valid when `paired_baseline_command` is explicitly different.

Paired baseline spread rule: when an experiment defines
`max_sample_spread_ratio`, the paired baseline sample spread is part of the
oracle. If `paired_baseline.sample_spread_ratio` exceeds that limit, the runner
must discard the candidate and record `paired_baseline_sample_spread_ratio`,
even when the candidate median appears faster. A noisy depressed baseline is not
promotion evidence.

## Latest Accepted Change

2026-07-07: paired baseline spread guard for autoresearch.

- Change: paired autoresearch now applies the configured
  `max_sample_spread_ratio` to the paired baseline sample set as well as to the
  candidate. Rows with an unstable paired baseline are forced to `discard` and
  include `paired_baseline_sample_spread_ratio` plus a reason string.
- Motivation: the 25M square double-product scout produced noisy paired samples
  while the 1M gate looked strongly positive. This guard prevents a thermally
  depressed or order-sensitive baseline median from turning into false
  promotion evidence.
- Scope: this is a benchmark integrity improvement. It does not claim a new
  GKeys/s or distance/sec speedup, but it makes future M3 Metal promotion gates
  stricter and more reproducible.

Earlier 2026-07-07: same-tree paired baseline guard for autoresearch.

- Change: paired autoresearch now compares the baseline worktree tree id with
  the clean candidate tree id when the paired baseline command is the same as
  the candidate command. If tree and command are identical, candidate rows are
  forced to `discard`, even when timing noise makes the candidate appear faster.
- Motivation: a same-code `HEAD` versus `HEAD` 1M Metal fast-falsifier scout
  produced an apparent `keep` at
  `setup_inclusive_wall_distance_per_sec=458033093273.016968` versus paired
  baseline `445924603229.232971` (`paired_speedup=1.027154`) with identical
  oracle fields. That is thermal/order noise, not an optimization.
- Scope: this is a benchmark integrity improvement. It does not claim a new
  GKeys/s or distance/sec speedup, but it prevents false promotions from
  polluting `best_previous` and future gates.

Earlier 2026-07-07: dense source-line storage for real target files.

- Change: real target records now store only the full 64-byte affine point.
  Source lines are reconstructed as `index + 1` for stripped files or
  `index + 1 + source_line_base` for header-only/comment-offset files; only
  non-dense files allocate an explicit `u32` source-line side array.
- Correctness oracle: `GetPoint()` still returns the full affine point, and
  `GetSourceLine()` is covered for stripped, header-only, and middle-comment
  non-dense files. The `target-set-load-bench` checksum stayed
  `0x1b6099d07874199b` on the 1,048,576-target compressed header fixture.
- Scale effect: 25,005,000 stripped/header-only targets avoid about
  `100020000` bytes of per-target source-line storage versus the old
  68-byte record layout. The 1,048,576-target fixture reports
  `target_storage_bytes=67108864`, `source_line_storage=dense_index_plus_base`,
  `source_line_base=1`, and `explicit_source_line_bytes=0`.
- Speed evidence: the adjacent 1,048,576-target compressed loader run measured
  `200658.748317` targets/sec versus the pre-change baseline
  `198868.683259`, with the same checksum. Treat this as a loader memory win;
  it is not a Metal walk or GKeys/s claim.
- Rejected boundary: do not default to `x+parity` target storage yet. It saves
  more memory but would require field square-root decompression when active
  wild targets are materialized, so it risks slowing real solver startup.

Earlier 2026-07-07: lazy deterministic filler x-key storage for physical
distinct-miss parity target tables.

- Change: the tag32 parity target table still stores all bucket entries, tags,
  indices, parity bits, and fused filters, but the exact x-only key array stores
  only injected target keys for `lookup_distinct_misses`. Deterministic filler
  x/parity keys are reconstructed only when an exact CPU verification reaches a
  filler index after a filter positive.
- Correctness oracle: unchanged canonical 25M checksums
  (`target_lookup_checksum=0x5c90bdf7f12141b9`,
  `dp_checksum=0x7f111e78c67b5c18`,
  `dp_distance_checksum=0x894123b96acf0de5`, `dp_count=4121`,
  `hit_count=128`, `correctness=true`). The strict resolver gate also passed
  on the 1M physical distinct-miss oracle.
- Scale effect: on the 25M gate, `target_key_bytes` drops from `800160000` to
  `4096`, and `exact_host_table_bytes` drops from `1068595456` to `268439552`.
- Speed evidence: the 1M fast falsifier was noisy and ended `discard`
  (`confirmation_status=discard`), so do not cite it as a speed win. The 25M
  paired promotion run against `HEAD` ended `keep` with
  `setup_inclusive_wall_distance_per_sec=174531285283.435028`,
  paired baseline `171624904725.976135`, speedup `1.016934`, and sample spread
  `1.057247`.
- Interpretation: this is a real memory-pressure improvement with a small 25M
  end-to-end win on the local MacBook Air M3. It is not a mathematical kangaroo
  breakthrough, and it does not move the main bottleneck away from the XYZZ
  Metal walk.

## Current Bottleneck

The 25M physical gate is dominated by the XYZZ Metal walk. Lookup and target
construction are visible and must remain included in setup-inclusive scores, but
they are no longer the main MacBook Air M3 bottleneck.

Typical current shape:

- GPU walk wall time: several seconds and the dominant component.
- Target setup: secondary, usually around one second at 25M but still included.
- Affine scan and lookup: small but kept visible to prevent hidden costs.

## Dead Ends

Do not repeat these without new compiler evidence or a different oracle:

- Replacing `reduce512_mod_p` final loop with one or two conditional
  subtractions. Field microbenchmarks improved, but DP/walk gates did not.
- Replacing `jump_distances[jump_index]` with `1U << jump_index` in XYZZ or
  fixed-round kernels. Correct, but slower or neutral on real gates.
- Splitting `jacobian_add_affine_xyzz_values` into a finite hot-path helper.
  Correct, but worsened register/compiler pressure.
- Direct `q_xy[jump_index].x/y` argument loads instead of the local
  `AffineJumpValue` row. Correct, but not faster on the 25M gate.
- Threadgroup-caching the small jump table. Correct, but not a real M3 win.
- Retuning fixed-round walk threadgroups to 64 or 256 as a default. No stable
  improvement over the current 128-thread M3 policy.
- Unguarded automatic `.metallib` loading. The sidecar is useful as a Metal
  toolchain surface and is built with `-finline-functions`, but default loading
  must stay hash-guarded so stale kernels cannot silently replace the embedded
  source.
- Promoting `scaled4-balanced`, `balanced8`, or smaller jump counts from raw
  operation rate. Schedule claims must compare effective distance/sec and keep
  DP density, false positives, and exact target checksums visible.
- Broad no-copy walk-buffer rewrites. The current fixed-round path already uses
  no-copy buffers where they survived gates.
- Direct-filling fixed-round batched round starts to avoid per-round temporary
  vectors. Correct on the 1M oracle, and it can lower
  `round_sample_build_seconds`, but repeat paired confirmation failed the
  primary wall metric. Latest guarded rerun: `0.999964x` and `0.999170x`.
- Promoting Bloom64 as the fixed-round physical distinct-miss default.
  Correct and half the tag16 filter bytes on the 1M gate, but it raised false
  positives from `28` to `10075`; paired confirmations were `0.981014x` and
  `1.006939x`, below the 1% promotion threshold. The later high-bit mask
  independence fix improves the opt-in diagnostic path to `5749` false
  positives, but still failed default promotion with `0.984380x` and
  `1.006167x`.
- Retuning Bloom64 with k8/double-hash/secondary-mix/cheap-mixed-slot variants.
  All preserved the 1M oracle in direct smokes, but they either raised false
  positives or added enough GPU filter cost to lose wall-time. Latest observed
  false positives: odd-step k8 `12709`, direct high-window k8 `5002`,
  secondary-mix k8 `4746`, cheap mixed-slot k4 `5584`.
- Changing the opt-in Metal sidecar flags away from `-finline-functions`.
  `-O3`, `-O2`, `-Os`, forced unroll, disabled unroll, and disabled vectorizers
  all preserved the 1M fixed-round oracle but did not beat the current flag
  stably.
- Forcing source-shape changes around the fixed-round XYZZ helper without new
  compiler evidence. `static inline`, `always_inline`, and internal
  `bool`/`uint`/`uchar` infinity-flag rewrites preserved the oracle but slowed
  the 1M fixed-round gate sharply.
- Removing the local `av[4]` array from `field_mul_values`. The source change
  was correct and one paired 1M physical distinct-miss gate measured
  `1.007896x`, but that is below the 1% promotion threshold and was not
  repeat-confirmed; the code was reverted and only the evidence row was kept.
- Replacing `field_mul_values` local limb arrays with a direct-limb
  `mul256_by_64_values` helper. The candidate preserved the 1M physical
  distinct-miss oracle, but paired confirmations were slower and the final
  recorded speedup was `0.821769x`; the code was reverted.
- Replacing the avalanche64 dynamic jump mixer with a shift/xor-only
  `xorshift64_scout`. A direct smoke was internally correct and histogram-flat,
  but changed the walk oracle, lowered DP count, and produced weak
  setup-inclusive wall distance/sec; source guards correctly blocked treating
  it as the default.
- Rewriting the fixed-round XYZZ store-round path to avoid the outer
  `XyzzDistanceValue` struct return. The candidate preserved the 1M physical
  distinct-miss oracle, but paired confirmations were `0.991582x` and
  `1.007707x`, so the source was reverted.
- Replacing the two-pass `add_double_mul64_to_512` square cross-term addition
  with a single 129-bit doubled-product accumulation. The 1M gate kept it
  (`~1.06x` then `~1.05x`), but the canonical 25M physical distinct-miss
  promotion gate ended `confirmation_status=discard`; reverted.
- Promoting `--walk-round-mode persistent` as the fixed-round default from the
  1M physical distinct-miss gate. A same-tree command A/B stayed correct, but
  persistent lost both confirmations: `0.973113x` and `0.971031x` versus the
  explicit independent baseline.

## Promising Directions

These are the remaining high-leverage areas.

1. Coordinate/formula redesign for the walk kernel.

   The real target is fewer field multiplications or less register pressure per
   mixed addition. A candidate must preserve the XYZZ replay oracle and should
   first report compiler/code-shape evidence, because several locally cleaner
   formulas made Metal codegen worse.

2. Solver-level multi-target mathematics.

   A real breakthrough may come from target-aware kangaroo scheduling, negation
   symmetry, endomorphism-aware interval splitting, or target-window cycling.
   These must be measured with a solver-level oracle, not only with lookup
   microbenchmarks.

   Current opt-in CPU-tiny surface: `--jump-schedule scaled4-probe-power2`
   first tests a short `scaled4-balanced` schedule and then falls back to
   16-jump `power2`. `--portfolio-probe-steps N` can sweep the probe length
   without recompiling. It is promising for target-window/portfolio research
   because lower and middle tiny-range offsets solve much faster while high
   offsets remain correct through fallback. It is not a Metal default, and the
   automatic probe length must not be changed unless a broad offset sweep beats
   the current rule without creating new late-probe misses.

3. GPU-side affine normalization.

   Moving batch affine recovery from CPU to Metal is useful only if it keeps the
   packet-endpoint DP oracle and reports the normalization cost honestly. Start
   with a correctness-only kernel and compare `affine_scan_seconds` plus
   setup-inclusive wall score.

4. Persistent solver pipeline.

   Keeping walker state resident across packet rounds is solver-like, but prior
   persistent variants were close and noisy. The 2026-07-07 same-tree 1M
   command A/B rejected persistent as the current fixed-round default, so future
   work should change the underlying pipeline or solver cadence rather than
   merely rerunning the same mode. Use the physical distinct-miss gate,
   order-reversed pairs, cooldown, and exact cumulative distance checks.

5. Metal compiler/codegen evidence.

   Try toolchain flags or attributes as measured experiments. The runtime may
   auto-load a matching sidecar for startup/codegen ergonomics, but speed claims
   still require order-reversed 25M gates and the canonical oracle. On the local
   M3 Air toolchain, `metal-objdump --metallib --disassemble` exposes AIR
   modules by `source_filename`; the hot
   `jacobian_affine_walk_dynamic_xyzz_steps2048_pow2_u32_distance` module is
   visible and can be filtered for codegen diffs before spending long gates.

## Promotion Checklist

Every speed candidate must answer:

- What exact operation changed: walk arithmetic, affine scan, target setup,
  lookup, schedule, or harness?
- Which oracle proves correctness?
- Which metric is primary?
- Did the candidate keep the canonical checksum fields stable or explain why a
  solver-equivalent oracle changed?
- Did it run paired against current `main`, preferably with alternate order?
- Did the paired baseline resolve to a different clean tree, or is it an
  explicit same-tree command A/B via `paired_baseline_command`?
- Did it improve setup-inclusive wall distance/sec, not just a submetric?
- Did the research log record both the positive and negative evidence?
