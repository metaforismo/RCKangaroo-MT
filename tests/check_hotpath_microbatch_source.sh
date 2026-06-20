#!/bin/sh
set -eu

for marker in \
	EcIntMulModPFinalSubtractMode \
	JacobianBatchTailUpdateMode \
	KangarooDpClearMode \
	KangarooDpCapacityMode
do
	if ! grep -q "$marker" Ec.h macos/RCKMac.cpp; then
		printf 'missing hotpath microbatch marker: %s\n' "$marker"
		exit 1
	fi
done

if grep -q "while (data\\[4\\])" Ec.cpp; then
	printf '%s\n' "EcInt MulModP final subtract should be a single conditional subtract"
	exit 1
fi

if ! grep -q "overflow.empty()" macos/RCKMac.cpp; then
	printf '%s\n' "Kangaroo DP bucket clear should guard empty overflow vectors"
	exit 1
fi

if ! grep -q "reserve + (reserve / 2)" macos/RCKMac.cpp; then
	printf '%s\n' "Kangaroo DP table should target a denser 2/3 max load"
	exit 1
fi

if ! grep -q "i ? FieldMul(acc, prefixes\\[i\\]) : acc" macos/RCKMac.cpp; then
	printf '%s\n' "Jacobian batch affine should skip the final prefix multiply"
	exit 1
fi
