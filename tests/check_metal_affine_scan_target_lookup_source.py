from pathlib import Path
import json


root = Path(".")
kernels = (root / "macos" / "MetalField.mm").read_text(encoding="utf-8")
header = (root / "macos" / "MetalField.h").read_text(encoding="utf-8")
cli = (root / "macos" / "rck_macos.cpp").read_text(encoding="utf-8")
makefile = (root / "Makefile").read_text(encoding="utf-8")

markers = [
    "RCKMetalJacobianDynamicDpStreamXyzzAffineScanTargetLookupTag32BenchJson",
    "jacobian_affine_scan_target_lookup_tag32",
    "affine_dp_scan_target_lookup",
    "lookup_repeat",
    "lookup_query_mode",
    "lookup_engine",
    "lookup_engine_effective",
    "ChooseAffineLookupEngine",
    "lookup_threadgroup_limit",
    "ChooseAffineLookupThreadgroupLimit",
    "dp_query_count",
    "target_lookup_checksum",
    "RunTargetLookupTag32Kernel",
    "RunTargetLookupTag32FilterKernel",
    "RunTargetLookupTag16HashFilterKernel",
    "ResolveTargetLookupTag32FilterCandidates",
    "RunTargetLookupTag32Cpu",
    "ValidateAffineTargetLookupOutputs",
    "\"gpu_filter\"",
    "\"gpu_filter16_hash\"",
    "BuildTargetLookupTag32FilterTable",
    "BuildTargetLookupTag16FilterTable",
    "BuildTargetLookupQueryHashes",
    "BuildTargetLookupQueryHashesParallel",
    "kMinParallelTargetLookupHashQueries",
    "ParallelForSamples(queries.size()",
    "\\\"lookup_layout\\\":\\\"open_address_tag16_hash_filter_exact256\\\"",
    "\\\"candidate_verification\\\":\\\"tag16_hash_filter_then_cpu_exact_key_equality\\\"",
    "\\\"query_input\\\":\\\"hash64\\\"",
    "\\\"target_query_hash_bytes\\\":",
    "\\\"lookup_hash_seconds\\\":",
    "\\\"lookup_gpu_seconds\\\":",
    "\\\"lookup_exact_seconds\\\":",
    "\\\"gpu_lookup_lookups_per_sec\\\":",
    "filter_positive_count",
    "filter_false_positive_count",
    "lookup_hash_seconds += hash_seconds",
    "lookup_gpu_seconds += filter_seconds",
    "lookup_exact_seconds += exact_seconds",
    "lookup_gpu_lookups_per_sec",
]
for marker in markers:
    if marker not in kernels:
        raise SystemExit("missing affine-scan target-lookup host marker: " + marker)

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

choose_start = kernels.index("static const char* ChooseAffineLookupEngine")
choose_end = kernels.index("static unsigned int ChooseAffineLookupThreadgroupLimit", choose_start)
choose_body = kernels[choose_start:choose_end]
if '"gpu_filter"' in choose_body:
    raise SystemExit("auto lookup routing should not promote gpu_filter without a kept paired gate")

if "RCKMetalJacobianDynamicDpStreamXyzzAffineScanTargetLookupTag32BenchJson" not in header:
    raise SystemExit("missing affine-scan target-lookup header declaration")

command = "metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench"
if command not in cli:
    raise SystemExit("missing affine-scan target-lookup CLI command")
if "--lookup-repeat" not in cli:
    raise SystemExit("missing affine-scan target-lookup lookup-repeat CLI option")
if "--lookup-query-mode" not in cli:
    raise SystemExit("missing affine-scan target-lookup lookup-query-mode CLI option")
if "--lookup-engine" not in cli:
    raise SystemExit("missing affine-scan target-lookup lookup-engine CLI option")
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

print("metal affine-scan target lookup source ok")
