CUDA_PATH ?= /usr/local/cuda-12.0
CC := g++
NVCC := $(CUDA_PATH)/bin/nvcc

.PHONY: all clean check-host check-portable-ec check-autoresearch macos-build macos-check macos-bench macos-point-bench macos-jacobian-point-bench macos-jacobian-batch-affine-bench macos-jacobian-batch-affine-bench-run macos-jacobian-walk-bench macos-jacobian-kangaroo-small-test macos-jacobian-kangaroo-small-bench macos-jacobian-kangaroo-small-bench-run macos-jacobian-kangaroo-small-bench-test macos-jacobian-kangaroo-multi-small-test macos-jacobian-kangaroo-multi-small-bench macos-jacobian-kangaroo-multi-small-bench-run macos-jacobian-kangaroo-multi16-small-bench macos-jacobian-kangaroo-multi16-small-bench-run macos-jacobian-kangaroo-multi-small-bench-test macos-cpu-field-test macos-cpu-field-bench macos-metal-kernels-check macos-metal-field-test macos-metal-field-bench macos-metal-field-mul-test macos-metal-field-mul-bench macos-metal-field-square-test macos-metal-field-square-bench macos-metal-field-sub-test macos-metal-field-sub-bench macos-metal-field-double-test macos-metal-field-double-bench macos-metal-field-neg-test macos-metal-field-neg-bench macos-metal-field-mul4-test macos-metal-field-mul4-bench

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

check-host: check-portable-ec
	sh tests/check_target_parser.sh

check-portable-ec:
	sh tests/check_portable_ec.sh

check-autoresearch:
	python3 tests/check_autoresearch_metric_passthrough.py

MACOS_SRC := macos/rck_macos.cpp macos/RCKMac.cpp macos/CpuField.cpp macos/MetalSmoke.mm macos/MetalField.mm Ec.cpp utils.cpp TargetSet.cpp
MACOS_CXXFLAGS ?= -std=c++17 -O3 -I.
MACOS_LDFLAGS := -framework Foundation -framework Metal

macos-build:
	$(CXX) $(MACOS_CXXFLAGS) $(MACOS_SRC) -o $(MACOS_TARGET) $(MACOS_LDFLAGS)

macos-check: check-host check-autoresearch macos-build
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
	sh tests/check_metal_field_mul_cli.sh
	sh tests/check_metal_field_square_cli.sh
	sh tests/check_metal_field_sub_cli.sh
	sh tests/check_metal_field_double_cli.sh
	sh tests/check_metal_field_neg_cli.sh
	sh tests/check_metal_field_mul4_cli.sh

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
	./$(MACOS_TARGET) metal-field-bench --iterations 1024

macos-metal-field-mul-test: macos-build
	sh tests/check_metal_field_mul_cli.sh

macos-metal-field-mul-bench: macos-build
	./$(MACOS_TARGET) metal-field-mul-bench --iterations 1024

macos-metal-field-square-test: macos-build
	sh tests/check_metal_field_square_cli.sh

macos-metal-field-square-bench: macos-build
	./$(MACOS_TARGET) metal-field-square-bench --iterations 1024

macos-metal-field-sub-test: macos-build
	sh tests/check_metal_field_sub_cli.sh

macos-metal-field-sub-bench: macos-build
	./$(MACOS_TARGET) metal-field-sub-bench --iterations 1024

macos-metal-field-double-test: macos-build
	sh tests/check_metal_field_double_cli.sh

macos-metal-field-double-bench: macos-build
	./$(MACOS_TARGET) metal-field-double-bench --iterations 1024

macos-metal-field-neg-test: macos-build
	sh tests/check_metal_field_neg_cli.sh

macos-metal-field-neg-bench: macos-build
	./$(MACOS_TARGET) metal-field-neg-bench --iterations 1024

macos-metal-field-mul4-test: macos-build
	sh tests/check_metal_field_mul4_cli.sh

macos-metal-field-mul4-bench: macos-build
	./$(MACOS_TARGET) metal-field-mul4-bench --iterations 1024
