# RCKangaroo-MT

RCKangaroo-MT is a GPLv3 fork of RetiredCoder's `RCKangaroo v3.1`, based on the CUDA SOTA Kangaroo implementation for solving ECDLP on secp256k1.

Upstream project: https://github.com/RetiredC/RCKangaroo
RetiredCoder research collection: https://github.com/RetiredC
Discussion thread: https://bitcointalk.org/index.php?topic=5517607

This fork keeps the original single-target, benchmark, and tames workflows, and adds an experimental multi-target mode plus macOS-native correctness, benchmark, Metal arithmetic, and autoresearch tools.

## Features

- Original RCKangaroo v3.1 CUDA SOTA Kangaroo implementation.
- Single public-key solving with `-pubkey`.
- Benchmark mode when no target is supplied.
- Tames generation/loading with `-tames` and `-max`.
- Multi-target public-key solving with `-targets`.
- Target loader for compressed `02...` / `03...` and uncompressed `04...` secp256k1 public keys.
- Per-DP target metadata so solved collisions can be verified against the matching target.
- macOS CPU oracle for tiny-range correctness checks, local benchmarks, and limb-level field arithmetic.
- Metal smoke plus secp256k1 field-add, field-sub, field-double, field-mul4, field-neg, field-mul, and field-square microkernel checks for Apple Silicon runtime verification.
- Experimental Apple Silicon Metal Jacobian/XYZZ walk probes, including runtime-DP sparse streams, cumulative multi-packet XYZZ chain benchmarks, and exact multi-target lookup gates with setup-inclusive metrics.
- Autoresearch runner for fixed-gate optimization experiments.
- Benchforge Metal Lab for local notes, replayable submissions, verifier JSON, and static leaderboards for the macOS/Metal track.

## Requirements

The full high-performance solver requires NVIDIA CUDA. Linux and Windows CUDA builds are the intended runtime targets for the original kangaroo engine.

Apple Silicon/macOS cannot run CUDA kernels on the Apple GPU. This repo now includes a separate macOS path for target preparation, host correctness, tiny-range CPU solving, CPU field arithmetic, benchmarks, Metal runtime smoke tests, and autoresearch.

## Backend Matrix

| Backend | Status | Purpose |
|---|---|---|
| CUDA | Full solver | Original RCKangaroo CUDA kangaroo engine with multi-target additions. |
| macOS CPU | Working | Tiny-range oracle, secp256k1 correctness tests, baseline benchmarks, and `field_mul_mod_p` microbenchmarks. |
| macOS Metal | Experimental walk backend | Builds and runs Metal smoke, field microkernels, Jacobian walk kernels, dynamic DP stream probes, XYZZ packet walks, and cumulative multi-packet chain benchmarks when a Metal device is visible. |
| Autoresearch | Working | Runs fixed-gate checks and benchmarks, then logs keep/discard/skip experiment rows. |
| Benchforge | Working | Local-first challenge loop for Metal benchmarks, notes, submissions, verifier JSON, and static leaderboard export. |

## Build on Linux CUDA

Edit `CUDA_PATH` in `Makefile` if your CUDA installation is not in `/usr/local/cuda-12.0`.

```sh
make
```

Host-only checks that do not require CUDA:

```sh
make check-host
```

## Command line

```text
-gpu      GPU ids to use, for example "035" for GPUs 0, 3, and 5.
-pubkey   Single public key to solve. Compressed and uncompressed keys are supported.
-targets  Text file with one public key per line for multi-target mode.
-start    Start offset of the key interval, in hex.
-range    Private-key range in bits. Must be 32...170 in CLI parsing.
-dp       Distinguished point bits. Must be 14...60.
-max      Stop after max * 1.15 * sqrt(range) operations.
-tames    Load or generate a tames file.
-target-cycle-rounds
          Optional multi-target mode only: reassign active wild target windows
          every N CUDA rounds when the target file is larger than active wild
          slots.
```

`-pubkey` and `-targets` are mutually exclusive. Both require `-start`, `-range`, and `-dp`.

## Single-target example

```sh
./rckangaroo -dp 16 -range 84 -start 1000000000000000000000 -pubkey 0329c4574a4fd8c810b7e42a4b398882b381bcd85e40c6883712912d167c83e73a
```

