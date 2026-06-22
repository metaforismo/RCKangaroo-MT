#!/bin/sh
set -u

output="$(./macos/rck_macos metal-jacobian-dynamic-dp-count-bench --iterations 128 --steps 8 --jumps 8 --dp-bits 8 --min-ms 1 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-dp-count-bench returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_count\""*"\"sample_count\":128"*"\"steps_per_sample\":8"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"output_layout\":\"dp_count\""*"\"output_bytes_total\":4"*"\"distance_tracking\":\"none\""*"\"dp_tracking\":\"projective_x_limb0\""*"\"dp_bits\":8"*"\"dp_count\":"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_dp_count\""*"\"sample_count\":128"*"\"steps_per_sample\":8"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"output_layout\":\"dp_count\""*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-dp-count-bench output"
		printf '%s\n' "$output"
		exit 1
		;;
esac
