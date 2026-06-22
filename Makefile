CUDA_PATH ?= /usr/local/cuda-12.0
CC := g++
NVCC := $(CUDA_PATH)/bin/nvcc

.PHONY: all clean check-host check-portable-ec check-quality-gates check-autoresearch check-benchforge-rckmetal macos-lto-flags-check macos-jump-index-source-check macos-ecint-carry-source-check macos-hotpath-microbatch-source-check macos-affine-z-check-source-check macos-affine-inplace-field-source-check macos-affine-reverse-loop-source-check macos-metal-dp4-uchar-infinity-source-check macos-metal-dp4-q-struct-row-source-check macos-metal-dynamic-jump-walk-source-check macos-metal-dynamic-compact-dp-source-check macos-metal-dynamic-dp-stream-source-check macos-metal-dynamic-dp-stream-mask-source-check macos-metal-dynamic-dp-stream-inplace-source-check macos-metal-dynamic-dp-count-source-check macos-build macos-check macos-bench macos-point-bench macos-jacobian-point-bench macos-jacobian-batch-affine-bench macos-jacobian-batch-affine-bench-run macos-jacobian-walk-bench macos-jacobian-kangaroo-small-test macos-jacobian-kangaroo-small-bench macos-jacobian-kangaroo-small-bench-run macos-jacobian-kangaroo-small-bench-test macos-jacobian-kangaroo-multi-small-test macos-jacobian-kangaroo-multi-small-bench macos-jacobian-kangaroo-multi-small-bench-run macos-jacobian-kangaroo-multi16-small-bench macos-jacobian-kangaroo-multi16-small-bench-run macos-jacobian-kangaroo-multi-small-bench-test macos-cpu-field-test macos-cpu-field-bench macos-metal-kernels-check macos-metal-field-test macos-metal-field-bench macos-metal-field-mul-test macos-metal-field-mul-bench macos-metal-field-square-test macos-metal-field-square-bench macos-metal-field-square-mul-test macos-metal-field-square-mul-bench macos-metal-field-sub-test macos-metal-field-sub-bench macos-metal-field-double-test macos-metal-field-double-bench macos-metal-field-neg-test macos-metal-field-neg-bench macos-metal-field-mul4-test macos-metal-field-mul4-bench macos-metal-jacobian-add-test macos-metal-jacobian-add-bench macos-metal-jacobian-walk-test macos-metal-jacobian-walk-bench macos-metal-jacobian-jump-walk-test macos-metal-jacobian-jump-walk-bench macos-metal-jacobian-jump-walk-dp-bench macos-metal-jacobian-jump-walk-dp-stable-bench macos-metal-jacobian-jump-walk-dp-steps4-bench macos-metal-jacobian-dynamic-walk-test macos-metal-jacobian-dynamic-walk-bench macos-metal-jacobian-dynamic-walk-stable-bench macos-metal-jacobian-dynamic-compact-dp-test macos-metal-jacobian-dynamic-compact-dp-bench macos-metal-jacobian-dynamic-compact-dp-stable-bench macos-metal-jacobian-dynamic-dp-stream-test macos-metal-jacobian-dynamic-dp-stream-bench macos-metal-jacobian-dynamic-dp-stream-stable-bench macos-metal-jacobian-dynamic-dp-stream-dp8-bench macos-metal-jacobian-dynamic-dp-stream-dp8-stable-bench macos-metal-jacobian-dynamic-dp-stream-inplace-test macos-metal-jacobian-dynamic-dp-stream-inplace-bench macos-metal-jacobian-dynamic-dp-stream-inplace-stable-bench macos-metal-jacobian-dynamic-dp-stream-inplace-steps16-bench macos-metal-jacobian-dynamic-dp-stream-inplace-steps16-stable-bench macos-metal-jacobian-dynamic-dp-stream-inplace-steps32-bench macos-metal-jacobian-dynamic-dp-stream-inplace-steps32-stable-bench macos-metal-jacobian-dynamic-dp-stream-inplace-steps64-bench macos-metal-jacobian-dynamic-dp-stream-inplace-steps64-stable-bench macos-metal-jacobian-dynamic-dp-stream-inplace-steps128-bench macos-metal-jacobian-dynamic-dp-stream-inplace-steps128-stable-bench macos-metal-jacobian-dynamic-dp-stream-inplace-steps256-bench macos-metal-jacobian-dynamic-dp-stream-inplace-steps256-stable-bench macos-metal-jacobian-dynamic-dp-stream-dp12-bench macos-metal-jacobian-dynamic-dp-stream-dp12-stable-bench macos-metal-jacobian-dynamic-dp-count-dp8-bench macos-metal-jacobian-dynamic-dp-count-dp8-stable-bench benchforge-rckmetal-doctor benchforge-rckmetal-run benchforge-rckmetal-submit benchforge-rckmetal-leaderboard benchforge-rckmetal-report
.PHONY: macos-metal-dynamic-dp-stream-xyzz-source-check macos-metal-jacobian-dynamic-dp-stream-xyzz-test macos-metal-jacobian-dynamic-dp-stream-xyzz-steps256-bench macos-metal-jacobian-dynamic-dp-stream-xyzz-steps256-stable-bench macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-bench macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-stable-bench macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-saturated-bench macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-large-batch-bench

