#!/bin/sh
set -u

test_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-inplace-test 2>&1)"
test_status=$?
if [ "$test_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-inplace-test returned status %s\n' "$test_status"
	printf '%s\n' "$test_output"
	exit 1
fi

case "$test_output" in
	*"metal jacobian dynamic dp stream in-place ok"*|*"metal jacobian dynamic dp stream in-place skipped: no Metal device available"*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-inplace-test output"
		printf '%s\n' "$test_output"
		exit 1
		;;
esac

output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 128 --steps 8 --jumps 8 --dp-bits 8 --min-ms 1 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-inplace-bench returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_inplace\""*"\"sample_count\":128"*"\"steps_per_sample\":8"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"output_layout\":\"dp_stream\""*"\"output_bytes_per_record\":20"*"\"emitted_records\":"*"\"dp_stream_overflow\":false"*"\"distance_tracking\":\"dp_stream_uint64\""*"\"dp_tracking\":\"projective_x_limb0\""*"\"dp_bits\":8"*"\"dp_count\":"*"\"dp_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_inplace\""*"\"sample_count\":128"*"\"steps_per_sample\":8"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"output_layout\":\"dp_stream\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-inplace-bench output"
		printf '%s\n' "$output"
		exit 1
		;;
esac

steps16_output="$(./macos/rck_macos metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 128 --steps 16 --jumps 8 --dp-bits 8 --min-ms 1 2>&1)"
steps16_status=$?
if [ "$steps16_status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-stream-inplace-bench steps16 returned status %s\n' "$steps16_status"
	printf '%s\n' "$steps16_output"
	exit 1
fi

case "$steps16_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_inplace\""*"\"sample_count\":128"*"\"steps_per_sample\":16"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"output_layout\":\"dp_stream\""*"\"output_bytes_per_record\":20"*"\"emitted_records\":"*"\"dp_stream_overflow\":false"*"\"distance_tracking\":\"dp_stream_uint64\""*"\"dp_tracking\":\"projective_x_limb0\""*"\"dp_bits\":8"*"\"dp_count\":"*"\"dp_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_stream_inplace\""*"\"sample_count\":128"*"\"steps_per_sample\":16"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"output_layout\":\"dp_stream\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-stream-inplace-bench steps16 output"
		printf '%s\n' "$steps16_output"
		exit 1
		;;
esac
