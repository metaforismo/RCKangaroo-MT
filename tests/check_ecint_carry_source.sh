#!/bin/sh
set -eu

if ! grep -q "__builtin_addcll" utils.h; then
	printf '%s\n' "EcInt add carry should use clang builtin on supported non-x86 builds"
	exit 1
fi

if ! grep -q "__builtin_subcll" utils.h; then
	printf '%s\n' "EcInt sub borrow should use clang builtin on supported non-x86 builds"
	exit 1
fi
