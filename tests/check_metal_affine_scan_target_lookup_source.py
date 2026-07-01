from pathlib import Path
import json


root = Path(".")
kernels = (root / "macos" / "MetalField.mm").read_text(encoding="utf-8")
metal_kernels = (root / "macos" / "MetalFieldKernels.h").read_text(encoding="utf-8")
header = (root / "macos" / "MetalField.h").read_text(encoding="utf-8")
cli = (root / "macos" / "rck_macos.cpp").read_text(encoding="utf-8")
makefile = (root / "Makefile").read_text(encoding="utf-8")

markers = [
    "RCKMetalJacobianDynamicDpStreamXyzzAffineScanTargetLookupTag32BenchJson",
    "jacobian_affine_scan_target_lookup_tag32",
    "affine_dp_scan_target_lookup",
    "lookup_repeat",
    "lookup_query_mode",
    "dedup_repeat",
    "lookup_engine",
    "lookup_engine_effective",
    "ChooseAffineLookupEngine",
    "lookup_threadgroup_limit",
    "ChooseAffineLookupThreadgroupLimit",
    "dp_query_count",
    "target_lookup_checksum",
    "round_sample_build_seconds",
    "BuildJacobianSampleAt",
    "BuildJacobianPointSamplesFrom",
    "InjectedHashFilter",
    "BuildInjectedHashFilter",
    "TargetLookupHashMatchesInjectedFiltered",
    "RunTargetLookupTag32Kernel",
    "RunTargetLookupTag32FilterKernel",
    "RunTargetLookupTag16HashFilterKernel",
    "RunTargetLookupTag16HashFilterRepeatKernel",
    "RunTargetLookupTag16HashFilterRepeatBaseCountKernel",
    "RunTargetLookupTag32HashFilterRepeatKernel",
    "NewSharedMetalBufferNoCopyFallback",
    "newBufferWithBytesNoCopy",
    "RCK_METAL_DISABLE_NOCOPY",
    "ResolveTargetLookupTag32FilterCandidates",
    "ResolveTargetLookupTag32FilterRepeatCandidates",
    "ResolveTargetLookupTag32FilterRepeatPackedCandidates",
    "ResolveTargetLookupTag32FilterRepeatSparseExpected",
    "ResolveTargetLookupTag32FilterRepeatBaseCountsExpected",
    "ResolveTargetLookupTag32FilterRepeatBaseCountsExpectedIndices",
    "TargetLookupXOnlyHost",
    "TargetLookupXOnlyHostBuffer",
    "AllocateTargetLookupXOnlyBuffer",
    "TargetLookupTag32ParityBucketHost",
    "InsertTargetLookupTag32ParityBucket",
    "BuildTargetLookupTag32ParityTableFromKeysParallelInsert",
    "ResolveTargetLookupTag32ParityFilterCandidates",
    "ResolveTargetLookupTag32ParityFilterDistinctExpected",
    "ResolveTargetLookupTag32ParityFilterRepeatBaseCountsExpectedIndices",
    "DecodeTargetLookupParity(bucket.encoded_target_index) == (key.parity & 1U)",
    "ValidateAffineTargetLookupDedupRepeatOutputsWithExpected",
    "ValidateAffineTargetLookupRepeatBaseCountsWithExpected",
    "lookup_distinct_misses",
    "lookup_uses_distinct_misses",
    "physical_query_index",
    "ValidateAffineTargetLookupSparseRepeatOutputs",
    "ValidateDistinctTargetLookupSparseOutputsWithExpected",
    "use_base_exact_cache",
    "base_positive_counts",
    "use_base_repeat_positive_counts",
    "sparse repeat target lookup unexpected exact hit at base query",
    "rounds repeat base-count resolver",
    "total_round_samples",
    "batched_round_p",
    "CpuXyzzBatchAffineDpScanRange",
    "ValidateDynamicXyzzStateDistanceOutputsRange",
    "RunTargetLookupTag32Cpu",
    "ValidateAffineTargetLookupOutputs",
    "\"gpu_filter\"",
    "\"gpu_filter16_hash\"",
    "\"gpu_filter16_mix_hash\"",
    "\"gpu_filter16_hash_repeat\"",
    "\"gpu_filter16_mix_hash_repeat\"",
    "\"gpu_filter32_hash_repeat\"",
    "NormalizeAffineLookupFilterModeName",
    "lookup_filter_mode_name",
    "tag16-mix lookup filter mode requires gpu_filter16_hash_repeat effective engine",
    "BuildTargetLookupTag32FilterTable",
    "BuildTargetLookupTag16FilterTable",
    "BuildTargetLookupTag32FilterTableFromTag32Buckets",
    "BuildTargetLookupTag16FilterTableFromTag32Buckets",
    "BuildTargetLookupTag16MixedFilterTableFromTag32Buckets",
    "fuse_tag16_filter ? &target_filter16_buckets : NULL",
    "target_filter16_buckets.empty()",
    "BuildTargetLookupQueryHashes",
    "BuildTargetLookupQueryHashesParallel",
    "BuildRepeatedTargetLookupQueryHashes",
    "target_lookup_tag16_hash_filter_repeat2d256",
    "target_lookup_tag16_hash_filter_repeat_base2d256",
    "target_lookup_tag16_hash_filter_repeat_base_count_by_base2d256",
    "target_lookup_tag16_mixed_hash_filter256",
    "target_lookup_bloom64_hash_filter256",
    "target_lookup_tag16_mixed_hash_filter_repeat_base_count2d256",
    "target_lookup_tag16_hash_filter_repeat_packed2d256",
    "target_lookup_tag16_mixed_hash_filter_repeat2d256",
    "target_lookup_tag16_mixed_hash_filter_repeat_packed2d256",
    "target_lookup_tag32_hash_filter_repeat2d256",
    "target_lookup_tag32_hash_filter_repeat_packed2d256",
    "base_query_hashes",
    "pack_repeat_positive_indices",
    "base_repeat_positive_counts",
    "repeat_positive_index_encoding",
    "packed16_base_repeat",
    "base_query_count_repeated",
    "sparse repeat target lookup unexpected exact hit",
    "base_query_index",
    "hash64_dedup_repeat_base",
    "physical_query_count",
    "physical_filter_positive_count",
    "lookup_repeat_dedup",
    "jacobian_affine_walk_dynamic_xyzz_steps2048_pow2_u32_distance",
    "jacobian_affine_walk_dynamic_xyzz_steps4096_pow2_u32_distance",
    "packed repeat tag16 hash-filter dimensions exceed 16-bit encoding",
    "kMinParallelTargetLookupHashQueries",
    "ParallelForSamples(queries.size()",
    "\\\"lookup_layout\\\":\\\"open_address_tag16_hash_filter_exact256\\\"",
    "open_address_tag16_mix_hash_filter_exact256",
    "blocked_bloom64_hash_filter_exact256",
    "open_address_tag32_hash_filter_exact256",
    "\\\"candidate_verification\\\":\\\"tag16_hash_filter_then_cpu_exact_key_equality\\\"",
    "tag16_mix_hash_filter_then_cpu_exact_key_equality",
    "bloom64_hash_filter_then_cpu_exact_key_equality",
    "tag32_hash_filter_then_cpu_exact_key_equality",
    "\\\"query_input\\\":\\\"hash64\\\"",
    "\\\"target_query_hash_bytes\\\":",
    "\\\"lookup_hash_seconds\\\":",
    "\\\"lookup_gpu_seconds\\\":",
    "\\\"lookup_exact_seconds\\\":",
    "\\\"walk_wall_seconds\\\":",
    "\\\"walk_buffer_seconds\\\":",
    "\\\"lookup_wall_seconds\\\":",
    "\\\"lookup_buffer_seconds\\\":",
    "\\\"target_build_seconds\\\":",
    "\\\"target_filter_build_seconds\\\":",
    "\\\"setup_inclusive_seconds\\\":",
    "\\\"setup_inclusive_wall_seconds\\\":",
    "\\\"setup_inclusive_ops_per_sec\\\":",
    "\\\"setup_inclusive_wall_ops_per_sec\\\":",
    "\\\"mean_jump_distance\\\":",
    "\\\"gpu_distance_per_sec\\\":",
    "\\\"distance_per_sec\\\":",
    "\\\"setup_inclusive_distance_per_sec\\\":",
    "\\\"setup_inclusive_wall_distance_per_sec\\\":",
    "if (jump_count != 4)\n\t\t\treturn 0.0;",
    "\\\"gpu_lookup_lookups_per_sec\\\":",
    "filter_positive_count",
    "filter_false_positive_count",
    "lookup_hash_seconds += hash_seconds",
    "lookup_gpu_seconds += filter_seconds",
    "lookup_exact_seconds += exact_seconds",
    "lookup_gpu_lookups_per_sec",
    "target_build_seconds += std::chrono::duration<double>",
    "target_filter_build_seconds += std::chrono::duration<double>",
]
for marker in markers:
    if marker not in kernels:
        raise SystemExit("missing affine-scan target-lookup host marker: " + marker)

