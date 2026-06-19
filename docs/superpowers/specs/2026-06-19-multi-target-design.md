# RCKangaroo-MT Multi-Target Design

## Goal

Build a fork of RCKangaroo v3.1 that can load many public keys from a target file and run one shared GPU kangaroo job where wild kangaroos are assigned to target records. The single-target `-pubkey` mode remains compatible with upstream v3.1.

## User Interface

Add a new command-line option:

```text
-targets filename
```

The file contains one compressed or uncompressed secp256k1 public key per line. Blank lines and lines starting with `#` are ignored. `-targets` requires the same `-start`, `-range`, and `-dp` options as `-pubkey`. `-pubkey` and `-targets` are mutually exclusive.

## Architecture

The host loads every target public key, subtracts the configured start offset once, and stores the mapped target point in a compact in-memory vector. During GPU start-up, tame kangaroos remain target-independent. Wild kangaroos are assigned target indexes and start from each target's SOTA symmetric offsets, so one kernel run can work on many targets at the same time.

The GPU carries a `TargetIds` array parallel to `Kangs`. Distinguished points emitted by wild kangaroos include their target index in unused bytes of the existing 48-byte GPU DP record. The host DB record stores the target index for wild DPs, enabling collision verification to compute the private key for the correct target.

## Result Handling

When a target is solved, the program stops the current run and writes a result to `RESULTS.TXT` containing:

- target index
- private key
- target X and Y

Single-target output remains unchanged.

## Constraints

This first implementation prioritizes correctness, readable fork structure, and buildability over optimal million-target scheduling. Large target files are supported by compact point storage, but every active wild kangaroo is assigned one target at kernel start. Future work can add periodic target reassignment or a fully target-table-driven walk strategy.

## Testing

Add a small host-side test for target file parsing behavior that does not require CUDA. Build verification should use `make` on NVIDIA/CUDA systems. On non-CUDA macOS, syntax/build verification may be limited to non-CUDA helper tests and static inspection.
