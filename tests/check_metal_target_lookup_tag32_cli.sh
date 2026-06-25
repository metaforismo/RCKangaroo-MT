#!/bin/sh
set -eu

set +e
output="$(./macos/rck_macos metal-target-lookup-tag32-bench --target-count 64 --query-count 256 --hits 32 --min-ms 0 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
	printf 'metal-target-lookup-tag32-bench returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag32_exact256\""*"\"lookup_layout\":\"open_address_tag32_index_exact256\""*"\"target_key\":\"x256_y_parity\""*"\"candidate_verification\":\"tag32_prefilter_then_exact_key_equality\""*"\"target_count\":64"*"\"query_count\":256"*"\"expected_hits\":32"*"\"hit_count\":32"*"\"miss_count\":224"*"\"target_key_bytes\":2560"*"\"target_bucket_bytes\":1024"*"\"bytes_per_target\":56.000000"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag32_exact256\""*"\"target_count\":64"*"\"query_count\":256"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected metal-target-lookup-tag32-bench output"
		exit 1
		;;
esac

set +e
persistent_output="$(./macos/rck_macos metal-target-lookup-tag32-persistent-bench --target-count 64 --query-count 256 --hits 32 --min-ms 0 2>&1)"
persistent_status=$?
set -e

if [ "$persistent_status" -ne 0 ]; then
	printf 'metal-target-lookup-tag32-persistent-bench returned status %s\n' "$persistent_status"
	printf '%s\n' "$persistent_output"
	exit 1
fi

case "$persistent_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag32_persistent_exact256\""*"\"lookup_layout\":\"open_address_tag32_index_exact256\""*"\"buffer_lifetime\":\"persistent\""*"\"target_key\":\"x256_y_parity\""*"\"candidate_verification\":\"tag32_prefilter_then_exact_key_equality\""*"\"target_count\":64"*"\"query_count\":256"*"\"expected_hits\":32"*"\"hit_count\":32"*"\"miss_count\":224"*"\"metal_setup_seconds\":"*"\"dispatch_seconds\":"*"\"dispatch_lookups_per_sec\":"*"\"target_key_bytes\":2560"*"\"target_bucket_bytes\":1024"*"\"bytes_per_target\":56.000000"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag32_persistent_exact256\""*"\"target_count\":64"*"\"query_count\":256"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "$persistent_output"
		printf '%s\n' "unexpected metal-target-lookup-tag32-persistent-bench output"
		exit 1
		;;
esac

set +e
cpu_output="$(./macos/rck_macos target-lookup-tag32-cpu-bench --target-count 64 --query-count 256 --hits 32 --min-ms 0 2>&1)"
cpu_status=$?
set -e

if [ "$cpu_status" -ne 0 ]; then
	printf 'target-lookup-tag32-cpu-bench returned status %s\n' "$cpu_status"
	printf '%s\n' "$cpu_output"
	exit 1
fi

case "$cpu_output" in
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"target_lookup_tag32_cpu_exact256\""*"\"lookup_layout\":\"open_address_tag32_index_exact256\""*"\"lookup_engine\":\"cpu\""*"\"target_key\":\"x256_y_parity\""*"\"candidate_verification\":\"tag32_prefilter_then_exact_key_equality\""*"\"target_count\":64"*"\"query_count\":256"*"\"expected_hits\":32"*"\"hit_count\":32"*"\"miss_count\":224"*"\"target_key_bytes\":2560"*"\"target_bucket_bytes\":1024"*"\"bytes_per_target\":56.000000"*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$cpu_output"
		printf '%s\n' "unexpected target-lookup-tag32-cpu-bench output"
		exit 1
		;;
esac
