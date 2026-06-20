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

#include "macos/MetalFieldKernels.h"

typedef std::array<uint64_t, 4> FieldElement;

static constexpr unsigned int kDefaultMetalFieldThreadgroupLimit = 256;

struct MetalDispatchStats
{
	unsigned int threadgroup_limit = 0;
	unsigned int thread_execution_width = 0;
	unsigned int max_threads_per_threadgroup = 0;
	unsigned int threads_per_threadgroup = 0;
};

static const FieldElement kSecp256k1P = {
	0xFFFFFFFEFFFFFC2FULL,
	0xFFFFFFFFFFFFFFFFULL,
	0xFFFFFFFFFFFFFFFFULL,
	0xFFFFFFFFFFFFFFFFULL,
};

static FieldElement DeterministicElement(uint64_t i, uint64_t salt);

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

static inline uint64_t Mul64(uint64_t a, uint64_t b, uint64_t* hi)
{
	unsigned __int128 product = (unsigned __int128)a * (unsigned __int128)b;
	*hi = (uint64_t)(product >> 64);
	return (uint64_t)product;
}

static inline uint8_t AddCarry(uint8_t carry, uint64_t a, uint64_t b, uint64_t* out)
{
	unsigned __int128 sum = (unsigned __int128)a + (unsigned __int128)b + carry;
	*out = (uint64_t)sum;
	return (uint8_t)(sum >> 64);
}

static inline uint8_t SubBorrow(uint8_t borrow, uint64_t a, uint64_t b, uint64_t* out)
{
	uint64_t sub = b + borrow;
	*out = a - sub;
	return (uint8_t)((a < b) || (borrow && a == b));
}

