#!/bin/sh
set -eu

set +e
output="$(./macos/rck_macos cpu-field-bench --iterations 8 --min-ms 1 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
	printf '%s\n' "$output"
	printf 'cpu-field-bench returned status %s\n' "$status"
	exit 1
fi

case "$output" in
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"field_mul_mod_p\""*"\"carry_impl\":\"clang_builtin\""*"\"ecint_mul_final_sub\":\"single_conditional\""*"\"sample_count\":8"*"\"min_ms\":1"*"\"correctness\":true"*)
		exit 0
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected cpu-field-bench output"
		exit 1
		;;
esac
