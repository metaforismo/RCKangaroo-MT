#!/bin/sh
set -eu

output="$(make -n macos-build 2>&1)"

case "$output" in
	*"-flto=thin"*)
		exit 0
		;;
	*)
		printf '%s\n' "$output"
		printf '%s\n' "macos-build does not enable ThinLTO by default"
		exit 1
		;;
esac