static void SubtractP5(uint64_t v[5])
{
	uint8_t borrow = SubBorrow(0, v[0], kSecp256k1P[0], v + 0);
	borrow = SubBorrow(borrow, v[1], kSecp256k1P[1], v + 1);
	borrow = SubBorrow(borrow, v[2], kSecp256k1P[2], v + 2);
	borrow = SubBorrow(borrow, v[3], kSecp256k1P[3], v + 3);
	SubBorrow(borrow, v[4], 0, v + 4);
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

static FieldElement CpuFieldSub(const FieldElement& a, const FieldElement& b)
{
	FieldElement out;
	uint8_t borrow = 0;
	for (size_t i = 0; i < 4; ++i)
		borrow = SubBorrow(borrow, a[i], b[i], &out[i]);

	if (borrow)
	{
		uint64_t carry = 0;
		for (size_t i = 0; i < 4; ++i)
		{
			uint64_t sum = out[i] + kSecp256k1P[i];
			uint64_t carry_ab = sum < out[i];
			uint64_t sum_with_carry = sum + carry;
			uint64_t carry_c = sum_with_carry < sum;
			out[i] = sum_with_carry;
			carry = carry_ab | carry_c;
		}
	}
	return out;
}

static FieldElement CpuFieldDouble(const FieldElement& a)
{
	return CpuFieldAdd(a, a);
}

static FieldElement CpuFieldMul4(const FieldElement& a)
{
	return CpuFieldDouble(CpuFieldDouble(a));
}

static FieldElement CpuFieldNeg(const FieldElement& a)
{
	static const FieldElement zero = {0, 0, 0, 0};
	return CpuFieldSub(zero, a);
}

static void Mul256By64(const uint64_t input[4], uint64_t multiplier, uint64_t result[5])
{
	uint64_t h1, h2;
	result[0] = Mul64(input[0], multiplier, &h1);
	uint8_t carry = AddCarry(0, Mul64(input[1], multiplier, &h2), h1, result + 1);
	carry = AddCarry(carry, Mul64(input[2], multiplier, &h1), h2, result + 2);
	carry = AddCarry(carry, Mul64(input[3], multiplier, &h2), h1, result + 3);
	AddCarry(carry, 0, h2, result + 4);
}

static void Add320To256(uint64_t* in_out, const uint64_t val[5])
{
	uint8_t carry = AddCarry(0, in_out[0], val[0], in_out);
	carry = AddCarry(carry, in_out[1], val[1], in_out + 1);
	carry = AddCarry(carry, in_out[2], val[2], in_out + 2);
	carry = AddCarry(carry, in_out[3], val[3], in_out + 3);
	AddCarry(carry, 0, val[4], in_out + 4);
}

static FieldElement CpuFieldMul(const FieldElement& a, const FieldElement& b)
{
	static const uint64_t p_rev = 0x00000001000003D1ULL;
	uint64_t buff[8] = {0};
	uint64_t tmp[5] = {0};
	uint64_t high = 0;

	Mul256By64(b.data(), a[0], buff);
	Mul256By64(b.data(), a[1], tmp);
	Add320To256(buff + 1, tmp);
	Mul256By64(b.data(), a[2], tmp);
	Add320To256(buff + 2, tmp);
	Mul256By64(b.data(), a[3], tmp);
	Add320To256(buff + 3, tmp);

	Mul256By64(buff + 4, p_rev, tmp);
	uint8_t carry = AddCarry(0, buff[0], tmp[0], buff + 0);
	carry = AddCarry(carry, buff[1], tmp[1], buff + 1);
	carry = AddCarry(carry, buff[2], tmp[2], buff + 2);
	tmp[4] += AddCarry(carry, buff[3], tmp[3], buff + 3);

	uint64_t reduced[5] = {0};
	carry = AddCarry(0, buff[0], Mul64(tmp[4], p_rev, &high), reduced + 0);
	carry = AddCarry(carry, buff[1], high, reduced + 1);
	carry = AddCarry(carry, 0, buff[2], reduced + 2);
	reduced[4] = AddCarry(carry, buff[3], 0, reduced + 3);

	FieldElement out = {reduced[0], reduced[1], reduced[2], reduced[3]};
	while (reduced[4] || GreaterOrEqualP(out))
	{
		SubtractP5(reduced);
		out = {reduced[0], reduced[1], reduced[2], reduced[3]};
	}
	return out;
}

static FieldElement CpuFieldSquare(const FieldElement& a)
{
	return CpuFieldMul(a, a);
}

typedef FieldElement (*ExpectedFieldFn)(const FieldElement& a, const FieldElement& b);

static FieldElement ExpectedAdd(const FieldElement& a, const FieldElement& b)
{
	return CpuFieldAdd(a, b);
}

static FieldElement ExpectedSub(const FieldElement& a, const FieldElement& b)
{
	return CpuFieldSub(a, b);
}

static FieldElement ExpectedDouble(const FieldElement& a, const FieldElement&)
{
	return CpuFieldDouble(a);
}

static FieldElement ExpectedMul4(const FieldElement& a, const FieldElement&)
{
	return CpuFieldMul4(a);
}

static FieldElement ExpectedNeg(const FieldElement& a, const FieldElement&)
{
	return CpuFieldNeg(a);
}

static FieldElement ExpectedMul(const FieldElement& a, const FieldElement& b)
{
	return CpuFieldMul(a, b);
}

static FieldElement ExpectedSquare(const FieldElement& a, const FieldElement&)
{
	return CpuFieldSquare(a);
}

static FieldElement ExpectedSquareMul(const FieldElement& a, const FieldElement& b)
{
	return CpuFieldMul(CpuFieldSquare(a), b);
}

struct CpuJacobianPoint
{
	FieldElement x;
	FieldElement y;
	FieldElement z;
	bool infinity = false;
};

struct CpuAffinePoint
{
	FieldElement x;
	FieldElement y;
};

static bool CpuFieldIsZero(const FieldElement& v)
{
	return (v[0] | v[1] | v[2] | v[3]) == 0;
}

static CpuJacobianPoint CpuJacobianInfinity()
{
	CpuJacobianPoint out;
	out.x = {0, 0, 0, 0};
	out.y = {0, 0, 0, 0};
	out.z = {0, 0, 0, 0};
	out.infinity = true;
	return out;
}

static CpuJacobianPoint CpuJacobianFromAffine(const CpuAffinePoint& q)
{
	CpuJacobianPoint out;
	out.x = q.x;
	out.y = q.y;
	out.z = {1, 0, 0, 0};
	out.infinity = false;
	return out;
}

static CpuJacobianPoint CpuJacobianDouble(const CpuJacobianPoint& p)
{
	if (p.infinity || CpuFieldIsZero(p.y))
		return CpuJacobianInfinity();

	FieldElement xx = CpuFieldSquare(p.x);
	FieldElement yy = CpuFieldSquare(p.y);
	FieldElement yyyy = CpuFieldSquare(yy);
	FieldElement s = CpuFieldDouble(CpuFieldSub(CpuFieldSub(CpuFieldSquare(CpuFieldAdd(p.x, yy)), xx), yyyy));
	FieldElement m = CpuFieldAdd(CpuFieldDouble(xx), xx);
	FieldElement t = CpuFieldSub(CpuFieldSquare(m), CpuFieldDouble(s));
	FieldElement eight_yyyy = CpuFieldDouble(CpuFieldDouble(CpuFieldDouble(yyyy)));

	CpuJacobianPoint out;
	out.x = t;
	out.y = CpuFieldSub(CpuFieldMul(m, CpuFieldSub(s, t)), eight_yyyy);
	out.z = CpuFieldSub(CpuFieldSub(CpuFieldSquare(CpuFieldAdd(p.y, p.z)), yy), CpuFieldSquare(p.z));
	out.infinity = false;
	return out;
}

static CpuJacobianPoint CpuJacobianAddAffine(const CpuJacobianPoint& p, const CpuAffinePoint& q)
{
	if (p.infinity)
		return CpuJacobianFromAffine(q);

	FieldElement z2 = CpuFieldSquare(p.z);
	FieldElement z3 = CpuFieldMul(z2, p.z);
	FieldElement u2 = CpuFieldMul(q.x, z2);
	FieldElement s2 = CpuFieldMul(q.y, z3);
	FieldElement h = CpuFieldSub(u2, p.x);
	FieldElement r = CpuFieldSub(s2, p.y);

	if (CpuFieldIsZero(h))
	{
		if (CpuFieldIsZero(r))
			return CpuJacobianDouble(p);
		return CpuJacobianInfinity();
	}

	FieldElement hh = CpuFieldSquare(h);
	FieldElement hhh = CpuFieldMul(hh, h);
	FieldElement v = CpuFieldMul(p.x, hh);
	FieldElement x3 = CpuFieldSub(CpuFieldSub(CpuFieldSquare(r), hhh), CpuFieldDouble(v));
	FieldElement y3 = CpuFieldSub(CpuFieldMul(r, CpuFieldSub(v, x3)), CpuFieldMul(p.y, hhh));
	FieldElement z3_out = CpuFieldMul(p.z, h);

	CpuJacobianPoint out;
	out.x = x3;
	out.y = y3;
	out.z = z3_out;
	out.infinity = false;
	return out;
}

static bool CpuJacobianMatches(const CpuJacobianPoint& a, const CpuJacobianPoint& b)
{
	if (a.infinity != b.infinity)
		return false;
	if (a.infinity)
		return true;
	return a.x == b.x && a.y == b.y && a.z == b.z;
}

static void PackJacobianInputs(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& q,
	std::vector<uint64_t>& p_xyz,
	std::vector<uint64_t>& q_xy,
	std::vector<uint32_t>& p_infinity)
{
	p_xyz.clear();
	q_xy.clear();
	p_infinity.clear();
	p_xyz.reserve(p.size() * 12);
	q_xy.reserve(q.size() * 8);
	p_infinity.reserve(p.size());
	for (size_t i = 0; i < p.size(); ++i)
	{
		for (uint64_t limb : p[i].x)
			p_xyz.push_back(limb);
		for (uint64_t limb : p[i].y)
			p_xyz.push_back(limb);
		for (uint64_t limb : p[i].z)
			p_xyz.push_back(limb);
		for (uint64_t limb : q[i].x)
			q_xy.push_back(limb);
		for (uint64_t limb : q[i].y)
			q_xy.push_back(limb);
		p_infinity.push_back(p[i].infinity ? 1U : 0U);
	}
}

static CpuJacobianPoint UnpackJacobianOutput(const std::vector<uint64_t>& out_xyz,
	const std::vector<uint32_t>& out_infinity,
	size_t index)
{
	CpuJacobianPoint out;
	size_t base = index * 12;
	for (size_t i = 0; i < 4; ++i)
		out.x[i] = out_xyz[base + i];
	for (size_t i = 0; i < 4; ++i)
		out.y[i] = out_xyz[base + 4 + i];
	for (size_t i = 0; i < 4; ++i)
		out.z[i] = out_xyz[base + 8 + i];
	out.infinity = out_infinity[index] != 0;
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

static std::string MetalFieldBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int sample_count,
	unsigned int min_ms,
	const MetalDispatchStats& dispatch_stats,
	double seconds,
	double ops_per_sec,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << sample_count << ",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"threadgroup_limit\":" << dispatch_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << dispatch_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << dispatch_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << dispatch_stats.threads_per_threadgroup << ",";
	oss << "\"seconds\":" << seconds << ",";
	oss << "\"ops_per_sec\":" << ops_per_sec << ",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static NSString* FieldSource()
{
	return [NSString stringWithUTF8String:RCKMetalFieldKernelsSource];
}

static NSUInteger EffectiveThreadgroupLimit(unsigned int threadgroup_limit)
{
	return threadgroup_limit ? (NSUInteger)threadgroup_limit : (NSUInteger)kDefaultMetalFieldThreadgroupLimit;
}

static NSUInteger PreferredThreadgroupWidth(id<MTLComputePipelineState> pipeline, unsigned int threadgroup_limit)
{
	NSUInteger execution_width = [pipeline threadExecutionWidth] ? [pipeline threadExecutionWidth] : 1;
	NSUInteger max_threads = [pipeline maxTotalThreadsPerThreadgroup] ? [pipeline maxTotalThreadsPerThreadgroup] : execution_width;
	NSUInteger requested_limit = EffectiveThreadgroupLimit(threadgroup_limit);
	NSUInteger target = max_threads < requested_limit ? max_threads : requested_limit;
	target -= target % execution_width;
	if (target < execution_width)
		target = execution_width;
	return target;
}

static bool RunFieldKernel(const std::vector<FieldElement>& a,
	const std::vector<FieldElement>& b,
	std::vector<FieldElement>& out,
	std::string& error,
	double* seconds,
	const char* function_name,
	unsigned int threadgroup_limit = 0,
	MetalDispatchStats* dispatch_stats = NULL)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);

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
		id<MTLLibrary> library = [device newLibraryWithSource:FieldSource() options:nil error:&ns_error];
		if (!library)
		{
			error = NSErrorToString(ns_error);
			return false;
		}

		id<MTLFunction> function = [library newFunctionWithName:[NSString stringWithUTF8String:function_name]];
		if (!function)
		{
			error = std::string("failed to load ") + function_name + " function";
			return false;
		}

		id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&ns_error];
		if (!pipeline)
		{
			error = NSErrorToString(ns_error);
			return false;
		}
		NSUInteger execution_width = [pipeline threadExecutionWidth] ? [pipeline threadExecutionWidth] : 1;
		NSUInteger max_threads = [pipeline maxTotalThreadsPerThreadgroup] ? [pipeline maxTotalThreadsPerThreadgroup] : execution_width;
		NSUInteger threads_per_threadgroup = PreferredThreadgroupWidth(pipeline, threadgroup_limit);
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
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
		[encoder dispatchThreads:MTLSizeMake(count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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

static bool RunJacobianAddAffineKernel(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& q,
	std::vector<CpuJacobianPoint>& out,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit = 0,
	MetalDispatchStats* dispatch_stats = NULL)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);

	if (p.size() != q.size() || p.empty())
	{
		error = "invalid jacobian add input";
		return false;
	}

	std::vector<uint64_t> p_xyz;
	std::vector<uint64_t> q_xy;
	std::vector<uint32_t> p_infinity;
	PackJacobianInputs(p, q, p_xyz, q_xy, p_infinity);

	@autoreleasepool
	{
		id<MTLDevice> device = MTLCreateSystemDefaultDevice();
		if (!device)
		{
			error = "no Metal device available";
			return false;
		}

		NSError* ns_error = nil;
		id<MTLLibrary> library = [device newLibraryWithSource:FieldSource() options:nil error:&ns_error];
		if (!library)
		{
			error = NSErrorToString(ns_error);
			return false;
		}

		id<MTLFunction> function = [library newFunctionWithName:@"jacobian_add_affine"];
		if (!function)
		{
			error = "failed to load jacobian_add_affine function";
			return false;
		}

		id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:function error:&ns_error];
		if (!pipeline)
		{
			error = NSErrorToString(ns_error);
			return false;
		}
		NSUInteger execution_width = [pipeline threadExecutionWidth] ? [pipeline threadExecutionWidth] : 1;
		NSUInteger max_threads = [pipeline maxTotalThreadsPerThreadgroup] ? [pipeline maxTotalThreadsPerThreadgroup] : execution_width;
		NSUInteger threads_per_threadgroup = PreferredThreadgroupWidth(pipeline, threadgroup_limit);
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t p_bytes = p_xyz.size() * sizeof(uint64_t);
		size_t q_bytes = q_xy.size() * sizeof(uint64_t);
		size_t inf_bytes = p_infinity.size() * sizeof(uint32_t);
		std::vector<uint64_t> out_xyz(p.size() * 12);
		std::vector<uint32_t> out_infinity(p.size());
		size_t out_bytes = out_xyz.size() * sizeof(uint64_t);
		id<MTLBuffer> p_buffer = [device newBufferWithBytes:p_xyz.data() length:p_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> q_buffer = [device newBufferWithBytes:q_xy.data() length:q_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> p_inf_buffer = [device newBufferWithBytes:p_infinity.data() length:inf_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_buffer = [device newBufferWithLength:out_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_inf_buffer = [device newBufferWithLength:inf_bytes options:MTLResourceStorageModeShared];
		uint32_t count = (uint32_t)p.size();
		id<MTLBuffer> count_buffer = [device newBufferWithBytes:&count length:sizeof(count) options:MTLResourceStorageModeShared];
		if (!p_buffer || !q_buffer || !p_inf_buffer || !out_buffer || !out_inf_buffer || !count_buffer)
		{
			error = "failed to allocate Metal jacobian add buffers";
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
		[encoder setBuffer:p_buffer offset:0 atIndex:0];
		[encoder setBuffer:q_buffer offset:0 atIndex:1];
		[encoder setBuffer:p_inf_buffer offset:0 atIndex:2];
		[encoder setBuffer:out_buffer offset:0 atIndex:3];
		[encoder setBuffer:out_inf_buffer offset:0 atIndex:4];
		[encoder setBuffer:count_buffer offset:0 atIndex:5];
		[encoder dispatchThreads:MTLSizeMake(count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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

		memcpy(out_xyz.data(), [out_buffer contents], out_bytes);
		memcpy(out_infinity.data(), [out_inf_buffer contents], inf_bytes);
		out.resize(p.size());
		for (size_t i = 0; i < p.size(); ++i)
			out[i] = UnpackJacobianOutput(out_xyz, out_infinity, i);
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
	if (!RunFieldKernel(a, b, out, error, NULL, "field_add_mod_p"))
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

bool RCKMetalFieldSubSelfTest(std::string& error)
{
	std::vector<FieldElement> a;
	std::vector<FieldElement> b;
	a.push_back({3, 0, 0, 0});
	b.push_back({1, 0, 0, 0});
	a.push_back({1, 0, 0, 0});
	b.push_back({2, 0, 0, 0});
	a.push_back({0, 0, 0, 0});
	b.push_back({0, 0, 0, 0});
	a.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	b.push_back({0xFFFFFFFEFFFFFC2DULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	a.push_back({0xFFFFFFFEFFFFFC2DULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	b.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	for (uint64_t i = 0; i < 16; ++i)
	{
		a.push_back(DeterministicElement(i, 0x51BULL));
		b.push_back(DeterministicElement(i, 0xA7BULL));
	}

	std::vector<FieldElement> out;
	if (!RunFieldKernel(a, b, out, error, NULL, "field_sub_mod_p"))
		return false;

	for (size_t i = 0; i < a.size(); ++i)
	{
		FieldElement expected = CpuFieldSub(a[i], b[i]);
		if (out[i] != expected)
		{
			error = "field sub mismatch at vector " + std::to_string(i) +
				": got " + FieldToHex(out[i]) + " expected " + FieldToHex(expected);
			return false;
		}
	}
	return true;
}

bool RCKMetalFieldDoubleSelfTest(std::string& error)
{
	std::vector<FieldElement> a;
	std::vector<FieldElement> b;
	a.push_back({1, 0, 0, 0});
	a.push_back({0, 0, 0, 0});
	a.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	a.push_back({0xFFFFFFFEFFFFFC2DULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	a.push_back({0xFFFFFFFFFFFFFFFFULL, 0, 0, 0});
	for (uint64_t i = 0; i < 16; ++i)
		a.push_back(DeterministicElement(i, 0xD00BULL));
	b = a;

	std::vector<FieldElement> out;
	if (!RunFieldKernel(a, b, out, error, NULL, "field_double_mod_p"))
		return false;

	for (size_t i = 0; i < a.size(); ++i)
	{
		FieldElement expected = CpuFieldDouble(a[i]);
		if (out[i] != expected)
		{
			error = "field double mismatch at vector " + std::to_string(i) +
				": got " + FieldToHex(out[i]) + " expected " + FieldToHex(expected);
			return false;
		}
	}
	return true;
}

bool RCKMetalFieldMul4SelfTest(std::string& error)
{
	std::vector<FieldElement> a;
	std::vector<FieldElement> b;
	a.push_back({0, 0, 0, 0});
	a.push_back({1, 0, 0, 0});
	a.push_back({2, 0, 0, 0});
	a.push_back({0x4000000000000000ULL, 0, 0, 0});
	a.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	a.push_back({0xFFFFFFFEFFFFFC2DULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	a.push_back({0xFFFFFFFFFFFFFFFFULL, 0, 0, 0});
	for (uint64_t i = 0; i < 16; ++i)
		a.push_back(DeterministicElement(i, 0x4D14ULL));
	b = a;

	std::vector<FieldElement> out;
	if (!RunFieldKernel(a, b, out, error, NULL, "field_mul4_mod_p"))
		return false;

	for (size_t i = 0; i < a.size(); ++i)
	{
		FieldElement expected = CpuFieldMul4(a[i]);
		if (out[i] != expected)
		{
			error = "field mul4 mismatch at vector " + std::to_string(i) +
				": got " + FieldToHex(out[i]) + " expected " + FieldToHex(expected);
			return false;
		}
	}
	return true;
}

bool RCKMetalFieldNegSelfTest(std::string& error)
{
	std::vector<FieldElement> a;
	std::vector<FieldElement> b;
	a.push_back({0, 0, 0, 0});
	a.push_back({1, 0, 0, 0});
	a.push_back({2, 0, 0, 0});
	a.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	a.push_back({0xFFFFFFFEFFFFFC2DULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	a.push_back({0xFFFFFFFFFFFFFFFFULL, 0, 0, 0});
	for (uint64_t i = 0; i < 16; ++i)
		a.push_back(DeterministicElement(i, 0x6E67ULL));
	b = a;

	std::vector<FieldElement> out;
	if (!RunFieldKernel(a, b, out, error, NULL, "field_neg_mod_p"))
		return false;

	for (size_t i = 0; i < a.size(); ++i)
	{
		FieldElement expected = CpuFieldNeg(a[i]);
		if (out[i] != expected)
		{
			error = "field neg mismatch at vector " + std::to_string(i) +
				": got " + FieldToHex(out[i]) + " expected " + FieldToHex(expected);
			return false;
		}
	}
	return true;
}

bool RCKMetalFieldMulSelfTest(std::string& error)
{
	std::vector<FieldElement> a;
	std::vector<FieldElement> b;
	a.push_back({1, 0, 0, 0});
	b.push_back({2, 0, 0, 0});
	a.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	b.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	a.push_back({0xFFFFFFFFFFFFFFFFULL, 0, 0, 0});
	b.push_back({0xFFFFFFFFFFFFFFFFULL, 0, 0, 0});
	for (uint64_t i = 0; i < 16; ++i)
	{
		a.push_back(DeterministicElement(i, 0xCAFEULL));
		b.push_back(DeterministicElement(i, 0xBEEFULL));
	}

	std::vector<FieldElement> out;
	if (!RunFieldKernel(a, b, out, error, NULL, "field_mul_mod_p"))
		return false;

	for (size_t i = 0; i < a.size(); ++i)
	{
		FieldElement expected = CpuFieldMul(a[i], b[i]);
		if (out[i] != expected)
		{
			error = "field mul mismatch at vector " + std::to_string(i) +
				": got " + FieldToHex(out[i]) + " expected " + FieldToHex(expected);
			return false;
		}
	}
	return true;
}

bool RCKMetalFieldSquareSelfTest(std::string& error)
{
	std::vector<FieldElement> a;
	std::vector<FieldElement> b;
	a.push_back({1, 0, 0, 0});
	a.push_back({2, 0, 0, 0});
	a.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	a.push_back({0xFFFFFFFFFFFFFFFFULL, 0, 0, 0});
	for (uint64_t i = 0; i < 16; ++i)
		a.push_back(DeterministicElement(i, 0x5A5AULL));
	b = a;

	std::vector<FieldElement> out;
	if (!RunFieldKernel(a, b, out, error, NULL, "field_square_mod_p"))
		return false;

	for (size_t i = 0; i < a.size(); ++i)
	{
		FieldElement expected = CpuFieldSquare(a[i]);
		if (out[i] != expected)
		{
			error = "field square mismatch at vector " + std::to_string(i) +
				": got " + FieldToHex(out[i]) + " expected " + FieldToHex(expected);
			return false;
		}
	}
	return true;
}

bool RCKMetalFieldSquareMulSelfTest(std::string& error)
{
	std::vector<FieldElement> a;
	std::vector<FieldElement> b;
	a.push_back({1, 0, 0, 0});
	b.push_back({2, 0, 0, 0});
	a.push_back({2, 0, 0, 0});
	b.push_back({3, 0, 0, 0});
	a.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	b.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	a.push_back({0xFFFFFFFFFFFFFFFFULL, 0, 0, 0});
	b.push_back({0xFFFFFFFFFFFFFFFFULL, 0, 0, 0});
	for (uint64_t i = 0; i < 16; ++i)
	{
		a.push_back(DeterministicElement(i, 0x5A5AULL));
		b.push_back(DeterministicElement(i, 0xC0DEULL));
	}

	std::vector<FieldElement> out;
	if (!RunFieldKernel(a, b, out, error, NULL, "field_square_mul_mod_p"))
		return false;

	for (size_t i = 0; i < a.size(); ++i)
	{
		FieldElement expected = ExpectedSquareMul(a[i], b[i]);
		if (out[i] != expected)
		{
			error = "field square-mul mismatch at vector " + std::to_string(i) +
				": got " + FieldToHex(out[i]) + " expected " + FieldToHex(expected);
			return false;
		}
	}
	return true;
}

static void BuildJacobianAddSamples(unsigned int sample_count,
	std::vector<CpuJacobianPoint>& p,
	std::vector<CpuAffinePoint>& q)
{
	p.clear();
	q.clear();
	p.reserve(sample_count);
	q.reserve(sample_count);
	for (unsigned int i = 0; i < sample_count; ++i)
	{
		CpuJacobianPoint jp;
		CpuAffinePoint aq;
		if (i == 0)
		{
			jp = CpuJacobianInfinity();
			aq.x = {7, 0, 0, 0};
			aq.y = {11, 0, 0, 0};
		}
		else if (i == 1)
		{
			jp.x = {3, 0, 0, 0};
			jp.y = {4, 0, 0, 0};
			jp.z = {1, 0, 0, 0};
			jp.infinity = false;
			aq.x = jp.x;
			aq.y = jp.y;
		}
		else if (i == 2)
		{
			jp.x = {5, 0, 0, 0};
			jp.y = {9, 0, 0, 0};
			jp.z = {1, 0, 0, 0};
			jp.infinity = false;
			aq.x = jp.x;
			aq.y = CpuFieldAdd(jp.y, {1, 0, 0, 0});
		}
		else
		{
			jp.x = DeterministicElement(i, 0xA11CEULL);
			jp.y = DeterministicElement(i, 0xB0BULL);
			jp.z = DeterministicElement(i, 0x533DULL);
			if (CpuFieldIsZero(jp.z))
				jp.z = {1, 0, 0, 0};
			jp.infinity = false;
			aq.x = DeterministicElement(i, 0xC0FFEEULL);
			aq.y = DeterministicElement(i, 0xFACEULL);
		}
		p.push_back(jp);
		q.push_back(aq);
	}
}

bool RCKMetalJacobianAddSelfTest(std::string& error)
{
	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> q;
	BuildJacobianAddSamples(24, p, q);

	std::vector<CpuJacobianPoint> out;
	if (!RunJacobianAddAffineKernel(p, q, out, error, NULL))
		return false;

	for (size_t i = 0; i < p.size(); ++i)
	{
		CpuJacobianPoint expected = CpuJacobianAddAffine(p[i], q[i]);
		if (!CpuJacobianMatches(out[i], expected))
		{
			error = "jacobian add mismatch at vector " + std::to_string(i) +
				": got x=" + FieldToHex(out[i].x) + " y=" + FieldToHex(out[i].y) +
				" z=" + FieldToHex(out[i].z) + " inf=" + (out[i].infinity ? "1" : "0") +
				" expected x=" + FieldToHex(expected.x) + " y=" + FieldToHex(expected.y) +
				" z=" + FieldToHex(expected.z) + " inf=" + (expected.infinity ? "1" : "0");
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

std::string RCKMetalJacobianAddBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit)
{
	if (iterations == 0)
		iterations = 1;

	const unsigned int sample_count = iterations;
	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> q;
	BuildJacobianAddSamples(sample_count, p, q);

	std::vector<CpuJacobianPoint> out;
	std::string error;
	double seconds = 0.0;
	uint64_t operations = 0;
	unsigned int dispatch_count = 0;
	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunJacobianAddAffineKernel(p, q, out, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalFieldBenchJson("jacobian_add_affine", 0, sample_count, min_ms, dispatch_stats, 0.0, 0.0, false, true, error);
			return MetalFieldBenchJson("jacobian_add_affine", operations ? operations : sample_count, sample_count, min_ms, dispatch_stats, seconds, 0.0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += sample_count;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	for (unsigned int i = 0; i < sample_count; ++i)
	{
		CpuJacobianPoint expected = CpuJacobianAddAffine(p[i], q[i]);
		if (!CpuJacobianMatches(out[i], expected))
		{
			std::string reason = "mismatch at vector " + std::to_string(i) +
				": got x=" + FieldToHex(out[i].x) + " y=" + FieldToHex(out[i].y) +
				" z=" + FieldToHex(out[i].z) + " inf=" + (out[i].infinity ? "1" : "0") +
				" expected x=" + FieldToHex(expected.x) + " y=" + FieldToHex(expected.y) +
				" z=" + FieldToHex(expected.z) + " inf=" + (expected.infinity ? "1" : "0");
			return MetalFieldBenchJson("jacobian_add_affine", operations, sample_count, min_ms, dispatch_stats, seconds, 0.0, false, false, reason);
		}
	}

	double ops_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	return MetalFieldBenchJson("jacobian_add_affine", operations, sample_count, min_ms, dispatch_stats, seconds, ops_per_sec, true, false, "");
}

static std::string RunMetalFieldBenchJson(const char* operation,
	const char* function_name,
	unsigned int iterations,
	unsigned int min_ms,
	uint64_t a_salt,
	uint64_t b_salt,
	bool same_inputs,
	ExpectedFieldFn expected_fn,
	unsigned int threadgroup_limit)
{
	if (iterations == 0)
		iterations = 1;

	const unsigned int sample_count = iterations;
	std::vector<FieldElement> a;
	std::vector<FieldElement> b;
	a.reserve(sample_count);
	b.reserve(sample_count);
	for (unsigned int i = 0; i < sample_count; ++i)
	{
		a.push_back(DeterministicElement(i, a_salt));
		b.push_back(same_inputs ? a.back() : DeterministicElement(i, b_salt));
	}

	std::vector<FieldElement> out;
	std::string error;
	double seconds = 0.0;
	uint64_t operations = 0;
	unsigned int dispatch_count = 0;
	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunFieldKernel(a, b, out, error, &dispatch_seconds, function_name, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalFieldBenchJson(operation, 0, sample_count, min_ms, dispatch_stats, 0.0, 0.0, false, true, error);
			return MetalFieldBenchJson(operation, operations ? operations : sample_count, sample_count, min_ms, dispatch_stats, seconds, 0.0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += sample_count;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	for (unsigned int i = 0; i < sample_count; ++i)
	{
		FieldElement expected = expected_fn(a[i], b[i]);
		if (out[i] != expected)
		{
			std::string reason = "mismatch at vector " + std::to_string(i) +
				": got " + FieldToHex(out[i]) + " expected " + FieldToHex(expected);
			return MetalFieldBenchJson(operation, operations, sample_count, min_ms, dispatch_stats, seconds, 0.0, false, false, reason);
		}
	}

	double ops_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	return MetalFieldBenchJson(operation, operations, sample_count, min_ms, dispatch_stats, seconds, ops_per_sec, true, false, "");
}

std::string RCKMetalFieldAddBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit)
{
	return RunMetalFieldBenchJson("field_add_mod_p", "field_add_mod_p", iterations, min_ms, 0x1234ULL, 0xBEEFULL, false, ExpectedAdd, threadgroup_limit);
}

std::string RCKMetalFieldSubBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit)
{
	return RunMetalFieldBenchJson("field_sub_mod_p", "field_sub_mod_p", iterations, min_ms, 0x51BULL, 0xA7BULL, false, ExpectedSub, threadgroup_limit);
}

std::string RCKMetalFieldDoubleBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit)
{
	return RunMetalFieldBenchJson("field_double_mod_p", "field_double_mod_p", iterations, min_ms, 0xD00BULL, 0, true, ExpectedDouble, threadgroup_limit);
}

std::string RCKMetalFieldMul4BenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit)
{
	return RunMetalFieldBenchJson("field_mul4_mod_p", "field_mul4_mod_p", iterations, min_ms, 0x4D14ULL, 0, true, ExpectedMul4, threadgroup_limit);
}

std::string RCKMetalFieldNegBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit)
{
	return RunMetalFieldBenchJson("field_neg_mod_p", "field_neg_mod_p", iterations, min_ms, 0x6E67ULL, 0, true, ExpectedNeg, threadgroup_limit);
}

std::string RCKMetalFieldMulBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit)
{
	return RunMetalFieldBenchJson("field_mul_mod_p", "field_mul_mod_p", iterations, min_ms, 0xCAFEULL, 0xBEEFULL, false, ExpectedMul, threadgroup_limit);
}

std::string RCKMetalFieldSquareBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit)
{
	return RunMetalFieldBenchJson("field_square_mod_p", "field_square_mod_p", iterations, min_ms, 0x5A5AULL, 0, true, ExpectedSquare, threadgroup_limit);
}

std::string RCKMetalFieldSquareMulBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit)
{
	return RunMetalFieldBenchJson("field_square_mul_mod_p", "field_square_mul_mod_p", iterations, min_ms, 0x5A5AULL, 0xC0DEULL, false, ExpectedSquareMul, threadgroup_limit);
}
