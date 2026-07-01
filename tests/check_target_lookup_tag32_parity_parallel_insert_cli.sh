#!/bin/sh
set -eu

set +e
output="$(./macos/rck_macos target-lookup-tag32-parity-parallel-insert-bench --target-count 256 --injected-count 16 --iterations 1 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
	printf 'target-lookup-tag32-parity-parallel-insert-bench returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"target_lookup_tag32_parity_parallel_insert_probe\""*"\"setup_phase\":\"host_tag32_parity_parallel_insert_probe\""*"\"lookup_layout\":\"open_address_tag32_parity_xonly_tag16_filter_exact256\""*"\"target_key\":\"x256_y_parity\""*"\"candidate_verification\":\"xonly_parity_tag32_prefilter_semantic_find_all_keys\""*"\"target_count\":256"*"\"injected_count\":16"*"\"target_x_key_bytes\":8192"*"\"target_bucket_bytes\":4096"*"\"target_filter_bucket_bytes\":1024"*"\"build_seconds\":"*"\"parallel_targets_per_sec\":"*"\"semantic_checksum\":\"0x"*"\"all_keys_found\":true"*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected target-lookup-tag32-parity-parallel-insert-bench output"
		exit 1
		;;
esac