CCFLAGS := -O3 -I$(CUDA_PATH)/include
NVCCFLAGS := -O3 -gencode=arch=compute_89,code=compute_89 -gencode=arch=compute_86,code=compute_86 -gencode=arch=compute_75,code=compute_75 -gencode=arch=compute_61,code=compute_61
LDFLAGS := -L$(CUDA_PATH)/lib64 -lcudart -pthread

CPU_SRC := RCKangaroo.cpp GpuKang.cpp Ec.cpp utils.cpp TargetSet.cpp
GPU_SRC := RCGpuCore.cu

CPP_OBJECTS := $(CPU_SRC:.cpp=.o)
CU_OBJECTS := $(GPU_SRC:.cu=.o)

TARGET := rckangaroo
MACOS_TARGET := macos/rck_macos

all: $(TARGET)

$(TARGET): $(CPP_OBJECTS) $(CU_OBJECTS)
	$(CC) $(CCFLAGS) -o $@ $^ $(LDFLAGS)

%.o: %.cpp
	$(CC) $(CCFLAGS) -c $< -o $@

%.o: %.cu
	$(NVCC) $(NVCCFLAGS) -c $< -o $@

clean:
	rm -f $(CPP_OBJECTS) $(CU_OBJECTS)

check-host: check-portable-ec check-quality-gates check-benchforge-rckmetal
	sh tests/check_target_parser.sh

check-portable-ec:
	sh tests/check_portable_ec.sh

check-quality-gates:
	sh tests/check_quality_gates.sh

check-autoresearch:
	python3 tests/check_autoresearch_metric_passthrough.py
	python3 tests/check_metal_autoresearch_sample_runs.py

check-benchforge-rckmetal:
	sh tests/check_benchforge_rckmetal.sh

BENCHFORGE_RCKMETAL := node ./challenges/rckmetal/bin/rckmetal.js

benchforge-rckmetal-doctor:
	$(BENCHFORGE_RCKMETAL) doctor --run

benchforge-rckmetal-run:
	$(BENCHFORGE_RCKMETAL) run

benchforge-rckmetal-submit:
	$(BENCHFORGE_RCKMETAL) submit --verify --bundle-output .benchforge/latest.bundle.json --output .benchforge/verifier-result.json

benchforge-rckmetal-leaderboard:
	$(BENCHFORGE_RCKMETAL) leaderboard

benchforge-rckmetal-report:
	$(BENCHFORGE_RCKMETAL) export-site

