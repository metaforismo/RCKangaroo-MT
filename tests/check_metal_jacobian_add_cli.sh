#!/bin/sh
set -u

output="$(./macos/rck_macos metal-jacobian-add-test 2>&1)"
status=$?
case "$output" in
	*"metal jacobian add ok"*|*"metal jacobian add skipped: no Metal device available"*)
		;;
	*)
		printf 'metal-jacobian-add-test returned status %s\n' "$status"
		printf '%s\n' "$output"
		exit 1
		;;
esac

output="$(./macos/rck_macos metal-jacobian-add-bench --iterations 8 --min-ms 1 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
	printf 'metal-jacobian-add-bench returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"jacobian_add_affine\""*"\"iterations\":"*"\"sample_count\":8"*"\"min_ms\":1"*"\"threadgroup_limit\":256"*"\"thread_execution_width\":"*"\"max_threads_per_threadgroup\":"*"\"threads_per_threadgroup\":"*"\"correctness\":"*"\"skipped\":"*)
		;;
	*)
		printf '%s\n' "unexpected metal-jacobian-add-bench output"
		printf '%s\n' "$output"
		exit 1
		;;
esac
