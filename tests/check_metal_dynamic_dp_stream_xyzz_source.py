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
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp12_pow2_u32_distance",
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp12_pow2_u32_distance",
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_dp12_pow2_u32_distance",
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_dp12_pow2_u32_distance",
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp16_pow2_u32_distance",
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp16_pow2_u32_distance",
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_dp16_pow2_u32_distance",
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_dp16_pow2_u32_distance",
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_pow2_u32_distance",
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_pow2_u32_distance",
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_pow2_u32_distance",
    "kernel void jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_pow2_u32_distance",
    "if (!out.inf && ((out.x0 & 0xFFFUL) == 0))",
    "if (!out.inf && ((out.x0 & 0xFFFFUL) == 0))",
    "constant ulong& dp_mask [[buffer(14)]]",
    "if (!out.inf && ((out.x0 & dp_mask) == 0))",
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
    "ValidateDynamicXyzzDpStreamAndStateOutputs",
    "ValidateDynamicXyzzChainDpStreamAndStateOutputs",
    "RCKMetalJacobianDynamicDpStreamXyzzSelfTest",
    "RCKMetalJacobianDynamicDpStreamXyzzBenchJson",
    "RCKMetalJacobianDynamicDpStreamXyzzChainBenchJson",
    "RCKMetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson",
    "RCKMetalJacobianDynamicDpStreamXyzzAffineScanBenchJson",
    "RunJacobianDynamicDpStreamXyzzChainKernel",
    "RunJacobianDynamicDpStreamXyzzPersistentChainKernel",
    "CpuXyzzBatchAffineDpScan",
    "affine_scan_mode",
    "cpu_batch_prod_zz_zzz",
    "affine_scan_seconds",
    "\\\"dp_tracking\\\":\\\"affine_x_limb0_cpu_batch\\\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp8_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp8_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_dp8_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_dp8_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp12_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp12_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_dp12_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_dp12_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp16_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp16_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_dp16_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_dp16_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_pow2_u32_distance\"",
    "\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_pow2_u32_distance\"",
    "use_xyzz_dp8_specialization",
    "use_xyzz_dp12_specialization",
    "use_xyzz_dp16_specialization",
    "use_xyzz_hardcoded_dp_specialization",
    "ProjectiveDpMask(dp_bits)",
    "dp_mask_buffer",
    "[encoder setBuffer:dp_mask_buffer offset:0 atIndex:14]",
    "\\\"state_layout\\\":\\\"xyzz\\\"",
    "\\\"packet_count\\\":",
    "\\\"packets_per_round\\\":",
    "\\\"round_count\\\":",
    "\\\"setup_mode\\\":\\\"reuse_pipeline_buffers\\\"",
    "\\\"state_persistence\\\":\\\"round_cumulative_xyzz\\\"",
    "steps_per_sample != 256 && steps_per_sample != 512",
    "CanAccumulateDistanceU32(jump_distances, steps_per_sample)",
    "XYZZ dynamic dp stream packet distance exceeds uint32 accumulator",
    "dp_stream_cumulative_uint64",
    "RCK_VALIDATION_WORKERS",
    "ParallelForSamples(p.size()",
    "std::thread::hardware_concurrency()",
    "steps_per_sample >= 256",
    "EffectiveDynamicDpStreamXyzzThreadgroupLimit",
    "EffectiveDynamicDpStreamXyzzThreadgroupLimit(threadgroup_limit, dp_bits, steps_per_sample)",
    "kDefaultMetalLongDpStreamThreadgroupLimit = 512",
    "return (NSUInteger)kDefaultMetalLongDpStreamThreadgroupLimit;",
    "\\\"validation_workers\\\"",
    "\\\"validation_seconds\\\"",
    "emitted_indices_bytes",
    "emitted_distances_bytes",
    "emitted_dp_terms_bytes",
)
for marker in required_host_markers:
    if marker not in host_source:
        raise SystemExit("missing XYZZ host marker: " + marker)