MACOS_SRC := macos/rck_macos.cpp macos/RCKMac.cpp macos/CpuField.cpp macos/MetalSmoke.mm macos/MetalField.mm Ec.cpp utils.cpp TargetSet.cpp
MACOS_LTO_FLAGS ?= -flto=thin
MACOS_CXXFLAGS ?= -std=c++17 -O3 -I. $(MACOS_LTO_FLAGS)
MACOS_LDFLAGS := -framework Foundation -framework Metal

macos-lto-flags-check:
	@if [ "$(origin MACOS_CXXFLAGS)" = "command line" ] || [ "$(origin MACOS_LTO_FLAGS)" = "command line" ]; then \
		printf '%s\n' "macos ThinLTO flag check skipped for overridden build flags"; \
	else \
		sh tests/check_macos_lto_flags.sh; \
	fi

macos-jump-index-source-check:
	sh tests/check_jacobian_jump_index_source.sh

macos-ecint-carry-source-check:
	sh tests/check_ecint_carry_source.sh

macos-hotpath-microbatch-source-check:
	sh tests/check_hotpath_microbatch_source.sh

macos-affine-z-check-source-check:
	sh tests/check_affine_z_check_source.sh

macos-affine-inplace-field-source-check:
	sh tests/check_affine_inplace_field_source.sh

macos-affine-reverse-loop-source-check:
	sh tests/check_affine_reverse_loop_source.sh

macos-metal-dp4-uchar-infinity-source-check:
	python3 tests/check_metal_dp4_uchar_infinity_source.py

macos-metal-dp4-q-struct-row-source-check:
	python3 tests/check_metal_dp4_q_struct_row_source.py

macos-metal-dynamic-jump-walk-source-check:
	python3 tests/check_metal_dynamic_jump_walk_source.py

macos-metal-dynamic-compact-dp-source-check:
	python3 tests/check_metal_dynamic_compact_dp_source.py

macos-metal-dynamic-dp-stream-source-check:
	python3 tests/check_metal_dynamic_dp_stream_source.py

macos-metal-dynamic-dp-stream-mask-source-check:
	python3 tests/check_metal_dynamic_dp_stream_mask_source.py

macos-metal-dynamic-dp-stream-inplace-source-check:
	python3 tests/check_metal_dynamic_dp_stream_inplace_source.py

macos-metal-dynamic-dp-stream-xyzz-source-check:
	python3 tests/check_metal_dynamic_dp_stream_xyzz_source.py

macos-metal-dynamic-dp-count-source-check:
	python3 tests/check_metal_dynamic_dp_count_source.py

macos-build:
	$(CXX) $(MACOS_CXXFLAGS) $(MACOS_SRC) -o $(MACOS_TARGET) $(MACOS_LDFLAGS)

