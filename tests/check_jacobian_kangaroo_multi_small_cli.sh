#!/bin/sh
set -eu

targets="tests/jacobian_kangaroo_multi_targets.txt"

set +e
output="$(./macos/rck_macos jacobian-kangaroo-multi-small --range 8 --start 2 --targets "$targets" --jumps 8 --dp-bits 0 --max-steps 4096 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
	printf '%s\n' "$output"
	printf 'jacobian-kangaroo-multi-small returned status %s\n' "$status"
	exit 1
fi

case "$output" in
	*"FOUND private_key=7 private_key_hex=7"*"target_index=1"*"method=jacobian_kangaroo_multi_small"*)
		exit 0
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected jacobian-kangaroo-multi-small output"
		exit 1
		;;
esac
