#!/usr/bin/env python3
from pathlib import Path


kernel_source = Path("macos/MetalFieldKernels.h").read_text()
start = kernel_source.index("kernel void jacobian_affine_walk_jump_table_steps8_dp4")
next_kernel = kernel_source.find("\nkernel void ", start + 1)
end_marker = kernel_source.index("\n)RCK_METAL", start)
end = next_kernel if next_kernel != -1 and next_kernel < end_marker else end_marker
dp4_body = kernel_source[start:end]

if "constant uchar* p_infinity [[buffer(2)]]" not in dp4_body:
    raise SystemExit("dp4 kernel still reads p_infinity as a non-packed type")
if "bool inf = p_infinity[id];" not in dp4_body:
    raise SystemExit("dp4 kernel must keep the existing boolean infinity load")

host_source = Path("macos/MetalField.mm").read_text()
for marker in (
    "const bool use_dp4_specialization = steps_per_sample == 8 && dp_bits == 4;",
    "std::vector<uint8_t> metal_p_infinity;",
    "metal_p_infinity.push_back(p_infinity_value ? 1U : 0U);",
    "const void* p_inf_data = use_dp4_specialization",
    "size_t p_inf_bytes = use_dp4_specialization",
):
    if marker not in host_source:
        raise SystemExit("missing packed p_infinity host marker: " + marker)

print("metal dp4 uchar infinity source ok")
