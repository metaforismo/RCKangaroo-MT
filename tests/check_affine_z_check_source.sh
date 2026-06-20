#!/bin/sh
set -eu

source_file="macos/RCKMac.cpp"

if ! grep -q "JacobianBatchZCheckMode" "$source_file"; then
	printf '%s\n' "missing affine z-check marker"
	exit 1
fi

if grep -q "p.infinity || IntIsZero(z)" "$source_file"; then
	printf '%s\n' "batch affine hot path should use the infinity flag instead of scanning z"
	exit 1
fi

if ! grep -q "affine_z_check" "$source_file"; then
	printf '%s\n' "missing affine_z_check JSON marker"
	exit 1
fi
