#!/bin/sh
set -u

output="$(./macos/rck_macos metal-jacobian-dynamic-walk-test 2>&1)"
status=$?
case "$output" in
	*"metal jacobian dynamic walk ok"*|*"metal jacobian dynamic walk skipped: no Metal device available"*)
		;;
	*)
		printf 'metal-jacobian-dynamic-walk-test returned status %s\n' "$status"
		printf '%s\n' "$output"
		exit 1
		;;
esac

output="$(./macos/rck_macos metal-jacobian-dynamic-walk-bench --iterations 8 --steps 4 --jumps 8 --dp-bits 4 --min-ms 1 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-walk-bench returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_jump_table\""*"\"sample_count\":8"*"\"steps_per_sample\":4"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"jump_histogram_max_deviation_ppm\":"*"\"distance_tracking\":\"uint64\""*"\"dp_tracking\":\"projective_x_limb0\""*"\"dp_bits\":4"*"\"dp_count\":"*"\"dp_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_jump_table\""*"\"sample_count\":8"*"\"steps_per_sample\":4"*"\"jump_count\":8"*"\"jump_index\":\"power2_mask\""*"\"jump_mixer\":\"avalanche64\""*"\"jump_histogram_max_deviation_ppm\":"*"\"distance_tracking\":\"uint64\""*"\"dp_tracking\":\"projective_x_limb0\""*"\"dp_bits\":4"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-walk-bench power2 output"
		printf '%s\n' "$output"
		exit 1
		;;
esac

output="$(./macos/rck_macos metal-jacobian-dynamic-walk-bench --iterations 8 --steps 4 --jumps 5 --min-ms 1 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
	printf 'metal-jacobian-dynamic-walk-bench modulo returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_dynamic_jump_table\""*"\"sample_count\":8"*"\"steps_per_sample\":4"*"\"jump_count\":5"*"\"jump_index\":\"modulo\""*"\"jump_mixer\":\"avalanche64\""*"\"jump_histogram_max_deviation_ppm\":"*"\"distance_tracking\":\"uint64\""*"\"correctness\":"*"\"skipped\":"*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-dynamic-walk-bench modulo output"
		printf '%s\n' "$output"
		exit 1
		;;
esac
