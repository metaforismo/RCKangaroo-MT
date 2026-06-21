#!/bin/sh
set -eu

source_header="macos/MetalFieldKernels.h"
host_source="macos/MetalField.mm"
if [ ! -f "$source_header" ]; then
	printf 'missing %s\n' "$source_header"
	exit 1
fi
if [ ! -f "$host_source" ]; then
	printf 'missing %s\n' "$host_source"
	exit 1
fi

tmp_source="${TMPDIR:-/tmp}/rck_metal_field_kernels_$$.metal"
tmp_air="${TMPDIR:-/tmp}/rck_metal_field_kernels_$$.air"
trap 'rm -f "$tmp_source" "$tmp_air" "$tmp_air.out"' EXIT

awk '
	/R"RCK_METAL\(/ { emit = 1; next }
	/\)RCK_METAL";/ { emit = 0 }
	emit { print }
' "$source_header" > "$tmp_source"

if ! grep -q "kernel void field_add_mod_p" "$tmp_source"; then
	printf '%s\n' "field_add_mod_p kernel missing from Metal source"
	exit 1
fi

if ! grep -q "kernel void field_sub_mod_p" "$tmp_source"; then
	printf '%s\n' "field_sub_mod_p kernel missing from Metal source"
	exit 1
fi

if ! grep -q "kernel void field_double_mod_p" "$tmp_source"; then
	printf '%s\n' "field_double_mod_p kernel missing from Metal source"
	exit 1
fi

if ! grep -q "kernel void field_neg_mod_p" "$tmp_source"; then
	printf '%s\n' "field_neg_mod_p kernel missing from Metal source"
	exit 1
fi

if ! grep -q "kernel void field_mul4_mod_p" "$tmp_source"; then
	printf '%s\n' "field_mul4_mod_p kernel missing from Metal source"
	exit 1
fi

if ! grep -q "kernel void field_mul_mod_p" "$tmp_source"; then
	printf '%s\n' "field_mul_mod_p kernel missing from Metal source"
	exit 1
fi

if ! grep -q "kernel void field_square_mod_p" "$tmp_source"; then
	printf '%s\n' "field_square_mod_p kernel missing from Metal source"
	exit 1
fi

if ! grep -q "kernel void field_square_mul_mod_p" "$tmp_source"; then
	printf '%s\n' "field_square_mul_mod_p kernel missing from Metal source"
	exit 1
fi

if ! grep -q "kernel void jacobian_add_affine" "$tmp_source"; then
	printf '%s\n' "jacobian_add_affine kernel missing from Metal source"
	exit 1
fi

if ! grep -q "kernel void jacobian_affine_walk_fixed" "$tmp_source"; then
	printf '%s\n' "jacobian_affine_walk_fixed kernel missing from Metal source"
	exit 1
fi

if ! grep -q "kernel void jacobian_affine_walk_jump_table" "$tmp_source"; then
	printf '%s\n' "jacobian_affine_walk_jump_table kernel missing from Metal source"
	exit 1
fi

if ! grep -q "kernel void jacobian_affine_walk_jump_table_steps8" "$tmp_source"; then
	printf '%s\n' "jacobian_affine_walk_jump_table_steps8 kernel missing from Metal source"
	exit 1
fi

if ! grep -q "kernel void jacobian_affine_walk_jump_table_steps8_dp4" "$tmp_source"; then
	printf '%s\n' "jacobian_affine_walk_jump_table_steps8_dp4 kernel missing from Metal source"
	exit 1
fi

if ! grep -q "field_square_values" "$tmp_source"; then
	printf '%s\n' "field_square_values helper missing from Metal source"
	exit 1
fi

if grep -q "store_jacobian_u8_infinity" "$tmp_source"; then
	printf '%s\n' "stale store_jacobian_u8_infinity helper still present"
	exit 1
fi

if ! awk '
	/kernel void field_square_mod_p/ { in_square = 1 }
	in_square && /field_square_values/ { found = 1 }
	in_square && /^}/ { in_square = 0 }
	END { exit found ? 0 : 1 }
' "$tmp_source"; then
	printf '%s\n' "field_square_mod_p does not use field_square_values"
	exit 1
fi

if ! awk '
	/kernel void field_square_mul_mod_p/ { in_square_mul = 1 }
	in_square_mul && /field_square_values/ { found_square = 1 }
	in_square_mul && /field_mul_values/ { found_mul = 1 }
	in_square_mul && /^}/ { in_square_mul = 0 }
	END { exit (found_square && found_mul) ? 0 : 1 }
