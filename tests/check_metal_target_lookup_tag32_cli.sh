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
tag16_filter_persistent_output="$(./macos/rck_macos metal-target-lookup-tag16-filter-persistent-bench --target-count 64 --query-count 256 --hits 32 --min-ms 0 2>&1)"
tag16_filter_persistent_status=$?
set -e

if [ "$tag16_filter_persistent_status" -ne 0 ]; then
	printf 'metal-target-lookup-tag16-filter-persistent-bench returned status %s\n' "$tag16_filter_persistent_status"
	printf '%s\n' "$tag16_filter_persistent_output"
	exit 1
fi

case "$tag16_filter_persistent_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag16_filter_persistent_exact256\""*"\"lookup_layout\":\"open_address_tag16_filter_exact256\""*"\"buffer_lifetime\":\"persistent\""*"\"target_key\":\"x256_y_parity\""*"\"candidate_verification\":\"tag16_filter_then_cpu_exact_key_equality\""*"\"target_count\":64"*"\"query_count\":256"*"\"expected_hits\":32"*"\"hit_count\":32"*"\"miss_count\":224"*"\"filter_positive_count\":"*"\"filter_false_positive_count\":"*"\"target_key_bytes\":2560"*"\"target_bucket_bytes\":1024"*"\"target_filter_bucket_bytes\":256"*"\"bytes_per_target\":4.000000"*"\"metal_setup_seconds\":"*"\"dispatch_seconds\":"*"\"exact_verify_seconds\":"*"\"gpu_dispatch_lookups_per_sec\":"*"\"dispatch_lookups_per_sec\":"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag16_filter_persistent_exact256\""*"\"target_count\":64"*"\"query_count\":256"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "$tag16_filter_persistent_output"
		printf '%s\n' "unexpected metal-target-lookup-tag16-filter-persistent-bench output"
		exit 1
		;;
esac

set +e
tag16_hash_filter_persistent_output="$(./macos/rck_macos metal-target-lookup-tag16-hash-filter-persistent-bench --target-count 64 --query-count 256 --hits 32 --min-ms 0 2>&1)"
tag16_hash_filter_persistent_status=$?
set -e

if [ "$tag16_hash_filter_persistent_status" -ne 0 ]; then
	printf 'metal-target-lookup-tag16-hash-filter-persistent-bench returned status %s\n' "$tag16_hash_filter_persistent_status"
	printf '%s\n' "$tag16_hash_filter_persistent_output"
	exit 1
fi

case "$tag16_hash_filter_persistent_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag16_hash_filter_persistent_exact256\""*"\"lookup_layout\":\"open_address_tag16_hash_filter_exact256\""*"\"buffer_lifetime\":\"persistent\""*"\"query_input\":\"hash64\""*"\"target_key\":\"x256_y_parity\""*"\"candidate_verification\":\"tag16_hash_filter_then_cpu_exact_key_equality\""*"\"target_count\":64"*"\"query_count\":256"*"\"expected_hits\":32"*"\"hit_count\":32"*"\"miss_count\":224"*"\"filter_positive_count\":"*"\"filter_false_positive_count\":"*"\"target_key_bytes\":2560"*"\"target_bucket_bytes\":1024"*"\"target_filter_bucket_bytes\":256"*"\"target_query_hash_bytes\":2048"*"\"bytes_per_target\":4.000000"*"\"metal_setup_seconds\":"*"\"dispatch_seconds\":"*"\"exact_verify_seconds\":"*"\"gpu_dispatch_lookups_per_sec\":"*"\"dispatch_lookups_per_sec\":"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag16_hash_filter_persistent_exact256\""*"\"target_count\":64"*"\"query_count\":256"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "$tag16_hash_filter_persistent_output"
		printf '%s\n' "unexpected metal-target-lookup-tag16-hash-filter-persistent-bench output"
		exit 1
		;;
esac

set +e
filter_persistent_output="$(./macos/rck_macos metal-target-lookup-tag32-filter-persistent-bench --target-count 64 --query-count 256 --hits 32 --min-ms 0 2>&1)"
filter_persistent_status=$?
set -e

if [ "$filter_persistent_status" -ne 0 ]; then
	printf 'metal-target-lookup-tag32-filter-persistent-bench returned status %s\n' "$filter_persistent_status"
	printf '%s\n' "$filter_persistent_output"
	exit 1
fi

case "$filter_persistent_output" in
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag32_filter_persistent_exact256\""*"\"lookup_layout\":\"open_address_tag32_filter_exact256\""*"\"buffer_lifetime\":\"persistent\""*"\"target_key\":\"x256_y_parity\""*"\"candidate_verification\":\"tag32_filter_then_cpu_exact_key_equality\""*"\"target_count\":64"*"\"query_count\":256"*"\"expected_hits\":32"*"\"hit_count\":32"*"\"miss_count\":224"*"\"filter_positive_count\":32"*"\"filter_false_positive_count\":0"*"\"target_key_bytes\":2560"*"\"target_bucket_bytes\":1024"*"\"target_filter_bucket_bytes\":512"*"\"bytes_per_target\":8.000000"*"\"metal_setup_seconds\":"*"\"dispatch_seconds\":"*"\"exact_verify_seconds\":"*"\"gpu_dispatch_lookups_per_sec\":"*"\"dispatch_lookups_per_sec\":"*"\"correctness\":true"*)
		;;
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag32_filter_persistent_exact256\""*"\"target_count\":64"*"\"query_count\":256"*"\"skipped\":true"*"\"reason\":\"no Metal device available\""*)
		;;
	*)
		printf '%s\n' "$filter_persistent_output"
		printf '%s\n' "unexpected metal-target-lookup-tag32-filter-persistent-bench output"
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
	*"\"backend\":\"metal\""*"\"operation\":\"target_lookup_tag32_persistent_exact256\""*"\"lookup_layout\":\"open_address_tag32_index_exact256\""*"\"buffer_lifetime\":\"persistent\""*"\"target_key\":\"x256_y_parity\""*"\"candidate_verification\":\"tag32_prefilter_then_exact_key_equality\""*"\"target_count\":64"*"\"query_count\":256"*"\"expected_hits\":32"*"\"hit_count\":32"*"\"miss_count\":224"*"\"target_key_bytes\":2560"*"\"target_bucket_bytes\":1024"*"\"bytes_per_target\":56.000000"*"\"metal_setup_seconds\":"*"\"dispatch_seconds\":"*"\"dispatch_lookups_per_sec\":"*"\"correctness\":true"*)
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

