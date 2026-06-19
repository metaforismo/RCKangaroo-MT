# macOS Metal Autoresearch Design

## Goal

Build a real macOS-native research and execution path for RCKangaroo-MT:

1. make the project build and run useful correctness/benchmark workflows on Apple Silicon without CUDA;
2. add a Metal backend incrementally for secp256k1 and kangaroo work;
3. add an autoresearch loop that searches for measured improvements in math, memory layout, scheduling, and parameters;
4. keep CUDA/Linux behavior intact.

The autoresearch loop is not an end in itself. It exists to discover, validate, and preserve optimizations that improve a defined metric without weakening correctness.

## Current State

The repository is a fork of RCKangaroo v3.1 with experimental multi-target support:

- `-targets` loads many secp256k1 public keys and maps them by subtracting `-start`.
- GPU distinguished points carry a `target_id`.
- Collision verification checks the matching target.
- `macos/prepare_targets.py` validates and normalizes target files on macOS.

The solver still requires CUDA because `RCKangaroo.cpp`, `GpuKang.cpp`, and `RCGpuCore.cu` include CUDA headers and execute CUDA kernels directly. On the local Mac, Xcode/Metal tools are available, but CUDA headers are not.

## Non-Goals

- Do not remove or degrade the CUDA backend.
- Do not claim Apple GPU parity with RTX 4090 unless measured on the same problem class.
- Do not use probabilistic shortcuts that can produce unverifiable private keys.
- Do not change evaluation rules during an autoresearch run.
- Do not make MLX/PyTorch the production solver backend for bigint elliptic-curve kernels.

MLX and the autoresearch forks are inspiration for research protocol and Apple Silicon workflow, not a direct replacement for low-level secp256k1 arithmetic.

## Architecture

### 1. Backend Boundary

Introduce a backend interface so the CLI can choose an execution engine:

- `cuda`: existing CUDA solver path.
- `cpu`: portable macOS/Linux correctness and benchmark backend.
- `metal`: Apple Silicon GPU backend, added in stages.

The first backend boundary should be conservative. It can initially expose only:

- environment detection;
- build/runtime capability reporting;
- small-range correctness execution;
- microbenchmarks.

The full kangaroo loop can remain CUDA-only until CPU/Metal primitives are verified.

### 2. Host-Only Core

Extract shared host logic away from CUDA includes:

- CLI parsing;
- target loading;
- secp256k1 point parsing;
- small test-vector generation;
- result verification;
- benchmark result serialization.

This allows macOS builds to compile the host code even when CUDA is absent.

### 3. CPU Baseline

Add a CPU backend for correctness, not ultimate speed. It should solve only intentionally tiny ranges in tests and benchmarks.

Responsibilities:

- run deterministic small-range kangaroo or fallback brute-force checks;
- validate collision math;
- validate target mapping;
- produce baseline measurements for secp256k1 operations.

The CPU backend gives the Metal backend an oracle and gives autoresearch a safe correctness gate.

### 4. Metal Backend

Build Metal incrementally:

1. compile and run a trivial kernel from the repo;
2. implement field arithmetic microkernels over secp256k1 prime field limbs;
3. validate point addition/doubling kernels against CPU vectors;
4. validate jump-step kernels against CPU vectors;
5. implement distinguished-point emission;
6. integrate target ids and multi-target scheduling;
7. run bounded small-range solves.

Metal should use explicit benchmark names and result files so every experiment is comparable.

### 5. Autoresearch Harness

Add an `autoresearch/` folder inspired by the fixed-budget loop in `karpathy/autoresearch` and the Apple Silicon framing in `trevin-creator/autoresearch-mlx`.

The harness should include:

- `program.md`: instructions for agents running experiments;
- `runner.py`: executes one fixed-budget experiment and records results;
- `experiments/`: candidate configuration files or patches;
- `results.tsv`: tracked or intentionally untracked according to mode;
- `benchmarks.jsonl`: append-only machine-readable benchmark history;
- `README.md`: how to start a local research run.

The mutable surface for autonomous agents must be small. Early runs should mutate only config files and isolated experiment modules, not the whole solver.

