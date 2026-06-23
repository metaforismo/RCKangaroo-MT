#!/bin/sh
set -eu

target="025CBDF0646E5DB4EAA398F365F2EA7A0E3D419B7E0330E39CE92BDDEDCAC4F9BC"

set +e
output="$(./macos/rck_macos jacobian-kangaroo-small --range 8 --start 0 --pubkey "$target" --jumps 8 --dp-bits 0 --max-steps 4096 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
	printf '%s\n' "$output"
	printf 'jacobian-kangaroo-small returned status %s\n' "$status"
	exit 1
fi

case "$output" in
	*"FOUND private_key=7 private_key_hex=7"*"target_index=0"*"method=jacobian_kangaroo_small"*"dp_lookup=open_address_linear"*"affine_conversion=batch"*"affine_initial_conversion=unit_z_copy"*)
		exit 0
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected jacobian-kangaroo-small output"
		exit 1
		;;
esac
