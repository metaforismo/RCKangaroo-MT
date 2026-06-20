#!/bin/sh
set -eu

source_file="macos/RCKMac.cpp"

if ! grep -q "JacobianBatchReverseLoopMode" "$source_file"; then
	printf '%s\n' "missing batch affine reverse-loop marker"
	exit 1
fi

if ! grep -q 'return "split_zero"' "$source_file"; then
	printf '%s\n' "batch affine reverse loop should report split_zero"
	exit 1
fi

if ! grep -q "affine_reverse_loop" "$source_file"; then
	printf '%s\n' "missing affine_reverse_loop JSON marker"
	exit 1
fi

if ! grep -q "remaining > 1" "$source_file"; then
	printf '%s\n' "all-active reverse loop should stop before index zero"
	exit 1
fi

if ! grep -q "affines\\[0\\]\\.x = tame\\.x" "$source_file"; then
	printf '%s\n' "all-active index zero should be handled explicitly"
	exit 1
fi
