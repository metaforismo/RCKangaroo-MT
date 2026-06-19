#!/bin/sh
set -eu

set +e
output="$(./macos/rck_macos cpu-field-test 2>&1)"
status=$?
set -e

case "$output" in
	*"cpu field ok"*)
		if [ "$status" -eq 0 ]; then
			exit 0
		fi
		printf '%s\n' "$output"
		printf 'cpu-field-test returned status %s\n' "$status"
		exit 1
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected cpu-field-test output"
		exit 1
		;;
esac
