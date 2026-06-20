#!/bin/sh
set -u

output="$(./macos/rck_macos metal-field-square-mul-test 2>&1)"
status=$?

case "$output" in
	*"metal field square-mul ok"*|*"metal field square-mul skipped: no Metal device available"*)
		;;
	*)
		if [ "$status" -ne 0 ]; then
			printf 'metal-field-square-mul-test returned status %s\n' "$status"
		fi
		printf '%s\n' "unexpected metal-field-square-mul-test output"
		printf '%s\n' "$output"
		exit 1
		;;
esac
