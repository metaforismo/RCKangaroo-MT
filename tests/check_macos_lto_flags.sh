#!/bin/sh
set -eu

output="$(make -Bn macos/rck_macos 2>&1)"

case "$output" in
	*"-flto=thin"*)
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "macos/rck_macos does not enable ThinLTO by default"
		exit 1
		;;
esac

case "$(make -pRrq macos/rck_macos 2>/dev/null)" in
	*"macos/MetalFieldKernels.h"*)
		exit 0
		;;
	*)
		printf '%s\n' "macos/rck_macos does not depend on MetalFieldKernels.h"
		exit 1
		;;
esac
