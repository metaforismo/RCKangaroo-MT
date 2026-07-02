#!/usr/bin/env sh
set -eu

output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations 128 --steps 256 --jumps 8 --dp-bits 8 --min-ms 1 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-bench returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz\""*"\"state_layout\":\"xyzz\""*"\"sample_count\":128"*"\"steps_per_sample\":256"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"jump_schedule\":\"power2\""*"\"output_layout\":\"dp_stream\""*"\"output_bytes_per_record\":20"*"\"emitted_records\":"*"\"dp_stream_overflow\":false"*"\"distance_tracking\":\"dp_stream_uint64\""*"\"dp_tracking\":\"projective_x_limb0\""*"\"dp_bits\":8"*"\"dp_count\":"*"\"dp_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz\""*"\"state_layout\":\"xyzz\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-bench output"
		printf '%s\n' "$output"
		exit 1
		;;
esac

runtime_dp_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations 128 --steps 256 --jumps 8 --dp-bits 12 --min-ms 0 2>&1)"
runtime_dp_status=$?
if [ "$runtime_dp_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-bench runtime dp returned status %s\n' "$runtime_dp_status"
	printf '%s\n' "$runtime_dp_output"
	exit 1
fi

case "$runtime_dp_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz\""*"\"state_layout\":\"xyzz\""*"\"sample_count\":128"*"\"steps_per_sample\":256"*"\"jump_count\":8"*"\"output_layout\":\"dp_stream\""*"\"distance_tracking\":\"dp_stream_uint64\""*"\"dp_bits\":12"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz\""*"\"state_layout\":\"xyzz\""*"\"dp_bits\":12"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected runtime-dp metal-jacobian-dynamic-dp-stream-xyzz-bench output"
		printf '%s\n' "$runtime_dp_output"
		exit 1
		;;
esac

scaled_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations 128 --steps 256 --jumps 4 --dp-bits 8 --min-ms 1 --jump-schedule scaled4-balanced 2>&1)"
scaled_status=$?
if [ "$scaled_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-bench scaled4 returned status %s\n' "$scaled_status"
	printf '%s\n' "$scaled_output"
	exit 1
fi

case "$scaled_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz\""*"\"state_layout\":\"xyzz\""*"\"sample_count\":128"*"\"steps_per_sample\":256"*"\"jump_count\":4"*"\"jump_schedule\":\"scaled4_balanced\""*"\"distance_tracking\":\"dp_stream_uint64\""*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz\""*"\"state_layout\":\"xyzz\""*"\"jump_schedule\":\"scaled4_balanced\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected scaled4 metal-jacobian-dynamic-dp-stream-xyzz-bench output"
		printf '%s\n' "$scaled_output"
		exit 1
		;;
esac

invalid_schedule_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations 128 --steps 256 --jumps 4 --dp-bits 8 --min-ms 1 --jump-schedule unknown 2>&1)"
invalid_schedule_status=$?
if [ "$invalid_schedule_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-bench invalid schedule returned status %s\n' "$invalid_schedule_status"
	printf '%s\n' "$invalid_schedule_output"
	exit 1
fi

case "$invalid_schedule_output" in
	*"\"jump_schedule\":\"invalid\""*"\"correctness\":false"*"\"reason\":\"unknown jump schedule\""*)
		;;
	*)
		printf '%s\n' "unexpected invalid metal jump schedule output"
		printf '%s\n' "$invalid_schedule_output"
		exit 1
		;;
esac

