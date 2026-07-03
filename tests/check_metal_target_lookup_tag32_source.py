#!/usr/bin/env python3
import json
from pathlib import Path


kernel_source = Path("macos/MetalFieldKernels.h").read_text(encoding="utf-8")
host_source = Path("macos/MetalField.mm").read_text(encoding="utf-8")
header_source = Path("macos/MetalField.h").read_text(encoding="utf-8")
cli_source = Path("macos/rck_macos.cpp").read_text(encoding="utf-8")
makefile = Path("Makefile").read_text(encoding="utf-8")

for marker in (
    "struct TargetLookupTag32Bucket",
    "target_lookup_tag32_exact256",
    "device const TargetLookupTag32Bucket* target_buckets [[buffer(0)]]",
    "uint tag = (uint)(hash >> 32)",
    "bucket.target_index != 0xFFFFFFFFU",
    "bucket.tag == tag && target_lookup_key_equals(target_keys[bucket.target_index], query)",
    "target_lookup_tag32_filter256",
    "device const uint* target_filter_buckets [[buffer(0)]]",
    "uint filter_tag = target_lookup_filter_tag(hash)",
    "return tag == 0U ? 1U : tag",
    "target_lookup_tag16_filter256",
    "device const ushort* target_filter_buckets [[buffer(0)]]",
    "ushort filter_tag = target_lookup_filter_tag16(hash)",
    "tag == (ushort)0U ? (ushort)1U : tag",
    "target_lookup_filter_tag16_mixed",
    "target_lookup_tag16_hash_filter256",
    "device const ulong* query_hashes [[buffer(1)]]",
    "ulong hash = query_hashes[id]",
    "target_lookup_tag16_mixed_hash_filter_repeat2d256",
    "target_lookup_tag16_mixed_hash_filter_repeat_packed2d256",
    "target_lookup_tag32_hash_filter_repeat2d256",
    "target_lookup_tag32_hash_filter_repeat_packed2d256",
    "device const ulong* base_query_hashes [[buffer(1)]]",
):
    if marker not in kernel_source:
        raise SystemExit("missing tag32 target lookup kernel marker: " + marker)

