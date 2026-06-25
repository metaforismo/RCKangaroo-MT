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
    "dp_query_count",
    "target_lookup_checksum",
    "RunTargetLookupTag32Kernel",
]
for marker in markers:
    if marker not in kernels:
        raise SystemExit("missing affine-scan target-lookup host marker: " + marker)

if "RCKMetalJacobianDynamicDpStreamXyzzAffineScanTargetLookupTag32BenchJson" not in header:
    raise SystemExit("missing affine-scan target-lookup header declaration")

command = "metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench"
if command not in cli:
    raise SystemExit("missing affine-scan target-lookup CLI command")

make_markers = [
    "macos-metal-affine-scan-target-lookup-source-check",
    "macos-metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench",
]
for marker in make_markers:
    if marker not in makefile:
        raise SystemExit("missing affine-scan target-lookup Makefile marker: " + marker)

experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_target_lookup_tag32.json")
if not experiment.exists():
    raise SystemExit("missing affine-scan target-lookup autoresearch experiment")

payload = json.loads(experiment.read_text(encoding="utf-8"))
expected_command = [
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
if payload.get("bench_command") != expected_command:
    raise SystemExit("affine-scan target-lookup experiment should run the integrated CLI")
if payload.get("metric") != "ops_per_sec":
    raise SystemExit("affine-scan target-lookup experiment should optimize end-to-end ops_per_sec")
if int(payload.get("sample_runs", 0)) < 3:
    raise SystemExit("affine-scan target-lookup experiment should keep sample_runs >= 3")

print("metal affine-scan target lookup source ok")
