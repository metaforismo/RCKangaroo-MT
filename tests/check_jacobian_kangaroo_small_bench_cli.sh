#!/bin/sh
set -eu

set +e
output="$(./macos/rck_macos jacobian-kangaroo-small-bench --iterations 1 --min-ms 1 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
	printf '%s\n' "$output"
	printf 'jacobian-kangaroo-small-bench returned status %s\n' "$status"
	exit 1
fi

case "$output" in
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"jacobian_kangaroo_small\""*"\"dp_lookup\":\"hash\""*"\"dp_hash\":\"partial_limb_mix\""*"\"dp_bucket_storage\":\"inline_first\""*"\"point_passing\":\"const_ref\""*"\"affine_conversion\":\"batch\""*"\"jump_index\":\"power2_mask\""*"\"jump_table\":\"precomputed\""*"\"scratch\":\"reused\""*"\"range_context\":\"precomputed\""*"\"target_count\":1"*"\"tame_states\":1"*"\"wild_states\":1"*"\"found_target_index\":0"*"\"found_private_key\":\"0x7\""*"\"correctness\":true"*)
		exit 0
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected jacobian-kangaroo-small-bench output"
		exit 1
		;;
esac
