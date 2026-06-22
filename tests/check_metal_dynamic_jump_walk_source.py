#!/usr/bin/env python3
from pathlib import Path


kernel_source = Path("macos/MetalFieldKernels.h").read_text()
host_source = Path("macos/MetalField.mm").read_text()
cli_source = Path("macos/rck_macos.cpp").read_text()

kernel_name = "jacobian_affine_walk_dynamic_jump_table"
if f"kernel void {kernel_name}" not in kernel_source:
    raise SystemExit(f"{kernel_name} kernel missing from Metal source")

start = kernel_source.index(f"kernel void {kernel_name}")
next_kernel = kernel_source.find("\nkernel void ", start + 1)
end_marker = kernel_source.find("\n)RCK_METAL", start + 1)
end = next_kernel if next_kernel != -1 and next_kernel < end_marker else end_marker
body = kernel_source[start:end]

required_kernel_markers = (
    "constant ulong* p_xyz [[buffer(0)]]",
    "constant ulong* q_xy [[buffer(1)]]",
    "constant uint* p_infinity [[buffer(2)]]",
    "device uchar* out_flags [[buffer(4)]]",
    "constant ulong* jump_distances",
    "device ulong* out_distances",
    "constant ulong& dp_mask",
    "constant uint& jump_count",
    "ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;",
    "mixed ^= mixed >> 33;",
    "mixed *= 0xff51afd7ed558ccdUL;",
    "((jump_count & (jump_count - 1)) == 0)",
    "mixed & (ulong)(jump_count - 1)",
    "mixed % (ulong)jump_count",
    "distance += jump_distances[jump_index];",
    "uint q_base = jump_index << 3;",
    "jacobian_add_affine_values",
    "out_flags[id] = (inf ? 1 : 0) | ((!inf && ((x0 & dp_mask) == 0)) ? 2 : 0);",
)
for marker in required_kernel_markers:
    if marker not in body:
        raise SystemExit("missing dynamic jump walk kernel marker: " + marker)

for forbidden in (
    "constant uchar* jump_indices",
    "jump_indices[",
    "uint jump_base",
):
    if forbidden in body:
        raise SystemExit("dynamic jump walk kernel must not use host-precomputed jump indices: " + forbidden)

dp4_kernel_name = "jacobian_affine_walk_dynamic_jump_table_steps8_dp4"
if f"kernel void {dp4_kernel_name}" not in kernel_source:
    raise SystemExit(f"{dp4_kernel_name} kernel missing from Metal source")

dp4_start = kernel_source.index(f"kernel void {dp4_kernel_name}")
dp4_next_kernel = kernel_source.find("\nkernel void ", dp4_start + 1)
dp4_end_marker = kernel_source.find("\n)RCK_METAL", dp4_start + 1)
dp4_end = dp4_next_kernel if dp4_next_kernel != -1 and dp4_next_kernel < dp4_end_marker else dp4_end_marker
dp4_body = kernel_source[dp4_start:dp4_end]

required_dp4_markers = (
    "constant AffineJumpValue* q_xy [[buffer(1)]]",
    "constant uchar* p_infinity [[buffer(2)]]",
    "bool inf = p_infinity[id];",
    "for (uint step = 0; step < 8; step++)",
    "ulong mixed = x0 ^ (x1 << 7) ^ (y0 >> 3) ^ z0;",
    "mixed *= 0xff51afd7ed558ccdUL;",
    "((jump_count & (jump_count - 1)) == 0)",
    "distance += jump_distances[jump_index];",
    "q_xy[jump_index].x0",
    "q_xy[jump_index].y3",
    "jacobian_add_affine_finite_values",
    "(x0 & 0xFUL) == 0",
)
for marker in required_dp4_markers:
    if marker not in dp4_body:
        raise SystemExit("missing dynamic dp4 jump walk kernel marker: " + marker)

for forbidden in (
    "constant uchar* jump_indices",
    "jump_indices[",
    "uint q_base = jump_index << 3",
    "constant ulong& dp_mask",
):
    if forbidden in dp4_body:
        raise SystemExit("dynamic dp4 jump walk kernel has stale generic marker: " + forbidden)

required_host_markers = (
    "RunJacobianDynamicJumpWalkKernel",
    "\"jacobian_affine_walk_dynamic_jump_table\"",
    "\"jacobian_affine_walk_dynamic_jump_table_steps8_dp4\"",
    "const bool use_dynamic_dp4_specialization = steps_per_sample == 8 && dp_bits == 4;",
    "std::vector<uint8_t> dynamic_p_infinity;",
    "dynamic_p_infinity.push_back(p_infinity_value ? 1U : 0U);",
    "CpuJacobianDynamicJumpWalk",
    "CpuJacobianJumpIndex",
    "RCKMetalJacobianDynamicWalkSelfTest",
    "RCKMetalJacobianDynamicWalkBenchJson",
    "\\\"jump_index\\\":\\\"",
)
for marker in required_host_markers:
    if marker not in host_source:
        raise SystemExit("missing dynamic jump walk host marker: " + marker)

for marker in (
    "metal-jacobian-dynamic-walk-test",
    "metal-jacobian-dynamic-walk-bench",
    "RCKMetalJacobianDynamicWalkSelfTest",
    "RCKMetalJacobianDynamicWalkBenchJson",
):
    if marker not in cli_source:
        raise SystemExit("missing dynamic jump walk CLI marker: " + marker)

print("metal dynamic jump walk source ok")
