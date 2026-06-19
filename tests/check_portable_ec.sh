#!/bin/sh
set -eu

out="${TMPDIR:-/tmp}/rck_ec_vector_check.$$"
cxx="${CXX:-clang++}"

"$cxx" -std=c++17 -O2 -I. tests/ec_vector_check.cpp Ec.cpp utils.cpp -o "$out"
"$out"
rm -f "$out"