if "bool* no_copy_used = NULL" not in kernels or "*no_copy_used = true;" not in kernels:
    raise SystemExit("no-copy Metal buffer helper should report whether fallback copied storage")

target_lookup_start = kernels.index(
    "std::string RCKMetalJacobianDynamicDpStreamXyzzAffineScanTargetLookupTag32BenchJson"
)
target_lookup_end = kernels.index("std::string RCKMetalJacobianDynamicDpCountBenchJson", target_lookup_start)
target_lookup_body = kernels[target_lookup_start:target_lookup_end]
if "dp_distances" in target_lookup_body:
    raise SystemExit("integrated affine-scan target lookup should not materialize unused DP distances")
if "scan_reason, &dp_keys)" not in target_lookup_body:
    raise SystemExit("integrated affine-scan target lookup should request only DP keys from the affine scan")
if "lookup_expected_indices" in target_lookup_body:
    raise SystemExit("integrated affine-scan target lookup should validate expected indices on the fly")
if "fill_reason" in target_lookup_body:
    raise SystemExit("integrated filter lookup should not run a second unmeasured exact-output fill pass")
if "id % base_query_count" in kernels:
    raise SystemExit("repeat-indexed tag16 hash lookup should use the 2D grid instead of per-thread modulo")
integrated_filter_resolve_false = (
    "ResolveTargetLookupTag32FilterCandidates(target_buckets, target_keys, "
    "lookup_queries, positive_query_indices, local_filter_positive_count, "
    "out_indices, local_hit_count, local_false_positive_count, resolve_reason, false)"
)
integrated_filter_resolve_true = integrated_filter_resolve_false.replace(
    "resolve_reason, false)", "resolve_reason, true)"
)
if integrated_filter_resolve_false in target_lookup_body:
    raise SystemExit("integrated filter lookup should resolve exact positives with output fill in one measured pass")