macos-check: check-host check-autoresearch check-quality-gates macos-lto-flags-check macos-jump-index-source-check macos-ecint-carry-source-check macos-hotpath-microbatch-source-check macos-affine-z-check-source-check macos-affine-inplace-field-source-check macos-affine-reverse-loop-source-check macos-metal-dp4-uchar-infinity-source-check macos-metal-dp4-q-struct-row-source-check macos-metal-dynamic-jump-walk-source-check macos-metal-dynamic-compact-dp-source-check macos-metal-dynamic-dp-stream-source-check macos-metal-dynamic-dp-stream-mask-source-check macos-metal-dynamic-dp-stream-inplace-source-check macos-metal-dynamic-dp-stream-xyzz-source-check macos-metal-dynamic-dp-count-source-check macos-build
	./$(MACOS_TARGET) selftest
	sh tests/check_point_bench_cli.sh
	sh tests/check_jacobian_point_bench_cli.sh
	sh tests/check_jacobian_batch_affine_bench_cli.sh
	sh tests/check_jacobian_walk_bench_cli.sh
	sh tests/check_jacobian_kangaroo_small_cli.sh
	sh tests/check_jacobian_kangaroo_small_bench_cli.sh
	sh tests/check_jacobian_kangaroo_multi_small_cli.sh
	sh tests/check_jacobian_kangaroo_multi_small_bench_cli.sh
	sh tests/check_cpu_field_cli.sh
	sh tests/check_cpu_field_bench_cli.sh
	sh tests/check_metal_kernels.sh
	sh tests/check_metal_field_cli.sh
	sh tests/check_metal_field_bench_cli.sh
	sh tests/check_metal_field_tg_limit_cli.sh
	sh tests/check_metal_field_mul_cli.sh
	sh tests/check_metal_field_square_cli.sh
	sh tests/check_metal_field_square_mul_cli.sh
	sh tests/check_metal_field_square_mul_bench_cli.sh
	sh tests/check_metal_field_sub_cli.sh
	sh tests/check_metal_field_double_cli.sh
	sh tests/check_metal_field_neg_cli.sh
	sh tests/check_metal_field_mul4_cli.sh
	sh tests/check_metal_jacobian_add_cli.sh
	sh tests/check_metal_jacobian_walk_cli.sh
	sh tests/check_metal_jacobian_jump_walk_cli.sh
	sh tests/check_metal_jacobian_dynamic_walk_cli.sh
	sh tests/check_metal_dynamic_compact_dp_cli.sh
	sh tests/check_metal_dynamic_dp_stream_cli.sh
	sh tests/check_metal_dynamic_dp_stream_dp8_cli.sh
	sh tests/check_metal_dynamic_dp_stream_inplace_cli.sh
	sh tests/check_metal_dynamic_dp_stream_xyzz_cli.sh
	sh tests/check_metal_dynamic_dp_count_cli.sh

macos-bench: macos-build
	./$(MACOS_TARGET) bench --iterations 64

macos-point-bench: macos-build
	./$(MACOS_TARGET) point-bench --iterations 256 --min-ms 50

macos-jacobian-point-bench: macos-build
	./$(MACOS_TARGET) jacobian-point-bench --iterations 256 --min-ms 50

macos-jacobian-batch-affine-bench: macos-build
	./$(MACOS_TARGET) jacobian-batch-affine-bench --iterations 256 --min-ms 50 --points 17

macos-jacobian-batch-affine-bench-run:
	./$(MACOS_TARGET) jacobian-batch-affine-bench --iterations 256 --min-ms 50 --points 17

macos-jacobian-walk-bench: macos-build
	./$(MACOS_TARGET) jacobian-walk-bench --iterations 256 --min-ms 50 --jumps 16

macos-jacobian-kangaroo-small-test: macos-build
	sh tests/check_jacobian_kangaroo_small_cli.sh

macos-jacobian-kangaroo-small-bench: macos-build
	./$(MACOS_TARGET) jacobian-kangaroo-small-bench --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096

macos-jacobian-kangaroo-small-bench-run:
	./$(MACOS_TARGET) jacobian-kangaroo-small-bench --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096

macos-jacobian-kangaroo-small-bench-test: macos-build
	sh tests/check_jacobian_kangaroo_small_bench_cli.sh

macos-jacobian-kangaroo-multi-small-test: macos-build
	sh tests/check_jacobian_kangaroo_multi_small_cli.sh

macos-jacobian-kangaroo-multi-small-bench: macos-build
	./$(MACOS_TARGET) jacobian-kangaroo-multi-small-bench --target-count 4 --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096

macos-jacobian-kangaroo-multi-small-bench-run:
	./$(MACOS_TARGET) jacobian-kangaroo-multi-small-bench --target-count 4 --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096

macos-jacobian-kangaroo-multi16-small-bench: macos-build
	./$(MACOS_TARGET) jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096

macos-jacobian-kangaroo-multi16-small-bench-run:
	./$(MACOS_TARGET) jacobian-kangaroo-multi-small-bench --target-count 16 --iterations 1 --min-ms 50 --range 8 --jumps 8 --dp-bits 0 --max-steps 4096

