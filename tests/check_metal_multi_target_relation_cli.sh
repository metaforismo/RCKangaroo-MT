#!/bin/sh
set -eu

output="$(./macos/rck_macos metal-multi-target-relation-test 2>&1)"
case "$output" in
	*"metal multi-target signed relation ok"*)
		exit 0
		;;
	*"metal multi-target signed relation skipped: no Metal device available"*)
		exit 0
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected Metal multi-target relation output"
		exit 1
		;;
esac