chain_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-chain-bench --iterations 128 --steps 256 --packets 2 --jumps 8 --dp-bits 8 --min-ms 1 2>&1)"
chain_status=$?
if [ "$chain_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-chain-bench returned status %s\n' "$chain_status"
	printf '%s\n' "$chain_output"
	exit 1
fi

case "$chain_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain\""*"\"state_layout\":\"xyzz\""*"\"sample_count\":128"*"\"steps_per_sample\":256"*"\"packet_count\":2"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"jump_schedule\":\"power2\""*"\"output_layout\":\"dp_stream\""*"\"emitted_records\":"*"\"dp_stream_overflow\":false"*"\"distance_tracking\":\"dp_stream_cumulative_uint64\""*"\"dp_bits\":8"*"\"dp_count\":"*"\"dp_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain\""*"\"state_layout\":\"xyzz\""*"\"packet_count\":2"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-chain-bench output"
		printf '%s\n' "$chain_output"
		exit 1
		;;
esac

chain_runtime_dp_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-chain-bench --iterations 128 --steps 256 --packets 2 --jumps 8 --dp-bits 12 --min-ms 0 2>&1)"
chain_runtime_dp_status=$?
if [ "$chain_runtime_dp_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-chain-bench runtime dp returned status %s\n' "$chain_runtime_dp_status"
	printf '%s\n' "$chain_runtime_dp_output"
	exit 1
fi

case "$chain_runtime_dp_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain\""*"\"state_layout\":\"xyzz\""*"\"sample_count\":128"*"\"steps_per_sample\":256"*"\"packet_count\":2"*"\"distance_tracking\":\"dp_stream_cumulative_uint64\""*"\"dp_bits\":12"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain\""*"\"state_layout\":\"xyzz\""*"\"packet_count\":2"*"\"dp_bits\":12"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected runtime-dp metal-jacobian-dynamic-dp-stream-xyzz-chain-bench output"
		printf '%s\n' "$chain_runtime_dp_output"
		exit 1
		;;
esac

chain_scaled_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-chain-bench --iterations 128 --steps 256 --packets 2 --jumps 4 --dp-bits 8 --min-ms 1 --jump-schedule scaled4-balanced 2>&1)"
chain_scaled_status=$?
if [ "$chain_scaled_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-chain-bench scaled4 returned status %s\n' "$chain_scaled_status"
	printf '%s\n' "$chain_scaled_output"
	exit 1
fi

case "$chain_scaled_output" in
	*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain\""*"\"packet_count\":2"*"\"jump_count\":4"*"\"jump_schedule\":\"scaled4_balanced\""*"\"distance_tracking\":\"dp_stream_cumulative_uint64\""*"\"correctness\":true"*)
		;;
	*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain\""*"\"packet_count\":2"*"\"jump_schedule\":\"scaled4_balanced\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected scaled4 metal-jacobian-dynamic-dp-stream-xyzz-chain-bench output"
		printf '%s\n' "$chain_scaled_output"
		exit 1
		;;
esac

chain_invalid_schedule_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-chain-bench --iterations 128 --steps 256 --packets 2 --jumps 16 --dp-bits 8 --min-ms 1 --jump-schedule scaled4-balanced 2>&1)"
case "$chain_invalid_schedule_output" in
	*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain\""*"\"jump_schedule\":\"scaled4_balanced\""*"\"correctness\":false"*"\"reason\":\"scaled4-balanced jump schedule requires --jumps 4\""*)
		;;
	*)
		printf '%s\n' "unexpected invalid chain jump schedule output"
		printf '%s\n' "$chain_invalid_schedule_output"
		exit 1
		;;
esac

chain_default_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-chain-bench --iterations 16 --packets 1 --jumps 8 --dp-bits 8 --min-ms 0 2>&1)"
chain_default_status=$?
if [ "$chain_default_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-chain-bench default steps returned status %s\n' "$chain_default_status"
	printf '%s\n' "$chain_default_output"
	exit 1
fi

case "$chain_default_output" in
	*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain\""*"\"steps_per_sample\":256"*"\"packet_count\":1"*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-chain-bench default steps output"
		printf '%s\n' "$chain_default_output"
		exit 1
		;;
esac

worker_output="$(RCK_VALIDATION_WORKERS=1 ./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations 16 --steps 256 --jumps 8 --dp-bits 8 --min-ms 0 2>&1)"
worker_status=$?
if [ "$worker_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-bench validation worker override returned status %s\n' "$worker_status"
	printf '%s\n' "$worker_output"
	exit 1
fi

case "$worker_output" in
	*"\"validation_workers\":1"*)
		;;
	*)
		printf '%s\n' "unexpected validation worker override output"
		printf '%s\n' "$worker_output"
		exit 1
		;;
