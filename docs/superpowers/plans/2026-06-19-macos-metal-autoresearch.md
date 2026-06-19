# macOS Metal Autoresearch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working macOS-native foundation for RCKangaroo-MT with CPU correctness, Metal smoke execution, benchmark output, and an autoresearch harness that can search for measured optimizations.

**Architecture:** Keep the CUDA solver intact and add a separate macOS toolchain under `macos/`. The first production-quality milestone is a host/CPU oracle plus benchmark and autoresearch runner; Metal starts with a compile/run smoke kernel and then becomes the next optimization target.

**Tech Stack:** C++17, Objective-C++ for Metal interop, Apple Metal framework, existing secp256k1 `Ec.cpp`, POSIX shell tests, Python 3 standard library.

---

## File Structure

- Modify `utils.h` and `utils.cpp`: make arithmetic helpers portable on Apple Silicon without breaking x86/CUDA builds.
- Create `tests/ec_vector_check.cpp`: host-only secp256k1 vector tests.
- Create `tests/check_portable_ec.sh`: compiles/runs host vector tests.
- Create `macos/RCKMac.h`: tiny CPU solver and benchmark API.
- Create `macos/RCKMac.cpp`: CPU oracle implementation, tiny single/multi-target solves, JSON benchmark output.
- Create `macos/MetalSmoke.mm`: minimal Metal device/kernel smoke test using runtime shader source.
- Create `macos/rck_macos.cpp`: macOS CLI for `selftest`, `solve-small`, `bench`, and `metal-smoke`.
- Modify `Makefile`: add `macos-build`, `macos-check`, and `macos-bench`.
- Create `autoresearch/program.md`: rules for optimization agents.
- Create `autoresearch/runner.py`: fixed-budget runner that executes checks/benchmarks and logs keep/discard metrics.
- Create `autoresearch/experiments/baseline.json`: immutable baseline config.
- Create `autoresearch/README.md`: usage documentation.
- Update `README.md`, `README.it.md`, `macos/README.md`, and `macos/README.it.md`: backend matrix and commands.

## Task 1: Portable Host Arithmetic

**Files:**
- Modify: `utils.h`
- Modify: `utils.cpp`
- Create: `tests/ec_vector_check.cpp`
- Create: `tests/check_portable_ec.sh`
- Modify: `Makefile`

- [ ] **Step 1: Write failing host vector test**

Create `tests/ec_vector_check.cpp` with a `main()` that:

```cpp
#include <stdio.h>
#include "Ec.h"

static int fail(const char* msg)
{
	printf("%s\n", msg);
	return 1;
}

int main()
{
	InitEc();
	EcInt one, two, three;
	one.Set(1);
	two.Set(2);
	three.Set(3);
	EcPoint g = Ec::MultiplyG(one);
	EcPoint two_g = Ec::MultiplyG(two);
	EcPoint two_g_by_double = Ec::DoublePoint(g);
	EcPoint three_g = Ec::MultiplyG(three);
	EcPoint three_g_by_add = Ec::AddPoints(two_g, g);
	if (!two_g.IsEqual(two_g_by_double))
		return fail("2G mismatch");
	if (!three_g.IsEqual(three_g_by_add))
		return fail("3G mismatch");
	DeInitEc();
	printf("ec vectors ok\n");
	return 0;
}
```

Create `tests/check_portable_ec.sh`:

```sh
#!/bin/sh
set -eu
out="${TMPDIR:-/tmp}/rck_ec_vector_check.$$"
cxx="${CXX:-clang++}"
"$cxx" -std=c++17 -O2 -I. tests/ec_vector_check.cpp Ec.cpp utils.cpp -o "$out"
"$out"
rm -f "$out"
```

- [ ] **Step 2: Verify RED**

Run: `sh tests/check_portable_ec.sh`

Expected on Apple Silicon before the fix: compile failure caused by non-portable x86 intrinsic/asm helpers.

