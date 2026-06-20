#!/bin/sh
set -eu

set +e
output=$(./macos/rck_macos jacobian-batch-affine-bench --points 17 --iterations 1 --min-ms 1)
status=$?
set -e

if [ "$status" -ne 0 ]; then
	printf '%s\n' "$output"
	printf 'jacobian-batch-affine-bench returned status %s\n' "$status"
	exit "$status"
fi

case "$output" in
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"jacobian_batch_affine\""*"\"field_rhs_passing\":\"const_ref\""*"\"affine_conversion\":\"batch\""*"\"affine_z_access\":\"const_ref\""*"\"affine_z_check\":\"infinity_flag\""*"\"affine_buffer\":\"resize_reuse\""*"\"affine_active_path\":\"all_active_fast\""*"\"affine_tail_update\":\"skip_final\""*"\"batch_points\":17"*"\"wild_points\":16"*"\"iterations\":"*"\"ops_per_sec\":"*"\"points_per_sec\":"*"\"checksum\":\"0x"*"\"correctness\":true"*)
		exit 0
		;;
	*)
		printf '%s\n' "$output"
		printf 'unexpected jacobian-batch-affine-bench output\n'
		exit 1
		;;
esac