xyzz_bench_start = host_source.index("std::string RCKMetalJacobianDynamicDpStreamXyzzBenchJson")
xyzz_bench_end = host_source.index("std::string RCKMetalJacobianDynamicDpCountBenchJson", xyzz_bench_start)
xyzz_bench_body = host_source[xyzz_bench_start:xyzz_bench_end]
if "ValidateDynamicXyzzDpStreamAndStateOutputs" not in xyzz_bench_body:
    raise SystemExit("XYZZ bench should validate DP stream and final state in one replay")
if "ValidateDynamicXyzzDpStreamOutputs(" in xyzz_bench_body or "ValidateDynamicXyzzStateOutputs(" in xyzz_bench_body:
    raise SystemExit("XYZZ bench should not replay DP stream and final state separately")

for marker in (
    "RCKMetalJacobianDynamicDpStreamXyzzSelfTest",
    "RCKMetalJacobianDynamicDpStreamXyzzBenchJson",
    "RCKMetalJacobianDynamicDpStreamXyzzChainBenchJson",
    "RCKMetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson",
    "RCKMetalJacobianDynamicDpStreamXyzzAffineScanBenchJson",
):
    if marker not in header_source:
        raise SystemExit("missing XYZZ header marker: " + marker)

for marker in (
    "metal-jacobian-dynamic-dp-stream-xyzz-test",
    "metal-jacobian-dynamic-dp-stream-xyzz-bench",
    "metal-jacobian-dynamic-dp-stream-xyzz-chain-bench",
    "metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench",
    "metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-bench",
    "RCKMetalJacobianDynamicDpStreamXyzzSelfTest",
    "RCKMetalJacobianDynamicDpStreamXyzzBenchJson",
    "RCKMetalJacobianDynamicDpStreamXyzzChainBenchJson",
    "RCKMetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson",
    "RCKMetalJacobianDynamicDpStreamXyzzAffineScanBenchJson",
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
    "macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-saturated-bench",
    "macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-large-batch-bench",
    "macos-metal-jacobian-dynamic-dp-stream-xyzz-chain-steps512-bench",
    "macos-metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-steps512-bench",
    "macos-metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-bench",
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

saturated_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_steps512_saturated.json")
if not saturated_experiment.exists():
    raise SystemExit("missing XYZZ steps512 saturated autoresearch experiment")
saturated_payload = json.loads(saturated_experiment.read_text(encoding="utf-8"))
expected_saturated_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-bench",
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--min-ms",
    "500",
]
if saturated_payload.get("bench_command") != expected_saturated_command:
    raise SystemExit("XYZZ steps512 saturated experiment should run the saturated batch CLI")
if "paired_baseline_command" in saturated_payload:
    raise SystemExit("XYZZ steps512 saturated experiment should not mix packet and batch-size baselines")
if int(saturated_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ steps512 saturated experiment should keep sample_runs >= 3")

large_batch_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_steps512_large_batch.json")
if not large_batch_experiment.exists():
    raise SystemExit("missing XYZZ steps512 large-batch autoresearch experiment")
large_batch_payload = json.loads(large_batch_experiment.read_text(encoding="utf-8"))
expected_large_batch_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-bench",
    "--iterations",
    "524288",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--min-ms",
    "500",
]
if large_batch_payload.get("bench_command") != expected_large_batch_command:
    raise SystemExit("XYZZ steps512 large-batch experiment should run the 524288-state CLI")
if "paired_baseline_command" in large_batch_payload:
    raise SystemExit("XYZZ steps512 large-batch experiment should not mix packet and batch-size baselines")
if int(large_batch_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ steps512 large-batch experiment should keep sample_runs >= 3")

affine_scan_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_affine_scan_steps512.json")
if not affine_scan_experiment.exists():
    raise SystemExit("missing XYZZ affine-scan steps512 autoresearch experiment")
affine_scan_payload = json.loads(affine_scan_experiment.read_text(encoding="utf-8"))
expected_affine_scan_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-bench",
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--min-ms",
    "500",
]
if affine_scan_payload.get("bench_command") != expected_affine_scan_command:
    raise SystemExit("XYZZ affine-scan experiment should run the affine packet-boundary CLI")