## Research Objective

Autoresearch should optimize a score, not vibes.

Primary score:

```text
score = correctness_passed ? measured_work_per_second_adjusted : 0
```

Where measured work can be:

- field multiplications/sec;
- point additions/sec;
- kangaroo steps/sec;
- distinguished points/sec;
- solved tiny-range cases per fixed budget.

Secondary metrics:

- memory used;
- compile time;
- energy/time proxy when available;
- code complexity delta;
- crash rate.

An experiment is kept only if it passes correctness and improves the chosen metric by a margin above noise.

## Candidate Search Areas

The harness should allow targeted experiments in these areas:

- limb representation: 4x64, 5x52, 8x32, or mixed carry strategies;
- modular reduction schedule for secp256k1 prime `2^256 - 2^32 - 977`;
- point coordinate system: affine, Jacobian, mixed affine/Jacobian;
- jump table size and distribution;
- distinguished-point bit threshold;
- tame/wild ratio;
- multi-target wild distribution;
- DP record layout and memory bandwidth;
- Metal threadgroup sizing and occupancy;
- batching strategy for target start points;
- CPU precomputation versus GPU generation;
- Bloom/filter prechecks before DB insertion;
- database prefix length and record layout.

## Correctness Gates

Every backend and experiment must pass:

- public key parser tests;
- target loader tests;
- secp256k1 field arithmetic vectors;
- point addition/doubling vectors;
- `k*G` vectors for small known `k`;
- single-target tiny-range solve;
- multi-target tiny-range solve with at least one decoy target;
- result verification by recomputing `private_key * G`.

Autoresearch cannot keep a result that bypasses these gates.

## Benchmark Gates

Benchmarks must be repeatable from a clean checkout:

```sh
make check-host
make macos-check
make macos-bench
python3 autoresearch/runner.py --experiment baseline --budget-sec 60
```

Expected first milestone:

- no CUDA headers required for macOS host checks;
- CPU correctness backend runs on Apple Silicon;
- benchmark files are generated;
- autoresearch runner records baseline rows.

Expected later milestone:

- Metal microkernels compile and pass vector tests;
- Metal point/jump microbenchmarks beat CPU baseline;
- bounded Metal kangaroo solve passes tiny-range tests.

## Data Flow

```text
CLI/config
  -> target loader / test vector loader
  -> backend selection
  -> CPU oracle and/or Metal/CUDA execution
  -> DP/collision/result verification
  -> benchmark metrics
  -> autoresearch keep/discard decision
```

## Error Handling

- Missing CUDA on macOS should not prevent host checks.
- Missing Metal compiler should skip Metal tests with a clear message.
- Incorrect vector output fails immediately.
- Autoresearch crashes are logged as `crash` with metric `0`.
- Benchmark runs should include machine and backend metadata.

## Documentation

Add or update:

- root README backend matrix;
- Italian README backend matrix;
- `macos/README.md` and `macos/README.it.md` for CPU/Metal build commands;
- `autoresearch/README.md` for experiment workflow;
- `autoresearch/program.md` for agent rules.

## Implementation Strategy

Implement in phases:

1. split host-only code from CUDA-only code;
2. add macOS CPU build and tests;
3. add benchmark/result schema;
4. add autoresearch harness with baseline-only runs;
5. add Metal build skeleton and trivial kernel;
6. add secp256k1 Metal arithmetic vectors;
7. add point/jump kernels;
8. integrate tiny-range solves;
9. open the autoresearch search space gradually.

This makes the system useful at every stage and prevents speculative Metal work from breaking the existing CUDA solver.

## Open Questions Resolved

- Use MLX directly for the solver? No. MLX is useful as workflow inspiration, but bigint elliptic-curve arithmetic should be C++/Metal.
- Use PyTorch/MPS directly? No. It is too high-level for this workload.
- Make autoresearch mutate all source files? Not initially. It starts with configs and isolated experiment modules, then expands after tests and benchmarks are reliable.
- Chase breakthrough ideas? Yes, but under fixed correctness and benchmark rules.
