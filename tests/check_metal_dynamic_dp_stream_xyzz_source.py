#!/usr/bin/env python3
import json
from pathlib import Path


kernel_source = Path("macos/MetalFieldKernels.h").read_text()
host_source = Path("macos/MetalField.mm").read_text()
header_source = Path("macos/MetalField.h").read_text()
cli_source = Path("macos/rck_macos.cpp").read_text()
makefile = Path("Makefile").read_text()

required_kernel_markers = (
    "struct XyzzValue",
    "jacobian_add_affine_xyzz_values",
    "field_mul_values(zz0, zz1, zz2, zz3, hh0, hh1, hh2, hh3, zz_out0",
    "field_mul_values(zzz0, zzz1, zzz2, zzz3, hhh0, hhh1, hhh2, hhh3, zzz_out0",
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp8_pow2_u32_distance",
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp8_pow2_u32_distance",
    "device ulong* p_xyzz [[buffer(0)]]",
    "out_dp_terms[slot] = x0 ^ (y0 << 1) ^ (zz0 << 7) ^ (zzz0 << 13);",
)
for marker in required_kernel_markers:
    if marker not in kernel_source:
        raise SystemExit("missing XYZZ kernel marker: " + marker)

xyzz_kernel_start = kernel_source.index(
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp8_pow2_u32_distance"
)
xyzz_kernel_end_marker = kernel_source.find("\n)RCK_METAL", xyzz_kernel_start)
xyzz_kernel_body = kernel_source[xyzz_kernel_start:xyzz_kernel_end_marker]
if "field_square_values(z0, z1, z2, z3" in xyzz_kernel_body:
    raise SystemExit("XYZZ packet kernel must not recompute z^2 inside the hot loop")
if "field_mul_values(z20, z21, z22, z23, z0" in xyzz_kernel_body:
    raise SystemExit("XYZZ packet kernel must not recompute z^3 inside the hot loop")
if "step < 256" not in xyzz_kernel_body:
    raise SystemExit("XYZZ packet kernel must run the 256-step candidate")

xyzz_steps512_start = kernel_source.index(
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp8_pow2_u32_distance"
)
xyzz_steps512_end = kernel_source.find("\n", xyzz_steps512_start)
xyzz_steps512_body_end = kernel_source.find("\nkernel void ", xyzz_steps512_start + 1)
xyzz_steps512_body = kernel_source[xyzz_steps512_start:xyzz_steps512_body_end]
if "step < 512" not in xyzz_steps512_body:
    raise SystemExit("XYZZ packet steps512 kernel must run 512 dynamic jumps")

required_host_markers = (
    "RunJacobianDynamicDpStreamXyzzKernel",
    "PackJacobianXyzzStateInputs",
    "ValidateDynamicXyzzStateOutputs",
    "RCKMetalJacobianDynamicDpStreamXyzzSelfTest",
    "RCKMetalJacobianDynamicDpStreamXyzzBenchJson",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp8_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp8_pow2_u32_distance\"",
    "\\\"state_layout\\\":\\\"xyzz\\\"",
    "steps_per_sample != 256 && steps_per_sample != 512",
)
for marker in required_host_markers:
    if marker not in host_source:
        raise SystemExit("missing XYZZ host marker: " + marker)

for marker in (
    "RCKMetalJacobianDynamicDpStreamXyzzSelfTest",
    "RCKMetalJacobianDynamicDpStreamXyzzBenchJson",
):
    if marker not in header_source:
        raise SystemExit("missing XYZZ header marker: " + marker)

for marker in (
    "metal-jacobian-dynamic-dp-stream-xyzz-test",
    "metal-jacobian-dynamic-dp-stream-xyzz-bench",
    "RCKMetalJacobianDynamicDpStreamXyzzSelfTest",
    "RCKMetalJacobianDynamicDpStreamXyzzBenchJson",
):
    if marker not in cli_source:
        raise SystemExit("missing XYZZ CLI marker: " + marker)

for marker in (
    "macos-metal-dynamic-dp-stream-xyzz-source-check",
    "macos-metal-jacobian-dynamic-dp-stream-xyzz-test",
    "macos-metal-jacobian-dynamic-dp-stream-xyzz-steps256-bench",
    "macos-metal-jacobian-dynamic-dp-stream-xyzz-steps256-stable-bench",
    "macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-bench",
    "macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-stable-bench",
):
    if marker not in makefile:
        raise SystemExit("missing XYZZ Makefile marker: " + marker)

experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_steps256.json")
if not experiment.exists():
    raise SystemExit("missing XYZZ autoresearch experiment")
payload = json.loads(experiment.read_text(encoding="utf-8"))
expected_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-bench",
    "--iterations",
    "16384",
    "--steps",
    "256",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--min-ms",
    "200",
]
if payload.get("bench_command") != expected_command:
    raise SystemExit("XYZZ autoresearch experiment should run the steps256 XYZZ CLI")
expected_baseline = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-inplace-bench",
    "--iterations",
    "16384",
    "--steps",
    "256",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--min-ms",
    "200",
]
if payload.get("paired_baseline_command") != expected_baseline:
    raise SystemExit("XYZZ autoresearch experiment should compare against accepted in-place steps256")
if int(payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ autoresearch experiment should keep sample_runs >= 3")

steps512_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_steps512.json")
if not steps512_experiment.exists():
    raise SystemExit("missing XYZZ steps512 autoresearch experiment")
steps512_payload = json.loads(steps512_experiment.read_text(encoding="utf-8"))
expected_steps512_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-bench",
    "--iterations",
    "16384",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--min-ms",
    "200",
]
if steps512_payload.get("bench_command") != expected_steps512_command:
    raise SystemExit("XYZZ steps512 autoresearch experiment should run the steps512 XYZZ CLI")
if steps512_payload.get("paired_baseline_command") != expected_command:
    raise SystemExit("XYZZ steps512 autoresearch experiment should compare against accepted XYZZ steps256")
if int(steps512_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ steps512 autoresearch experiment should keep sample_runs >= 3")

print("metal dynamic dp stream XYZZ source ok")