' "$tmp_source"; then
	printf '%s\n' "field_square_mul_mod_p does not use square and multiply helpers"
	exit 1
fi

if ! awk '
	/static inline JacobianValue jacobian_add_affine_values/ { in_helper = 1 }
	in_helper && /uint p_infinity/ { found_p_infinity = 1 }
	in_helper && /if \(p_infinity\)/ { found_inf_branch = 1 }
	in_helper && /jacobian_add_affine_finite_values/ { found_finite_delegate = 1 }
	in_helper && /kernel void jacobian_add_affine/ { in_helper = 0 }
	END { exit (found_p_infinity && found_inf_branch && found_finite_delegate) ? 0 : 1 }
' "$tmp_source"; then
	printf '%s\n' "jacobian_add_affine_values does not preserve infinity handling with finite helper delegation"
	exit 1
fi

if ! awk '
	/static inline JacobianValue jacobian_add_affine_finite_values/ { in_helper = 1 }
	in_helper && /uint p_infinity/ { found_p_infinity = 1 }
	in_helper && /if \(p_infinity\)/ { found_inf_branch = 1 }
	in_helper && /field_square_values/ { found_square = 1 }
	in_helper && /field_mul_values/ { found_mul = 1 }
	in_helper && /field_sub_values/ { found_sub = 1 }
	in_helper && /static inline JacobianValue jacobian_add_affine_values/ { in_helper = 0 }
	END { exit (!found_p_infinity && !found_inf_branch && found_square && found_mul && found_sub) ? 0 : 1 }
' "$tmp_source"; then
	printf '%s\n' "jacobian_add_affine_finite_values missing or not limited to finite input points"
	exit 1
fi

if ! awk '
	/kernel void jacobian_add_affine/ { in_jacobian = 1 }
	in_jacobian && /jacobian_add_affine_values/ { found_step = 1 }
	in_jacobian && /^}/ { in_jacobian = 0 }
	END { exit found_step ? 0 : 1 }
' "$tmp_source"; then
	printf '%s\n' "jacobian_add_affine does not use shared Jacobian add helper"
	exit 1
fi

if ! awk '
	/kernel void jacobian_affine_walk_fixed/ { in_walk = 1 }
	in_walk && /jacobian_add_affine_values/ { found_step = 1 }
	in_walk && /for \(uint step/ { found_loop = 1 }
	in_walk && /^}/ { in_walk = 0 }
	END { exit (found_step && found_loop) ? 0 : 1 }
' "$tmp_source"; then
	printf '%s\n' "jacobian_affine_walk_fixed does not loop over the shared Jacobian add helper"
	exit 1
fi

