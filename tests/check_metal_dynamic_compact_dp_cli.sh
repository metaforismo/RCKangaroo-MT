#!/bin/sh
set -u

output="$(./macos/rck_macos metal-jacobian-dynamic-compact-dp-test 2>&1)"
status=$?
case "$output" in
	*"metal jacobian dynamic compact dp ok"*|*"metal jacobian dynamic compact dp skipped: no Metal device available"*)
		;;
	*)
		printf 'metal-jacobian-dynamic-compact-dp-test returned status %s\n' "$status"
		printf '%s\n' "$output"
		exit 1
		;;
esac

output="$(./macos/rck_macos metal-jacobian-dynamic-compact-dp-bench --iterations 8 --steps 8 --jumps 8 --dp-bits 4 --min-ms 1 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-compact-dp-bench returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_compact\""*"\"sample_count\":8"*"\"steps_per_sample\":8"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"output_layout\":\"dp_compact\""*"\"output_bytes_per_sample\":17"*"\"distance_tracking\":\"uint64\""*"\"dp_tracking\":\"projective_x_limb0\""*"\"dp_bits\":4"*"\"dp_count\":"*"\"dp_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_compact\""*"\"sample_count\":8"*"\"steps_per_sample\":8"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"output_layout\":\"dp_compact\""*"\"output_bytes_per_sample\":17"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-compact-dp-bench output"
		printf '%s\n' "$output"
		exit 1
		;;
esac
