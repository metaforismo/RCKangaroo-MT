#!/bin/sh
set -eu

set +e
output="$(./macos/rck_macos metal-field-mul4-test 2>&1)"
status=$?
set -e

case "$output" in
	*"metal field mul4 ok"*|*"metal field mul4 skipped: no Metal device available"*)
		if [ "$status" -eq 0 ]; then
			exit 0
		fi
		printf '%s\n' "$output"
		printf 'metal-field-mul4-test returned status %s\n' "$status"
		exit 1
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected metal-field-mul4-test output"
		exit 1
		;;
esac