if ! awk '
	/kernel void jacobian_affine_walk_jump_table/ { in_walk = 1 }
	in_walk && /constant ulong\* p_xyz/ { found_constant_p = 1 }
	in_walk && /constant ulong\* q_xy/ { found_constant_q = 1 }
	in_walk && /constant uint\* p_infinity/ { found_constant_inf = 1 }
	in_walk && /constant uchar\* jump_indices/ { found_indices = 1 }
	in_walk && /constant ulong\* jump_distances/ { found_distances = 1 }
	in_walk && /device uchar\* out_flags/ { found_out_flags = 1 }
	in_walk && /device .*out_infinity/ { found_old_out_inf = 1 }
	in_walk && /device ulong\* out_distances/ { found_out_distances = 1 }
	in_walk && /device .*out_dp_flags/ { found_old_out_dp_flags = 1 }
	in_walk && /constant ulong& dp_mask/ { found_dp_mask = 1 }
	in_walk && /jacobian_add_affine_values/ { found_step = 1 }
	in_walk && /uint p_base = \(id << 3\) \+ \(id << 2\)/ { found_p_base_shift = 1 }
	in_walk && /uint p_base = id \* 12/ { found_p_base_mul = 1 }
	in_walk && /uint out_base = p_base/ { found_out_base_reuse = 1 }
	in_walk && /uint out_base = id \* 12/ { found_out_base_mul = 1 }
	in_walk && /uint jump_base = id \* steps/ { found_jump_base = 1 }
	in_walk && /for \(uint step/ { found_loop = 1 }
	in_walk && /uint jump_index = jump_indices\[jump_base \+ step\]/ { found_jump_base_fetch = 1 }
	in_walk && /uint jump_index = \(uint\)jump_indices\[jump_base \+ step\]/ { found_jump_base_cast = 1 }
	in_walk && /jump_indices\[id \* steps \+ step\]/ { found_hot_jump_mul = 1 }
	in_walk && /distance \+= jump_distances\[jump_index\]/ { found_accumulate = 1 }
	in_walk && /uint q_base = jump_index << 3/ { found_q_base_shift = 1 }
	in_walk && /uint q_base = jump_index \* 8/ { found_q_base_mul = 1 }
	in_walk && /out_distances\[id\] = distance/ { found_store = 1 }
	in_walk && /out_flags\[id\]/ { found_flags_store = 1 }
	in_walk && /\? 2 : 0/ { found_dp_bit = 1 }
	in_walk && /\(x0 & dp_mask\) == 0/ { found_dp_mask_test = 1 }
	in_walk && /(1UL << dp_bits|dp_bits == 0)/ { found_hot_dp_mask_build = 1 }
	in_walk && /% jump_count/ { found_hot_mod = 1 }
	in_walk && /^}/ { in_walk = 0 }
	END { exit (found_constant_p && found_constant_q && found_constant_inf && found_indices && found_distances && found_out_flags && !found_old_out_inf && found_out_distances && !found_old_out_dp_flags && found_dp_mask && found_step && found_p_base_shift && !found_p_base_mul && found_out_base_reuse && !found_out_base_mul && found_jump_base && found_loop && found_jump_base_fetch && !found_jump_base_cast && found_accumulate && found_q_base_shift && !found_q_base_mul && found_store && found_flags_store && found_dp_bit && found_dp_mask_test && !found_hot_jump_mul && !found_hot_dp_mask_build && !found_hot_mod) ? 0 : 1 }
' "$tmp_source"; then
	printf '%s\n' "jacobian_affine_walk_jump_table does not precompute hot base state and constant read-only buffers"
	exit 1
fi

if ! awk '
	/kernel void jacobian_affine_walk_jump_table_steps8/ { in_walk = 1 }
	in_walk && /constant ulong\* p_xyz/ { found_constant_p = 1 }
	in_walk && /constant ulong\* q_xy/ { found_constant_q = 1 }
	in_walk && /constant uint\* p_infinity/ { found_constant_inf = 1 }
	in_walk && /constant uchar\* jump_indices/ { found_indices = 1 }
	in_walk && /constant ulong\* jump_distances/ { found_distances = 1 }
	in_walk && /device uchar\* out_flags/ { found_out_flags = 1 }
	in_walk && /device .*out_infinity/ { found_old_out_inf = 1 }
	in_walk && /device ulong\* out_distances/ { found_out_distances = 1 }
	in_walk && /device .*out_dp_flags/ { found_old_out_dp_flags = 1 }
	in_walk && /constant ulong& dp_mask/ { found_dp_mask = 1 }
	in_walk && /jacobian_add_affine_values/ { found_step = 1 }
	in_walk && /uint p_base = \(id << 3\) \+ \(id << 2\)/ { found_p_base_shift = 1 }
	in_walk && /uint p_base = id \* 12/ { found_p_base_mul = 1 }
	in_walk && /uint out_base = p_base/ { found_out_base_reuse = 1 }
	in_walk && /uint out_base = id \* 12/ { found_out_base_mul = 1 }
	in_walk && /uint jump_base = id << 3/ { found_jump_base = 1 }
	in_walk && /for \(uint step = 0; step < 8; step\+\+\)/ { found_fixed_loop = 1 }
	in_walk && /step < steps/ { found_dynamic_loop = 1 }
	in_walk && /uint jump_index = jump_indices\[jump_base \+ step\]/ { found_jump_base_fetch = 1 }
	in_walk && /uint jump_index = \(uint\)jump_indices\[jump_base \+ step\]/ { found_jump_base_cast = 1 }
	in_walk && /distance \+= jump_distances\[jump_index\]/ { found_accumulate = 1 }
	in_walk && /uint q_base = jump_index << 3/ { found_q_base_shift = 1 }
	in_walk && /uint q_base = jump_index \* 8/ { found_q_base_mul = 1 }
	in_walk && /out_distances\[id\] = distance/ { found_store = 1 }
	in_walk && /out_flags\[id\]/ { found_flags_store = 1 }
	in_walk && /\? 2 : 0/ { found_dp_bit = 1 }
	in_walk && /\(x0 & dp_mask\) == 0/ { found_dp_mask_test = 1 }
	in_walk && /(1UL << dp_bits|dp_bits == 0)/ { found_hot_dp_mask_build = 1 }
	in_walk && /% jump_count/ { found_hot_mod = 1 }
	in_walk && /^}/ { in_walk = 0 }
	END { exit (found_constant_p && found_constant_q && found_constant_inf && found_indices && found_distances && found_out_flags && !found_old_out_inf && found_out_distances && !found_old_out_dp_flags && found_dp_mask && found_step && found_p_base_shift && !found_p_base_mul && found_out_base_reuse && !found_out_base_mul && found_jump_base && found_fixed_loop && !found_dynamic_loop && found_jump_base_fetch && !found_jump_base_cast && found_accumulate && found_q_base_shift && !found_q_base_mul && found_store && found_flags_store && found_dp_bit && found_dp_mask_test && !found_hot_dp_mask_build && !found_hot_mod) ? 0 : 1 }
