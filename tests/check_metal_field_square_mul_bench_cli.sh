#!/bin/sh
set -u

output="$(./macos/rck_macos metal-field-square-mul-bench --iterations 8 --min-ms 1 2>&1)"
status=$?

if [ "$status" -ne 0 ]; then
	printf 'metal-field-square-mul-bench returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"field_square_mul_mod_p\""*"\"iterations\":"*"\"sample_count\":8"*"\"min_ms\":1"*"\"thread_execution_width\":"*"\"max_threads_per_threadgroup\":"*"\"threads_per_threadgroup\":"*"\"correctness\":"*"\"skipped\":"*)
		;;
	*)
		printf '%s\n' "unexpected metal-field-square-mul-bench output"
		printf '%s\n' "$output"
		exit 1
		;;
esac
