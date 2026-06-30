#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
gpu_h = (root / "GpuKang.h").read_text()
gpu_cpp = (root / "GpuKang.cpp").read_text()
main_cpp = (root / "RCKangaroo.cpp").read_text()
target_h = (root / "TargetSet.h").read_text()
target_cpp = (root / "TargetSet.cpp").read_text()

checks = [
    ("target mapper declared", "MapActiveWildTargetId" in target_h),
    ("target cycle mapper declared", "MapCycledActiveWildTargetId" in target_h),
    ("coverage cycle helper declared", "CoverageCycleCount" in target_h),
    ("target cycle mapper implemented", "cycle_offset + active_index" in target_cpp),
    ("wild1 offset field", "Wild1TargetOffset" in gpu_h),
    ("wild2 offset field", "Wild2TargetOffset" in gpu_h),
    ("target cycle rounds field", "TargetCycleRounds" in gpu_h),
    ("reset start points helper", "ResetStartPoints" in gpu_h),
    ("prepare receives wild1 total", "_Wild1TargetTotal" in gpu_cpp),
    ("prepare receives wild2 total", "_Wild2TargetTotal" in gpu_cpp),
    ("prepare receives target cycle rounds", "_TargetCycleRounds" in gpu_cpp),
    ("start uses active-wild mapper", "TTargetSet::MapActiveWildTargetId(active_index, target_total, target_cnt)" in gpu_cpp),
    ("start uses cycled active-wild mapper", "TTargetSet::MapCycledActiveWildTargetId(active_index, target_total, target_cnt, target_cycle_index)" in gpu_cpp),
    ("execute can reset start points", "ResetStartPoints(TargetCycleIndex + 1)" in gpu_cpp),
    ("solvepoint computes wild1 offsets", "wild1_offsets[i] = total_wild1" in main_cpp),
    ("solvepoint computes wild2 offsets", "wild2_offsets[i] = total_wild2" in main_cpp),
    ("solvepoint passes wild1 sharding", "wild1_offsets[i], total_wild1" in main_cpp),
    ("solvepoint passes wild2 sharding", "wild2_offsets[i], total_wild2" in main_cpp),
    ("solvepoint passes cycle rounds", "total_wild2, gTargetCycleRounds" in main_cpp),
    ("target cycle cli", "-target-cycle-rounds" in main_cpp),
    ("operator-visible coverage log", "Multi-target active shard coverage" in main_cpp),
    ("operator-visible cycling log", "Multi-target cycling" in main_cpp),
]

missing = [name for name, ok in checks if not ok]
if missing:
    raise SystemExit("multi-target sharding source check failed: " + ", ".join(missing))

print("multi-target sharding source ok")
