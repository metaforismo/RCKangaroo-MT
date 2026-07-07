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

## Current Bottleneck

The 25M physical gate is dominated by the XYZZ Metal walk. Lookup and target
construction are visible and must remain included in setup-inclusive scores, but
they are no longer the main MacBook Air M3 bottleneck.

Typical current shape:

- GPU walk wall time: several seconds and the dominant component.
- Target setup: secondary, usually subsecond but still included.
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
- Changing the opt-in Metal sidecar flags away from `-finline-functions`.
  `-O3`, `-O2`, `-Os`, forced unroll, disabled unroll, and disabled vectorizers
  all preserved the 1M fixed-round oracle but did not beat the current flag
  stably.
- Forcing source-shape changes around the fixed-round XYZZ helper without new
  compiler evidence. `static inline`, `always_inline`, and internal
  `bool`/`uint`/`uchar` infinity-flag rewrites preserved the oracle but slowed
  the 1M fixed-round gate sharply.

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
   persistent variants were close and noisy. Future work should use the physical
   distinct-miss gate, order-reversed pairs, cooldown, and exact cumulative
   distance checks.

5. Metal compiler/codegen evidence.

   Try toolchain flags or attributes as measured experiments. The runtime may
   auto-load a matching sidecar for startup/codegen ergonomics, but speed claims
   still require order-reversed 25M gates and the canonical oracle.

## Promotion Checklist

Every speed candidate must answer:

- What exact operation changed: walk arithmetic, affine scan, target setup,
  lookup, schedule, or harness?
- Which oracle proves correctness?
- Which metric is primary?
- Did the candidate keep the canonical checksum fields stable or explain why a
  solver-equivalent oracle changed?
- Did it run paired against current `main`, preferably with alternate order?
- Did it improve setup-inclusive wall distance/sec, not just a submetric?
- Did the research log record both the positive and negative evidence?
