#!/bin/sh
set -eu

set +e
output="$(./macos/rck_macos metal-field-sub-test 2>&1)"
status=$?
set -e

case "$output" in
	*"metal field sub ok"*|*"metal field sub skipped: no Metal device available"*)
		if [ "$status" -eq 0 ]; then
			exit 0
		fi
		printf '%s\n' "$output"
		printf 'metal-field-sub-test returned status %s\n' "$status"
		exit 1
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected metal-field-sub-test output"
		exit 1
		;;
esac
