#!/bin/sh
set -eu

set +e
output="$(./macos/rck_macos jacobian-walk-bench --iterations 8 --min-ms 1 --jumps 8 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
	printf '%s\n' "$output"
	printf 'jacobian-walk-bench returned status %s\n' "$status"
	exit 1
fi

case "$output" in
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"jacobian_jump_walk\""*"\"jump_index\":\"power2_mask\""*"\"sample_count\":8"*"\"min_ms\":1"*"\"jump_count\":8"*"\"scalar_distance\":\"0x"*"\"correctness\":true"*)
		exit 0
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected jacobian-walk-bench output"
		exit 1
		;;
esac
