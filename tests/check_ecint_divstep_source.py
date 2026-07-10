#!/usr/bin/env python3
from pathlib import Path


source = Path("Ec.cpp").read_text(encoding="utf-8")
start = source.index("static inline u64 I64Bits")
end = source.index("void EcInt::InvModP()", start)
divstep = source[start:end]

required = (
    "I64WrapNeg",
    "I64WrapAdd",
    "I64WrapMul",
    "I64WrapShiftLeft",
    "I64ArithmeticShiftRight",
    "val = I64ArithmeticShiftRight(val, index)",
    "matrix[0] = I64WrapShiftLeft(matrix[0], index)",
    "I64WrapMul(I64WrapNeg(modp), val)",
)
for marker in required:
    if marker not in divstep:
        raise SystemExit("missing defined-wrap divstep marker: " + marker)

for forbidden in (
    "-modp * val",
    "val += (modp * mul)",
    "matrix[0] <<= index",
    "matrix[1] <<= index",
):
    if forbidden in divstep:
        raise SystemExit("signed-overflow divstep expression returned: " + forbidden)

print("ecint divstep defined-wrap source ok")
