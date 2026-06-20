#!/bin/sh
set -eu

set +e
output="$(./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 4 --iterations 1 --min-ms 1 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
	printf '%s\n' "$output"
	printf 'jacobian-kangaroo-multi-small-bench returned status %s\n' "$status"
	exit 1
fi

case "$output" in
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"jacobian_kangaroo_multi_small\""*"\"architecture\":\"shared_tame\""*"\"dp_lookup\":\"hash\""*"\"affine_conversion\":\"batch\""*"\"jump_table\":\"precomputed\""*"\"scratch\":\"reused\""*"\"range_context\":\"precomputed\""*"\"target_count\":4"*"\"tame_states\":1"*"\"wild_states\":4"*"\"single_target_ops_per_sec\":"*"\"speedup_vs_single\":"*"\"target_throughput_vs_single\":"*"\"found_target_index\":3"*"\"found_private_key\":\"0x7\""*"\"correctness\":true"*)
		exit 0
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected jacobian-kangaroo-multi-small-bench output"
		exit 1
		;;
esac
