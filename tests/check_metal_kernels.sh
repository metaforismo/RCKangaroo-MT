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

if ! grep -q "kernel void field_mul_mod_p" "$tmp_source"; then
	printf '%s\n' "field_mul_mod_p kernel missing from Metal source"
	exit 1
fi

if ! grep -q "kernel void field_square_mod_p" "$tmp_source"; then
	printf '%s\n' "field_square_mod_p kernel missing from Metal source"
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