## Multi-target example

Prepare a file with one public key per line:

```text
# comments and blank lines are allowed
0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
0379BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798
```

Run:

```sh
./rckangaroo -dp 16 -range 84 -start 1000000000000000000000 -targets targets.cleaned.txt
```

The startup output includes:

```text
Loading multi-target public keys from targets.cleaned.txt...
Successfully loaded N targets into memory.

Initializing Multi-Target Math Architecture...
Successfully mapped N targets against the Base Point.
```

When a key is found, the solver prints and appends to `RESULTS.TXT`:

```text
TARGET INDEX
TARGET SOURCE LINE
X
Y
PRIVATE KEY
```

## Multi-target notes

The loader maps every target by subtracting the configured `-start` offset. Wild kangaroos are then started from target-specific points and carry a `target_id` through GPU distinguished-point output. Tame kangaroos remain universal, so one tame DP can resolve a collision for any target wild. The current mode stops at the first solved target.

When `-start` is non-zero, target mapping uses chunked batch inversion on the host instead of one field inversion per target. This speeds the real startup phase reported as `Successfully mapped N targets against the Base Point` without changing the kangaroo walk, target identity, source-line reporting, or result verification. On macOS, `./macos/rck_macos target-set-load-bench --target-count 1048576 --start 2` isolates this parser plus start-offset mapping path; it is not a kernel GKeys/s benchmark.

For massive target files, consider preparing uncompressed public keys with `python3 macos/prepare_targets.py stripped.txt -o targets.uncompressed.txt --uncompressed`. The runtime parser already accepts both compressed and uncompressed secp256k1 public keys. Uncompressed files are larger, but they avoid recovering `y` with a square root for every compressed key during startup; on the MacBook Air M3 loader probe, the same 1,048,576 target fixture mapped with identical checksums at about `2.47M` targets/sec uncompressed versus about `198k` targets/sec compressed.

For very large target files, all targets are loaded and indexed, but the effective per-target wild density depends on GPU count and kangaroo count. CUDA multi-GPU starts shard the active wild target assignment across GPUs instead of repeating the same local target slice on every device; single-GPU behavior is unchanged. The startup log reports `Multi-target active shard coverage`.

If the target file is larger than the available WILD1/WILD2 slots, use `-target-cycle-rounds N` to reassign active wild start windows over time. Each cycle preserves the universal tame walks, regenerates only WILD1/WILD2 GPU start points and target ids at a CUDA round boundary, skips tame regeneration inside `KernelGen`, keeps already collected target-aware DPs in the host DB, and resets only per-GPU loop history for the new starts. This improves real target-file coverage for huge multi-target runs, but `N` should be chosen large enough to avoid spending too much time on restart overhead or repeatedly abandoning wild walks before they emit useful DPs.

Existing tames files from the original v3.1 format are still used by the normal single-target flow. In multi-target mode, use tames generated by this fork and generate them separately before using `-targets`.

## macOS companion workflow

Validate and normalize a target list on macOS:

```sh
python3 macos/prepare_targets.py stripped.txt -o targets.cleaned.txt
```

Build and test the native macOS path:

```sh
make macos-check
make macos-bench
make macos-point-bench
./macos/rck_macos point-bench --iterations 256 --min-ms 50
make macos-jacobian-point-bench
./macos/rck_macos jacobian-point-bench --iterations 256 --min-ms 50
make macos-jacobian-batch-affine-bench
./macos/rck_macos jacobian-batch-affine-bench --iterations 256 --min-ms 50 --points 17
make macos-jacobian-walk-bench
./macos/rck_macos jacobian-walk-bench --iterations 256 --min-ms 50 --jumps 16
./macos/rck_macos jacobian-kangaroo-small --range 8 --start 0 --pubkey 025CBDF0646E5DB4EAA398F365F2EA7A0E3D419B7E0330E39CE92BDDEDCAC4F9BC --jumps 8 --dp-bits 0 --max-steps 4096
./macos/rck_macos jacobian-kangaroo-multi-small --range 8 --start 2 --targets tests/jacobian_kangaroo_multi_targets.txt --jumps 8 --dp-bits 0 --max-steps 4096
make macos-jacobian-kangaroo-small-bench
make macos-jacobian-kangaroo-multi-small-bench
./macos/rck_macos cpu-field-test
make macos-cpu-field-bench
./macos/rck_macos cpu-field-bench --iterations 4096 --min-ms 50
./macos/rck_macos metal-smoke
./macos/rck_macos metal-field-test
make macos-metal-field-bench
make macos-metal-target-lookup-bench
./macos/rck_macos metal-target-lookup-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500
make macos-metal-target-lookup-compact-bench
./macos/rck_macos metal-target-lookup-compact-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500
make macos-metal-target-lookup-tag32-bench
./macos/rck_macos metal-target-lookup-tag32-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500
make macos-metal-target-lookup-tag32-persistent-bench
./macos/rck_macos metal-target-lookup-tag32-persistent-bench --target-count 1048576 --query-count 1048576 --hits 4096 --min-ms 500
./macos/rck_macos target-lookup-tag32-cpu-bench --target-count 25005000 --query-count 1057 --hits 64 --min-ms 50
./macos/rck_macos target-lookup-tag32-parity-parallel-insert-bench --target-count 25005000 --injected-count 128 --iterations 1
./macos/rck_macos metal-field-sub-test
make macos-metal-field-sub-bench
./macos/rck_macos metal-field-double-test
make macos-metal-field-double-bench
./macos/rck_macos metal-field-mul4-test
make macos-metal-field-mul4-bench
./macos/rck_macos metal-field-neg-test
make macos-metal-field-neg-bench
./macos/rck_macos metal-field-mul-test
make macos-metal-field-mul-bench
./macos/rck_macos metal-field-square-test
make macos-metal-field-square-bench
python3 autoresearch/runner.py --experiment baseline --budget-sec 5
python3 autoresearch/runner.py --experiment point_add_g --budget-sec 5
python3 autoresearch/runner.py --experiment jacobian_point_add_g --budget-sec 5
python3 autoresearch/runner.py --experiment jacobian_batch_affine --budget-sec 5
python3 autoresearch/runner.py --experiment jacobian_jump_walk --budget-sec 5
python3 autoresearch/runner.py --experiment jacobian_kangaroo_small --budget-sec 5
python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi_small --budget-sec 5
python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi_small --budget-sec 5 --paired-baseline-ref main
python3 autoresearch/runner.py --experiment jacobian_kangaroo_multi16_small --budget-sec 5
python3 autoresearch/runner.py --experiment cpu_field_mul --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_add --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_sub --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_double --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_mul4 --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_neg --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_mul --budget-sec 5
python3 autoresearch/runner.py --experiment metal_field_square --budget-sec 5
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_compact_dp --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_dp8 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_count_dp8 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_target_lookup_exact256 --budget-sec 10
python3 autoresearch/runner.py --experiment metal_target_lookup_compact_exact256 --budget-sec 10 --paired-baseline-ref main
python3 autoresearch/runner.py --experiment metal_target_lookup_tag32_exact256 --budget-sec 10 --paired-baseline-ref main
./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-chain-bench --iterations 262144 --steps 512 --packets 2 --jumps 16 --dp-bits 8 --min-ms 500
python3 autoresearch/runner.py --experiment metal_jacobian_dynamic_dp_stream_xyzz_chain_steps512 --budget-sec 120
```

The default macOS build enables ThinLTO (`MACOS_LTO_FLAGS=-flto=thin`) so clang can optimize the small Jacobian and field-arithmetic call graph across translation units on Apple Silicon. Disable it for toolchain debugging or generic compile checks with `make macos-check MACOS_LTO_FLAGS=`.

## Benchforge Metal Lab

This repository includes a Benchforge challenge for the Apple Silicon Metal
track. It records local runs, notes, replayable candidate bundles, verifier
JSON, and a static leaderboard.

Initialize the Benchforge submodule:

```sh
git submodule update --init tools/benchforge
```

Run the local lab:

```sh
make benchforge-rckmetal-doctor
make benchforge-rckmetal-run
make benchforge-rckmetal-submit
make benchforge-rckmetal-leaderboard
make benchforge-rckmetal-report
```

Challenge docs:

- English: `challenges/rckmetal/README.md`
- Italiano: `challenges/rckmetal/README.it.md`
- Shared notes: `challenges/rckmetal/NOTES.md`

