#!/bin/sh
set -u

output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-test 2>&1)"
status=$?
case "$output" in
	*"metal jacobian dynamic dp stream ok"*|*"metal jacobian dynamic dp stream skipped: no Metal device available"*)
		;;
	*)
		printf 'metal-jacobian-dynamic-dp-stream-test returned status %s\n' "$status"
		printf '%s\n' "$output"
		exit 1
		;;
esac

output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-bench --iterations 8 --steps 8 --jumps 8 --dp-bits 4 --min-ms 1 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-bench returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream\""*"\"sample_count\":8"*"\"steps_per_sample\":8"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"output_layout\":\"dp_stream\""*"\"output_bytes_per_record\":20"*"\"emitted_records\":"*"\"dp_stream_overflow\":false"*"\"distance_tracking\":\"dp_stream_uint64\""*"\"dp_tracking\":\"projective_x_limb0\""*"\"dp_bits\":4"*"\"dp_count\":"*"\"dp_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream\""*"\"sample_count\":8"*"\"steps_per_sample\":8"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"output_layout\":\"dp_stream\""*"\"output_bytes_per_record\":20"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-bench output"
		printf '%s\n' "$output"
		exit 1
		;;
esac