set +e
filter_build_output="$(./macos/rck_macos target-lookup-filter-build-bench --target-count 64 --iterations 1 2>&1)"
filter_build_status=$?
set -e

if [ "$filter_build_status" -ne 0 ]; then
	printf 'target-lookup-filter-build-bench returned status %s\n' "$filter_build_status"
	printf '%s\n' "$filter_build_output"
	exit 1
fi

case "$filter_build_output" in
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"target_lookup_filter_build_from_tag32_buckets\""*"\"setup_phase\":\"host_filter_build\""*"\"lookup_layout\":\"open_address_tag32_tag16_filter_exact256\""*"\"candidate_verification\":\"legacy_rehash_filter_byte_equality\""*"\"iterations\":1"*"\"target_count\":64"*"\"target_table_buckets\":128"*"\"target_key_bytes\":2560"*"\"target_bucket_bytes\":1024"*"\"target_filter32_bucket_bytes\":512"*"\"target_filter16_bucket_bytes\":256"*"\"tag32_legacy_seconds\":"*"\"tag32_derived_seconds\":"*"\"tag32_speedup\":"*"\"tag16_legacy_seconds\":"*"\"tag16_derived_seconds\":"*"\"tag16_speedup\":"*"\"speedup\":"*"\"ops_per_sec\":"*"\"tag32_filter_checksum\":\"0x"*"\"tag16_filter_checksum\":\"0x"*"\"tag32_byte_equal\":true"*"\"tag16_byte_equal\":true"*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$filter_build_output"
		printf '%s\n' "unexpected target-lookup-filter-build-bench output"
		exit 1
		;;
esac

set +e
build_from_keys_output="$(./macos/rck_macos target-lookup-tag32-build-from-keys-bench --target-count 64 --injected-count 8 --iterations 1 2>&1)"
build_from_keys_status=$?
set -e

if [ "$build_from_keys_status" -ne 0 ]; then
	printf 'target-lookup-tag32-build-from-keys-bench returned status %s\n' "$build_from_keys_status"
	printf '%s\n' "$build_from_keys_output"
	exit 1
fi

case "$build_from_keys_output" in
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"target_lookup_tag32_build_from_injected_keys\""*"\"setup_phase\":\"host_tag32_build_from_injected_keys\""*"\"lookup_layout\":\"open_address_tag32_index_exact256\""*"\"target_key\":\"x256_y_parity\""*"\"candidate_verification\":\"legacy_tag32_table_field_equality\""*"\"iterations\":1"*"\"target_count\":64"*"\"injected_count\":8"*"\"target_table_buckets\":128"*"\"target_key_bytes\":2560"*"\"target_bucket_bytes\":1024"*"\"target_table_bytes\":3584"*"\"legacy_seconds\":"*"\"prehashed_seconds\":"*"\"speedup\":"*"\"legacy_targets_per_sec\":"*"\"prehashed_targets_per_sec\":"*"\"legacy_checksum\":\"0x"*"\"prehashed_checksum\":\"0x"*"\"table_equal\":true"*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$build_from_keys_output"
		printf '%s\n' "unexpected target-lookup-tag32-build-from-keys-bench output"
		exit 1
		;;
esac

set +e
parallel_insert_output="$(./macos/rck_macos target-lookup-tag32-parallel-insert-bench --target-count 64 --injected-count 8 --iterations 1 2>&1)"
parallel_insert_status=$?
set -e

if [ "$parallel_insert_status" -ne 0 ]; then
	printf 'target-lookup-tag32-parallel-insert-bench returned status %s\n' "$parallel_insert_status"
	printf '%s\n' "$parallel_insert_output"
	exit 1
fi

case "$parallel_insert_output" in
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"target_lookup_tag32_parallel_insert_probe\""*"\"setup_phase\":\"host_tag32_parallel_insert_probe\""*"\"lookup_layout\":\"open_address_tag32_index_exact256\""*"\"target_key\":\"x256_y_parity\""*"\"candidate_verification\":\"prehashed_serial_vs_parallel_semantic_find_all_keys\""*"\"iterations\":1"*"\"target_count\":64"*"\"injected_count\":8"*"\"target_table_buckets\":128"*"\"target_key_bytes\":2560"*"\"target_bucket_bytes\":1024"*"\"target_table_bytes\":3584"*"\"serial_seconds\":"*"\"parallel_seconds\":"*"\"speedup\":"*"\"serial_targets_per_sec\":"*"\"parallel_targets_per_sec\":"*"\"serial_checksum\":\"0x"*"\"parallel_checksum\":\"0x"*"\"target_keys_equal\":true"*"\"all_keys_found\":true"*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$parallel_insert_output"
		printf '%s\n' "unexpected target-lookup-tag32-parallel-insert-bench output"
		exit 1
		;;
esac