Local or accepted Benchforge results are not public proof. Use `verified`,
`promoted`, or `replicated` only after an independent trusted runner reproduces
the result on a declared hardware track.

The CPU field multiplication benchmark reports `carry_impl=clang_builtin` on Apple Clang, where modular add/sub carry chains use `__builtin_addcll` and `__builtin_subcll`; non-Clang builds keep the portable `unsigned __int128` fallback. The Jacobian walk and tiny kangaroo benchmarks also report `ecint_carry_impl`; on supported non-x86 Clang builds this is `clang_builtin` because the shared `EcInt` carry/borrow wrappers use the same builtins, while x86/platform-intrinsic and non-Clang builds report `platform_intrinsic_or_uint128`. `ecint_mul_final_sub=single_conditional` records that the final `MulModP` reduction subtracts `P` with one conditional subtract after the carry is known.

The macOS `jacobian-batch-affine-bench` command isolates the Jacobian batch-to-affine conversion used by the multi-target kangaroo loop and reports batch conversions per second plus affine points per second. It records `field_rhs_passing=const_ref`, `affine_z_access=const_ref`, `affine_z_check=infinity_flag`, `affine_field_ops=inplace`, `affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`, `affine_reverse_loop=split_zero`, and `affine_tail_update=skip_final` so autoresearch can separate field-copy, z-validity, field-op temporaries, buffer-reuse, all-active batch-path, split reverse-loop handling, and final-tail update changes. The `jacobian-kangaroo-small` and `jacobian-kangaroo-multi-small` commands are tiny-range CPU architecture probes. The single-target solver records distinguished points in a reusable x-plus-y-parity point-key open-addressed table with inline-first DP storage, batch-converts its tame/wild Jacobian pair to affine with one inversion per loop, and reports `field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`, `ecint_carry_impl`, `ecint_mul_final_sub`, `dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `candidate_verification=full_point_collision`, `dp_reserve=sqrt_range_estimate`, `dp_capacity=max_load_2of3`, `dp_bucket_storage=inline_first`, `dp_clear=empty_guard`, `point_passing=const_ref`, `affine_conversion=batch`, and `dp_count`; its benchmark precomputes the deterministic jump table once per run (`jump_table=precomputed`), masks the jump index for power-of-two jump counts (`jump_index=power2_mask`, falling back to `modulo` otherwise), precomputes the range/tame-start context once per run (`range_context=precomputed`), reuses scratch storage across measured solves (`scratch=reused`), and measures deterministic single-target solves per second. The multi-target solver runs one shared tame walk plus one wild walk per target, batch-converts tame/wild Jacobian states to affine with one inversion per loop, avoids point copies in hot checks (`point_passing=const_ref`), passes field RHS and Jacobian step points by const reference (`field_rhs_passing=const_ref`, `jacobian_step_passing=const_ref`), and reports `architecture=shared_tame`, `ecint_carry_impl`, `ecint_mul_final_sub`, `dp_lookup=open_address_linear`, `dp_hash=partial_limb_mix`, `dp_key=x_parity`, `candidate_verification=full_point_collision`, `dp_reserve=sqrt_range_estimate`, `dp_capacity=max_load_2of3`, `dp_bucket_storage=inline_first`, `dp_clear=empty_guard`, `affine_conversion=batch`, `affine_z_access=const_ref`, `affine_z_check=infinity_flag`, `affine_field_ops=inplace`, `affine_buffer=resize_reuse`, `affine_active_path=all_active_fast`, `affine_reverse_loop=split_zero`, `affine_tail_update=skip_final`, and target/walk-state counts. The DP hash mixes a few high-entropy point limbs for the open-address probe start while keeping compressed affine point identity (`x` plus `y` parity) as the equality key; a cross-side full-point collision plus range and target-index checks proves the candidate without re-multiplying it by `G`. The DP reserve starts from a sqrt(range) kangaroo-step estimate, applies `dp_bits`, targets a denser two-thirds max load, and still rehashes if a run needs more slots. The matching multi benchmarks also precompute the same jump table and range context once per run, reuse scratch storage across measured solves, generate deterministic synthetic targets, measure shared-tame solves per second for fixed target counts of 4 and 16, and report `single_target_ops_per_sec`, `speedup_vs_single`, and `target_throughput_vs_single`.

Tiny CPU kangaroo solvers also report `affine_initial_conversion=unit_z_copy`. This records the step-zero fast path: freshly initialized Jacobian tame/wild states have `Z=1`, so their first affine view copies `x/y` directly; subsequent steps keep the normal `affine_conversion=batch` path and all existing collision oracles.

The macOS Metal target lookup benchmark isolates the exact multi-target join needed after packet-boundary affine DP extraction. `metal-target-lookup-bench` builds a deterministic open-addressed table keyed by full affine `x` plus `y` parity (`target_key=x256_y_parity`, `lookup_layout=open_address_exact256`) and validates known hit/miss queries with exact key equality. `metal-target-lookup-compact-bench` keeps full-key equality but stores `hash64 + target_index` buckets, and `metal-target-lookup-tag32-bench` uses an 8-byte `tag32 + target_index` bucket with the full target key in a separate array. `metal-target-lookup-tag32-persistent-bench` runs the same Metal kernel with device buffers and pipeline reused across dispatches; it reports both `metal_setup_seconds` and `dispatch_seconds` so setup cost is visible instead of hidden. `metal-target-lookup-tag16-filter-persistent-bench` keeps only a 2-byte high-hash tag in the resident GPU filter and then verifies every compact positive on CPU with exact `x256 + y_parity` equality; this can introduce harmless false positives, which are reported explicitly. `metal-target-lookup-tag16-hash-filter-persistent-bench` keeps the same exact verification and tag16 filter but sends precomputed 64-bit query hashes to Metal, reducing query-side GPU bandwidth and hash work while still resolving all positives against full keys on CPU. `target-lookup-tag32-cpu-bench` runs the same exact tag32 lookup on the host CPU, which is useful on Apple Silicon when a huge target table produces only a small DP query batch. `target-lookup-tag32-parity-parallel-insert-bench` measures the x-only plus encoded-parity tag32 builder used by the fixed-round distinct-miss path and verifies every inserted synthetic target through the same parity lookup oracle; use it for target-build tuning instead of the older full-key tag32 builder when the integrated path reports `lookup_query_mode=distinct_misses`. The integrated affine-scan target-lookup command keeps the GPU lookup default, but accepts `--lookup-engine cpu`, `--lookup-engine gpu-filter`, `--lookup-engine gpu-filter16-hash`, or repeat-mode-only `--lookup-engine gpu-filter16-hash-repeat` to route only the final exact target join while preserving the same hit/miss oracle and checksum; `--lookup-engine auto` now promotes large repeat-mode joins to `gpu_filter16_hash_repeat` when the target table is at least the large-target threshold and the logical repeated query count is at least 16,000,000. The tag16-hash integrated paths report `query_input=hash64` or `query_input=hash64_repeat_indexed` and `target_query_hash_bytes`; repeat-indexed exact resolution verifies compact positives without materializing the full repeated miss vector, and caches exact full-key results per repeated base query while still counting every logical repeated hit or false positive. In repeat mode, fitting 16-bit base/repeat dimensions use a packed positive-index fast path that avoids resolver-side logical-index division; larger integrated sparse-repeat shapes emit `base_query_count_repeated` base-count positives: the GPU still probes every logical repeat, while the CPU resolver receives per-base counts and still accounts every logical repeated hit or false positive. The fixed-round repeat benchmark uses the same base-count output path for large standard tag16 repeat batches, while still building distinct deterministic round starts, batching those starts through one larger Metal walk dispatch, splitting the results back into per-round affine scans, reusing one target table/filter, and validating the exact repeated checksum oracle. The base-count Metal kernel groups work by base DP query and reduces positives inside each threadgroup before global atomics, so it preserves logical probes while reducing atomic pressure on Apple Silicon. Full-output paths keep logical indices. JSON records the chosen path as `repeat_positive_index_encoding`. The fixed-round benchmark also accepts `--lookup-query-mode distinct-misses`: it keeps the real DP keys once, fills the remaining physical query batch with deterministic misses verified against the compact x-only-plus-parity target table, probes every physical query with the non-repeat tag16 hash-filter kernel, resolves positives with exact `x256 + y_parity` equality, and validates explicit expected indices. The diagnostic `--lookup-filter-mode tag16-mix` is supported on this distinct path too, but it remains non-default after the M3 25M gate measured more false positives and no speed win. Use distinct-misses to check whether repeat-mode gains survive a mostly-miss DP stream. `--lookup-repeat-mode dedup` remains a separate non-default diagnostic: it filters each base DP query once, expands exact outputs back to the same logical repeat oracle, and reports `physical_query_count` plus `physical_filter_positive_count`, so it is an honest upper-bound probe for repeated batches rather than a distinct-query throughput claim. All variants report `lookups_per_sec`, `target_table_bytes`, `bytes_per_target`, `hit_count`, `miss_count`, and `target_lookup_checksum`; these are not per-step kangaroo throughput, but they tell whether a large target set can be joined cheaply at DP boundaries without probabilistic shortcuts.

Fixed-round `distinct-misses` also reports `distinct_miss_source_seconds` and includes it in `setup_inclusive_seconds` and `setup_inclusive_wall_seconds`. This is the host time used to validate compact deterministic miss sources and prepare the GPU hash-filter pass, so setup-inclusive metrics are the honest score for these probes. When a fused tag16 filter exists, the miss-source builder uses it as a host prefilter before exact `x256 + y_parity` checks; Bloom64 and filterless paths keep the original exact-check behavior. After primary misses are exact-validated, the default Metal path sends only real DP-prefix hashes and generates deterministic suffix miss hashes in the GPU filter kernel (`query_input=hash64_prefix_gpu_miss`); if validation ever finds a primary miss that is an exact target, it falls back to the raw physical hash buffer and retry-source path. The default resolver trusts those already-validated compact miss sources, exact-checks only real DP-prefix positives, and does not retain the compact miss-source payload array; set `RCK_STRICT_DISTINCT_MISS_RESOLVE=1` to force the older full exact audit for every filter-positive compact miss while comparing checksums or debugging source-generation changes.

For large fixed-round standard tag16 base-count repeat batches, the exact host table stores only affine `x` in the target key array and encodes `y` parity in the tag32 bucket index. This reduces `target_key_bytes` on the 25M-target gate while preserving exact `x256 + y_parity` resolution; verify `target_lookup_checksum`, `hit_count`, `filter_false_positive_count`, and `repeat_positive_index_encoding=base_query_count_repeated` before reading speed fields.

The standard integrated repeat path also accepts diagnostic `--lookup-filter-mode tag16-mix`; it keeps exact verification and fused setup but remains non-default after the M3 setup-inclusive gate discarded it.

For the 25M repeat-mode gate, the explicit `steps=2048, dp_bits=6, lookup_repeat=1024` autoresearch recipe now scores `setup_inclusive_ops_per_sec` against the accepted `steps=1024, dp_bits=7, lookup_repeat=1024` path, so target setup cost is not hidden.
On the local M3, the same 2048/dp6 repeat-mode gate also has an accepted schedule probe using `--jumps 4 --jump-schedule scaled4-balanced` against the 16-jump `power2` baseline; it keeps the exact target checksum and false-positive counters visible.

More details:

- English: `macos/README.md`
- Italiano: `macos/README.it.md`

## Original limitations

This remains a proof-of-concept style GPU solver. It does not add networking, distributed coordination, checkpointing of all DPs, or a full Apple GPU kangaroo backend yet.

## Changelog

### RCKangaroo-MT

- Added `-targets` multi-target mode.
- Added target-file loader and target offset mapping.
- Added GPU-side target id output for distinguished points.
- Added multi-target collision verification and target-aware result output.
- Added macOS target preparation, CPU oracle, CPU field arithmetic, Metal smoke, and Metal field-add/field-sub/field-double/field-mul4/field-neg/field-mul/field-square tools.
- Added host-only parser checks and fixed-gate autoresearch experiments.

### Upstream v3.1

- Fixed "gpu illegal memory access" bug.
- Small improvements.

### Upstream v3.0

- Added `-tames` and `-max` options.
- Fixed bugs.

### Upstream v2.0

- Added support for 30xx, 20xx, and 1xxx cards.
- Minor changes.

### Upstream v1.1

- Added ability to start software on 30xx cards.

### Upstream v1.0

- Initial release.