if target_lookup_body.count(integrated_filter_resolve_true) < 2:
    raise SystemExit("integrated filter lookup should use one measured exact-output fill pass per filter engine")
repeat_hash_branch = (
    'if (strcmp(lookup_query_mode_name, "repeat") == 0)\n'
    '\t\t\t\tBuildRepeatedTargetLookupQueryHashes(dp_keys, lookup_repeat, lookup_query_hashes);\n'
    "\t\t\telse\n"
    "\t\t\t\tBuildTargetLookupQueryHashesParallel(lookup_queries, lookup_query_hashes);"
)
if repeat_hash_branch not in target_lookup_body:
    raise SystemExit("repeat-mode gpu-filter16-hash should reuse base DP query hashes and keep other modes on full query hashing")
if "ResolveTargetLookupTag32FilterRepeatSparseExpected(target_buckets, target_keys, dp_keys" not in target_lookup_body:
    raise SystemExit("repeat-indexed integrated lookup should resolve exact positives sparsely without materializing repeated misses")
if "ValidateAffineTargetLookupSparseRepeatOutputs(dp_keys.size(), injected_hits, lookup_repeat" not in target_lookup_body:
    raise SystemExit("repeat-indexed integrated lookup should validate sparse repeat outputs against the checksum oracle")
if "filter_positive_count > base_query_count" not in kernels or "base_positive_counts(base_query_count" not in kernels:
    raise SystemExit("sparse repeat exact resolver should aggregate positives per repeated base query")
if "double setup_inclusive_seconds = round_sample_build_seconds + walk_seconds + affine_scan_seconds + lookup_seconds + target_build_seconds + target_filter_build_seconds;" not in kernels:
    raise SystemExit("setup-inclusive seconds should include fixed-round sample generation time")
if "double setup_inclusive_wall_seconds = round_sample_build_seconds + effective_walk_wall_seconds + affine_scan_seconds + effective_lookup_wall_seconds + target_build_seconds + target_filter_build_seconds;" not in kernels:
    raise SystemExit("setup-inclusive wall seconds should include fixed-round sample generation time")

rounds_start = kernels.index(
    "std::string RCKMetalJacobianDynamicDpStreamXyzzAffineScanTargetLookupTag32RoundsBenchJson"
)
rounds_end = kernels.index("std::string RCKMetalJacobianDynamicDpCountBenchJson", rounds_start)
rounds_body = kernels[rounds_start:rounds_end]
if "RunTargetLookupTag16HashFilterRepeatBaseCountKernel(target_filter16_buckets, lookup_query_hashes, dispatch_query_count" not in rounds_body:
    raise SystemExit("fixed-round repeat lookup should route large standard tag16 repeat batches through base-count positives")
if "RunTargetLookupTag16HashFilterKernel(target_filter16_buckets, lookup_query_hashes, positive_query_indices" not in rounds_body:
    raise SystemExit("fixed-round distinct-misses lookup should use the physical non-repeat tag16 hash-filter kernel")
