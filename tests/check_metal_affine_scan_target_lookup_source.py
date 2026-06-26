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
    "RunTargetLookupTag32Cpu",
]
for marker in markers:
    if marker not in kernels:
        raise SystemExit("missing affine-scan target-lookup host marker: " + marker)

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

print("metal affine-scan target lookup source ok")