esac

persistent_chain_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench --iterations 64 --steps 256 --packets 2 --rounds 2 --jumps 8 --dp-bits 8 2>&1)"
persistent_chain_status=$?
if [ "$persistent_chain_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench returned status %s\n' "$persistent_chain_status"
	printf '%s\n' "$persistent_chain_output"
	exit 1
fi

case "$persistent_chain_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain\""*"\"state_layout\":\"xyzz\""*"\"setup_mode\":\"reuse_pipeline_buffers\""*"\"state_persistence\":\"round_cumulative_xyzz\""*"\"sample_count\":64"*"\"steps_per_sample\":256"*"\"packet_count\":4"*"\"packets_per_round\":2"*"\"round_count\":2"*"\"jump_schedule\":\"power2\""*"\"distance_tracking\":\"dp_stream_cumulative_uint64\""*"\"stream_indexing\":\"round_packet_sample_u32\""*"\"dp_bits\":8"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain\""*"\"state_layout\":\"xyzz\""*"\"round_count\":2"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench output"
		printf '%s\n' "$persistent_chain_output"
		exit 1
		;;
esac

persistent_chain_runtime_dp_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench --iterations 64 --steps 256 --packets 2 --rounds 2 --jumps 8 --dp-bits 12 2>&1)"
persistent_chain_runtime_dp_status=$?
if [ "$persistent_chain_runtime_dp_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench runtime dp returned status %s\n' "$persistent_chain_runtime_dp_status"
	printf '%s\n' "$persistent_chain_runtime_dp_output"
	exit 1
fi

case "$persistent_chain_runtime_dp_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain\""*"\"state_layout\":\"xyzz\""*"\"sample_count\":64"*"\"steps_per_sample\":256"*"\"packet_count\":4"*"\"packets_per_round\":2"*"\"round_count\":2"*"\"distance_tracking\":\"dp_stream_cumulative_uint64\""*"\"dp_bits\":12"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain\""*"\"state_layout\":\"xyzz\""*"\"round_count\":2"*"\"dp_bits\":12"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected runtime-dp metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench output"
		printf '%s\n' "$persistent_chain_runtime_dp_output"
		exit 1
		;;
esac

persistent_chain_scaled_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench --iterations 64 --steps 256 --packets 2 --rounds 2 --jumps 4 --dp-bits 8 --jump-schedule scaled4-balanced 2>&1)"
persistent_chain_scaled_status=$?
if [ "$persistent_chain_scaled_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench scaled4 returned status %s\n' "$persistent_chain_scaled_status"
	printf '%s\n' "$persistent_chain_scaled_output"
	exit 1
fi

case "$persistent_chain_scaled_output" in
	*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain\""*"\"packet_count\":4"*"\"jump_count\":4"*"\"jump_schedule\":\"scaled4_balanced\""*"\"distance_tracking\":\"dp_stream_cumulative_uint64\""*"\"correctness\":true"*)
		;;
	*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain\""*"\"packet_count\":4"*"\"jump_schedule\":\"scaled4_balanced\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected scaled4 metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench output"
		printf '%s\n' "$persistent_chain_scaled_output"
		exit 1
		;;
esac

persistent_chain_invalid_schedule_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench --iterations 64 --steps 256 --packets 2 --rounds 2 --jumps 4 --dp-bits 8 --jump-schedule unknown 2>&1)"
case "$persistent_chain_invalid_schedule_output" in
	*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain\""*"\"jump_schedule\":\"invalid\""*"\"correctness\":false"*"\"reason\":\"unknown jump schedule\""*)
		;;
	*)
		printf '%s\n' "unexpected invalid persistent-chain jump schedule output"
		printf '%s\n' "$persistent_chain_invalid_schedule_output"
		exit 1
		;;
esac

