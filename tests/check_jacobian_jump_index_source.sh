#!/bin/sh
set -eu

source_file="macos/RCKMac.cpp"

if ! grep -q "IsPowerOfTwo" "$source_file"; then
	printf '%s\n' "Jacobian jump index power-of-two helper missing"
	exit 1
fi

if ! grep -q "mixed & (jump_count - 1)" "$source_file"; then
	printf '%s\n' "Jacobian jump index does not use a power-of-two mask"
	exit 1
fi
