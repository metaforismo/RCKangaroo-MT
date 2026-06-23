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