macos-jacobian-kangaroo-multi-small-bench-test: macos-build
	sh tests/check_jacobian_kangaroo_multi_small_bench_cli.sh

macos-cpu-field-test: macos-build
	sh tests/check_cpu_field_cli.sh

macos-cpu-field-bench: macos-build
	./$(MACOS_TARGET) cpu-field-bench --iterations 4096 --min-ms 50

macos-metal-kernels-check:
	sh tests/check_metal_kernels.sh

macos-metal-field-test: macos-build
	sh tests/check_metal_field_cli.sh

macos-metal-field-bench: macos-build
	./$(MACOS_TARGET) metal-field-bench --iterations 1048576 --min-ms 50

macos-metal-field-mul-test: macos-build
	sh tests/check_metal_field_mul_cli.sh

macos-metal-field-mul-bench: macos-build
	./$(MACOS_TARGET) metal-field-mul-bench --iterations 1048576 --min-ms 50

macos-metal-field-square-test: macos-build
	sh tests/check_metal_field_square_cli.sh

macos-metal-field-square-bench: macos-build
	./$(MACOS_TARGET) metal-field-square-bench --iterations 1048576 --min-ms 50

macos-metal-field-square-mul-test: macos-build
	sh tests/check_metal_field_square_mul_cli.sh

macos-metal-field-square-mul-bench: macos-build
	./$(MACOS_TARGET) metal-field-square-mul-bench --iterations 1048576 --min-ms 50

macos-metal-field-sub-test: macos-build
	sh tests/check_metal_field_sub_cli.sh

macos-metal-field-sub-bench: macos-build
	./$(MACOS_TARGET) metal-field-sub-bench --iterations 1048576 --min-ms 50

macos-metal-field-double-test: macos-build
	sh tests/check_metal_field_double_cli.sh

macos-metal-field-double-bench: macos-build
	./$(MACOS_TARGET) metal-field-double-bench --iterations 1048576 --min-ms 50

macos-metal-field-neg-test: macos-build
	sh tests/check_metal_field_neg_cli.sh

macos-metal-field-neg-bench: macos-build
	./$(MACOS_TARGET) metal-field-neg-bench --iterations 1048576 --min-ms 50

macos-metal-field-mul4-test: macos-build
	sh tests/check_metal_field_mul4_cli.sh

macos-metal-field-mul4-bench: macos-build
	./$(MACOS_TARGET) metal-field-mul4-bench --iterations 1048576 --min-ms 50

macos-metal-jacobian-add-test: macos-build
	./$(MACOS_TARGET) metal-jacobian-add-test

macos-metal-jacobian-add-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-add-bench --iterations 65536 --min-ms 50

macos-metal-jacobian-walk-test: macos-build
	./$(MACOS_TARGET) metal-jacobian-walk-test

macos-metal-jacobian-walk-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-walk-bench --iterations 16384 --steps 8 --min-ms 50

macos-metal-jacobian-jump-walk-test: macos-build
	./$(MACOS_TARGET) metal-jacobian-jump-walk-test

macos-metal-jacobian-jump-walk-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-jump-walk-bench --iterations 16384 --steps 8 --jumps 16 --min-ms 50

macos-metal-jacobian-jump-walk-dp-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-jump-walk-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 50

macos-metal-jacobian-jump-walk-dp-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-jump-walk-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 200

macos-metal-jacobian-jump-walk-dp-steps4-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-jump-walk-bench --iterations 16384 --steps 4 --jumps 16 --dp-bits 4 --min-ms 50

macos-metal-jacobian-dynamic-walk-test: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-walk-test

macos-metal-jacobian-dynamic-walk-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-walk-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 50

macos-metal-jacobian-dynamic-walk-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-walk-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 200

macos-metal-jacobian-dynamic-compact-dp-test: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-compact-dp-test

macos-metal-jacobian-dynamic-compact-dp-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-compact-dp-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 50