if int(affine_scan_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ affine-scan experiment should keep sample_runs >= 3")

chain_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_chain_steps512.json")
if not chain_experiment.exists():
    raise SystemExit("missing XYZZ chain steps512 autoresearch experiment")
chain_payload = json.loads(chain_experiment.read_text(encoding="utf-8"))
expected_chain_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-chain-bench",
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--packets",
    "2",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--min-ms",
    "500",
]
if chain_payload.get("build_target") != "macos-build":
    raise SystemExit("XYZZ chain experiment should use macos-build")
if chain_payload.get("bench_command") != expected_chain_command:
    raise SystemExit("XYZZ chain experiment should run the cumulative chain CLI")
if "paired_baseline_command" in chain_payload:
    raise SystemExit("XYZZ chain experiment should be tracked as a separate cumulative-distance operation")
if int(chain_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ chain experiment should keep sample_runs >= 3")

chain_packets4_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_chain_packets4_steps512.json")
if not chain_packets4_experiment.exists():
    raise SystemExit("missing XYZZ chain packets4 steps512 autoresearch experiment")
chain_packets4_payload = json.loads(chain_packets4_experiment.read_text(encoding="utf-8"))
expected_chain_packets4_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-chain-bench",
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--packets",
    "4",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--min-ms",
    "0",
]
if chain_packets4_payload.get("build_target") != "macos-build":
    raise SystemExit("XYZZ chain packets4 experiment should use macos-build")
if chain_packets4_payload.get("bench_command") != expected_chain_packets4_command:
    raise SystemExit("XYZZ chain packets4 experiment should run the four-packet cumulative chain CLI")
if "paired_baseline_command" in chain_packets4_payload:
    raise SystemExit("XYZZ chain packets4 experiment should be tracked as a separate cumulative-distance operation")
if int(chain_packets4_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ chain packets4 experiment should keep sample_runs >= 3")
if int(chain_packets4_payload.get("cooldown_sec", 0)) < 10:
    raise SystemExit("XYZZ chain packets4 experiment should cool down between long samples")

chain_scaled_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_chain_scaled4_balanced.json")
if not chain_scaled_experiment.exists():
    raise SystemExit("missing XYZZ chain scaled4 autoresearch experiment")
chain_scaled_payload = json.loads(chain_scaled_experiment.read_text(encoding="utf-8"))
expected_chain_scaled_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-chain-bench",
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--packets",
    "2",
    "--jumps",
    "4",
    "--dp-bits",
    "8",
    "--min-ms",
    "500",
    "--jump-schedule",
    "scaled4-balanced",
]
if chain_scaled_payload.get("build_target") != "macos-build":
    raise SystemExit("XYZZ chain scaled4 experiment should use macos-build")
if chain_scaled_payload.get("bench_command") != expected_chain_scaled_command:
    raise SystemExit("XYZZ chain scaled4 experiment should run the scaled schedule chain CLI")
if chain_scaled_payload.get("paired_baseline_command") != expected_chain_command:
    raise SystemExit("XYZZ chain scaled4 experiment should compare against the matching power2 chain")
if int(chain_scaled_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ chain scaled4 experiment should keep sample_runs >= 3")

persistent_chain_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_persistent_chain_steps512.json")
if not persistent_chain_experiment.exists():
    raise SystemExit("missing XYZZ persistent chain steps512 autoresearch experiment")
persistent_chain_payload = json.loads(persistent_chain_experiment.read_text(encoding="utf-8"))
expected_persistent_chain_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench",
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--packets",
    "2",
    "--rounds",
    "2",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
]
expected_persistent_chain_baseline = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-chain-bench",
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--packets",
    "4",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--min-ms",
    "0",
]
if persistent_chain_payload.get("build_target") != "macos-build":
    raise SystemExit("XYZZ persistent chain experiment should use macos-build")
if persistent_chain_payload.get("bench_command") != expected_persistent_chain_command:
    raise SystemExit("XYZZ persistent chain experiment should run the persistent cumulative chain CLI")
