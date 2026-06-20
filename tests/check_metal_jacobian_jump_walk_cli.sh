#!/bin/sh
set -u

output="$(./macos/rck_macos metal-jacobian-jump-walk-test 2>&1)"
status=$?
case "$output" in
	*"metal jacobian jump walk ok"*|*"metal jacobian jump walk skipped: no Metal device available"*)
		;;
	*)
		printf 'metal-jacobian-jump-walk-test returned status %s\n' "$status"
		printf '%s\n' "$output"
		exit 1
		;;
esac

output="$(./macos/rck_macos metal-jacobian-jump-walk-bench --iterations 8 --steps 4 --jumps 5 --min-ms 1 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
	printf 'metal-jacobian-jump-walk-bench returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_jump_table\""*"\"iterations\":"*"\"sample_count\":8"*"\"steps_per_sample\":4"*"\"jump_count\":5"*"\"distance_tracking\":\"uint64\""*"\"distance_checksum\":\"0x"*"\"min_ms\":1"*"\"threadgroup_limit\":256"*"\"thread_execution_width\":"*"\"max_threads_per_threadgroup\":"*"\"threads_per_threadgroup\":"*"\"correctness\":"*"\"skipped\":"*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-jump-walk-bench output"
		printf '%s\n' "$output"
		exit 1
		;;
esac

output="$(./macos/rck_macos metal-jacobian-jump-walk-bench --iterations 8 --steps 4 --jumps 5 --dp-bits 4 --min-ms 1 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
	printf 'metal-jacobian-jump-walk-bench --dp-bits returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_jump_table\""*"\"sample_count\":8"*"\"steps_per_sample\":4"*"\"jump_count\":5"*"\"distance_tracking\":\"uint64\""*"\"dp_tracking\":\"projective_x_limb0\""*"\"dp_bits\":4"*"\"dp_count\":"*"\"dp_checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-jump-walk-bench --dp-bits output"
		printf '%s\n' "$output"
		exit 1
		;;
esac