macos-metal-jacobian-dynamic-compact-dp-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-compact-dp-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 200

macos-metal-jacobian-dynamic-dp-stream-test: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-test

macos-metal-jacobian-dynamic-dp-stream-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 50

macos-metal-jacobian-dynamic-dp-stream-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 4 --min-ms 200

macos-metal-jacobian-dynamic-dp-stream-dp8-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 8 --min-ms 50

macos-metal-jacobian-dynamic-dp-stream-dp8-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 8 --min-ms 200

macos-metal-jacobian-dynamic-dp-stream-inplace-test: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-inplace-test

macos-metal-jacobian-dynamic-dp-stream-inplace-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 8 --min-ms 50

macos-metal-jacobian-dynamic-dp-stream-inplace-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 8 --min-ms 200

macos-metal-jacobian-dynamic-dp-stream-inplace-steps16-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 16384 --steps 16 --jumps 16 --dp-bits 8 --min-ms 50

macos-metal-jacobian-dynamic-dp-stream-inplace-steps16-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 16384 --steps 16 --jumps 16 --dp-bits 8 --min-ms 200

macos-metal-jacobian-dynamic-dp-stream-inplace-steps32-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 16384 --steps 32 --jumps 16 --dp-bits 8 --min-ms 50

macos-metal-jacobian-dynamic-dp-stream-inplace-steps32-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 16384 --steps 32 --jumps 16 --dp-bits 8 --min-ms 200

macos-metal-jacobian-dynamic-dp-stream-inplace-steps64-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 16384 --steps 64 --jumps 16 --dp-bits 8 --min-ms 50

macos-metal-jacobian-dynamic-dp-stream-inplace-steps64-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 16384 --steps 64 --jumps 16 --dp-bits 8 --min-ms 200

macos-metal-jacobian-dynamic-dp-stream-inplace-steps128-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 16384 --steps 128 --jumps 16 --dp-bits 8 --min-ms 50

macos-metal-jacobian-dynamic-dp-stream-inplace-steps128-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 16384 --steps 128 --jumps 16 --dp-bits 8 --min-ms 200

macos-metal-jacobian-dynamic-dp-stream-inplace-steps256-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 16384 --steps 256 --jumps 16 --dp-bits 8 --min-ms 50

macos-metal-jacobian-dynamic-dp-stream-inplace-steps256-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-inplace-bench --iterations 16384 --steps 256 --jumps 16 --dp-bits 8 --min-ms 200

macos-metal-jacobian-dynamic-dp-stream-xyzz-test: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-xyzz-test

macos-metal-jacobian-dynamic-dp-stream-xyzz-steps256-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations 16384 --steps 256 --jumps 16 --dp-bits 8 --min-ms 50

macos-metal-jacobian-dynamic-dp-stream-xyzz-steps256-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations 16384 --steps 256 --jumps 16 --dp-bits 8 --min-ms 200

macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations 16384 --steps 512 --jumps 16 --dp-bits 8 --min-ms 50

macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations 16384 --steps 512 --jumps 16 --dp-bits 8 --min-ms 200

macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-saturated-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations 262144 --steps 512 --jumps 16 --dp-bits 8 --min-ms 500

macos-metal-jacobian-dynamic-dp-stream-xyzz-steps512-large-batch-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations 524288 --steps 512 --jumps 16 --dp-bits 8 --min-ms 500

macos-metal-jacobian-dynamic-dp-stream-dp12-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 12 --min-ms 50

macos-metal-jacobian-dynamic-dp-stream-dp12-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-stream-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 12 --min-ms 200

macos-metal-jacobian-dynamic-dp-count-dp8-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-count-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 8 --min-ms 50

macos-metal-jacobian-dynamic-dp-count-dp8-stable-bench: macos-build
	./$(MACOS_TARGET) metal-jacobian-dynamic-dp-count-bench --iterations 16384 --steps 8 --jumps 16 --dp-bits 8 --min-ms 200
