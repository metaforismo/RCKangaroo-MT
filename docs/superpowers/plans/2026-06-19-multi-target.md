# Multi-Target Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a multi-target mode to RCKangaroo v3.1 that loads a file of public keys and assigns wild kangaroos to targets in one GPU run.

**Architecture:** Keep upstream single-target behavior intact. Add compact target storage on the host, a target-id array on the GPU, and target-aware collision/result handling on the host. Preserve the 48-byte GPU DP record by writing target id into an unused trailing word.

**Tech Stack:** C++17-compatible C++/CUDA, existing RCKangaroo host/GPU code, Makefile, simple shell-based helper test.

---

### Task 1: Target Loader

**Files:**
- Create: `TargetSet.h`
- Create: `TargetSet.cpp`
- Create: `tests/target_lines_sample.txt`
- Create: `tests/check_target_parser.sh`
- Modify: `Makefile`

- [ ] **Step 1: Write failing parser fixture**

Create `tests/target_lines_sample.txt` with one comment, one blank line, and two valid public keys.

- [ ] **Step 2: Write parser smoke script**

Create `tests/check_target_parser.sh` that verifies the fixture contains exactly two loadable target lines according to the line filtering rules.

- [ ] **Step 3: Implement `TargetSet`**

Add compact target storage, line filtering, public key parsing through `EcPoint::SetHexStr`, mapping by subtracting `start*G`, and accessors for target count and mapped points.

- [ ] **Step 4: Wire the helper script into the Makefile**

Add `make check-host` to run the parser smoke script without CUDA.

### Task 2: CLI And Host State

**Files:**
- Modify: `RCKangaroo.cpp`
- Modify: `README.md`
- Modify: `Makefile`

- [ ] **Step 1: Add CLI state**

Add `gTargetsFileName`, `gTargetSet`, `gMultiTargetMode`, and result metadata globals.

- [ ] **Step 2: Add `-targets` parsing**

Reject `-pubkey` plus `-targets`, require `-start`, `-range`, and `-dp`, and load targets before GPU initialization.

- [ ] **Step 3: Add multi-target main path**

Map the loaded targets, call the new multi-target solve path, and write target-aware result output.

- [ ] **Step 4: Document usage**

Update README command-line parameters and add a multi-target example.

### Task 3: GPU Target IDs And Start Points

**Files:**
- Modify: `defs.h`
- Modify: `GpuKang.h`
- Modify: `GpuKang.cpp`
- Modify: `RCGpuCore.cu`

- [ ] **Step 1: Extend kernel params**

Add `u32* TargetIds` and `bool IsMultiTarget` to `TKparams`.

- [ ] **Step 2: Allocate and populate target IDs**

Allocate a device `TargetIds` array. Tame kangaroos use target id `0`; wild kangaroos receive round-robin target ids.

- [ ] **Step 3: Generate target-aware wild offsets**

For each wild kangaroo, use its assigned target's mapped point to build SOTA `PntA` or `PntB` before `KernelGen`.

- [ ] **Step 4: Emit target id with DPs**

In `BuildDP`, copy `TargetIds[kang_ind]` into the existing trailing GPU DP word.

### Task 4: Host Collision And Results

**Files:**
- Modify: `RCKangaroo.cpp`
- Modify: `utils.cpp`

- [ ] **Step 1: Extend DB records**

Store a `target_id` field in host DB records and increase internal DB record storage size accordingly.

- [ ] **Step 2: Verify collisions against the right target**

Pass the matched wild target's mapped point into `Collision_SOTA`. Record the solved target id and private key when verification succeeds.

- [ ] **Step 3: Write multi-target result output**

Append target index, target coordinates, and private key to `RESULTS.TXT`.

### Task 5: Verification And Publish

**Files:**
- Modify as needed from previous tasks

- [ ] **Step 1: Run host checks**

Run `make check-host`.

- [ ] **Step 2: Attempt native build**

Run `make` and record whether CUDA is available in the environment.

- [ ] **Step 3: Commit changes**

Commit with message `feat: add multi-target mode`.

- [ ] **Step 4: Publish**

Create GitHub repo `RCKangaroo-MT` when GitHub authentication is available, set it as origin, and push this branch as `main`.
