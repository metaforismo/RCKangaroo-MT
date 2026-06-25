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
		:
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag32_exact256\""*"\"target_count\":64"*"\"query_count\":256"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		exit 0
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected metal-target-lookup-tag32-bench output"
		exit 1
		;;
esac

set +e
output="$(./macos/rck_macos metal-target-lookup-tag32-bench --target-count 96 --query-count 256 --hits 32 --min-ms 0 2>&1)"
status=$?
set -e

if [ "$status" -ne 0 ]; then
	printf 'metal-target-lookup-tag32-bench returned status %s\n' "$status"
	printf '%s\n' "$output"
	exit 1
fi

case "$output" in
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag32_exact256\""*"\"target_count\":96"*"\"query_count\":256"*"\"expected_hits\":32"*"\"hit_count\":32"*"\"miss_count\":224"*"\"target_table_buckets\":256"*"\"target_key_bytes\":3840"*"\"target_bucket_bytes\":2048"*"\"bytes_per_target\":61.333333"*"\"correctness\":true"*)
		exit 0
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag32_exact256\""*"\"target_count\":96"*"\"query_count\":256"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		exit 0
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected non-power-of-two metal-target-lookup-tag32-bench output"
		exit 1
		;;
esac