- [ ] **Step 3: Add portable helpers**

In `utils.h`, include `<x86intrin.h>` only on x86/x86_64. On other non-Windows platforms, define inline `_addcarry_u64` and `_subborrow_u64` using `__uint128_t`.

In `utils.cpp`, keep the current x86 inline assembly for x86/x86_64 and add portable `__shiftright128`/`__shiftleft128` implementations for Apple Silicon.

- [ ] **Step 4: Verify GREEN**

Run: `sh tests/check_portable_ec.sh`

Expected: prints `ec vectors ok`.

- [ ] **Step 5: Wire into Makefile**

Add `check-portable-ec` and make `check-host` run both target parser and portable EC checks.

- [ ] **Step 6: Commit**

```sh
git add utils.h utils.cpp tests/ec_vector_check.cpp tests/check_portable_ec.sh Makefile
git commit -m "test: add portable ec host checks"
```

## Task 2: macOS CPU Backend and CLI

**Files:**
- Create: `macos/RCKMac.h`
- Create: `macos/RCKMac.cpp`
- Create: `macos/rck_macos.cpp`
- Modify: `Makefile`

- [ ] **Step 1: Write failing macOS CLI build target**

Add Makefile targets:

```make
MACOS_TARGET := macos/rck_macos
MACOS_SRC := macos/rck_macos.cpp macos/RCKMac.cpp Ec.cpp utils.cpp TargetSet.cpp

macos-build:
	$(CXX) -std=c++17 -O2 -I. $(MACOS_SRC) -o $(MACOS_TARGET)

macos-check: check-host macos-build
	./$(MACOS_TARGET) selftest
```

Run: `make macos-check`

Expected: fails because `macos/rck_macos.cpp` and `macos/RCKMac.cpp` do not exist.

- [ ] **Step 2: Implement CPU oracle API**

Create `macos/RCKMac.h` with:

```cpp
#pragma once

#include <string>
#include <vector>
#include "Ec.h"

struct RCKSmallSolveResult
{
	bool found;
	unsigned long long private_key;
	unsigned int target_index;
};

bool RCKSelfTest(std::string& error);
RCKSmallSolveResult RCKSolveSmallSingle(EcPoint target, unsigned long long start, unsigned int range_bits);
RCKSmallSolveResult RCKSolveSmallMulti(const std::vector<EcPoint>& targets, unsigned long long start, unsigned int range_bits);
std::string RCKBenchJson(unsigned int iterations);
```

Implement `RCKMac.cpp` with brute-force tiny-range solving using `Ec::MultiplyG`, accepting only `range_bits <= 24` for safety.

- [ ] **Step 3: Implement CLI**

Create `macos/rck_macos.cpp` commands:

```text
selftest
solve-small --range N --start HEX --pubkey PUBKEY
bench --iterations N
```

`selftest` must verify `2G == DoublePoint(G)`, `3G == 2G+G`, and a tiny private key solve for `k=7`.

- [ ] **Step 4: Verify GREEN**

Run: `make macos-check`

Expected: `selftest ok`.

- [ ] **Step 5: Verify tiny solve**

Run:

```sh
./macos/rck_macos solve-small --range 8 --start 0 --pubkey 025cbdf0646e5db4eaa398f365f2ea7a0e3d419b7e0330e39c640b3d9e9a9b7e31
```

Expected: prints a found private key for a tiny test vector generated by the tool or test.

- [ ] **Step 6: Commit**

```sh
git add macos/RCKMac.h macos/RCKMac.cpp macos/rck_macos.cpp Makefile
git commit -m "feat: add macos cpu oracle cli"
```

## Task 3: Benchmark JSON and Autoresearch Runner

**Files:**
- Create: `autoresearch/README.md`
- Create: `autoresearch/program.md`
- Create: `autoresearch/runner.py`
- Create: `autoresearch/experiments/baseline.json`
- Modify: `Makefile`