if "use_tag16_mixed_hash_filter" not in rounds_body:
    raise SystemExit("fixed-round distinct-misses lookup should preserve the tag16-mix filter choice")
if "BuildTargetLookupTag32ParityTableFromKeysParallelInsert(injected_keys, target_count, target_x_keys, target_x_key_count, target_parity_buckets, error, fuse_tag16_filter ? &target_filter16_buckets : NULL, use_tag16_mixed_hash_filter, use_bloom64_hash_filter ? &target_bloom64_filter_words : NULL)" not in rounds_body:
    raise SystemExit("fixed-round distinct-misses lookup should fuse standard or mixed tag16 filters into the compact parity table")
if "RunTargetLookupTag16HashFilterKernel(target_filter16_buckets, lookup_query_hashes, positive_query_indices, local_filter_positive_count, error, &filter_seconds, effective_lookup_threadgroup_limit, &lookup_stats, use_tag16_mixed_hash_filter)" not in rounds_body:
    raise SystemExit("fixed-round distinct-misses lookup should pass the mixed tag selector to the non-repeat hash-filter kernel")
if "RunTargetLookupBloom64HashFilterKernel(target_bloom64_filter_words, lookup_query_hashes, positive_query_indices" not in rounds_body:
    raise SystemExit("fixed-round bloom64 distinct-misses lookup should use the physical non-repeat bloom64 hash-filter kernel")
if 'lookup_distinct_misses ?\n\t\t(use_bloom64_hash_filter ? "gpu_filter_bloom64_hash" :' not in rounds_body:
    raise SystemExit("fixed-round distinct-misses should report standard versus mixed tag16 hash engines separately")
if "lookup_uses_tag16_mixed_hash_repeat_filter" not in kernels:
    raise SystemExit("JSON query_input reporting should distinguish mixed hash repeat from mixed hash distinct")
if "fixed-round distinct-misses currently supports tag16 hash filters only" not in rounds_body:
    raise SystemExit("fixed-round distinct-misses should reject only tag32 filters")
if "fixed-round bloom64 filter currently requires distinct-misses query mode" not in rounds_body:
    raise SystemExit("fixed-round bloom64 filter should be guarded to physical distinct-miss mode")
if "fixed-round distinct-misses currently supports the standard tag16 hash filter only" in rounds_body:
    raise SystemExit("fixed-round distinct-misses should no longer reject tag16-mix")
if "ValidateDistinctTargetLookupSparseOutputsWithExpected(aggregate_expected_indices, physical_query_count" not in rounds_body:
    raise SystemExit("fixed-round distinct-misses lookup should validate physical query outputs against sparse expected indices")
if "distinct_expected_indices" in rounds_body:
    raise SystemExit("fixed-round distinct-misses lookup should not materialize physical expected miss indices")
if 'repeat_positive_index_encoding = lookup_distinct_misses ? "physical_query_index"' not in rounds_body:
    raise SystemExit("fixed-round distinct-misses lookup should report physical query index positives")
if "RunJacobianDynamicXyzzDistanceKernel(batched_round_p, jumps, jump_distances" not in rounds_body:
    raise SystemExit("fixed-round target lookup should batch distinct round walks into one Metal dispatch")
if 'lookup_repeat_dedup ? "base_query_index" :' not in rounds_body:
    raise SystemExit("fixed-round repeat lookup should report its positive index encoding")
if 'ValidateAffineTargetLookupRepeatBaseCountsWithExpected(aggregate_expected_indices, lookup_repeat' not in rounds_body:
    raise SystemExit("fixed-round base-count repeat lookup should preserve the repeated checksum oracle")
if "use_parity_xonly_target_table = use_base_repeat_positive_counts || lookup_distinct_misses" not in rounds_body:
    raise SystemExit("fixed-round x-only target table should cover base-count repeat and physical distinct-miss paths")
if "target_x_key_count * sizeof(TargetLookupXOnlyHost)" not in rounds_body:
    raise SystemExit("fixed-round x-only target table should report compact target key bytes")
if "BuildTargetLookupTag32ParityTableFromKeysParallelInsert(injected_keys, target_count, target_x_keys, target_x_key_count, target_parity_buckets" not in rounds_body:
    raise SystemExit("fixed-round base-count repeat lookup should build the x-only parity target table")
if "ResolveTargetLookupTag32ParityFilterRepeatBaseCountsExpectedIndices(target_parity_buckets, target_x_keys.get(), target_x_key_count" not in rounds_body:
    raise SystemExit("fixed-round base-count repeat lookup should exact-resolve against x plus encoded parity")
