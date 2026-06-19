#include "macos/MetalField.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <stdint.h>
#include <string.h>

#include <array>
#include <chrono>
#include <iomanip>
#include <sstream>
#include <vector>

typedef std::array<uint64_t, 4> FieldElement;

static const FieldElement kSecp256k1P = {
	0xFFFFFFFEFFFFFC2FULL,
	0xFFFFFFFFFFFFFFFFULL,
	0xFFFFFFFFFFFFFFFFULL,
	0xFFFFFFFFFFFFFFFFULL,
};

static std::string NSErrorToString(NSError* err)
{
	if (!err)
		return "unknown Metal error";
	const char* msg = [[err localizedDescription] UTF8String];
	return msg ? std::string(msg) : "unknown Metal error";
}

static bool GreaterOrEqualP(const FieldElement& v)
{
	for (int i = 3; i >= 0; --i)
	{
		if (v[(size_t)i] > kSecp256k1P[(size_t)i])
			return true;
		if (v[(size_t)i] < kSecp256k1P[(size_t)i])
			return false;
	}
	return true;
}

static void SubtractP(FieldElement& v)
{
	uint64_t borrow = 0;
	for (size_t i = 0; i < 4; ++i)
	{
		uint64_t before = v[i];
		uint64_t sub = kSecp256k1P[i];
		v[i] = before - sub - borrow;
		borrow = (before < sub) || (borrow && before == sub);
	}
}

static FieldElement CpuFieldAdd(const FieldElement& a, const FieldElement& b)
{
	FieldElement out;
	uint64_t carry = 0;
	for (size_t i = 0; i < 4; ++i)
	{
		uint64_t sum = a[i] + b[i];
		uint64_t carry_ab = sum < a[i];
		uint64_t sum_with_carry = sum + carry;
		uint64_t carry_c = sum_with_carry < sum;
		out[i] = sum_with_carry;
		carry = carry_ab | carry_c;
	}

	if (carry || GreaterOrEqualP(out))
		SubtractP(out);
	return out;
}

static std::string FieldToHex(const FieldElement& v)
{
	std::ostringstream oss;
	oss << std::hex;
	for (int i = 3; i >= 0; --i)
	{
		uint64_t limb = v[(size_t)i];
		for (int shift = 60; shift >= 0; shift -= 4)
			oss << "0123456789abcdef"[(limb >> shift) & 0xFULL];
	}
	return oss.str();
}

static std::string JsonEscape(const std::string& s)
{
	std::ostringstream oss;
	for (char ch : s)
	{
		switch (ch)
		{
		case '\\':
			oss << "\\\\";
			break;
		case '"':
			oss << "\\\"";
			break;
		case '\n':
			oss << "\\n";
			break;
		case '\r':
			oss << "\\r";
			break;
		case '\t':
			oss << "\\t";
			break;
		default:
			oss << ch;
			break;
		}
	}
	return oss.str();
}

