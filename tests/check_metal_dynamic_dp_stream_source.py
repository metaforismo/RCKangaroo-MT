#!/usr/bin/env python3
from pathlib import Path


kernel_source = Path("macos/MetalFieldKernels.h").read_text()
host_source = Path("macos/MetalField.mm").read_text()
header_source = Path("macos/MetalField.h").read_text()
cli_source = Path("macos/rck_macos.cpp").read_text()
makefile = Path("Makefile").read_text()

kernel_name = "jacobian_affine_walk_dynamic_dp_stream_steps8_dp4_pow2"
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
    "constant ulong* jump_distances [[buffer(8)]]",
    "device ulong* out_distances [[buffer(9)]]",
    "device ulong* out_dp_terms [[buffer(10)]]",
    "constant uint& jump_mask [[buffer(11)]]",
    "constant uint& dp_capacity [[buffer(12)]]",
    "atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed)",
    "out_indices[slot] = id;",
    "out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (z0 << 7);",
)
for marker in required_kernel_markers:
    if marker not in body:
        raise SystemExit("missing dynamic dp stream kernel marker: " + marker)

for forbidden in (
    "device ulong* out_xyz",
    "store_jacobian_xyz_only",
    "constant uchar* jump_indices",
    "jump_indices[",
    "out_flags",
):
    if forbidden in body:
        raise SystemExit("dynamic dp stream kernel must not keep full-output marker: " + forbidden)

required_host_markers = (
    "RunJacobianDynamicDpStreamKernel",
    "RCKMetalJacobianDynamicDpStreamSelfTest",
    "RCKMetalJacobianDynamicDpStreamBenchJson",
    "\"jacobian_affine_walk_dynamic_dp_stream_steps8_dp4_pow2\"",
    "\"jacobian_affine_walk_dynamic_dp_stream\"",
    "\\\"output_layout\\\":\\\"dp_stream\\\"",
    "\\\"output_bytes_per_record\\\":20",
    "\\\"emitted_records\\\":",
    "\\\"dp_stream_overflow\\\":",
    "out_indices",
)
for marker in required_host_markers:
    if marker not in host_source:
        raise SystemExit("missing dynamic dp stream host marker: " + marker)

for marker in (
    "RCKMetalJacobianDynamicDpStreamSelfTest",
    "RCKMetalJacobianDynamicDpStreamBenchJson",
):
    if marker not in header_source:
        raise SystemExit("missing dynamic dp stream header marker: " + marker)

for marker in (
    "metal-jacobian-dynamic-dp-stream-test",
    "metal-jacobian-dynamic-dp-stream-bench",
    "RCKMetalJacobianDynamicDpStreamSelfTest",
    "RCKMetalJacobianDynamicDpStreamBenchJson",
):
    if marker not in cli_source:
        raise SystemExit("missing dynamic dp stream CLI marker: " + marker)

for marker in (
    "macos-metal-dynamic-dp-stream-source-check",
    "macos-metal-jacobian-dynamic-dp-stream-test",
    "macos-metal-jacobian-dynamic-dp-stream-bench",
    "macos-metal-jacobian-dynamic-dp-stream-stable-bench",
):
    if marker not in makefile:
        raise SystemExit("missing dynamic dp stream Makefile marker: " + marker)

experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream.json")
if not experiment.exists():
    raise SystemExit("missing dynamic dp stream autoresearch experiment")

print("metal dynamic dp stream source ok")