if "ResolveTargetLookupTag32ParityFilterDistinctExpected(target_parity_buckets, target_x_keys.get(), target_x_key_count, distinct_lookup_queries" not in rounds_body:
    raise SystemExit("fixed-round distinct-misses lookup should exact-resolve against x plus encoded parity with sparse expected indices")
if "BuildJacobianPointSamplesFrom((uint64_t)round * (uint64_t)sample_count, sample_count, p);" not in rounds_body:
    raise SystemExit("fixed-round setup should avoid generating discarded affine q samples after round zero")
if "ignored_q" in rounds_body:
    raise SystemExit("fixed-round setup should not generate discarded affine q samples")
if "std::vector<CpuJacobianPoint> p(batched_round_p.begin()" in rounds_body:
    raise SystemExit("fixed-round per-round validation should not copy jacobian input slices")
if "std::vector<CpuXyzzPoint> state_out(batched_state_out.begin()" in rounds_body:
    raise SystemExit("fixed-round affine scan should not copy XYZZ output slices")
if "std::vector<uint64_t> distances_out(batched_distances_out.begin()" in rounds_body:
    raise SystemExit("fixed-round affine scan should not copy distance output slices")
if "CpuXyzzBatchAffineDpScanRange(round_state_out, round_distances_out, sample_count" not in rounds_body:
    raise SystemExit("fixed-round affine scan should use range views into the batched Metal output")
if "ValidateDynamicXyzzStateDistanceOutputsRange(round_p, sample_count" not in rounds_body:
    raise SystemExit("fixed-round validation should use range views into the batched Metal output")

distance_kernel_start = kernels.index("static bool RunJacobianDynamicXyzzDistanceKernel")
distance_kernel_end = kernels.index("static bool RunJacobianDynamicDpStreamXyzzPersistentChainKernel", distance_kernel_start)
distance_kernel_body = kernels[distance_kernel_start:distance_kernel_end]
if "bool p_no_copy = false;" not in distance_kernel_body or "bool p_inf_no_copy = false;" not in distance_kernel_body:
    raise SystemExit("fixed-round XYZZ distance wrapper should track no-copy fallback status")
if "NewSharedMetalBufferNoCopyFallback(device, p_xyzz.data(), p_bytes, &p_no_copy)" not in distance_kernel_body:
    raise SystemExit("fixed-round XYZZ distance wrapper should avoid the initial full p_xyzz Metal buffer copy")
if "NewSharedMetalBufferNoCopyFallback(device, dynamic_p_infinity.data(), p_inf_bytes, &p_inf_no_copy)" not in distance_kernel_body:
    raise SystemExit("fixed-round XYZZ distance wrapper should avoid the initial p_infinity Metal buffer copy")
if "if (!p_no_copy)\n\t\t\tmemcpy(p_xyzz.data(), [p_buffer contents], p_bytes);" not in distance_kernel_body:
    raise SystemExit("fixed-round XYZZ distance fallback should copy p_xyzz back only when no-copy was unavailable")
if "if (!p_inf_no_copy)\n\t\t\tmemcpy(dynamic_p_infinity.data(), [p_inf_buffer contents], p_inf_bytes);" not in distance_kernel_body:
    raise SystemExit("fixed-round XYZZ distance fallback should copy infinity flags back only when no-copy was unavailable")
if "distances_out = std::move(distances);" not in distance_kernel_body:
    raise SystemExit("fixed-round XYZZ distance wrapper should move packet distances instead of copying them")

if "kernel void target_lookup_tag16_mixed_hash_filter256" not in metal_kernels:
    raise SystemExit("missing non-repeat mixed tag16 hash-filter Metal kernel")
if "target_lookup_filter_tag16_mixed(hash)" not in metal_kernels:
    raise SystemExit("non-repeat mixed tag16 hash-filter kernel should derive mixed tags from query hashes")
if "kernel void target_lookup_bloom64_hash_filter256" not in metal_kernels:
    raise SystemExit("missing non-repeat bloom64 hash-filter Metal kernel")
if "target_lookup_bloom64_mask(hash)" not in metal_kernels:
    raise SystemExit("bloom64 hash-filter kernel should derive blocked masks from query hashes")

parity_builder_start = kernels.index("static bool BuildTargetLookupTag32ParityTableFromKeysParallelInsert")
parity_builder_end = kernels.index("static void BuildTargetLookupQueries", parity_builder_start)
parity_builder_body = kernels[parity_builder_start:parity_builder_end]
if "std::vector<uint64_t> target_hashes" in parity_builder_body:
    raise SystemExit("x-only parity target builder should not materialize per-target hash temporaries")
if "std::vector<uint8_t> target_parities" in parity_builder_body:
    raise SystemExit("x-only parity target builder should not materialize per-target parity temporaries")