static std::string MetalFieldBenchJson(unsigned int iterations,
	double seconds,
	double ops_per_sec,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"field_add_mod_p\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"seconds\":" << seconds << ",";
	oss << "\"ops_per_sec\":" << ops_per_sec << ",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static NSString* FieldAddSource()
{
	return
		@"#include <metal_stdlib>\n"
		@"using namespace metal;\n"
		@"static inline bool ge_p(ulong r0, ulong r1, ulong r2, ulong r3) {\n"
		@"  const ulong p0 = 0xFFFFFFFEFFFFFC2FUL;\n"
		@"  const ulong p1 = 0xFFFFFFFFFFFFFFFFUL;\n"
		@"  const ulong p2 = 0xFFFFFFFFFFFFFFFFUL;\n"
		@"  const ulong p3 = 0xFFFFFFFFFFFFFFFFUL;\n"
		@"  if (r3 != p3) return r3 > p3;\n"
		@"  if (r2 != p2) return r2 > p2;\n"
		@"  if (r1 != p1) return r1 > p1;\n"
		@"  return r0 >= p0;\n"
		@"}\n"
		@"static inline void sub_p(thread ulong& r0, thread ulong& r1, thread ulong& r2, thread ulong& r3) {\n"
		@"  const ulong p0 = 0xFFFFFFFEFFFFFC2FUL;\n"
		@"  const ulong p1 = 0xFFFFFFFFFFFFFFFFUL;\n"
		@"  const ulong p2 = 0xFFFFFFFFFFFFFFFFUL;\n"
		@"  const ulong p3 = 0xFFFFFFFFFFFFFFFFUL;\n"
		@"  ulong b = 0;\n"
		@"  ulong before = r0; r0 = before - p0 - b; b = (before < p0) || (b && before == p0);\n"
		@"  before = r1; r1 = before - p1 - b; b = (before < p1) || (b && before == p1);\n"
		@"  before = r2; r2 = before - p2 - b; b = (before < p2) || (b && before == p2);\n"
		@"  before = r3; r3 = before - p3 - b;\n"
		@"}\n"
		@"kernel void field_add_mod_p(device const ulong* a [[buffer(0)]],\n"
		@"                            device const ulong* b [[buffer(1)]],\n"
		@"                            device ulong* out [[buffer(2)]],\n"
		@"                            constant uint& count [[buffer(3)]],\n"
		@"                            uint id [[thread_position_in_grid]]) {\n"
		@"  if (id >= count) return;\n"
		@"  uint base = id * 4;\n"
		@"  ulong a0 = a[base + 0], a1 = a[base + 1], a2 = a[base + 2], a3 = a[base + 3];\n"
		@"  ulong b0 = b[base + 0], b1 = b[base + 1], b2 = b[base + 2], b3 = b[base + 3];\n"
		@"  ulong r0 = a0 + b0;\n"
		@"  ulong c = r0 < a0;\n"
		@"  ulong t = a1 + b1; ulong c1 = t < a1; ulong r1 = t + c; c = c1 || (r1 < t);\n"
		@"  t = a2 + b2; c1 = t < a2; ulong r2 = t + c; c = c1 || (r2 < t);\n"
		@"  t = a3 + b3; c1 = t < a3; ulong r3 = t + c; c = c1 || (r3 < t);\n"
		@"  if (c || ge_p(r0, r1, r2, r3)) sub_p(r0, r1, r2, r3);\n"
		@"  out[base + 0] = r0; out[base + 1] = r1; out[base + 2] = r2; out[base + 3] = r3;\n"
		@"}\n";
}

static bool RunFieldAddKernel(const std::vector<FieldElement>& a,
	const std::vector<FieldElement>& b,
	std::vector<FieldElement>& out,
	std::string& error,
	double* seconds)
{
	if (a.size() != b.size() || a.empty())
	{
		error = "invalid field add input";
		return false;
	}

	@autoreleasepool
	{
		id<MTLDevice> device = MTLCreateSystemDefaultDevice();
		if (!device)
		{
			error = "no Metal device available";
			return false;
		}

		NSError* ns_error = nil;
		id<MTLLibrary> library = [device newLibraryWithSource:FieldAddSource() options:nil error:&ns_error];
		if (!library)
		{
			error = NSErrorToString(ns_error);
			return false;
		}

		id<MTLFunction> function = [library newFunctionWithName:@"field_add_mod_p"];
		if (!function)
		{
			error = "failed to load field_add_mod_p function";
			return false;
		}

		id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&ns_error];
		if (!pipeline)
		{
			error = NSErrorToString(ns_error);
			return false;
		}

		size_t bytes = a.size() * sizeof(FieldElement);
		id<MTLBuffer> a_buffer = [device newBufferWithBytes:a.data() length:bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> b_buffer = [device newBufferWithBytes:b.data() length:bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_buffer = [device newBufferWithLength:bytes options:MTLResourceStorageModeShared];
		uint32_t count = (uint32_t)a.size();
		id<MTLBuffer> count_buffer = [device newBufferWithBytes:&count length:sizeof(count) options:MTLResourceStorageModeShared];
		if (!a_buffer || !b_buffer || !out_buffer || !count_buffer)
		{
			error = "failed to allocate Metal field buffers";
			return false;
		}

		id<MTLCommandQueue> queue = [device newCommandQueue];
		if (!queue)
		{
			error = "failed to create Metal command queue";
			return false;
		}

		id<MTLCommandBuffer> command_buffer = [queue commandBuffer];
		id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
		[encoder setComputePipelineState:pipeline];
		[encoder setBuffer:a_buffer offset:0 atIndex:0];
		[encoder setBuffer:b_buffer offset:0 atIndex:1];
		[encoder setBuffer:out_buffer offset:0 atIndex:2];
		[encoder setBuffer:count_buffer offset:0 atIndex:3];
		NSUInteger width = [pipeline threadExecutionWidth] ? [pipeline threadExecutionWidth] : 1;
		[encoder dispatchThreads:MTLSizeMake(count, 1, 1) threadsPerThreadgroup:MTLSizeMake(width, 1, 1)];
		[encoder endEncoding];
		auto start = std::chrono::steady_clock::now();
		[command_buffer commit];
		[command_buffer waitUntilCompleted];
		auto end = std::chrono::steady_clock::now();
		if (seconds)
			*seconds = std::chrono::duration<double>(end - start).count();

		if ([command_buffer status] != MTLCommandBufferStatusCompleted)
		{
			error = NSErrorToString([command_buffer error]);
			return false;
		}

		out.resize(a.size());
		memcpy(out.data(), [out_buffer contents], bytes);
		return true;
	}
}

bool RCKMetalFieldAddSelfTest(std::string& error)
{
	std::vector<FieldElement> a;
	std::vector<FieldElement> b;
	a.push_back({1, 0, 0, 0});
	b.push_back({2, 0, 0, 0});
	a.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	b.push_back({1, 0, 0, 0});
	a.push_back({0xFFFFFFFEFFFFFC2DULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	b.push_back({1, 0, 0, 0});
	a.push_back({0xFFFFFFFFFFFFFFFFULL, 0, 0, 0});
	b.push_back({1, 0, 0, 0});
	a.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	b.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});

	std::vector<FieldElement> out;
	if (!RunFieldAddKernel(a, b, out, error, NULL))
		return false;

	for (size_t i = 0; i < a.size(); ++i)
	{
		FieldElement expected = CpuFieldAdd(a[i], b[i]);
		if (out[i] != expected)
		{
			error = "field add mismatch at vector " + std::to_string(i) +
				": got " + FieldToHex(out[i]) + " expected " + FieldToHex(expected);
			return false;
		}
	}
	return true;
}

static FieldElement DeterministicElement(uint64_t i, uint64_t salt)
{
	FieldElement v = {
		0x9E3779B97F4A7C15ULL * (i + 1) + salt,
		0xD1B54A32D192ED03ULL * (i + 3) + (salt << 1),
		0x94D049BB133111EBULL * (i + 5) + (salt << 2),
		((i + salt) << 17) ^ (0xA5A5A5A5ULL + salt),
	};
	if (GreaterOrEqualP(v))
		SubtractP(v);
	return v;
}

std::string RCKMetalFieldAddBenchJson(unsigned int iterations)
{
	if (iterations == 0)
		iterations = 1;

	std::vector<FieldElement> a;
	std::vector<FieldElement> b;
	a.reserve(iterations);
	b.reserve(iterations);
	for (unsigned int i = 0; i < iterations; ++i)
	{
		a.push_back(DeterministicElement(i, 0x1234ULL));
		b.push_back(DeterministicElement(i, 0xBEEFULL));
	}

	std::vector<FieldElement> out;
	std::string error;
	double seconds = 0.0;
	if (!RunFieldAddKernel(a, b, out, error, &seconds))
	{
		if (error == "no Metal device available")
			return MetalFieldBenchJson(0, 0.0, 0.0, false, true, error);
		return MetalFieldBenchJson(iterations, seconds, 0.0, false, false, error);
	}

	for (unsigned int i = 0; i < iterations; ++i)
	{
		FieldElement expected = CpuFieldAdd(a[i], b[i]);
		if (out[i] != expected)
		{
			std::string reason = "mismatch at vector " + std::to_string(i) +
				": got " + FieldToHex(out[i]) + " expected " + FieldToHex(expected);
			return MetalFieldBenchJson(iterations, seconds, 0.0, false, false, reason);
		}
	}

	double ops_per_sec = seconds > 0.0 ? (double)iterations / seconds : 0.0;
	return MetalFieldBenchJson(iterations, seconds, ops_per_sec, true, false, "");
}
