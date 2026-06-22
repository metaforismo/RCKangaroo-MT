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
    "use_stream_dp4_specialization",
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
