#!/usr/bin/env python3
from pathlib import Path


source = Path("macos/MetalFieldKernels.h").read_text()
if "struct AffineJumpValue" not in source:
    raise SystemExit("missing affine jump struct row type")

start = source.index("kernel void jacobian_affine_walk_jump_table_steps8_dp4")
end = source.index("}\n)RCK_METAL", start)
dp4_body = source[start:end]

if "constant AffineJumpValue* q_xy [[buffer(1)]]" not in dp4_body:
    raise SystemExit("dp4 kernel must view q_xy as affine jump rows")
if "uint q_base = jump_index << 3" in dp4_body:
    raise SystemExit("dp4 q struct row path must not compute q_base")
if "q_xy[q_base +" in dp4_body:
    raise SystemExit("dp4 q struct row path still uses scalar q_base indexing")

for marker in (
    "q_xy[jump_index].x0",
    "q_xy[jump_index].x3",
    "q_xy[jump_index].y0",
    "q_xy[jump_index].y3",
):
    if marker not in dp4_body:
        raise SystemExit("missing dp4 q struct row marker: " + marker)

print("metal dp4 q struct row source ok")