- [ ] **Step 1: Write failing runner invocation**

Add `macos-bench` target:

```make
macos-bench: macos-build
	./$(MACOS_TARGET) bench --iterations 64
```

Run:

```sh
python3 autoresearch/runner.py --experiment baseline --budget-sec 5
```

Expected: fails because `autoresearch/runner.py` does not exist.

- [ ] **Step 2: Implement benchmark command**

Make `./macos/rck_macos bench --iterations 64` print one JSON object with:

```json
{"backend":"cpu","operation":"multiply_g","iterations":64,"seconds":0.0,"ops_per_sec":0.0,"correctness":true}
```

Use measured wall time and real ops/sec.

- [ ] **Step 3: Implement runner**

`runner.py` must:

1. load `autoresearch/experiments/<name>.json`;
2. run `make macos-check`;
3. run `make macos-bench`;
4. parse the benchmark JSON;
5. append `autoresearch/results.tsv`;
6. append `autoresearch/benchmarks.jsonl`;
7. exit non-zero if correctness fails.

- [ ] **Step 4: Verify GREEN**

Run:

```sh
make macos-bench
python3 autoresearch/runner.py --experiment baseline --budget-sec 5
```

Expected: JSON benchmark prints and TSV/JSONL rows are created.

- [ ] **Step 5: Commit**

```sh
git add autoresearch Makefile macos/RCKMac.cpp macos/rck_macos.cpp
git commit -m "feat: add autoresearch benchmark runner"
```

## Task 4: Metal Smoke Backend

**Files:**
- Create: `macos/MetalSmoke.h`
- Create: `macos/MetalSmoke.mm`
- Modify: `macos/rck_macos.cpp`
- Modify: `Makefile`

- [ ] **Step 1: Write failing Metal command**

Add `metal-smoke` to `macos/rck_macos.cpp` usage and add Makefile Objective-C++ build flags:

```make
MACOS_SRC := macos/rck_macos.cpp macos/RCKMac.cpp macos/MetalSmoke.mm Ec.cpp utils.cpp TargetSet.cpp
MACOS_LDFLAGS := -framework Foundation -framework Metal
```

Run: `./macos/rck_macos metal-smoke`

Expected: fails because `MetalSmoke.mm` does not exist.

- [ ] **Step 2: Implement Metal smoke**

`MetalSmoke.mm` should:

1. create `MTLCreateSystemDefaultDevice()`;
2. compile a runtime Metal shader that increments four `uint` values;
3. run one compute dispatch;
4. verify output is `[2, 3, 4, 5]`;
5. return an error string on failure.

- [ ] **Step 3: Verify GREEN**

Run:

```sh
make macos-check
./macos/rck_macos metal-smoke
```

Expected: `metal smoke ok`.

- [ ] **Step 4: Commit**

```sh
git add macos/MetalSmoke.h macos/MetalSmoke.mm macos/rck_macos.cpp Makefile
git commit -m "feat: add metal smoke backend"
```

## Task 5: Documentation and Final Verification

**Files:**
- Modify: `README.md`
- Modify: `README.it.md`
- Modify: `macos/README.md`
- Modify: `macos/README.it.md`

- [ ] **Step 1: Document backend matrix**

Document:

```text
CUDA: full solver
macOS CPU: correctness and tiny-range oracle
macOS Metal: smoke backend now, arithmetic kernels next
autoresearch: fixed-gate benchmark runner
```

- [ ] **Step 2: Run full verification**

Run:

```sh
make check-host
make macos-check
make macos-bench
python3 autoresearch/runner.py --experiment baseline --budget-sec 5
git diff --check
```

- [ ] **Step 3: Commit**

```sh
git add README.md README.it.md macos/README.md macos/README.it.md
git commit -m "docs: document macos autoresearch workflow"
```

- [ ] **Step 4: Push branch**

```sh
git push -u origin feature/macos-metal-autoresearch
```