for marker in (
    "TargetLookupTag32BucketHost",
    "static_assert(sizeof(TargetLookupTag32BucketHost) == 8",
    "struct alignas(uint64_t) TargetLookupTag32BucketHost",
    "static_assert(alignof(TargetLookupTag32BucketHost) >= alignof(uint64_t)",
    "offsetof(TargetLookupTag32BucketHost, tag) == 0",
    "offsetof(TargetLookupTag32BucketHost, target_index) == 4",
    "BuildTargetLookupTag32FilterTable",
    "BuildTargetLookupTag16FilterTable",
    "BuildTargetLookupTag32FilterTableFromTag32Buckets",
    "return tag ? tag : 1U",
    "filter_buckets[slot] = bucket.tag ? bucket.tag : 1U",
    "BuildTargetLookupTag16FilterTableFromTag32Buckets",
    "BuildTargetLookupTag16MixedFilterTableFromTag32Buckets",
    "TargetLookupFilterTag16FromTag32",
    "TargetLookupFilterTag16Mixed",
    "kMinParallelTargetLookupFilterBuckets",
    "TargetLookupFilterChecksum",
    "RCKTargetLookupFilterBuildBenchJson",
    "RCKTargetLookupTag32BuildFromKeysBenchJson",
    "RCKTargetLookupTag32ParallelInsertBenchJson",
    "BuildTargetLookupTag32TableFromKeysLegacy",
    "BuildTargetLookupTag32TableFromKeysPrehashed",
    "BuildTargetLookupTag32TableFromKeysParallelInsert",
    "InsertTargetLookupTag32PrehashedTableParallel",
    "fused_tag16_filter_buckets",
    "(*fused_tag16_filter_buckets)[slot]",
    "TargetLookupHashMatchesInjected",
    "TargetLookupTag32TablesEqual",
    "TargetLookupTag32TableFindsAllKeys",
    "target_count < kMinParallelTargetLookupHashQueries || ValidationWorkerCount(target_count) <= 1",
    "__atomic_compare_exchange(&buckets[slot]",
    "\\\"setup_phase\\\":\\\"host_tag32_build_from_injected_keys\\\"",
    "\\\"setup_phase\\\":\\\"host_tag32_parallel_insert_probe\\\"",
    "\\\"candidate_verification\\\":\\\"legacy_tag32_table_field_equality\\\"",
    "\\\"candidate_verification\\\":\\\"prehashed_serial_vs_parallel_semantic_find_all_keys\\\"",
    "\\\"prehashed_seconds\\\":",
    "\\\"parallel_seconds\\\":",
    "\\\"prehashed_checksum\\\":",
    "\\\"parallel_checksum\\\":",
    "\\\"table_equal\\\":",
    "\\\"all_keys_found\\\":",
    "\\\"candidate_verification\\\":\\\"legacy_rehash_filter_byte_equality\\\"",
    "\\\"tag32_legacy_seconds\\\":",
    "\\\"tag32_derived_seconds\\\":",
    "\\\"tag16_legacy_seconds\\\":",
    "\\\"tag16_derived_seconds\\\":",
    "\\\"tag32_byte_equal\\\":",
    "\\\"tag16_byte_equal\\\":",
    "BuildTargetLookupQueryHashes",
    "BuildTargetLookupTag32Table",
    "RunTargetLookupTag32FilterKernel",
    "RunTargetLookupTag32FilterPersistentKernel",
    "RunTargetLookupTag16FilterPersistentKernel",
    "RunTargetLookupTag16HashFilterPersistentKernel",
    "RCKMetalTargetLookupTag32FilterBenchJson",
    "RCKMetalTargetLookupTag32FilterPersistentBenchJson",
    "RCKMetalTargetLookupTag16FilterPersistentBenchJson",
    "RCKMetalTargetLookupTag16HashFilterPersistentBenchJson",
    "RunTargetLookupTag32Kernel",
    "RunTargetLookupTag32Cpu",
    "RCKMetalTargetLookupTag32BenchJson",
    "RCKMetalTargetLookupTag32PersistentBenchJson",
    "RCKCpuTargetLookupTag32BenchJson",
    "kDefaultMetalTargetLookupThreadgroupLimit = 64",
    "kDefaultMetalPersistentTargetLookupLargeThreadgroupLimit = 1024",
    "kDefaultMetalPersistentTargetLookupFilterLargeThreadgroupLimit = 512",
    "kDefaultMetalPersistentTargetLookupLargeTargetThreshold = 16777216",
    "PersistentTargetLookupDefaultThreadgroupLimit",
    "PersistentTargetLookupFilterDefaultThreadgroupLimit",
    "EffectiveTargetLookupFilterPersistentThreadgroupLimit",
    "PreferredTargetLookupFilterPersistentThreadgroupWidth",
    "EffectiveTargetLookupPersistentThreadgroupLimit",
    "PreferredTargetLookupPersistentThreadgroupWidth",
    "target_lookup_tag32_persistent_exact256",
    "target_lookup_tag32_filter_exact256",
    "target_lookup_tag32_filter_persistent_exact256",
    "target_lookup_tag16_filter_persistent_exact256",
    "target_lookup_tag16_hash_filter_persistent_exact256",
    "\\\"lookup_layout\\\":\\\"open_address_tag32_filter_exact256\\\"",
    "\\\"lookup_layout\\\":\\\"open_address_tag16_filter_exact256\\\"",
    "\\\"lookup_layout\\\":\\\"open_address_tag16_hash_filter_exact256\\\"",
    "\\\"query_input\\\":\\\"hash64\\\"",
    "\\\"target_query_hash_bytes\\\":",
    "\\\"candidate_verification\\\":\\\"tag32_filter_then_cpu_exact_key_equality\\\"",
    "\\\"candidate_verification\\\":\\\"tag16_filter_then_cpu_exact_key_equality\\\"",
    "\\\"candidate_verification\\\":\\\"tag16_hash_filter_then_cpu_exact_key_equality\\\"",
    "\\\"filter_positive_count\\\":",
    "\\\"filter_false_positive_count\\\":",
    "\\\"buffer_lifetime\\\":\\\"persistent\\\"",
    "\\\"metal_setup_seconds\\\":",
    "\\\"dispatch_lookups_per_sec\\\":",
    "\\\"gpu_dispatch_lookups_per_sec\\\":",
    "\\\"lookup_layout\\\":\\\"open_address_tag32_index_exact256\\\"",
    "\\\"lookup_engine\\\":\\\"cpu\\\"",
    "\\\"candidate_verification\\\":\\\"tag32_prefilter_then_exact_key_equality\\\"",
    "\\\"target_key_bytes\\\":",
    "\\\"target_bucket_bytes\\\":",
):
    if marker not in host_source:
        raise SystemExit("missing tag32 target lookup host marker: " + marker)

