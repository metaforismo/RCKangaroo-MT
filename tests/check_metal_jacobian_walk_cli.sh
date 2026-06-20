#!/bin/sh
set -u

output="$(./macos/rck_macos metal-jacobian-walk-test 2>&1)"
status=$?
case "$output" in
	*"metal jacobian walk ok"*|*"metal jacobian walk skipped: no Metal device available"*)
		;;
	*)
		printf 'metal-jacobian-walk-test returned status %s\n' "$status"
		printf '%s\n' "$output"
		exit 1
		;;
esac

output="$(./macos/rck_macos metal-jacobian-walk-bench --iterations 8 --steps 4 --min-ms 1 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
	printf 'metal-jacobian-walk-bench returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_affine_walk_fixed\""*"\"iterations\":"*"\"sample_count\":8"*"\"steps_per_sample\":4"*"\"min_ms\":1"*"\"threadgroup_limit\":256"*"\"thread_execution_width\":"*"\"max_threads_per_threadgroup\":"*"\"threads_per_threadgroup\":"*"\"correctness\":"*"\"skipped\":"*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-walk-bench output"
		printf '%s\n' "$output"
		exit 1
		;;
esac
