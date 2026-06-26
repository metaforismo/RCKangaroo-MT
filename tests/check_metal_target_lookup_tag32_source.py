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
):
    if marker not in kernel_source:
        raise SystemExit("missing tag32 target lookup kernel marker: " + marker)

for marker in (
    "TargetLookupTag32BucketHost",
    "static_assert(sizeof(TargetLookupTag32BucketHost) == 8",
    "BuildTargetLookupTag32FilterTable",
    "BuildTargetLookupTag32Table",
    "RunTargetLookupTag32FilterKernel",
    "RunTargetLookupTag32FilterPersistentKernel",
    "RCKMetalTargetLookupTag32FilterBenchJson",
    "RCKMetalTargetLookupTag32FilterPersistentBenchJson",
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
    "\\\"lookup_layout\\\":\\\"open_address_tag32_filter_exact256\\\"",
    "\\\"candidate_verification\\\":\\\"tag32_filter_then_cpu_exact_key_equality\\\"",
    "\\\"filter_positive_count\\\":",
    "\\\"filter_false_positive_count\\\":",
    "\\\"buffer_lifetime\\\":\\\"persistent\\\"",
    "\\\"metal_setup_seconds\\\":",
    "\\\"dispatch_lookups_per_sec\\\":",
    "\\\"lookup_layout\\\":\\\"open_address_tag32_index_exact256\\\"",
    "\\\"lookup_engine\\\":\\\"cpu\\\"",
    "\\\"candidate_verification\\\":\\\"tag32_prefilter_then_exact_key_equality\\\"",
    "\\\"target_key_bytes\\\":",
    "\\\"target_bucket_bytes\\\":",
):
    if marker not in host_source:
        raise SystemExit("missing tag32 target lookup host marker: " + marker)

if "RCKMetalTargetLookupTag32BenchJson" not in header_source:
    raise SystemExit("missing tag32 target lookup header declaration")

for marker in (
    "metal-target-lookup-tag32-bench",
    "metal-target-lookup-tag32-filter-bench",
    "metal-target-lookup-tag32-filter-persistent-bench",
    "metal-target-lookup-tag32-persistent-bench",
    "target-lookup-tag32-cpu-bench",
    "RCKMetalTargetLookupTag32BenchJson",
    "RCKMetalTargetLookupTag32FilterBenchJson",
    "RCKMetalTargetLookupTag32FilterPersistentBenchJson",
    "RCKMetalTargetLookupTag32PersistentBenchJson",
    "RCKCpuTargetLookupTag32BenchJson",
):
    if marker not in cli_source:
        raise SystemExit("missing tag32 target lookup CLI marker: " + marker)

for marker in (
    "macos-metal-target-lookup-tag32-source-check",
    "macos-metal-target-lookup-tag32-bench",
    "macos-metal-target-lookup-tag32-filter-bench",
    "macos-metal-target-lookup-tag32-filter-persistent-bench",
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
