from pathlib import Path


metal = Path("macos/MetalField.mm").read_text()
makefile = Path("Makefile").read_text()
gitignore = Path(".gitignore").read_text()
meta_tool = Path("tools/write_metal_library_meta.py").read_text()

required_metal_markers = [
    "RCK_METAL_DISABLE_PRECOMPILED",
    "RCK_METAL_USE_PRECOMPILED",
    "RCK_METAL_FIELD_LIB",
    "FieldSourceFnv1a64",
    "MetalLibraryMetaMatchesSource",
    "if (!explicit_precompiled && !MetalLibraryMetaMatchesSource(path))",
    "FieldLibraryCandidatePaths",
    "newLibraryWithURL:ns_url",
    "return [device newLibraryWithSource:FieldSource() options:nil error:ns_error];",
    "LoadFieldLibrary(device, &ns_error)",
]

for marker in required_metal_markers:
    if marker not in metal:
        raise SystemExit(f"missing precompiled Metal library marker: {marker}")

if metal.count("newLibraryWithSource:FieldSource()") != 1:
    raise SystemExit("Metal source compilation should exist only inside LoadFieldLibrary fallback")

required_makefile_markers = [
    "MACOS_METALLIB := macos/rck_macos.metallib",
    "MACOS_METALLIB_META := macos/rck_macos.metallib.meta",
    "MACOS_METAL_FLAGS ?= -finline-functions",
    "tools/extract_metal_kernels.py",
    "tools/write_metal_library_meta.py",
    "$(MACOS_METALLIB_META)",
    "xcrun -sdk macosx metal $(MACOS_METAL_FLAGS) -c",
    "xcrun -sdk macosx metallib",
    "macos-build: $(MACOS_TARGET) $(MACOS_METALLIB)",
]

for marker in required_makefile_markers:
    if marker not in makefile:
        raise SystemExit(f"missing precompiled Metal build marker: {marker}")

required_meta_tool_markers = [
    "FNV64_OFFSET",
    "source_fnv64=0x",
    "metal_flags=",
]

for marker in required_meta_tool_markers:
    if marker not in meta_tool:
        raise SystemExit(f"missing Metal library metadata marker: {marker}")

if (
    "/macos/rck_macos.metallib" not in gitignore
    or "/macos/rck_macos.metallib.meta" not in gitignore
    or "build/" not in gitignore
):
    raise SystemExit("generated Metal library artifacts should stay untracked")

print("metal precompiled library source ok")
