#!/bin/sh
set -eu

source_file="macos/RCKMac.cpp"

if ! grep -q "JacobianBatchFieldOpsMode" "$source_file"; then
	printf '%s\n' "missing batch affine field-op marker"
	exit 1
fi

if ! grep -q "acc.MulModP(z)" "$source_file"; then
	printf '%s\n' "batch affine prefix products should update acc in place"
	exit 1
fi

if ! grep -q "affines\\[i\\]\\.x.MulModP(z2)" "$source_file"; then
	printf '%s\n' "batch affine x conversion should multiply in place"
	exit 1
fi

if ! grep -q "affines\\[i\\]\\.y.MulModP(z3)" "$source_file"; then
	printf '%s\n' "batch affine y conversion should multiply in place"
	exit 1
fi

if ! grep -q "affine_field_ops" "$source_file"; then
	printf '%s\n' "missing affine_field_ops JSON marker"
	exit 1
fi
