#!/bin/sh
set -eu

set +e
output="$(./macos/rck_macos metal-field-mul-bench --iterations 8 --min-ms 1 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
	printf '%s\n' "$output"
	printf 'metal-field-mul-bench returned status %s\n' "$status"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"field_mul_mod_p\""*"\"iterations\":"*"\"sample_count\":8"*"\"min_ms\":1"*"\"thread_execution_width\":"*"\"max_threads_per_threadgroup\":"*"\"threads_per_threadgroup\":"*"\"correctness\":"*"\"skipped\":"*)
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected metal-field-mul-bench output"
		exit 1
		;;
esac

set +e
output="$(./macos/rck_macos metal-field-square-bench --iterations 8 --min-ms 1 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
	printf '%s\n' "$output"
	printf 'metal-field-square-bench returned status %s\n' "$status"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"field_square_mod_p\""*"\"iterations\":"*"\"sample_count\":8"*"\"min_ms\":1"*"\"thread_execution_width\":"*"\"max_threads_per_threadgroup\":"*"\"threads_per_threadgroup\":"*"\"correctness\":"*"\"skipped\":"*)
		exit 0
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected metal-field-square-bench output"
		exit 1
		;;
esac
