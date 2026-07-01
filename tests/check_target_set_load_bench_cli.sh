#!/bin/sh
set -eu

output="$(./macos/rck_macos target-set-load-bench --target-count 64 --iterations 1 --start 2 2>&1)"

case "$output" in
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"target_set_load\""*"\"setup_phase\":\"multi_target_start_offset_mapping\""*"\"parser\":\"shared_target_set\""*"\"fixture\":\"alternating_public_key_generator\""*"\"key_format\":\"compressed\""*"\"mapping\":\"batch_inversion_chunks\""*"\"batch_size\":32768"*"\"metric\":\"targets_per_sec\""*"\"iterations\":1"*"\"target_count\":64"*"\"loaded_count\":64"*"\"start_scalar\":\"0x2\""*"\"seconds\":"*"\"targets_per_sec\":"*"\"checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected target-set-load-bench output"
		exit 1
		;;
esac

uncompressed_output="$(./macos/rck_macos target-set-load-bench --target-count 64 --iterations 1 --start 2 --key-format uncompressed 2>&1)"

case "$uncompressed_output" in
	*"\"operation\":\"target_set_load\""*"\"key_format\":\"uncompressed\""*"\"target_count\":64"*"\"loaded_count\":64"*"\"checksum\":\"0x"*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$uncompressed_output"
		printf '%s\n' "unexpected uncompressed target-set-load-bench output"
		exit 1
		;;
esac