if "target_x_keys.resize" in parity_builder_body:
    raise SystemExit("x-only parity target builder should avoid value-initializing the full target key array")
if "AllocateTargetLookupXOnlyBuffer(target_count)" not in parity_builder_body:
    raise SystemExit("x-only parity target builder should allocate an uninitialized x-only target buffer")
if "InsertTargetLookupTag32ParityBucket(buckets" not in parity_builder_body:
    raise SystemExit("x-only parity target builder should stream bucket insertion while filling target keys")

choose_start = kernels.index("static const char* ChooseAffineLookupEngine")
choose_end = kernels.index("static unsigned int ChooseAffineLookupThreadgroupLimit", choose_start)
choose_body = kernels[choose_start:choose_end]
if '"gpu_filter"' in choose_body:
    raise SystemExit("auto lookup routing should not promote gpu_filter without a kept paired gate")
auto_repeat_branch = (
    'strcmp(lookup_query_mode, "repeat") == 0 &&\n'
    "\t\tlookup_repeat > 1 &&\n"
    "\t\ttarget_count >= kDefaultMetalPersistentTargetLookupLargeTargetThreshold &&\n"
    "\t\tquery_count >= kMinAutoRepeatHashLookupLogicalQueries"
)
if auto_repeat_branch not in choose_body or 'return "gpu_filter16_hash_repeat";' not in choose_body:
    raise SystemExit("auto lookup routing should promote large repeat-mode M3 shapes to the tag16 hash-repeat engine")

if "RCKMetalJacobianDynamicDpStreamXyzzAffineScanTargetLookupTag32BenchJson" not in header:
    raise SystemExit("missing affine-scan target-lookup header declaration")

command = "metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench"
if command not in cli:
    raise SystemExit("missing affine-scan target-lookup CLI command")
if "--lookup-repeat" not in cli:
    raise SystemExit("missing affine-scan target-lookup lookup-repeat CLI option")
if "--lookup-repeat-mode" not in cli:
    raise SystemExit("missing affine-scan target-lookup lookup-repeat-mode CLI option")
if "--lookup-query-mode" not in cli:
    raise SystemExit("missing affine-scan target-lookup lookup-query-mode CLI option")
if "--lookup-engine" not in cli:
    raise SystemExit("missing affine-scan target-lookup lookup-engine CLI option")
if "--lookup-filter-mode" not in cli:
    raise SystemExit("missing affine-scan target-lookup lookup-filter-mode CLI option")
if "--lookup-tg-limit" not in cli:
    raise SystemExit("missing affine-scan target-lookup lookup-tg-limit CLI option")

make_markers = [
    "macos-metal-affine-scan-target-lookup-source-check",
    "macos-metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench",
]
for marker in make_markers:
    if marker not in makefile:
        raise SystemExit("missing affine-scan target-lookup Makefile marker: " + marker)

def check_experiment(path: str, expected_command: list[str], metric: str) -> None:
    experiment = Path(path)
    if not experiment.exists():
        raise SystemExit(f"missing affine-scan target-lookup autoresearch experiment: {path}")

    payload = json.loads(experiment.read_text(encoding="utf-8"))
    if payload.get("bench_command") != expected_command:
        raise SystemExit(f"{path} should run the integrated CLI")
    if payload.get("metric") != metric:
        raise SystemExit(f"{path} should optimize {metric}")
    if int(payload.get("sample_runs", 0)) < 3:
        raise SystemExit(f"{path} should keep sample_runs >= 3")


base_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--target-count",
    "1048576",
    "--hits",
    "64",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32.json",
    base_command,
    "ops_per_sec",
)

bulk1024_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--target-count",
    "1048576",
    "--hits",
    "64",
    "--lookup-repeat",
    "1024",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_bulk1024.json",
    bulk1024_command,
    "lookups_per_sec",
)

distinct1024_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--target-count",
    "1048576",
    "--hits",
    "64",
    "--lookup-repeat",
    "1024",
    "--lookup-query-mode",
    "distinct-misses",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_distinct_misses1024.json",
    distinct1024_command,
    "lookups_per_sec",
)

lookup_tg512_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--target-count",
    "1048576",
    "--hits",
    "64",
    "--lookup-repeat",
    "1024",
    "--lookup-query-mode",
    "distinct-misses",
    "--lookup-engine",
    "gpu",
    "--lookup-tg-limit",
    "512",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_lookup_tg512.json",
    lookup_tg512_command,
    "lookups_per_sec",
)

gpu_filter25m_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--target-count",
    "25005000",
    "--hits",
    "64",
    "--lookup-repeat",
    "1024",
    "--lookup-query-mode",
    "distinct-misses",
    "--lookup-engine",
    "gpu-filter",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32_gpu_filter25m.json",
    gpu_filter25m_command,
    "ops_per_sec",
)

