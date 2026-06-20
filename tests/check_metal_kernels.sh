#!/bin/sh
set -eu

source_header="macos/MetalFieldKernels.h"
if [ ! -f "$source_header" ]; then
	printf 'missing %s\n' "$source_header"
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

if ! grep -q "field_square_values" "$tmp_source"; then
	printf '%s\n' "field_square_values helper missing from Metal source"
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
	in_helper && /field_square_values/ { found_square = 1 }
	in_helper && /field_mul_values/ { found_mul = 1 }
	in_helper && /field_sub_values/ { found_sub = 1 }
	in_helper && /kernel void jacobian_add_affine/ { in_helper = 0 }
	END { exit (found_square && found_mul && found_sub) ? 0 : 1 }
' "$tmp_source"; then
	printf '%s\n' "jacobian_add_affine_values does not use field square/mul/sub helpers"
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
	in_walk && /device const uint\* jump_indices/ { found_indices = 1 }
	in_walk && /jacobian_add_affine_values/ { found_step = 1 }
	in_walk && /for \(uint step/ { found_loop = 1 }
	in_walk && /% jump_count/ { found_hot_mod = 1 }
	in_walk && /^}/ { in_walk = 0 }
	END { exit (found_indices && found_step && found_loop && !found_hot_mod) ? 0 : 1 }
' "$tmp_source"; then
	printf '%s\n' "jacobian_affine_walk_jump_table does not use pre-normalized jump indices in the hot loop"
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