if host_source.count("ParallelForSamples(tag32_buckets.size()") < 2:
    raise SystemExit("derived tag32/tag16 filter builders should parallelize large bucket scans")
if host_source.count("std::atomic<bool> index_out_of_range(false)") < 2:
    raise SystemExit("parallel derived filter builders should preserve index-range error detection")

if "((total_dispatch_seconds + total_exact_verify_seconds) * 1000.0 < (double)min_ms)" in host_source:
    raise SystemExit("persistent filter lookup min-ms window should be bounded by GPU dispatch time, not exact CPU verification")
if host_source.count("(total_dispatch_seconds * 1000.0 < (double)min_ms)") < 3:
    raise SystemExit("persistent filter lookup kernels should keep GPU dispatch-bound min-ms windows")

for marker in (
    "RCKMetalTargetLookupTag32BenchJson",
    "RCKTargetLookupFilterBuildBenchJson",
    "RCKTargetLookupTag32BuildFromKeysBenchJson",
    "RCKTargetLookupTag32ParallelInsertBenchJson",
):
    if marker not in header_source:
        raise SystemExit("missing tag32 target lookup header declaration: " + marker)

if "RCKMetalTargetLookupTag32BenchJson" not in header_source:
    raise SystemExit("missing tag32 target lookup header declaration")

for marker in (
    "metal-target-lookup-tag32-bench",
    "metal-target-lookup-tag32-filter-bench",
    "metal-target-lookup-tag32-filter-persistent-bench",
    "metal-target-lookup-tag16-filter-persistent-bench",
    "metal-target-lookup-tag16-hash-filter-persistent-bench",
    "metal-target-lookup-tag32-persistent-bench",
    "target-lookup-tag32-cpu-bench",
    "target-lookup-filter-build-bench",
    "target-lookup-tag32-build-from-keys-bench",
    "target-lookup-tag32-parallel-insert-bench",
    "RCKMetalTargetLookupTag32BenchJson",
    "RCKMetalTargetLookupTag32FilterBenchJson",
    "RCKMetalTargetLookupTag32FilterPersistentBenchJson",
    "RCKMetalTargetLookupTag16FilterPersistentBenchJson",
    "RCKMetalTargetLookupTag16HashFilterPersistentBenchJson",
    "RCKMetalTargetLookupTag32PersistentBenchJson",
    "RCKCpuTargetLookupTag32BenchJson",
    "RCKTargetLookupFilterBuildBenchJson",
    "RCKTargetLookupTag32BuildFromKeysBenchJson",
    "RCKTargetLookupTag32ParallelInsertBenchJson",
):
    if marker not in cli_source:
        raise SystemExit("missing tag32 target lookup CLI marker: " + marker)

for marker in (
    "macos-metal-target-lookup-tag32-source-check",
    "macos-metal-target-lookup-tag32-bench",
    "macos-metal-target-lookup-tag32-filter-bench",
    "macos-metal-target-lookup-tag32-filter-persistent-bench",
    "macos-metal-target-lookup-tag16-filter-persistent-bench",
    "macos-metal-target-lookup-tag16-hash-filter-persistent-bench",
    "macos-metal-target-lookup-tag32-persistent-bench",
):
    if marker not in makefile:
        raise SystemExit("missing tag32 target lookup Makefile marker: " + marker)