gpu_filter16_hash25m_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--target-count",
    "25005000",
    "--hits",
    "64",
    "--lookup-repeat",
    "1024",
    "--lookup-query-mode",
    "distinct-misses",
    "--lookup-engine",
    "gpu-filter16-hash",
    "--lookup-tg-limit",
    "512",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m.json",
    gpu_filter16_hash25m_command,
    "ops_per_sec",
)

check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_parallel_hash.json",
    gpu_filter16_hash25m_command,
    "lookups_per_sec",
)

gpu_filter16_hash25m_repeat4096_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--target-count",
    "25005000",
    "--hits",
    "64",
    "--lookup-repeat",
    "4096",
    "--lookup-query-mode",
    "distinct-misses",
    "--lookup-engine",
    "gpu-filter16-hash",
    "--lookup-tg-limit",
    "512",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_parallel_hash_repeat4096.json",
    gpu_filter16_hash25m_repeat4096_command,
    "lookups_per_sec",
)

gpu_filter16_hash25m_repeat2048_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--target-count",
    "25005000",
    "--hits",
    "64",
    "--lookup-repeat",
    "2048",
    "--lookup-query-mode",
    "distinct-misses",
    "--lookup-engine",
    "gpu-filter16-hash",
    "--lookup-tg-limit",
    "512",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_parallel_hash_repeat2048.json",
    gpu_filter16_hash25m_repeat2048_command,
    "lookups_per_sec",
)

gpu_filter16_hash25m_repeat_mode2048_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--target-count",
    "25005000",
    "--hits",
    "64",
    "--lookup-repeat",
    "2048",
    "--lookup-query-mode",
    "repeat",
    "--lookup-engine",
    "gpu-filter16-hash",
    "--lookup-tg-limit",
    "512",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_repeat_mode2048.json",
    gpu_filter16_hash25m_repeat_mode2048_command,
    "lookups_per_sec",
)

gpu_filter16_hash25m_repeat_indexed2048_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--target-count",
    "25005000",
    "--hits",
    "64",
    "--lookup-repeat",
    "2048",
    "--lookup-query-mode",
    "repeat",
    "--lookup-engine",
    "gpu-filter16-hash-repeat",
    "--lookup-tg-limit",
    "512",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_repeat_indexed2048.json",
    gpu_filter16_hash25m_repeat_indexed2048_command,
    "lookups_per_sec",
)

check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_repeat_packed_positive2048.json",
    gpu_filter16_hash25m_repeat_indexed2048_command,
    "lookups_per_sec",
)

gpu_filter16_hash25m_steps1024_dp7_setup_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "262144",
    "--steps",
    "1024",
    "--jumps",
    "16",
    "--dp-bits",
    "7",
    "--target-count",
    "25005000",
    "--hits",
    "64",
    "--lookup-repeat",
    "1024",
    "--lookup-query-mode",
    "repeat",
    "--lookup-engine",
    "gpu-filter16-hash-repeat",
    "--lookup-tg-limit",
    "512",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_steps1024_dp7_setup.json",
    gpu_filter16_hash25m_steps1024_dp7_setup_command,
    "setup_inclusive_ops_per_sec",
)

gpu_filter16_hash25m_steps2048_dp6_setup_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "131072",
    "--steps",
    "2048",
    "--jumps",
    "16",
    "--dp-bits",
    "6",
    "--target-count",
    "25005000",
    "--hits",
    "64",
    "--lookup-repeat",
    "1024",
    "--lookup-query-mode",
    "repeat",
    "--lookup-engine",
    "gpu-filter16-hash-repeat",
    "--lookup-tg-limit",
    "512",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_steps2048_dp6_setup.json",
    gpu_filter16_hash25m_steps2048_dp6_setup_command,
    "setup_inclusive_ops_per_sec",
)

gpu_filter16_hash25m_steps4096_dp5_setup_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "65536",
    "--steps",
    "4096",
    "--jumps",
    "16",
    "--dp-bits",
    "5",
    "--target-count",
    "25005000",
    "--hits",
    "64",
    "--lookup-repeat",
    "1024",
    "--lookup-query-mode",
    "repeat",
    "--lookup-engine",
    "gpu-filter16-hash-repeat",
    "--lookup-tg-limit",
    "512",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_steps4096_dp5_setup.json",
    gpu_filter16_hash25m_steps4096_dp5_setup_command,
    "setup_inclusive_ops_per_sec",
)

