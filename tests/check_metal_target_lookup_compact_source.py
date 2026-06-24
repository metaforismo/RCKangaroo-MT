#!/usr/bin/env python3
import json
from pathlib import Path


kernel_source = Path("macos/MetalFieldKernels.h").read_text(encoding="utf-8")
host_source = Path("macos/MetalField.mm").read_text(encoding="utf-8")
header_source = Path("macos/MetalField.h").read_text(encoding="utf-8")
cli_source = Path("macos/rck_macos.cpp").read_text(encoding="utf-8")
makefile = Path("Makefile").read_text(encoding="utf-8")

for marker in (
    "struct TargetLookupCompactBucket",
    "target_lookup_compact_exact256",
    "device const TargetLookupCompactBucket* target_buckets [[buffer(0)]]",
    "device const TargetLookupKey* target_keys [[buffer(1)]]",
    "target_lookup_key_equals(target_keys[bucket.target_index], query)",
):
    if marker not in kernel_source:
        raise SystemExit("missing compact target lookup kernel marker: " + marker)

for marker in (
    "TargetLookupCompactBucketHost",
    "BuildTargetLookupCompactTable",
    "RunTargetLookupCompactKernel",
    "RCKMetalTargetLookupCompactBenchJson",
    "\\\"lookup_layout\\\":\\\"open_address_hash64_index_exact256\\\"",
    "\\\"candidate_verification\\\":\\\"hash64_prefilter_then_exact_key_equality\\\"",
    "\\\"target_key_bytes\\\":",
    "\\\"target_bucket_bytes\\\":",
):
    if marker not in host_source:
        raise SystemExit("missing compact target lookup host marker: " + marker)

lookup_tg_marker = (
    "dispatch_stats.threadgroup_limit = "
    "(unsigned int)EffectiveTargetLookupThreadgroupLimit(threadgroup_limit);"
)
if host_source.count(lookup_tg_marker) < 2:
    raise SystemExit("target lookup benches should report the lookup-specific threadgroup default")

if "RCKMetalTargetLookupCompactBenchJson" not in header_source:
    raise SystemExit("missing compact target lookup header declaration")

for marker in (
    "metal-target-lookup-compact-bench",
    "RCKMetalTargetLookupCompactBenchJson",
):
    if marker not in cli_source:
        raise SystemExit("missing compact target lookup CLI marker: " + marker)

for marker in (
    "macos-metal-target-lookup-compact-source-check",
    "macos-metal-target-lookup-compact-bench",
):
    if marker not in makefile:
        raise SystemExit("missing compact target lookup Makefile marker: " + marker)

experiment = Path("autoresearch/experiments/metal_target_lookup_compact_exact256.json")
if not experiment.exists():
    raise SystemExit("missing compact target lookup autoresearch experiment")
payload = json.loads(experiment.read_text(encoding="utf-8"))
expected_command = [
    "./macos/rck_macos",
    "metal-target-lookup-compact-bench",
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
    raise SystemExit("compact target lookup experiment should run the compact lookup CLI")
if payload.get("paired_baseline_command", [])[:2] != ["./macos/rck_macos", "metal-target-lookup-bench"]:
    raise SystemExit("compact target lookup experiment should compare against exact256 baseline")
if payload.get("metric") != "lookups_per_sec":
    raise SystemExit("compact target lookup experiment should optimize lookups_per_sec")
if int(payload.get("sample_runs", 0)) < 3:
    raise SystemExit("compact target lookup experiment should keep sample_runs >= 3")

print("metal compact target lookup source ok")