' "$tmp_source"; then
	printf '%s\n' "jacobian_affine_walk_jump_table_steps8 does not use the fixed steps=8 constant read-only hot path with shifted point base"
	exit 1
fi

if ! awk '
	/kernel void jacobian_affine_walk_jump_table_steps8_dp4/ { in_walk = 1 }
	in_walk && /constant ulong\* p_xyz/ { found_constant_p = 1 }
	in_walk && /constant ulong\* q_xy/ { found_constant_q = 1 }
	in_walk && /constant uint\* p_infinity/ { found_constant_inf = 1 }
	in_walk && /constant uchar\* jump_indices/ { found_indices = 1 }
	in_walk && /constant ulong\* jump_distances/ { found_distances = 1 }
	in_walk && /constant ulong& dp_mask/ { found_dynamic_dp_mask = 1 }
	in_walk && /\(x0 & 0xFUL\) == 0/ { found_dp4_mask = 1 }
	in_walk && /bool inf = p_infinity\[id\] != 0/ { found_bool_inf = 1 }
	in_walk && /uint inf = p_infinity\[id\]/ { found_uint_inf = 1 }
	in_walk && /inf = out.inf != 0/ { found_bool_inf_update = 1 }
	in_walk && /inf = out.inf;/ { found_uint_inf_update = 1 }
	in_walk && /uint jump_base = id << 3/ { found_jump_base = 1 }
	in_walk && /for \(uint step = 0; step < 8; step\+\+\)/ { found_fixed_loop = 1 }
	in_walk && /if \(inf\)/ { found_inf_guard = 1 }
	in_walk && /jacobian_add_affine_values/ { found_generic_step = 1 }
	in_walk && /jacobian_add_affine_finite_values/ { found_finite_step = 1 }
	in_walk && /out_flags\[id\]/ { found_flags_store = 1 }
	in_walk && /^}/ { in_walk = 0 }
	END { exit (found_constant_p && found_constant_q && found_constant_inf && found_indices && found_distances && !found_dynamic_dp_mask && found_dp4_mask && found_bool_inf && !found_uint_inf && found_bool_inf_update && !found_uint_inf_update && found_jump_base && found_fixed_loop && found_inf_guard && found_generic_step && found_finite_step && found_flags_store) ? 0 : 1 }
' "$tmp_source"; then
	printf '%s\n' "jacobian_affine_walk_jump_table_steps8_dp4 does not keep the finite hot path with bool infinity state"
	exit 1
fi

