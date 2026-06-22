#!/usr/bin/env python3
from pathlib import Path


kernel_source = Path("macos/MetalFieldKernels.h").read_text()
host_source = Path("macos/MetalField.mm").read_text()
header_source = Path("macos/MetalField.h").read_text()
cli_source = Path("macos/rck_macos.cpp").read_text()
makefile = Path("Makefile").read_text()

kernel_name = "jacobian_affine_walk_dynamic_dp_stream_inplace_steps8_dp8_pow2_u32_distance"
if f"kernel void {kernel_name}" not in kernel_source:
    raise SystemExit(f"{kernel_name} kernel missing from Metal source")

start = kernel_source.index(f"kernel void {kernel_name}")
next_kernel = kernel_source.find("\nkernel void ", start + 1)
end_marker = kernel_source.find("\n)RCK_METAL", start + 1)
end = next_kernel if next_kernel != -1 and next_kernel < end_marker else end_marker
body = kernel_source[start:end]

required_kernel_markers = (
    "device ulong* p_xyz [[buffer(0)]]",
    "device uchar* p_infinity [[buffer(2)]]",
    "device atomic_uint* out_dp_count [[buffer(4)]]",
    "store_jacobian_xyz_only(p_xyz, p_base,",
    "p_infinity[id] = inf ? 1 : 0;",
    "AffineJumpValue jump = q_xy[jump_index];",
    "if (!inf && ((x0 & 0xFFUL) == 0))",
    "atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed)",
    "out_indices[slot] = id;",
    "out_distances[slot] = (ulong)distance;",
    "out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);",
)
for marker in required_kernel_markers:
    if marker not in body:
        raise SystemExit("missing in-place DP8 stream kernel marker: " + marker)

for forbidden in (
    "constant uint& steps",
    "constant ulong& dp_mask",
    "device atomic_uint* out_overflow",
    "constant uint& dp_capacity",
    "slot < dp_capacity",
    "atomic_store_explicit(out_overflow",
):
    if forbidden in body:
        raise SystemExit("in-place DP8 stream kernel must not keep marker: " + forbidden)

required_host_markers = (
    "RunJacobianDynamicDpStreamInplaceKernel",
    "RCKMetalJacobianDynamicDpStreamInplaceSelfTest",
    "RCKMetalJacobianDynamicDpStreamInplaceBenchJson",
    "\"jacobian_affine_walk_dynamic_dp_stream_inplace_steps8_dp8_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_inplace\"",
    "ValidateDynamicStateOutputs",
)
for marker in required_host_markers:
    if marker not in host_source:
        raise SystemExit("missing in-place DP8 stream host marker: " + marker)

for marker in (
    "RCKMetalJacobianDynamicDpStreamInplaceSelfTest",
    "RCKMetalJacobianDynamicDpStreamInplaceBenchJson",
):
    if marker not in header_source:
        raise SystemExit("missing in-place DP8 stream header marker: " + marker)

for marker in (
    "metal-jacobian-dynamic-dp-stream-inplace-test",
    "metal-jacobian-dynamic-dp-stream-inplace-bench",
    "RCKMetalJacobianDynamicDpStreamInplaceSelfTest",
    "RCKMetalJacobianDynamicDpStreamInplaceBenchJson",
):
    if marker not in cli_source:
        raise SystemExit("missing in-place DP8 stream CLI marker: " + marker)

for marker in (
    "macos-metal-dynamic-dp-stream-inplace-source-check",
    "macos-metal-jacobian-dynamic-dp-stream-inplace-test",
    "macos-metal-jacobian-dynamic-dp-stream-inplace-bench",
    "macos-metal-jacobian-dynamic-dp-stream-inplace-stable-bench",
):
    if marker not in makefile:
        raise SystemExit("missing in-place DP8 stream Makefile marker: " + marker)

experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_inplace.json")
if not experiment.exists():
    raise SystemExit("missing in-place DP8 stream autoresearch experiment")

print("metal dynamic dp stream in-place source ok")
