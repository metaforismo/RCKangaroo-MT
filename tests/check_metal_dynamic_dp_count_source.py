#!/usr/bin/env python3
from pathlib import Path


kernel_source = Path("macos/MetalFieldKernels.h").read_text()
host_source = Path("macos/MetalField.mm").read_text()
header_source = Path("macos/MetalField.h").read_text()
cli_source = Path("macos/rck_macos.cpp").read_text()
makefile = Path("Makefile").read_text()

kernel_name = "jacobian_affine_walk_dynamic_dp_count_steps8_pow2_mask"
if f"kernel void {kernel_name}" not in kernel_source:
    raise SystemExit(f"{kernel_name} kernel missing from Metal source")

start = kernel_source.index(f"kernel void {kernel_name}")
next_kernel = kernel_source.find("\nkernel void ", start + 1)
end_marker = kernel_source.find("\n)RCK_METAL", start + 1)
end = next_kernel if next_kernel != -1 and next_kernel < end_marker else end_marker
body = kernel_source[start:end]

required_kernel_markers = (
    "device atomic_uint* out_dp_count [[buffer(4)]]",
    "constant ulong& dp_mask [[buffer(10)]]",
    "if (!inf && ((x0 & dp_mask) == 0))",
    "atomic_fetch_add_explicit(out_dp_count, 1U, memory_order_relaxed)",
)
for marker in required_kernel_markers:
    if marker not in body:
        raise SystemExit("missing dynamic dp count kernel marker: " + marker)

for forbidden in (
    "device uint* out_indices",
    "device ulong* out_distances",
    "device ulong* out_dp_terms",
    "out_indices[",
    "out_distances[",
    "out_dp_terms[",
    "(x0 & 0xFUL) == 0",
):
    if forbidden in body:
        raise SystemExit("dynamic dp count kernel must not keep marker: " + forbidden)

required_host_markers = (
    "\"jacobian_affine_walk_dynamic_dp_count_steps8_pow2_mask\"",
    "RunJacobianDynamicDpCountKernel",
    "MetalJacobianDynamicDpCountBenchJson",
    "RCKMetalJacobianDynamicDpCountBenchJson",
    "\\\"output_layout\\\":\\\"dp_count\\\"",
    "\\\"output_bytes_total\\\":4",
    "ProjectiveDpMask(dp_bits)",
)
for marker in required_host_markers:
    if marker not in host_source:
        raise SystemExit("missing dynamic dp count host marker: " + marker)

if "RCKMetalJacobianDynamicDpCountBenchJson" not in header_source:
    raise SystemExit("missing dynamic dp count header declaration")

for marker in (
    "metal-jacobian-dynamic-dp-count-bench",
    "RCKMetalJacobianDynamicDpCountBenchJson",
):
    if marker not in cli_source:
        raise SystemExit("missing dynamic dp count CLI marker: " + marker)

for marker in (
    "macos-metal-dynamic-dp-count-source-check",
    "macos-metal-jacobian-dynamic-dp-count-dp8-bench",
    "macos-metal-jacobian-dynamic-dp-count-dp8-stable-bench",
):
    if marker not in makefile:
        raise SystemExit("missing dynamic dp count Makefile marker: " + marker)

experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_count_dp8.json")
if not experiment.exists():
    raise SystemExit("missing dynamic dp count dp8 autoresearch experiment")

print("metal dynamic dp count source ok")
