CUDA_PATH ?= /usr/local/cuda-12.0
CC := g++
NVCC := $(CUDA_PATH)/bin/nvcc

.PHONY: all clean check-host check-portable-ec macos-build macos-check macos-bench

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

MACOS_SRC := macos/rck_macos.cpp macos/RCKMac.cpp Ec.cpp utils.cpp TargetSet.cpp

macos-build:
	$(CXX) -std=c++17 -O2 -I. $(MACOS_SRC) -o $(MACOS_TARGET)

macos-check: check-host macos-build
	./$(MACOS_TARGET) selftest

macos-bench: macos-build
	./$(MACOS_TARGET) bench --iterations 64