gpu_filter16_hash25m_scaled4_j4_setup_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "131072",
    "--steps",
    "2048",
    "--jumps",
    "4",
    "--dp-bits",
    "6",
    "--target-count",
    "25005000",
    "--hits",
    "64",
    "--lookup-repeat",
    "1024",
    "--lookup-query-mode",
    "repeat",
    "--lookup-engine",
    "gpu-filter16-hash-repeat",
    "--lookup-tg-limit",
    "512",
    "--jump-schedule",
    "scaled4-balanced",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_scaled4_j4_setup.json",
    gpu_filter16_hash25m_scaled4_j4_setup_command,
    "setup_inclusive_ops_per_sec",
)

gpu_filter16_hash25m_tg256_command = [
    "./macos/rck_macos",
    command,
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--target-count",
    "25005000",
    "--hits",
    "64",
    "--lookup-repeat",
    "1024",
    "--lookup-query-mode",
    "distinct-misses",
    "--lookup-engine",
    "gpu-filter16-hash",
    "--lookup-tg-limit",
    "256",
    "--min-ms",
    "500",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_tg256_gpu_lookup.json",
    gpu_filter16_hash25m_tg256_command,
    "gpu_lookup_lookups_per_sec",
)

check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_cpu_gate.json",
    gpu_filter16_hash25m_command,
    "ops_per_sec",
)

m3_auto_repeat_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench",
    "--iterations",
    "8192",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "6",
    "--target-count",
    "16777216",
    "--hits",
    "16",
    "--lookup-repeat",
    "131072",
    "--lookup-query-mode",
    "repeat",
    "--lookup-engine",
    "auto",
    "--lookup-tg-limit",
    "512",
    "--min-ms",
    "100",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter_m3_auto_repeat.json",
    m3_auto_repeat_command,
    "ops_per_sec",
)

check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter_m3_sparse_repeat_exact.json",
    m3_auto_repeat_command,
    "ops_per_sec",
)

check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter_m3_sparse_repeat_exact_cache.json",
    m3_auto_repeat_command,
    "ops_per_sec",
)

check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter_m3_sparse_repeat_base_index.json",
    m3_auto_repeat_command,
    "ops_per_sec",
)

check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter_m3_fused_filter_setup.json",
    m3_auto_repeat_command,
    "setup_inclusive_ops_per_sec",
)

check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter_m3_sparse_repeat_base_counts.json",
    m3_auto_repeat_command,
    "ops_per_sec",
)

check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter_m3_base_count_repeat.json",
    m3_auto_repeat_command,
    "ops_per_sec",
)

check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter_m3_base_count_by_base_reduce.json",
    m3_auto_repeat_command,
    "ops_per_sec",
)

rounds_base_count_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench",
    "--iterations",
    "131072",
    "--steps",
    "2048",
    "--jumps",
    "16",
    "--dp-bits",
    "6",
    "--target-count",
    "25005000",
    "--hits",
    "64",
    "--lookup-repeat",
    "1024",
    "--rounds",
    "2",
    "--lookup-tg-limit",
    "512",
    "--jump-schedule",
    "power2",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_rounds_base_count_repeat.json",
    rounds_base_count_command,
    "ops_per_sec",
)

check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_rounds_batched_walk.json",
    rounds_base_count_command,
    "ops_per_sec",
)

check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_rounds_setup_inclusive.json",
    rounds_base_count_command,
    "setup_inclusive_ops_per_sec",
)

rounds_distinct_misses_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench",
    "--iterations",
    "131072",
    "--steps",
    "2048",
    "--jumps",
    "16",
    "--dp-bits",
    "6",
    "--target-count",
    "25005000",
    "--hits",
    "64",
    "--lookup-repeat",
    "1024",
    "--lookup-query-mode",
    "distinct-misses",
    "--rounds",
    "2",
    "--lookup-tg-limit",
    "512",
    "--jump-schedule",
    "power2",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_hash_filter25m_rounds_distinct_misses_distance.json",
    rounds_distinct_misses_command,
    "setup_inclusive_wall_distance_per_sec",
)

m3_auto_repeat_tag16_mix_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench",
    "--iterations",
    "8192",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "6",
    "--target-count",
    "16777216",
    "--hits",
    "16",
    "--lookup-repeat",
    "131072",
    "--lookup-query-mode",
    "repeat",
    "--lookup-engine",
    "auto",
    "--lookup-filter-mode",
    "tag16-mix",
    "--lookup-tg-limit",
    "512",
    "--min-ms",
    "100",
]
check_experiment(
    "autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag16_mix_filter_m3_base_count_repeat.json",
    m3_auto_repeat_tag16_mix_command,
    "setup_inclusive_ops_per_sec",
)

print("metal affine-scan target lookup source ok")
