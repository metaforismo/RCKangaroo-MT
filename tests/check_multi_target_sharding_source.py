#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
gpu_h = (root / "GpuKang.h").read_text()
gpu_cpp = (root / "GpuKang.cpp").read_text()
gpu_core = (root / "RCGpuCore.cu").read_text()
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
    ("wild-only random distance support", "GenerateRndDistances(bool wild_only)" in gpu_cpp),
    ("prepare receives wild1 total", "_Wild1TargetTotal" in gpu_cpp),
    ("prepare receives wild2 total", "_Wild2TargetTotal" in gpu_cpp),
    ("prepare receives target cycle rounds", "_TargetCycleRounds" in gpu_cpp),
    ("start uses active-wild mapper", "TTargetSet::MapActiveWildTargetId(active_index, target_total, target_cnt)" in gpu_cpp),
    ("start uses cycled active-wild mapper", "TTargetSet::MapCycledActiveWildTargetId(active_index, target_total, target_cnt, target_cycle_index)" in gpu_cpp),
    ("initial start resets all kangaroos", "ResetStartPoints(0, false)" in gpu_cpp),
    ("cycle reset preserves tame walks", "ResetStartPoints(TargetCycleIndex + 1, true)" in gpu_cpp),
    ("cycle reset copies wild1 only", "cudaMemcpy(Kparams.Kangs + (u64)tame_cnt * 12" in gpu_cpp),
    ("cycle reset copies wild2 only", "cudaMemcpy(Kparams.Kangs + (u64)wild2_start * 12" in gpu_cpp),
    ("kernel gen accepts wild-only", "KernelGen(const TKparams Kparams, bool wild_only)" in gpu_core),
    ("kernel gen skips tame in wild-only mode", "wild_only && (kang_ind < Kparams.KangCnt / 3)" in gpu_core),
    ("host passes preserve_tame to kernel gen", "CallGpuKernelGen(Kparams, preserve_tame)" in gpu_cpp),
    ("kernel launch receives wild-only", "KernelGen << < Kparams.BlockCnt, Kparams.BlockSize, 0 >> > (Kparams, wild_only)" in gpu_core),
    ("loop table loads are per-thread", "+ i * BLOCK_SIZE + THREAD_X" in gpu_core and "+ (i + MD_LEN) * BLOCK_SIZE + THREAD_X" in gpu_core),
    ("loop table stores are per-thread", "+ ind * BLOCK_SIZE + THREAD_X" in gpu_core and "+ (ind + MD_LEN) * BLOCK_SIZE + THREAD_X" in gpu_core),
    ("loop table never uses block index as thread lane", "LoopTable[MD_LEN * BLOCK_SIZE * PNT_GROUP_CNT * BLOCK_X + 2 * MD_LEN * BLOCK_SIZE * gr_ind2 + i * BLOCK_SIZE + BLOCK_X]" not in gpu_core and "+ (i + MD_LEN) * BLOCK_SIZE + BLOCK_X" not in gpu_core and "+ ind * BLOCK_SIZE + BLOCK_X" not in gpu_core and "+ (ind + MD_LEN) * BLOCK_SIZE + BLOCK_X" not in gpu_core),
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
