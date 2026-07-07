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
	*"\"backend\":\"macos_cpu\""*"\"operation\":\"jacobian_kangaroo_multi_small\""*"\"architecture\":\"shared_tame\""*"\"ecint_carry_impl\":\"clang_builtin\""*"\"ecint_mul_final_sub\":\"single_conditional\""*"\"field_rhs_passing\":\"const_ref\""*"\"jacobian_step_passing\":\"const_ref\""*"\"dp_lookup\":\"open_address_linear\""*"\"dp_hash\":\"partial_limb_mix\""*"\"dp_key\":\"x_parity\""*"\"candidate_verification\":\"full_point_collision\""*"\"dp_reserve\":\"sqrt_range_estimate\""*"\"dp_capacity\":\"max_load_2of3\""*"\"dp_bucket_storage\":\"inline_first\""*"\"dp_clear\":\"empty_guard\""*"\"point_passing\":\"const_ref\""*"\"affine_conversion\":\"batch\""*"\"affine_initial_conversion\":\"unit_z_copy\""*"\"affine_z_access\":\"const_ref\""*"\"affine_z_check\":\"infinity_flag\""*"\"affine_field_ops\":\"inplace\""*"\"affine_buffer\":\"resize_reuse\""*"\"affine_active_path\":\"all_active_fast\""*"\"affine_reverse_loop\":\"split_zero\""*"\"affine_tail_update\":\"skip_final\""*"\"jump_index\":\"power2_mask\""*"\"jump_table\":\"precomputed\""*"\"jump_schedule\":\"power2\""*"\"scratch\":\"reused\""*"\"range_context\":\"precomputed\""*"\"target_count\":4"*"\"tame_states\":1"*"\"wild_states\":4"*"\"single_target_ops_per_sec\":"*"\"speedup_vs_single\":"*"\"target_throughput_vs_single\":"*"\"found_target_index\":3"*"\"found_private_key\":\"0x7\""*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "unexpected jacobian-kangaroo-multi-small-bench output"
		exit 1
		;;
esac

scaled_output="$(./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 0 --range 20 --jumps 4 --dp-bits 4 --max-steps 500000 --jump-schedule scaled4-balanced 2>&1)"
case "$scaled_output" in
	*"\"operation\":\"jacobian_kangaroo_multi_small\""*"\"jump_schedule\":\"scaled4_balanced\""*"\"jump_count\":4"*"\"found_target_index\":15"*"\"found_private_key\":\"0x7\""*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$scaled_output"
		printf '%s\n' "unexpected scaled4-balanced multi-target output"
		exit 1
		;;
esac

scaled_mid_output="$(./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 0 --range 20 --jumps 4 --dp-bits 4 --max-steps 2000000 --jump-schedule scaled4-balanced --key-offset 524288 2>&1)"
case "$scaled_mid_output" in
	*"\"operation\":\"jacobian_kangaroo_multi_small\""*"\"jump_schedule\":\"scaled4_balanced\""*"\"jump_count\":4"*"\"key_offset\":524288"*"\"expected_private_key\":\"0x80002\""*"\"found_target_index\":15"*"\"found_private_key\":\"0x80002\""*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$scaled_mid_output"
		printf '%s\n' "unexpected mid-interval scaled4-balanced multi-target output"
		exit 1
		;;
esac

portfolio_high_output="$(./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 0 --range 20 --jumps 4 --dp-bits 4 --max-steps 2000000 --jump-schedule scaled4-probe-power2 --key-offset 900000 2>&1)"
case "$portfolio_high_output" in
	*"\"operation\":\"jacobian_kangaroo_multi_small\""*"\"jump_schedule\":\"scaled4_probe_power2\""*"\"portfolio_probe_jump_schedule\":\"scaled4_balanced\""*"\"portfolio_probe_max_steps\":10000"*"\"portfolio_fallback_jump_schedule\":\"power2\""*"\"portfolio_fallback_jump_count\":16"*"\"portfolio_fallback_runs\":1"*"\"last_portfolio_probe_dp_count\":"*"\"key_offset\":900000"*"\"expected_private_key\":\"0xdbba2\""*"\"found_target_index\":15"*"\"found_private_key\":\"0xdbba2\""*"\"correctness\":true"*)
		;;
	*)
		printf '%s\n' "$portfolio_high_output"
		printf '%s\n' "unexpected high-offset scaled4-probe-power2 portfolio output"
		exit 1
		;;
esac

invalid_output="$(./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 0 --range 20 --jumps 16 --dp-bits 4 --max-steps 500000 --jump-schedule scaled4-balanced 2>&1)"
case "$invalid_output" in
	*"\"jump_schedule\":\"scaled4_balanced\""*"\"correctness\":false"*"\"reason\":\"jump schedule requires --jumps 4\""*)
		;;
	*)
		printf '%s\n' "$invalid_output"
		printf '%s\n' "unexpected invalid scaled4-balanced guard output"
		exit 1
		;;
esac

invalid_portfolio_output="$(./macos/rck_macos jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 0 --range 20 --jumps 16 --dp-bits 4 --max-steps 500000 --jump-schedule scaled4-probe-power2 2>&1)"
case "$invalid_portfolio_output" in
	*"\"jump_schedule\":\"scaled4_probe_power2\""*"\"correctness\":false"*"\"reason\":\"jump schedule requires --jumps 4\""*)
		;;
	*)
		printf '%s\n' "$invalid_portfolio_output"
		printf '%s\n' "unexpected invalid scaled4-probe-power2 guard output"
		exit 1
		;;
esac
