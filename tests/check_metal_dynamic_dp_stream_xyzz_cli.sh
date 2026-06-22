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
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz\""*"\"state_layout\":\"xyzz\""*"\"sample_count\":128"*"\"steps_per_sample\":256"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"output_layout\":\"dp_stream\""*"\"output_bytes_per_record\":20"*"\"emitted_records\":"*"\"dp_stream_overflow\":false"*"\"distance_tracking\":\"dp_stream_uint64\""*"\"dp_tracking\":\"projective_x_limb0\""*"\"dp_bits\":8"*"\"dp_count\":"*"\"dp_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz\""*"\"state_layout\":\"xyzz\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-bench output"
		printf '%s\n' "$output"
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
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain\""*"\"state_layout\":\"xyzz\""*"\"sample_count\":128"*"\"steps_per_sample\":256"*"\"packet_count\":2"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"output_layout\":\"dp_stream\""*"\"emitted_records\":"*"\"dp_stream_overflow\":false"*"\"distance_tracking\":\"dp_stream_cumulative_uint64\""*"\"dp_bits\":8"*"\"dp_count\":"*"\"dp_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_xyzz_chain\""*"\"state_layout\":\"xyzz\""*"\"packet_count\":2"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-xyzz-chain-bench output"
		printf '%s\n' "$chain_output"
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
