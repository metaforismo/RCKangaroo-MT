#!/bin/sh
set -u

output="$(./macos/rck_macos metal-field-mul-bench --iterations 8 --min-ms 1 --tg-limit 128 2>&1)"
status=$?

if [ "$status" -ne 0 ]; then
	printf 'metal-field-mul-bench --tg-limit returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"field_mul_mod_p\""*"\"sample_count\":8"*"\"threadgroup_limit\":128"*"\"threads_per_threadgroup\":"*"\"correctness\":"*"\"skipped\":"*)
		;;
	*)
		printf '%s\n' "unexpected metal-field-mul-bench --tg-limit output"
		printf '%s\n' "$output"
		exit 1
		;;
esac

output="$(./macos/rck_macos metal-field-square-mul-bench --iterations 8 --min-ms 1 --tg-limit 128 2>&1)"
status=$?

if [ "$status" -ne 0 ]; then
	printf 'metal-field-square-mul-bench --tg-limit returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"field_square_mul_mod_p\""*"\"sample_count\":8"*"\"threadgroup_limit\":128"*"\"threads_per_threadgroup\":"*"\"correctness\":"*"\"skipped\":"*)
		;;
	*)
		printf '%s\n' "unexpected metal-field-square-mul-bench --tg-limit output"
		printf '%s\n' "$output"
		exit 1
		;;
esac