if persistent_chain_payload.get("paired_baseline_command") != expected_persistent_chain_baseline:
    raise SystemExit("XYZZ persistent chain experiment should compare against the exact total-packet chain")
if int(persistent_chain_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ persistent chain experiment should keep sample_runs >= 3")
if float(persistent_chain_payload.get("cooldown_sec", 0.0)) < 10.0:
    raise SystemExit("XYZZ persistent chain experiment should cool down between paired samples")

persistent_chain_scaled_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_persistent_chain_scaled4_balanced.json")
if not persistent_chain_scaled_experiment.exists():
    raise SystemExit("missing XYZZ persistent chain scaled4 autoresearch experiment")
persistent_chain_scaled_payload = json.loads(persistent_chain_scaled_experiment.read_text(encoding="utf-8"))
expected_persistent_chain_scaled_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench",
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--packets",
    "2",
    "--rounds",
    "2",
    "--jumps",
    "4",
    "--dp-bits",
    "8",
    "--jump-schedule",
    "scaled4-balanced",
]
if persistent_chain_scaled_payload.get("build_target") != "macos-build":
    raise SystemExit("XYZZ persistent chain scaled4 experiment should use macos-build")
if persistent_chain_scaled_payload.get("bench_command") != expected_persistent_chain_scaled_command:
    raise SystemExit("XYZZ persistent chain scaled4 experiment should run the scaled schedule persistent CLI")
if persistent_chain_scaled_payload.get("paired_baseline_command") != expected_persistent_chain_command:
    raise SystemExit("XYZZ persistent chain scaled4 experiment should compare against the matching power2 persistent chain")
if int(persistent_chain_scaled_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ persistent chain scaled4 experiment should keep sample_runs >= 3")
if float(persistent_chain_scaled_payload.get("cooldown_sec", 0.0)) < 10.0:
    raise SystemExit("XYZZ persistent chain scaled4 experiment should cool down between paired samples")

xyzz_dp12_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_dp12_steps512.json")
if not xyzz_dp12_experiment.exists():
    raise SystemExit("missing XYZZ DP12 steps512 autoresearch experiment")
xyzz_dp12_payload = json.loads(xyzz_dp12_experiment.read_text(encoding="utf-8"))
expected_xyzz_dp12_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-bench",
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "12",
    "--min-ms",
    "500",
]
if xyzz_dp12_payload.get("build_target") != "macos-build":
    raise SystemExit("XYZZ DP12 experiment should use macos-build")
if xyzz_dp12_payload.get("bench_command") != expected_xyzz_dp12_command:
    raise SystemExit("XYZZ DP12 experiment should run the DP12 packet CLI")
if int(xyzz_dp12_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ DP12 experiment should keep sample_runs >= 3")
if float(xyzz_dp12_payload.get("cooldown_sec", 0.0)) < 10.0:
    raise SystemExit("XYZZ DP12 experiment should cool down between samples")

xyzz_dp16_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_dp16_steps512.json")
if not xyzz_dp16_experiment.exists():
    raise SystemExit("missing XYZZ DP16 steps512 autoresearch experiment")
xyzz_dp16_payload = json.loads(xyzz_dp16_experiment.read_text(encoding="utf-8"))
expected_xyzz_dp16_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-bench",
    "--iterations",
    "262144",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "16",
    "--min-ms",
    "500",
]
if xyzz_dp16_payload.get("build_target") != "macos-build":
    raise SystemExit("XYZZ DP16 experiment should use macos-build")
if xyzz_dp16_payload.get("bench_command") != expected_xyzz_dp16_command:
    raise SystemExit("XYZZ DP16 experiment should run the DP16 packet CLI")
