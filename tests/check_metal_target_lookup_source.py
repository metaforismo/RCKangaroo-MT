#!/usr/bin/env python3
import json
from pathlib import Path


kernel_source = Path("macos/MetalFieldKernels.h").read_text()
host_source = Path("macos/MetalField.mm").read_text()
header_source = Path("macos/MetalField.h").read_text()
cli_source = Path("macos/rck_macos.cpp").read_text()
makefile = Path("Makefile").read_text()

required_kernel_markers = (
    "struct TargetLookupKey",
    "struct TargetLookupBucket",
    "target_lookup_hash",
    "target_lookup_key_equals",
    "kernel void target_lookup_exact256",
    "device const TargetLookupBucket* target_buckets [[buffer(0)]]",
    "device const TargetLookupKey* query_keys [[buffer(1)]]",
    "device uint* out_target_indices [[buffer(2)]]",
    "device atomic_uint* out_hit_count [[buffer(3)]]",
    "constant uint& bucket_count [[buffer(4)]]",
    "while (probes < bucket_count)",
    "bucket.occupied",
)
for marker in required_kernel_markers:
    if marker not in kernel_source:
        raise SystemExit("missing target lookup kernel marker: " + marker)

exact_kernel_start = kernel_source.index("kernel void target_lookup_exact256")
exact_kernel_end = kernel_source.index("kernel void target_lookup_compact_exact256", exact_kernel_start)
exact_kernel_source = kernel_source[exact_kernel_start:exact_kernel_end].lower()
for forbidden in (
    "fingerprint",
    "probabilistic",
    "bloom",
):
    if forbidden in exact_kernel_source:
        raise SystemExit("target lookup gate must remain exact, found marker: " + forbidden)

required_host_markers = (
    "BuildTargetLookupExactTable",
    "ValidateTargetLookupOutputs",
    "kDefaultMetalTargetLookupThreadgroupLimit = 64",
    "EffectiveTargetLookupThreadgroupLimit",
    "RCKMetalTargetLookupBenchJson",
    "\"target_lookup_exact256\"",
    "\\\"lookup_layout\\\":\\\"open_address_exact256\\\"",
    "\\\"target_key\\\":\\\"x256_y_parity\\\"",
    "\\\"candidate_verification\\\":\\\"exact_key_equality\\\"",
    "\\\"target_table_bytes\\\":",
    "\\\"bytes_per_target\\\":",
    "\\\"expected_hits\\\":",
    "\\\"hit_count\\\":",
    "\\\"miss_count\\\":",
    "\\\"target_lookup_checksum\\\":\\\"0x",
)
for marker in required_host_markers:
    if marker not in host_source:
        raise SystemExit("missing target lookup host marker: " + marker)

if "RCKMetalTargetLookupBenchJson" not in header_source:
    raise SystemExit("missing target lookup header declaration")

for marker in (
    "metal-target-lookup-bench",
    "RCKMetalTargetLookupBenchJson",
):
    if marker not in cli_source:
        raise SystemExit("missing target lookup CLI marker: " + marker)

for marker in (
    "macos-metal-target-lookup-source-check",
    "macos-metal-target-lookup-bench",
):
    if marker not in makefile:
        raise SystemExit("missing target lookup Makefile marker: " + marker)

experiment = Path("autoresearch/experiments/metal_target_lookup_exact256.json")
if not experiment.exists():
    raise SystemExit("missing target lookup autoresearch experiment")
payload = json.loads(experiment.read_text(encoding="utf-8"))
expected_command = [
    "./macos/rck_macos",
    "metal-target-lookup-bench",
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
    raise SystemExit("target lookup experiment should run the exact256 lookup CLI")
if payload.get("metric") != "lookups_per_sec":
    raise SystemExit("target lookup experiment should optimize lookups_per_sec")
if int(payload.get("sample_runs", 0)) < 3:
    raise SystemExit("target lookup experiment should keep sample_runs >= 3")

print("metal target lookup source ok")
