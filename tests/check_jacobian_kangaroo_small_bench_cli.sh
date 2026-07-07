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
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"jacobian_kangaroo_small\""*"\"ecint_carry_impl\":\"clang_builtin\""*"\"ecint_mul_final_sub\":\"single_conditional\""*"\"field_rhs_passing\":\"const_ref\""*"\"jacobian_step_passing\":\"const_ref\""*"\"dp_lookup\":\"open_address_linear\""*"\"dp_hash\":\"partial_limb_mix\""*"\"dp_key\":\"x_parity\""*"\"candidate_verification\":\"full_point_collision\""*"\"dp_reserve\":\"sqrt_range_estimate\""*"\"dp_capacity\":\"max_load_2of3\""*"\"dp_bucket_storage\":\"inline_first\""*"\"dp_clear\":\"empty_guard\""*"\"point_passing\":\"const_ref\""*"\"affine_conversion\":\"batch\""*"\"affine_initial_conversion\":\"unit_z_copy\""*"\"jump_index\":\"power2_mask\""*"\"jump_table\":\"precomputed\""*"\"jump_schedule\":\"power2\""*"\"scratch\":\"reused\""*"\"range_context\":\"precomputed\""*"\"target_count\":1"*"\"tame_states\":1"*"\"wild_states\":1"*"\"found_target_index\":0"*"\"found_private_key\":\"0x7\""*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected jacobian-kangaroo-small-bench output"
		exit 1
		;;
esac

offset_output="$(./macos/rck_macos jacobian-kangaroo-small-bench --iterations 1 --min-ms 0 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096 --key-offset 42 2>&1)"
case "$offset_output" in
	*"\"operation\":\"jacobian_kangaroo_small\""*"\"key_offset\":42"*"\"expected_private_key\":\"0x2a\""*"\"found_target_index\":0"*"\"found_private_key\":\"0x2a\""*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$offset_output"
		printf '%s\n' "unexpected key-offset jacobian-kangaroo-small-bench output"
		exit 1
		;;
esac

portfolio_output="$(./macos/rck_macos jacobian-kangaroo-small-bench --iterations 1 --min-ms 0 --range 20 --jumps 4 --dp-bits 4 --max-steps 2000000 --jump-schedule scaled4-probe-power2 --key-offset 7 2>&1)"
case "$portfolio_output" in
	*"\"operation\":\"jacobian_kangaroo_small\""*"\"jump_schedule\":\"scaled4_probe_power2\""*"\"portfolio_probe_jump_schedule\":\"scaled4_balanced\""*"\"portfolio_probe_max_steps\":10000"*"\"portfolio_fallback_jump_schedule\":\"power2\""*"\"portfolio_fallback_jump_count\":16"*"\"portfolio_probe_hits\":1"*"\"portfolio_fallback_runs\":0"*"\"key_offset\":7"*"\"expected_private_key\":\"0x7\""*"\"found_target_index\":0"*"\"found_private_key\":\"0x7\""*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$portfolio_output"
		printf '%s\n' "unexpected scaled4-probe-power2 single-target output"
		exit 1
		;;
esac