if ! awk '
	/RunJacobianJumpWalkKernel/ { in_host = 1 }
	in_host && /steps_per_sample == 8 && dp_bits == 4/ && /jacobian_affine_walk_jump_table_steps8_dp4/ { found_dp4_selection = 1 }
	in_host && /steps_per_sample == 8/ && /jacobian_affine_walk_jump_table_steps8/ && /jacobian_affine_walk_jump_table/ { found_selection = 1 }
	in_host && /std::vector<uint8_t> metal_jump_indices/ { found_packed = 1 }
	in_host && /metal_jump_indices.push_back\(static_cast<uint8_t>\(jump_index\)\)/ { found_pack_push = 1 }
	in_host && /size_t indices_bytes = metal_jump_indices.size\(\) \* sizeof\(uint8_t\)/ { found_packed_bytes = 1 }
	in_host && /newBufferWithBytes:metal_jump_indices.data\(\) length:indices_bytes/ { found_packed_buffer = 1 }
	in_host && /size_t p_inf_bytes = p_infinity.size\(\) \* sizeof\(uint32_t\)/ { found_p_inf_bytes = 1 }
	in_host && /newBufferWithBytes:p_infinity.data\(\) length:p_inf_bytes/ { found_p_inf_buffer = 1 }
	in_host && /std::vector<uint8_t> out_flags_metal/ { found_packed_flags_out = 1 }
	in_host && /size_t out_flags_bytes = out_flags_metal.size\(\) \* sizeof\(uint8_t\)/ { found_packed_flags_bytes = 1 }
	in_host && /newBufferWithLength:out_flags_bytes/ { found_out_flags_buffer = 1 }
	in_host && /memcpy\(out_flags_metal.data\(\), \[out_flags_buffer contents\], out_flags_bytes\)/ { found_packed_flags_copy = 1 }
	in_host && /uint8_t flags = out_flags_metal\[i\]/ { found_flags_local = 1 }
	in_host && /out_infinity\[i\] = \(flags & 1U\) \? 1U : 0U/ { found_inf_expand = 1 }
	in_host && /out_dp_flags\[i\] = \(flags & 2U\) \? 1U : 0U/ { found_dp_expand = 1 }
	in_host && /out_dp_flags_buffer/ { found_old_dp_buffer = 1 }
	in_host && /out_infinity_metal/ { found_old_inf_metal = 1 }
	in_host && /dp_flags_out_metal/ { found_old_dp_metal = 1 }
	in_host && /newBufferWithLength:inf_bytes/ { found_old_out_inf_buffer = 1 }
	in_host && /memcpy\(out_infinity.data\(\), \[out_inf_buffer contents\], inf_bytes\)/ { found_old_inf_copy = 1 }
	in_host && /dp_flags_out.size\(\) \* sizeof\(uint32_t\)/ { found_u32_dp_bytes = 1 }
	in_host && /jump_indices.size\(\) \* sizeof\(uint32_t\)/ { found_u32_bytes = 1 }
	in_host && /newFunctionWithName:\[NSString stringWithUTF8String:function_name\]/ { found_dynamic_load = 1 }
	in_host && /NSUInteger threadgroup_count = \(count \+ threads_per_threadgroup - 1\) \/ threads_per_threadgroup/ { found_threadgroup_count = 1 }
	in_host && /\[encoder dispatchThreadgroups:MTLSizeMake\(threadgroup_count, 1, 1\) threadsPerThreadgroup:MTLSizeMake\(threads_per_threadgroup, 1, 1\)\]/ { found_dispatch_threadgroups = 1 }
	in_host && /\[encoder dispatchThreads:/ { found_dispatch_threads = 1 }
	in_host && /^}/ { in_host = 0 }
	END { exit (found_dp4_selection && found_selection && found_packed && found_pack_push && found_packed_bytes && found_packed_buffer && found_p_inf_bytes && found_p_inf_buffer && found_packed_flags_out && found_packed_flags_bytes && found_out_flags_buffer && found_packed_flags_copy && found_flags_local && found_inf_expand && found_dp_expand && !found_old_dp_buffer && !found_old_inf_metal && !found_old_dp_metal && !found_old_out_inf_buffer && !found_old_inf_copy && !found_u32_dp_bytes && !found_u32_bytes && found_dynamic_load && found_threadgroup_count && found_dispatch_threadgroups && !found_dispatch_threads) ? 0 : 1 }
' "$host_source"; then
	printf '%s\n' "RunJacobianJumpWalkKernel does not pack Metal jump indices and combined output flags to uint8 with dp4 steps8 specialization and generic fallback"
	exit 1
fi

set +e
xcrun -sdk macosx metal -c "$tmp_source" -o "$tmp_air" > "$tmp_air.out" 2>&1
status=$?
set -e

if [ "$status" -eq 0 ]; then
	printf '%s\n' "metal kernels compile ok"
	exit 0
fi

if grep -q "missing Metal Toolchain" "$tmp_air.out"; then
	printf '%s\n' "metal kernels compile skipped: missing Metal Toolchain"
	exit 0
fi

cat "$tmp_air.out"
exit "$status"