affine_scan_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-bench --iterations 64 --steps 256 --jumps 8 --dp-bits 8 --min-ms 0 2>&1)"
affine_scan_status=$?
if [ "$affine_scan_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-bench returned status %s\n' "$affine_scan_status"
	printf '%s\n' "$affine_scan_output"
	exit 1
fi

case "$affine_scan_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_affine_scan\""*"\"state_layout\":\"xyzz\""*"\"sample_count\":64"*"\"steps_per_sample\":256"*"\"jump_count\":8"*"\"affine_scan_mode\":\"cpu_batch_prod_zz_zzz\""*"\"distance_tracking\":\"packet_distance_uint64\""*"\"dp_tracking\":\"affine_x_limb0_cpu_batch\""*"\"dp_bits\":8"*"\"affine_scan_seconds\":"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_affine_scan\""*"\"state_layout\":\"xyzz\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-bench output"
		printf '%s\n' "$affine_scan_output"
		exit 1
		;;
esac

affine_lookup_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench --iterations 64 --steps 256 --jumps 8 --dp-bits 4 --target-count 128 --hits 4 --lookup-repeat 3 --min-ms 0 2>&1)"
affine_lookup_status=$?
if [ "$affine_lookup_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench returned status %s\n' "$affine_lookup_status"
	printf '%s\n' "$affine_lookup_output"
	exit 1
fi

case "$affine_lookup_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"output_layout\":\"affine_dp_scan_target_lookup\""*"\"lookup_layout\":\"open_address_tag32_index_exact256\""*"\"target_key\":\"x256_y_parity\""*"\"candidate_verification\":\"tag32_prefilter_then_exact_key_equality\""*"\"sample_count\":64"*"\"steps_per_sample\":256"*"\"jump_count\":8"*"\"dp_bits\":4"*"\"target_count\":128"*"\"requested_hits\":4"*"\"injected_hits\":4"*"\"lookup_repeat\":3"*"\"lookup_query_mode\":\"repeat\""*"\"dp_query_count\":5"*"\"query_count\":15"*"\"hit_count\":12"*"\"miss_count\":3"*"\"target_lookup_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench output"
		printf '%s\n' "$affine_lookup_output"
		exit 1
		;;
esac

affine_lookup_tag16_mix_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench --iterations 64 --steps 256 --jumps 8 --dp-bits 4 --target-count 128 --hits 4 --lookup-repeat 3 --lookup-engine gpu-filter16-hash-repeat --lookup-filter-mode tag16-mix --min-ms 0 2>&1)"
affine_lookup_tag16_mix_status=$?
if [ "$affine_lookup_tag16_mix_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench tag16-mix returned status %s\n' "$affine_lookup_tag16_mix_status"
	printf '%s\n' "$affine_lookup_tag16_mix_output"
	exit 1
fi

case "$affine_lookup_tag16_mix_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"output_layout\":\"affine_dp_scan_target_lookup\""*"\"lookup_layout\":\"open_address_tag16_mix_hash_filter_exact256\""*"\"query_input\":\"hash64_repeat_indexed\""*"\"repeat_positive_index_encoding\":\"packed16_base_repeat\""*"\"target_key\":\"x256_y_parity\""*"\"candidate_verification\":\"tag16_mix_hash_filter_then_cpu_exact_key_equality\""*"\"sample_count\":64"*"\"steps_per_sample\":256"*"\"jump_count\":8"*"\"dp_bits\":4"*"\"target_count\":128"*"\"requested_hits\":4"*"\"injected_hits\":4"*"\"lookup_repeat\":3"*"\"lookup_query_mode\":\"repeat\""*"\"lookup_engine\":\"gpu_filter16_hash_repeat\""*"\"lookup_engine_effective\":\"gpu_filter16_mix_hash_repeat\""*"\"dp_query_count\":5"*"\"query_count\":15"*"\"hit_count\":12"*"\"miss_count\":3"*"\"filter_positive_count\":12"*"\"filter_false_positive_count\":0"*"\"target_lookup_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench tag16-mix output"
		printf '%s\n' "$affine_lookup_tag16_mix_output"
		exit 1
		;;
esac

affine_lookup_rounds_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench --iterations 64 --steps 256 --jumps 4 --dp-bits 4 --target-count 128 --hits 4 --lookup-repeat 3 --rounds 2 --lookup-tg-limit 128 --jump-schedule scaled4-balanced 2>&1)"
affine_lookup_rounds_status=$?
if [ "$affine_lookup_rounds_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench returned status %s\n' "$affine_lookup_rounds_status"
	printf '%s\n' "$affine_lookup_rounds_output"
	exit 1
fi

case "$affine_lookup_rounds_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32_rounds\""*"\"output_layout\":\"affine_dp_scan_target_lookup\""*"\"lookup_layout\":\"open_address_tag16_hash_filter_exact256\""*"\"query_input\":\"hash64_repeat_indexed\""*"\"repeat_positive_index_encoding\":\"packed16_base_repeat\""*"\"iterations\":32768"*"\"sample_count\":64"*"\"round_count\":2"*"\"steps_per_sample\":256"*"\"jump_count\":4"*"\"jump_schedule\":\"scaled4_balanced\""*"\"dp_bits\":4"*"\"target_count\":128"*"\"requested_hits\":4"*"\"injected_hits\":3"*"\"lookup_repeat\":3"*"\"lookup_query_mode\":\"repeat\""*"\"lookup_engine\":\"gpu_filter16_hash_repeat\""*"\"lookup_engine_effective\":\"gpu_filter16_hash_repeat\""*"\"dp_query_count\":3"*"\"query_count\":9"*"\"hit_count\":9"*"\"miss_count\":0"*"\"filter_positive_count\":9"*"\"filter_false_positive_count\":0"*"\"lookup_threadgroup_limit\":128"*"\"target_lookup_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32_rounds\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench output"
		printf '%s\n' "$affine_lookup_rounds_output"
		exit 1
		;;
esac

affine_lookup_rounds_persistent_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench --iterations 64 --steps 256 --jumps 8 --dp-bits 4 --target-count 128 --hits 4 --lookup-repeat 3 --rounds 2 --walk-round-mode persistent 2>&1)"
affine_lookup_rounds_persistent_status=$?
if [ "$affine_lookup_rounds_persistent_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench persistent returned status %s\n' "$affine_lookup_rounds_persistent_status"
	printf '%s\n' "$affine_lookup_rounds_persistent_output"
	exit 1
fi

case "$affine_lookup_rounds_persistent_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32_rounds\""*"\"walk_round_mode\":\"persistent\""*"\"round_count\":2"*"\"steps_per_sample\":256"*"\"jump_count\":8"*"\"distance_tracking\":\"round_cumulative_uint64\""*"\"target_count\":128"*"\"requested_hits\":4"*"\"injected_hits\":8"*"\"lookup_repeat\":3"*"\"lookup_query_mode\":\"repeat\""*"\"hit_count\":24"*"\"filter_false_positive_count\":0"*"\"target_lookup_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32_rounds\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected persistent metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench output"
		printf '%s\n' "$affine_lookup_rounds_persistent_output"
		exit 1
		;;
esac

affine_lookup_rounds_dedup_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench --iterations 64 --steps 256 --jumps 4 --dp-bits 4 --target-count 128 --hits 4 --lookup-repeat 3 --rounds 2 --lookup-tg-limit 128 --jump-schedule scaled4-balanced --lookup-repeat-mode dedup 2>&1)"
affine_lookup_rounds_dedup_status=$?
if [ "$affine_lookup_rounds_dedup_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench dedup repeat returned status %s\n' "$affine_lookup_rounds_dedup_status"
	printf '%s\n' "$affine_lookup_rounds_dedup_output"
	exit 1
fi

case "$affine_lookup_rounds_dedup_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32_rounds\""*"\"output_layout\":\"affine_dp_scan_target_lookup\""*"\"lookup_layout\":\"open_address_tag16_hash_filter_exact256\""*"\"query_input\":\"hash64_dedup_repeat_base\""*"\"repeat_positive_index_encoding\":\"base_query_index\""*"\"iterations\":32768"*"\"sample_count\":64"*"\"round_count\":2"*"\"steps_per_sample\":256"*"\"jump_count\":4"*"\"jump_schedule\":\"scaled4_balanced\""*"\"dp_bits\":4"*"\"target_count\":128"*"\"requested_hits\":4"*"\"injected_hits\":3"*"\"lookup_repeat\":3"*"\"lookup_query_mode\":\"dedup_repeat\""*"\"lookup_engine\":\"gpu_filter16_hash_repeat\""*"\"lookup_engine_effective\":\"gpu_filter16_hash_repeat\""*"\"dp_query_count\":3"*"\"query_count\":9"*"\"physical_query_count\":3"*"\"hit_count\":9"*"\"miss_count\":0"*"\"filter_positive_count\":9"*"\"physical_filter_positive_count\":3"*"\"filter_false_positive_count\":0"*"\"lookup_threadgroup_limit\":128"*"\"target_lookup_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32_rounds\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench dedup repeat output"
		printf '%s\n' "$affine_lookup_rounds_dedup_output"
		exit 1
		;;
esac

affine_lookup_rounds_tag16_mix_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench --iterations 64 --steps 256 --jumps 4 --dp-bits 4 --target-count 128 --hits 4 --lookup-repeat 3 --rounds 2 --lookup-tg-limit 128 --jump-schedule scaled4-balanced --lookup-filter-mode tag16-mix 2>&1)"
affine_lookup_rounds_tag16_mix_status=$?
if [ "$affine_lookup_rounds_tag16_mix_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench tag16-mix filter returned status %s\n' "$affine_lookup_rounds_tag16_mix_status"
	printf '%s\n' "$affine_lookup_rounds_tag16_mix_output"
	exit 1
fi

case "$affine_lookup_rounds_tag16_mix_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32_rounds\""*"\"output_layout\":\"affine_dp_scan_target_lookup\""*"\"lookup_layout\":\"open_address_tag16_mix_hash_filter_exact256\""*"\"query_input\":\"hash64_repeat_indexed\""*"\"repeat_positive_index_encoding\":\"packed16_base_repeat\""*"\"iterations\":32768"*"\"sample_count\":64"*"\"round_count\":2"*"\"steps_per_sample\":256"*"\"jump_count\":4"*"\"jump_schedule\":\"scaled4_balanced\""*"\"dp_bits\":4"*"\"target_count\":128"*"\"requested_hits\":4"*"\"injected_hits\":3"*"\"lookup_repeat\":3"*"\"lookup_query_mode\":\"repeat\""*"\"lookup_engine\":\"gpu_filter16_mix_hash_repeat\""*"\"lookup_engine_effective\":\"gpu_filter16_mix_hash_repeat\""*"\"dp_query_count\":3"*"\"query_count\":9"*"\"hit_count\":9"*"\"miss_count\":0"*"\"filter_positive_count\":9"*"\"filter_false_positive_count\":0"*"\"lookup_threadgroup_limit\":128"*"\"target_lookup_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32_rounds\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench tag16-mix filter output"
		printf '%s\n' "$affine_lookup_rounds_tag16_mix_output"
		exit 1
		;;
esac

affine_lookup_rounds_tag32_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench --iterations 64 --steps 256 --jumps 4 --dp-bits 4 --target-count 128 --hits 4 --lookup-repeat 3 --rounds 2 --lookup-tg-limit 128 --jump-schedule scaled4-balanced --lookup-filter-bits 32 2>&1)"
affine_lookup_rounds_tag32_status=$?
if [ "$affine_lookup_rounds_tag32_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench tag32 filter returned status %s\n' "$affine_lookup_rounds_tag32_status"
	printf '%s\n' "$affine_lookup_rounds_tag32_output"
	exit 1
fi

case "$affine_lookup_rounds_tag32_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32_rounds\""*"\"output_layout\":\"affine_dp_scan_target_lookup\""*"\"lookup_layout\":\"open_address_tag32_hash_filter_exact256\""*"\"query_input\":\"hash64_repeat_indexed\""*"\"repeat_positive_index_encoding\":\"packed16_base_repeat\""*"\"iterations\":32768"*"\"sample_count\":64"*"\"round_count\":2"*"\"steps_per_sample\":256"*"\"jump_count\":4"*"\"jump_schedule\":\"scaled4_balanced\""*"\"dp_bits\":4"*"\"target_count\":128"*"\"requested_hits\":4"*"\"injected_hits\":3"*"\"lookup_repeat\":3"*"\"lookup_query_mode\":\"repeat\""*"\"lookup_engine\":\"gpu_filter32_hash_repeat\""*"\"lookup_engine_effective\":\"gpu_filter32_hash_repeat\""*"\"dp_query_count\":3"*"\"query_count\":9"*"\"hit_count\":9"*"\"miss_count\":0"*"\"filter_positive_count\":9"*"\"filter_false_positive_count\":0"*"\"lookup_threadgroup_limit\":128"*"\"target_lookup_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32_rounds\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench tag32 filter output"
		printf '%s\n' "$affine_lookup_rounds_tag32_output"
		exit 1
		;;
esac

affine_lookup_rounds_invalid_schedule_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-rounds-bench --iterations 64 --steps 256 --jumps 8 --dp-bits 4 --target-count 128 --hits 4 --lookup-repeat 3 --rounds 2 --jump-schedule scaled4-balanced 2>&1)"
case "$affine_lookup_rounds_invalid_schedule_output" in
	*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32_rounds\""*"\"jump_schedule\":\"scaled4_balanced\""*"\"correctness\":false"*"\"reason\":\"scaled4-balanced jump schedule requires --jumps 4\""*)
		;;
	*)
		printf '%s\n' "unexpected invalid rounds jump schedule output"
		printf '%s\n' "$affine_lookup_rounds_invalid_schedule_output"
		exit 1
		;;