if int(xyzz_dp16_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ DP16 experiment should keep sample_runs >= 3")
if float(xyzz_dp16_payload.get("cooldown_sec", 0.0)) < 10.0:
    raise SystemExit("XYZZ DP16 experiment should cool down between samples")

persistent_chain_dp12_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_persistent_chain_dp12_steps512.json")
if not persistent_chain_dp12_experiment.exists():
    raise SystemExit("missing XYZZ persistent chain DP12 autoresearch experiment")
persistent_chain_dp12_payload = json.loads(persistent_chain_dp12_experiment.read_text(encoding="utf-8"))
expected_persistent_chain_dp12_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench",
    "--iterations",
    "131072",
    "--steps",
    "512",
    "--packets",
    "2",
    "--rounds",
    "2",
    "--jumps",
    "16",
    "--dp-bits",
    "12",
]
if persistent_chain_dp12_payload.get("build_target") != "macos-build":
    raise SystemExit("XYZZ persistent chain DP12 experiment should use macos-build")
if persistent_chain_dp12_payload.get("bench_command") != expected_persistent_chain_dp12_command:
    raise SystemExit("XYZZ persistent chain DP12 experiment should run the persistent DP12 CLI")
if int(persistent_chain_dp12_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ persistent chain DP12 experiment should keep sample_runs >= 3")
if float(persistent_chain_dp12_payload.get("cooldown_sec", 0.0)) < 10.0:
    raise SystemExit("XYZZ persistent chain DP12 experiment should cool down between samples")

persistent_chain_dp16_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_persistent_chain_dp16_steps512.json")
if not persistent_chain_dp16_experiment.exists():
    raise SystemExit("missing XYZZ persistent chain DP16 autoresearch experiment")
persistent_chain_dp16_payload = json.loads(persistent_chain_dp16_experiment.read_text(encoding="utf-8"))
expected_persistent_chain_dp16_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench",
    "--iterations",
    "131072",
    "--steps",
    "512",
    "--packets",
    "2",
    "--rounds",
    "2",
    "--jumps",
    "16",
    "--dp-bits",
    "16",
]
if persistent_chain_dp16_payload.get("build_target") != "macos-build":
    raise SystemExit("XYZZ persistent chain DP16 experiment should use macos-build")
if persistent_chain_dp16_payload.get("bench_command") != expected_persistent_chain_dp16_command:
    raise SystemExit("XYZZ persistent chain DP16 experiment should run the persistent DP16 CLI")
if int(persistent_chain_dp16_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ persistent chain DP16 experiment should keep sample_runs >= 3")
if float(persistent_chain_dp16_payload.get("cooldown_sec", 0.0)) < 10.0:
    raise SystemExit("XYZZ persistent chain DP16 experiment should cool down between samples")

xyzz_tg512_default_experiment = Path("autoresearch/experiments/metal_jacobian_dynamic_dp_stream_xyzz_steps512_tg512_default.json")
if not xyzz_tg512_default_experiment.exists():
    raise SystemExit("missing XYZZ tg512 default autoresearch experiment")
xyzz_tg512_default_payload = json.loads(xyzz_tg512_default_experiment.read_text(encoding="utf-8"))
expected_xyzz_tg512_default_command = [
    "./macos/rck_macos",
    "metal-jacobian-dynamic-dp-stream-xyzz-bench",
    "--iterations",
    "524288",
    "--steps",
    "512",
    "--jumps",
    "16",
    "--dp-bits",
    "8",
    "--min-ms",
    "500",
]
if xyzz_tg512_default_payload.get("build_target") != "macos-build":
    raise SystemExit("XYZZ tg512 default experiment should use macos-build")
if xyzz_tg512_default_payload.get("bench_command") != expected_xyzz_tg512_default_command:
    raise SystemExit("XYZZ tg512 default experiment should run the default-threadgroup packet CLI")
if xyzz_tg512_default_payload.get("paired_baseline_command") != expected_xyzz_tg512_default_command:
    raise SystemExit("XYZZ tg512 default experiment should compare the same CLI across commits")
if int(xyzz_tg512_default_payload.get("sample_runs", 0)) < 3:
    raise SystemExit("XYZZ tg512 default experiment should keep sample_runs >= 3")
if float(xyzz_tg512_default_payload.get("cooldown_sec", 0.0)) < 10.0:
    raise SystemExit("XYZZ tg512 default experiment should cool down between paired samples")

print("metal dynamic dp stream XYZZ source ok")
