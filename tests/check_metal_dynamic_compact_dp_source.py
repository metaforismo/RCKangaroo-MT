#!/usr/bin/env python3
from pathlib import Path


kernel_source = Path("macos/MetalFieldKernels.h").read_text()
host_source = Path("macos/MetalField.mm").read_text()
header_source = Path("macos/MetalField.h").read_text()
cli_source = Path("macos/rck_macos.cpp").read_text()
makefile = Path("Makefile").read_text()

kernel_name = "jacobian_affine_walk_dynamic_dp_compact_steps8_dp4_pow2"
if f"kernel void {kernel_name}" not in kernel_source:
    raise SystemExit(f"{kernel_name} kernel missing from Metal source")

start = kernel_source.index(f"kernel void {kernel_name}")
next_kernel = kernel_source.find("\nkernel void ", start + 1)
end_marker = kernel_source.find("\n)RCK_METAL", start + 1)
end = next_kernel if next_kernel != -1 and next_kernel < end_marker else end_marker
body = kernel_source[start:end]

required_kernel_markers = (
    "device uchar* out_flags [[buffer(4)]]",
    "device ulong* out_distances [[buffer(8)]]",
    "device ulong* out_dp_terms [[buffer(9)]]",
    "constant uint& jump_mask [[buffer(10)]]",
    "out_dp_terms[id] = (!inf && ((x0 & 0xFUL) == 0)) ? (x0 ^ (y0 << 1) ^ (z0 << 7)) : 0UL;",
    "out_flags[id] = (inf ? 1 : 0) | ((!inf && ((x0 & 0xFUL) == 0)) ? 2 : 0);",
)
for marker in required_kernel_markers:
    if marker not in body:
        raise SystemExit("missing compact dynamic kernel marker: " + marker)

for forbidden in (
    "device ulong* out_xyz",
    "store_jacobian_xyz_only",
    "constant uchar* jump_indices",
    "jump_indices[",
):
    if forbidden in body:
        raise SystemExit("compact dynamic kernel must not keep full-output marker: " + forbidden)

required_host_markers = (
    "RunJacobianDynamicCompactDpKernel",
    "RCKMetalJacobianDynamicCompactDpSelfTest",
    "RCKMetalJacobianDynamicCompactDpBenchJson",
    "\"jacobian_affine_walk_dynamic_dp_compact_steps8_dp4_pow2\"",
    "\"jacobian_affine_walk_dynamic_dp_compact\"",
    "\\\"output_layout\\\":\\\"dp_compact\\\"",
    "\\\"output_bytes_per_sample\\\":",
    "out_dp_terms",
)
for marker in required_host_markers:
    if marker not in host_source:
        raise SystemExit("missing compact dynamic host marker: " + marker)

for marker in (
    "RCKMetalJacobianDynamicCompactDpSelfTest",
    "RCKMetalJacobianDynamicCompactDpBenchJson",
):
    if marker not in header_source:
        raise SystemExit("missing compact dynamic header marker: " + marker)

for marker in (
    "metal-jacobian-dynamic-compact-dp-test",
    "metal-jacobian-dynamic-compact-dp-bench",
    "RCKMetalJacobianDynamicCompactDpSelfTest",
    "RCKMetalJacobianDynamicCompactDpBenchJson",
):
    if marker not in cli_source:
        raise SystemExit("missing compact dynamic CLI marker: " + marker)

for marker in (
    "macos-metal-dynamic-compact-dp-source-check",
    "macos-metal-jacobian-dynamic-compact-dp-test",
    "macos-metal-jacobian-dynamic-compact-dp-bench",
):
    if marker not in makefile:
        raise SystemExit("missing compact dynamic Makefile marker: " + marker)

experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_compact_dp.json")
if not experiment.exists():
    raise SystemExit("missing compact dynamic autoresearch experiment")

print("metal dynamic compact dp source ok")