experiment = Path("autoresearch/experiments/metal_target_lookup_tag32_exact256.json")
if not experiment.exists():
    raise SystemExit("missing tag32 target lookup autoresearch experiment")
payload = json.loads(experiment.read_text(encoding="utf-8"))
expected_command = [
    "./macos/rck_macos",
    "metal-target-lookup-tag32-bench",
    "--target-count",
    "1048576",
    "--query-count",
    "1048576",
    "--hits",
    "4096",
    "--min-ms",
    "500",
]
if payload.get("bench_command") != expected_command:
    raise SystemExit("tag32 target lookup experiment should run the tag32 lookup CLI")
if payload.get("paired_baseline_command", [])[:2] != ["./macos/rck_macos", "metal-target-lookup-compact-bench"]:
    raise SystemExit("tag32 target lookup experiment should compare against compact64 baseline")
if payload.get("metric") != "lookups_per_sec":
    raise SystemExit("tag32 target lookup experiment should optimize lookups_per_sec")
if int(payload.get("sample_runs", 0)) < 3:
    raise SystemExit("tag32 target lookup experiment should keep sample_runs >= 3")

filter_experiment = Path("autoresearch/experiments/metal_target_lookup_tag32_filter_exact256.json")
if not filter_experiment.exists():
    raise SystemExit("missing tag32 filter target lookup autoresearch experiment")
filter_payload = json.loads(filter_experiment.read_text(encoding="utf-8"))
filter_command = [
    "./macos/rck_macos",
    "metal-target-lookup-tag32-filter-bench",
    "--target-count",
    "25005000",
    "--query-count",
    "1082368",
    "--hits",
    "64",
    "--min-ms",
    "500",
]
if filter_payload.get("bench_command") != filter_command:
    raise SystemExit("tag32 filter experiment should run the filter lookup CLI")
if filter_payload.get("paired_baseline_command", [])[:2] != ["./macos/rck_macos", "metal-target-lookup-tag32-bench"]:
    raise SystemExit("tag32 filter experiment should compare against exact tag32 baseline")
if filter_payload.get("metric") != "lookups_per_sec":
    raise SystemExit("tag32 filter experiment should optimize lookups_per_sec")
