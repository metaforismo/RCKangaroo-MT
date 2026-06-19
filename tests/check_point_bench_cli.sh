#!/bin/sh
set -eu

set +e
output="$(./macos/rck_macos point-bench --iterations 4 --min-ms 1 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
	printf '%s\n' "$output"
	printf 'point-bench returned status %s\n' "$status"
	exit 1
fi

case "$output" in
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"point_add_g\""*"\"sample_count\":4"*"\"min_ms\":1"*"\"correctness\":true"*)
		exit 0
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected point-bench output"
		exit 1
		;;
esac
