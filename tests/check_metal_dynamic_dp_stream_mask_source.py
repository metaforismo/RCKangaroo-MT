#!/usr/bin/env python3
from pathlib import Path


kernel_source = Path("macos/MetalFieldKernels.h").read_text()
host_source = Path("macos/MetalField.mm").read_text()
makefile = Path("Makefile").read_text()

kernel_name = "jacobian_affine_walk_dynamic_dp_stream_steps8_pow2_mask"
if f"kernel void {kernel_name}" not in kernel_source:
    raise SystemExit(f"{kernel_name} kernel missing from Metal source")

start = kernel_source.index(f"kernel void {kernel_name}")
next_kernel = kernel_source.find("\nkernel void ", start + 1)
end_marker = kernel_source.find("\n)RCK_METAL", start + 1)
end = next_kernel if next_kernel != -1 and next_kernel < end_marker else end_marker
body = kernel_source[start:end]

required_kernel_markers = (
    "device atomic_uint* out_dp_count [[buffer(4)]]",
    "device uint* out_indices [[buffer(5)]]",
    "constant ulong& dp_mask [[buffer(14)]]",
    "if (!inf && ((x0 & dp_mask) == 0))",
    "atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed)",
    "out_indices[slot] = id;",
    "out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);",
)
for marker in required_kernel_markers:
    if marker not in body:
        raise SystemExit("missing dynamic dp stream mask kernel marker: " + marker)

u32_kernel_name = "jacobian_affine_walk_dynamic_dp_stream_steps8_pow2_mask_u32_distance"
if f"kernel void {u32_kernel_name}" not in kernel_source:
    raise SystemExit(f"{u32_kernel_name} kernel missing from Metal source")

u32_start = kernel_source.index(f"kernel void {u32_kernel_name}")
u32_next = kernel_source.find("\nkernel void ", u32_start + 1)
u32_end_marker = kernel_source.find("\n)RCK_METAL", u32_start + 1)
u32_end = u32_next if u32_next != -1 and u32_next < u32_end_marker else u32_end_marker
u32_body = kernel_source[u32_start:u32_end]

required_u32_markers = (
    "constant ulong& dp_mask [[buffer(14)]]",
    "uint distance = 0;",
    "distance += (uint)jump_distances[jump_index];",
    "out_distances[slot] = (ulong)distance;",
    "out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);",
)
for marker in required_u32_markers:
    if marker not in u32_body:
        raise SystemExit("missing dynamic dp stream u32-distance marker: " + marker)

if "ulong distance = 0;" in u32_body:
    raise SystemExit("u32-distance stream kernel must not keep a ulong accumulator")

for forbidden in (
    "(x0 & 0xFUL) == 0",
    "device ulong* out_xyz",
    "store_jacobian_xyz_only",
    "constant uchar* jump_indices",
    "jump_indices[",
):
    if forbidden in body:
        raise SystemExit("dynamic dp stream mask kernel must not keep marker: " + forbidden)

required_host_markers = (
    "\"jacobian_affine_walk_dynamic_dp_stream_steps8_pow2_mask\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_steps8_pow2_mask_u32_distance\"",
    "use_stream_dp4_specialization",
    "CanAccumulateDistanceU32(jump_distances, steps_per_sample)",
    "use_stream_u32_distance",
    "ProjectiveDpMask(dp_bits)",
    "dp_mask_buffer",
    "[encoder setBuffer:dp_mask_buffer offset:0 atIndex:14]",
)
for marker in required_host_markers:
    if marker not in host_source:
        raise SystemExit("missing dynamic dp stream mask host marker: " + marker)

for marker in (
    "macos-metal-dynamic-dp-stream-mask-source-check",
    "macos-metal-jacobian-dynamic-dp-stream-dp8-bench",
    "macos-metal-jacobian-dynamic-dp-stream-dp8-stable-bench",
):
    if marker not in makefile:
        raise SystemExit("missing dynamic dp stream mask Makefile marker: " + marker)

experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_dp8.json")
if not experiment.exists():
    raise SystemExit("missing dynamic dp stream dp8 autoresearch experiment")

print("metal dynamic dp stream mask source ok")