if int(filter_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("tag32 filter experiment should keep sample_runs >= 3")

filter_persistent_experiment = Path("autoresearch/experiments/metal_target_lookup_tag32_filter_persistent.json")
if not filter_persistent_experiment.exists():
    raise SystemExit("missing persistent tag32 filter target lookup autoresearch experiment")
filter_persistent_payload = json.loads(filter_persistent_experiment.read_text(encoding="utf-8"))
filter_persistent_command = [
    "./macos/rck_macos",
    "metal-target-lookup-tag32-filter-persistent-bench",
    "--target-count",
    "25005000",
    "--query-count",
    "1082368",
    "--hits",
    "64",
    "--min-ms",
    "700",
]
if filter_persistent_payload.get("bench_command") != filter_persistent_command:
    raise SystemExit("persistent tag32 filter experiment should run the persistent filter lookup CLI")
if filter_persistent_payload.get("paired_baseline_command", [])[:2] != ["./macos/rck_macos", "metal-target-lookup-tag32-filter-bench"]:
    raise SystemExit("persistent tag32 filter experiment should compare against non-persistent filter baseline")
if filter_persistent_payload.get("metric") != "lookups_per_sec":
    raise SystemExit("persistent tag32 filter experiment should optimize lookups_per_sec")
if int(filter_persistent_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("persistent tag32 filter experiment should keep sample_runs >= 3")

tag16_filter_persistent_experiment = Path("autoresearch/experiments/metal_target_lookup_tag16_filter_persistent.json")
if not tag16_filter_persistent_experiment.exists():
    raise SystemExit("missing persistent tag16 filter target lookup autoresearch experiment")
tag16_filter_persistent_payload = json.loads(tag16_filter_persistent_experiment.read_text(encoding="utf-8"))
tag16_filter_persistent_command = [
    "./macos/rck_macos",
    "metal-target-lookup-tag16-filter-persistent-bench",
    "--target-count",
    "25005000",
    "--query-count",
    "1082368",
    "--hits",
    "64",
    "--min-ms",
    "700",
]
if tag16_filter_persistent_payload.get("bench_command") != tag16_filter_persistent_command:
    raise SystemExit("persistent tag16 filter experiment should run the persistent tag16 filter lookup CLI")
if tag16_filter_persistent_payload.get("paired_baseline_command", [])[:2] != ["./macos/rck_macos", "metal-target-lookup-tag32-filter-persistent-bench"]:
    raise SystemExit("persistent tag16 filter experiment should compare against persistent tag32 filter baseline")
if tag16_filter_persistent_payload.get("metric") != "lookups_per_sec":
    raise SystemExit("persistent tag16 filter experiment should optimize lookups_per_sec")
if int(tag16_filter_persistent_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("persistent tag16 filter experiment should keep sample_runs >= 3")

tag16_hash_filter_persistent_experiment = Path("autoresearch/experiments/metal_target_lookup_tag16_hash_filter_persistent.json")
if not tag16_hash_filter_persistent_experiment.exists():
    raise SystemExit("missing persistent tag16 hash-filter target lookup autoresearch experiment")
tag16_hash_filter_persistent_payload = json.loads(tag16_hash_filter_persistent_experiment.read_text(encoding="utf-8"))
tag16_hash_filter_persistent_command = [
    "./macos/rck_macos",
    "metal-target-lookup-tag16-hash-filter-persistent-bench",
    "--target-count",
    "25005000",
    "--query-count",
    "1082368",
    "--hits",
    "64",
    "--min-ms",
    "700",
]
if tag16_hash_filter_persistent_payload.get("bench_command") != tag16_hash_filter_persistent_command:
    raise SystemExit("persistent tag16 hash-filter experiment should run the persistent tag16 hash-filter lookup CLI")
if tag16_hash_filter_persistent_payload.get("paired_baseline_command", [])[:2] != ["./macos/rck_macos", "metal-target-lookup-tag16-filter-persistent-bench"]:
    raise SystemExit("persistent tag16 hash-filter experiment should compare against persistent tag16 filter baseline")
if tag16_hash_filter_persistent_payload.get("metric") != "lookups_per_sec":
    raise SystemExit("persistent tag16 hash-filter experiment should optimize lookups_per_sec")
if int(tag16_hash_filter_persistent_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("persistent tag16 hash-filter experiment should keep sample_runs >= 3")

tag16_hash_dispatch_experiment = Path("autoresearch/experiments/metal_target_lookup_tag16_hash_filter_persistent_dispatch.json")
if not tag16_hash_dispatch_experiment.exists():
    raise SystemExit("missing persistent tag16 hash-filter dispatch target lookup autoresearch experiment")
tag16_hash_dispatch_payload = json.loads(tag16_hash_dispatch_experiment.read_text(encoding="utf-8"))
if tag16_hash_dispatch_payload.get("bench_command") != tag16_hash_filter_persistent_command:
    raise SystemExit("persistent tag16 hash-filter dispatch experiment should run the prehashed persistent CLI")
if tag16_hash_dispatch_payload.get("paired_baseline_command", [])[:2] != ["./macos/rck_macos", "metal-target-lookup-tag16-filter-persistent-bench"]:
    raise SystemExit("persistent tag16 hash-filter dispatch experiment should compare against persistent tag16 filter baseline")
if tag16_hash_dispatch_payload.get("metric") != "gpu_dispatch_lookups_per_sec":
    raise SystemExit("persistent tag16 hash-filter dispatch experiment should optimize gpu_dispatch_lookups_per_sec")
if int(tag16_hash_dispatch_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("persistent tag16 hash-filter dispatch experiment should keep sample_runs >= 3")
if float(tag16_hash_dispatch_payload.get("cooldown_sec", 0.0)) < 10.0:
    raise SystemExit("persistent tag16 hash-filter dispatch experiment should cool down between paired samples")

filter_build_experiment = Path("autoresearch/experiments/target_lookup_filter_build_from_tag32_buckets.json")
if not filter_build_experiment.exists():
    raise SystemExit("missing target lookup filter-build autoresearch experiment")
filter_build_payload = json.loads(filter_build_experiment.read_text(encoding="utf-8"))
filter_build_command = [
    "./macos/rck_macos",
    "target-lookup-filter-build-bench",
    "--target-count",
    "25005000",
    "--iterations",
    "1",
]
if filter_build_payload.get("bench_command") != filter_build_command:
    raise SystemExit("filter-build experiment should run the host filter-build CLI")
if filter_build_payload.get("metric") != "speedup":
    raise SystemExit("filter-build experiment should optimize internal old-vs-derived speedup")
if int(filter_build_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("filter-build experiment should keep sample_runs >= 3")

build_from_keys_experiment = Path("autoresearch/experiments/target_lookup_tag32_build_from_keys.json")
if not build_from_keys_experiment.exists():
    raise SystemExit("missing target lookup tag32 build-from-keys autoresearch experiment")
build_from_keys_payload = json.loads(build_from_keys_experiment.read_text(encoding="utf-8"))
build_from_keys_command = [
    "./macos/rck_macos",
    "target-lookup-tag32-build-from-keys-bench",
    "--target-count",
    "25005000",
    "--injected-count",
    "64",
    "--iterations",
    "1",
]
if build_from_keys_payload.get("bench_command") != build_from_keys_command:
    raise SystemExit("build-from-keys experiment should run the host tag32 build CLI")
if build_from_keys_payload.get("metric") != "speedup":
    raise SystemExit("build-from-keys experiment should optimize internal legacy-vs-prehashed speedup")
if int(build_from_keys_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("build-from-keys experiment should keep sample_runs >= 3")

parallel_insert_experiment = Path("autoresearch/experiments/target_lookup_tag32_parallel_insert.json")
if not parallel_insert_experiment.exists():
    raise SystemExit("missing target lookup tag32 parallel-insert autoresearch experiment")
parallel_insert_payload = json.loads(parallel_insert_experiment.read_text(encoding="utf-8"))
parallel_insert_command = [
    "./macos/rck_macos",
    "target-lookup-tag32-parallel-insert-bench",
    "--target-count",
    "25005000",
    "--injected-count",
    "64",
    "--iterations",
    "1",
]
if parallel_insert_payload.get("bench_command") != parallel_insert_command:
    raise SystemExit("parallel-insert experiment should run the host tag32 parallel-insert CLI")
if parallel_insert_payload.get("metric") != "parallel_targets_per_sec":
    raise SystemExit("parallel-insert experiment should optimize absolute parallel insert throughput")
if int(parallel_insert_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("parallel-insert experiment should keep sample_runs >= 3")
if parallel_insert_payload.get("paired_order") != "alternate":
    raise SystemExit("parallel-insert paired experiment should alternate baseline/candidate order")

persistent_experiment = Path("autoresearch/experiments/metal_target_lookup_tag32_persistent_tg1024.json")
if not persistent_experiment.exists():
    raise SystemExit("missing persistent tag32 target lookup autoresearch experiment")
persistent_payload = json.loads(persistent_experiment.read_text(encoding="utf-8"))
persistent_command = [
    "./macos/rck_macos",
    "metal-target-lookup-tag32-persistent-bench",
    "--target-count",
    "25005000",
    "--query-count",
    "1082368",
    "--hits",
    "64",
    "--min-ms",
    "700",
]
if persistent_payload.get("bench_command") != persistent_command:
    raise SystemExit("persistent tag32 target lookup experiment should run the promoted persistent CLI default")
if persistent_payload.get("paired_baseline_command", [])[-2:] != ["--tg-limit", "64"]:
    raise SystemExit("persistent tag32 target lookup experiment should compare against the old tg64 default")
if persistent_payload.get("metric") != "lookups_per_sec":
    raise SystemExit("persistent tag32 target lookup experiment should optimize lookups_per_sec")
if int(persistent_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("persistent tag32 target lookup experiment should keep sample_runs >= 3")

print("metal tag32 target lookup source ok")