esac

affine_lookup_tg_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench --iterations 64 --steps 256 --jumps 8 --dp-bits 4 --target-count 128 --hits 4 --lookup-repeat 3 --lookup-engine gpu --lookup-tg-limit 256 --min-ms 0 2>&1)"
affine_lookup_tg_status=$?
if [ "$affine_lookup_tg_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench lookup tg returned status %s\n' "$affine_lookup_tg_status"
	printf '%s\n' "$affine_lookup_tg_output"
	exit 1
fi

case "$affine_lookup_tg_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"lookup_engine\":\"gpu\""*"\"threadgroup_limit\":128"*"\"lookup_threadgroup_limit\":256"*"\"lookup_threads_per_threadgroup\":256"*"\"target_lookup_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"lookup_engine\":\"gpu\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected lookup-tg metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench output"
		printf '%s\n' "$affine_lookup_tg_output"
		exit 1
		;;
esac

affine_lookup_cpu_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench --iterations 64 --steps 256 --jumps 8 --dp-bits 4 --target-count 128 --hits 4 --lookup-repeat 3 --lookup-engine cpu --min-ms 0 2>&1)"
affine_lookup_cpu_status=$?
if [ "$affine_lookup_cpu_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench cpu returned status %s\n' "$affine_lookup_cpu_status"
	printf '%s\n' "$affine_lookup_cpu_output"
	exit 1
fi

case "$affine_lookup_cpu_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"lookup_repeat\":3"*"\"lookup_query_mode\":\"repeat\""*"\"lookup_engine\":\"cpu\""*"\"dp_query_count\":5"*"\"query_count\":15"*"\"hit_count\":12"*"\"miss_count\":3"*"\"lookup_threadgroup_limit\":0"*"\"lookup_thread_execution_width\":0"*"\"lookup_threads_per_threadgroup\":0"*"\"target_lookup_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"lookup_engine\":\"cpu\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected cpu metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench output"
		printf '%s\n' "$affine_lookup_cpu_output"
		exit 1
		;;
esac

affine_lookup_auto_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench --iterations 64 --steps 256 --jumps 8 --dp-bits 4 --target-count 1048576 --hits 4 --lookup-repeat 3 --lookup-engine auto --min-ms 0 2>&1)"
affine_lookup_auto_status=$?
if [ "$affine_lookup_auto_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench auto returned status %s\n' "$affine_lookup_auto_status"
	printf '%s\n' "$affine_lookup_auto_output"
	exit 1
fi

case "$affine_lookup_auto_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"lookup_repeat\":3"*"\"lookup_query_mode\":\"repeat\""*"\"lookup_engine\":\"auto\""*"\"lookup_engine_effective\":\"cpu\""*"\"dp_query_count\":5"*"\"query_count\":15"*"\"hit_count\":12"*"\"miss_count\":3"*"\"lookup_threadgroup_limit\":0"*"\"lookup_thread_execution_width\":0"*"\"lookup_threads_per_threadgroup\":0"*"\"target_lookup_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"lookup_engine\":\"auto\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected auto metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench output"
		printf '%s\n' "$affine_lookup_auto_output"
		exit 1
		;;
esac

affine_lookup_auto_bulk_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench --iterations 64 --steps 256 --jumps 8 --dp-bits 4 --target-count 1048576 --hits 4 --lookup-repeat 262144 --lookup-engine auto --min-ms 0 2>&1)"
affine_lookup_auto_bulk_status=$?
if [ "$affine_lookup_auto_bulk_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench auto bulk returned status %s\n' "$affine_lookup_auto_bulk_status"
	printf '%s\n' "$affine_lookup_auto_bulk_output"
	exit 1
fi

case "$affine_lookup_auto_bulk_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"lookup_repeat\":262144"*"\"lookup_engine\":\"auto\""*"\"lookup_engine_effective\":\"gpu\""*"\"query_count\":1310720"*"\"hit_count\":1048576"*"\"lookup_threadgroup_limit\":512"*"\"lookup_threads_per_threadgroup\":512"*"\"target_lookup_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"lookup_engine\":\"auto\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected auto bulk metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench output"
		printf '%s\n' "$affine_lookup_auto_bulk_output"
		exit 1
		;;
esac

affine_lookup_distinct_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench --iterations 64 --steps 256 --jumps 8 --dp-bits 4 --target-count 128 --hits 4 --lookup-repeat 3 --lookup-query-mode distinct-misses --min-ms 0 2>&1)"
affine_lookup_distinct_status=$?
if [ "$affine_lookup_distinct_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench distinct returned status %s\n' "$affine_lookup_distinct_status"
	printf '%s\n' "$affine_lookup_distinct_output"
	exit 1
fi

case "$affine_lookup_distinct_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"lookup_repeat\":3"*"\"lookup_query_mode\":\"distinct_misses\""*"\"dp_query_count\":5"*"\"query_count\":15"*"\"hit_count\":4"*"\"miss_count\":11"*"\"target_lookup_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_scan_target_lookup_tag32\""*"\"lookup_query_mode\":\"distinct_misses\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected distinct metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench output"
		printf '%s\n' "$affine_lookup_distinct_output"
		exit 1
		;;
esac

overflow_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations 128 --steps 512 --jumps 32 --dp-bits 8 --min-ms 1 2>&1)"
overflow_status=$?
if [ "$overflow_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-xyzz-bench overflow guard returned status %s\n' "$overflow_status"
	printf '%s\n' "$overflow_output"
	exit 1
fi

case "$overflow_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz\""*"\"state_layout\":\"xyzz\""*"\"steps_per_sample\":512"*"\"jump_count\":32"*"\"correctness\":false"*"\"reason\":\"XYZZ dynamic dp stream packet distance exceeds uint32 accumulator\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-bench overflow guard output"
		printf '%s\n' "$overflow_output"
		exit 1
		;;
esac
