#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
gpu_h = (root / "GpuKang.h").read_text()
gpu_cpp = (root / "GpuKang.cpp").read_text()
main_cpp = (root / "RCKangaroo.cpp").read_text()
target_h = (root / "TargetSet.h").read_text()

checks = [
    ("target mapper declared", "MapActiveWildTargetId" in target_h),
    ("wild1 offset field", "Wild1TargetOffset" in gpu_h),
    ("wild2 offset field", "Wild2TargetOffset" in gpu_h),
    ("prepare receives wild1 total", "_Wild1TargetTotal" in gpu_cpp),
    ("prepare receives wild2 total", "_Wild2TargetTotal" in gpu_cpp),
    ("start uses active-wild mapper", "TTargetSet::MapActiveWildTargetId(target_offset + group_ind, target_total, target_cnt)" in gpu_cpp),
    ("solvepoint computes wild1 offsets", "wild1_offsets[i] = total_wild1" in main_cpp),
    ("solvepoint computes wild2 offsets", "wild2_offsets[i] = total_wild2" in main_cpp),
    ("solvepoint passes wild1 sharding", "wild1_offsets[i], total_wild1" in main_cpp),
    ("solvepoint passes wild2 sharding", "wild2_offsets[i], total_wild2" in main_cpp),
    ("operator-visible coverage log", "Multi-target active shard coverage" in main_cpp),
]

missing = [name for name, ok in checks if not ok]
if missing:
    raise SystemExit("multi-target sharding source check failed: " + ", ".join(missing))

print("multi-target sharding source ok")
