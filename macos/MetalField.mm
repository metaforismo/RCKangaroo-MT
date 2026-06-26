#include "macos/MetalField.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <array>
#include <chrono>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <thread>
#include <vector>

#include "Ec.h"
#include "macos/MetalFieldKernels.h"

typedef std::array<uint64_t, 4> FieldElement;

static constexpr unsigned int kDefaultMetalFieldThreadgroupLimit = 256;
static constexpr unsigned int kDefaultMetalDp12StreamThreadgroupLimit = 128;
static constexpr unsigned int kDefaultMetalTargetLookupThreadgroupLimit = 64;
static constexpr unsigned int kDefaultMetalPersistentTargetLookupLargeThreadgroupLimit = 1024;
static constexpr unsigned int kDefaultMetalPersistentTargetLookupFilterLargeThreadgroupLimit = 512;
static constexpr size_t kDefaultMetalPersistentTargetLookupLargeTargetThreshold = 16777216;
static constexpr size_t kMinValidationSamplesPerWorker = 1024;

struct MetalDispatchStats
{
	unsigned int threadgroup_limit = 0;
	unsigned int thread_execution_width = 0;
	unsigned int max_threads_per_threadgroup = 0;
	unsigned int threads_per_threadgroup = 0;
};

struct TargetLookupKeyHost
{
	uint64_t x[4];
	uint32_t parity;
};

struct TargetLookupBucketHost
{
	TargetLookupKeyHost key;
	uint32_t target_index;
	uint32_t occupied;
};

struct TargetLookupCompactBucketHost
{
	uint64_t hash;
	uint32_t target_index;
	uint32_t occupied;
};

struct TargetLookupTag32BucketHost
{
	uint32_t tag;
	uint32_t target_index;
};

static const uint32_t kTargetLookupEmptyIndex = 0xFFFFFFFFU;

static_assert(sizeof(TargetLookupKeyHost) == 40, "Metal target lookup key layout drifted");
static_assert(sizeof(TargetLookupBucketHost) == 48, "Metal target lookup bucket layout drifted");
static_assert(sizeof(TargetLookupCompactBucketHost) == 16, "Metal compact target lookup bucket layout drifted");
static_assert(sizeof(TargetLookupTag32BucketHost) == 8, "Metal tag32 target lookup bucket layout drifted");

static unsigned int ValidationWorkerOverride()
{
	const char* raw = getenv("RCK_VALIDATION_WORKERS");
	if (!raw || !*raw)
		return 0;

	char* end = NULL;
	unsigned long parsed = strtoul(raw, &end, 10);
	if (end == raw || *end != '\0' || parsed == 0)
		return 0;
	if (parsed > 1024UL)
		parsed = 1024UL;
	return (unsigned int)parsed;
}

static unsigned int ValidationWorkerCount(size_t sample_count)
{
	unsigned int worker_count = ValidationWorkerOverride();
	if (worker_count == 0)
		worker_count = std::thread::hardware_concurrency();
	if (worker_count == 0)
		worker_count = 1;
	size_t sample_limited_workers = sample_count / kMinValidationSamplesPerWorker;
	if (sample_limited_workers == 0)
		sample_limited_workers = 1;
	if ((size_t)worker_count > sample_limited_workers)
		worker_count = (unsigned int)sample_limited_workers;
	return worker_count == 0 ? 1 : worker_count;
}

template <typename Func>
static void ParallelForSamples(size_t sample_count, Func func)
{
	unsigned int worker_count = ValidationWorkerCount(sample_count);
	if (worker_count <= 1 || sample_count == 0)
	{
		func(0, sample_count, 0);
		return;
	}

	std::vector<std::thread> workers;
	workers.reserve(worker_count - 1);
	for (unsigned int worker = 0; worker + 1 < worker_count; ++worker)
	{
		size_t begin = (sample_count * worker) / worker_count;
		size_t end = (sample_count * (worker + 1)) / worker_count;
		workers.emplace_back([=, &func]() {
			func(begin, end, worker);
		});
	}

	size_t begin = (sample_count * (worker_count - 1)) / worker_count;
	func(begin, sample_count, worker_count - 1);
	for (std::thread& worker : workers)
		worker.join();
}

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

static FieldElement CpuFieldOne()
{
	return FieldElement{1, 0, 0, 0};
}

static FieldElement CpuFieldInv(const FieldElement& a)
{
	EcInt value;
	for (size_t limb = 0; limb < 4; ++limb)
		value.data[limb] = a[limb];
	value.data[4] = 0;
	value.InvModP();
	return FieldElement{value.data[0], value.data[1], value.data[2], value.data[3]};
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

struct CpuXyzzPoint
{
	FieldElement x;
	FieldElement y;
	FieldElement zz;
	FieldElement zzz;
	bool infinity = false;
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

static CpuXyzzPoint CpuXyzzFromJacobian(const CpuJacobianPoint& p)
{
	CpuXyzzPoint out;
	out.x = p.x;
	out.y = p.y;
	if (p.infinity)
	{
		out.zz = {0, 0, 0, 0};
		out.zzz = {0, 0, 0, 0};
		out.infinity = true;
		return out;
	}
	out.zz = CpuFieldSquare(p.z);
	out.zzz = CpuFieldMul(out.zz, p.z);
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

static CpuXyzzPoint CpuXyzzInfinity()
{
	CpuXyzzPoint out;
	out.x = {0, 0, 0, 0};
	out.y = {0, 0, 0, 0};
	out.zz = {0, 0, 0, 0};
	out.zzz = {0, 0, 0, 0};
	out.infinity = true;
	return out;
}

static CpuXyzzPoint CpuXyzzFromAffine(const CpuAffinePoint& q)
{
	CpuXyzzPoint out;
	out.x = q.x;
	out.y = q.y;
	out.zz = {1, 0, 0, 0};
	out.zzz = {1, 0, 0, 0};
	out.infinity = false;
	return out;
}

static CpuXyzzPoint CpuXyzzDouble(const CpuXyzzPoint& p)
{
	if (p.infinity || CpuFieldIsZero(p.y))
		return CpuXyzzInfinity();

	FieldElement xx = CpuFieldSquare(p.x);
	FieldElement yy = CpuFieldSquare(p.y);
	FieldElement yyyy = CpuFieldSquare(yy);
	FieldElement s = CpuFieldDouble(CpuFieldSub(CpuFieldSub(CpuFieldSquare(CpuFieldAdd(p.x, yy)), xx), yyyy));
	FieldElement m = CpuFieldAdd(CpuFieldDouble(xx), xx);
	FieldElement t = CpuFieldSub(CpuFieldSquare(m), CpuFieldDouble(s));
	FieldElement eight_yyyy = CpuFieldDouble(CpuFieldDouble(CpuFieldDouble(yyyy)));
	FieldElement four_yy = CpuFieldDouble(CpuFieldDouble(yy));
	FieldElement eight_yyy = CpuFieldDouble(CpuFieldDouble(CpuFieldDouble(CpuFieldMul(yy, p.y))));

	CpuXyzzPoint out;
	out.x = t;
	out.y = CpuFieldSub(CpuFieldMul(m, CpuFieldSub(s, t)), eight_yyyy);
	out.zz = CpuFieldMul(four_yy, p.zz);
	out.zzz = CpuFieldMul(eight_yyy, p.zzz);
	out.infinity = false;
	return out;
}

static CpuXyzzPoint CpuXyzzAddAffine(const CpuXyzzPoint& p, const CpuAffinePoint& q)
{
	if (p.infinity)
		return CpuXyzzFromAffine(q);

	FieldElement u2 = CpuFieldMul(q.x, p.zz);
	FieldElement s2 = CpuFieldMul(q.y, p.zzz);
	FieldElement h = CpuFieldSub(u2, p.x);
	FieldElement r = CpuFieldSub(s2, p.y);

	if (CpuFieldIsZero(h))
	{
		if (CpuFieldIsZero(r))
			return CpuXyzzDouble(p);
		return CpuXyzzInfinity();
	}

	FieldElement hh = CpuFieldSquare(h);
	FieldElement hhh = CpuFieldMul(hh, h);
	FieldElement v = CpuFieldMul(p.x, hh);
	FieldElement x3 = CpuFieldSub(CpuFieldSub(CpuFieldSquare(r), hhh), CpuFieldDouble(v));
	FieldElement y3 = CpuFieldSub(CpuFieldMul(r, CpuFieldSub(v, x3)), CpuFieldMul(p.y, hhh));

	CpuXyzzPoint out;
	out.x = x3;
	out.y = y3;
	out.zz = CpuFieldMul(p.zz, hh);
	out.zzz = CpuFieldMul(p.zzz, hhh);
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

static bool CpuXyzzMatches(const CpuXyzzPoint& a, const CpuXyzzPoint& b)
{
	if (a.infinity != b.infinity)
		return false;
	if (a.infinity)
		return true;
	return a.x == b.x && a.y == b.y && a.zz == b.zz && a.zzz == b.zzz;
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

static std::string MetalTargetLookupBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int target_count,
	unsigned int query_count,
	unsigned int expected_hits,
	unsigned int hit_count,
	uint64_t target_table_buckets,
	uint64_t target_table_bytes,
	unsigned int min_ms,
	const MetalDispatchStats& dispatch_stats,
	double seconds,
	double lookups_per_sec,
	uint64_t target_lookup_checksum,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	unsigned int miss_count = query_count >= hit_count ? query_count - hit_count : 0;
	double bytes_per_target = target_count ? (double)target_table_bytes / (double)target_count : 0.0;
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"lookup_layout\":\"open_address_exact256\",";
	oss << "\"target_key\":\"x256_y_parity\",";
	oss << "\"candidate_verification\":\"exact_key_equality\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << query_count << ",";
	oss << "\"target_count\":" << target_count << ",";
	oss << "\"query_count\":" << query_count << ",";
	oss << "\"expected_hits\":" << expected_hits << ",";
	oss << "\"hit_count\":" << hit_count << ",";
	oss << "\"miss_count\":" << miss_count << ",";
	oss << "\"target_table_buckets\":" << target_table_buckets << ",";
	oss << "\"target_table_bytes\":" << target_table_bytes << ",";
	oss << "\"bytes_per_target\":" << bytes_per_target << ",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"threadgroup_limit\":" << dispatch_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << dispatch_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << dispatch_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << dispatch_stats.threads_per_threadgroup << ",";
	oss << "\"seconds\":" << seconds << ",";
	oss << "\"lookups_per_sec\":" << lookups_per_sec << ",";
	oss << "\"ops_per_sec\":" << lookups_per_sec << ",";
	oss << "\"target_lookup_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << target_lookup_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string MetalTargetLookupCompactBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int target_count,
	unsigned int query_count,
	unsigned int expected_hits,
	unsigned int hit_count,
	uint64_t target_table_buckets,
	uint64_t target_key_bytes,
	uint64_t target_bucket_bytes,
	unsigned int min_ms,
	const MetalDispatchStats& dispatch_stats,
	double seconds,
	double lookups_per_sec,
	uint64_t target_lookup_checksum,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	unsigned int miss_count = query_count >= hit_count ? query_count - hit_count : 0;
	uint64_t target_table_bytes = target_key_bytes + target_bucket_bytes;
	double bytes_per_target = target_count ? (double)target_table_bytes / (double)target_count : 0.0;
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"lookup_layout\":\"open_address_hash64_index_exact256\",";
	oss << "\"target_key\":\"x256_y_parity\",";
	oss << "\"candidate_verification\":\"hash64_prefilter_then_exact_key_equality\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << query_count << ",";
	oss << "\"target_count\":" << target_count << ",";
	oss << "\"query_count\":" << query_count << ",";
	oss << "\"expected_hits\":" << expected_hits << ",";
	oss << "\"hit_count\":" << hit_count << ",";
	oss << "\"miss_count\":" << miss_count << ",";
	oss << "\"target_table_buckets\":" << target_table_buckets << ",";
	oss << "\"target_key_bytes\":" << target_key_bytes << ",";
	oss << "\"target_bucket_bytes\":" << target_bucket_bytes << ",";
	oss << "\"target_table_bytes\":" << target_table_bytes << ",";
	oss << "\"bytes_per_target\":" << bytes_per_target << ",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"threadgroup_limit\":" << dispatch_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << dispatch_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << dispatch_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << dispatch_stats.threads_per_threadgroup << ",";
	oss << "\"seconds\":" << seconds << ",";
	oss << "\"lookups_per_sec\":" << lookups_per_sec << ",";
	oss << "\"ops_per_sec\":" << lookups_per_sec << ",";
	oss << "\"target_lookup_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << target_lookup_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string MetalTargetLookupTag32BenchJson(const char* operation,
	uint64_t iterations,
	unsigned int target_count,
	unsigned int query_count,
	unsigned int expected_hits,
	unsigned int hit_count,
	uint64_t target_table_buckets,
	uint64_t target_key_bytes,
	uint64_t target_bucket_bytes,
	unsigned int min_ms,
	const MetalDispatchStats& dispatch_stats,
	double seconds,
	double lookups_per_sec,
	uint64_t target_lookup_checksum,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	unsigned int miss_count = query_count >= hit_count ? query_count - hit_count : 0;
	uint64_t target_table_bytes = target_key_bytes + target_bucket_bytes;
	double bytes_per_target = target_count ? (double)target_table_bytes / (double)target_count : 0.0;
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"lookup_layout\":\"open_address_tag32_index_exact256\",";
	oss << "\"target_key\":\"x256_y_parity\",";
	oss << "\"candidate_verification\":\"tag32_prefilter_then_exact_key_equality\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << query_count << ",";
	oss << "\"target_count\":" << target_count << ",";
	oss << "\"query_count\":" << query_count << ",";
	oss << "\"expected_hits\":" << expected_hits << ",";
	oss << "\"hit_count\":" << hit_count << ",";
	oss << "\"miss_count\":" << miss_count << ",";
	oss << "\"target_table_buckets\":" << target_table_buckets << ",";
	oss << "\"target_key_bytes\":" << target_key_bytes << ",";
	oss << "\"target_bucket_bytes\":" << target_bucket_bytes << ",";
	oss << "\"target_table_bytes\":" << target_table_bytes << ",";
	oss << "\"bytes_per_target\":" << bytes_per_target << ",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"threadgroup_limit\":" << dispatch_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << dispatch_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << dispatch_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << dispatch_stats.threads_per_threadgroup << ",";
	oss << "\"seconds\":" << seconds << ",";
	oss << "\"lookups_per_sec\":" << lookups_per_sec << ",";
	oss << "\"ops_per_sec\":" << lookups_per_sec << ",";
	oss << "\"target_lookup_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << target_lookup_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string MetalTargetLookupTag32FilterBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int target_count,
	unsigned int query_count,
	unsigned int expected_hits,
	unsigned int hit_count,
	unsigned int filter_positive_count,
	unsigned int filter_false_positive_count,
	uint64_t target_table_buckets,
	uint64_t target_key_bytes,
	uint64_t target_bucket_bytes,
	uint64_t target_filter_bucket_bytes,
	unsigned int min_ms,
	const MetalDispatchStats& dispatch_stats,
	double filter_seconds,
	double exact_verify_seconds,
	double seconds,
	double lookups_per_sec,
	uint64_t target_lookup_checksum,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	unsigned int miss_count = query_count >= hit_count ? query_count - hit_count : 0;
	uint64_t exact_host_table_bytes = target_key_bytes + target_bucket_bytes;
	uint64_t target_table_bytes = target_filter_bucket_bytes;
	double bytes_per_target = target_count ? (double)target_table_bytes / (double)target_count : 0.0;
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"lookup_layout\":\"open_address_tag32_filter_exact256\",";
	oss << "\"target_key\":\"x256_y_parity\",";
	oss << "\"candidate_verification\":\"tag32_filter_then_cpu_exact_key_equality\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << query_count << ",";
	oss << "\"target_count\":" << target_count << ",";
	oss << "\"query_count\":" << query_count << ",";
	oss << "\"expected_hits\":" << expected_hits << ",";
	oss << "\"hit_count\":" << hit_count << ",";
	oss << "\"miss_count\":" << miss_count << ",";
	oss << "\"filter_positive_count\":" << filter_positive_count << ",";
	oss << "\"filter_false_positive_count\":" << filter_false_positive_count << ",";
	oss << "\"target_table_buckets\":" << target_table_buckets << ",";
	oss << "\"target_key_bytes\":" << target_key_bytes << ",";
	oss << "\"target_bucket_bytes\":" << target_bucket_bytes << ",";
	oss << "\"target_filter_bucket_bytes\":" << target_filter_bucket_bytes << ",";
	oss << "\"target_table_bytes\":" << target_table_bytes << ",";
	oss << "\"exact_host_table_bytes\":" << exact_host_table_bytes << ",";
	oss << "\"bytes_per_target\":" << bytes_per_target << ",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"threadgroup_limit\":" << dispatch_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << dispatch_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << dispatch_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << dispatch_stats.threads_per_threadgroup << ",";
	oss << "\"filter_seconds\":" << filter_seconds << ",";
	oss << "\"exact_verify_seconds\":" << exact_verify_seconds << ",";
	oss << "\"seconds\":" << seconds << ",";
	oss << "\"lookups_per_sec\":" << lookups_per_sec << ",";
	oss << "\"ops_per_sec\":" << lookups_per_sec << ",";
	oss << "\"target_lookup_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << target_lookup_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string MetalTargetLookupTag32FilterPersistentBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int target_count,
	unsigned int query_count,
	unsigned int expected_hits,
	unsigned int hit_count,
	unsigned int filter_positive_count,
	unsigned int filter_false_positive_count,
	uint64_t target_table_buckets,
	uint64_t target_key_bytes,
	uint64_t target_bucket_bytes,
	uint64_t target_filter_bucket_bytes,
	unsigned int min_ms,
	const MetalDispatchStats& dispatch_stats,
	double metal_setup_seconds,
	double dispatch_seconds,
	double exact_verify_seconds,
	double total_seconds,
	double dispatch_lookups_per_sec,
	double lookups_per_sec,
	uint64_t target_lookup_checksum,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	unsigned int miss_count = query_count >= hit_count ? query_count - hit_count : 0;
	uint64_t exact_host_table_bytes = target_key_bytes + target_bucket_bytes;
	uint64_t target_table_bytes = target_filter_bucket_bytes;
	double bytes_per_target = target_count ? (double)target_table_bytes / (double)target_count : 0.0;
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"lookup_layout\":\"open_address_tag32_filter_exact256\",";
	oss << "\"buffer_lifetime\":\"persistent\",";
	oss << "\"target_key\":\"x256_y_parity\",";
	oss << "\"candidate_verification\":\"tag32_filter_then_cpu_exact_key_equality\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << query_count << ",";
	oss << "\"target_count\":" << target_count << ",";
	oss << "\"query_count\":" << query_count << ",";
	oss << "\"expected_hits\":" << expected_hits << ",";
	oss << "\"hit_count\":" << hit_count << ",";
	oss << "\"miss_count\":" << miss_count << ",";
	oss << "\"filter_positive_count\":" << filter_positive_count << ",";
	oss << "\"filter_false_positive_count\":" << filter_false_positive_count << ",";
	oss << "\"target_table_buckets\":" << target_table_buckets << ",";
	oss << "\"target_key_bytes\":" << target_key_bytes << ",";
	oss << "\"target_bucket_bytes\":" << target_bucket_bytes << ",";
	oss << "\"target_filter_bucket_bytes\":" << target_filter_bucket_bytes << ",";
	oss << "\"target_table_bytes\":" << target_table_bytes << ",";
	oss << "\"exact_host_table_bytes\":" << exact_host_table_bytes << ",";
	oss << "\"bytes_per_target\":" << bytes_per_target << ",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"threadgroup_limit\":" << dispatch_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << dispatch_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << dispatch_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << dispatch_stats.threads_per_threadgroup << ",";
	oss << "\"metal_setup_seconds\":" << metal_setup_seconds << ",";
	oss << "\"dispatch_seconds\":" << dispatch_seconds << ",";
	oss << "\"exact_verify_seconds\":" << exact_verify_seconds << ",";
	oss << "\"seconds\":" << total_seconds << ",";
	oss << "\"dispatch_lookups_per_sec\":" << dispatch_lookups_per_sec << ",";
	oss << "\"lookups_per_sec\":" << lookups_per_sec << ",";
	oss << "\"ops_per_sec\":" << lookups_per_sec << ",";
	oss << "\"target_lookup_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << target_lookup_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string MetalTargetLookupTag16FilterPersistentBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int target_count,
	unsigned int query_count,
	unsigned int expected_hits,
	unsigned int hit_count,
	unsigned int filter_positive_count,
	unsigned int filter_false_positive_count,
	uint64_t target_table_buckets,
	uint64_t target_key_bytes,
	uint64_t target_bucket_bytes,
	uint64_t target_filter_bucket_bytes,
	unsigned int min_ms,
	const MetalDispatchStats& dispatch_stats,
	double metal_setup_seconds,
	double dispatch_seconds,
	double exact_verify_seconds,
	double total_seconds,
	double dispatch_lookups_per_sec,
	double lookups_per_sec,
	uint64_t target_lookup_checksum,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	unsigned int miss_count = query_count >= hit_count ? query_count - hit_count : 0;
	uint64_t exact_host_table_bytes = target_key_bytes + target_bucket_bytes;
	uint64_t target_table_bytes = target_filter_bucket_bytes;
	double bytes_per_target = target_count ? (double)target_table_bytes / (double)target_count : 0.0;
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"lookup_layout\":\"open_address_tag16_filter_exact256\",";
	oss << "\"buffer_lifetime\":\"persistent\",";
	oss << "\"target_key\":\"x256_y_parity\",";
	oss << "\"candidate_verification\":\"tag16_filter_then_cpu_exact_key_equality\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << query_count << ",";
	oss << "\"target_count\":" << target_count << ",";
	oss << "\"query_count\":" << query_count << ",";
	oss << "\"expected_hits\":" << expected_hits << ",";
	oss << "\"hit_count\":" << hit_count << ",";
	oss << "\"miss_count\":" << miss_count << ",";
	oss << "\"filter_positive_count\":" << filter_positive_count << ",";
	oss << "\"filter_false_positive_count\":" << filter_false_positive_count << ",";
	oss << "\"target_table_buckets\":" << target_table_buckets << ",";
	oss << "\"target_key_bytes\":" << target_key_bytes << ",";
	oss << "\"target_bucket_bytes\":" << target_bucket_bytes << ",";
	oss << "\"target_filter_bucket_bytes\":" << target_filter_bucket_bytes << ",";
	oss << "\"target_table_bytes\":" << target_table_bytes << ",";
	oss << "\"exact_host_table_bytes\":" << exact_host_table_bytes << ",";
	oss << "\"bytes_per_target\":" << bytes_per_target << ",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"threadgroup_limit\":" << dispatch_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << dispatch_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << dispatch_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << dispatch_stats.threads_per_threadgroup << ",";
	oss << "\"metal_setup_seconds\":" << metal_setup_seconds << ",";
	oss << "\"dispatch_seconds\":" << dispatch_seconds << ",";
	oss << "\"exact_verify_seconds\":" << exact_verify_seconds << ",";
	oss << "\"seconds\":" << total_seconds << ",";
	oss << "\"dispatch_lookups_per_sec\":" << dispatch_lookups_per_sec << ",";
	oss << "\"lookups_per_sec\":" << lookups_per_sec << ",";
	oss << "\"ops_per_sec\":" << lookups_per_sec << ",";
	oss << "\"target_lookup_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << target_lookup_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string MetalTargetLookupTag16HashFilterPersistentBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int target_count,
	unsigned int query_count,
	unsigned int expected_hits,
	unsigned int hit_count,
	unsigned int filter_positive_count,
	unsigned int filter_false_positive_count,
	uint64_t target_table_buckets,
	uint64_t target_key_bytes,
	uint64_t target_bucket_bytes,
	uint64_t target_filter_bucket_bytes,
	uint64_t target_query_hash_bytes,
	unsigned int min_ms,
	const MetalDispatchStats& dispatch_stats,
	double metal_setup_seconds,
	double dispatch_seconds,
	double exact_verify_seconds,
	double total_seconds,
	double dispatch_lookups_per_sec,
	double lookups_per_sec,
	uint64_t target_lookup_checksum,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	unsigned int miss_count = query_count >= hit_count ? query_count - hit_count : 0;
	uint64_t exact_host_table_bytes = target_key_bytes + target_bucket_bytes;
	uint64_t target_table_bytes = target_filter_bucket_bytes;
	double bytes_per_target = target_count ? (double)target_table_bytes / (double)target_count : 0.0;
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"lookup_layout\":\"open_address_tag16_hash_filter_exact256\",";
	oss << "\"buffer_lifetime\":\"persistent\",";
	oss << "\"query_input\":\"hash64\",";
	oss << "\"target_key\":\"x256_y_parity\",";
	oss << "\"candidate_verification\":\"tag16_hash_filter_then_cpu_exact_key_equality\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << query_count << ",";
	oss << "\"target_count\":" << target_count << ",";
	oss << "\"query_count\":" << query_count << ",";
	oss << "\"expected_hits\":" << expected_hits << ",";
	oss << "\"hit_count\":" << hit_count << ",";
	oss << "\"miss_count\":" << miss_count << ",";
	oss << "\"filter_positive_count\":" << filter_positive_count << ",";
	oss << "\"filter_false_positive_count\":" << filter_false_positive_count << ",";
	oss << "\"target_table_buckets\":" << target_table_buckets << ",";
	oss << "\"target_key_bytes\":" << target_key_bytes << ",";
	oss << "\"target_bucket_bytes\":" << target_bucket_bytes << ",";
	oss << "\"target_filter_bucket_bytes\":" << target_filter_bucket_bytes << ",";
	oss << "\"target_query_hash_bytes\":" << target_query_hash_bytes << ",";
	oss << "\"target_table_bytes\":" << target_table_bytes << ",";
	oss << "\"exact_host_table_bytes\":" << exact_host_table_bytes << ",";
	oss << "\"bytes_per_target\":" << bytes_per_target << ",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"threadgroup_limit\":" << dispatch_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << dispatch_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << dispatch_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << dispatch_stats.threads_per_threadgroup << ",";
	oss << "\"metal_setup_seconds\":" << metal_setup_seconds << ",";
	oss << "\"dispatch_seconds\":" << dispatch_seconds << ",";
	oss << "\"exact_verify_seconds\":" << exact_verify_seconds << ",";
	oss << "\"seconds\":" << total_seconds << ",";
	oss << "\"dispatch_lookups_per_sec\":" << dispatch_lookups_per_sec << ",";
	oss << "\"lookups_per_sec\":" << lookups_per_sec << ",";
	oss << "\"ops_per_sec\":" << lookups_per_sec << ",";
	oss << "\"target_lookup_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << target_lookup_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string MetalTargetLookupTag32PersistentBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int target_count,
	unsigned int query_count,
	unsigned int expected_hits,
	unsigned int hit_count,
	uint64_t target_table_buckets,
	uint64_t target_key_bytes,
	uint64_t target_bucket_bytes,
	unsigned int min_ms,
	const MetalDispatchStats& dispatch_stats,
	double metal_setup_seconds,
	double dispatch_seconds,
	double total_seconds,
	double dispatch_lookups_per_sec,
	double lookups_per_sec,
	uint64_t target_lookup_checksum,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	unsigned int miss_count = query_count >= hit_count ? query_count - hit_count : 0;
	uint64_t target_table_bytes = target_key_bytes + target_bucket_bytes;
	double bytes_per_target = target_count ? (double)target_table_bytes / (double)target_count : 0.0;
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"lookup_layout\":\"open_address_tag32_index_exact256\",";
	oss << "\"buffer_lifetime\":\"persistent\",";
	oss << "\"target_key\":\"x256_y_parity\",";
	oss << "\"candidate_verification\":\"tag32_prefilter_then_exact_key_equality\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << query_count << ",";
	oss << "\"target_count\":" << target_count << ",";
	oss << "\"query_count\":" << query_count << ",";
	oss << "\"expected_hits\":" << expected_hits << ",";
	oss << "\"hit_count\":" << hit_count << ",";
	oss << "\"miss_count\":" << miss_count << ",";
	oss << "\"target_table_buckets\":" << target_table_buckets << ",";
	oss << "\"target_key_bytes\":" << target_key_bytes << ",";
	oss << "\"target_bucket_bytes\":" << target_bucket_bytes << ",";
	oss << "\"target_table_bytes\":" << target_table_bytes << ",";
	oss << "\"bytes_per_target\":" << bytes_per_target << ",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"threadgroup_limit\":" << dispatch_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << dispatch_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << dispatch_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << dispatch_stats.threads_per_threadgroup << ",";
	oss << "\"metal_setup_seconds\":" << metal_setup_seconds << ",";
	oss << "\"dispatch_seconds\":" << dispatch_seconds << ",";
	oss << "\"seconds\":" << total_seconds << ",";
	oss << "\"dispatch_lookups_per_sec\":" << dispatch_lookups_per_sec << ",";
	oss << "\"lookups_per_sec\":" << lookups_per_sec << ",";
	oss << "\"ops_per_sec\":" << lookups_per_sec << ",";
	oss << "\"target_lookup_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << target_lookup_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string CpuTargetLookupTag32BenchJson(const char* operation,
	uint64_t iterations,
	unsigned int target_count,
	unsigned int query_count,
	unsigned int expected_hits,
	unsigned int hit_count,
	uint64_t target_table_buckets,
	uint64_t target_key_bytes,
	uint64_t target_bucket_bytes,
	unsigned int min_ms,
	double seconds,
	double lookups_per_sec,
	uint64_t target_lookup_checksum,
	bool correctness,
	const std::string& reason)
{
	unsigned int miss_count = query_count >= hit_count ? query_count - hit_count : 0;
	uint64_t target_table_bytes = target_key_bytes + target_bucket_bytes;
	double bytes_per_target = target_count ? (double)target_table_bytes / (double)target_count : 0.0;
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"macos_cpu\",\"operation\":\"" << operation << "\",";
	oss << "\"lookup_layout\":\"open_address_tag32_index_exact256\",";
	oss << "\"lookup_engine\":\"cpu\",";
	oss << "\"target_key\":\"x256_y_parity\",";
	oss << "\"candidate_verification\":\"tag32_prefilter_then_exact_key_equality\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << query_count << ",";
	oss << "\"target_count\":" << target_count << ",";
	oss << "\"query_count\":" << query_count << ",";
	oss << "\"expected_hits\":" << expected_hits << ",";
	oss << "\"hit_count\":" << hit_count << ",";
	oss << "\"miss_count\":" << miss_count << ",";
	oss << "\"target_table_buckets\":" << target_table_buckets << ",";
	oss << "\"target_key_bytes\":" << target_key_bytes << ",";
	oss << "\"target_bucket_bytes\":" << target_bucket_bytes << ",";
	oss << "\"target_table_bytes\":" << target_table_bytes << ",";
	oss << "\"bytes_per_target\":" << bytes_per_target << ",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"seconds\":" << seconds << ",";
	oss << "\"lookups_per_sec\":" << lookups_per_sec << ",";
	oss << "\"ops_per_sec\":" << lookups_per_sec << ",";
	oss << "\"target_lookup_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << target_lookup_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":false";
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string MetalAffineScanTargetLookupTag32BenchJson(const char* operation,
	uint64_t iterations,
	unsigned int sample_count,
	unsigned int steps_per_sample,
	unsigned int jump_count,
	const char* jump_index_mode,
	const char* jump_mixer,
	const char* jump_schedule,
	uint64_t jump_histogram_min_bucket,
	uint64_t jump_histogram_max_bucket,
	uint64_t jump_histogram_max_deviation_ppm,
	uint64_t dp_distance_checksum,
	unsigned int dp_bits,
	unsigned int dp_count,
	uint64_t dp_checksum,
	unsigned int target_count,
	unsigned int requested_hits,
	unsigned int injected_hits,
	unsigned int dp_query_count,
	unsigned int hit_count,
	uint64_t target_table_buckets,
	uint64_t target_key_bytes,
	uint64_t target_bucket_bytes,
	unsigned int min_ms,
	const MetalDispatchStats& walk_stats,
	const MetalDispatchStats& lookup_stats,
	double walk_seconds,
	double affine_scan_seconds,
	double lookup_seconds,
	double validation_seconds,
	double ops_per_sec,
	double gpu_ops_per_sec,
	double lookups_per_sec,
	uint64_t target_lookup_checksum,
	bool correctness,
	bool skipped,
	const std::string& reason,
	unsigned int lookup_repeat = 1,
	const char* lookup_query_mode = "repeat",
	const char* lookup_engine = "gpu",
	const char* lookup_engine_effective = NULL,
	unsigned int filter_positive_count = 0,
	unsigned int filter_false_positive_count = 0,
	uint64_t target_filter_bucket_bytes = 0)
{
	if (!lookup_engine_effective)
		lookup_engine_effective = lookup_engine;
	bool lookup_uses_filter = strcmp(lookup_engine_effective, "gpu_filter") == 0;
	uint64_t query_count = (uint64_t)dp_query_count * (uint64_t)(lookup_repeat ? lookup_repeat : 1U);
	unsigned int miss_count = query_count >= hit_count ? (unsigned int)(query_count - hit_count) : 0;
	uint64_t exact_host_table_bytes = target_key_bytes + target_bucket_bytes;
	uint64_t target_table_bytes = lookup_uses_filter && target_filter_bucket_bytes ? target_filter_bucket_bytes : exact_host_table_bytes;
	double bytes_per_target = target_count ? (double)target_table_bytes / (double)target_count : 0.0;
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"state_layout\":\"xyzz\",";
	oss << "\"output_layout\":\"affine_dp_scan_target_lookup\",";
	oss << "\"affine_scan_mode\":\"cpu_batch_prod_zz_zzz\",";
	oss << "\"lookup_layout\":\"" << (lookup_uses_filter ? "open_address_tag32_filter_exact256" : "open_address_tag32_index_exact256") << "\",";
	oss << "\"target_key\":\"x256_y_parity\",";
	oss << "\"candidate_verification\":\"" << (lookup_uses_filter ? "tag32_filter_then_cpu_exact_key_equality" : "tag32_prefilter_then_exact_key_equality") << "\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << sample_count << ",";
	oss << "\"steps_per_sample\":" << steps_per_sample << ",";
	oss << "\"jump_count\":" << jump_count << ",";
	oss << "\"jump_index\":\"" << jump_index_mode << "\",";
	oss << "\"jump_mixer\":\"" << jump_mixer << "\",";
	oss << "\"jump_schedule\":\"" << jump_schedule << "\",";
	oss << "\"jump_histogram_min_bucket\":" << jump_histogram_min_bucket << ",";
	oss << "\"jump_histogram_max_bucket\":" << jump_histogram_max_bucket << ",";
	oss << "\"jump_histogram_max_deviation_ppm\":" << jump_histogram_max_deviation_ppm << ",";
	oss << "\"distance_tracking\":\"packet_distance_uint64\",";
	oss << "\"dp_distance_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_distance_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"dp_tracking\":\"affine_x256_y_parity_cpu_batch\",";
	oss << "\"dp_bits\":" << dp_bits << ",";
	oss << "\"dp_count\":" << dp_count << ",";
	oss << "\"dp_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"target_count\":" << target_count << ",";
	oss << "\"requested_hits\":" << requested_hits << ",";
	oss << "\"injected_hits\":" << injected_hits << ",";
	oss << "\"lookup_repeat\":" << lookup_repeat << ",";
	oss << "\"lookup_query_mode\":\"" << lookup_query_mode << "\",";
	oss << "\"lookup_engine\":\"" << lookup_engine << "\",";
	oss << "\"lookup_engine_effective\":\"" << lookup_engine_effective << "\",";
	oss << "\"dp_query_count\":" << dp_query_count << ",";
	oss << "\"query_count\":" << query_count << ",";
	oss << "\"hit_count\":" << hit_count << ",";
	oss << "\"miss_count\":" << miss_count << ",";
	oss << "\"filter_positive_count\":" << filter_positive_count << ",";
	oss << "\"filter_false_positive_count\":" << filter_false_positive_count << ",";
	oss << "\"target_table_buckets\":" << target_table_buckets << ",";
	oss << "\"target_key_bytes\":" << target_key_bytes << ",";
	oss << "\"target_bucket_bytes\":" << target_bucket_bytes << ",";
	oss << "\"target_filter_bucket_bytes\":" << target_filter_bucket_bytes << ",";
	oss << "\"target_table_bytes\":" << target_table_bytes << ",";
	oss << "\"exact_host_table_bytes\":" << exact_host_table_bytes << ",";
	oss << "\"bytes_per_target\":" << bytes_per_target << ",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"threadgroup_limit\":" << walk_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << walk_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << walk_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << walk_stats.threads_per_threadgroup << ",";
	oss << "\"lookup_threadgroup_limit\":" << lookup_stats.threadgroup_limit << ",";
	oss << "\"lookup_thread_execution_width\":" << lookup_stats.thread_execution_width << ",";
	oss << "\"lookup_max_threads_per_threadgroup\":" << lookup_stats.max_threads_per_threadgroup << ",";
	oss << "\"lookup_threads_per_threadgroup\":" << lookup_stats.threads_per_threadgroup << ",";
	oss << "\"seconds\":" << walk_seconds << ",";
	oss << "\"affine_scan_seconds\":" << affine_scan_seconds << ",";
	oss << "\"lookup_seconds\":" << lookup_seconds << ",";
	oss << "\"validation_workers\":" << ValidationWorkerCount(sample_count) << ",";
	oss << "\"validation_seconds\":" << validation_seconds << ",";
	oss << "\"gpu_ops_per_sec\":" << gpu_ops_per_sec << ",";
	oss << "\"lookups_per_sec\":" << lookups_per_sec << ",";
	oss << "\"ops_per_sec\":" << ops_per_sec << ",";
	oss << "\"target_lookup_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << target_lookup_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string MetalJacobianWalkBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int sample_count,
	unsigned int steps_per_sample,
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
	oss << "\"steps_per_sample\":" << steps_per_sample << ",";
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

static std::string MetalJacobianJumpWalkBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int sample_count,
	unsigned int steps_per_sample,
	unsigned int jump_count,
	uint64_t distance_checksum,
	unsigned int dp_bits,
	unsigned int dp_count,
	uint64_t dp_checksum,
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
	oss << "\"steps_per_sample\":" << steps_per_sample << ",";
	oss << "\"jump_count\":" << jump_count << ",";
	oss << "\"distance_tracking\":\"uint64\",";
	oss << "\"distance_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << distance_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"dp_tracking\":\"projective_x_limb0\",";
	oss << "\"dp_bits\":" << dp_bits << ",";
	oss << "\"dp_count\":" << dp_count << ",";
	oss << "\"dp_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_checksum << std::dec << std::setfill(' ') << "\",";
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

static std::string MetalJacobianDynamicJumpWalkBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int sample_count,
	unsigned int steps_per_sample,
	unsigned int jump_count,
	const char* jump_index_mode,
	const char* jump_mixer,
	uint64_t jump_histogram_min_bucket,
	uint64_t jump_histogram_max_bucket,
	uint64_t jump_histogram_max_deviation_ppm,
	uint64_t distance_checksum,
	unsigned int dp_bits,
	unsigned int dp_count,
	uint64_t dp_checksum,
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
	oss << "\"steps_per_sample\":" << steps_per_sample << ",";
	oss << "\"jump_count\":" << jump_count << ",";
	oss << "\"jump_index\":\"" << jump_index_mode << "\",";
	oss << "\"jump_mixer\":\"" << jump_mixer << "\",";
	oss << "\"jump_histogram_min_bucket\":" << jump_histogram_min_bucket << ",";
	oss << "\"jump_histogram_max_bucket\":" << jump_histogram_max_bucket << ",";
	oss << "\"jump_histogram_max_deviation_ppm\":" << jump_histogram_max_deviation_ppm << ",";
	oss << "\"distance_tracking\":\"uint64\",";
	oss << "\"distance_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << distance_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"dp_tracking\":\"projective_x_limb0\",";
	oss << "\"dp_bits\":" << dp_bits << ",";
	oss << "\"dp_count\":" << dp_count << ",";
	oss << "\"dp_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_checksum << std::dec << std::setfill(' ') << "\",";
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

static std::string MetalJacobianDynamicCompactDpBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int sample_count,
	unsigned int steps_per_sample,
	unsigned int jump_count,
	const char* jump_index_mode,
	const char* jump_mixer,
	uint64_t jump_histogram_min_bucket,
	uint64_t jump_histogram_max_bucket,
	uint64_t jump_histogram_max_deviation_ppm,
	uint64_t distance_checksum,
	unsigned int dp_bits,
	unsigned int dp_count,
	uint64_t dp_checksum,
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
	oss << "\"steps_per_sample\":" << steps_per_sample << ",";
	oss << "\"jump_count\":" << jump_count << ",";
	oss << "\"jump_index\":\"" << jump_index_mode << "\",";
	oss << "\"jump_mixer\":\"" << jump_mixer << "\",";
	oss << "\"jump_histogram_min_bucket\":" << jump_histogram_min_bucket << ",";
	oss << "\"jump_histogram_max_bucket\":" << jump_histogram_max_bucket << ",";
	oss << "\"jump_histogram_max_deviation_ppm\":" << jump_histogram_max_deviation_ppm << ",";
	oss << "\"output_layout\":\"dp_compact\",";
	oss << "\"output_bytes_per_sample\":17,";
	oss << "\"distance_tracking\":\"uint64\",";
	oss << "\"distance_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << distance_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"dp_tracking\":\"projective_x_limb0\",";
	oss << "\"dp_bits\":" << dp_bits << ",";
	oss << "\"dp_count\":" << dp_count << ",";
	oss << "\"dp_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_checksum << std::dec << std::setfill(' ') << "\",";
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

static std::string MetalJacobianDynamicDpStreamBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int sample_count,
	unsigned int steps_per_sample,
	unsigned int jump_count,
	const char* jump_index_mode,
	const char* jump_mixer,
	uint64_t jump_histogram_min_bucket,
	uint64_t jump_histogram_max_bucket,
	uint64_t jump_histogram_max_deviation_ppm,
	unsigned int emitted_records,
	unsigned int dp_capacity,
	bool dp_stream_overflow,
	uint64_t dp_distance_checksum,
	unsigned int dp_bits,
	unsigned int dp_count,
	uint64_t dp_checksum,
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
	oss << "\"steps_per_sample\":" << steps_per_sample << ",";
	oss << "\"jump_count\":" << jump_count << ",";
	oss << "\"jump_index\":\"" << jump_index_mode << "\",";
	oss << "\"jump_mixer\":\"" << jump_mixer << "\",";
	oss << "\"jump_histogram_min_bucket\":" << jump_histogram_min_bucket << ",";
	oss << "\"jump_histogram_max_bucket\":" << jump_histogram_max_bucket << ",";
	oss << "\"jump_histogram_max_deviation_ppm\":" << jump_histogram_max_deviation_ppm << ",";
	oss << "\"output_layout\":\"dp_stream\",";
	oss << "\"output_bytes_per_record\":20,";
	oss << "\"output_bytes_total\":" << (uint64_t)emitted_records * 20ULL << ",";
	oss << "\"emitted_records\":" << emitted_records << ",";
	oss << "\"dp_capacity\":" << dp_capacity << ",";
	oss << "\"dp_stream_overflow\":" << (dp_stream_overflow ? "true" : "false") << ",";
	oss << "\"distance_tracking\":\"dp_stream_uint64\",";
	oss << "\"dp_distance_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_distance_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"dp_tracking\":\"projective_x_limb0\",";
	oss << "\"dp_bits\":" << dp_bits << ",";
	oss << "\"dp_count\":" << dp_count << ",";
	oss << "\"dp_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_checksum << std::dec << std::setfill(' ') << "\",";
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

static std::string MetalJacobianDynamicDpStreamXyzzBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int sample_count,
	unsigned int steps_per_sample,
	unsigned int jump_count,
	const char* jump_index_mode,
	const char* jump_mixer,
	const char* jump_schedule,
	uint64_t jump_histogram_min_bucket,
	uint64_t jump_histogram_max_bucket,
	uint64_t jump_histogram_max_deviation_ppm,
	unsigned int emitted_records,
	unsigned int dp_capacity,
	bool dp_stream_overflow,
	uint64_t dp_distance_checksum,
	unsigned int dp_bits,
	unsigned int dp_count,
	uint64_t dp_checksum,
	unsigned int min_ms,
	const MetalDispatchStats& dispatch_stats,
	double seconds,
	double validation_seconds,
	double ops_per_sec,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"state_layout\":\"xyzz\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << sample_count << ",";
	oss << "\"steps_per_sample\":" << steps_per_sample << ",";
	oss << "\"jump_count\":" << jump_count << ",";
	oss << "\"jump_index\":\"" << jump_index_mode << "\",";
	oss << "\"jump_mixer\":\"" << jump_mixer << "\",";
	oss << "\"jump_schedule\":\"" << jump_schedule << "\",";
	oss << "\"jump_histogram_min_bucket\":" << jump_histogram_min_bucket << ",";
	oss << "\"jump_histogram_max_bucket\":" << jump_histogram_max_bucket << ",";
	oss << "\"jump_histogram_max_deviation_ppm\":" << jump_histogram_max_deviation_ppm << ",";
	oss << "\"output_layout\":\"dp_stream\",";
	oss << "\"output_bytes_per_record\":20,";
	oss << "\"output_bytes_total\":" << (uint64_t)emitted_records * 20ULL << ",";
	oss << "\"emitted_records\":" << emitted_records << ",";
	oss << "\"dp_capacity\":" << dp_capacity << ",";
	oss << "\"dp_stream_overflow\":" << (dp_stream_overflow ? "true" : "false") << ",";
	oss << "\"distance_tracking\":\"dp_stream_uint64\",";
	oss << "\"dp_distance_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_distance_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"dp_tracking\":\"projective_x_limb0\",";
	oss << "\"dp_bits\":" << dp_bits << ",";
	oss << "\"dp_count\":" << dp_count << ",";
	oss << "\"dp_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"threadgroup_limit\":" << dispatch_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << dispatch_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << dispatch_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << dispatch_stats.threads_per_threadgroup << ",";
	oss << "\"seconds\":" << seconds << ",";
	oss << "\"validation_workers\":" << ValidationWorkerCount(sample_count) << ",";
	oss << "\"validation_seconds\":" << validation_seconds << ",";
	oss << "\"ops_per_sec\":" << ops_per_sec << ",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string MetalJacobianDynamicDpStreamXyzzAffineScanBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int sample_count,
	unsigned int steps_per_sample,
	unsigned int jump_count,
	const char* jump_index_mode,
	const char* jump_mixer,
	const char* jump_schedule,
	uint64_t jump_histogram_min_bucket,
	uint64_t jump_histogram_max_bucket,
	uint64_t jump_histogram_max_deviation_ppm,
	uint64_t dp_distance_checksum,
	unsigned int dp_bits,
	unsigned int dp_count,
	uint64_t dp_checksum,
	unsigned int min_ms,
	const MetalDispatchStats& dispatch_stats,
	double seconds,
	double affine_scan_seconds,
	double validation_seconds,
	double ops_per_sec,
	double gpu_ops_per_sec,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"state_layout\":\"xyzz\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << sample_count << ",";
	oss << "\"steps_per_sample\":" << steps_per_sample << ",";
	oss << "\"jump_count\":" << jump_count << ",";
	oss << "\"jump_index\":\"" << jump_index_mode << "\",";
	oss << "\"jump_mixer\":\"" << jump_mixer << "\",";
	oss << "\"jump_schedule\":\"" << jump_schedule << "\",";
	oss << "\"jump_histogram_min_bucket\":" << jump_histogram_min_bucket << ",";
	oss << "\"jump_histogram_max_bucket\":" << jump_histogram_max_bucket << ",";
	oss << "\"jump_histogram_max_deviation_ppm\":" << jump_histogram_max_deviation_ppm << ",";
	oss << "\"output_layout\":\"affine_dp_scan\",";
	oss << "\"affine_scan_mode\":\"cpu_batch_prod_zz_zzz\",";
	oss << "\"distance_tracking\":\"packet_distance_uint64\",";
	oss << "\"dp_distance_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_distance_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"dp_tracking\":\"affine_x_limb0_cpu_batch\",";
	oss << "\"dp_bits\":" << dp_bits << ",";
	oss << "\"dp_count\":" << dp_count << ",";
	oss << "\"dp_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"threadgroup_limit\":" << dispatch_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << dispatch_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << dispatch_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << dispatch_stats.threads_per_threadgroup << ",";
	oss << "\"seconds\":" << seconds << ",";
	oss << "\"affine_scan_seconds\":" << affine_scan_seconds << ",";
	oss << "\"validation_workers\":" << ValidationWorkerCount(sample_count) << ",";
	oss << "\"validation_seconds\":" << validation_seconds << ",";
	oss << "\"gpu_ops_per_sec\":" << gpu_ops_per_sec << ",";
	oss << "\"ops_per_sec\":" << ops_per_sec << ",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string MetalJacobianDynamicDpStreamXyzzChainBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int sample_count,
	unsigned int steps_per_sample,
	unsigned int packet_count,
	unsigned int jump_count,
	const char* jump_index_mode,
	const char* jump_mixer,
	const char* jump_schedule,
	uint64_t jump_histogram_min_bucket,
	uint64_t jump_histogram_max_bucket,
	uint64_t jump_histogram_max_deviation_ppm,
	unsigned int emitted_records,
	unsigned int dp_capacity,
	bool dp_stream_overflow,
	uint64_t dp_distance_checksum,
	unsigned int dp_bits,
	unsigned int dp_count,
	uint64_t dp_checksum,
	unsigned int min_ms,
	const MetalDispatchStats& dispatch_stats,
	double seconds,
	double validation_seconds,
	double ops_per_sec,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"state_layout\":\"xyzz\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << sample_count << ",";
	oss << "\"steps_per_sample\":" << steps_per_sample << ",";
	oss << "\"packet_count\":" << packet_count << ",";
	oss << "\"jump_count\":" << jump_count << ",";
	oss << "\"jump_index\":\"" << jump_index_mode << "\",";
	oss << "\"jump_mixer\":\"" << jump_mixer << "\",";
	oss << "\"jump_schedule\":\"" << jump_schedule << "\",";
	oss << "\"jump_histogram_min_bucket\":" << jump_histogram_min_bucket << ",";
	oss << "\"jump_histogram_max_bucket\":" << jump_histogram_max_bucket << ",";
	oss << "\"jump_histogram_max_deviation_ppm\":" << jump_histogram_max_deviation_ppm << ",";
	oss << "\"output_layout\":\"dp_stream\",";
	oss << "\"output_bytes_per_record\":20,";
	oss << "\"output_bytes_total\":" << (uint64_t)emitted_records * 20ULL << ",";
	oss << "\"emitted_records\":" << emitted_records << ",";
	oss << "\"dp_capacity\":" << dp_capacity << ",";
	oss << "\"dp_stream_overflow\":" << (dp_stream_overflow ? "true" : "false") << ",";
	oss << "\"distance_tracking\":\"dp_stream_cumulative_uint64\",";
	oss << "\"stream_indexing\":\"packet_sample_u32\",";
	oss << "\"dp_distance_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_distance_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"dp_tracking\":\"projective_x_limb0\",";
	oss << "\"dp_bits\":" << dp_bits << ",";
	oss << "\"dp_count\":" << dp_count << ",";
	oss << "\"dp_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"threadgroup_limit\":" << dispatch_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << dispatch_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << dispatch_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << dispatch_stats.threads_per_threadgroup << ",";
	oss << "\"seconds\":" << seconds << ",";
	oss << "\"validation_workers\":" << ValidationWorkerCount(sample_count) << ",";
	oss << "\"validation_seconds\":" << validation_seconds << ",";
	oss << "\"ops_per_sec\":" << ops_per_sec << ",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string MetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int sample_count,
	unsigned int steps_per_sample,
	unsigned int packet_count,
	unsigned int packets_per_round,
	unsigned int round_count,
	unsigned int jump_count,
	const char* jump_index_mode,
	const char* jump_mixer,
	const char* jump_schedule,
	uint64_t jump_histogram_min_bucket,
	uint64_t jump_histogram_max_bucket,
	uint64_t jump_histogram_max_deviation_ppm,
	unsigned int emitted_records,
	unsigned int dp_capacity,
	bool dp_stream_overflow,
	uint64_t dp_distance_checksum,
	unsigned int dp_bits,
	unsigned int dp_count,
	uint64_t dp_checksum,
	const MetalDispatchStats& dispatch_stats,
	double seconds,
	double validation_seconds,
	double ops_per_sec,
	bool correctness,
	bool skipped,
	const std::string& reason)
{
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"metal\",\"operation\":\"" << operation << "\",";
	oss << "\"state_layout\":\"xyzz\",";
	oss << "\"setup_mode\":\"reuse_pipeline_buffers\",";
	oss << "\"state_persistence\":\"round_cumulative_xyzz\",";
	oss << "\"iterations\":" << iterations << ",";
	oss << "\"sample_count\":" << sample_count << ",";
	oss << "\"steps_per_sample\":" << steps_per_sample << ",";
	oss << "\"packet_count\":" << packet_count << ",";
	oss << "\"packets_per_round\":" << packets_per_round << ",";
	oss << "\"round_count\":" << round_count << ",";
	oss << "\"command_buffer_count\":" << round_count << ",";
	oss << "\"jump_count\":" << jump_count << ",";
	oss << "\"jump_index\":\"" << jump_index_mode << "\",";
	oss << "\"jump_mixer\":\"" << jump_mixer << "\",";
	oss << "\"jump_schedule\":\"" << jump_schedule << "\",";
	oss << "\"jump_histogram_min_bucket\":" << jump_histogram_min_bucket << ",";
	oss << "\"jump_histogram_max_bucket\":" << jump_histogram_max_bucket << ",";
	oss << "\"jump_histogram_max_deviation_ppm\":" << jump_histogram_max_deviation_ppm << ",";
	oss << "\"output_layout\":\"dp_stream\",";
	oss << "\"output_bytes_per_record\":20,";
	oss << "\"output_bytes_total\":" << (uint64_t)emitted_records * 20ULL << ",";
	oss << "\"emitted_records\":" << emitted_records << ",";
	oss << "\"dp_capacity\":" << dp_capacity << ",";
	oss << "\"dp_stream_overflow\":" << (dp_stream_overflow ? "true" : "false") << ",";
	oss << "\"distance_tracking\":\"dp_stream_cumulative_uint64\",";
	oss << "\"stream_indexing\":\"round_packet_sample_u32\",";
	oss << "\"dp_distance_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_distance_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"dp_tracking\":\"projective_x_limb0\",";
	oss << "\"dp_bits\":" << dp_bits << ",";
	oss << "\"dp_count\":" << dp_count << ",";
	oss << "\"dp_checksum\":\"0x" << std::hex << std::setw(16) << std::setfill('0') << dp_checksum << std::dec << std::setfill(' ') << "\",";
	oss << "\"threadgroup_limit\":" << dispatch_stats.threadgroup_limit << ",";
	oss << "\"thread_execution_width\":" << dispatch_stats.thread_execution_width << ",";
	oss << "\"max_threads_per_threadgroup\":" << dispatch_stats.max_threads_per_threadgroup << ",";
	oss << "\"threads_per_threadgroup\":" << dispatch_stats.threads_per_threadgroup << ",";
	oss << "\"seconds\":" << seconds << ",";
	oss << "\"validation_workers\":" << ValidationWorkerCount(sample_count) << ",";
	oss << "\"validation_seconds\":" << validation_seconds << ",";
	oss << "\"ops_per_sec\":" << ops_per_sec << ",";
	oss << "\"correctness\":" << (correctness ? "true" : "false") << ",";
	oss << "\"skipped\":" << (skipped ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << JsonEscape(reason) << "\"";
	oss << "}";
	return oss.str();
}

static std::string MetalJacobianDynamicDpCountBenchJson(const char* operation,
	uint64_t iterations,
	unsigned int sample_count,
	unsigned int steps_per_sample,
	unsigned int jump_count,
	const char* jump_index_mode,
	const char* jump_mixer,
	uint64_t jump_histogram_min_bucket,
	uint64_t jump_histogram_max_bucket,
	uint64_t jump_histogram_max_deviation_ppm,
	unsigned int dp_bits,
	unsigned int dp_count,
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
	oss << "\"steps_per_sample\":" << steps_per_sample << ",";
	oss << "\"jump_count\":" << jump_count << ",";
	oss << "\"jump_index\":\"" << jump_index_mode << "\",";
	oss << "\"jump_mixer\":\"" << jump_mixer << "\",";
	oss << "\"jump_histogram_min_bucket\":" << jump_histogram_min_bucket << ",";
	oss << "\"jump_histogram_max_bucket\":" << jump_histogram_max_bucket << ",";
	oss << "\"jump_histogram_max_deviation_ppm\":" << jump_histogram_max_deviation_ppm << ",";
	oss << "\"output_layout\":\"dp_count\",";
	oss << "\"output_bytes_total\":4,";
	oss << "\"distance_tracking\":\"none\",";
	oss << "\"dp_tracking\":\"projective_x_limb0\",";
	oss << "\"dp_bits\":" << dp_bits << ",";
	oss << "\"dp_count\":" << dp_count << ",";
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

static NSUInteger EffectiveDynamicDpStreamThreadgroupLimit(unsigned int threadgroup_limit, unsigned int dp_bits)
{
	if (threadgroup_limit)
		return (NSUInteger)threadgroup_limit;
	return dp_bits == 12 ? (NSUInteger)kDefaultMetalDp12StreamThreadgroupLimit : (NSUInteger)kDefaultMetalFieldThreadgroupLimit;
}

static NSUInteger EffectiveDynamicDpStreamInplaceThreadgroupLimit(unsigned int threadgroup_limit, unsigned int dp_bits, unsigned int steps_per_sample)
{
	if (threadgroup_limit)
		return (NSUInteger)threadgroup_limit;
	if (steps_per_sample >= 256 || (dp_bits == 8 && steps_per_sample >= 16))
		return (NSUInteger)128;
	return EffectiveDynamicDpStreamThreadgroupLimit(threadgroup_limit, dp_bits);
}

static NSUInteger EffectiveTargetLookupThreadgroupLimit(unsigned int threadgroup_limit)
{
	if (threadgroup_limit)
		return (NSUInteger)threadgroup_limit;
	return (NSUInteger)kDefaultMetalTargetLookupThreadgroupLimit;
}

static unsigned int PersistentTargetLookupDefaultThreadgroupLimit(size_t target_count)
{
	return target_count >= kDefaultMetalPersistentTargetLookupLargeTargetThreshold ? kDefaultMetalPersistentTargetLookupLargeThreadgroupLimit : kDefaultMetalTargetLookupThreadgroupLimit;
}

static unsigned int PersistentTargetLookupFilterDefaultThreadgroupLimit(size_t target_count)
{
	return target_count >= kDefaultMetalPersistentTargetLookupLargeTargetThreshold ? kDefaultMetalPersistentTargetLookupFilterLargeThreadgroupLimit : kDefaultMetalTargetLookupThreadgroupLimit;
}

static NSUInteger EffectiveTargetLookupPersistentThreadgroupLimit(unsigned int threadgroup_limit, size_t target_count)
{
	if (threadgroup_limit)
		return (NSUInteger)threadgroup_limit;
	return (NSUInteger)PersistentTargetLookupDefaultThreadgroupLimit(target_count);
}

static NSUInteger EffectiveTargetLookupFilterPersistentThreadgroupLimit(unsigned int threadgroup_limit, size_t target_count)
{
	if (threadgroup_limit)
		return (NSUInteger)threadgroup_limit;
	return (NSUInteger)PersistentTargetLookupFilterDefaultThreadgroupLimit(target_count);
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

static NSUInteger PreferredTargetLookupThreadgroupWidth(id<MTLComputePipelineState> pipeline, unsigned int threadgroup_limit)
{
	NSUInteger execution_width = [pipeline threadExecutionWidth] ? [pipeline threadExecutionWidth] : 1;
	NSUInteger max_threads = [pipeline maxTotalThreadsPerThreadgroup] ? [pipeline maxTotalThreadsPerThreadgroup] : execution_width;
	NSUInteger requested_limit = EffectiveTargetLookupThreadgroupLimit(threadgroup_limit);
	NSUInteger target = max_threads < requested_limit ? max_threads : requested_limit;
	target -= target % execution_width;
	if (target < execution_width)
		target = execution_width;
	return target;
}

static NSUInteger PreferredTargetLookupPersistentThreadgroupWidth(id<MTLComputePipelineState> pipeline, unsigned int threadgroup_limit, size_t target_count)
{
	NSUInteger execution_width = [pipeline threadExecutionWidth] ? [pipeline threadExecutionWidth] : 1;
	NSUInteger max_threads = [pipeline maxTotalThreadsPerThreadgroup] ? [pipeline maxTotalThreadsPerThreadgroup] : execution_width;
	NSUInteger requested_limit = EffectiveTargetLookupPersistentThreadgroupLimit(threadgroup_limit, target_count);
	NSUInteger target = max_threads < requested_limit ? max_threads : requested_limit;
	target -= target % execution_width;
	if (target < execution_width)
		target = execution_width;
	return target;
}

static NSUInteger PreferredTargetLookupFilterPersistentThreadgroupWidth(id<MTLComputePipelineState> pipeline, unsigned int threadgroup_limit, size_t target_count)
{
	NSUInteger execution_width = [pipeline threadExecutionWidth] ? [pipeline threadExecutionWidth] : 1;
	NSUInteger max_threads = [pipeline maxTotalThreadsPerThreadgroup] ? [pipeline maxTotalThreadsPerThreadgroup] : execution_width;
	NSUInteger requested_limit = EffectiveTargetLookupFilterPersistentThreadgroupLimit(threadgroup_limit, target_count);
	NSUInteger target = max_threads < requested_limit ? max_threads : requested_limit;
	target -= target % execution_width;
	if (target < execution_width)
		target = execution_width;
	return target;
}

static uint64_t TargetLookupMix(uint64_t v)
{
	v ^= v >> 33;
	v *= 0xff51afd7ed558ccdULL;
	v ^= v >> 33;
	v *= 0xc4ceb9fe1a85ec53ULL;
	v ^= v >> 33;
	return v;
}

static TargetLookupKeyHost DeterministicTargetLookupKey(uint64_t index, uint64_t salt)
{
	TargetLookupKeyHost key;
	for (unsigned int limb = 0; limb < 4; ++limb)
		key.x[limb] = TargetLookupMix(index + salt + 0x9e3779b97f4a7c15ULL * (uint64_t)(limb + 1));
	key.parity = (uint32_t)(TargetLookupMix(index ^ (salt << 1) ^ 0xD1B54A32D192ED03ULL) & 1ULL);
	return key;
}

static bool TargetLookupKeyEquals(const TargetLookupKeyHost& a, const TargetLookupKeyHost& b)
{
	return a.parity == b.parity &&
		a.x[0] == b.x[0] &&
		a.x[1] == b.x[1] &&
		a.x[2] == b.x[2] &&
		a.x[3] == b.x[3];
}

static uint64_t TargetLookupHash(const TargetLookupKeyHost& key)
{
	uint64_t h = 0x9e3779b97f4a7c15ULL;
	h = TargetLookupMix(h ^ key.x[0]);
	h = TargetLookupMix(h ^ key.x[1]);
	h = TargetLookupMix(h ^ key.x[2]);
	h = TargetLookupMix(h ^ key.x[3]);
	return TargetLookupMix(h ^ (uint64_t)key.parity);
}

static uint32_t TargetLookupTag32(uint64_t hash)
{
	return (uint32_t)(hash >> 32);
}

static uint32_t TargetLookupFilterTag32(uint64_t hash)
{
	return TargetLookupTag32(hash) | 1U;
}

static uint16_t TargetLookupFilterTag16(uint64_t hash)
{
	return (uint16_t)(((uint16_t)(hash >> 48)) | (uint16_t)1U);
}

static unsigned int TargetLookupBucketCount(unsigned int target_count)
{
	uint64_t needed = target_count ? target_count : 1;
	uint64_t buckets = 2;
	while (buckets * 3ULL < needed * 4ULL)
		buckets <<= 1;
	if (buckets > 0x80000000ULL)
		return 0;
	return (unsigned int)buckets;
}

static bool TargetLookupFind(const std::vector<TargetLookupBucketHost>& buckets,
	const TargetLookupKeyHost& key,
	uint32_t* target_index)
{
	if (buckets.empty())
		return false;
	uint32_t mask = (uint32_t)buckets.size() - 1U;
	uint32_t slot = (uint32_t)(TargetLookupHash(key) & (uint64_t)mask);
	for (uint32_t probes = 0; probes < buckets.size(); ++probes)
	{
		const TargetLookupBucketHost& bucket = buckets[slot];
		if (!bucket.occupied)
			return false;
		if (TargetLookupKeyEquals(bucket.key, key))
		{
			if (target_index)
				*target_index = bucket.target_index;
			return true;
		}
		slot = (slot + 1U) & mask;
	}
	return false;
}

static bool BuildTargetLookupExactTable(unsigned int target_count,
	std::vector<TargetLookupKeyHost>& target_keys,
	std::vector<TargetLookupBucketHost>& buckets,
	std::string& error)
{
	unsigned int bucket_count = TargetLookupBucketCount(target_count);
	if (!bucket_count)
	{
		error = "target lookup table too large";
		return false;
	}

	target_keys.clear();
	target_keys.reserve(target_count);
	buckets.assign(bucket_count, TargetLookupBucketHost{});
	uint32_t mask = bucket_count - 1U;
	for (unsigned int i = 0; i < target_count; ++i)
	{
		TargetLookupKeyHost key = DeterministicTargetLookupKey(i, 0xA47D1B5EEDULL);
		target_keys.push_back(key);
		uint32_t slot = (uint32_t)(TargetLookupHash(key) & (uint64_t)mask);
		for (uint32_t probes = 0; probes < bucket_count; ++probes)
		{
			TargetLookupBucketHost& bucket = buckets[slot];
			if (!bucket.occupied)
			{
				bucket.key = key;
				bucket.target_index = i;
				bucket.occupied = 1;
				break;
			}
			slot = (slot + 1U) & mask;
			if (probes + 1U == bucket_count)
			{
				error = "target lookup table insertion failed";
				return false;
			}
		}
	}
	return true;
}

static bool TargetLookupCompactFind(const std::vector<TargetLookupKeyHost>& target_keys,
	const std::vector<TargetLookupCompactBucketHost>& buckets,
	const TargetLookupKeyHost& key,
	uint32_t* target_index)
{
	if (buckets.empty())
		return false;
	uint64_t hash = TargetLookupHash(key);
	uint32_t mask = (uint32_t)buckets.size() - 1U;
	uint32_t slot = (uint32_t)(hash & (uint64_t)mask);
	for (uint32_t probes = 0; probes < buckets.size(); ++probes)
	{
		const TargetLookupCompactBucketHost& bucket = buckets[slot];
		if (!bucket.occupied)
			return false;
		if (bucket.hash == hash && bucket.target_index < target_keys.size() &&
			TargetLookupKeyEquals(target_keys[bucket.target_index], key))
		{
			if (target_index)
				*target_index = bucket.target_index;
			return true;
		}
		slot = (slot + 1U) & mask;
	}
	return false;
}

static bool BuildTargetLookupCompactTable(unsigned int target_count,
	std::vector<TargetLookupKeyHost>& target_keys,
	std::vector<TargetLookupCompactBucketHost>& buckets,
	std::string& error)
{
	unsigned int bucket_count = TargetLookupBucketCount(target_count);
	if (!bucket_count)
	{
		error = "target lookup table too large";
		return false;
	}

	target_keys.clear();
	target_keys.reserve(target_count);
	buckets.assign(bucket_count, TargetLookupCompactBucketHost{});
	uint32_t mask = bucket_count - 1U;
	for (unsigned int i = 0; i < target_count; ++i)
	{
		TargetLookupKeyHost key = DeterministicTargetLookupKey(i, 0xA47D1B5EEDULL);
		uint64_t hash = TargetLookupHash(key);
		target_keys.push_back(key);
		uint32_t slot = (uint32_t)(hash & (uint64_t)mask);
		for (uint32_t probes = 0; probes < bucket_count; ++probes)
		{
			TargetLookupCompactBucketHost& bucket = buckets[slot];
			if (!bucket.occupied)
			{
				bucket.hash = hash;
				bucket.target_index = i;
				bucket.occupied = 1;
				break;
			}
			slot = (slot + 1U) & mask;
			if (probes + 1U == bucket_count)
			{
				error = "compact target lookup table insertion failed";
				return false;
			}
		}
	}
	return true;
}

static bool TargetLookupTag32Find(const std::vector<TargetLookupKeyHost>& target_keys,
	const std::vector<TargetLookupTag32BucketHost>& buckets,
	const TargetLookupKeyHost& key,
	uint32_t* target_index)
{
	if (buckets.empty())
		return false;
	uint64_t hash = TargetLookupHash(key);
	uint32_t tag = TargetLookupTag32(hash);
	uint32_t mask = (uint32_t)buckets.size() - 1U;
	uint32_t slot = (uint32_t)(hash & (uint64_t)mask);
	for (uint32_t probes = 0; probes < buckets.size(); ++probes)
	{
		const TargetLookupTag32BucketHost& bucket = buckets[slot];
		if (bucket.target_index == kTargetLookupEmptyIndex)
			return false;
		if (bucket.tag == tag && bucket.target_index < target_keys.size() &&
			TargetLookupKeyEquals(target_keys[bucket.target_index], key))
		{
			if (target_index)
				*target_index = bucket.target_index;
			return true;
		}
		slot = (slot + 1U) & mask;
	}
	return false;
}

static bool BuildTargetLookupTag32Table(unsigned int target_count,
	std::vector<TargetLookupKeyHost>& target_keys,
	std::vector<TargetLookupTag32BucketHost>& buckets,
	std::string& error)
{
	unsigned int bucket_count = TargetLookupBucketCount(target_count);
	if (!bucket_count)
	{
		error = "target lookup table too large";
		return false;
	}

	target_keys.clear();
	target_keys.reserve(target_count);
	buckets.assign(bucket_count, TargetLookupTag32BucketHost{0, kTargetLookupEmptyIndex});
	uint32_t mask = bucket_count - 1U;
	for (unsigned int i = 0; i < target_count; ++i)
	{
		TargetLookupKeyHost key = DeterministicTargetLookupKey(i, 0xA47D1B5EEDULL);
		uint64_t hash = TargetLookupHash(key);
		target_keys.push_back(key);
		uint32_t slot = (uint32_t)(hash & (uint64_t)mask);
		for (uint32_t probes = 0; probes < bucket_count; ++probes)
		{
			TargetLookupTag32BucketHost& bucket = buckets[slot];
			if (bucket.target_index == kTargetLookupEmptyIndex)
			{
				bucket.tag = TargetLookupTag32(hash);
				bucket.target_index = i;
				break;
			}
			slot = (slot + 1U) & mask;
			if (probes + 1U == bucket_count)
			{
				error = "tag32 target lookup table insertion failed";
				return false;
			}
		}
	}
	return true;
}

static bool BuildTargetLookupTag32FilterTable(const std::vector<TargetLookupKeyHost>& target_keys,
	std::vector<uint32_t>& filter_buckets,
	std::string& error)
{
	if (target_keys.size() > 0xFFFFFFFFULL)
	{
		error = "tag32 filter target lookup table too large";
		return false;
	}
	unsigned int bucket_count = TargetLookupBucketCount((unsigned int)target_keys.size());
	if (!bucket_count)
	{
		error = "tag32 filter target lookup table too large";
		return false;
	}

	filter_buckets.assign(bucket_count, 0U);
	uint32_t mask = bucket_count - 1U;
	for (uint32_t i = 0; i < (uint32_t)target_keys.size(); ++i)
	{
		uint64_t hash = TargetLookupHash(target_keys[i]);
		uint32_t slot = (uint32_t)(hash & (uint64_t)mask);
		for (unsigned int probe = 0; probe < bucket_count; ++probe)
		{
			uint32_t& bucket = filter_buckets[slot];
			if (bucket == 0U)
			{
				bucket = TargetLookupFilterTag32(hash);
				break;
			}
			slot = (slot + 1U) & mask;
			if (probe + 1U == bucket_count)
			{
				error = "tag32 filter target lookup table insertion failed";
				return false;
			}
		}
	}
	return true;
}

static bool BuildTargetLookupTag16FilterTable(const std::vector<TargetLookupKeyHost>& target_keys,
	std::vector<uint16_t>& filter_buckets,
	std::string& error)
{
	if (target_keys.size() > 0xFFFFFFFFULL)
	{
		error = "tag16 filter target lookup table too large";
		return false;
	}
	unsigned int bucket_count = TargetLookupBucketCount((unsigned int)target_keys.size());
	if (!bucket_count)
	{
		error = "tag16 filter target lookup table too large";
		return false;
	}

	filter_buckets.assign(bucket_count, 0U);
	uint32_t mask = bucket_count - 1U;
	for (uint32_t i = 0; i < (uint32_t)target_keys.size(); ++i)
	{
		uint64_t hash = TargetLookupHash(target_keys[i]);
		uint32_t slot = (uint32_t)(hash & (uint64_t)mask);
		for (unsigned int probe = 0; probe < bucket_count; ++probe)
		{
			uint16_t& bucket = filter_buckets[slot];
			if (bucket == 0U)
			{
				bucket = TargetLookupFilterTag16(hash);
				break;
			}
			slot = (slot + 1U) & mask;
			if (probe + 1U == bucket_count)
			{
				error = "tag16 filter target lookup table insertion failed";
				return false;
			}
		}
	}
	return true;
}

static void BuildTargetLookupQueryHashes(const std::vector<TargetLookupKeyHost>& queries,
	std::vector<uint64_t>& query_hashes)
{
	query_hashes.clear();
	query_hashes.reserve(queries.size());
	for (const TargetLookupKeyHost& query : queries)
		query_hashes.push_back(TargetLookupHash(query));
}

static bool BuildTargetLookupTag32TableFromKeys(const std::vector<TargetLookupKeyHost>& injected_keys,
	unsigned int target_count,
	std::vector<TargetLookupKeyHost>& target_keys,
	std::vector<TargetLookupTag32BucketHost>& buckets,
	std::string& error)
{
	unsigned int bucket_count = TargetLookupBucketCount(target_count);
	if (!bucket_count || target_count < injected_keys.size())
	{
		error = "invalid affine DP target lookup table shape";
		return false;
	}

	target_keys.clear();
	target_keys.reserve(target_count);
	for (const TargetLookupKeyHost& key : injected_keys)
		target_keys.push_back(key);

	uint64_t nonce = 0;
	while (target_keys.size() < target_count)
	{
		TargetLookupKeyHost key = DeterministicTargetLookupKey(nonce++, 0xA1171E5CAFULL);
		bool duplicate = false;
		for (const TargetLookupKeyHost& injected : injected_keys)
		{
			if (TargetLookupKeyEquals(key, injected))
			{
				duplicate = true;
				break;
			}
		}
		if (!duplicate)
			target_keys.push_back(key);
	}

	buckets.assign(bucket_count, TargetLookupTag32BucketHost{0, kTargetLookupEmptyIndex});
	uint32_t mask = bucket_count - 1U;
	for (uint32_t i = 0; i < (uint32_t)target_keys.size(); ++i)
	{
		const TargetLookupKeyHost& key = target_keys[i];
		uint64_t hash = TargetLookupHash(key);
		uint32_t slot = (uint32_t)(hash & (uint64_t)mask);
		for (unsigned int probe = 0; probe < bucket_count; ++probe)
		{
			TargetLookupTag32BucketHost& bucket = buckets[slot];
			if (bucket.target_index == kTargetLookupEmptyIndex)
			{
				bucket.tag = TargetLookupTag32(hash);
				bucket.target_index = i;
				break;
			}
			slot = (slot + 1U) & mask;
			if (probe + 1U == bucket_count)
			{
				error = "affine DP tag32 target lookup table insertion failed";
				return false;
			}
		}
	}
	return true;
}

static void BuildTargetLookupQueries(const std::vector<TargetLookupKeyHost>& target_keys,
	const std::vector<TargetLookupBucketHost>& buckets,
	unsigned int query_count,
	unsigned int expected_hits,
	std::vector<TargetLookupKeyHost>& queries,
	std::vector<uint32_t>& expected_indices)
{
	queries.clear();
	expected_indices.clear();
	queries.reserve(query_count);
	expected_indices.reserve(query_count);
	for (unsigned int i = 0; i < query_count; ++i)
	{
		if (i < expected_hits && !target_keys.empty())
		{
			uint32_t target_index = (uint32_t)(((uint64_t)i * 2654435761ULL) % target_keys.size());
			queries.push_back(target_keys[target_index]);
			expected_indices.push_back(target_index);
			continue;
		}

		uint64_t miss_nonce = i;
		TargetLookupKeyHost miss_key = DeterministicTargetLookupKey(miss_nonce, 0xC001D00D55ULL);
		uint32_t ignored = 0;
		while (TargetLookupFind(buckets, miss_key, &ignored))
			miss_key = DeterministicTargetLookupKey(++miss_nonce, 0xBAD5EED123ULL);
		queries.push_back(miss_key);
		expected_indices.push_back(0xFFFFFFFFU);
	}
}

static void BuildTargetLookupCompactQueries(const std::vector<TargetLookupKeyHost>& target_keys,
	const std::vector<TargetLookupCompactBucketHost>& buckets,
	unsigned int query_count,
	unsigned int expected_hits,
	std::vector<TargetLookupKeyHost>& queries,
	std::vector<uint32_t>& expected_indices)
{
	queries.clear();
	expected_indices.clear();
	queries.reserve(query_count);
	expected_indices.reserve(query_count);
	for (unsigned int i = 0; i < query_count; ++i)
	{
		if (i < expected_hits && !target_keys.empty())
		{
			uint32_t target_index = (uint32_t)(((uint64_t)i * 2654435761ULL) % target_keys.size());
			queries.push_back(target_keys[target_index]);
			expected_indices.push_back(target_index);
			continue;
		}

		uint64_t miss_nonce = i;
		TargetLookupKeyHost miss_key = DeterministicTargetLookupKey(miss_nonce, 0xC001D00D55ULL);
		uint32_t ignored = 0;
		while (TargetLookupCompactFind(target_keys, buckets, miss_key, &ignored))
			miss_key = DeterministicTargetLookupKey(++miss_nonce, 0xBAD5EED123ULL);
		queries.push_back(miss_key);
		expected_indices.push_back(0xFFFFFFFFU);
	}
}

static void BuildTargetLookupTag32Queries(const std::vector<TargetLookupKeyHost>& target_keys,
	const std::vector<TargetLookupTag32BucketHost>& buckets,
	unsigned int query_count,
	unsigned int expected_hits,
	std::vector<TargetLookupKeyHost>& queries,
	std::vector<uint32_t>& expected_indices)
{
	queries.clear();
	expected_indices.clear();
	queries.reserve(query_count);
	expected_indices.reserve(query_count);
	for (unsigned int i = 0; i < query_count; ++i)
	{
		if (i < expected_hits && !target_keys.empty())
		{
			uint32_t target_index = (uint32_t)(((uint64_t)i * 2654435761ULL) % target_keys.size());
			queries.push_back(target_keys[target_index]);
			expected_indices.push_back(target_index);
			continue;
		}

		uint64_t miss_nonce = i;
		TargetLookupKeyHost miss_key = DeterministicTargetLookupKey(miss_nonce, 0xC001D00D55ULL);
		uint32_t ignored = 0;
		while (TargetLookupTag32Find(target_keys, buckets, miss_key, &ignored))
			miss_key = DeterministicTargetLookupKey(++miss_nonce, 0xBAD5EED123ULL);
		queries.push_back(miss_key);
		expected_indices.push_back(kTargetLookupEmptyIndex);
	}
}

static uint64_t MixTargetLookupChecksum(uint64_t checksum, uint32_t target_index, size_t query_index)
{
	uint64_t v = ((uint64_t)target_index << 32) ^ (uint64_t)query_index ^ 0xD6E8FEB86659FD93ULL;
	return TargetLookupMix(checksum ^ TargetLookupMix(v));
}

static bool ValidateTargetLookupOutputs(const std::vector<uint32_t>& out_indices,
	const std::vector<uint32_t>& expected_indices,
	uint32_t hit_count,
	unsigned int expected_hits,
	uint64_t* checksum,
	std::string& reason)
{
	if (hit_count != expected_hits)
	{
		reason = "target lookup hit count mismatch: got " + std::to_string(hit_count) +
			" expected " + std::to_string(expected_hits);
		return false;
	}
	if (out_indices.size() != expected_indices.size())
	{
		reason = "target lookup output size mismatch";
		return false;
	}

	uint64_t sum = 0x84c2f3a952d7495bULL;
	for (size_t i = 0; i < out_indices.size(); ++i)
	{
		if (out_indices[i] != expected_indices[i])
		{
			reason = "target lookup index mismatch at query " + std::to_string(i) +
				": got " + std::to_string(out_indices[i]) +
				" expected " + std::to_string(expected_indices[i]);
			return false;
		}
		sum = MixTargetLookupChecksum(sum, out_indices[i], i);
	}
	*checksum = sum;
	return true;
}

static bool ResolveTargetLookupTag32FilterCandidates(const std::vector<TargetLookupTag32BucketHost>& buckets,
	const std::vector<TargetLookupKeyHost>& target_keys,
	const std::vector<TargetLookupKeyHost>& queries,
	const std::vector<uint32_t>& positive_query_indices,
	uint32_t filter_positive_count,
	std::vector<uint32_t>& out_indices,
	uint32_t& hit_count,
	uint32_t& false_positive_count,
	std::string& reason,
	bool fill_outputs = true)
{
	if (filter_positive_count > positive_query_indices.size())
	{
		reason = "tag32 filter positive count exceeds output capacity";
		return false;
	}

	if (fill_outputs)
		out_indices.assign(queries.size(), kTargetLookupEmptyIndex);
	hit_count = 0;
	false_positive_count = 0;
	for (uint32_t i = 0; i < filter_positive_count; ++i)
	{
		uint32_t query_index = positive_query_indices[i];
		if (query_index >= queries.size())
		{
			reason = "tag32 filter emitted invalid query index";
			return false;
		}

		uint32_t found = kTargetLookupEmptyIndex;
		if (TargetLookupTag32Find(target_keys, buckets, queries[query_index], &found))
		{
			if (fill_outputs)
				out_indices[query_index] = found;
			hit_count++;
		}
		else
			false_positive_count++;
	}
	return true;
}

static bool RunTargetLookupTag32Cpu(const std::vector<TargetLookupTag32BucketHost>& buckets,
	const std::vector<TargetLookupKeyHost>& target_keys,
	const std::vector<TargetLookupKeyHost>& queries,
	std::vector<uint32_t>& out_indices,
	uint32_t& hit_count,
	std::string& error,
	double* seconds)
{
	if (buckets.empty() || target_keys.empty() || queries.empty())
	{
		error = "invalid tag32 target lookup input";
		return false;
	}

	out_indices.resize(queries.size());
	uint32_t local_hit_count = 0;
	auto start = std::chrono::steady_clock::now();
	for (size_t i = 0; i < queries.size(); ++i)
	{
		uint32_t found = kTargetLookupEmptyIndex;
		if (TargetLookupTag32Find(target_keys, buckets, queries[i], &found))
			local_hit_count++;
		out_indices[i] = found;
	}
	auto end = std::chrono::steady_clock::now();
	hit_count = local_hit_count;
	if (seconds)
		*seconds = std::chrono::duration<double>(end - start).count();
	return true;
}

static bool RunTargetLookupExactKernel(const std::vector<TargetLookupBucketHost>& buckets,
	const std::vector<TargetLookupKeyHost>& queries,
	std::vector<uint32_t>& out_indices,
	uint32_t& hit_count,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit = 0,
	MetalDispatchStats* dispatch_stats = NULL)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveTargetLookupThreadgroupLimit(threadgroup_limit);
	if (buckets.empty() || queries.empty())
	{
		error = "invalid target lookup input";
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

		id<MTLFunction> function = [library newFunctionWithName:@"target_lookup_exact256"];
		if (!function)
		{
			error = "failed to load target_lookup_exact256 function";
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
		NSUInteger threads_per_threadgroup = PreferredTargetLookupThreadgroupWidth(pipeline, threadgroup_limit);
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t bucket_bytes = buckets.size() * sizeof(TargetLookupBucketHost);
		size_t query_bytes = queries.size() * sizeof(TargetLookupKeyHost);
		size_t out_bytes = queries.size() * sizeof(uint32_t);
		uint32_t zero = 0;
		uint32_t bucket_count = (uint32_t)buckets.size();
		uint32_t query_count = (uint32_t)queries.size();
		id<MTLBuffer> buckets_buffer = [device newBufferWithBytes:buckets.data() length:bucket_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> queries_buffer = [device newBufferWithBytes:queries.data() length:query_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_buffer = [device newBufferWithLength:out_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> hit_count_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> bucket_count_buffer = [device newBufferWithBytes:&bucket_count length:sizeof(bucket_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> query_count_buffer = [device newBufferWithBytes:&query_count length:sizeof(query_count) options:MTLResourceStorageModeShared];
		if (!buckets_buffer || !queries_buffer || !out_buffer || !hit_count_buffer || !bucket_count_buffer || !query_count_buffer)
		{
			error = "failed to allocate Metal target lookup buffers";
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
		[encoder setBuffer:buckets_buffer offset:0 atIndex:0];
		[encoder setBuffer:queries_buffer offset:0 atIndex:1];
		[encoder setBuffer:out_buffer offset:0 atIndex:2];
		[encoder setBuffer:hit_count_buffer offset:0 atIndex:3];
		[encoder setBuffer:bucket_count_buffer offset:0 atIndex:4];
		[encoder setBuffer:query_count_buffer offset:0 atIndex:5];
		[encoder dispatchThreads:MTLSizeMake(query_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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

		out_indices.resize(queries.size());
		memcpy(out_indices.data(), [out_buffer contents], out_bytes);
		memcpy(&hit_count, [hit_count_buffer contents], sizeof(hit_count));
		return true;
	}
}

static bool RunTargetLookupCompactKernel(const std::vector<TargetLookupCompactBucketHost>& buckets,
	const std::vector<TargetLookupKeyHost>& target_keys,
	const std::vector<TargetLookupKeyHost>& queries,
	std::vector<uint32_t>& out_indices,
	uint32_t& hit_count,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit = 0,
	MetalDispatchStats* dispatch_stats = NULL)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveTargetLookupThreadgroupLimit(threadgroup_limit);
	if (buckets.empty() || target_keys.empty() || queries.empty())
	{
		error = "invalid compact target lookup input";
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

		id<MTLFunction> function = [library newFunctionWithName:@"target_lookup_compact_exact256"];
		if (!function)
		{
			error = "failed to load target_lookup_compact_exact256 function";
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
		NSUInteger threads_per_threadgroup = PreferredTargetLookupThreadgroupWidth(pipeline, threadgroup_limit);
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t bucket_bytes = buckets.size() * sizeof(TargetLookupCompactBucketHost);
		size_t key_bytes = target_keys.size() * sizeof(TargetLookupKeyHost);
		size_t query_bytes = queries.size() * sizeof(TargetLookupKeyHost);
		size_t out_bytes = queries.size() * sizeof(uint32_t);
		uint32_t zero = 0;
		uint32_t bucket_count = (uint32_t)buckets.size();
		uint32_t query_count = (uint32_t)queries.size();
		id<MTLBuffer> buckets_buffer = [device newBufferWithBytes:buckets.data() length:bucket_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> target_keys_buffer = [device newBufferWithBytes:target_keys.data() length:key_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> queries_buffer = [device newBufferWithBytes:queries.data() length:query_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_buffer = [device newBufferWithLength:out_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> hit_count_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> bucket_count_buffer = [device newBufferWithBytes:&bucket_count length:sizeof(bucket_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> query_count_buffer = [device newBufferWithBytes:&query_count length:sizeof(query_count) options:MTLResourceStorageModeShared];
		if (!buckets_buffer || !target_keys_buffer || !queries_buffer || !out_buffer || !hit_count_buffer || !bucket_count_buffer || !query_count_buffer)
		{
			error = "failed to allocate Metal compact target lookup buffers";
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
		[encoder setBuffer:buckets_buffer offset:0 atIndex:0];
		[encoder setBuffer:target_keys_buffer offset:0 atIndex:1];
		[encoder setBuffer:queries_buffer offset:0 atIndex:2];
		[encoder setBuffer:out_buffer offset:0 atIndex:3];
		[encoder setBuffer:hit_count_buffer offset:0 atIndex:4];
		[encoder setBuffer:bucket_count_buffer offset:0 atIndex:5];
		[encoder setBuffer:query_count_buffer offset:0 atIndex:6];
		[encoder dispatchThreads:MTLSizeMake(query_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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

		out_indices.resize(queries.size());
		memcpy(out_indices.data(), [out_buffer contents], out_bytes);
		memcpy(&hit_count, [hit_count_buffer contents], sizeof(hit_count));
		return true;
	}
}

static bool RunTargetLookupTag32Kernel(const std::vector<TargetLookupTag32BucketHost>& buckets,
	const std::vector<TargetLookupKeyHost>& target_keys,
	const std::vector<TargetLookupKeyHost>& queries,
	std::vector<uint32_t>& out_indices,
	uint32_t& hit_count,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit = 0,
	MetalDispatchStats* dispatch_stats = NULL)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveTargetLookupThreadgroupLimit(threadgroup_limit);
	if (buckets.empty() || target_keys.empty() || queries.empty())
	{
		error = "invalid tag32 target lookup input";
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

		id<MTLFunction> function = [library newFunctionWithName:@"target_lookup_tag32_exact256"];
		if (!function)
		{
			error = "failed to load target_lookup_tag32_exact256 function";
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
		NSUInteger threads_per_threadgroup = PreferredTargetLookupThreadgroupWidth(pipeline, threadgroup_limit);
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t bucket_bytes = buckets.size() * sizeof(TargetLookupTag32BucketHost);
		size_t key_bytes = target_keys.size() * sizeof(TargetLookupKeyHost);
		size_t query_bytes = queries.size() * sizeof(TargetLookupKeyHost);
		size_t out_bytes = queries.size() * sizeof(uint32_t);
		uint32_t zero = 0;
		uint32_t bucket_count = (uint32_t)buckets.size();
		uint32_t query_count = (uint32_t)queries.size();
		id<MTLBuffer> buckets_buffer = [device newBufferWithBytes:buckets.data() length:bucket_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> target_keys_buffer = [device newBufferWithBytes:target_keys.data() length:key_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> queries_buffer = [device newBufferWithBytes:queries.data() length:query_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_buffer = [device newBufferWithLength:out_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> hit_count_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> bucket_count_buffer = [device newBufferWithBytes:&bucket_count length:sizeof(bucket_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> query_count_buffer = [device newBufferWithBytes:&query_count length:sizeof(query_count) options:MTLResourceStorageModeShared];
		if (!buckets_buffer || !target_keys_buffer || !queries_buffer || !out_buffer || !hit_count_buffer || !bucket_count_buffer || !query_count_buffer)
		{
			error = "failed to allocate Metal tag32 target lookup buffers";
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
		[encoder setBuffer:buckets_buffer offset:0 atIndex:0];
		[encoder setBuffer:target_keys_buffer offset:0 atIndex:1];
		[encoder setBuffer:queries_buffer offset:0 atIndex:2];
		[encoder setBuffer:out_buffer offset:0 atIndex:3];
		[encoder setBuffer:hit_count_buffer offset:0 atIndex:4];
		[encoder setBuffer:bucket_count_buffer offset:0 atIndex:5];
		[encoder setBuffer:query_count_buffer offset:0 atIndex:6];
		[encoder dispatchThreads:MTLSizeMake(query_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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

		out_indices.resize(queries.size());
		memcpy(out_indices.data(), [out_buffer contents], out_bytes);
		memcpy(&hit_count, [hit_count_buffer contents], sizeof(hit_count));
		return true;
	}
}

static bool RunTargetLookupTag32FilterKernel(const std::vector<uint32_t>& filter_buckets,
	const std::vector<TargetLookupKeyHost>& queries,
	std::vector<uint32_t>& positive_query_indices,
	uint32_t& filter_positive_count,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit = 0,
	MetalDispatchStats* dispatch_stats = NULL)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveTargetLookupThreadgroupLimit(threadgroup_limit);
	if (filter_buckets.empty() || queries.empty())
	{
		error = "invalid tag32 filter target lookup input";
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

		id<MTLFunction> function = [library newFunctionWithName:@"target_lookup_tag32_filter256"];
		if (!function)
		{
			error = "failed to load target_lookup_tag32_filter256 function";
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
		NSUInteger threads_per_threadgroup = PreferredTargetLookupThreadgroupWidth(pipeline, threadgroup_limit);
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t bucket_bytes = filter_buckets.size() * sizeof(uint32_t);
		size_t query_bytes = queries.size() * sizeof(TargetLookupKeyHost);
		size_t positive_bytes = queries.size() * sizeof(uint32_t);
		uint32_t zero = 0;
		uint32_t bucket_count = (uint32_t)filter_buckets.size();
		uint32_t query_count = (uint32_t)queries.size();
		id<MTLBuffer> buckets_buffer = [device newBufferWithBytes:filter_buckets.data() length:bucket_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> queries_buffer = [device newBufferWithBytes:queries.data() length:query_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> positive_buffer = [device newBufferWithLength:positive_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> positive_count_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> bucket_count_buffer = [device newBufferWithBytes:&bucket_count length:sizeof(bucket_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> query_count_buffer = [device newBufferWithBytes:&query_count length:sizeof(query_count) options:MTLResourceStorageModeShared];
		if (!buckets_buffer || !queries_buffer || !positive_buffer || !positive_count_buffer || !bucket_count_buffer || !query_count_buffer)
		{
			error = "failed to allocate Metal tag32 filter target lookup buffers";
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
		[encoder setBuffer:buckets_buffer offset:0 atIndex:0];
		[encoder setBuffer:queries_buffer offset:0 atIndex:1];
		[encoder setBuffer:positive_buffer offset:0 atIndex:2];
		[encoder setBuffer:positive_count_buffer offset:0 atIndex:3];
		[encoder setBuffer:bucket_count_buffer offset:0 atIndex:4];
		[encoder setBuffer:query_count_buffer offset:0 atIndex:5];
		[encoder dispatchThreads:MTLSizeMake(query_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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

		memcpy(&filter_positive_count, [positive_count_buffer contents], sizeof(filter_positive_count));
		if (filter_positive_count > queries.size())
		{
			error = "tag32 filter positive count overflow";
			return false;
		}
		positive_query_indices.resize(filter_positive_count);
		if (filter_positive_count)
			memcpy(positive_query_indices.data(), [positive_buffer contents], (size_t)filter_positive_count * sizeof(uint32_t));
		return true;
	}
}

static bool RunTargetLookupTag32PersistentKernel(const std::vector<TargetLookupTag32BucketHost>& buckets,
	const std::vector<TargetLookupKeyHost>& target_keys,
	const std::vector<TargetLookupKeyHost>& queries,
	unsigned int min_ms,
	std::vector<uint32_t>& out_indices,
	uint32_t& hit_count,
	uint64_t& operations,
	std::string& error,
	double* setup_seconds,
	double* dispatch_seconds,
	unsigned int threadgroup_limit = 0,
	MetalDispatchStats* dispatch_stats = NULL)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveTargetLookupPersistentThreadgroupLimit(threadgroup_limit, target_keys.size());
	if (buckets.empty() || target_keys.empty() || queries.empty())
	{
		error = "invalid tag32 target lookup input";
		return false;
	}

	@autoreleasepool
	{
		auto setup_start = std::chrono::steady_clock::now();
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

		id<MTLFunction> function = [library newFunctionWithName:@"target_lookup_tag32_exact256"];
		if (!function)
		{
			error = "failed to load target_lookup_tag32_exact256 function";
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
		NSUInteger threads_per_threadgroup = PreferredTargetLookupPersistentThreadgroupWidth(pipeline, threadgroup_limit, target_keys.size());
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t bucket_bytes = buckets.size() * sizeof(TargetLookupTag32BucketHost);
		size_t key_bytes = target_keys.size() * sizeof(TargetLookupKeyHost);
		size_t query_bytes = queries.size() * sizeof(TargetLookupKeyHost);
		size_t out_bytes = queries.size() * sizeof(uint32_t);
		uint32_t zero = 0;
		uint32_t bucket_count = (uint32_t)buckets.size();
		uint32_t query_count = (uint32_t)queries.size();
		id<MTLBuffer> buckets_buffer = [device newBufferWithBytes:buckets.data() length:bucket_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> target_keys_buffer = [device newBufferWithBytes:target_keys.data() length:key_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> queries_buffer = [device newBufferWithBytes:queries.data() length:query_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_buffer = [device newBufferWithLength:out_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> hit_count_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> bucket_count_buffer = [device newBufferWithBytes:&bucket_count length:sizeof(bucket_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> query_count_buffer = [device newBufferWithBytes:&query_count length:sizeof(query_count) options:MTLResourceStorageModeShared];
		if (!buckets_buffer || !target_keys_buffer || !queries_buffer || !out_buffer || !hit_count_buffer || !bucket_count_buffer || !query_count_buffer)
		{
			error = "failed to allocate persistent Metal tag32 target lookup buffers";
			return false;
		}

		id<MTLCommandQueue> queue = [device newCommandQueue];
		if (!queue)
		{
			error = "failed to create Metal command queue";
			return false;
		}
		auto setup_end = std::chrono::steady_clock::now();
		if (setup_seconds)
			*setup_seconds = std::chrono::duration<double>(setup_end - setup_start).count();

		double total_dispatch_seconds = 0.0;
		unsigned int dispatch_count = 0;
		operations = 0;
		do
		{
			memcpy([hit_count_buffer contents], &zero, sizeof(zero));
			id<MTLCommandBuffer> command_buffer = [queue commandBuffer];
			id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
			[encoder setComputePipelineState:pipeline];
			[encoder setBuffer:buckets_buffer offset:0 atIndex:0];
			[encoder setBuffer:target_keys_buffer offset:0 atIndex:1];
			[encoder setBuffer:queries_buffer offset:0 atIndex:2];
			[encoder setBuffer:out_buffer offset:0 atIndex:3];
			[encoder setBuffer:hit_count_buffer offset:0 atIndex:4];
			[encoder setBuffer:bucket_count_buffer offset:0 atIndex:5];
			[encoder setBuffer:query_count_buffer offset:0 atIndex:6];
			[encoder dispatchThreads:MTLSizeMake(query_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
			[encoder endEncoding];
			auto dispatch_start = std::chrono::steady_clock::now();
			[command_buffer commit];
			[command_buffer waitUntilCompleted];
			auto dispatch_end = std::chrono::steady_clock::now();
			double local_dispatch_seconds = std::chrono::duration<double>(dispatch_end - dispatch_start).count();
			total_dispatch_seconds += local_dispatch_seconds;
			operations += query_count;
			dispatch_count++;

			if ([command_buffer status] != MTLCommandBufferStatusCompleted)
			{
				error = NSErrorToString([command_buffer error]);
				return false;
			}
			if (min_ms && local_dispatch_seconds == 0.0)
				break;
		} while (min_ms && (total_dispatch_seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

		if (dispatch_seconds)
			*dispatch_seconds = total_dispatch_seconds;
		out_indices.resize(queries.size());
		memcpy(out_indices.data(), [out_buffer contents], out_bytes);
		memcpy(&hit_count, [hit_count_buffer contents], sizeof(hit_count));
		return true;
	}
}

static bool RunTargetLookupTag32FilterPersistentKernel(const std::vector<uint32_t>& filter_buckets,
	const std::vector<TargetLookupTag32BucketHost>& buckets,
	const std::vector<TargetLookupKeyHost>& target_keys,
	const std::vector<TargetLookupKeyHost>& queries,
	unsigned int min_ms,
	std::vector<uint32_t>& out_indices,
	uint32_t& hit_count,
	uint32_t& filter_positive_count,
	uint32_t& false_positive_count,
	uint64_t& operations,
	std::string& error,
	double* setup_seconds,
	double* dispatch_seconds,
	double* exact_verify_seconds,
	unsigned int threadgroup_limit = 0,
	MetalDispatchStats* dispatch_stats = NULL)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveTargetLookupFilterPersistentThreadgroupLimit(threadgroup_limit, target_keys.size());
	if (filter_buckets.empty() || buckets.empty() || target_keys.empty() || queries.empty())
	{
		error = "invalid persistent tag32 filter target lookup input";
		return false;
	}

	@autoreleasepool
	{
		auto setup_start = std::chrono::steady_clock::now();
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

		id<MTLFunction> function = [library newFunctionWithName:@"target_lookup_tag32_filter256"];
		if (!function)
		{
			error = "failed to load target_lookup_tag32_filter256 function";
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
		NSUInteger threads_per_threadgroup = PreferredTargetLookupFilterPersistentThreadgroupWidth(pipeline, threadgroup_limit, target_keys.size());
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t bucket_bytes = filter_buckets.size() * sizeof(uint32_t);
		size_t query_bytes = queries.size() * sizeof(TargetLookupKeyHost);
		size_t positive_bytes = queries.size() * sizeof(uint32_t);
		uint32_t zero = 0;
		uint32_t bucket_count = (uint32_t)filter_buckets.size();
		uint32_t query_count = (uint32_t)queries.size();
		id<MTLBuffer> buckets_buffer = [device newBufferWithBytes:filter_buckets.data() length:bucket_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> queries_buffer = [device newBufferWithBytes:queries.data() length:query_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> positive_buffer = [device newBufferWithLength:positive_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> positive_count_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> bucket_count_buffer = [device newBufferWithBytes:&bucket_count length:sizeof(bucket_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> query_count_buffer = [device newBufferWithBytes:&query_count length:sizeof(query_count) options:MTLResourceStorageModeShared];
		if (!buckets_buffer || !queries_buffer || !positive_buffer || !positive_count_buffer || !bucket_count_buffer || !query_count_buffer)
		{
			error = "failed to allocate persistent Metal tag32 filter target lookup buffers";
			return false;
		}

		id<MTLCommandQueue> queue = [device newCommandQueue];
		if (!queue)
		{
			error = "failed to create Metal command queue";
			return false;
		}
		auto setup_end = std::chrono::steady_clock::now();
		if (setup_seconds)
			*setup_seconds = std::chrono::duration<double>(setup_end - setup_start).count();

		double total_dispatch_seconds = 0.0;
		double total_exact_verify_seconds = 0.0;
		unsigned int dispatch_count = 0;
		operations = 0;
		std::vector<uint32_t> positive_query_indices;
		do
		{
			memcpy([positive_count_buffer contents], &zero, sizeof(zero));
			id<MTLCommandBuffer> command_buffer = [queue commandBuffer];
			id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
			[encoder setComputePipelineState:pipeline];
			[encoder setBuffer:buckets_buffer offset:0 atIndex:0];
			[encoder setBuffer:queries_buffer offset:0 atIndex:1];
			[encoder setBuffer:positive_buffer offset:0 atIndex:2];
			[encoder setBuffer:positive_count_buffer offset:0 atIndex:3];
			[encoder setBuffer:bucket_count_buffer offset:0 atIndex:4];
			[encoder setBuffer:query_count_buffer offset:0 atIndex:5];
			[encoder dispatchThreads:MTLSizeMake(query_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
			[encoder endEncoding];
			auto dispatch_start = std::chrono::steady_clock::now();
			[command_buffer commit];
			[command_buffer waitUntilCompleted];
			auto dispatch_end = std::chrono::steady_clock::now();
			double local_dispatch_seconds = std::chrono::duration<double>(dispatch_end - dispatch_start).count();
			total_dispatch_seconds += local_dispatch_seconds;

			if ([command_buffer status] != MTLCommandBufferStatusCompleted)
			{
				error = NSErrorToString([command_buffer error]);
				return false;
			}

			memcpy(&filter_positive_count, [positive_count_buffer contents], sizeof(filter_positive_count));
			if (filter_positive_count > queries.size())
			{
				error = "persistent tag32 filter positive count overflow";
				return false;
			}
			positive_query_indices.resize(filter_positive_count);
			if (filter_positive_count)
				memcpy(positive_query_indices.data(), [positive_buffer contents], (size_t)filter_positive_count * sizeof(uint32_t));

			std::string resolve_reason;
			auto verify_start = std::chrono::steady_clock::now();
			if (!ResolveTargetLookupTag32FilterCandidates(buckets, target_keys, queries, positive_query_indices, filter_positive_count, out_indices, hit_count, false_positive_count, resolve_reason, false))
			{
				total_exact_verify_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - verify_start).count();
				error = resolve_reason;
				return false;
			}
			total_exact_verify_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - verify_start).count();

			operations += query_count;
			dispatch_count++;
			if (min_ms && local_dispatch_seconds == 0.0)
				break;
		} while (min_ms && ((total_dispatch_seconds + total_exact_verify_seconds) * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

		if (dispatch_seconds)
			*dispatch_seconds = total_dispatch_seconds;
		if (exact_verify_seconds)
			*exact_verify_seconds = total_exact_verify_seconds;

		std::string resolve_reason;
		if (!ResolveTargetLookupTag32FilterCandidates(buckets, target_keys, queries, positive_query_indices, filter_positive_count, out_indices, hit_count, false_positive_count, resolve_reason, true))
		{
			error = resolve_reason;
			return false;
		}
		return true;
	}
}

static bool RunTargetLookupTag16FilterPersistentKernel(const std::vector<uint16_t>& filter_buckets,
	const std::vector<TargetLookupTag32BucketHost>& buckets,
	const std::vector<TargetLookupKeyHost>& target_keys,
	const std::vector<TargetLookupKeyHost>& queries,
	unsigned int min_ms,
	std::vector<uint32_t>& out_indices,
	uint32_t& hit_count,
	uint32_t& filter_positive_count,
	uint32_t& false_positive_count,
	uint64_t& operations,
	std::string& error,
	double* setup_seconds,
	double* dispatch_seconds,
	double* exact_verify_seconds,
	unsigned int threadgroup_limit = 0,
	MetalDispatchStats* dispatch_stats = NULL)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveTargetLookupFilterPersistentThreadgroupLimit(threadgroup_limit, target_keys.size());
	if (filter_buckets.empty() || buckets.empty() || target_keys.empty() || queries.empty())
	{
		error = "invalid persistent tag16 filter target lookup input";
		return false;
	}

	@autoreleasepool
	{
		auto setup_start = std::chrono::steady_clock::now();
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

		id<MTLFunction> function = [library newFunctionWithName:@"target_lookup_tag16_filter256"];
		if (!function)
		{
			error = "failed to load target_lookup_tag16_filter256 function";
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
		NSUInteger threads_per_threadgroup = PreferredTargetLookupFilterPersistentThreadgroupWidth(pipeline, threadgroup_limit, target_keys.size());
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t bucket_bytes = filter_buckets.size() * sizeof(uint16_t);
		size_t query_bytes = queries.size() * sizeof(TargetLookupKeyHost);
		size_t positive_bytes = queries.size() * sizeof(uint32_t);
		uint32_t zero = 0;
		uint32_t bucket_count = (uint32_t)filter_buckets.size();
		uint32_t query_count = (uint32_t)queries.size();
		id<MTLBuffer> buckets_buffer = [device newBufferWithBytes:filter_buckets.data() length:bucket_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> queries_buffer = [device newBufferWithBytes:queries.data() length:query_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> positive_buffer = [device newBufferWithLength:positive_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> positive_count_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> bucket_count_buffer = [device newBufferWithBytes:&bucket_count length:sizeof(bucket_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> query_count_buffer = [device newBufferWithBytes:&query_count length:sizeof(query_count) options:MTLResourceStorageModeShared];
		if (!buckets_buffer || !queries_buffer || !positive_buffer || !positive_count_buffer || !bucket_count_buffer || !query_count_buffer)
		{
			error = "failed to allocate persistent Metal tag16 filter target lookup buffers";
			return false;
		}

		id<MTLCommandQueue> queue = [device newCommandQueue];
		if (!queue)
		{
			error = "failed to create Metal command queue";
			return false;
		}
		auto setup_end = std::chrono::steady_clock::now();
		if (setup_seconds)
			*setup_seconds = std::chrono::duration<double>(setup_end - setup_start).count();

		double total_dispatch_seconds = 0.0;
		double total_exact_verify_seconds = 0.0;
		unsigned int dispatch_count = 0;
		operations = 0;
		std::vector<uint32_t> positive_query_indices;
		do
		{
			memcpy([positive_count_buffer contents], &zero, sizeof(zero));
			id<MTLCommandBuffer> command_buffer = [queue commandBuffer];
			id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
			[encoder setComputePipelineState:pipeline];
			[encoder setBuffer:buckets_buffer offset:0 atIndex:0];
			[encoder setBuffer:queries_buffer offset:0 atIndex:1];
			[encoder setBuffer:positive_buffer offset:0 atIndex:2];
			[encoder setBuffer:positive_count_buffer offset:0 atIndex:3];
			[encoder setBuffer:bucket_count_buffer offset:0 atIndex:4];
			[encoder setBuffer:query_count_buffer offset:0 atIndex:5];
			[encoder dispatchThreads:MTLSizeMake(query_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
			[encoder endEncoding];
			auto dispatch_start = std::chrono::steady_clock::now();
			[command_buffer commit];
			[command_buffer waitUntilCompleted];
			auto dispatch_end = std::chrono::steady_clock::now();
			double local_dispatch_seconds = std::chrono::duration<double>(dispatch_end - dispatch_start).count();
			total_dispatch_seconds += local_dispatch_seconds;

			if ([command_buffer status] != MTLCommandBufferStatusCompleted)
			{
				error = NSErrorToString([command_buffer error]);
				return false;
			}

			memcpy(&filter_positive_count, [positive_count_buffer contents], sizeof(filter_positive_count));
			if (filter_positive_count > queries.size())
			{
				error = "persistent tag16 filter positive count overflow";
				return false;
			}
			positive_query_indices.resize(filter_positive_count);
			if (filter_positive_count)
				memcpy(positive_query_indices.data(), [positive_buffer contents], (size_t)filter_positive_count * sizeof(uint32_t));

			std::string resolve_reason;
			auto verify_start = std::chrono::steady_clock::now();
			if (!ResolveTargetLookupTag32FilterCandidates(buckets, target_keys, queries, positive_query_indices, filter_positive_count, out_indices, hit_count, false_positive_count, resolve_reason, false))
			{
				total_exact_verify_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - verify_start).count();
				error = resolve_reason;
				return false;
			}
			total_exact_verify_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - verify_start).count();

			operations += query_count;
			dispatch_count++;
			if (min_ms && local_dispatch_seconds == 0.0)
				break;
		} while (min_ms && ((total_dispatch_seconds + total_exact_verify_seconds) * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

		if (dispatch_seconds)
			*dispatch_seconds = total_dispatch_seconds;
		if (exact_verify_seconds)
			*exact_verify_seconds = total_exact_verify_seconds;

		std::string resolve_reason;
		if (!ResolveTargetLookupTag32FilterCandidates(buckets, target_keys, queries, positive_query_indices, filter_positive_count, out_indices, hit_count, false_positive_count, resolve_reason, true))
		{
			error = resolve_reason;
			return false;
		}
		return true;
	}
}

static bool RunTargetLookupTag16HashFilterPersistentKernel(const std::vector<uint16_t>& filter_buckets,
	const std::vector<TargetLookupTag32BucketHost>& buckets,
	const std::vector<TargetLookupKeyHost>& target_keys,
	const std::vector<TargetLookupKeyHost>& queries,
	const std::vector<uint64_t>& query_hashes,
	unsigned int min_ms,
	std::vector<uint32_t>& out_indices,
	uint32_t& hit_count,
	uint32_t& filter_positive_count,
	uint32_t& false_positive_count,
	uint64_t& operations,
	std::string& error,
	double* setup_seconds,
	double* dispatch_seconds,
	double* exact_verify_seconds,
	unsigned int threadgroup_limit = 0,
	MetalDispatchStats* dispatch_stats = NULL)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveTargetLookupFilterPersistentThreadgroupLimit(threadgroup_limit, target_keys.size());
	if (filter_buckets.empty() || buckets.empty() || target_keys.empty() || queries.empty() || query_hashes.size() != queries.size())
	{
		error = "invalid persistent tag16 hash-filter target lookup input";
		return false;
	}

	@autoreleasepool
	{
		auto setup_start = std::chrono::steady_clock::now();
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

		id<MTLFunction> function = [library newFunctionWithName:@"target_lookup_tag16_hash_filter256"];
		if (!function)
		{
			error = "failed to load target_lookup_tag16_hash_filter256 function";
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
		NSUInteger threads_per_threadgroup = PreferredTargetLookupFilterPersistentThreadgroupWidth(pipeline, threadgroup_limit, target_keys.size());
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t bucket_bytes = filter_buckets.size() * sizeof(uint16_t);
		size_t hash_bytes = query_hashes.size() * sizeof(uint64_t);
		size_t positive_bytes = queries.size() * sizeof(uint32_t);
		uint32_t zero = 0;
		uint32_t bucket_count = (uint32_t)filter_buckets.size();
		uint32_t query_count = (uint32_t)queries.size();
		id<MTLBuffer> buckets_buffer = [device newBufferWithBytes:filter_buckets.data() length:bucket_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> query_hashes_buffer = [device newBufferWithBytes:query_hashes.data() length:hash_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> positive_buffer = [device newBufferWithLength:positive_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> positive_count_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> bucket_count_buffer = [device newBufferWithBytes:&bucket_count length:sizeof(bucket_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> query_count_buffer = [device newBufferWithBytes:&query_count length:sizeof(query_count) options:MTLResourceStorageModeShared];
		if (!buckets_buffer || !query_hashes_buffer || !positive_buffer || !positive_count_buffer || !bucket_count_buffer || !query_count_buffer)
		{
			error = "failed to allocate persistent Metal tag16 hash-filter target lookup buffers";
			return false;
		}

		id<MTLCommandQueue> queue = [device newCommandQueue];
		if (!queue)
		{
			error = "failed to create Metal command queue";
			return false;
		}
		auto setup_end = std::chrono::steady_clock::now();
		if (setup_seconds)
			*setup_seconds = std::chrono::duration<double>(setup_end - setup_start).count();

		double total_dispatch_seconds = 0.0;
		double total_exact_verify_seconds = 0.0;
		unsigned int dispatch_count = 0;
		operations = 0;
		std::vector<uint32_t> positive_query_indices;
		do
		{
			memcpy([positive_count_buffer contents], &zero, sizeof(zero));
			id<MTLCommandBuffer> command_buffer = [queue commandBuffer];
			id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
			[encoder setComputePipelineState:pipeline];
			[encoder setBuffer:buckets_buffer offset:0 atIndex:0];
			[encoder setBuffer:query_hashes_buffer offset:0 atIndex:1];
			[encoder setBuffer:positive_buffer offset:0 atIndex:2];
			[encoder setBuffer:positive_count_buffer offset:0 atIndex:3];
			[encoder setBuffer:bucket_count_buffer offset:0 atIndex:4];
			[encoder setBuffer:query_count_buffer offset:0 atIndex:5];
			[encoder dispatchThreads:MTLSizeMake(query_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
			[encoder endEncoding];
			auto dispatch_start = std::chrono::steady_clock::now();
			[command_buffer commit];
			[command_buffer waitUntilCompleted];
			auto dispatch_end = std::chrono::steady_clock::now();
			double local_dispatch_seconds = std::chrono::duration<double>(dispatch_end - dispatch_start).count();
			total_dispatch_seconds += local_dispatch_seconds;

			if ([command_buffer status] != MTLCommandBufferStatusCompleted)
			{
				error = NSErrorToString([command_buffer error]);
				return false;
			}

			memcpy(&filter_positive_count, [positive_count_buffer contents], sizeof(filter_positive_count));
			if (filter_positive_count > queries.size())
			{
				error = "persistent tag16 hash-filter positive count overflow";
				return false;
			}
			positive_query_indices.resize(filter_positive_count);
			if (filter_positive_count)
				memcpy(positive_query_indices.data(), [positive_buffer contents], (size_t)filter_positive_count * sizeof(uint32_t));

			std::string resolve_reason;
			auto verify_start = std::chrono::steady_clock::now();
			if (!ResolveTargetLookupTag32FilterCandidates(buckets, target_keys, queries, positive_query_indices, filter_positive_count, out_indices, hit_count, false_positive_count, resolve_reason, false))
			{
				total_exact_verify_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - verify_start).count();
				error = resolve_reason;
				return false;
			}
			total_exact_verify_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - verify_start).count();

			operations += query_count;
			dispatch_count++;
			if (min_ms && local_dispatch_seconds == 0.0)
				break;
		} while (min_ms && ((total_dispatch_seconds + total_exact_verify_seconds) * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

		if (dispatch_seconds)
			*dispatch_seconds = total_dispatch_seconds;
		if (exact_verify_seconds)
			*exact_verify_seconds = total_exact_verify_seconds;

		std::string resolve_reason;
		if (!ResolveTargetLookupTag32FilterCandidates(buckets, target_keys, queries, positive_query_indices, filter_positive_count, out_indices, hit_count, false_positive_count, resolve_reason, true))
		{
			error = resolve_reason;
			return false;
		}
		return true;
	}
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
	MetalDispatchStats* dispatch_stats = NULL,
	const char* function_name = "jacobian_add_affine",
	unsigned int steps_per_sample = 0)
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
		uint32_t step_count = steps_per_sample;
		id<MTLBuffer> steps_buffer = steps_per_sample ? [device newBufferWithBytes:&step_count length:sizeof(step_count) options:MTLResourceStorageModeShared] : nil;
		if (!p_buffer || !q_buffer || !p_inf_buffer || !out_buffer || !out_inf_buffer || !count_buffer || (steps_per_sample && !steps_buffer))
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
		if (steps_per_sample)
			[encoder setBuffer:steps_buffer offset:0 atIndex:6];
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

static void PackJacobianStateInputs(const std::vector<CpuJacobianPoint>& p,
	std::vector<uint64_t>& p_xyz,
	std::vector<uint32_t>& p_infinity)
{
	p_xyz.clear();
	p_infinity.clear();
	p_xyz.reserve(p.size() * 12);
	p_infinity.reserve(p.size());
	for (size_t i = 0; i < p.size(); ++i)
	{
		for (uint64_t limb : p[i].x)
			p_xyz.push_back(limb);
		for (uint64_t limb : p[i].y)
			p_xyz.push_back(limb);
		for (uint64_t limb : p[i].z)
			p_xyz.push_back(limb);
		p_infinity.push_back(p[i].infinity ? 1U : 0U);
	}
}

static void PackJacobianXyzzStateInputs(const std::vector<CpuJacobianPoint>& p,
	std::vector<uint64_t>& p_xyzz,
	std::vector<uint32_t>& p_infinity)
{
	p_xyzz.clear();
	p_infinity.clear();
	p_xyzz.reserve(p.size() * 16);
	p_infinity.reserve(p.size());
	for (size_t i = 0; i < p.size(); ++i)
	{
		CpuXyzzPoint xyzz = CpuXyzzFromJacobian(p[i]);
		for (uint64_t limb : xyzz.x)
			p_xyzz.push_back(limb);
		for (uint64_t limb : xyzz.y)
			p_xyzz.push_back(limb);
		for (uint64_t limb : xyzz.zz)
			p_xyzz.push_back(limb);
		for (uint64_t limb : xyzz.zzz)
			p_xyzz.push_back(limb);
		p_infinity.push_back(xyzz.infinity ? 1U : 0U);
	}
}

static void PackAffineTable(const std::vector<CpuAffinePoint>& q,
	std::vector<uint64_t>& q_xy)
{
	q_xy.clear();
	q_xy.reserve(q.size() * 8);
	for (size_t i = 0; i < q.size(); ++i)
	{
		for (uint64_t limb : q[i].x)
			q_xy.push_back(limb);
		for (uint64_t limb : q[i].y)
			q_xy.push_back(limb);
	}
}

static uint64_t ProjectiveDpMask(unsigned int dp_bits);
static bool IsMetalPowerOfTwo(unsigned int value);

static bool CanAccumulateDistanceU32(const std::vector<uint64_t>& jump_distances, unsigned int steps_per_sample)
{
	uint64_t max_jump_distance = 0;
	for (uint64_t distance : jump_distances)
		if (distance > max_jump_distance)
			max_jump_distance = distance;
	return steps_per_sample == 0 || max_jump_distance <= 0xFFFFFFFFULL / steps_per_sample;
}

static bool RunJacobianJumpWalkKernel(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	const std::vector<uint32_t>& jump_indices,
	unsigned int steps_per_sample,
	std::vector<CpuJacobianPoint>& out,
	std::vector<uint64_t>& out_distances,
	std::vector<uint32_t>& out_dp_flags,
	unsigned int dp_bits,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit,
	MetalDispatchStats* dispatch_stats)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);

	if (p.empty() || jumps.empty() || jumps.size() != jump_distances.size() || steps_per_sample == 0 || jump_indices.size() != p.size() * (size_t)steps_per_sample)
	{
		error = "invalid jacobian jump walk input";
		return false;
	}
	for (uint32_t jump_index : jump_indices)
	{
		if (jump_index >= jumps.size())
		{
			error = "jacobian jump walk index out of range";
			return false;
		}
	}
	std::vector<uint8_t> metal_jump_indices;
	metal_jump_indices.reserve(jump_indices.size());
	for (uint32_t jump_index : jump_indices)
		metal_jump_indices.push_back(static_cast<uint8_t>(jump_index));

	std::vector<uint64_t> p_xyz;
	std::vector<uint64_t> q_xy;
	std::vector<uint32_t> p_infinity;
	PackJacobianStateInputs(p, p_xyz, p_infinity);
	PackAffineTable(jumps, q_xy);

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

		const bool use_dp4_specialization = steps_per_sample == 8 && dp_bits == 4;
		const char* function_name = use_dp4_specialization ? "jacobian_affine_walk_jump_table_steps8_dp4" :
			(steps_per_sample == 8 ? "jacobian_affine_walk_jump_table_steps8" : "jacobian_affine_walk_jump_table");
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

		size_t p_bytes = p_xyz.size() * sizeof(uint64_t);
		size_t q_bytes = q_xy.size() * sizeof(uint64_t);
		std::vector<uint8_t> metal_p_infinity;
		if (use_dp4_specialization)
		{
			metal_p_infinity.reserve(p_infinity.size());
			for (uint32_t p_infinity_value : p_infinity)
				metal_p_infinity.push_back(p_infinity_value ? 1U : 0U);
		}
		const void* p_inf_data = use_dp4_specialization ?
			static_cast<const void*>(metal_p_infinity.data()) : static_cast<const void*>(p_infinity.data());
		size_t p_inf_bytes = use_dp4_specialization ?
			metal_p_infinity.size() * sizeof(uint8_t) : p_infinity.size() * sizeof(uint32_t);
		size_t indices_bytes = metal_jump_indices.size() * sizeof(uint8_t);
		size_t distance_bytes = jump_distances.size() * sizeof(uint64_t);
		std::vector<uint64_t> out_xyz(p.size() * 12);
		std::vector<uint32_t> out_infinity(p.size());
		std::vector<uint8_t> out_flags_metal(p.size());
		std::vector<uint64_t> distance_out(p.size());
		size_t out_bytes = out_xyz.size() * sizeof(uint64_t);
		size_t out_flags_bytes = out_flags_metal.size() * sizeof(uint8_t);
		size_t distance_out_bytes = distance_out.size() * sizeof(uint64_t);
		id<MTLBuffer> p_buffer = [device newBufferWithBytes:p_xyz.data() length:p_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> q_buffer = [device newBufferWithBytes:q_xy.data() length:q_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> p_inf_buffer = [device newBufferWithBytes:p_inf_data length:p_inf_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_buffer = [device newBufferWithLength:out_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_flags_buffer = [device newBufferWithLength:out_flags_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_distances_buffer = [device newBufferWithLength:distance_out_bytes options:MTLResourceStorageModeShared];
		uint32_t count = (uint32_t)p.size();
		uint32_t step_count = steps_per_sample;
		uint64_t dp_mask = ProjectiveDpMask(dp_bits);
		id<MTLBuffer> count_buffer = [device newBufferWithBytes:&count length:sizeof(count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> steps_buffer = [device newBufferWithBytes:&step_count length:sizeof(step_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> dp_mask_buffer = [device newBufferWithBytes:&dp_mask length:sizeof(dp_mask) options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_indices_buffer = [device newBufferWithBytes:metal_jump_indices.data() length:indices_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_distances_buffer = [device newBufferWithBytes:jump_distances.data() length:distance_bytes options:MTLResourceStorageModeShared];
		if (!p_buffer || !q_buffer || !p_inf_buffer || !out_buffer || !out_flags_buffer || !out_distances_buffer || !count_buffer || !steps_buffer || !dp_mask_buffer || !jump_indices_buffer || !jump_distances_buffer)
		{
			error = "failed to allocate Metal jacobian jump walk buffers";
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
		[encoder setBuffer:out_flags_buffer offset:0 atIndex:4];
		[encoder setBuffer:count_buffer offset:0 atIndex:5];
		[encoder setBuffer:steps_buffer offset:0 atIndex:6];
		[encoder setBuffer:jump_indices_buffer offset:0 atIndex:7];
		[encoder setBuffer:jump_distances_buffer offset:0 atIndex:8];
		[encoder setBuffer:out_distances_buffer offset:0 atIndex:9];
		[encoder setBuffer:dp_mask_buffer offset:0 atIndex:10];
		NSUInteger threadgroup_count = (count + threads_per_threadgroup - 1) / threads_per_threadgroup;
		[encoder dispatchThreadgroups:MTLSizeMake(threadgroup_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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
		memcpy(out_flags_metal.data(), [out_flags_buffer contents], out_flags_bytes);
		memcpy(distance_out.data(), [out_distances_buffer contents], distance_out_bytes);
		out_infinity.resize(out_flags_metal.size());
		out_dp_flags.resize(out_flags_metal.size());
		for (size_t i = 0; i < out_flags_metal.size(); ++i)
		{
			uint8_t flags = out_flags_metal[i];
			out_infinity[i] = (flags & 1U) ? 1U : 0U;
			out_dp_flags[i] = (flags & 2U) ? 1U : 0U;
		}
		out.resize(p.size());
		for (size_t i = 0; i < p.size(); ++i)
			out[i] = UnpackJacobianOutput(out_xyz, out_infinity, i);
		out_distances = distance_out;
		return true;
	}
}

static bool RunJacobianDynamicJumpWalkKernel(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	std::vector<CpuJacobianPoint>& out,
	std::vector<uint64_t>& out_distances,
	std::vector<uint32_t>& out_dp_flags,
	unsigned int dp_bits,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit,
	MetalDispatchStats* dispatch_stats)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);

	if (p.empty() || jumps.empty() || jumps.size() != jump_distances.size() || steps_per_sample == 0 || jumps.size() > 32)
	{
		error = "invalid jacobian dynamic jump walk input";
		return false;
	}

	std::vector<uint64_t> p_xyz;
	std::vector<uint64_t> q_xy;
	std::vector<uint32_t> p_infinity;
	PackJacobianStateInputs(p, p_xyz, p_infinity);
	PackAffineTable(jumps, q_xy);

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

		const bool use_dynamic_dp4_specialization = steps_per_sample == 8 && dp_bits == 4;
		const bool use_dynamic_dp4_pow2_specialization = use_dynamic_dp4_specialization && IsMetalPowerOfTwo((unsigned int)jumps.size());
		const char* function_name = use_dynamic_dp4_pow2_specialization ?
			"jacobian_affine_walk_dynamic_jump_table_steps8_dp4_pow2" :
			(use_dynamic_dp4_specialization ? "jacobian_affine_walk_dynamic_jump_table_steps8_dp4" : "jacobian_affine_walk_dynamic_jump_table");
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

		size_t p_bytes = p_xyz.size() * sizeof(uint64_t);
		size_t q_bytes = q_xy.size() * sizeof(uint64_t);
		std::vector<uint8_t> dynamic_p_infinity;
		if (use_dynamic_dp4_specialization)
		{
			dynamic_p_infinity.reserve(p_infinity.size());
			for (uint32_t p_infinity_value : p_infinity)
				dynamic_p_infinity.push_back(p_infinity_value ? 1U : 0U);
		}
		const void* p_inf_data = use_dynamic_dp4_specialization ?
			static_cast<const void*>(dynamic_p_infinity.data()) : static_cast<const void*>(p_infinity.data());
		size_t p_inf_bytes = use_dynamic_dp4_specialization ?
			dynamic_p_infinity.size() * sizeof(uint8_t) : p_infinity.size() * sizeof(uint32_t);
		size_t distance_bytes = jump_distances.size() * sizeof(uint64_t);
		std::vector<uint64_t> out_xyz(p.size() * 12);
		std::vector<uint32_t> out_infinity(p.size());
		std::vector<uint8_t> out_flags_metal(p.size());
		std::vector<uint64_t> distance_out(p.size());
		size_t out_bytes = out_xyz.size() * sizeof(uint64_t);
		size_t out_flags_bytes = out_flags_metal.size() * sizeof(uint8_t);
		size_t distance_out_bytes = distance_out.size() * sizeof(uint64_t);
		id<MTLBuffer> p_buffer = [device newBufferWithBytes:p_xyz.data() length:p_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> q_buffer = [device newBufferWithBytes:q_xy.data() length:q_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> p_inf_buffer = [device newBufferWithBytes:p_inf_data length:p_inf_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_buffer = [device newBufferWithLength:out_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_flags_buffer = [device newBufferWithLength:out_flags_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_distances_buffer = [device newBufferWithLength:distance_out_bytes options:MTLResourceStorageModeShared];
		uint32_t count = (uint32_t)p.size();
		uint32_t step_count = steps_per_sample;
		uint32_t jump_count = (uint32_t)jumps.size();
		uint32_t jump_mask = jump_count - 1U;
		uint64_t dp_mask = ProjectiveDpMask(dp_bits);
		id<MTLBuffer> count_buffer = [device newBufferWithBytes:&count length:sizeof(count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> steps_buffer = [device newBufferWithBytes:&step_count length:sizeof(step_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_distances_buffer = [device newBufferWithBytes:jump_distances.data() length:distance_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> dp_mask_buffer = use_dynamic_dp4_specialization ? nil : [device newBufferWithBytes:&dp_mask length:sizeof(dp_mask) options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_count_buffer = [device newBufferWithBytes:&jump_count length:sizeof(jump_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_mask_buffer = use_dynamic_dp4_pow2_specialization ? [device newBufferWithBytes:&jump_mask length:sizeof(jump_mask) options:MTLResourceStorageModeShared] : nil;
		if (!p_buffer || !q_buffer || !p_inf_buffer || !out_buffer || !out_flags_buffer || !out_distances_buffer || !count_buffer || !steps_buffer || !jump_distances_buffer || (!use_dynamic_dp4_specialization && !dp_mask_buffer) || (!use_dynamic_dp4_pow2_specialization && !jump_count_buffer) || (use_dynamic_dp4_pow2_specialization && !jump_mask_buffer))
		{
			error = "failed to allocate Metal jacobian dynamic jump walk buffers";
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
		[encoder setBuffer:out_flags_buffer offset:0 atIndex:4];
		[encoder setBuffer:count_buffer offset:0 atIndex:5];
		[encoder setBuffer:steps_buffer offset:0 atIndex:6];
		[encoder setBuffer:jump_distances_buffer offset:0 atIndex:7];
		[encoder setBuffer:out_distances_buffer offset:0 atIndex:8];
		if (use_dynamic_dp4_pow2_specialization)
		{
			[encoder setBuffer:jump_mask_buffer offset:0 atIndex:9];
		}
		else if (use_dynamic_dp4_specialization)
		{
			[encoder setBuffer:jump_count_buffer offset:0 atIndex:9];
		}
		else
		{
			[encoder setBuffer:dp_mask_buffer offset:0 atIndex:9];
			[encoder setBuffer:jump_count_buffer offset:0 atIndex:10];
		}
		NSUInteger threadgroup_count = (count + threads_per_threadgroup - 1) / threads_per_threadgroup;
		[encoder dispatchThreadgroups:MTLSizeMake(threadgroup_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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
		memcpy(out_flags_metal.data(), [out_flags_buffer contents], out_flags_bytes);
		memcpy(distance_out.data(), [out_distances_buffer contents], distance_out_bytes);
		out_infinity.resize(out_flags_metal.size());
		out_dp_flags.resize(out_flags_metal.size());
		for (size_t i = 0; i < out_flags_metal.size(); ++i)
		{
			uint8_t flags = out_flags_metal[i];
			out_infinity[i] = (flags & 1U) ? 1U : 0U;
			out_dp_flags[i] = (flags & 2U) ? 1U : 0U;
		}
		out.resize(p.size());
		for (size_t i = 0; i < p.size(); ++i)
			out[i] = UnpackJacobianOutput(out_xyz, out_infinity, i);
		out_distances = distance_out;
		return true;
	}
}

static bool RunJacobianDynamicCompactDpKernel(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	std::vector<uint8_t>& out_flags,
	std::vector<uint64_t>& out_distances,
	std::vector<uint64_t>& out_dp_terms,
	unsigned int dp_bits,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit,
	MetalDispatchStats* dispatch_stats)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);

	if (p.empty() || jumps.empty() || jumps.size() != jump_distances.size() || steps_per_sample != 8 || dp_bits != 4 || !IsMetalPowerOfTwo((unsigned int)jumps.size()) || jumps.size() > 32)
	{
		error = "invalid jacobian dynamic compact dp input";
		return false;
	}

	std::vector<uint64_t> p_xyz;
	std::vector<uint64_t> q_xy;
	std::vector<uint32_t> p_infinity;
	PackJacobianStateInputs(p, p_xyz, p_infinity);
	PackAffineTable(jumps, q_xy);

	std::vector<uint8_t> dynamic_p_infinity;
	dynamic_p_infinity.reserve(p_infinity.size());
	for (uint32_t p_infinity_value : p_infinity)
		dynamic_p_infinity.push_back(p_infinity_value ? 1U : 0U);

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

		const char* function_name = "jacobian_affine_walk_dynamic_dp_compact_steps8_dp4_pow2";
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

		size_t p_bytes = p_xyz.size() * sizeof(uint64_t);
		size_t q_bytes = q_xy.size() * sizeof(uint64_t);
		size_t p_inf_bytes = dynamic_p_infinity.size() * sizeof(uint8_t);
		size_t distance_bytes = jump_distances.size() * sizeof(uint64_t);
		std::vector<uint8_t> out_flags_metal(p.size());
		std::vector<uint64_t> distance_out(p.size());
		std::vector<uint64_t> dp_terms_out(p.size());
		size_t out_flags_bytes = out_flags_metal.size() * sizeof(uint8_t);
		size_t distance_out_bytes = distance_out.size() * sizeof(uint64_t);
		size_t dp_terms_bytes = dp_terms_out.size() * sizeof(uint64_t);
		id<MTLBuffer> p_buffer = [device newBufferWithBytes:p_xyz.data() length:p_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> q_buffer = [device newBufferWithBytes:q_xy.data() length:q_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> p_inf_buffer = [device newBufferWithBytes:dynamic_p_infinity.data() length:p_inf_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_flags_buffer = [device newBufferWithLength:out_flags_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_distances_buffer = [device newBufferWithLength:distance_out_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_dp_terms_buffer = [device newBufferWithLength:dp_terms_bytes options:MTLResourceStorageModeShared];
		uint32_t count = (uint32_t)p.size();
		uint32_t step_count = steps_per_sample;
		uint32_t jump_mask = (uint32_t)jumps.size() - 1U;
		id<MTLBuffer> count_buffer = [device newBufferWithBytes:&count length:sizeof(count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> steps_buffer = [device newBufferWithBytes:&step_count length:sizeof(step_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_distances_buffer = [device newBufferWithBytes:jump_distances.data() length:distance_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_mask_buffer = [device newBufferWithBytes:&jump_mask length:sizeof(jump_mask) options:MTLResourceStorageModeShared];
		if (!p_buffer || !q_buffer || !p_inf_buffer || !out_flags_buffer || !out_distances_buffer || !out_dp_terms_buffer || !count_buffer || !steps_buffer || !jump_distances_buffer || !jump_mask_buffer)
		{
			error = "failed to allocate Metal jacobian dynamic compact dp buffers";
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
		[encoder setBuffer:out_flags_buffer offset:0 atIndex:4];
		[encoder setBuffer:count_buffer offset:0 atIndex:5];
		[encoder setBuffer:steps_buffer offset:0 atIndex:6];
		[encoder setBuffer:jump_distances_buffer offset:0 atIndex:7];
		[encoder setBuffer:out_distances_buffer offset:0 atIndex:8];
		[encoder setBuffer:out_dp_terms_buffer offset:0 atIndex:9];
		[encoder setBuffer:jump_mask_buffer offset:0 atIndex:10];
		NSUInteger threadgroup_count = (count + threads_per_threadgroup - 1) / threads_per_threadgroup;
		[encoder dispatchThreadgroups:MTLSizeMake(threadgroup_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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

		memcpy(out_flags_metal.data(), [out_flags_buffer contents], out_flags_bytes);
		memcpy(distance_out.data(), [out_distances_buffer contents], distance_out_bytes);
		memcpy(dp_terms_out.data(), [out_dp_terms_buffer contents], dp_terms_bytes);
		out_flags = out_flags_metal;
		out_distances = distance_out;
		out_dp_terms = dp_terms_out;
		return true;
	}
}

static bool RunJacobianDynamicDpStreamKernel(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	std::vector<uint32_t>& out_indices,
	std::vector<uint64_t>& out_distances,
	std::vector<uint64_t>& out_dp_terms,
	uint32_t& emitted_records,
	bool& dp_stream_overflow,
	unsigned int dp_bits,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit,
	MetalDispatchStats* dispatch_stats)
{
	NSUInteger effective_threadgroup_limit = EffectiveDynamicDpStreamThreadgroupLimit(threadgroup_limit, dp_bits);
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)effective_threadgroup_limit;

	if (p.empty() || jumps.empty() || jumps.size() != jump_distances.size() || steps_per_sample != 8 || dp_bits > 32 || !IsMetalPowerOfTwo((unsigned int)jumps.size()) || jumps.size() > 32)
	{
		error = "invalid jacobian dynamic dp stream input";
		return false;
	}

	std::vector<uint64_t> p_xyz;
	std::vector<uint64_t> q_xy;
	std::vector<uint32_t> p_infinity;
	PackJacobianStateInputs(p, p_xyz, p_infinity);
	PackAffineTable(jumps, q_xy);

	std::vector<uint8_t> dynamic_p_infinity;
	dynamic_p_infinity.reserve(p_infinity.size());
	for (uint32_t p_infinity_value : p_infinity)
		dynamic_p_infinity.push_back(p_infinity_value ? 1U : 0U);

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

		const bool use_stream_dp4_specialization = dp_bits == 4;
		const bool use_stream_dp8_specialization = dp_bits == 8 && CanAccumulateDistanceU32(jump_distances, steps_per_sample);
		const bool use_stream_u32_distance = !use_stream_dp4_specialization && !use_stream_dp8_specialization && CanAccumulateDistanceU32(jump_distances, steps_per_sample);
		const char* function_name = use_stream_dp4_specialization
			? "jacobian_affine_walk_dynamic_dp_stream_steps8_dp4_pow2"
			: (use_stream_dp8_specialization
				? "jacobian_affine_walk_dynamic_dp_stream_steps8_dp8_pow2_u32_distance"
				: (use_stream_u32_distance
					? "jacobian_affine_walk_dynamic_dp_stream_steps8_pow2_mask_u32_distance"
					: "jacobian_affine_walk_dynamic_dp_stream_steps8_pow2_mask"));
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
		NSUInteger threads_per_threadgroup = PreferredThreadgroupWidth(pipeline, (unsigned int)effective_threadgroup_limit);
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t p_bytes = p_xyz.size() * sizeof(uint64_t);
		size_t q_bytes = q_xy.size() * sizeof(uint64_t);
		size_t p_inf_bytes = dynamic_p_infinity.size() * sizeof(uint8_t);
		size_t distance_bytes = jump_distances.size() * sizeof(uint64_t);
		uint32_t count = (uint32_t)p.size();
		uint32_t step_count = steps_per_sample;
		uint32_t jump_mask = (uint32_t)jumps.size() - 1U;
		uint64_t dp_mask = ProjectiveDpMask(dp_bits);
		uint32_t dp_capacity = count;
		uint32_t zero = 0;
		std::vector<uint32_t> indices_out(dp_capacity);
		std::vector<uint64_t> distances_out(dp_capacity);
		std::vector<uint64_t> dp_terms_out(dp_capacity);
		size_t indices_bytes = indices_out.size() * sizeof(uint32_t);
		size_t distances_out_bytes = distances_out.size() * sizeof(uint64_t);
		size_t dp_terms_bytes = dp_terms_out.size() * sizeof(uint64_t);
		id<MTLBuffer> p_buffer = [device newBufferWithBytes:p_xyz.data() length:p_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> q_buffer = [device newBufferWithBytes:q_xy.data() length:q_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> p_inf_buffer = [device newBufferWithBytes:dynamic_p_infinity.data() length:p_inf_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> dp_count_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> indices_buffer = [device newBufferWithLength:indices_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> count_buffer = [device newBufferWithBytes:&count length:sizeof(count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> steps_buffer = [device newBufferWithBytes:&step_count length:sizeof(step_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_distances_buffer = [device newBufferWithBytes:jump_distances.data() length:distance_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_distances_buffer = [device newBufferWithLength:distances_out_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_dp_terms_buffer = [device newBufferWithLength:dp_terms_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_mask_buffer = [device newBufferWithBytes:&jump_mask length:sizeof(jump_mask) options:MTLResourceStorageModeShared];
		id<MTLBuffer> dp_capacity_buffer = [device newBufferWithBytes:&dp_capacity length:sizeof(dp_capacity) options:MTLResourceStorageModeShared];
		id<MTLBuffer> overflow_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> dp_mask_buffer = (use_stream_dp4_specialization || use_stream_dp8_specialization) ? nil : [device newBufferWithBytes:&dp_mask length:sizeof(dp_mask) options:MTLResourceStorageModeShared];
		if (!p_buffer || !q_buffer || !p_inf_buffer || !dp_count_buffer || !indices_buffer || !count_buffer || !steps_buffer || !jump_distances_buffer || !out_distances_buffer || !out_dp_terms_buffer || !jump_mask_buffer || !dp_capacity_buffer || !overflow_buffer || ((!use_stream_dp4_specialization && !use_stream_dp8_specialization) && !dp_mask_buffer))
		{
			error = "failed to allocate Metal jacobian dynamic dp stream buffers";
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
		[encoder setBuffer:dp_count_buffer offset:0 atIndex:4];
		[encoder setBuffer:indices_buffer offset:0 atIndex:5];
		[encoder setBuffer:count_buffer offset:0 atIndex:6];
		[encoder setBuffer:steps_buffer offset:0 atIndex:7];
		[encoder setBuffer:jump_distances_buffer offset:0 atIndex:8];
		[encoder setBuffer:out_distances_buffer offset:0 atIndex:9];
		[encoder setBuffer:out_dp_terms_buffer offset:0 atIndex:10];
		[encoder setBuffer:jump_mask_buffer offset:0 atIndex:11];
		[encoder setBuffer:dp_capacity_buffer offset:0 atIndex:12];
		[encoder setBuffer:overflow_buffer offset:0 atIndex:13];
		if (!use_stream_dp4_specialization && !use_stream_dp8_specialization)
			[encoder setBuffer:dp_mask_buffer offset:0 atIndex:14];
		NSUInteger threadgroup_count = (count + threads_per_threadgroup - 1) / threads_per_threadgroup;
		[encoder dispatchThreadgroups:MTLSizeMake(threadgroup_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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

		uint32_t emitted_raw = 0;
		uint32_t overflow_raw = 0;
		memcpy(&emitted_raw, [dp_count_buffer contents], sizeof(emitted_raw));
		memcpy(&overflow_raw, [overflow_buffer contents], sizeof(overflow_raw));
		emitted_records = emitted_raw < dp_capacity ? emitted_raw : dp_capacity;
		dp_stream_overflow = overflow_raw != 0 || emitted_raw > dp_capacity;
		size_t emitted_indices_bytes = (size_t)emitted_records * sizeof(uint32_t);
		size_t emitted_distances_bytes = (size_t)emitted_records * sizeof(uint64_t);
		size_t emitted_dp_terms_bytes = (size_t)emitted_records * sizeof(uint64_t);
		memcpy(indices_out.data(), [indices_buffer contents], emitted_indices_bytes);
		memcpy(distances_out.data(), [out_distances_buffer contents], emitted_distances_bytes);
		memcpy(dp_terms_out.data(), [out_dp_terms_buffer contents], emitted_dp_terms_bytes);
		indices_out.resize(emitted_records);
		distances_out.resize(emitted_records);
		dp_terms_out.resize(emitted_records);
		out_indices = indices_out;
		out_distances = distances_out;
		out_dp_terms = dp_terms_out;
		return true;
	}
}

static bool RunJacobianDynamicDpStreamInplaceKernel(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	std::vector<CpuJacobianPoint>& state_out,
	std::vector<uint32_t>& out_indices,
	std::vector<uint64_t>& out_distances,
	std::vector<uint64_t>& out_dp_terms,
	uint32_t& emitted_records,
	bool& dp_stream_overflow,
	unsigned int dp_bits,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit,
	MetalDispatchStats* dispatch_stats)
{
	NSUInteger effective_threadgroup_limit = EffectiveDynamicDpStreamInplaceThreadgroupLimit(threadgroup_limit, dp_bits, steps_per_sample);
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)effective_threadgroup_limit;

	if (p.empty() || jumps.empty() || jumps.size() != jump_distances.size() || (steps_per_sample != 8 && steps_per_sample != 16 && steps_per_sample != 32 && steps_per_sample != 64 && steps_per_sample != 128 && steps_per_sample != 256) || dp_bits != 8 || !IsMetalPowerOfTwo((unsigned int)jumps.size()) || jumps.size() > 32)
	{
		error = "invalid jacobian dynamic dp stream in-place input";
		return false;
	}
	if (!CanAccumulateDistanceU32(jump_distances, steps_per_sample))
	{
		error = "in-place dynamic dp stream packet distance exceeds uint32 accumulator";
		return false;
	}

	std::vector<uint64_t> p_xyz;
	std::vector<uint64_t> q_xy;
	std::vector<uint32_t> p_infinity;
	PackJacobianStateInputs(p, p_xyz, p_infinity);
	PackAffineTable(jumps, q_xy);

	std::vector<uint8_t> dynamic_p_infinity;
	dynamic_p_infinity.reserve(p_infinity.size());
	for (uint32_t p_infinity_value : p_infinity)
		dynamic_p_infinity.push_back(p_infinity_value ? 1U : 0U);

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

		const char* function_name = steps_per_sample == 256
			? "jacobian_affine_walk_dynamic_dp_stream_inplace_steps256_dp8_pow2_u32_distance"
			: (steps_per_sample == 128
				? "jacobian_affine_walk_dynamic_dp_stream_inplace_steps128_dp8_pow2_u32_distance"
				: (steps_per_sample == 64
					? "jacobian_affine_walk_dynamic_dp_stream_inplace_steps64_dp8_pow2_u32_distance"
					: (steps_per_sample == 32
						? "jacobian_affine_walk_dynamic_dp_stream_inplace_steps32_dp8_pow2_u32_distance"
						: (steps_per_sample == 16
							? "jacobian_affine_walk_dynamic_dp_stream_inplace_steps16_dp8_pow2_u32_distance"
							: "jacobian_affine_walk_dynamic_dp_stream_inplace_steps8_dp8_pow2_u32_distance"))));
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
		NSUInteger threads_per_threadgroup = PreferredThreadgroupWidth(pipeline, (unsigned int)effective_threadgroup_limit);
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t p_bytes = p_xyz.size() * sizeof(uint64_t);
		size_t q_bytes = q_xy.size() * sizeof(uint64_t);
		size_t p_inf_bytes = dynamic_p_infinity.size() * sizeof(uint8_t);
		size_t distance_bytes = jump_distances.size() * sizeof(uint64_t);
		uint32_t count = (uint32_t)p.size();
		uint32_t jump_mask = (uint32_t)jumps.size() - 1U;
		uint32_t dp_capacity = count;
		uint32_t zero = 0;
		std::vector<uint32_t> indices_out(dp_capacity);
		std::vector<uint64_t> distances_out(dp_capacity);
		std::vector<uint64_t> dp_terms_out(dp_capacity);
		size_t indices_bytes = indices_out.size() * sizeof(uint32_t);
		size_t distances_out_bytes = distances_out.size() * sizeof(uint64_t);
		size_t dp_terms_bytes = dp_terms_out.size() * sizeof(uint64_t);
		id<MTLBuffer> p_buffer = [device newBufferWithBytes:p_xyz.data() length:p_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> q_buffer = [device newBufferWithBytes:q_xy.data() length:q_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> p_inf_buffer = [device newBufferWithBytes:dynamic_p_infinity.data() length:p_inf_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> dp_count_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> indices_buffer = [device newBufferWithLength:indices_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> count_buffer = [device newBufferWithBytes:&count length:sizeof(count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_distances_buffer = [device newBufferWithBytes:jump_distances.data() length:distance_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_distances_buffer = [device newBufferWithLength:distances_out_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_dp_terms_buffer = [device newBufferWithLength:dp_terms_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_mask_buffer = [device newBufferWithBytes:&jump_mask length:sizeof(jump_mask) options:MTLResourceStorageModeShared];
		if (!p_buffer || !q_buffer || !p_inf_buffer || !dp_count_buffer || !indices_buffer || !count_buffer || !jump_distances_buffer || !out_distances_buffer || !out_dp_terms_buffer || !jump_mask_buffer)
		{
			error = "failed to allocate Metal jacobian dynamic dp stream in-place buffers";
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
		[encoder setBuffer:dp_count_buffer offset:0 atIndex:4];
		[encoder setBuffer:indices_buffer offset:0 atIndex:5];
		[encoder setBuffer:count_buffer offset:0 atIndex:6];
		[encoder setBuffer:jump_distances_buffer offset:0 atIndex:8];
		[encoder setBuffer:out_distances_buffer offset:0 atIndex:9];
		[encoder setBuffer:out_dp_terms_buffer offset:0 atIndex:10];
		[encoder setBuffer:jump_mask_buffer offset:0 atIndex:11];
		NSUInteger threadgroup_count = (count + threads_per_threadgroup - 1) / threads_per_threadgroup;
		[encoder dispatchThreadgroups:MTLSizeMake(threadgroup_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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

		uint32_t emitted_raw = 0;
		memcpy(&emitted_raw, [dp_count_buffer contents], sizeof(emitted_raw));
		emitted_records = emitted_raw < dp_capacity ? emitted_raw : dp_capacity;
		dp_stream_overflow = emitted_raw > dp_capacity;
		size_t emitted_indices_bytes = (size_t)emitted_records * sizeof(uint32_t);
		size_t emitted_distances_bytes = (size_t)emitted_records * sizeof(uint64_t);
		size_t emitted_dp_terms_bytes = (size_t)emitted_records * sizeof(uint64_t);
		memcpy(indices_out.data(), [indices_buffer contents], emitted_indices_bytes);
		memcpy(distances_out.data(), [out_distances_buffer contents], emitted_distances_bytes);
		memcpy(dp_terms_out.data(), [out_dp_terms_buffer contents], emitted_dp_terms_bytes);
		memcpy(p_xyz.data(), [p_buffer contents], p_bytes);
		memcpy(dynamic_p_infinity.data(), [p_inf_buffer contents], p_inf_bytes);
		indices_out.resize(emitted_records);
		distances_out.resize(emitted_records);
		dp_terms_out.resize(emitted_records);
		out_indices = indices_out;
		out_distances = distances_out;
		out_dp_terms = dp_terms_out;
		state_out.clear();
		state_out.reserve(p.size());
		for (size_t i = 0; i < p.size(); ++i)
		{
			CpuJacobianPoint point;
			size_t base = i * 12;
			for (size_t limb = 0; limb < 4; ++limb)
				point.x[limb] = p_xyz[base + limb];
			for (size_t limb = 0; limb < 4; ++limb)
				point.y[limb] = p_xyz[base + 4 + limb];
			for (size_t limb = 0; limb < 4; ++limb)
				point.z[limb] = p_xyz[base + 8 + limb];
			point.infinity = dynamic_p_infinity[i] != 0;
			state_out.push_back(point);
		}
		return true;
	}
}

static bool RunJacobianDynamicDpStreamXyzzKernel(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	std::vector<CpuXyzzPoint>& state_out,
	std::vector<uint32_t>& out_indices,
	std::vector<uint64_t>& out_distances,
	std::vector<uint64_t>& out_dp_terms,
	uint32_t& emitted_records,
	bool& dp_stream_overflow,
	unsigned int dp_bits,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit,
	MetalDispatchStats* dispatch_stats)
{
	NSUInteger effective_threadgroup_limit = EffectiveDynamicDpStreamInplaceThreadgroupLimit(threadgroup_limit, dp_bits, steps_per_sample);
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)effective_threadgroup_limit;

	if (p.empty() || jumps.empty() || jumps.size() != jump_distances.size() || (steps_per_sample != 256 && steps_per_sample != 512) || dp_bits > 32 || !IsMetalPowerOfTwo((unsigned int)jumps.size()) || jumps.size() > 32)
	{
		error = "invalid jacobian dynamic dp stream XYZZ input";
		return false;
	}
	if (!CanAccumulateDistanceU32(jump_distances, steps_per_sample))
	{
		error = "XYZZ dynamic dp stream packet distance exceeds uint32 accumulator";
		return false;
	}

	std::vector<uint64_t> p_xyzz;
	std::vector<uint64_t> q_xy;
	std::vector<uint32_t> p_infinity;
	PackJacobianXyzzStateInputs(p, p_xyzz, p_infinity);
	PackAffineTable(jumps, q_xy);

	std::vector<uint8_t> dynamic_p_infinity;
	dynamic_p_infinity.reserve(p_infinity.size());
	for (uint32_t p_infinity_value : p_infinity)
		dynamic_p_infinity.push_back(p_infinity_value ? 1U : 0U);

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

		const bool use_xyzz_dp8_specialization = dp_bits == 8;
		const bool use_xyzz_dp12_specialization = dp_bits == 12;
		const bool use_xyzz_dp16_specialization = dp_bits == 16;
		const bool use_xyzz_hardcoded_dp_specialization = use_xyzz_dp8_specialization || use_xyzz_dp12_specialization || use_xyzz_dp16_specialization;
		const char* function_name = use_xyzz_dp8_specialization
			? (steps_per_sample == 512
				? "jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp8_pow2_u32_distance"
				: "jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp8_pow2_u32_distance")
			: (use_xyzz_dp12_specialization
				? (steps_per_sample == 512
					? "jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp12_pow2_u32_distance"
					: "jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp12_pow2_u32_distance")
				: (use_xyzz_dp16_specialization
					? (steps_per_sample == 512
						? "jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_dp16_pow2_u32_distance"
						: "jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_dp16_pow2_u32_distance")
					: (steps_per_sample == 512
						? "jacobian_affine_walk_dynamic_dp_stream_xyzz_steps512_pow2_u32_distance"
						: "jacobian_affine_walk_dynamic_dp_stream_xyzz_steps256_pow2_u32_distance")));
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
		NSUInteger threads_per_threadgroup = PreferredThreadgroupWidth(pipeline, (unsigned int)effective_threadgroup_limit);
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t p_bytes = p_xyzz.size() * sizeof(uint64_t);
		size_t q_bytes = q_xy.size() * sizeof(uint64_t);
		size_t p_inf_bytes = dynamic_p_infinity.size() * sizeof(uint8_t);
		size_t distance_bytes = jump_distances.size() * sizeof(uint64_t);
		uint32_t count = (uint32_t)p.size();
		uint32_t jump_mask = (uint32_t)jumps.size() - 1U;
		uint64_t dp_mask = ProjectiveDpMask(dp_bits);
		uint32_t dp_capacity = count;
		uint32_t zero = 0;
		std::vector<uint32_t> indices_out(dp_capacity);
		std::vector<uint64_t> distances_out(dp_capacity);
		std::vector<uint64_t> dp_terms_out(dp_capacity);
		size_t indices_bytes = indices_out.size() * sizeof(uint32_t);
		size_t distances_out_bytes = distances_out.size() * sizeof(uint64_t);
		size_t dp_terms_bytes = dp_terms_out.size() * sizeof(uint64_t);
		id<MTLBuffer> p_buffer = [device newBufferWithBytes:p_xyzz.data() length:p_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> q_buffer = [device newBufferWithBytes:q_xy.data() length:q_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> p_inf_buffer = [device newBufferWithBytes:dynamic_p_infinity.data() length:p_inf_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> dp_count_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> indices_buffer = [device newBufferWithLength:indices_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> count_buffer = [device newBufferWithBytes:&count length:sizeof(count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_distances_buffer = [device newBufferWithBytes:jump_distances.data() length:distance_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_distances_buffer = [device newBufferWithLength:distances_out_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_dp_terms_buffer = [device newBufferWithLength:dp_terms_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_mask_buffer = [device newBufferWithBytes:&jump_mask length:sizeof(jump_mask) options:MTLResourceStorageModeShared];
		id<MTLBuffer> dp_mask_buffer = use_xyzz_hardcoded_dp_specialization ? nil : [device newBufferWithBytes:&dp_mask length:sizeof(dp_mask) options:MTLResourceStorageModeShared];
		if (!p_buffer || !q_buffer || !p_inf_buffer || !dp_count_buffer || !indices_buffer || !count_buffer || !jump_distances_buffer || !out_distances_buffer || !out_dp_terms_buffer || !jump_mask_buffer || (!use_xyzz_hardcoded_dp_specialization && !dp_mask_buffer))
		{
			error = "failed to allocate Metal jacobian dynamic dp stream XYZZ buffers";
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
		[encoder setBuffer:dp_count_buffer offset:0 atIndex:4];
		[encoder setBuffer:indices_buffer offset:0 atIndex:5];
		[encoder setBuffer:count_buffer offset:0 atIndex:6];
		[encoder setBuffer:jump_distances_buffer offset:0 atIndex:8];
		[encoder setBuffer:out_distances_buffer offset:0 atIndex:9];
		[encoder setBuffer:out_dp_terms_buffer offset:0 atIndex:10];
		[encoder setBuffer:jump_mask_buffer offset:0 atIndex:11];
		if (!use_xyzz_hardcoded_dp_specialization)
			[encoder setBuffer:dp_mask_buffer offset:0 atIndex:14];
		NSUInteger threadgroup_count = (count + threads_per_threadgroup - 1) / threads_per_threadgroup;
		[encoder dispatchThreadgroups:MTLSizeMake(threadgroup_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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

		uint32_t emitted_raw = 0;
		memcpy(&emitted_raw, [dp_count_buffer contents], sizeof(emitted_raw));
		emitted_records = emitted_raw < dp_capacity ? emitted_raw : dp_capacity;
		dp_stream_overflow = emitted_raw > dp_capacity;
		size_t emitted_indices_bytes = (size_t)emitted_records * sizeof(uint32_t);
		size_t emitted_distances_bytes = (size_t)emitted_records * sizeof(uint64_t);
		size_t emitted_dp_terms_bytes = (size_t)emitted_records * sizeof(uint64_t);
		memcpy(indices_out.data(), [indices_buffer contents], emitted_indices_bytes);
		memcpy(distances_out.data(), [out_distances_buffer contents], emitted_distances_bytes);
		memcpy(dp_terms_out.data(), [out_dp_terms_buffer contents], emitted_dp_terms_bytes);
		memcpy(p_xyzz.data(), [p_buffer contents], p_bytes);
		memcpy(dynamic_p_infinity.data(), [p_inf_buffer contents], p_inf_bytes);
		indices_out.resize(emitted_records);
		distances_out.resize(emitted_records);
		dp_terms_out.resize(emitted_records);
		out_indices = indices_out;
		out_distances = distances_out;
		out_dp_terms = dp_terms_out;
		state_out.clear();
		state_out.reserve(p.size());
		for (size_t i = 0; i < p.size(); ++i)
		{
			CpuXyzzPoint point;
			size_t base = i * 16;
			for (size_t limb = 0; limb < 4; ++limb)
				point.x[limb] = p_xyzz[base + limb];
			for (size_t limb = 0; limb < 4; ++limb)
				point.y[limb] = p_xyzz[base + 4 + limb];
			for (size_t limb = 0; limb < 4; ++limb)
				point.zz[limb] = p_xyzz[base + 8 + limb];
			for (size_t limb = 0; limb < 4; ++limb)
				point.zzz[limb] = p_xyzz[base + 12 + limb];
			point.infinity = dynamic_p_infinity[i] != 0;
			state_out.push_back(point);
		}
		return true;
	}
}

static bool RunJacobianDynamicXyzzDistanceKernel(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	std::vector<CpuXyzzPoint>& state_out,
	std::vector<uint64_t>& distances_out,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit,
	MetalDispatchStats* dispatch_stats)
{
	NSUInteger effective_threadgroup_limit = EffectiveDynamicDpStreamInplaceThreadgroupLimit(threadgroup_limit, 8, steps_per_sample);
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)effective_threadgroup_limit;

	if (p.empty() || jumps.empty() || jumps.size() != jump_distances.size() || (steps_per_sample != 256 && steps_per_sample != 512) || !IsMetalPowerOfTwo((unsigned int)jumps.size()) || jumps.size() > 32 || p.size() > 0xFFFFFFFFULL)
	{
		error = "invalid jacobian dynamic XYZZ distance input";
		return false;
	}
	if (!CanAccumulateDistanceU32(jump_distances, steps_per_sample))
	{
		error = "XYZZ dynamic distance packet exceeds uint32 accumulator";
		return false;
	}

	std::vector<uint64_t> p_xyzz;
	std::vector<uint64_t> q_xy;
	std::vector<uint32_t> p_infinity;
	PackJacobianXyzzStateInputs(p, p_xyzz, p_infinity);
	PackAffineTable(jumps, q_xy);

	std::vector<uint8_t> dynamic_p_infinity;
	dynamic_p_infinity.reserve(p_infinity.size());
	for (uint32_t p_infinity_value : p_infinity)
		dynamic_p_infinity.push_back(p_infinity_value ? 1U : 0U);
	std::vector<uint64_t> distances(p.size(), 0);

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

		const char* function_name = steps_per_sample == 512
			? "jacobian_affine_walk_dynamic_xyzz_steps512_pow2_u32_distance"
			: "jacobian_affine_walk_dynamic_xyzz_steps256_pow2_u32_distance";
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
		NSUInteger threads_per_threadgroup = PreferredThreadgroupWidth(pipeline, (unsigned int)effective_threadgroup_limit);
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t p_bytes = p_xyzz.size() * sizeof(uint64_t);
		size_t q_bytes = q_xy.size() * sizeof(uint64_t);
		size_t p_inf_bytes = dynamic_p_infinity.size() * sizeof(uint8_t);
		size_t distance_bytes = jump_distances.size() * sizeof(uint64_t);
		size_t distances_out_bytes = distances.size() * sizeof(uint64_t);
		uint32_t count = (uint32_t)p.size();
		uint32_t jump_mask = (uint32_t)jumps.size() - 1U;
		id<MTLBuffer> p_buffer = [device newBufferWithBytes:p_xyzz.data() length:p_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> q_buffer = [device newBufferWithBytes:q_xy.data() length:q_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> p_inf_buffer = [device newBufferWithBytes:dynamic_p_infinity.data() length:p_inf_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_distances_buffer = [device newBufferWithLength:distances_out_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> count_buffer = [device newBufferWithBytes:&count length:sizeof(count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_distances_buffer = [device newBufferWithBytes:jump_distances.data() length:distance_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_mask_buffer = [device newBufferWithBytes:&jump_mask length:sizeof(jump_mask) options:MTLResourceStorageModeShared];
		if (!p_buffer || !q_buffer || !p_inf_buffer || !out_distances_buffer || !count_buffer || !jump_distances_buffer || !jump_mask_buffer)
		{
			error = "failed to allocate Metal jacobian dynamic XYZZ distance buffers";
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
		[encoder setBuffer:out_distances_buffer offset:0 atIndex:4];
		[encoder setBuffer:count_buffer offset:0 atIndex:6];
		[encoder setBuffer:jump_distances_buffer offset:0 atIndex:8];
		[encoder setBuffer:jump_mask_buffer offset:0 atIndex:11];
		NSUInteger threadgroup_count = (count + threads_per_threadgroup - 1) / threads_per_threadgroup;
		[encoder dispatchThreadgroups:MTLSizeMake(threadgroup_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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

		memcpy(distances.data(), [out_distances_buffer contents], distances_out_bytes);
		memcpy(p_xyzz.data(), [p_buffer contents], p_bytes);
		memcpy(dynamic_p_infinity.data(), [p_inf_buffer contents], p_inf_bytes);
		distances_out = distances;
		state_out.clear();
		state_out.reserve(p.size());
		for (size_t i = 0; i < p.size(); ++i)
		{
			CpuXyzzPoint point;
			size_t base = i * 16;
			for (size_t limb = 0; limb < 4; ++limb)
				point.x[limb] = p_xyzz[base + limb];
			for (size_t limb = 0; limb < 4; ++limb)
				point.y[limb] = p_xyzz[base + 4 + limb];
			for (size_t limb = 0; limb < 4; ++limb)
				point.zz[limb] = p_xyzz[base + 8 + limb];
			for (size_t limb = 0; limb < 4; ++limb)
				point.zzz[limb] = p_xyzz[base + 12 + limb];
			point.infinity = dynamic_p_infinity[i] != 0;
			state_out.push_back(point);
		}
		return true;
	}
}

static bool RunJacobianDynamicDpStreamXyzzPersistentChainKernel(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	unsigned int packet_count,
	unsigned int round_count,
	std::vector<CpuXyzzPoint>& state_out,
	std::vector<uint32_t>& out_indices,
	std::vector<uint64_t>& out_distances,
	std::vector<uint64_t>& out_dp_terms,
	uint32_t& emitted_records,
	bool& dp_stream_overflow,
	unsigned int dp_bits,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit,
	MetalDispatchStats* dispatch_stats)
{
	NSUInteger effective_threadgroup_limit = EffectiveDynamicDpStreamInplaceThreadgroupLimit(threadgroup_limit, dp_bits, steps_per_sample);
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)effective_threadgroup_limit;

	uint64_t total_packet_count = (uint64_t)packet_count * round_count;
	uint64_t total_record_capacity = (uint64_t)p.size() * total_packet_count;
	if (p.empty() || jumps.empty() || jumps.size() != jump_distances.size() || (steps_per_sample != 256 && steps_per_sample != 512) || packet_count == 0 || round_count == 0 || total_packet_count > 0xFFFFFFFFULL || dp_bits > 32 || !IsMetalPowerOfTwo((unsigned int)jumps.size()) || jumps.size() > 32 || p.size() > 0xFFFFFFFFULL || total_record_capacity > 0xFFFFFFFFULL)
	{
		error = "invalid jacobian dynamic dp stream XYZZ persistent chain input";
		return false;
	}
	if (!CanAccumulateDistanceU32(jump_distances, steps_per_sample))
	{
		error = "XYZZ dynamic dp stream packet distance exceeds uint32 accumulator";
		return false;
	}

	std::vector<uint64_t> p_xyzz;
	std::vector<uint64_t> q_xy;
	std::vector<uint32_t> p_infinity;
	PackJacobianXyzzStateInputs(p, p_xyzz, p_infinity);
	PackAffineTable(jumps, q_xy);

	std::vector<uint8_t> dynamic_p_infinity;
	dynamic_p_infinity.reserve(p_infinity.size());
	for (uint32_t p_infinity_value : p_infinity)
		dynamic_p_infinity.push_back(p_infinity_value ? 1U : 0U);
	std::vector<uint64_t> cumulative_distances(p.size(), 0);

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

		const bool use_xyzz_dp8_specialization = dp_bits == 8;
		const bool use_xyzz_dp12_specialization = dp_bits == 12;
		const bool use_xyzz_dp16_specialization = dp_bits == 16;
		const bool use_xyzz_hardcoded_dp_specialization = use_xyzz_dp8_specialization || use_xyzz_dp12_specialization || use_xyzz_dp16_specialization;
		const char* function_name = use_xyzz_dp8_specialization
			? (steps_per_sample == 512
				? "jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_dp8_pow2_u32_distance"
				: "jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_dp8_pow2_u32_distance")
			: (use_xyzz_dp12_specialization
				? (steps_per_sample == 512
					? "jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_dp12_pow2_u32_distance"
					: "jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_dp12_pow2_u32_distance")
				: (use_xyzz_dp16_specialization
					? (steps_per_sample == 512
						? "jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_dp16_pow2_u32_distance"
						: "jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_dp16_pow2_u32_distance")
					: (steps_per_sample == 512
						? "jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps512_pow2_u32_distance"
						: "jacobian_affine_walk_dynamic_dp_stream_xyzz_chain_steps256_pow2_u32_distance")));
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
		NSUInteger threads_per_threadgroup = PreferredThreadgroupWidth(pipeline, (unsigned int)effective_threadgroup_limit);
		if (dispatch_stats)
		{
			dispatch_stats->thread_execution_width = (unsigned int)execution_width;
			dispatch_stats->max_threads_per_threadgroup = (unsigned int)max_threads;
			dispatch_stats->threads_per_threadgroup = (unsigned int)threads_per_threadgroup;
		}

		size_t p_bytes = p_xyzz.size() * sizeof(uint64_t);
		size_t q_bytes = q_xy.size() * sizeof(uint64_t);
		size_t p_inf_bytes = dynamic_p_infinity.size() * sizeof(uint8_t);
		size_t cumulative_bytes = cumulative_distances.size() * sizeof(uint64_t);
		size_t distance_bytes = jump_distances.size() * sizeof(uint64_t);
		uint32_t count = (uint32_t)p.size();
		uint32_t jump_mask = (uint32_t)jumps.size() - 1U;
		uint64_t dp_mask = ProjectiveDpMask(dp_bits);
		uint32_t dp_capacity = (uint32_t)total_record_capacity;
		uint32_t zero = 0;
		std::vector<uint32_t> indices_out(dp_capacity);
		std::vector<uint64_t> distances_out(dp_capacity);
		std::vector<uint64_t> dp_terms_out(dp_capacity);
		size_t indices_bytes = indices_out.size() * sizeof(uint32_t);
		size_t distances_out_bytes = distances_out.size() * sizeof(uint64_t);
		size_t dp_terms_bytes = dp_terms_out.size() * sizeof(uint64_t);
		id<MTLBuffer> p_buffer = [device newBufferWithBytes:p_xyzz.data() length:p_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> q_buffer = [device newBufferWithBytes:q_xy.data() length:q_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> p_inf_buffer = [device newBufferWithBytes:dynamic_p_infinity.data() length:p_inf_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> cumulative_distances_buffer = [device newBufferWithBytes:cumulative_distances.data() length:cumulative_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> dp_count_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> indices_buffer = [device newBufferWithLength:indices_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> count_buffer = [device newBufferWithBytes:&count length:sizeof(count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_distances_buffer = [device newBufferWithBytes:jump_distances.data() length:distance_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_distances_buffer = [device newBufferWithLength:distances_out_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> out_dp_terms_buffer = [device newBufferWithLength:dp_terms_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_mask_buffer = [device newBufferWithBytes:&jump_mask length:sizeof(jump_mask) options:MTLResourceStorageModeShared];
		id<MTLBuffer> dp_mask_buffer = use_xyzz_hardcoded_dp_specialization ? nil : [device newBufferWithBytes:&dp_mask length:sizeof(dp_mask) options:MTLResourceStorageModeShared];
		if (!p_buffer || !q_buffer || !p_inf_buffer || !cumulative_distances_buffer || !dp_count_buffer || !indices_buffer || !count_buffer || !jump_distances_buffer || !out_distances_buffer || !out_dp_terms_buffer || !jump_mask_buffer || (!use_xyzz_hardcoded_dp_specialization && !dp_mask_buffer))
		{
			error = "failed to allocate Metal jacobian dynamic dp stream XYZZ chain buffers";
			return false;
		}

		id<MTLCommandQueue> queue = [device newCommandQueue];
		if (!queue)
		{
			error = "failed to create Metal command queue";
			return false;
		}

		double dispatch_seconds = 0.0;
		for (uint32_t round = 0; round < round_count; ++round)
		{
			id<MTLCommandBuffer> command_buffer = [queue commandBuffer];
			for (uint32_t packet = 0; packet < packet_count; ++packet)
			{
				id<MTLComputeCommandEncoder> encoder = [command_buffer computeCommandEncoder];
				[encoder setComputePipelineState:pipeline];
				[encoder setBuffer:p_buffer offset:0 atIndex:0];
				[encoder setBuffer:q_buffer offset:0 atIndex:1];
				[encoder setBuffer:p_inf_buffer offset:0 atIndex:2];
				[encoder setBuffer:cumulative_distances_buffer offset:0 atIndex:3];
				[encoder setBuffer:dp_count_buffer offset:0 atIndex:4];
				[encoder setBuffer:indices_buffer offset:0 atIndex:5];
				[encoder setBuffer:count_buffer offset:0 atIndex:6];
				[encoder setBuffer:jump_distances_buffer offset:0 atIndex:8];
				[encoder setBuffer:out_distances_buffer offset:0 atIndex:9];
				[encoder setBuffer:out_dp_terms_buffer offset:0 atIndex:10];
				[encoder setBuffer:jump_mask_buffer offset:0 atIndex:11];
				uint32_t packet_index_base = (uint32_t)(((uint64_t)round * packet_count + packet) * count);
				[encoder setBytes:&packet_index_base length:sizeof(packet_index_base) atIndex:12];
				if (!use_xyzz_hardcoded_dp_specialization)
					[encoder setBuffer:dp_mask_buffer offset:0 atIndex:14];
				NSUInteger threadgroup_count = (count + threads_per_threadgroup - 1) / threads_per_threadgroup;
				[encoder dispatchThreadgroups:MTLSizeMake(threadgroup_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
				[encoder endEncoding];
			}
			auto start = std::chrono::steady_clock::now();
			[command_buffer commit];
			[command_buffer waitUntilCompleted];
			auto end = std::chrono::steady_clock::now();
			dispatch_seconds += std::chrono::duration<double>(end - start).count();

			if ([command_buffer status] != MTLCommandBufferStatusCompleted)
			{
				error = NSErrorToString([command_buffer error]);
				return false;
			}
		}
		if (seconds)
			*seconds = dispatch_seconds;

		uint32_t emitted_raw = 0;
		memcpy(&emitted_raw, [dp_count_buffer contents], sizeof(emitted_raw));
		emitted_records = emitted_raw < dp_capacity ? emitted_raw : dp_capacity;
		dp_stream_overflow = emitted_raw > dp_capacity;
		size_t emitted_indices_bytes = (size_t)emitted_records * sizeof(uint32_t);
		size_t emitted_distances_bytes = (size_t)emitted_records * sizeof(uint64_t);
		size_t emitted_dp_terms_bytes = (size_t)emitted_records * sizeof(uint64_t);
		memcpy(indices_out.data(), [indices_buffer contents], emitted_indices_bytes);
		memcpy(distances_out.data(), [out_distances_buffer contents], emitted_distances_bytes);
		memcpy(dp_terms_out.data(), [out_dp_terms_buffer contents], emitted_dp_terms_bytes);
		memcpy(p_xyzz.data(), [p_buffer contents], p_bytes);
		memcpy(dynamic_p_infinity.data(), [p_inf_buffer contents], p_inf_bytes);
		indices_out.resize(emitted_records);
		distances_out.resize(emitted_records);
		dp_terms_out.resize(emitted_records);
		out_indices = indices_out;
		out_distances = distances_out;
		out_dp_terms = dp_terms_out;
		state_out.clear();
		state_out.reserve(p.size());
		for (size_t i = 0; i < p.size(); ++i)
		{
			CpuXyzzPoint point;
			size_t base = i * 16;
			for (size_t limb = 0; limb < 4; ++limb)
				point.x[limb] = p_xyzz[base + limb];
			for (size_t limb = 0; limb < 4; ++limb)
				point.y[limb] = p_xyzz[base + 4 + limb];
			for (size_t limb = 0; limb < 4; ++limb)
				point.zz[limb] = p_xyzz[base + 8 + limb];
			for (size_t limb = 0; limb < 4; ++limb)
				point.zzz[limb] = p_xyzz[base + 12 + limb];
			point.infinity = dynamic_p_infinity[i] != 0;
			state_out.push_back(point);
		}
		return true;
	}
}

static bool RunJacobianDynamicDpStreamXyzzChainKernel(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	unsigned int packet_count,
	std::vector<CpuXyzzPoint>& state_out,
	std::vector<uint32_t>& out_indices,
	std::vector<uint64_t>& out_distances,
	std::vector<uint64_t>& out_dp_terms,
	uint32_t& emitted_records,
	bool& dp_stream_overflow,
	unsigned int dp_bits,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit,
	MetalDispatchStats* dispatch_stats)
{
	return RunJacobianDynamicDpStreamXyzzPersistentChainKernel(p, jumps, jump_distances, steps_per_sample, packet_count, 1, state_out, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, error, seconds, threadgroup_limit, dispatch_stats);
}

static bool RunJacobianDynamicDpCountKernel(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	unsigned int steps_per_sample,
	uint32_t& dp_count,
	unsigned int dp_bits,
	std::string& error,
	double* seconds,
	unsigned int threadgroup_limit,
	MetalDispatchStats* dispatch_stats)
{
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);

	if (p.empty() || jumps.empty() || steps_per_sample != 8 || dp_bits > 32 || !IsMetalPowerOfTwo((unsigned int)jumps.size()) || jumps.size() > 32)
	{
		error = "invalid jacobian dynamic dp count input";
		return false;
	}

	std::vector<uint64_t> p_xyz;
	std::vector<uint64_t> q_xy;
	std::vector<uint32_t> p_infinity;
	PackJacobianStateInputs(p, p_xyz, p_infinity);
	PackAffineTable(jumps, q_xy);

	std::vector<uint8_t> dynamic_p_infinity;
	dynamic_p_infinity.reserve(p_infinity.size());
	for (uint32_t p_infinity_value : p_infinity)
		dynamic_p_infinity.push_back(p_infinity_value ? 1U : 0U);

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

		const char* function_name = "jacobian_affine_walk_dynamic_dp_count_steps8_pow2_mask";
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

		size_t p_bytes = p_xyz.size() * sizeof(uint64_t);
		size_t q_bytes = q_xy.size() * sizeof(uint64_t);
		size_t p_inf_bytes = dynamic_p_infinity.size() * sizeof(uint8_t);
		uint32_t count = (uint32_t)p.size();
		uint32_t step_count = steps_per_sample;
		uint32_t jump_mask = (uint32_t)jumps.size() - 1U;
		uint64_t dp_mask = ProjectiveDpMask(dp_bits);
		uint32_t zero = 0;
		id<MTLBuffer> p_buffer = [device newBufferWithBytes:p_xyz.data() length:p_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> q_buffer = [device newBufferWithBytes:q_xy.data() length:q_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> p_inf_buffer = [device newBufferWithBytes:dynamic_p_infinity.data() length:p_inf_bytes options:MTLResourceStorageModeShared];
		id<MTLBuffer> dp_count_buffer = [device newBufferWithBytes:&zero length:sizeof(zero) options:MTLResourceStorageModeShared];
		id<MTLBuffer> count_buffer = [device newBufferWithBytes:&count length:sizeof(count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> steps_buffer = [device newBufferWithBytes:&step_count length:sizeof(step_count) options:MTLResourceStorageModeShared];
		id<MTLBuffer> jump_mask_buffer = [device newBufferWithBytes:&jump_mask length:sizeof(jump_mask) options:MTLResourceStorageModeShared];
		id<MTLBuffer> dp_mask_buffer = [device newBufferWithBytes:&dp_mask length:sizeof(dp_mask) options:MTLResourceStorageModeShared];
		if (!p_buffer || !q_buffer || !p_inf_buffer || !dp_count_buffer || !count_buffer || !steps_buffer || !jump_mask_buffer || !dp_mask_buffer)
		{
			error = "failed to allocate Metal jacobian dynamic dp count buffers";
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
		[encoder setBuffer:dp_count_buffer offset:0 atIndex:4];
		[encoder setBuffer:count_buffer offset:0 atIndex:5];
		[encoder setBuffer:steps_buffer offset:0 atIndex:6];
		[encoder setBuffer:jump_mask_buffer offset:0 atIndex:7];
		[encoder setBuffer:dp_mask_buffer offset:0 atIndex:10];
		NSUInteger threadgroup_count = (count + threads_per_threadgroup - 1) / threads_per_threadgroup;
		[encoder dispatchThreadgroups:MTLSizeMake(threadgroup_count, 1, 1) threadsPerThreadgroup:MTLSizeMake(threads_per_threadgroup, 1, 1)];
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

		uint32_t count_raw = 0;
		memcpy(&count_raw, [dp_count_buffer contents], sizeof(count_raw));
		dp_count = count_raw;
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

static CpuJacobianPoint CpuJacobianWalkFixed(CpuJacobianPoint p, const CpuAffinePoint& q, unsigned int steps_per_sample)
{
	for (unsigned int i = 0; i < steps_per_sample; ++i)
		p = CpuJacobianAddAffine(p, q);
	return p;
}

static void BuildJacobianJumpWalkSamples(unsigned int sample_count,
	unsigned int jump_count,
	std::vector<CpuJacobianPoint>& p,
	std::vector<CpuAffinePoint>& jumps)
{
	std::vector<CpuJacobianPoint> sample_p;
	std::vector<CpuAffinePoint> sample_q;
	unsigned int source_count = sample_count > jump_count ? sample_count : jump_count;
	BuildJacobianAddSamples(source_count ? source_count : 1, sample_p, sample_q);
	p.assign(sample_p.begin(), sample_p.begin() + sample_count);
	jumps.assign(sample_q.begin(), sample_q.begin() + jump_count);
}

static bool IsScaled4BalancedJumpSchedule(const char* jump_schedule)
{
	return jump_schedule && (strcmp(jump_schedule, "scaled4-balanced") == 0 || strcmp(jump_schedule, "scaled4_balanced") == 0);
}

static const char* NormalizeMetalJumpScheduleName(const char* jump_schedule)
{
	if (!jump_schedule || !*jump_schedule || strcmp(jump_schedule, "power2") == 0)
		return "power2";
	if (IsScaled4BalancedJumpSchedule(jump_schedule))
		return "scaled4_balanced";
	return "invalid";
}

static bool ValidateMetalJumpSchedule(const char* jump_schedule, unsigned int jump_count, std::string& reason)
{
	if (!jump_schedule || !*jump_schedule || strcmp(jump_schedule, "power2") == 0)
		return true;
	if (IsScaled4BalancedJumpSchedule(jump_schedule))
	{
		if (jump_count == 4)
			return true;
		reason = "scaled4-balanced jump schedule requires --jumps 4";
		return false;
	}
	reason = "unknown jump schedule";
	return false;
}

static const char* NormalizeAffineLookupQueryModeName(const char* lookup_query_mode)
{
	if (!lookup_query_mode || !*lookup_query_mode || strcmp(lookup_query_mode, "repeat") == 0)
		return "repeat";
	if (strcmp(lookup_query_mode, "distinct-misses") == 0 || strcmp(lookup_query_mode, "distinct_misses") == 0)
		return "distinct_misses";
	return "invalid";
}

static bool ValidateAffineLookupQueryMode(const char* lookup_query_mode, std::string& reason)
{
	const char* normalized = NormalizeAffineLookupQueryModeName(lookup_query_mode);
	if (strcmp(normalized, "repeat") == 0 || strcmp(normalized, "distinct_misses") == 0)
		return true;
	reason = "unknown affine lookup query mode";
	return false;
}

static const char* NormalizeAffineLookupEngineName(const char* lookup_engine)
{
	if (!lookup_engine || !*lookup_engine || strcmp(lookup_engine, "gpu") == 0 || strcmp(lookup_engine, "metal") == 0)
		return "gpu";
	if (strcmp(lookup_engine, "gpu-filter") == 0 || strcmp(lookup_engine, "gpu_filter") == 0 || strcmp(lookup_engine, "filter") == 0)
		return "gpu_filter";
	if (strcmp(lookup_engine, "cpu") == 0 || strcmp(lookup_engine, "host") == 0)
		return "cpu";
	if (strcmp(lookup_engine, "auto") == 0)
		return "auto";
	return "invalid";
}

static bool ValidateAffineLookupEngine(const char* lookup_engine, std::string& reason)
{
	const char* normalized = NormalizeAffineLookupEngineName(lookup_engine);
	if (strcmp(normalized, "gpu") == 0 || strcmp(normalized, "gpu_filter") == 0 || strcmp(normalized, "cpu") == 0 || strcmp(normalized, "auto") == 0)
		return true;
	reason = "unknown affine lookup engine";
	return false;
}

static const char* ChooseAffineLookupEngine(const char* lookup_engine, unsigned int target_count, uint64_t query_count)
{
	if (strcmp(lookup_engine, "auto") != 0)
		return lookup_engine;
	if (target_count <= 4194304U && query_count >= 1048576ULL)
		return "gpu";
	if (target_count >= 1048576U && query_count <= 4194304ULL)
		return "cpu";
	return "gpu";
}

static unsigned int ChooseAffineLookupThreadgroupLimit(const char* lookup_engine,
	const char* effective_lookup_engine,
	unsigned int target_count,
	uint64_t query_count,
	unsigned int threadgroup_limit,
	unsigned int lookup_threadgroup_limit)
{
	if (lookup_threadgroup_limit)
		return lookup_threadgroup_limit;
	if (strcmp(lookup_engine, "auto") == 0 &&
		strcmp(effective_lookup_engine, "gpu") == 0 &&
		target_count <= 4194304U &&
		query_count >= 1048576ULL)
		return 512;
	return threadgroup_limit;
}

static FieldElement FieldFromEcInt(const EcInt& value)
{
	return {value.data[0], value.data[1], value.data[2], value.data[3]};
}

static CpuAffinePoint CpuAffineFromEcPoint(const EcPoint& point)
{
	CpuAffinePoint out;
	out.x = FieldFromEcInt(point.x);
	out.y = FieldFromEcInt(point.y);
	return out;
}

static void BuildAffineJumpsFromDistances(const std::vector<uint64_t>& jump_distances,
	std::vector<CpuAffinePoint>& jumps)
{
	jumps.clear();
	jumps.reserve(jump_distances.size());
	for (uint64_t distance : jump_distances)
	{
		EcInt k;
		k.Set(distance);
		EcPoint point = Ec::MultiplyG(k);
		jumps.push_back(CpuAffineFromEcPoint(point));
	}
}

static void BuildJacobianJumpWalkSamplesForSchedule(unsigned int sample_count,
	unsigned int jump_count,
	const char* jump_schedule,
	const std::vector<uint64_t>& jump_distances,
	std::vector<CpuJacobianPoint>& p,
	std::vector<CpuAffinePoint>& jumps)
{
	if (!IsScaled4BalancedJumpSchedule(jump_schedule))
	{
		BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
		return;
	}

	std::vector<CpuJacobianPoint> sample_p;
	std::vector<CpuAffinePoint> sample_q;
	BuildJacobianAddSamples(sample_count ? sample_count : 1, sample_p, sample_q);
	p.assign(sample_p.begin(), sample_p.begin() + sample_count);
	BuildAffineJumpsFromDistances(jump_distances, jumps);
}

static void BuildJacobianJumpDistances(unsigned int jump_count, std::vector<uint64_t>& jump_distances)
{
	jump_distances.clear();
	jump_distances.reserve(jump_count);
	for (unsigned int i = 0; i < jump_count; ++i)
		jump_distances.push_back(1ULL << i);
}

static void BuildJacobianJumpDistancesForSchedule(unsigned int jump_count,
	const char* jump_schedule,
	std::vector<uint64_t>& jump_distances)
{
	static const uint64_t scaled4_distances[] = {1, 2, 8192, 8193};
	if (!IsScaled4BalancedJumpSchedule(jump_schedule))
	{
		BuildJacobianJumpDistances(jump_count, jump_distances);
		return;
	}

	jump_distances.assign(scaled4_distances, scaled4_distances + 4);
}

static unsigned int NormalizeMetalJumpCount(unsigned int jump_count)
{
	if (jump_count == 0)
		return 1;
	if (jump_count > 32)
		return 32;
	return jump_count;
}

static bool IsMetalPowerOfTwo(unsigned int value)
{
	return value && ((value & (value - 1)) == 0);
}

static const char* MetalJumpIndexMode(unsigned int jump_count)
{
	return IsMetalPowerOfTwo(jump_count) ? "power2_mask" : "modulo";
}

static constexpr const char* kDynamicJumpMixerName = "avalanche64";

static unsigned int NormalizeMetalDpBits(unsigned int dp_bits)
{
	return dp_bits > 32 ? 32 : dp_bits;
}

static uint64_t ProjectiveDpMask(unsigned int dp_bits)
{
	dp_bits = NormalizeMetalDpBits(dp_bits);
	if (dp_bits == 0)
		return 0;
	return (1ULL << dp_bits) - 1ULL;
}

static void BuildDeterministicJumpIndices(unsigned int sample_count,
	unsigned int steps_per_sample,
	unsigned int jump_count,
	std::vector<uint32_t>& jump_indices)
{
	jump_indices.clear();
	jump_indices.reserve((size_t)sample_count * steps_per_sample);
	for (unsigned int i = 0; i < sample_count; ++i)
	{
		for (unsigned int step = 0; step < steps_per_sample; ++step)
		{
			uint32_t mixed = (uint32_t)(i * 1315423911U) ^ (uint32_t)(step * 2654435761U) ^ (uint32_t)((i + 17U) << (step & 7U));
			jump_indices.push_back(mixed % jump_count);
		}
	}
}

static CpuJacobianPoint CpuJacobianJumpWalk(CpuJacobianPoint p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	const std::vector<uint32_t>& jump_indices,
	size_t sample_index,
	unsigned int steps_per_sample,
	uint64_t* distance_out)
{
	uint64_t distance = 0;
	size_t base = sample_index * (size_t)steps_per_sample;
	for (unsigned int step = 0; step < steps_per_sample; ++step)
	{
		uint32_t jump_index = jump_indices[base + step];
		distance += jump_distances[jump_index];
		p = CpuJacobianAddAffine(p, jumps[jump_index]);
	}
	if (distance_out)
		*distance_out = distance;
	return p;
}

static uint32_t CpuJacobianJumpIndex(const CpuJacobianPoint& p, unsigned int jump_count)
{
	uint64_t mixed = p.x[0] ^ (p.x[1] << 7) ^ (p.y[0] >> 3) ^ p.z[0];
	mixed ^= mixed >> 33;
	mixed *= 0xff51afd7ed558ccdULL;
	mixed ^= mixed >> 33;
	if (IsMetalPowerOfTwo(jump_count))
		return (uint32_t)(mixed & (jump_count - 1));
	return (uint32_t)(mixed % jump_count);
}

static uint32_t CpuXyzzJumpIndex(const CpuXyzzPoint& p, unsigned int jump_count)
{
	uint64_t mixed = p.x[0] ^ (p.x[1] << 7) ^ (p.y[0] >> 3) ^ p.zz[0];
	mixed ^= mixed >> 33;
	mixed *= 0xff51afd7ed558ccdULL;
	mixed ^= mixed >> 33;
	if (IsMetalPowerOfTwo(jump_count))
		return (uint32_t)(mixed & (jump_count - 1));
	return (uint32_t)(mixed % jump_count);
}

static uint64_t JumpHistogramTotal(const std::vector<uint64_t>& jump_histogram)
{
	uint64_t total = 0;
	for (uint64_t bucket : jump_histogram)
		total += bucket;
	return total;
}

static uint64_t JumpHistogramMinBucket(const std::vector<uint64_t>& jump_histogram)
{
	if (jump_histogram.empty())
		return 0;
	uint64_t min_bucket = jump_histogram[0];
	for (uint64_t bucket : jump_histogram)
		if (bucket < min_bucket)
			min_bucket = bucket;
	return min_bucket;
}

static uint64_t JumpHistogramMaxBucket(const std::vector<uint64_t>& jump_histogram)
{
	uint64_t max_bucket = 0;
	for (uint64_t bucket : jump_histogram)
		if (bucket > max_bucket)
			max_bucket = bucket;
	return max_bucket;
}

static uint64_t JumpHistogramMaxDeviationPpm(const std::vector<uint64_t>& jump_histogram)
{
	uint64_t total = JumpHistogramTotal(jump_histogram);
	if (jump_histogram.empty() || total == 0)
		return 0;
	uint64_t bucket_count = (uint64_t)jump_histogram.size();
	uint64_t max_scaled_delta = 0;
	for (uint64_t bucket : jump_histogram)
	{
		uint64_t scaled = bucket * bucket_count;
		uint64_t delta = scaled > total ? scaled - total : total - scaled;
		if (delta > max_scaled_delta)
			max_scaled_delta = delta;
	}
	return (max_scaled_delta * 1000000ULL + (total / 2ULL)) / total;
}

static CpuJacobianPoint CpuJacobianDynamicJumpWalk(CpuJacobianPoint p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	uint64_t* distance_out,
	std::vector<uint64_t>* jump_histogram = NULL)
{
	uint64_t distance = 0;
	for (unsigned int step = 0; step < steps_per_sample; ++step)
	{
		uint32_t jump_index = CpuJacobianJumpIndex(p, (unsigned int)jumps.size());
		if (jump_histogram && jump_index < jump_histogram->size())
			(*jump_histogram)[jump_index]++;
		distance += jump_distances[jump_index];
		p = CpuJacobianAddAffine(p, jumps[jump_index]);
	}
	if (distance_out)
		*distance_out = distance;
	return p;
}

static CpuXyzzPoint CpuXyzzDynamicJumpWalk(CpuXyzzPoint p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	uint64_t* distance_out,
	std::vector<uint64_t>* jump_histogram = NULL)
{
	uint64_t distance = 0;
	for (unsigned int step = 0; step < steps_per_sample; ++step)
	{
		uint32_t jump_index = CpuXyzzJumpIndex(p, (unsigned int)jumps.size());
		if (jump_histogram && jump_index < jump_histogram->size())
			(*jump_histogram)[jump_index]++;
		distance += jump_distances[jump_index];
		p = CpuXyzzAddAffine(p, jumps[jump_index]);
	}
	if (distance_out)
		*distance_out = distance;
	return p;
}

static uint64_t MixDistanceChecksum(uint64_t checksum, uint64_t distance, size_t sample_index)
{
	checksum ^= distance + 0x9E3779B97F4A7C15ULL + (checksum << 6) + (checksum >> 2) + (uint64_t)sample_index;
	return checksum;
}

static uint32_t ProjectiveDpFlag(const CpuJacobianPoint& p, unsigned int dp_bits)
{
	if (p.infinity)
		return 0;
	uint64_t mask = ProjectiveDpMask(dp_bits);
	return (p.x[0] & mask) == 0 ? 1U : 0U;
}

static uint32_t ProjectiveXyzzDpFlag(const CpuXyzzPoint& p, unsigned int dp_bits)
{
	if (p.infinity)
		return 0;
	uint64_t mask = ProjectiveDpMask(dp_bits);
	return (p.x[0] & mask) == 0 ? 1U : 0U;
}

static uint64_t MixDpChecksum(uint64_t checksum, const CpuJacobianPoint& p, uint32_t dp_flag, size_t sample_index)
{
	if (!dp_flag)
		return checksum ^ ((uint64_t)sample_index * 0xD6E8FEB86659FD93ULL);
	return checksum ^ p.x[0] ^ (p.y[0] << 1) ^ (p.z[0] << 7) ^ ((uint64_t)sample_index * 0x9E3779B97F4A7C15ULL);
}

static uint64_t CompactDpTerm(const CpuJacobianPoint& p, uint32_t dp_flag)
{
	if (!dp_flag)
		return 0;
	return p.x[0] ^ (p.y[0] << 1) ^ (p.z[0] << 7);
}

static uint64_t CompactXyzzDpTerm(const CpuXyzzPoint& p, uint32_t dp_flag)
{
	if (!dp_flag)
		return 0;
	return p.x[0] ^ (p.y[0] << 1) ^ (p.zz[0] << 7) ^ (p.zzz[0] << 13);
}

static uint64_t MixCompactDpChecksum(uint64_t checksum, uint64_t dp_term, uint32_t dp_flag, size_t sample_index)
{
	if (!dp_flag)
		return checksum ^ ((uint64_t)sample_index * 0xD6E8FEB86659FD93ULL);
	return checksum ^ dp_term ^ ((uint64_t)sample_index * 0x9E3779B97F4A7C15ULL);
}

static bool CpuXyzzBatchAffineDpScan(const std::vector<CpuXyzzPoint>& points,
	const std::vector<uint64_t>& distances,
	unsigned int dp_bits,
	uint64_t* dp_distance_checksum_out,
	uint64_t* dp_checksum_out,
	unsigned int* dp_count_out,
	std::string& reason,
	std::vector<TargetLookupKeyHost>* dp_keys_out = NULL,
	std::vector<uint64_t>* dp_distances_out = NULL)
{
	if (points.size() != distances.size())
	{
		reason = "XYZZ affine scan state/distance size mismatch";
		return false;
	}
	if (dp_keys_out)
		dp_keys_out->clear();
	if (dp_distances_out)
		dp_distances_out->clear();

	const uint64_t dp_mask = ProjectiveDpMask(dp_bits);
	const FieldElement one = CpuFieldOne();
	std::vector<FieldElement> prefixes(points.size());
	std::vector<FieldElement> products(points.size());
	std::vector<uint8_t> active(points.size(), 0);
	FieldElement acc = one;
	unsigned int active_count = 0;
	for (size_t i = 0; i < points.size(); ++i)
	{
		const CpuXyzzPoint& p = points[i];
		if (p.infinity || CpuFieldIsZero(p.zz) || CpuFieldIsZero(p.zzz))
			continue;
		prefixes[i] = acc;
		products[i] = CpuFieldMul(p.zz, p.zzz);
		acc = CpuFieldMul(acc, products[i]);
		active[i] = 1;
		active_count++;
	}

	uint64_t dp_distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	if (active_count)
	{
		FieldElement inv_suffix = CpuFieldInv(acc);
		for (size_t remaining = points.size(); remaining > 0; --remaining)
		{
			size_t i = remaining - 1;
			const CpuXyzzPoint& p = points[i];
			uint32_t dp_flag = 0;
			uint64_t dp_term = 0;
			if (active[i])
			{
				FieldElement inv_product = CpuFieldMul(inv_suffix, prefixes[i]);
				inv_suffix = CpuFieldMul(inv_suffix, products[i]);
				FieldElement inv_zz = CpuFieldMul(p.zzz, inv_product);
				FieldElement affine_x = CpuFieldMul(p.x, inv_zz);
				dp_flag = (affine_x[0] & dp_mask) == 0 ? 1U : 0U;
				if (dp_flag)
				{
					FieldElement inv_zzz = CpuFieldMul(p.zz, inv_product);
					FieldElement affine_y = CpuFieldMul(p.y, inv_zzz);
					dp_term = affine_x[0] ^ (affine_y[0] << 1);
					if (dp_keys_out)
					{
						TargetLookupKeyHost key;
						for (size_t limb = 0; limb < 4; ++limb)
							key.x[limb] = affine_x[limb];
						key.parity = (uint32_t)(affine_y[0] & 1ULL);
						dp_keys_out->push_back(key);
					}
					if (dp_distances_out)
						dp_distances_out->push_back(distances[i]);
				}
			}
			if (dp_flag)
			{
				dp_distance_checksum = MixDistanceChecksum(dp_distance_checksum, distances[i], i);
				dp_count++;
			}
			dp_checksum = MixCompactDpChecksum(dp_checksum, dp_term, dp_flag, i);
		}
	}
	else
	{
		for (size_t i = 0; i < points.size(); ++i)
			dp_checksum = MixCompactDpChecksum(dp_checksum, 0, 0, i);
	}

	if (dp_distance_checksum_out)
		*dp_distance_checksum_out = dp_distance_checksum;
	if (dp_checksum_out)
		*dp_checksum_out = dp_checksum;
	if (dp_count_out)
		*dp_count_out = dp_count;
	return true;
}

static bool ValidateDynamicDpStreamOutputs(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	const std::vector<uint32_t>& out_indices,
	const std::vector<uint64_t>& out_distances,
	const std::vector<uint64_t>& out_dp_terms,
	uint32_t emitted_records,
	bool dp_stream_overflow,
	unsigned int dp_bits,
	std::vector<uint64_t>* jump_histogram,
	uint64_t* dp_distance_checksum_out,
	uint64_t* dp_checksum_out,
	unsigned int* dp_count_out,
	std::string& reason)
{
	if (dp_stream_overflow)
	{
		reason = "dynamic dp stream overflow";
		return false;
	}
	if (out_indices.size() != emitted_records || out_distances.size() != emitted_records || out_dp_terms.size() != emitted_records)
	{
		reason = "dynamic dp stream output size mismatch";
		return false;
	}

	std::vector<uint32_t> expected_dp_flags(p.size(), 0);
	std::vector<uint64_t> expected_distances(p.size(), 0);
	std::vector<uint64_t> expected_dp_terms(p.size(), 0);
	unsigned int expected_dp_count = 0;
	unsigned int worker_count = ValidationWorkerCount(p.size());
	std::vector<unsigned int> local_dp_counts(worker_count, 0);
	std::vector<std::vector<uint64_t> > local_jump_histograms;
	if (jump_histogram)
		local_jump_histograms.assign(worker_count, std::vector<uint64_t>(jump_histogram->size(), 0));
	ParallelForSamples(p.size(), [&](size_t begin, size_t end, unsigned int worker_index) {
		unsigned int local_dp_count = 0;
		std::vector<uint64_t>* local_jump_histogram = jump_histogram ? &local_jump_histograms[worker_index] : NULL;
		for (size_t i = begin; i < end; ++i)
		{
			uint64_t expected_distance = 0;
			CpuJacobianPoint expected = CpuJacobianDynamicJumpWalk(p[i], jumps, jump_distances, steps_per_sample, &expected_distance, local_jump_histogram);
			uint32_t expected_dp_flag = ProjectiveDpFlag(expected, dp_bits);
			expected_dp_flags[i] = expected_dp_flag;
			expected_distances[i] = expected_distance;
			expected_dp_terms[i] = CompactDpTerm(expected, expected_dp_flag);
			local_dp_count += expected_dp_flag ? 1U : 0U;
		}
		local_dp_counts[worker_index] = local_dp_count;
	});
	for (unsigned int count : local_dp_counts)
		expected_dp_count += count;
	if (jump_histogram)
	{
		for (const std::vector<uint64_t>& local : local_jump_histograms)
			for (size_t bucket = 0; bucket < local.size(); ++bucket)
				(*jump_histogram)[bucket] += local[bucket];
	}
	if (emitted_records != expected_dp_count)
	{
		reason = "dynamic dp stream count mismatch: got " + std::to_string(emitted_records) +
			" expected " + std::to_string(expected_dp_count);
		return false;
	}

	std::vector<uint8_t> seen(p.size(), 0);
	std::vector<uint64_t> stream_distances(p.size(), 0);
	std::vector<uint64_t> stream_dp_terms(p.size(), 0);
	for (size_t slot = 0; slot < out_indices.size(); ++slot)
	{
		uint32_t sample_index = out_indices[slot];
		if (sample_index >= p.size())
		{
			reason = "dynamic dp stream index out of range at slot " + std::to_string(slot);
			return false;
		}
		if (seen[sample_index])
		{
			reason = "dynamic dp stream duplicate index " + std::to_string(sample_index);
			return false;
		}
		if (!expected_dp_flags[sample_index])
		{
			reason = "dynamic dp stream emitted non-DP sample " + std::to_string(sample_index);
			return false;
		}
		if (out_distances[slot] != expected_distances[sample_index] || out_dp_terms[slot] != expected_dp_terms[sample_index])
		{
			reason = "dynamic dp stream mismatch at sample " + std::to_string(sample_index) +
				": distance=" + std::to_string(out_distances[slot]) +
				" dp_term=0x" + FieldToHex(FieldElement{out_dp_terms[slot], 0, 0, 0}) +
				" expected distance=" + std::to_string(expected_distances[sample_index]) +
				" expected dp_term=0x" + FieldToHex(FieldElement{expected_dp_terms[sample_index], 0, 0, 0});
			return false;
		}
		seen[sample_index] = 1;
		stream_distances[sample_index] = out_distances[slot];
		stream_dp_terms[sample_index] = out_dp_terms[slot];
	}
	for (size_t i = 0; i < p.size(); ++i)
	{
		if (expected_dp_flags[i] && !seen[i])
		{
			reason = "dynamic dp stream missing DP sample " + std::to_string(i);
			return false;
		}
	}

	uint64_t dp_distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	for (size_t i = 0; i < p.size(); ++i)
	{
		uint32_t stream_dp_flag = seen[i] ? 1U : 0U;
		if (stream_dp_flag)
		{
			dp_distance_checksum = MixDistanceChecksum(dp_distance_checksum, stream_distances[i], i);
			dp_count++;
		}
		dp_checksum = MixCompactDpChecksum(dp_checksum, stream_dp_terms[i], stream_dp_flag, i);
	}

	if (dp_distance_checksum_out)
		*dp_distance_checksum_out = dp_distance_checksum;
	if (dp_checksum_out)
		*dp_checksum_out = dp_checksum;
	if (dp_count_out)
		*dp_count_out = dp_count;
	return true;
}

static bool ValidateDynamicXyzzDpStreamOutputs(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	const std::vector<uint32_t>& out_indices,
	const std::vector<uint64_t>& out_distances,
	const std::vector<uint64_t>& out_dp_terms,
	uint32_t emitted_records,
	bool dp_stream_overflow,
	unsigned int dp_bits,
	std::vector<uint64_t>* jump_histogram,
	uint64_t* dp_distance_checksum_out,
	uint64_t* dp_checksum_out,
	unsigned int* dp_count_out,
	std::string& reason)
{
	if (dp_stream_overflow)
	{
		reason = "dynamic XYZZ dp stream overflow";
		return false;
	}
	if (out_indices.size() != emitted_records || out_distances.size() != emitted_records || out_dp_terms.size() != emitted_records)
	{
		reason = "dynamic XYZZ dp stream output size mismatch";
		return false;
	}

	std::vector<uint32_t> expected_dp_flags(p.size(), 0);
	std::vector<uint64_t> expected_distances(p.size(), 0);
	std::vector<uint64_t> expected_dp_terms(p.size(), 0);
	unsigned int expected_dp_count = 0;
	unsigned int worker_count = ValidationWorkerCount(p.size());
	std::vector<unsigned int> local_dp_counts(worker_count, 0);
	std::vector<std::vector<uint64_t> > local_jump_histograms;
	if (jump_histogram)
		local_jump_histograms.assign(worker_count, std::vector<uint64_t>(jump_histogram->size(), 0));
	ParallelForSamples(p.size(), [&](size_t begin, size_t end, unsigned int worker_index) {
		unsigned int local_dp_count = 0;
		std::vector<uint64_t>* local_jump_histogram = jump_histogram ? &local_jump_histograms[worker_index] : NULL;
		for (size_t i = begin; i < end; ++i)
		{
			uint64_t expected_distance = 0;
			CpuXyzzPoint expected = CpuXyzzDynamicJumpWalk(CpuXyzzFromJacobian(p[i]), jumps, jump_distances, steps_per_sample, &expected_distance, local_jump_histogram);
			uint32_t expected_dp_flag = ProjectiveXyzzDpFlag(expected, dp_bits);
			expected_dp_flags[i] = expected_dp_flag;
			expected_distances[i] = expected_distance;
			expected_dp_terms[i] = CompactXyzzDpTerm(expected, expected_dp_flag);
			local_dp_count += expected_dp_flag ? 1U : 0U;
		}
		local_dp_counts[worker_index] = local_dp_count;
	});
	for (unsigned int count : local_dp_counts)
		expected_dp_count += count;
	if (jump_histogram)
	{
		for (const std::vector<uint64_t>& local : local_jump_histograms)
			for (size_t bucket = 0; bucket < local.size(); ++bucket)
				(*jump_histogram)[bucket] += local[bucket];
	}
	if (emitted_records != expected_dp_count)
	{
		reason = "dynamic XYZZ dp stream count mismatch: got " + std::to_string(emitted_records) +
			" expected " + std::to_string(expected_dp_count);
		return false;
	}

	std::vector<uint8_t> seen(p.size(), 0);
	std::vector<uint64_t> stream_distances(p.size(), 0);
	std::vector<uint64_t> stream_dp_terms(p.size(), 0);
	for (size_t slot = 0; slot < out_indices.size(); ++slot)
	{
		uint32_t sample_index = out_indices[slot];
		if (sample_index >= p.size())
		{
			reason = "dynamic XYZZ dp stream index out of range at slot " + std::to_string(slot);
			return false;
		}
		if (seen[sample_index])
		{
			reason = "dynamic XYZZ dp stream duplicate index " + std::to_string(sample_index);
			return false;
		}
		if (!expected_dp_flags[sample_index])
		{
			reason = "dynamic XYZZ dp stream emitted non-DP sample " + std::to_string(sample_index);
			return false;
		}
		if (out_distances[slot] != expected_distances[sample_index] || out_dp_terms[slot] != expected_dp_terms[sample_index])
		{
			reason = "dynamic XYZZ dp stream mismatch at sample " + std::to_string(sample_index) +
				": distance=" + std::to_string(out_distances[slot]) +
				" dp_term=0x" + FieldToHex(FieldElement{out_dp_terms[slot], 0, 0, 0}) +
				" expected distance=" + std::to_string(expected_distances[sample_index]) +
				" expected dp_term=0x" + FieldToHex(FieldElement{expected_dp_terms[sample_index], 0, 0, 0});
			return false;
		}
		seen[sample_index] = 1;
		stream_distances[sample_index] = out_distances[slot];
		stream_dp_terms[sample_index] = out_dp_terms[slot];
	}
	for (size_t i = 0; i < p.size(); ++i)
	{
		if (expected_dp_flags[i] && !seen[i])
		{
			reason = "dynamic XYZZ dp stream missing DP sample " + std::to_string(i);
			return false;
		}
	}

	uint64_t dp_distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	for (size_t i = 0; i < p.size(); ++i)
	{
		uint32_t stream_dp_flag = seen[i] ? 1U : 0U;
		if (stream_dp_flag)
		{
			dp_distance_checksum = MixDistanceChecksum(dp_distance_checksum, stream_distances[i], i);
			dp_count++;
		}
		dp_checksum = MixCompactDpChecksum(dp_checksum, stream_dp_terms[i], stream_dp_flag, i);
	}

	if (dp_distance_checksum_out)
		*dp_distance_checksum_out = dp_distance_checksum;
	if (dp_checksum_out)
		*dp_checksum_out = dp_checksum;
	if (dp_count_out)
		*dp_count_out = dp_count;
	return true;
}

static bool ValidateDynamicXyzzDpStreamAndStateOutputs(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	const std::vector<CpuXyzzPoint>& state_out,
	const std::vector<uint32_t>& out_indices,
	const std::vector<uint64_t>& out_distances,
	const std::vector<uint64_t>& out_dp_terms,
	uint32_t emitted_records,
	bool dp_stream_overflow,
	unsigned int dp_bits,
	std::vector<uint64_t>* jump_histogram,
	uint64_t* dp_distance_checksum_out,
	uint64_t* dp_checksum_out,
	unsigned int* dp_count_out,
	std::string& reason)
{
	if (state_out.size() != p.size())
	{
		reason = "dynamic XYZZ state output size mismatch";
		return false;
	}
	if (dp_stream_overflow)
	{
		reason = "dynamic XYZZ dp stream overflow";
		return false;
	}
	if (out_indices.size() != emitted_records || out_distances.size() != emitted_records || out_dp_terms.size() != emitted_records)
	{
		reason = "dynamic XYZZ dp stream output size mismatch";
		return false;
	}

	struct ValidationResult
	{
		bool ok = true;
		std::string reason;
	};

	std::vector<uint32_t> expected_dp_flags(p.size(), 0);
	std::vector<uint64_t> expected_distances(p.size(), 0);
	std::vector<uint64_t> expected_dp_terms(p.size(), 0);
	unsigned int expected_dp_count = 0;
	unsigned int worker_count = ValidationWorkerCount(p.size());
	std::vector<unsigned int> local_dp_counts(worker_count, 0);
	std::vector<ValidationResult> results(worker_count);
	std::vector<std::vector<uint64_t> > local_jump_histograms;
	if (jump_histogram)
		local_jump_histograms.assign(worker_count, std::vector<uint64_t>(jump_histogram->size(), 0));
	ParallelForSamples(p.size(), [&](size_t begin, size_t end, unsigned int worker_index) {
		unsigned int local_dp_count = 0;
		std::vector<uint64_t>* local_jump_histogram = jump_histogram ? &local_jump_histograms[worker_index] : NULL;
		for (size_t i = begin; i < end; ++i)
		{
			uint64_t expected_distance = 0;
			CpuXyzzPoint expected = CpuXyzzDynamicJumpWalk(CpuXyzzFromJacobian(p[i]), jumps, jump_distances, steps_per_sample, &expected_distance, local_jump_histogram);
			if (!CpuXyzzMatches(state_out[i], expected))
			{
				results[worker_index].ok = false;
				results[worker_index].reason = "dynamic XYZZ state mismatch at sample " + std::to_string(i) +
					": got x=" + FieldToHex(state_out[i].x) +
					" y=" + FieldToHex(state_out[i].y) +
					" zz=" + FieldToHex(state_out[i].zz) +
					" zzz=" + FieldToHex(state_out[i].zzz) +
					" inf=" + (state_out[i].infinity ? "1" : "0") +
					" expected x=" + FieldToHex(expected.x) +
					" expected y=" + FieldToHex(expected.y) +
					" expected zz=" + FieldToHex(expected.zz) +
					" expected zzz=" + FieldToHex(expected.zzz) +
					" expected inf=" + (expected.infinity ? "1" : "0");
				break;
			}
			uint32_t expected_dp_flag = ProjectiveXyzzDpFlag(expected, dp_bits);
			expected_dp_flags[i] = expected_dp_flag;
			expected_distances[i] = expected_distance;
			expected_dp_terms[i] = CompactXyzzDpTerm(expected, expected_dp_flag);
			local_dp_count += expected_dp_flag ? 1U : 0U;
		}
		local_dp_counts[worker_index] = local_dp_count;
	});
	for (const ValidationResult& result : results)
	{
		if (!result.ok)
		{
			reason = result.reason;
			return false;
		}
	}
	for (unsigned int count : local_dp_counts)
		expected_dp_count += count;
	if (jump_histogram)
	{
		for (const std::vector<uint64_t>& local : local_jump_histograms)
			for (size_t bucket = 0; bucket < local.size(); ++bucket)
				(*jump_histogram)[bucket] += local[bucket];
	}
	if (emitted_records != expected_dp_count)
	{
		reason = "dynamic XYZZ dp stream count mismatch: got " + std::to_string(emitted_records) +
			" expected " + std::to_string(expected_dp_count);
		return false;
	}

	std::vector<uint8_t> seen(p.size(), 0);
	std::vector<uint64_t> stream_distances(p.size(), 0);
	std::vector<uint64_t> stream_dp_terms(p.size(), 0);
	for (size_t slot = 0; slot < out_indices.size(); ++slot)
	{
		uint32_t sample_index = out_indices[slot];
		if (sample_index >= p.size())
		{
			reason = "dynamic XYZZ dp stream index out of range at slot " + std::to_string(slot);
			return false;
		}
		if (seen[sample_index])
		{
			reason = "dynamic XYZZ dp stream duplicate index " + std::to_string(sample_index);
			return false;
		}
		if (!expected_dp_flags[sample_index])
		{
			reason = "dynamic XYZZ dp stream emitted non-DP sample " + std::to_string(sample_index);
			return false;
		}
		if (out_distances[slot] != expected_distances[sample_index] || out_dp_terms[slot] != expected_dp_terms[sample_index])
		{
			reason = "dynamic XYZZ dp stream mismatch at sample " + std::to_string(sample_index) +
				": distance=" + std::to_string(out_distances[slot]) +
				" dp_term=0x" + FieldToHex(FieldElement{out_dp_terms[slot], 0, 0, 0}) +
				" expected distance=" + std::to_string(expected_distances[sample_index]) +
				" expected dp_term=0x" + FieldToHex(FieldElement{expected_dp_terms[sample_index], 0, 0, 0});
			return false;
		}
		seen[sample_index] = 1;
		stream_distances[sample_index] = out_distances[slot];
		stream_dp_terms[sample_index] = out_dp_terms[slot];
	}
	for (size_t i = 0; i < p.size(); ++i)
	{
		if (expected_dp_flags[i] && !seen[i])
		{
			reason = "dynamic XYZZ dp stream missing DP sample " + std::to_string(i);
			return false;
		}
	}

	uint64_t dp_distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	for (size_t i = 0; i < p.size(); ++i)
	{
		uint32_t stream_dp_flag = seen[i] ? 1U : 0U;
		if (stream_dp_flag)
		{
			dp_distance_checksum = MixDistanceChecksum(dp_distance_checksum, stream_distances[i], i);
			dp_count++;
		}
		dp_checksum = MixCompactDpChecksum(dp_checksum, stream_dp_terms[i], stream_dp_flag, i);
	}

	if (dp_distance_checksum_out)
		*dp_distance_checksum_out = dp_distance_checksum;
	if (dp_checksum_out)
		*dp_checksum_out = dp_checksum;
	if (dp_count_out)
		*dp_count_out = dp_count;
	return true;
}

static bool ValidateDynamicXyzzChainDpStreamAndStateOutputs(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	unsigned int packet_count,
	const std::vector<CpuXyzzPoint>& state_out,
	const std::vector<uint32_t>& out_indices,
	const std::vector<uint64_t>& out_distances,
	const std::vector<uint64_t>& out_dp_terms,
	uint32_t emitted_records,
	bool dp_stream_overflow,
	unsigned int dp_bits,
	std::vector<uint64_t>* jump_histogram,
	uint64_t* dp_distance_checksum_out,
	uint64_t* dp_checksum_out,
	unsigned int* dp_count_out,
	std::string& reason)
{
	if (state_out.size() != p.size())
	{
		reason = "dynamic XYZZ chain state output size mismatch";
		return false;
	}
	if (dp_stream_overflow)
	{
		reason = "dynamic XYZZ chain dp stream overflow";
		return false;
	}
	if (out_indices.size() != emitted_records || out_distances.size() != emitted_records || out_dp_terms.size() != emitted_records)
	{
		reason = "dynamic XYZZ chain dp stream output size mismatch";
		return false;
	}
	uint64_t total_slots64 = (uint64_t)p.size() * packet_count;
	if (p.empty() || packet_count == 0 || total_slots64 > 0xFFFFFFFFULL)
	{
		reason = "dynamic XYZZ chain validation input out of range";
		return false;
	}
	size_t total_slots = (size_t)total_slots64;

	struct ValidationResult
	{
		bool ok = true;
		std::string reason;
	};

	std::vector<uint32_t> expected_dp_flags(total_slots, 0);
	std::vector<uint64_t> expected_distances(total_slots, 0);
	std::vector<uint64_t> expected_dp_terms(total_slots, 0);
	unsigned int expected_dp_count = 0;
	unsigned int worker_count = ValidationWorkerCount(p.size());
	std::vector<unsigned int> local_dp_counts(worker_count, 0);
	std::vector<ValidationResult> results(worker_count);
	std::vector<std::vector<uint64_t> > local_jump_histograms;
	if (jump_histogram)
		local_jump_histograms.assign(worker_count, std::vector<uint64_t>(jump_histogram->size(), 0));
	ParallelForSamples(p.size(), [&](size_t begin, size_t end, unsigned int worker_index) {
		unsigned int local_dp_count = 0;
		std::vector<uint64_t>* local_jump_histogram = jump_histogram ? &local_jump_histograms[worker_index] : NULL;
		for (size_t i = begin; i < end; ++i)
		{
			CpuXyzzPoint expected = CpuXyzzFromJacobian(p[i]);
			uint64_t cumulative_distance = 0;
			for (unsigned int packet = 0; packet < packet_count; ++packet)
			{
				uint64_t packet_distance = 0;
				expected = CpuXyzzDynamicJumpWalk(expected, jumps, jump_distances, steps_per_sample, &packet_distance, local_jump_histogram);
				cumulative_distance += packet_distance;
				size_t key = (size_t)packet * p.size() + i;
				uint32_t expected_dp_flag = ProjectiveXyzzDpFlag(expected, dp_bits);
				expected_dp_flags[key] = expected_dp_flag;
				expected_distances[key] = cumulative_distance;
				expected_dp_terms[key] = CompactXyzzDpTerm(expected, expected_dp_flag);
				local_dp_count += expected_dp_flag ? 1U : 0U;
			}
			if (!CpuXyzzMatches(state_out[i], expected))
			{
				results[worker_index].ok = false;
				results[worker_index].reason = "dynamic XYZZ chain state mismatch at sample " + std::to_string(i) +
					": got x=" + FieldToHex(state_out[i].x) +
					" y=" + FieldToHex(state_out[i].y) +
					" zz=" + FieldToHex(state_out[i].zz) +
					" zzz=" + FieldToHex(state_out[i].zzz) +
					" inf=" + (state_out[i].infinity ? "1" : "0") +
					" expected x=" + FieldToHex(expected.x) +
					" expected y=" + FieldToHex(expected.y) +
					" expected zz=" + FieldToHex(expected.zz) +
					" expected zzz=" + FieldToHex(expected.zzz) +
					" expected inf=" + (expected.infinity ? "1" : "0");
				break;
			}
		}
		local_dp_counts[worker_index] = local_dp_count;
	});
	for (const ValidationResult& result : results)
	{
		if (!result.ok)
		{
			reason = result.reason;
			return false;
		}
	}
	for (unsigned int count : local_dp_counts)
		expected_dp_count += count;
	if (jump_histogram)
	{
		for (const std::vector<uint64_t>& local : local_jump_histograms)
			for (size_t bucket = 0; bucket < local.size(); ++bucket)
				(*jump_histogram)[bucket] += local[bucket];
	}
	if (emitted_records != expected_dp_count)
	{
		reason = "dynamic XYZZ chain dp stream count mismatch: got " + std::to_string(emitted_records) +
			" expected " + std::to_string(expected_dp_count);
		return false;
	}

	std::vector<uint8_t> seen(total_slots, 0);
	std::vector<uint64_t> stream_distances(total_slots, 0);
	std::vector<uint64_t> stream_dp_terms(total_slots, 0);
	for (size_t slot = 0; slot < out_indices.size(); ++slot)
	{
		uint32_t stream_key = out_indices[slot];
		if ((uint64_t)stream_key >= total_slots64)
		{
			reason = "dynamic XYZZ chain dp stream index out of range at slot " + std::to_string(slot);
			return false;
		}
		size_t key = (size_t)stream_key;
		size_t sample_index = key % p.size();
		size_t packet_index = key / p.size();
		if (seen[key])
		{
			reason = "dynamic XYZZ chain dp stream duplicate packet/sample key " + std::to_string(key);
			return false;
		}
		if (!expected_dp_flags[key])
		{
			reason = "dynamic XYZZ chain dp stream emitted non-DP packet " + std::to_string(packet_index) +
				" sample " + std::to_string(sample_index);
			return false;
		}
		if (out_distances[slot] != expected_distances[key] || out_dp_terms[slot] != expected_dp_terms[key])
		{
			reason = "dynamic XYZZ chain dp stream mismatch at packet " + std::to_string(packet_index) +
				" sample " + std::to_string(sample_index) +
				": distance=" + std::to_string(out_distances[slot]) +
				" dp_term=0x" + FieldToHex(FieldElement{out_dp_terms[slot], 0, 0, 0}) +
				" expected distance=" + std::to_string(expected_distances[key]) +
				" expected dp_term=0x" + FieldToHex(FieldElement{expected_dp_terms[key], 0, 0, 0});
			return false;
		}
		seen[key] = 1;
		stream_distances[key] = out_distances[slot];
		stream_dp_terms[key] = out_dp_terms[slot];
	}
	for (size_t key = 0; key < total_slots; ++key)
	{
		if (expected_dp_flags[key] && !seen[key])
		{
			reason = "dynamic XYZZ chain dp stream missing DP key " + std::to_string(key);
			return false;
		}
	}

	uint64_t dp_distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	for (size_t key = 0; key < total_slots; ++key)
	{
		uint32_t stream_dp_flag = seen[key] ? 1U : 0U;
		if (stream_dp_flag)
		{
			dp_distance_checksum = MixDistanceChecksum(dp_distance_checksum, stream_distances[key], key);
			dp_count++;
		}
		dp_checksum = MixCompactDpChecksum(dp_checksum, stream_dp_terms[key], stream_dp_flag, key);
	}

	if (dp_distance_checksum_out)
		*dp_distance_checksum_out = dp_distance_checksum;
	if (dp_checksum_out)
		*dp_checksum_out = dp_checksum;
	if (dp_count_out)
		*dp_count_out = dp_count;
	return true;
}

static bool ValidateDynamicStateOutputs(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	const std::vector<CpuJacobianPoint>& state_out,
	std::string& reason)
{
	if (state_out.size() != p.size())
	{
		reason = "dynamic state output size mismatch";
		return false;
	}

	struct ValidationResult
	{
		bool ok = true;
		std::string reason;
	};
	unsigned int worker_count = ValidationWorkerCount(p.size());
	std::vector<ValidationResult> results(worker_count);
	ParallelForSamples(p.size(), [&](size_t begin, size_t end, unsigned int worker_index) {
		for (size_t i = begin; i < end; ++i)
		{
			CpuJacobianPoint expected = CpuJacobianDynamicJumpWalk(p[i], jumps, jump_distances, steps_per_sample, NULL);
			if (!CpuJacobianMatches(state_out[i], expected))
			{
				results[worker_index].ok = false;
				results[worker_index].reason = "dynamic state mismatch at sample " + std::to_string(i) +
					": got x=" + FieldToHex(state_out[i].x) +
					" y=" + FieldToHex(state_out[i].y) +
					" z=" + FieldToHex(state_out[i].z) +
					" inf=" + (state_out[i].infinity ? "1" : "0") +
					" expected x=" + FieldToHex(expected.x) +
					" y=" + FieldToHex(expected.y) +
					" z=" + FieldToHex(expected.z) +
					" inf=" + (expected.infinity ? "1" : "0");
				break;
			}
		}
	});
	for (const ValidationResult& result : results)
	{
		if (!result.ok)
		{
			reason = result.reason;
			return false;
		}
	}
	return true;
}

static bool ValidateDynamicXyzzStateOutputs(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	const std::vector<CpuXyzzPoint>& state_out,
	std::string& reason)
{
	if (state_out.size() != p.size())
	{
		reason = "dynamic XYZZ state output size mismatch";
		return false;
	}

	struct ValidationResult
	{
		bool ok = true;
		std::string reason;
	};
	unsigned int worker_count = ValidationWorkerCount(p.size());
	std::vector<ValidationResult> results(worker_count);
	ParallelForSamples(p.size(), [&](size_t begin, size_t end, unsigned int worker_index) {
		for (size_t i = begin; i < end; ++i)
		{
			CpuXyzzPoint expected = CpuXyzzDynamicJumpWalk(CpuXyzzFromJacobian(p[i]), jumps, jump_distances, steps_per_sample, NULL);
			if (!CpuXyzzMatches(state_out[i], expected))
			{
				results[worker_index].ok = false;
				results[worker_index].reason = "dynamic XYZZ state mismatch at sample " + std::to_string(i) +
					": got x=" + FieldToHex(state_out[i].x) +
					" y=" + FieldToHex(state_out[i].y) +
					" zz=" + FieldToHex(state_out[i].zz) +
					" zzz=" + FieldToHex(state_out[i].zzz) +
					" inf=" + (state_out[i].infinity ? "1" : "0") +
					" expected x=" + FieldToHex(expected.x) +
					" expected y=" + FieldToHex(expected.y) +
					" expected zz=" + FieldToHex(expected.zz) +
					" expected zzz=" + FieldToHex(expected.zzz) +
					" expected inf=" + (expected.infinity ? "1" : "0");
				break;
			}
		}
	});
	for (const ValidationResult& result : results)
	{
		if (!result.ok)
		{
			reason = result.reason;
			return false;
		}
	}
	return true;
}

static bool ValidateDynamicXyzzStateDistanceOutputs(const std::vector<CpuJacobianPoint>& p,
	const std::vector<CpuAffinePoint>& jumps,
	const std::vector<uint64_t>& jump_distances,
	unsigned int steps_per_sample,
	const std::vector<CpuXyzzPoint>& state_out,
	const std::vector<uint64_t>& distances_out,
	std::vector<uint64_t>* jump_histogram,
	std::string& reason)
{
	if (state_out.size() != p.size() || distances_out.size() != p.size())
	{
		reason = "dynamic XYZZ state/distance output size mismatch";
		return false;
	}

	struct ValidationResult
	{
		bool ok = true;
		std::string reason;
	};
	unsigned int worker_count = ValidationWorkerCount(p.size());
	std::vector<ValidationResult> results(worker_count);
	std::vector<std::vector<uint64_t> > local_jump_histograms;
	if (jump_histogram)
		local_jump_histograms.assign(worker_count, std::vector<uint64_t>(jump_histogram->size(), 0));
	ParallelForSamples(p.size(), [&](size_t begin, size_t end, unsigned int worker_index) {
		std::vector<uint64_t>* local_jump_histogram = jump_histogram ? &local_jump_histograms[worker_index] : NULL;
		for (size_t i = begin; i < end; ++i)
		{
			uint64_t expected_distance = 0;
			CpuXyzzPoint expected = CpuXyzzDynamicJumpWalk(CpuXyzzFromJacobian(p[i]), jumps, jump_distances, steps_per_sample, &expected_distance, local_jump_histogram);
			if (!CpuXyzzMatches(state_out[i], expected) || distances_out[i] != expected_distance)
			{
				results[worker_index].ok = false;
				results[worker_index].reason = "dynamic XYZZ state/distance mismatch at sample " + std::to_string(i) +
					": got x=" + FieldToHex(state_out[i].x) +
					" y=" + FieldToHex(state_out[i].y) +
					" zz=" + FieldToHex(state_out[i].zz) +
					" zzz=" + FieldToHex(state_out[i].zzz) +
					" distance=" + std::to_string(distances_out[i]) +
					" inf=" + (state_out[i].infinity ? "1" : "0") +
					" expected x=" + FieldToHex(expected.x) +
					" expected y=" + FieldToHex(expected.y) +
					" expected zz=" + FieldToHex(expected.zz) +
					" expected zzz=" + FieldToHex(expected.zzz) +
					" expected distance=" + std::to_string(expected_distance) +
					" expected inf=" + (expected.infinity ? "1" : "0");
				break;
			}
		}
	});
	for (const ValidationResult& result : results)
	{
		if (!result.ok)
		{
			reason = result.reason;
			return false;
		}
	}
	if (jump_histogram)
	{
		for (const std::vector<uint64_t>& local : local_jump_histograms)
			for (size_t bucket = 0; bucket < local.size(); ++bucket)
				(*jump_histogram)[bucket] += local[bucket];
	}
	return true;
}

bool RCKMetalJacobianWalkSelfTest(std::string& error)
{
	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> q;
	BuildJacobianAddSamples(24, p, q);

	const unsigned int steps_per_sample = 5;
	std::vector<CpuJacobianPoint> out;
	if (!RunJacobianAddAffineKernel(p, q, out, error, NULL, 0, NULL, "jacobian_affine_walk_fixed", steps_per_sample))
		return false;

	for (size_t i = 0; i < p.size(); ++i)
	{
		CpuJacobianPoint expected = CpuJacobianWalkFixed(p[i], q[i], steps_per_sample);
		if (!CpuJacobianMatches(out[i], expected))
		{
			error = "jacobian walk mismatch at vector " + std::to_string(i) +
				": got x=" + FieldToHex(out[i].x) + " y=" + FieldToHex(out[i].y) +
				" z=" + FieldToHex(out[i].z) + " inf=" + (out[i].infinity ? "1" : "0") +
				" expected x=" + FieldToHex(expected.x) + " y=" + FieldToHex(expected.y) +
				" z=" + FieldToHex(expected.z) + " inf=" + (expected.infinity ? "1" : "0");
			return false;
		}
	}
	return true;
}

bool RCKMetalJacobianJumpWalkSelfTest(std::string& error)
{
	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	std::vector<uint32_t> jump_indices;

	const unsigned int sample_count = 24;
	const unsigned int steps_per_sample = 7;
	const unsigned int jump_count = 5;
	BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
	BuildJacobianJumpDistances(jump_count, jump_distances);
	BuildDeterministicJumpIndices(sample_count, steps_per_sample, jump_count, jump_indices);

	std::vector<CpuJacobianPoint> out;
	std::vector<uint64_t> out_distances;
	std::vector<uint32_t> out_dp_flags;
	const unsigned int dp_bits = 4;
	if (!RunJacobianJumpWalkKernel(p, jumps, jump_distances, jump_indices, steps_per_sample, out, out_distances, out_dp_flags, dp_bits, error, NULL, 0, NULL))
		return false;

	for (size_t i = 0; i < p.size(); ++i)
	{
		uint64_t expected_distance = 0;
		CpuJacobianPoint expected = CpuJacobianJumpWalk(p[i], jumps, jump_distances, jump_indices, i, steps_per_sample, &expected_distance);
		uint32_t expected_dp_flag = ProjectiveDpFlag(expected, dp_bits);
		if (!CpuJacobianMatches(out[i], expected) || out_distances[i] != expected_distance || out_dp_flags[i] != expected_dp_flag)
		{
			error = "jacobian jump walk mismatch at vector " + std::to_string(i) +
				": got x=" + FieldToHex(out[i].x) + " y=" + FieldToHex(out[i].y) +
				" z=" + FieldToHex(out[i].z) + " inf=" + (out[i].infinity ? "1" : "0") +
				" distance=" + std::to_string(out_distances[i]) +
				" dp=" + std::to_string(out_dp_flags[i]) +
				" expected x=" + FieldToHex(expected.x) + " y=" + FieldToHex(expected.y) +
				" z=" + FieldToHex(expected.z) + " inf=" + (expected.infinity ? "1" : "0");
			return false;
		}
	}

	std::vector<CpuJacobianPoint> edge_p_source;
	std::vector<CpuAffinePoint> edge_q_source;
	BuildJacobianAddSamples(4, edge_p_source, edge_q_source);

	std::vector<CpuJacobianPoint> edge_p = {edge_p_source[2]};
	std::vector<CpuAffinePoint> edge_jumps = {edge_q_source[2], edge_q_source[3]};
	std::vector<uint64_t> edge_distances = {1ULL, 2ULL};
	std::vector<uint32_t> edge_indices = {0U, 1U, 1U, 1U, 1U, 1U, 1U, 1U};
	std::vector<CpuJacobianPoint> edge_out;
	std::vector<uint64_t> edge_out_distances;
	std::vector<uint32_t> edge_out_dp_flags;
	if (!RunJacobianJumpWalkKernel(edge_p, edge_jumps, edge_distances, edge_indices, 8, edge_out, edge_out_distances, edge_out_dp_flags, dp_bits, error, NULL, 0, NULL))
		return false;

	uint64_t edge_expected_distance = 0;
	CpuJacobianPoint edge_expected = CpuJacobianJumpWalk(edge_p[0], edge_jumps, edge_distances, edge_indices, 0, 8, &edge_expected_distance);
	uint32_t edge_expected_dp_flag = ProjectiveDpFlag(edge_expected, dp_bits);
	if (!CpuJacobianMatches(edge_out[0], edge_expected) || edge_out_distances[0] != edge_expected_distance || edge_out_dp_flags[0] != edge_expected_dp_flag)
	{
		error = "jacobian jump walk dp4 infinity-tail mismatch" +
			std::string(": got x=") + FieldToHex(edge_out[0].x) + " y=" + FieldToHex(edge_out[0].y) +
			" z=" + FieldToHex(edge_out[0].z) + " inf=" + (edge_out[0].infinity ? "1" : "0") +
			" distance=" + std::to_string(edge_out_distances[0]) +
			" dp=" + std::to_string(edge_out_dp_flags[0]) +
			" expected x=" + FieldToHex(edge_expected.x) + " y=" + FieldToHex(edge_expected.y) +
			" z=" + FieldToHex(edge_expected.z) + " inf=" + (edge_expected.infinity ? "1" : "0");
		return false;
	}
	return true;
}

bool RCKMetalJacobianDynamicWalkSelfTest(std::string& error)
{
	const unsigned int sample_count = 24;
	const unsigned int steps_per_sample = 7;
	const unsigned int dp_bits = 4;
	const unsigned int jump_counts[] = {8, 5};

	for (unsigned int jump_count : jump_counts)
	{
		std::vector<CpuJacobianPoint> p;
		std::vector<CpuAffinePoint> jumps;
		std::vector<uint64_t> jump_distances;
		BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
		BuildJacobianJumpDistances(jump_count, jump_distances);

		std::vector<CpuJacobianPoint> out;
		std::vector<uint64_t> out_distances;
		std::vector<uint32_t> out_dp_flags;
		if (!RunJacobianDynamicJumpWalkKernel(p, jumps, jump_distances, steps_per_sample, out, out_distances, out_dp_flags, dp_bits, error, NULL, 0, NULL))
			return false;

		for (size_t i = 0; i < p.size(); ++i)
		{
			uint64_t expected_distance = 0;
			CpuJacobianPoint expected = CpuJacobianDynamicJumpWalk(p[i], jumps, jump_distances, steps_per_sample, &expected_distance);
			uint32_t expected_dp_flag = ProjectiveDpFlag(expected, dp_bits);
			if (!CpuJacobianMatches(out[i], expected) || out_distances[i] != expected_distance || out_dp_flags[i] != expected_dp_flag)
			{
				error = "jacobian dynamic jump walk mismatch at vector " + std::to_string(i) +
					" jumps=" + std::to_string(jump_count) +
					": got x=" + FieldToHex(out[i].x) + " y=" + FieldToHex(out[i].y) +
					" z=" + FieldToHex(out[i].z) + " inf=" + (out[i].infinity ? "1" : "0") +
					" distance=" + std::to_string(out_distances[i]) +
					" dp=" + std::to_string(out_dp_flags[i]) +
					" expected x=" + FieldToHex(expected.x) + " y=" + FieldToHex(expected.y) +
					" z=" + FieldToHex(expected.z) + " inf=" + (expected.infinity ? "1" : "0");
				return false;
			}
		}
	}
	return true;
}

bool RCKMetalJacobianDynamicCompactDpSelfTest(std::string& error)
{
	const unsigned int sample_count = 24;
	const unsigned int steps_per_sample = 8;
	const unsigned int dp_bits = 4;
	const unsigned int jump_count = 8;

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
	BuildJacobianJumpDistances(jump_count, jump_distances);

	std::vector<uint8_t> out_flags;
	std::vector<uint64_t> out_distances;
	std::vector<uint64_t> out_dp_terms;
	if (!RunJacobianDynamicCompactDpKernel(p, jumps, jump_distances, steps_per_sample, out_flags, out_distances, out_dp_terms, dp_bits, error, NULL, 0, NULL))
		return false;

	for (size_t i = 0; i < p.size(); ++i)
	{
		uint64_t expected_distance = 0;
		CpuJacobianPoint expected = CpuJacobianDynamicJumpWalk(p[i], jumps, jump_distances, steps_per_sample, &expected_distance);
		uint32_t expected_inf_flag = expected.infinity ? 1U : 0U;
		uint32_t expected_dp_flag = ProjectiveDpFlag(expected, dp_bits);
		uint64_t expected_dp_term = CompactDpTerm(expected, expected_dp_flag);
		uint32_t got_inf_flag = (out_flags[i] & 1U) ? 1U : 0U;
		uint32_t got_dp_flag = (out_flags[i] & 2U) ? 1U : 0U;
		if (out_distances[i] != expected_distance || got_inf_flag != expected_inf_flag || got_dp_flag != expected_dp_flag || out_dp_terms[i] != expected_dp_term)
		{
			error = "jacobian dynamic compact dp mismatch at vector " + std::to_string(i) +
				": distance=" + std::to_string(out_distances[i]) +
				" flags=" + std::to_string((unsigned int)out_flags[i]) +
				" dp_term=0x" + FieldToHex(FieldElement{out_dp_terms[i], 0, 0, 0}) +
				" expected distance=" + std::to_string(expected_distance) +
				" inf=" + std::to_string(expected_inf_flag) +
				" dp=" + std::to_string(expected_dp_flag) +
				" expected dp_term=0x" + FieldToHex(FieldElement{expected_dp_term, 0, 0, 0});
			return false;
		}
	}
	return true;
}

bool RCKMetalJacobianDynamicDpStreamSelfTest(std::string& error)
{
	const unsigned int sample_count = 24;
	const unsigned int steps_per_sample = 8;
	const unsigned int dp_bit_cases[] = {4, 8};
	const unsigned int jump_count = 8;

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
	BuildJacobianJumpDistances(jump_count, jump_distances);

	for (unsigned int dp_bits : dp_bit_cases)
	{
		std::vector<uint32_t> out_indices;
		std::vector<uint64_t> out_distances;
		std::vector<uint64_t> out_dp_terms;
		uint32_t emitted_records = 0;
		bool dp_stream_overflow = false;
		if (!RunJacobianDynamicDpStreamKernel(p, jumps, jump_distances, steps_per_sample, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, error, NULL, 0, NULL))
			return false;

		if (!ValidateDynamicDpStreamOutputs(p, jumps, jump_distances, steps_per_sample, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, NULL, NULL, NULL, NULL, error))
			return false;
	}
	return true;
}

bool RCKMetalJacobianDynamicDpStreamInplaceSelfTest(std::string& error)
{
	const unsigned int sample_count = 24;
	const unsigned int dp_bits = 8;
	const unsigned int jump_count = 8;

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
	BuildJacobianJumpDistances(jump_count, jump_distances);

	for (unsigned int steps_per_sample : {8U, 16U, 32U, 64U, 128U, 256U})
	{
		std::vector<CpuJacobianPoint> state_out;
		std::vector<uint32_t> out_indices;
		std::vector<uint64_t> out_distances;
		std::vector<uint64_t> out_dp_terms;
		uint32_t emitted_records = 0;
		bool dp_stream_overflow = false;
		if (!RunJacobianDynamicDpStreamInplaceKernel(p, jumps, jump_distances, steps_per_sample, state_out, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, error, NULL, 0, NULL))
			return false;

		if (!ValidateDynamicDpStreamOutputs(p, jumps, jump_distances, steps_per_sample, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, NULL, NULL, NULL, NULL, error))
			return false;
		if (!ValidateDynamicStateOutputs(p, jumps, jump_distances, steps_per_sample, state_out, error))
			return false;
	}
	return true;
}

bool RCKMetalJacobianDynamicDpStreamXyzzSelfTest(std::string& error)
{
	const unsigned int sample_count = 24;
	const unsigned int dp_bits = 8;
	const unsigned int jump_count = 8;

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
	BuildJacobianJumpDistances(jump_count, jump_distances);

	for (unsigned int steps_per_sample : {256U, 512U})
	{
		std::vector<CpuXyzzPoint> state_out;
		std::vector<uint32_t> out_indices;
		std::vector<uint64_t> out_distances;
		std::vector<uint64_t> out_dp_terms;
		uint32_t emitted_records = 0;
		bool dp_stream_overflow = false;
		if (!RunJacobianDynamicDpStreamXyzzKernel(p, jumps, jump_distances, steps_per_sample, state_out, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, error, NULL, 0, NULL))
			return false;
		if (!ValidateDynamicXyzzDpStreamOutputs(p, jumps, jump_distances, steps_per_sample, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, NULL, NULL, NULL, NULL, error))
			return false;
		if (!ValidateDynamicXyzzStateOutputs(p, jumps, jump_distances, steps_per_sample, state_out, error))
			return false;

		state_out.clear();
		out_indices.clear();
		out_distances.clear();
		out_dp_terms.clear();
		emitted_records = 0;
		dp_stream_overflow = false;
		if (!RunJacobianDynamicDpStreamXyzzChainKernel(p, jumps, jump_distances, steps_per_sample, 2, state_out, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, error, NULL, 0, NULL))
			return false;
		if (!ValidateDynamicXyzzChainDpStreamAndStateOutputs(p, jumps, jump_distances, steps_per_sample, 2, state_out, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, NULL, NULL, NULL, NULL, error))
			return false;
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
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveTargetLookupThreadgroupLimit(threadgroup_limit);
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

std::string RCKMetalJacobianWalkBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int min_ms, unsigned int threadgroup_limit)
{
	if (iterations == 0)
		iterations = 1;
	if (steps_per_sample == 0)
		steps_per_sample = 1;

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
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveTargetLookupThreadgroupLimit(threadgroup_limit);
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunJacobianAddAffineKernel(p, q, out, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats, "jacobian_affine_walk_fixed", steps_per_sample))
		{
			if (error == "no Metal device available")
				return MetalJacobianWalkBenchJson("jacobian_affine_walk_fixed", 0, sample_count, steps_per_sample, min_ms, dispatch_stats, 0.0, 0.0, false, true, error);
			return MetalJacobianWalkBenchJson("jacobian_affine_walk_fixed", operations ? operations : (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, min_ms, dispatch_stats, seconds, 0.0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += (uint64_t)sample_count * steps_per_sample;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	for (unsigned int i = 0; i < sample_count; ++i)
	{
		CpuJacobianPoint expected = CpuJacobianWalkFixed(p[i], q[i], steps_per_sample);
		if (!CpuJacobianMatches(out[i], expected))
		{
			std::string reason = "mismatch at vector " + std::to_string(i) +
				": got x=" + FieldToHex(out[i].x) + " y=" + FieldToHex(out[i].y) +
				" z=" + FieldToHex(out[i].z) + " inf=" + (out[i].infinity ? "1" : "0") +
				" expected x=" + FieldToHex(expected.x) + " y=" + FieldToHex(expected.y) +
				" z=" + FieldToHex(expected.z) + " inf=" + (expected.infinity ? "1" : "0");
			return MetalJacobianWalkBenchJson("jacobian_affine_walk_fixed", operations, sample_count, steps_per_sample, min_ms, dispatch_stats, seconds, 0.0, false, false, reason);
		}
	}

	double ops_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	return MetalJacobianWalkBenchJson("jacobian_affine_walk_fixed", operations, sample_count, steps_per_sample, min_ms, dispatch_stats, seconds, ops_per_sec, true, false, "");
}

std::string RCKMetalJacobianJumpWalkBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit, unsigned int dp_bits)
{
	if (iterations == 0)
		iterations = 1;
	if (steps_per_sample == 0)
		steps_per_sample = 1;
	jump_count = NormalizeMetalJumpCount(jump_count);
	dp_bits = NormalizeMetalDpBits(dp_bits);

	const unsigned int sample_count = iterations;
	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	std::vector<uint32_t> jump_indices;
	BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
	BuildJacobianJumpDistances(jump_count, jump_distances);
	BuildDeterministicJumpIndices(sample_count, steps_per_sample, jump_count, jump_indices);

	std::vector<CpuJacobianPoint> out;
	std::vector<uint64_t> out_distances;
	std::vector<uint32_t> out_dp_flags;
	std::string error;
	double seconds = 0.0;
	uint64_t operations = 0;
	uint64_t distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	unsigned int dispatch_count = 0;
	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveTargetLookupThreadgroupLimit(threadgroup_limit);
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunJacobianJumpWalkKernel(p, jumps, jump_distances, jump_indices, steps_per_sample, out, out_distances, out_dp_flags, dp_bits, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalJacobianJumpWalkBenchJson("jacobian_affine_walk_jump_table", 0, sample_count, steps_per_sample, jump_count, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, false, true, error);
			return MetalJacobianJumpWalkBenchJson("jacobian_affine_walk_jump_table", operations ? operations : (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, 0, dp_bits, 0, 0, min_ms, dispatch_stats, seconds, 0.0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += (uint64_t)sample_count * steps_per_sample;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	for (unsigned int i = 0; i < sample_count; ++i)
	{
		uint64_t expected_distance = 0;
		CpuJacobianPoint expected = CpuJacobianJumpWalk(p[i], jumps, jump_distances, jump_indices, i, steps_per_sample, &expected_distance);
		uint32_t expected_dp_flag = ProjectiveDpFlag(expected, dp_bits);
		if (!CpuJacobianMatches(out[i], expected) || out_distances[i] != expected_distance || out_dp_flags[i] != expected_dp_flag)
		{
			std::string reason = "mismatch at vector " + std::to_string(i) +
				": got x=" + FieldToHex(out[i].x) + " y=" + FieldToHex(out[i].y) +
				" z=" + FieldToHex(out[i].z) + " inf=" + (out[i].infinity ? "1" : "0") +
				" distance=" + std::to_string(out_distances[i]) +
				" dp=" + std::to_string(out_dp_flags[i]) +
				" expected x=" + FieldToHex(expected.x) + " y=" + FieldToHex(expected.y) +
				" z=" + FieldToHex(expected.z) + " inf=" + (expected.infinity ? "1" : "0");
			return MetalJacobianJumpWalkBenchJson("jacobian_affine_walk_jump_table", operations, sample_count, steps_per_sample, jump_count, 0, dp_bits, 0, 0, min_ms, dispatch_stats, seconds, 0.0, false, false, reason);
		}
		distance_checksum = MixDistanceChecksum(distance_checksum, out_distances[i], i);
		dp_count += out_dp_flags[i] ? 1U : 0U;
		dp_checksum = MixDpChecksum(dp_checksum, out[i], out_dp_flags[i], i);
	}

	double ops_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	return MetalJacobianJumpWalkBenchJson("jacobian_affine_walk_jump_table", operations, sample_count, steps_per_sample, jump_count, distance_checksum, dp_bits, dp_count, dp_checksum, min_ms, dispatch_stats, seconds, ops_per_sec, true, false, "");
}

std::string RCKMetalJacobianDynamicWalkBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit, unsigned int dp_bits)
{
	if (iterations == 0)
		iterations = 1;
	if (steps_per_sample == 0)
		steps_per_sample = 1;
	jump_count = NormalizeMetalJumpCount(jump_count);
	dp_bits = NormalizeMetalDpBits(dp_bits);
	const char* jump_index_mode = MetalJumpIndexMode(jump_count);

	const unsigned int sample_count = iterations;
	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
	BuildJacobianJumpDistances(jump_count, jump_distances);

	std::vector<CpuJacobianPoint> out;
	std::vector<uint64_t> out_distances;
	std::vector<uint32_t> out_dp_flags;
	std::string error;
	double seconds = 0.0;
	uint64_t operations = 0;
	uint64_t distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	unsigned int dispatch_count = 0;
	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunJacobianDynamicJumpWalkKernel(p, jumps, jump_distances, steps_per_sample, out, out_distances, out_dp_flags, dp_bits, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalJacobianDynamicJumpWalkBenchJson("jacobian_affine_walk_dynamic_jump_table", 0, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, false, true, error);
			return MetalJacobianDynamicJumpWalkBenchJson("jacobian_affine_walk_dynamic_jump_table", operations ? operations : (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_bits, 0, 0, min_ms, dispatch_stats, seconds, 0.0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += (uint64_t)sample_count * steps_per_sample;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	std::vector<uint64_t> jump_histogram(jump_count, 0);
	for (unsigned int i = 0; i < sample_count; ++i)
	{
		uint64_t expected_distance = 0;
		CpuJacobianPoint expected = CpuJacobianDynamicJumpWalk(p[i], jumps, jump_distances, steps_per_sample, &expected_distance, &jump_histogram);
		uint32_t expected_dp_flag = ProjectiveDpFlag(expected, dp_bits);
		if (!CpuJacobianMatches(out[i], expected) || out_distances[i] != expected_distance || out_dp_flags[i] != expected_dp_flag)
		{
			std::string reason = "mismatch at vector " + std::to_string(i) +
				": got x=" + FieldToHex(out[i].x) + " y=" + FieldToHex(out[i].y) +
				" z=" + FieldToHex(out[i].z) + " inf=" + (out[i].infinity ? "1" : "0") +
				" distance=" + std::to_string(out_distances[i]) +
				" dp=" + std::to_string(out_dp_flags[i]) +
				" expected x=" + FieldToHex(expected.x) + " y=" + FieldToHex(expected.y) +
				" z=" + FieldToHex(expected.z) + " inf=" + (expected.infinity ? "1" : "0");
			return MetalJacobianDynamicJumpWalkBenchJson("jacobian_affine_walk_dynamic_jump_table", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_bits, 0, 0, min_ms, dispatch_stats, seconds, 0.0, false, false, reason);
		}
		distance_checksum = MixDistanceChecksum(distance_checksum, out_distances[i], i);
		dp_count += out_dp_flags[i] ? 1U : 0U;
		dp_checksum = MixDpChecksum(dp_checksum, out[i], out_dp_flags[i], i);
	}

	double ops_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	uint64_t jump_histogram_min_bucket = JumpHistogramMinBucket(jump_histogram);
	uint64_t jump_histogram_max_bucket = JumpHistogramMaxBucket(jump_histogram);
	uint64_t jump_histogram_max_deviation_ppm = JumpHistogramMaxDeviationPpm(jump_histogram);
	return MetalJacobianDynamicJumpWalkBenchJson("jacobian_affine_walk_dynamic_jump_table", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_histogram_min_bucket, jump_histogram_max_bucket, jump_histogram_max_deviation_ppm, distance_checksum, dp_bits, dp_count, dp_checksum, min_ms, dispatch_stats, seconds, ops_per_sec, true, false, "");
}

std::string RCKMetalJacobianDynamicCompactDpBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit, unsigned int dp_bits)
{
	if (iterations == 0)
		iterations = 1;
	if (steps_per_sample == 0)
		steps_per_sample = 8;
	if (dp_bits == 0)
		dp_bits = 4;
	jump_count = NormalizeMetalJumpCount(jump_count);
	dp_bits = NormalizeMetalDpBits(dp_bits);
	const char* jump_index_mode = MetalJumpIndexMode(jump_count);
	const unsigned int sample_count = iterations;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);
	if (steps_per_sample != 8 || dp_bits != 4 || !IsMetalPowerOfTwo(jump_count))
	{
		std::string reason = "compact dynamic dp supports steps=8, power-of-two jumps, dp_bits=4";
		return MetalJacobianDynamicCompactDpBenchJson("jacobian_affine_walk_dynamic_dp_compact", (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, false, false, reason);
	}

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
	BuildJacobianJumpDistances(jump_count, jump_distances);

	std::vector<uint8_t> out_flags;
	std::vector<uint64_t> out_distances;
	std::vector<uint64_t> out_dp_terms;
	std::string error;
	double seconds = 0.0;
	uint64_t operations = 0;
	uint64_t distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	unsigned int dispatch_count = 0;
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunJacobianDynamicCompactDpKernel(p, jumps, jump_distances, steps_per_sample, out_flags, out_distances, out_dp_terms, dp_bits, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalJacobianDynamicCompactDpBenchJson("jacobian_affine_walk_dynamic_dp_compact", 0, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, false, true, error);
			return MetalJacobianDynamicCompactDpBenchJson("jacobian_affine_walk_dynamic_dp_compact", operations ? operations : (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_bits, 0, 0, min_ms, dispatch_stats, seconds, 0.0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += (uint64_t)sample_count * steps_per_sample;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	std::vector<uint64_t> jump_histogram(jump_count, 0);
	for (unsigned int i = 0; i < sample_count; ++i)
	{
		uint64_t expected_distance = 0;
		CpuJacobianPoint expected = CpuJacobianDynamicJumpWalk(p[i], jumps, jump_distances, steps_per_sample, &expected_distance, &jump_histogram);
		uint32_t expected_inf_flag = expected.infinity ? 1U : 0U;
		uint32_t expected_dp_flag = ProjectiveDpFlag(expected, dp_bits);
		uint64_t expected_dp_term = CompactDpTerm(expected, expected_dp_flag);
		uint32_t got_inf_flag = (out_flags[i] & 1U) ? 1U : 0U;
		uint32_t got_dp_flag = (out_flags[i] & 2U) ? 1U : 0U;
		if (out_distances[i] != expected_distance || got_inf_flag != expected_inf_flag || got_dp_flag != expected_dp_flag || out_dp_terms[i] != expected_dp_term)
		{
			std::string reason = "compact dp mismatch at vector " + std::to_string(i) +
				": distance=" + std::to_string(out_distances[i]) +
				" flags=" + std::to_string((unsigned int)out_flags[i]) +
				" dp_term=0x" + FieldToHex(FieldElement{out_dp_terms[i], 0, 0, 0}) +
				" expected distance=" + std::to_string(expected_distance) +
				" inf=" + std::to_string(expected_inf_flag) +
				" dp=" + std::to_string(expected_dp_flag) +
				" expected dp_term=0x" + FieldToHex(FieldElement{expected_dp_term, 0, 0, 0});
			return MetalJacobianDynamicCompactDpBenchJson("jacobian_affine_walk_dynamic_dp_compact", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_bits, 0, 0, min_ms, dispatch_stats, seconds, 0.0, false, false, reason);
		}
		distance_checksum = MixDistanceChecksum(distance_checksum, out_distances[i], i);
		dp_count += got_dp_flag ? 1U : 0U;
		dp_checksum = MixCompactDpChecksum(dp_checksum, out_dp_terms[i], got_dp_flag, i);
	}

	double ops_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	uint64_t jump_histogram_min_bucket = JumpHistogramMinBucket(jump_histogram);
	uint64_t jump_histogram_max_bucket = JumpHistogramMaxBucket(jump_histogram);
	uint64_t jump_histogram_max_deviation_ppm = JumpHistogramMaxDeviationPpm(jump_histogram);
	return MetalJacobianDynamicCompactDpBenchJson("jacobian_affine_walk_dynamic_dp_compact", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_histogram_min_bucket, jump_histogram_max_bucket, jump_histogram_max_deviation_ppm, distance_checksum, dp_bits, dp_count, dp_checksum, min_ms, dispatch_stats, seconds, ops_per_sec, true, false, "");
}

std::string RCKMetalJacobianDynamicDpStreamBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit, unsigned int dp_bits)
{
	if (iterations == 0)
		iterations = 1;
	if (steps_per_sample == 0)
		steps_per_sample = 8;
	if (dp_bits == 0)
		dp_bits = 4;
	jump_count = NormalizeMetalJumpCount(jump_count);
	dp_bits = NormalizeMetalDpBits(dp_bits);
	const char* jump_index_mode = MetalJumpIndexMode(jump_count);
	const unsigned int sample_count = iterations;
	const unsigned int dp_capacity = sample_count;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);
	if (steps_per_sample != 8 || dp_bits > 32 || !IsMetalPowerOfTwo(jump_count))
	{
		std::string reason = "stream dynamic dp supports steps=8, power-of-two jumps, dp_bits=0..32";
		return MetalJacobianDynamicDpStreamBenchJson("jacobian_affine_walk_dynamic_dp_stream", (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, false, false, reason);
	}

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
	BuildJacobianJumpDistances(jump_count, jump_distances);

	std::vector<uint32_t> out_indices;
	std::vector<uint64_t> out_distances;
	std::vector<uint64_t> out_dp_terms;
	uint32_t emitted_records = 0;
	bool dp_stream_overflow = false;
	std::string error;
	double seconds = 0.0;
	uint64_t operations = 0;
	unsigned int dispatch_count = 0;
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunJacobianDynamicDpStreamKernel(p, jumps, jump_distances, steps_per_sample, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalJacobianDynamicDpStreamBenchJson("jacobian_affine_walk_dynamic_dp_stream", 0, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, false, true, error);
			return MetalJacobianDynamicDpStreamBenchJson("jacobian_affine_walk_dynamic_dp_stream", operations ? operations : (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, seconds, 0.0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += (uint64_t)sample_count * steps_per_sample;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	std::vector<uint64_t> jump_histogram(jump_count, 0);
	uint64_t dp_distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	std::string reason;
	if (!ValidateDynamicDpStreamOutputs(p, jumps, jump_distances, steps_per_sample, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, &jump_histogram, &dp_distance_checksum, &dp_checksum, &dp_count, reason))
	{
		return MetalJacobianDynamicDpStreamBenchJson("jacobian_affine_walk_dynamic_dp_stream", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, emitted_records, dp_capacity, dp_stream_overflow, 0, dp_bits, 0, 0, min_ms, dispatch_stats, seconds, 0.0, false, false, reason);
	}

	double ops_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	uint64_t jump_histogram_min_bucket = JumpHistogramMinBucket(jump_histogram);
	uint64_t jump_histogram_max_bucket = JumpHistogramMaxBucket(jump_histogram);
	uint64_t jump_histogram_max_deviation_ppm = JumpHistogramMaxDeviationPpm(jump_histogram);
	return MetalJacobianDynamicDpStreamBenchJson("jacobian_affine_walk_dynamic_dp_stream", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_histogram_min_bucket, jump_histogram_max_bucket, jump_histogram_max_deviation_ppm, emitted_records, dp_capacity, dp_stream_overflow, dp_distance_checksum, dp_bits, dp_count, dp_checksum, min_ms, dispatch_stats, seconds, ops_per_sec, true, false, "");
}

std::string RCKMetalJacobianDynamicDpStreamInplaceBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit, unsigned int dp_bits)
{
	if (iterations == 0)
		iterations = 1;
	if (steps_per_sample == 0)
		steps_per_sample = 8;
	if (dp_bits == 0)
		dp_bits = 8;
	jump_count = NormalizeMetalJumpCount(jump_count);
	dp_bits = NormalizeMetalDpBits(dp_bits);
	const char* jump_index_mode = MetalJumpIndexMode(jump_count);
	const unsigned int sample_count = iterations;
	const unsigned int dp_capacity = sample_count;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveDynamicDpStreamInplaceThreadgroupLimit(threadgroup_limit, dp_bits, steps_per_sample);
	if ((steps_per_sample != 8 && steps_per_sample != 16 && steps_per_sample != 32 && steps_per_sample != 64 && steps_per_sample != 128 && steps_per_sample != 256) || dp_bits != 8 || !IsMetalPowerOfTwo(jump_count))
	{
		std::string reason = "in-place stream dynamic dp supports steps=8, steps=16, steps=32, steps=64, steps=128, or steps=256, power-of-two jumps, dp_bits=8";
		return MetalJacobianDynamicDpStreamBenchJson("jacobian_affine_walk_dynamic_dp_stream_inplace", (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, false, false, reason);
	}

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
	BuildJacobianJumpDistances(jump_count, jump_distances);
	if (!CanAccumulateDistanceU32(jump_distances, steps_per_sample))
	{
		std::string reason = "in-place dynamic dp stream packet distance exceeds uint32 accumulator";
		return MetalJacobianDynamicDpStreamBenchJson("jacobian_affine_walk_dynamic_dp_stream_inplace", (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, false, false, reason);
	}

	std::vector<CpuJacobianPoint> state_out;
	std::vector<uint32_t> out_indices;
	std::vector<uint64_t> out_distances;
	std::vector<uint64_t> out_dp_terms;
	uint32_t emitted_records = 0;
	bool dp_stream_overflow = false;
	std::string error;
	double seconds = 0.0;
	uint64_t operations = 0;
	unsigned int dispatch_count = 0;
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunJacobianDynamicDpStreamInplaceKernel(p, jumps, jump_distances, steps_per_sample, state_out, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalJacobianDynamicDpStreamBenchJson("jacobian_affine_walk_dynamic_dp_stream_inplace", 0, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, false, true, error);
			return MetalJacobianDynamicDpStreamBenchJson("jacobian_affine_walk_dynamic_dp_stream_inplace", operations ? operations : (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, seconds, 0.0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += (uint64_t)sample_count * steps_per_sample;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	std::vector<uint64_t> jump_histogram(jump_count, 0);
	uint64_t dp_distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	std::string reason;
	if (!ValidateDynamicDpStreamOutputs(p, jumps, jump_distances, steps_per_sample, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, &jump_histogram, &dp_distance_checksum, &dp_checksum, &dp_count, reason))
	{
		return MetalJacobianDynamicDpStreamBenchJson("jacobian_affine_walk_dynamic_dp_stream_inplace", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, emitted_records, dp_capacity, dp_stream_overflow, 0, dp_bits, 0, 0, min_ms, dispatch_stats, seconds, 0.0, false, false, reason);
	}
	if (!ValidateDynamicStateOutputs(p, jumps, jump_distances, steps_per_sample, state_out, reason))
	{
		return MetalJacobianDynamicDpStreamBenchJson("jacobian_affine_walk_dynamic_dp_stream_inplace", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, emitted_records, dp_capacity, dp_stream_overflow, dp_distance_checksum, dp_bits, dp_count, dp_checksum, min_ms, dispatch_stats, seconds, 0.0, false, false, reason);
	}

	double ops_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	uint64_t jump_histogram_min_bucket = JumpHistogramMinBucket(jump_histogram);
	uint64_t jump_histogram_max_bucket = JumpHistogramMaxBucket(jump_histogram);
	uint64_t jump_histogram_max_deviation_ppm = JumpHistogramMaxDeviationPpm(jump_histogram);
	return MetalJacobianDynamicDpStreamBenchJson("jacobian_affine_walk_dynamic_dp_stream_inplace", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_histogram_min_bucket, jump_histogram_max_bucket, jump_histogram_max_deviation_ppm, emitted_records, dp_capacity, dp_stream_overflow, dp_distance_checksum, dp_bits, dp_count, dp_checksum, min_ms, dispatch_stats, seconds, ops_per_sec, true, false, "");
}

std::string RCKMetalJacobianDynamicDpStreamXyzzBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit, unsigned int dp_bits, const char* jump_schedule)
{
	if (iterations == 0)
		iterations = 1;
	if (steps_per_sample == 0)
		steps_per_sample = 256;
	if (dp_bits == 0)
		dp_bits = 8;
	jump_count = NormalizeMetalJumpCount(jump_count);
	dp_bits = NormalizeMetalDpBits(dp_bits);
	const char* jump_index_mode = MetalJumpIndexMode(jump_count);
	const char* jump_schedule_name = NormalizeMetalJumpScheduleName(jump_schedule);
	const unsigned int sample_count = iterations;
	const unsigned int dp_capacity = sample_count;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveDynamicDpStreamInplaceThreadgroupLimit(threadgroup_limit, dp_bits, steps_per_sample);
	if ((steps_per_sample != 256 && steps_per_sample != 512) || !IsMetalPowerOfTwo(jump_count))
	{
		std::string reason = "XYZZ dynamic dp stream supports steps=256 or steps=512, power-of-two jumps, and dp_bits<=32";
		return MetalJacobianDynamicDpStreamXyzzBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz", (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, false, false, reason);
	}
	std::string schedule_reason;
	if (!ValidateMetalJumpSchedule(jump_schedule, jump_count, schedule_reason))
	{
		return MetalJacobianDynamicDpStreamXyzzBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz", (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, false, false, schedule_reason);
	}

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpDistancesForSchedule(jump_count, jump_schedule, jump_distances);
	BuildJacobianJumpWalkSamplesForSchedule(sample_count, jump_count, jump_schedule, jump_distances, p, jumps);
	if (!CanAccumulateDistanceU32(jump_distances, steps_per_sample))
	{
		std::string reason = "XYZZ dynamic dp stream packet distance exceeds uint32 accumulator";
		return MetalJacobianDynamicDpStreamXyzzBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz", (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, false, false, reason);
	}

	std::vector<CpuXyzzPoint> state_out;
	std::vector<uint32_t> out_indices;
	std::vector<uint64_t> out_distances;
	std::vector<uint64_t> out_dp_terms;
	uint32_t emitted_records = 0;
	bool dp_stream_overflow = false;
	std::string error;
	double seconds = 0.0;
	uint64_t operations = 0;
	unsigned int dispatch_count = 0;
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunJacobianDynamicDpStreamXyzzKernel(p, jumps, jump_distances, steps_per_sample, state_out, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalJacobianDynamicDpStreamXyzzBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz", 0, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, false, true, error);
			return MetalJacobianDynamicDpStreamXyzzBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz", operations ? operations : (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, seconds, 0.0, 0.0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += (uint64_t)sample_count * steps_per_sample;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	std::vector<uint64_t> jump_histogram(jump_count, 0);
	uint64_t dp_distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	std::string reason;
	auto validation_start = std::chrono::steady_clock::now();
	if (!ValidateDynamicXyzzDpStreamAndStateOutputs(p, jumps, jump_distances, steps_per_sample, state_out, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, &jump_histogram, &dp_distance_checksum, &dp_checksum, &dp_count, reason))
	{
		double validation_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - validation_start).count();
		return MetalJacobianDynamicDpStreamXyzzBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, emitted_records, dp_capacity, dp_stream_overflow, dp_distance_checksum, dp_bits, dp_count, dp_checksum, min_ms, dispatch_stats, seconds, validation_seconds, 0.0, false, false, reason);
	}
	double validation_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - validation_start).count();

	double ops_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	uint64_t jump_histogram_min_bucket = JumpHistogramMinBucket(jump_histogram);
	uint64_t jump_histogram_max_bucket = JumpHistogramMaxBucket(jump_histogram);
	uint64_t jump_histogram_max_deviation_ppm = JumpHistogramMaxDeviationPpm(jump_histogram);
	return MetalJacobianDynamicDpStreamXyzzBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, jump_histogram_min_bucket, jump_histogram_max_bucket, jump_histogram_max_deviation_ppm, emitted_records, dp_capacity, dp_stream_overflow, dp_distance_checksum, dp_bits, dp_count, dp_checksum, min_ms, dispatch_stats, seconds, validation_seconds, ops_per_sec, true, false, "");
}

std::string RCKMetalJacobianDynamicDpStreamXyzzChainBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int packet_count, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit, unsigned int dp_bits, const char* jump_schedule)
{
	if (iterations == 0)
		iterations = 1;
	if (steps_per_sample == 0)
		steps_per_sample = 256;
	if (packet_count == 0)
		packet_count = 1;
	if (dp_bits == 0)
		dp_bits = 8;
	jump_count = NormalizeMetalJumpCount(jump_count);
	dp_bits = NormalizeMetalDpBits(dp_bits);
	const char* jump_index_mode = MetalJumpIndexMode(jump_count);
	const char* jump_schedule_name = NormalizeMetalJumpScheduleName(jump_schedule);
	const unsigned int sample_count = iterations;
	uint64_t dp_capacity64 = (uint64_t)sample_count * packet_count;
	unsigned int dp_capacity = dp_capacity64 <= 0xFFFFFFFFULL ? (unsigned int)dp_capacity64 : 0U;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveDynamicDpStreamInplaceThreadgroupLimit(threadgroup_limit, dp_bits, steps_per_sample);
	uint64_t requested_operations = (uint64_t)sample_count * steps_per_sample * packet_count;
	if ((steps_per_sample != 256 && steps_per_sample != 512) || !IsMetalPowerOfTwo(jump_count) || dp_capacity64 > 0xFFFFFFFFULL)
	{
		std::string reason = "XYZZ dynamic dp stream chain supports steps=256 or steps=512, power-of-two jumps, dp_bits<=32, and sample_count*packet_count <= uint32";
		return MetalJacobianDynamicDpStreamXyzzChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_chain", requested_operations, sample_count, steps_per_sample, packet_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, false, false, reason);
	}
	std::string schedule_reason;
	if (!ValidateMetalJumpSchedule(jump_schedule, jump_count, schedule_reason))
	{
		return MetalJacobianDynamicDpStreamXyzzChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_chain", requested_operations, sample_count, steps_per_sample, packet_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, false, false, schedule_reason);
	}

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpDistancesForSchedule(jump_count, jump_schedule, jump_distances);
	BuildJacobianJumpWalkSamplesForSchedule(sample_count, jump_count, jump_schedule, jump_distances, p, jumps);
	if (!CanAccumulateDistanceU32(jump_distances, steps_per_sample))
	{
		std::string reason = "XYZZ dynamic dp stream packet distance exceeds uint32 accumulator";
		return MetalJacobianDynamicDpStreamXyzzChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_chain", requested_operations, sample_count, steps_per_sample, packet_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, false, false, reason);
	}

	std::vector<CpuXyzzPoint> state_out;
	std::vector<uint32_t> out_indices;
	std::vector<uint64_t> out_distances;
	std::vector<uint64_t> out_dp_terms;
	uint32_t emitted_records = 0;
	bool dp_stream_overflow = false;
	std::string error;
	double seconds = 0.0;
	uint64_t operations = 0;
	unsigned int dispatch_count = 0;
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunJacobianDynamicDpStreamXyzzChainKernel(p, jumps, jump_distances, steps_per_sample, packet_count, state_out, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalJacobianDynamicDpStreamXyzzChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_chain", 0, sample_count, steps_per_sample, packet_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, false, true, error);
			return MetalJacobianDynamicDpStreamXyzzChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_chain", operations ? operations : requested_operations, sample_count, steps_per_sample, packet_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, seconds, 0.0, 0.0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += requested_operations;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	std::vector<uint64_t> jump_histogram(jump_count, 0);
	uint64_t dp_distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	std::string reason;
	auto validation_start = std::chrono::steady_clock::now();
	if (!ValidateDynamicXyzzChainDpStreamAndStateOutputs(p, jumps, jump_distances, steps_per_sample, packet_count, state_out, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, &jump_histogram, &dp_distance_checksum, &dp_checksum, &dp_count, reason))
	{
		double validation_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - validation_start).count();
		return MetalJacobianDynamicDpStreamXyzzChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_chain", operations, sample_count, steps_per_sample, packet_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, emitted_records, dp_capacity, dp_stream_overflow, dp_distance_checksum, dp_bits, dp_count, dp_checksum, min_ms, dispatch_stats, seconds, validation_seconds, 0.0, false, false, reason);
	}
	double validation_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - validation_start).count();

	double ops_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	uint64_t jump_histogram_min_bucket = JumpHistogramMinBucket(jump_histogram);
	uint64_t jump_histogram_max_bucket = JumpHistogramMaxBucket(jump_histogram);
	uint64_t jump_histogram_max_deviation_ppm = JumpHistogramMaxDeviationPpm(jump_histogram);
	return MetalJacobianDynamicDpStreamXyzzChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_chain", operations, sample_count, steps_per_sample, packet_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, jump_histogram_min_bucket, jump_histogram_max_bucket, jump_histogram_max_deviation_ppm, emitted_records, dp_capacity, dp_stream_overflow, dp_distance_checksum, dp_bits, dp_count, dp_checksum, min_ms, dispatch_stats, seconds, validation_seconds, ops_per_sec, true, false, "");
}

std::string RCKMetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int packet_count, unsigned int round_count, unsigned int jump_count, unsigned int threadgroup_limit, unsigned int dp_bits, const char* jump_schedule)
{
	if (iterations == 0)
		iterations = 1;
	if (steps_per_sample == 0)
		steps_per_sample = 256;
	if (packet_count == 0)
		packet_count = 2;
	if (round_count == 0)
		round_count = 2;
	if (dp_bits == 0)
		dp_bits = 8;
	jump_count = NormalizeMetalJumpCount(jump_count);
	dp_bits = NormalizeMetalDpBits(dp_bits);
	const char* jump_index_mode = MetalJumpIndexMode(jump_count);
	const char* jump_schedule_name = NormalizeMetalJumpScheduleName(jump_schedule);
	const unsigned int sample_count = iterations;
	uint64_t total_packet_count64 = (uint64_t)packet_count * round_count;
	uint64_t dp_capacity64 = (uint64_t)sample_count * total_packet_count64;
	unsigned int total_packet_count = total_packet_count64 <= 0xFFFFFFFFULL ? (unsigned int)total_packet_count64 : 0U;
	unsigned int dp_capacity = dp_capacity64 <= 0xFFFFFFFFULL ? (unsigned int)dp_capacity64 : 0U;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveDynamicDpStreamInplaceThreadgroupLimit(threadgroup_limit, dp_bits, steps_per_sample);
	uint64_t requested_operations = (uint64_t)sample_count * steps_per_sample * total_packet_count64;
	if ((steps_per_sample != 256 && steps_per_sample != 512) || !IsMetalPowerOfTwo(jump_count) || total_packet_count64 > 0xFFFFFFFFULL || dp_capacity64 > 0xFFFFFFFFULL)
	{
		std::string reason = "XYZZ persistent chain supports steps=256 or steps=512, power-of-two jumps, dp_bits<=32, packets*rounds <= uint32, and sample_count*packets*rounds <= uint32";
		return MetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain", requested_operations, sample_count, steps_per_sample, total_packet_count, packet_count, round_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, dispatch_stats, 0.0, 0.0, 0.0, false, false, reason);
	}
	std::string schedule_reason;
	if (!ValidateMetalJumpSchedule(jump_schedule, jump_count, schedule_reason))
	{
		return MetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain", requested_operations, sample_count, steps_per_sample, total_packet_count, packet_count, round_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, dispatch_stats, 0.0, 0.0, 0.0, false, false, schedule_reason);
	}

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpDistancesForSchedule(jump_count, jump_schedule, jump_distances);
	BuildJacobianJumpWalkSamplesForSchedule(sample_count, jump_count, jump_schedule, jump_distances, p, jumps);
	if (!CanAccumulateDistanceU32(jump_distances, steps_per_sample))
	{
		std::string reason = "XYZZ dynamic dp stream packet distance exceeds uint32 accumulator";
		return MetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain", requested_operations, sample_count, steps_per_sample, total_packet_count, packet_count, round_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, dispatch_stats, 0.0, 0.0, 0.0, false, false, reason);
	}

	std::vector<CpuXyzzPoint> state_out;
	std::vector<uint32_t> out_indices;
	std::vector<uint64_t> out_distances;
	std::vector<uint64_t> out_dp_terms;
	uint32_t emitted_records = 0;
	bool dp_stream_overflow = false;
	std::string error;
	double seconds = 0.0;
	if (!RunJacobianDynamicDpStreamXyzzPersistentChainKernel(p, jumps, jump_distances, steps_per_sample, packet_count, round_count, state_out, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, error, &seconds, threadgroup_limit, &dispatch_stats))
	{
		if (error == "no Metal device available")
			return MetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain", 0, sample_count, steps_per_sample, total_packet_count, packet_count, round_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, dispatch_stats, 0.0, 0.0, 0.0, false, true, error);
		return MetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain", requested_operations, sample_count, steps_per_sample, total_packet_count, packet_count, round_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, dispatch_stats, seconds, 0.0, 0.0, false, false, error);
	}

	std::vector<uint64_t> jump_histogram(jump_count, 0);
	uint64_t dp_distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	std::string reason;
	auto validation_start = std::chrono::steady_clock::now();
	if (!ValidateDynamicXyzzChainDpStreamAndStateOutputs(p, jumps, jump_distances, steps_per_sample, total_packet_count, state_out, out_indices, out_distances, out_dp_terms, emitted_records, dp_stream_overflow, dp_bits, &jump_histogram, &dp_distance_checksum, &dp_checksum, &dp_count, reason))
	{
		double validation_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - validation_start).count();
		return MetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain", requested_operations, sample_count, steps_per_sample, total_packet_count, packet_count, round_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, emitted_records, dp_capacity, dp_stream_overflow, dp_distance_checksum, dp_bits, dp_count, dp_checksum, dispatch_stats, seconds, validation_seconds, 0.0, false, false, reason);
	}
	double validation_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - validation_start).count();

	double ops_per_sec = seconds > 0.0 ? (double)requested_operations / seconds : 0.0;
	uint64_t jump_histogram_min_bucket = JumpHistogramMinBucket(jump_histogram);
	uint64_t jump_histogram_max_bucket = JumpHistogramMaxBucket(jump_histogram);
	uint64_t jump_histogram_max_deviation_ppm = JumpHistogramMaxDeviationPpm(jump_histogram);
	return MetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_persistent_chain", requested_operations, sample_count, steps_per_sample, total_packet_count, packet_count, round_count, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, jump_histogram_min_bucket, jump_histogram_max_bucket, jump_histogram_max_deviation_ppm, emitted_records, dp_capacity, dp_stream_overflow, dp_distance_checksum, dp_bits, dp_count, dp_checksum, dispatch_stats, seconds, validation_seconds, ops_per_sec, true, false, "");
}

std::string RCKMetalJacobianDynamicDpStreamXyzzAffineScanBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit, unsigned int dp_bits, const char* jump_schedule)
{
	if (iterations == 0)
		iterations = 1;
	if (steps_per_sample == 0)
		steps_per_sample = 256;
	if (dp_bits == 0)
		dp_bits = 8;
	jump_count = NormalizeMetalJumpCount(jump_count);
	dp_bits = NormalizeMetalDpBits(dp_bits);
	const char* jump_index_mode = MetalJumpIndexMode(jump_count);
	const char* jump_schedule_name = NormalizeMetalJumpScheduleName(jump_schedule);
	const unsigned int sample_count = iterations;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveDynamicDpStreamInplaceThreadgroupLimit(threadgroup_limit, dp_bits, steps_per_sample);
	uint64_t requested_operations = (uint64_t)sample_count * steps_per_sample;
	if ((steps_per_sample != 256 && steps_per_sample != 512) || !IsMetalPowerOfTwo(jump_count))
	{
		std::string reason = "XYZZ affine scan supports steps=256 or steps=512, power-of-two jumps, and dp_bits<=32";
		return MetalJacobianDynamicDpStreamXyzzAffineScanBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_affine_scan", requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, reason);
	}
	std::string schedule_reason;
	if (!ValidateMetalJumpSchedule(jump_schedule, jump_count, schedule_reason))
	{
		return MetalJacobianDynamicDpStreamXyzzAffineScanBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_affine_scan", requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, schedule_reason);
	}

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpDistancesForSchedule(jump_count, jump_schedule, jump_distances);
	BuildJacobianJumpWalkSamplesForSchedule(sample_count, jump_count, jump_schedule, jump_distances, p, jumps);
	if (!CanAccumulateDistanceU32(jump_distances, steps_per_sample))
	{
		std::string reason = "XYZZ dynamic distance packet exceeds uint32 accumulator";
		return MetalJacobianDynamicDpStreamXyzzAffineScanBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_affine_scan", requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, reason);
	}

	std::vector<CpuXyzzPoint> state_out;
	std::vector<uint64_t> distances_out;
	std::string error;
	double seconds = 0.0;
	double affine_scan_seconds = 0.0;
	uint64_t operations = 0;
	uint64_t dp_distance_checksum = 0;
	uint64_t dp_checksum = 0;
	unsigned int dp_count = 0;
	unsigned int dispatch_count = 0;
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunJacobianDynamicXyzzDistanceKernel(p, jumps, jump_distances, steps_per_sample, state_out, distances_out, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalJacobianDynamicDpStreamXyzzAffineScanBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_affine_scan", 0, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, false, true, error);
			return MetalJacobianDynamicDpStreamXyzzAffineScanBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_affine_scan", operations ? operations : requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, min_ms, dispatch_stats, seconds, affine_scan_seconds, 0.0, 0.0, 0.0, false, false, error);
		}
		seconds += dispatch_seconds;
		auto scan_start = std::chrono::steady_clock::now();
		std::string scan_reason;
		if (!CpuXyzzBatchAffineDpScan(state_out, distances_out, dp_bits, &dp_distance_checksum, &dp_checksum, &dp_count, scan_reason))
		{
			affine_scan_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - scan_start).count();
			return MetalJacobianDynamicDpStreamXyzzAffineScanBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_affine_scan", operations ? operations : requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, dp_distance_checksum, dp_bits, dp_count, dp_checksum, min_ms, dispatch_stats, seconds, affine_scan_seconds, 0.0, 0.0, 0.0, false, false, scan_reason);
		}
		affine_scan_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - scan_start).count();
		operations += requested_operations;
		dispatch_count++;
		if (min_ms && (seconds + affine_scan_seconds) == 0.0)
			break;
	} while (min_ms && (((seconds + affine_scan_seconds) * 1000.0) < (double)min_ms) && (dispatch_count < 100000));

	std::vector<uint64_t> jump_histogram(jump_count, 0);
	std::string reason;
	auto validation_start = std::chrono::steady_clock::now();
	if (!ValidateDynamicXyzzStateDistanceOutputs(p, jumps, jump_distances, steps_per_sample, state_out, distances_out, &jump_histogram, reason))
	{
		double validation_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - validation_start).count();
		return MetalJacobianDynamicDpStreamXyzzAffineScanBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_affine_scan", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, dp_distance_checksum, dp_bits, dp_count, dp_checksum, min_ms, dispatch_stats, seconds, affine_scan_seconds, validation_seconds, 0.0, 0.0, false, false, reason);
	}
	double validation_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - validation_start).count();

	double total_seconds = seconds + affine_scan_seconds;
	double ops_per_sec = total_seconds > 0.0 ? (double)operations / total_seconds : 0.0;
	double gpu_ops_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	uint64_t jump_histogram_min_bucket = JumpHistogramMinBucket(jump_histogram);
	uint64_t jump_histogram_max_bucket = JumpHistogramMaxBucket(jump_histogram);
	uint64_t jump_histogram_max_deviation_ppm = JumpHistogramMaxDeviationPpm(jump_histogram);
	return MetalJacobianDynamicDpStreamXyzzAffineScanBenchJson("jacobian_affine_walk_dynamic_dp_stream_xyzz_affine_scan", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, jump_histogram_min_bucket, jump_histogram_max_bucket, jump_histogram_max_deviation_ppm, dp_distance_checksum, dp_bits, dp_count, dp_checksum, min_ms, dispatch_stats, seconds, affine_scan_seconds, validation_seconds, ops_per_sec, gpu_ops_per_sec, true, false, "");
}

std::string RCKMetalJacobianDynamicDpStreamXyzzAffineScanTargetLookupTag32BenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int target_count, unsigned int requested_hits, unsigned int lookup_repeat, unsigned int threadgroup_limit, unsigned int dp_bits, const char* jump_schedule, const char* lookup_query_mode, const char* lookup_engine, unsigned int lookup_threadgroup_limit)
{
	if (iterations == 0)
		iterations = 1;
	if (steps_per_sample == 0)
		steps_per_sample = 256;
	if (dp_bits == 0)
		dp_bits = 8;
	if (lookup_repeat == 0)
		lookup_repeat = 1;
	jump_count = NormalizeMetalJumpCount(jump_count);
	dp_bits = NormalizeMetalDpBits(dp_bits);
	const char* jump_index_mode = MetalJumpIndexMode(jump_count);
	const char* jump_schedule_name = NormalizeMetalJumpScheduleName(jump_schedule);
	const char* lookup_query_mode_name = NormalizeAffineLookupQueryModeName(lookup_query_mode);
	const char* lookup_engine_name = NormalizeAffineLookupEngineName(lookup_engine);
	const unsigned int sample_count = iterations;

	MetalDispatchStats walk_stats;
	walk_stats.threadgroup_limit = (unsigned int)EffectiveDynamicDpStreamInplaceThreadgroupLimit(threadgroup_limit, dp_bits, steps_per_sample);
	unsigned int effective_lookup_threadgroup_limit = lookup_threadgroup_limit ? lookup_threadgroup_limit : threadgroup_limit;
	MetalDispatchStats lookup_stats;
	lookup_stats.threadgroup_limit = (unsigned int)EffectiveTargetLookupThreadgroupLimit(effective_lookup_threadgroup_limit);
	uint64_t requested_operations = (uint64_t)sample_count * steps_per_sample;
	if ((steps_per_sample != 256 && steps_per_sample != 512) || !IsMetalPowerOfTwo(jump_count))
	{
		std::string reason = "affine scan target lookup supports steps=256 or steps=512, power-of-two jumps, and dp_bits<=32";
		return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, target_count, requested_hits, 0, 0, 0, 0, 0, 0, min_ms, walk_stats, lookup_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, reason, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
	}
	if (target_count == 0 || target_count > 32000000U)
	{
		std::string reason = "affine scan target lookup target_count limit is 1..32000000 for host memory safety";
		return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, target_count, requested_hits, 0, 0, 0, 0, 0, 0, min_ms, walk_stats, lookup_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, reason, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
	}
	if (lookup_repeat > 1000000U)
	{
		std::string reason = "affine scan target lookup lookup_repeat limit is 1..1000000 for host memory safety";
		return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, target_count, requested_hits, 0, 0, 0, 0, 0, 0, min_ms, walk_stats, lookup_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, reason, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
	}
	std::string query_mode_reason;
	if (!ValidateAffineLookupQueryMode(lookup_query_mode, query_mode_reason))
	{
		return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, target_count, requested_hits, 0, 0, 0, 0, 0, 0, min_ms, walk_stats, lookup_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, query_mode_reason, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
	}
	std::string lookup_engine_reason;
	if (!ValidateAffineLookupEngine(lookup_engine, lookup_engine_reason))
	{
		return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, target_count, requested_hits, 0, 0, 0, 0, 0, 0, min_ms, walk_stats, lookup_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, lookup_engine_reason, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
	}
	std::string schedule_reason;
	if (!ValidateMetalJumpSchedule(jump_schedule, jump_count, schedule_reason))
	{
		return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, target_count, requested_hits, 0, 0, 0, 0, 0, 0, min_ms, walk_stats, lookup_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, schedule_reason, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
	}

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpDistancesForSchedule(jump_count, jump_schedule, jump_distances);
	BuildJacobianJumpWalkSamplesForSchedule(sample_count, jump_count, jump_schedule, jump_distances, p, jumps);
	if (!CanAccumulateDistanceU32(jump_distances, steps_per_sample))
	{
		std::string reason = "XYZZ dynamic distance packet exceeds uint32 accumulator";
		return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, target_count, requested_hits, 0, 0, 0, 0, 0, 0, min_ms, walk_stats, lookup_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, reason, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
	}

	std::vector<CpuXyzzPoint> state_out;
	std::vector<uint64_t> distances_out;
	std::vector<TargetLookupKeyHost> target_keys;
	std::vector<TargetLookupTag32BucketHost> target_buckets;
	std::vector<uint32_t> target_filter_buckets;
	std::vector<uint32_t> expected_indices;
	std::string error;
	double walk_seconds = 0.0;
	double affine_scan_seconds = 0.0;
	double lookup_seconds = 0.0;
	uint64_t operations = 0;
	uint64_t lookup_operations = 0;
	uint64_t dp_distance_checksum = 0;
	uint64_t dp_checksum = 0;
	uint64_t target_lookup_checksum = 0;
	unsigned int dp_count = 0;
	unsigned int dp_query_count = 0;
	unsigned int injected_hits = 0;
	unsigned int hit_count = 0;
	unsigned int filter_positive_count = 0;
	unsigned int filter_false_positive_count = 0;
	unsigned int dispatch_count = 0;
	uint64_t target_key_bytes = 0;
	uint64_t target_bucket_bytes = 0;
	uint64_t target_filter_bucket_bytes = 0;
	bool target_table_ready = false;
	const char* effective_lookup_engine_name = lookup_engine_name;
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunJacobianDynamicXyzzDistanceKernel(p, jumps, jump_distances, steps_per_sample, state_out, distances_out, error, &dispatch_seconds, threadgroup_limit, &walk_stats))
		{
			if (error == "no Metal device available")
				return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", 0, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, target_count, requested_hits, 0, 0, 0, 0, 0, 0, min_ms, walk_stats, lookup_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, true, error, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
			return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", operations ? operations : requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, 0, dp_bits, 0, 0, target_count, requested_hits, injected_hits, dp_query_count, hit_count, target_buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, walk_stats, lookup_stats, walk_seconds, affine_scan_seconds, lookup_seconds, 0.0, 0.0, 0.0, 0.0, target_lookup_checksum, false, false, error, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
		}
		walk_seconds += dispatch_seconds;

		std::vector<TargetLookupKeyHost> dp_keys;
		std::vector<uint64_t> dp_distances;
		auto scan_start = std::chrono::steady_clock::now();
		std::string scan_reason;
		if (!CpuXyzzBatchAffineDpScan(state_out, distances_out, dp_bits, &dp_distance_checksum, &dp_checksum, &dp_count, scan_reason, &dp_keys, &dp_distances))
		{
			affine_scan_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - scan_start).count();
			return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", operations ? operations : requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, dp_distance_checksum, dp_bits, dp_count, dp_checksum, target_count, requested_hits, injected_hits, dp_query_count, hit_count, target_buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, walk_stats, lookup_stats, walk_seconds, affine_scan_seconds, lookup_seconds, 0.0, 0.0, 0.0, 0.0, target_lookup_checksum, false, false, scan_reason, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
		}
		affine_scan_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - scan_start).count();
		dp_query_count = (unsigned int)dp_keys.size();
		if (dp_keys.empty())
		{
			std::string reason = "affine scan produced no DP queries for target lookup";
			return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", operations ? operations : requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, dp_distance_checksum, dp_bits, dp_count, dp_checksum, target_count, requested_hits, injected_hits, dp_query_count, hit_count, target_buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, walk_stats, lookup_stats, walk_seconds, affine_scan_seconds, lookup_seconds, 0.0, 0.0, 0.0, 0.0, target_lookup_checksum, false, false, reason, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
		}

		if (!target_table_ready)
		{
			injected_hits = requested_hits;
			if (injected_hits > dp_query_count)
				injected_hits = dp_query_count;
			if (injected_hits > target_count)
				injected_hits = target_count;
			std::vector<TargetLookupKeyHost> injected_keys;
			injected_keys.reserve(injected_hits);
			for (unsigned int i = 0; i < injected_hits; ++i)
				injected_keys.push_back(dp_keys[i]);
			if (!BuildTargetLookupTag32TableFromKeys(injected_keys, target_count, target_keys, target_buckets, error))
				return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", operations ? operations : requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, dp_distance_checksum, dp_bits, dp_count, dp_checksum, target_count, requested_hits, injected_hits, dp_query_count, hit_count, target_buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, walk_stats, lookup_stats, walk_seconds, affine_scan_seconds, lookup_seconds, 0.0, 0.0, 0.0, 0.0, target_lookup_checksum, false, false, error, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
			target_key_bytes = target_keys.size() * sizeof(TargetLookupKeyHost);
			target_bucket_bytes = target_buckets.size() * sizeof(TargetLookupTag32BucketHost);
			expected_indices.assign(dp_query_count, kTargetLookupEmptyIndex);
			for (unsigned int i = 0; i < injected_hits; ++i)
				expected_indices[i] = i;
			target_table_ready = true;
		}
		if (expected_indices.size() != dp_keys.size())
		{
			std::string reason = "affine DP target lookup query count changed across dispatches";
			return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", operations ? operations : requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, dp_distance_checksum, dp_bits, dp_count, dp_checksum, target_count, requested_hits, injected_hits, dp_query_count, hit_count, target_buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, walk_stats, lookup_stats, walk_seconds, affine_scan_seconds, lookup_seconds, 0.0, 0.0, 0.0, 0.0, target_lookup_checksum, false, false, reason, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
		}
		uint64_t repeated_query_count = (uint64_t)dp_keys.size() * (uint64_t)lookup_repeat;
		if (repeated_query_count > 32000000ULL)
		{
			std::string reason = "affine DP target lookup repeated query count limit is 32000000 for host memory safety";
			return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", operations ? operations : requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, dp_distance_checksum, dp_bits, dp_count, dp_checksum, target_count, requested_hits, injected_hits, dp_query_count, hit_count, target_buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, walk_stats, lookup_stats, walk_seconds, affine_scan_seconds, lookup_seconds, 0.0, 0.0, 0.0, 0.0, target_lookup_checksum, false, false, reason, lookup_repeat, lookup_query_mode_name, lookup_engine_name);
		}
		std::vector<TargetLookupKeyHost> lookup_queries;
		std::vector<uint32_t> lookup_expected_indices;
		lookup_queries.reserve((size_t)repeated_query_count);
		lookup_expected_indices.reserve((size_t)repeated_query_count);
		unsigned int expected_lookup_hits = 0;
		if (strcmp(lookup_query_mode_name, "distinct_misses") == 0)
		{
			lookup_queries.insert(lookup_queries.end(), dp_keys.begin(), dp_keys.end());
			lookup_expected_indices.insert(lookup_expected_indices.end(), expected_indices.begin(), expected_indices.end());
			expected_lookup_hits = injected_hits;

			uint64_t miss_nonce = 0;
			uint32_t ignored = 0;
			while (lookup_queries.size() < (size_t)repeated_query_count)
			{
				TargetLookupKeyHost miss_key = DeterministicTargetLookupKey(miss_nonce++, 0xD1571A57BEEFULL);
				while (TargetLookupTag32Find(target_keys, target_buckets, miss_key, &ignored))
					miss_key = DeterministicTargetLookupKey(miss_nonce++, 0xBADC0FFEE0DDF00DULL);
				lookup_queries.push_back(miss_key);
				lookup_expected_indices.push_back(kTargetLookupEmptyIndex);
			}
		}
		else
		{
			for (unsigned int repeat = 0; repeat < lookup_repeat; ++repeat)
			{
				lookup_queries.insert(lookup_queries.end(), dp_keys.begin(), dp_keys.end());
				lookup_expected_indices.insert(lookup_expected_indices.end(), expected_indices.begin(), expected_indices.end());
			}
			expected_lookup_hits = injected_hits * lookup_repeat;
		}

		effective_lookup_engine_name = ChooseAffineLookupEngine(lookup_engine_name, target_count, lookup_queries.size());
		effective_lookup_threadgroup_limit = ChooseAffineLookupThreadgroupLimit(lookup_engine_name, effective_lookup_engine_name, target_count, lookup_queries.size(), threadgroup_limit, lookup_threadgroup_limit);
		std::vector<uint32_t> out_indices;
		double lookup_dispatch_seconds = 0.0;
		bool lookup_ok = false;
		if (strcmp(effective_lookup_engine_name, "cpu") == 0)
		{
			lookup_stats.threadgroup_limit = 0;
			lookup_stats.thread_execution_width = 0;
			lookup_stats.max_threads_per_threadgroup = 0;
			lookup_stats.threads_per_threadgroup = 0;
			lookup_ok = RunTargetLookupTag32Cpu(target_buckets, target_keys, lookup_queries, out_indices, hit_count, error, &lookup_dispatch_seconds);
		}
		else if (strcmp(effective_lookup_engine_name, "gpu_filter") == 0)
		{
			if (target_filter_buckets.empty())
			{
				if (!BuildTargetLookupTag32FilterTable(target_keys, target_filter_buckets, error))
					return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", operations ? operations : requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, dp_distance_checksum, dp_bits, dp_count, dp_checksum, target_count, requested_hits, injected_hits, dp_query_count, hit_count, target_buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, walk_stats, lookup_stats, walk_seconds, affine_scan_seconds, lookup_seconds, 0.0, 0.0, 0.0, 0.0, target_lookup_checksum, false, false, error, lookup_repeat, lookup_query_mode_name, lookup_engine_name, effective_lookup_engine_name, filter_positive_count, filter_false_positive_count, target_filter_bucket_bytes);
				target_filter_bucket_bytes = target_filter_buckets.size() * sizeof(uint32_t);
			}
			std::vector<uint32_t> positive_query_indices;
			uint32_t local_filter_positive_count = 0;
			lookup_ok = RunTargetLookupTag32FilterKernel(target_filter_buckets, lookup_queries, positive_query_indices, local_filter_positive_count, error, &lookup_dispatch_seconds, effective_lookup_threadgroup_limit, &lookup_stats);
			if (lookup_ok)
			{
				uint32_t local_hit_count = 0;
				uint32_t local_false_positive_count = 0;
				std::string resolve_reason;
				auto exact_start = std::chrono::steady_clock::now();
				lookup_ok = ResolveTargetLookupTag32FilterCandidates(target_buckets, target_keys, lookup_queries, positive_query_indices, local_filter_positive_count, out_indices, local_hit_count, local_false_positive_count, resolve_reason, false);
				lookup_dispatch_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - exact_start).count();
				if (!lookup_ok)
					error = resolve_reason;
				else
				{
					filter_positive_count = local_filter_positive_count;
					filter_false_positive_count = local_false_positive_count;
					hit_count = local_hit_count;
					std::string fill_reason;
					if (!ResolveTargetLookupTag32FilterCandidates(target_buckets, target_keys, lookup_queries, positive_query_indices, local_filter_positive_count, out_indices, local_hit_count, local_false_positive_count, fill_reason, true))
					{
						lookup_ok = false;
						error = fill_reason;
					}
				}
			}
		}
		else
			lookup_ok = RunTargetLookupTag32Kernel(target_buckets, target_keys, lookup_queries, out_indices, hit_count, error, &lookup_dispatch_seconds, effective_lookup_threadgroup_limit, &lookup_stats);
		if (!lookup_ok)
		{
			if (error == "no Metal device available")
				return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", 0, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, dp_distance_checksum, dp_bits, dp_count, dp_checksum, target_count, requested_hits, injected_hits, dp_query_count, 0, target_buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, walk_stats, lookup_stats, walk_seconds, affine_scan_seconds, lookup_seconds, 0.0, 0.0, 0.0, 0.0, 0, false, true, error, lookup_repeat, lookup_query_mode_name, lookup_engine_name, effective_lookup_engine_name);
			return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", operations ? operations : requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, dp_distance_checksum, dp_bits, dp_count, dp_checksum, target_count, requested_hits, injected_hits, dp_query_count, hit_count, target_buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, walk_stats, lookup_stats, walk_seconds, affine_scan_seconds, lookup_seconds, 0.0, 0.0, 0.0, 0.0, target_lookup_checksum, false, false, error, lookup_repeat, lookup_query_mode_name, lookup_engine_name, effective_lookup_engine_name);
		}
		lookup_seconds += lookup_dispatch_seconds;
		lookup_operations += lookup_queries.size();

		std::string lookup_reason;
		if (!ValidateTargetLookupOutputs(out_indices, lookup_expected_indices, hit_count, expected_lookup_hits, &target_lookup_checksum, lookup_reason))
			return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", operations ? operations : requested_operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, dp_distance_checksum, dp_bits, dp_count, dp_checksum, target_count, requested_hits, injected_hits, dp_query_count, hit_count, target_buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, walk_stats, lookup_stats, walk_seconds, affine_scan_seconds, lookup_seconds, 0.0, 0.0, 0.0, 0.0, target_lookup_checksum, false, false, lookup_reason, lookup_repeat, lookup_query_mode_name, lookup_engine_name, effective_lookup_engine_name);

		operations += requested_operations;
		dispatch_count++;
		if (min_ms && (walk_seconds + affine_scan_seconds + lookup_seconds) == 0.0)
			break;
	} while (min_ms && (((walk_seconds + affine_scan_seconds + lookup_seconds) * 1000.0) < (double)min_ms) && (dispatch_count < 100000));

	std::vector<uint64_t> jump_histogram(jump_count, 0);
	std::string reason;
	auto validation_start = std::chrono::steady_clock::now();
	if (!ValidateDynamicXyzzStateDistanceOutputs(p, jumps, jump_distances, steps_per_sample, state_out, distances_out, &jump_histogram, reason))
	{
		double validation_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - validation_start).count();
		return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, 0, 0, 0, dp_distance_checksum, dp_bits, dp_count, dp_checksum, target_count, requested_hits, injected_hits, dp_query_count, hit_count, target_buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, walk_stats, lookup_stats, walk_seconds, affine_scan_seconds, lookup_seconds, validation_seconds, 0.0, 0.0, 0.0, target_lookup_checksum, false, false, reason, lookup_repeat, lookup_query_mode_name, lookup_engine_name, effective_lookup_engine_name);
	}
	double validation_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - validation_start).count();

	double total_seconds = walk_seconds + affine_scan_seconds + lookup_seconds;
	double ops_per_sec = total_seconds > 0.0 ? (double)operations / total_seconds : 0.0;
	double gpu_ops_per_sec = walk_seconds > 0.0 ? (double)operations / walk_seconds : 0.0;
	double lookups_per_sec = lookup_seconds > 0.0 ? (double)lookup_operations / lookup_seconds : 0.0;
	uint64_t jump_histogram_min_bucket = JumpHistogramMinBucket(jump_histogram);
	uint64_t jump_histogram_max_bucket = JumpHistogramMaxBucket(jump_histogram);
	uint64_t jump_histogram_max_deviation_ppm = JumpHistogramMaxDeviationPpm(jump_histogram);
	return MetalAffineScanTargetLookupTag32BenchJson("jacobian_affine_scan_target_lookup_tag32", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_schedule_name, jump_histogram_min_bucket, jump_histogram_max_bucket, jump_histogram_max_deviation_ppm, dp_distance_checksum, dp_bits, dp_count, dp_checksum, target_count, requested_hits, injected_hits, dp_query_count, hit_count, target_buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, walk_stats, lookup_stats, walk_seconds, affine_scan_seconds, lookup_seconds, validation_seconds, ops_per_sec, gpu_ops_per_sec, lookups_per_sec, target_lookup_checksum, true, false, "", lookup_repeat, lookup_query_mode_name, lookup_engine_name, effective_lookup_engine_name, filter_positive_count, filter_false_positive_count, target_filter_bucket_bytes);
}

std::string RCKMetalJacobianDynamicDpCountBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit, unsigned int dp_bits)
{
	if (iterations == 0)
		iterations = 1;
	if (steps_per_sample == 0)
		steps_per_sample = 8;
	if (dp_bits == 0)
		dp_bits = 4;
	jump_count = NormalizeMetalJumpCount(jump_count);
	dp_bits = NormalizeMetalDpBits(dp_bits);
	const char* jump_index_mode = MetalJumpIndexMode(jump_count);
	const unsigned int sample_count = iterations;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);
	if (steps_per_sample != 8 || dp_bits > 32 || !IsMetalPowerOfTwo(jump_count))
	{
		std::string reason = "count dynamic dp supports steps=8, power-of-two jumps, dp_bits=0..32";
		return MetalJacobianDynamicDpCountBenchJson("jacobian_affine_walk_dynamic_dp_count", (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, dp_bits, 0, min_ms, dispatch_stats, 0.0, 0.0, false, false, reason);
	}

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
	BuildJacobianJumpDistances(jump_count, jump_distances);

	uint32_t dp_count = 0;
	std::string error;
	double seconds = 0.0;
	uint64_t operations = 0;
	unsigned int dispatch_count = 0;
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunJacobianDynamicDpCountKernel(p, jumps, steps_per_sample, dp_count, dp_bits, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalJacobianDynamicDpCountBenchJson("jacobian_affine_walk_dynamic_dp_count", 0, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, dp_bits, 0, min_ms, dispatch_stats, 0.0, 0.0, false, true, error);
			return MetalJacobianDynamicDpCountBenchJson("jacobian_affine_walk_dynamic_dp_count", operations ? operations : (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, dp_bits, 0, min_ms, dispatch_stats, seconds, 0.0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += (uint64_t)sample_count * steps_per_sample;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	std::vector<uint64_t> jump_histogram(jump_count, 0);
	unsigned int expected_dp_count = 0;
	for (unsigned int i = 0; i < sample_count; ++i)
	{
		CpuJacobianPoint expected = CpuJacobianDynamicJumpWalk(p[i], jumps, jump_distances, steps_per_sample, NULL, &jump_histogram);
		expected_dp_count += ProjectiveDpFlag(expected, dp_bits) ? 1U : 0U;
	}
	if (dp_count != expected_dp_count)
	{
		std::string reason = "count dp mismatch: got " + std::to_string(dp_count) +
			" expected " + std::to_string(expected_dp_count);
		return MetalJacobianDynamicDpCountBenchJson("jacobian_affine_walk_dynamic_dp_count", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, dp_bits, dp_count, min_ms, dispatch_stats, seconds, 0.0, false, false, reason);
	}

	double ops_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	uint64_t jump_histogram_min_bucket = JumpHistogramMinBucket(jump_histogram);
	uint64_t jump_histogram_max_bucket = JumpHistogramMaxBucket(jump_histogram);
	uint64_t jump_histogram_max_deviation_ppm = JumpHistogramMaxDeviationPpm(jump_histogram);
	return MetalJacobianDynamicDpCountBenchJson("jacobian_affine_walk_dynamic_dp_count", operations, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, jump_histogram_min_bucket, jump_histogram_max_bucket, jump_histogram_max_deviation_ppm, dp_bits, dp_count, min_ms, dispatch_stats, seconds, ops_per_sec, true, false, "");
}

std::string RCKMetalTargetLookupBenchJson(unsigned int target_count, unsigned int query_count, unsigned int expected_hits, unsigned int min_ms, unsigned int threadgroup_limit)
{
	if (target_count == 0)
		target_count = 1;
	if (query_count == 0)
		query_count = 1;
	if (expected_hits > query_count)
		expected_hits = query_count;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);
	if (target_count > 32000000U)
	{
		std::string reason = "target lookup benchmark target_count limit is 32000000 for host memory safety";
		return MetalTargetLookupBenchJson("target_lookup_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0, false, false, reason);
	}

	std::vector<TargetLookupKeyHost> target_keys;
	std::vector<TargetLookupBucketHost> buckets;
	std::string error;
	if (!BuildTargetLookupExactTable(target_count, target_keys, buckets, error))
		return MetalTargetLookupBenchJson("target_lookup_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0, false, false, error);

	std::vector<TargetLookupKeyHost> queries;
	std::vector<uint32_t> expected_indices;
	BuildTargetLookupQueries(target_keys, buckets, query_count, expected_hits, queries, expected_indices);

	std::vector<uint32_t> out_indices;
	uint32_t hit_count = 0;
	double seconds = 0.0;
	uint64_t operations = 0;
	unsigned int dispatch_count = 0;
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunTargetLookupExactKernel(buckets, queries, out_indices, hit_count, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalTargetLookupBenchJson("target_lookup_exact256", 0, target_count, query_count, expected_hits, 0, buckets.size(), buckets.size() * sizeof(TargetLookupBucketHost), min_ms, dispatch_stats, 0.0, 0.0, 0, false, true, error);
			return MetalTargetLookupBenchJson("target_lookup_exact256", operations ? operations : query_count, target_count, query_count, expected_hits, 0, buckets.size(), buckets.size() * sizeof(TargetLookupBucketHost), min_ms, dispatch_stats, seconds, 0.0, 0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += query_count;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	uint64_t checksum = 0;
	std::string reason;
	if (!ValidateTargetLookupOutputs(out_indices, expected_indices, hit_count, expected_hits, &checksum, reason))
		return MetalTargetLookupBenchJson("target_lookup_exact256", operations, target_count, query_count, expected_hits, hit_count, buckets.size(), buckets.size() * sizeof(TargetLookupBucketHost), min_ms, dispatch_stats, seconds, 0.0, checksum, false, false, reason);

	double lookups_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	return MetalTargetLookupBenchJson("target_lookup_exact256", operations, target_count, query_count, expected_hits, hit_count, buckets.size(), buckets.size() * sizeof(TargetLookupBucketHost), min_ms, dispatch_stats, seconds, lookups_per_sec, checksum, true, false, "");
}

std::string RCKMetalTargetLookupCompactBenchJson(unsigned int target_count, unsigned int query_count, unsigned int expected_hits, unsigned int min_ms, unsigned int threadgroup_limit)
{
	if (target_count == 0)
		target_count = 1;
	if (query_count == 0)
		query_count = 1;
	if (expected_hits > query_count)
		expected_hits = query_count;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);
	if (target_count > 32000000U)
	{
		std::string reason = "target lookup benchmark target_count limit is 32000000 for host memory safety";
		return MetalTargetLookupCompactBenchJson("target_lookup_compact_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0, false, false, reason);
	}

	std::vector<TargetLookupKeyHost> target_keys;
	std::vector<TargetLookupCompactBucketHost> buckets;
	std::string error;
	if (!BuildTargetLookupCompactTable(target_count, target_keys, buckets, error))
		return MetalTargetLookupCompactBenchJson("target_lookup_compact_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0, false, false, error);

	std::vector<TargetLookupKeyHost> queries;
	std::vector<uint32_t> expected_indices;
	BuildTargetLookupCompactQueries(target_keys, buckets, query_count, expected_hits, queries, expected_indices);

	std::vector<uint32_t> out_indices;
	uint32_t hit_count = 0;
	double seconds = 0.0;
	uint64_t operations = 0;
	unsigned int dispatch_count = 0;
	uint64_t target_key_bytes = target_keys.size() * sizeof(TargetLookupKeyHost);
	uint64_t target_bucket_bytes = buckets.size() * sizeof(TargetLookupCompactBucketHost);
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunTargetLookupCompactKernel(buckets, target_keys, queries, out_indices, hit_count, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalTargetLookupCompactBenchJson("target_lookup_compact_exact256", 0, target_count, query_count, expected_hits, 0, buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, dispatch_stats, 0.0, 0.0, 0, false, true, error);
			return MetalTargetLookupCompactBenchJson("target_lookup_compact_exact256", operations ? operations : query_count, target_count, query_count, expected_hits, 0, buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, dispatch_stats, seconds, 0.0, 0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += query_count;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	uint64_t checksum = 0;
	std::string reason;
	if (!ValidateTargetLookupOutputs(out_indices, expected_indices, hit_count, expected_hits, &checksum, reason))
		return MetalTargetLookupCompactBenchJson("target_lookup_compact_exact256", operations, target_count, query_count, expected_hits, hit_count, buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, dispatch_stats, seconds, 0.0, checksum, false, false, reason);

	double lookups_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	return MetalTargetLookupCompactBenchJson("target_lookup_compact_exact256", operations, target_count, query_count, expected_hits, hit_count, buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, dispatch_stats, seconds, lookups_per_sec, checksum, true, false, "");
}

std::string RCKMetalTargetLookupTag32BenchJson(unsigned int target_count, unsigned int query_count, unsigned int expected_hits, unsigned int min_ms, unsigned int threadgroup_limit)
{
	if (target_count == 0)
		target_count = 1;
	if (query_count == 0)
		query_count = 1;
	if (expected_hits > query_count)
		expected_hits = query_count;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveTargetLookupThreadgroupLimit(threadgroup_limit);
	if (target_count > 32000000U)
	{
		std::string reason = "target lookup benchmark target_count limit is 32000000 for host memory safety";
		return MetalTargetLookupTag32BenchJson("target_lookup_tag32_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0, false, false, reason);
	}

	std::vector<TargetLookupKeyHost> target_keys;
	std::vector<TargetLookupTag32BucketHost> buckets;
	std::string error;
	if (!BuildTargetLookupTag32Table(target_count, target_keys, buckets, error))
		return MetalTargetLookupTag32BenchJson("target_lookup_tag32_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0, false, false, error);

	std::vector<TargetLookupKeyHost> queries;
	std::vector<uint32_t> expected_indices;
	BuildTargetLookupTag32Queries(target_keys, buckets, query_count, expected_hits, queries, expected_indices);

	std::vector<uint32_t> out_indices;
	uint32_t hit_count = 0;
	double seconds = 0.0;
	uint64_t operations = 0;
	unsigned int dispatch_count = 0;
	uint64_t target_key_bytes = target_keys.size() * sizeof(TargetLookupKeyHost);
	uint64_t target_bucket_bytes = buckets.size() * sizeof(TargetLookupTag32BucketHost);
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunTargetLookupTag32Kernel(buckets, target_keys, queries, out_indices, hit_count, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalTargetLookupTag32BenchJson("target_lookup_tag32_exact256", 0, target_count, query_count, expected_hits, 0, buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, dispatch_stats, 0.0, 0.0, 0, false, true, error);
			return MetalTargetLookupTag32BenchJson("target_lookup_tag32_exact256", operations ? operations : query_count, target_count, query_count, expected_hits, 0, buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, dispatch_stats, seconds, 0.0, 0, false, false, error);
		}
		seconds += dispatch_seconds;
		operations += query_count;
		dispatch_count++;
		if (min_ms && dispatch_seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	uint64_t checksum = 0;
	std::string reason;
	if (!ValidateTargetLookupOutputs(out_indices, expected_indices, hit_count, expected_hits, &checksum, reason))
		return MetalTargetLookupTag32BenchJson("target_lookup_tag32_exact256", operations, target_count, query_count, expected_hits, hit_count, buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, dispatch_stats, seconds, 0.0, checksum, false, false, reason);

	double lookups_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	return MetalTargetLookupTag32BenchJson("target_lookup_tag32_exact256", operations, target_count, query_count, expected_hits, hit_count, buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, dispatch_stats, seconds, lookups_per_sec, checksum, true, false, "");
}

std::string RCKMetalTargetLookupTag32FilterBenchJson(unsigned int target_count, unsigned int query_count, unsigned int expected_hits, unsigned int min_ms, unsigned int threadgroup_limit)
{
	if (target_count == 0)
		target_count = 1;
	if (query_count == 0)
		query_count = 1;
	if (expected_hits > query_count)
		expected_hits = query_count;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveTargetLookupThreadgroupLimit(threadgroup_limit);
	if (target_count > 32000000U)
	{
		std::string reason = "target lookup benchmark target_count limit is 32000000 for host memory safety";
		return MetalTargetLookupTag32FilterBenchJson("target_lookup_tag32_filter_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0, false, false, reason);
	}

	std::vector<TargetLookupKeyHost> target_keys;
	std::vector<TargetLookupTag32BucketHost> buckets;
	std::string error;
	if (!BuildTargetLookupTag32Table(target_count, target_keys, buckets, error))
		return MetalTargetLookupTag32FilterBenchJson("target_lookup_tag32_filter_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0, false, false, error);

	std::vector<uint32_t> filter_buckets;
	if (!BuildTargetLookupTag32FilterTable(target_keys, filter_buckets, error))
		return MetalTargetLookupTag32FilterBenchJson("target_lookup_tag32_filter_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, buckets.size(), target_keys.size() * sizeof(TargetLookupKeyHost), buckets.size() * sizeof(TargetLookupTag32BucketHost), 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0, false, false, error);

	std::vector<TargetLookupKeyHost> queries;
	std::vector<uint32_t> expected_indices;
	BuildTargetLookupTag32Queries(target_keys, buckets, query_count, expected_hits, queries, expected_indices);

	std::vector<uint32_t> positive_query_indices;
	std::vector<uint32_t> out_indices;
	uint32_t filter_positive_count = 0;
	uint32_t false_positive_count = 0;
	uint32_t hit_count = 0;
	double filter_seconds = 0.0;
	double exact_verify_seconds = 0.0;
	uint64_t operations = 0;
	unsigned int dispatch_count = 0;
	uint64_t target_key_bytes = target_keys.size() * sizeof(TargetLookupKeyHost);
	uint64_t target_bucket_bytes = buckets.size() * sizeof(TargetLookupTag32BucketHost);
	uint64_t target_filter_bucket_bytes = filter_buckets.size() * sizeof(uint32_t);
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunTargetLookupTag32FilterKernel(filter_buckets, queries, positive_query_indices, filter_positive_count, error, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
		{
			if (error == "no Metal device available")
				return MetalTargetLookupTag32FilterBenchJson("target_lookup_tag32_filter_exact256", 0, target_count, query_count, expected_hits, 0, filter_positive_count, 0, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0, false, true, error);
			return MetalTargetLookupTag32FilterBenchJson("target_lookup_tag32_filter_exact256", operations ? operations : query_count, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, filter_seconds, exact_verify_seconds, filter_seconds + exact_verify_seconds, 0.0, 0, false, false, error);
		}
		filter_seconds += dispatch_seconds;

		std::string resolve_reason;
		auto verify_start = std::chrono::steady_clock::now();
		if (!ResolveTargetLookupTag32FilterCandidates(buckets, target_keys, queries, positive_query_indices, filter_positive_count, out_indices, hit_count, false_positive_count, resolve_reason, false))
		{
			exact_verify_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - verify_start).count();
			return MetalTargetLookupTag32FilterBenchJson("target_lookup_tag32_filter_exact256", operations ? operations : query_count, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, filter_seconds, exact_verify_seconds, filter_seconds + exact_verify_seconds, 0.0, 0, false, false, resolve_reason);
		}
		exact_verify_seconds += std::chrono::duration<double>(std::chrono::steady_clock::now() - verify_start).count();

		operations += query_count;
		dispatch_count++;
		if (min_ms && (dispatch_seconds == 0.0))
			break;
	} while (min_ms && (((filter_seconds + exact_verify_seconds) * 1000.0) < (double)min_ms) && (dispatch_count < 100000));

	std::string resolve_reason;
	if (!ResolveTargetLookupTag32FilterCandidates(buckets, target_keys, queries, positive_query_indices, filter_positive_count, out_indices, hit_count, false_positive_count, resolve_reason, true))
		return MetalTargetLookupTag32FilterBenchJson("target_lookup_tag32_filter_exact256", operations, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, filter_seconds, exact_verify_seconds, filter_seconds + exact_verify_seconds, 0.0, 0, false, false, resolve_reason);

	uint64_t checksum = 0;
	std::string reason;
	if (!ValidateTargetLookupOutputs(out_indices, expected_indices, hit_count, expected_hits, &checksum, reason))
		return MetalTargetLookupTag32FilterBenchJson("target_lookup_tag32_filter_exact256", operations, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, filter_seconds, exact_verify_seconds, filter_seconds + exact_verify_seconds, 0.0, checksum, false, false, reason);

	double total_seconds = filter_seconds + exact_verify_seconds;
	double lookups_per_sec = total_seconds > 0.0 ? (double)operations / total_seconds : 0.0;
	return MetalTargetLookupTag32FilterBenchJson("target_lookup_tag32_filter_exact256", operations, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, filter_seconds, exact_verify_seconds, total_seconds, lookups_per_sec, checksum, true, false, "");
}

std::string RCKMetalTargetLookupTag32FilterPersistentBenchJson(unsigned int target_count, unsigned int query_count, unsigned int expected_hits, unsigned int min_ms, unsigned int threadgroup_limit)
{
	if (target_count == 0)
		target_count = 1;
	if (query_count == 0)
		query_count = 1;
	if (expected_hits > query_count)
		expected_hits = query_count;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveTargetLookupFilterPersistentThreadgroupLimit(threadgroup_limit, target_count);
	if (target_count > 32000000U)
	{
		std::string reason = "target lookup benchmark target_count limit is 32000000 for host memory safety";
		return MetalTargetLookupTag32FilterPersistentBenchJson("target_lookup_tag32_filter_persistent_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, reason);
	}

	std::vector<TargetLookupKeyHost> target_keys;
	std::vector<TargetLookupTag32BucketHost> buckets;
	std::string error;
	if (!BuildTargetLookupTag32Table(target_count, target_keys, buckets, error))
		return MetalTargetLookupTag32FilterPersistentBenchJson("target_lookup_tag32_filter_persistent_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, error);

	std::vector<uint32_t> filter_buckets;
	if (!BuildTargetLookupTag32FilterTable(target_keys, filter_buckets, error))
		return MetalTargetLookupTag32FilterPersistentBenchJson("target_lookup_tag32_filter_persistent_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, buckets.size(), target_keys.size() * sizeof(TargetLookupKeyHost), buckets.size() * sizeof(TargetLookupTag32BucketHost), 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, error);

	std::vector<TargetLookupKeyHost> queries;
	std::vector<uint32_t> expected_indices;
	BuildTargetLookupTag32Queries(target_keys, buckets, query_count, expected_hits, queries, expected_indices);

	std::vector<uint32_t> out_indices;
	uint32_t hit_count = 0;
	uint32_t filter_positive_count = 0;
	uint32_t false_positive_count = 0;
	double setup_seconds = 0.0;
	double dispatch_seconds = 0.0;
	double exact_verify_seconds = 0.0;
	uint64_t operations = 0;
	uint64_t target_key_bytes = target_keys.size() * sizeof(TargetLookupKeyHost);
	uint64_t target_bucket_bytes = buckets.size() * sizeof(TargetLookupTag32BucketHost);
	uint64_t target_filter_bucket_bytes = filter_buckets.size() * sizeof(uint32_t);
	if (!RunTargetLookupTag32FilterPersistentKernel(filter_buckets, buckets, target_keys, queries, min_ms, out_indices, hit_count, filter_positive_count, false_positive_count, operations, error, &setup_seconds, &dispatch_seconds, &exact_verify_seconds, threadgroup_limit, &dispatch_stats))
	{
		if (error == "no Metal device available")
			return MetalTargetLookupTag32FilterPersistentBenchJson("target_lookup_tag32_filter_persistent_exact256", 0, target_count, query_count, expected_hits, 0, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, exact_verify_seconds, setup_seconds + dispatch_seconds + exact_verify_seconds, 0.0, 0.0, 0, false, true, error);
		return MetalTargetLookupTag32FilterPersistentBenchJson("target_lookup_tag32_filter_persistent_exact256", operations ? operations : query_count, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, exact_verify_seconds, setup_seconds + dispatch_seconds + exact_verify_seconds, 0.0, 0.0, 0, false, false, error);
	}

	uint64_t checksum = 0;
	std::string reason;
	if (!ValidateTargetLookupOutputs(out_indices, expected_indices, hit_count, expected_hits, &checksum, reason))
		return MetalTargetLookupTag32FilterPersistentBenchJson("target_lookup_tag32_filter_persistent_exact256", operations, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, exact_verify_seconds, setup_seconds + dispatch_seconds + exact_verify_seconds, 0.0, 0.0, checksum, false, false, reason);

	double total_no_setup_seconds = dispatch_seconds + exact_verify_seconds;
	double total_seconds = setup_seconds + total_no_setup_seconds;
	double dispatch_lookups_per_sec = total_no_setup_seconds > 0.0 ? (double)operations / total_no_setup_seconds : 0.0;
	double lookups_per_sec = total_seconds > 0.0 ? (double)operations / total_seconds : 0.0;
	return MetalTargetLookupTag32FilterPersistentBenchJson("target_lookup_tag32_filter_persistent_exact256", operations, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, exact_verify_seconds, total_seconds, dispatch_lookups_per_sec, lookups_per_sec, checksum, true, false, "");
}

std::string RCKMetalTargetLookupTag16FilterPersistentBenchJson(unsigned int target_count, unsigned int query_count, unsigned int expected_hits, unsigned int min_ms, unsigned int threadgroup_limit)
{
	if (target_count == 0)
		target_count = 1;
	if (query_count == 0)
		query_count = 1;
	if (expected_hits > query_count)
		expected_hits = query_count;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveTargetLookupFilterPersistentThreadgroupLimit(threadgroup_limit, target_count);
	if (target_count > 32000000U)
	{
		std::string reason = "target lookup benchmark target_count limit is 32000000 for host memory safety";
		return MetalTargetLookupTag16FilterPersistentBenchJson("target_lookup_tag16_filter_persistent_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, reason);
	}

	std::vector<TargetLookupKeyHost> target_keys;
	std::vector<TargetLookupTag32BucketHost> buckets;
	std::string error;
	if (!BuildTargetLookupTag32Table(target_count, target_keys, buckets, error))
		return MetalTargetLookupTag16FilterPersistentBenchJson("target_lookup_tag16_filter_persistent_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, error);

	std::vector<uint16_t> filter_buckets;
	if (!BuildTargetLookupTag16FilterTable(target_keys, filter_buckets, error))
		return MetalTargetLookupTag16FilterPersistentBenchJson("target_lookup_tag16_filter_persistent_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, buckets.size(), target_keys.size() * sizeof(TargetLookupKeyHost), buckets.size() * sizeof(TargetLookupTag32BucketHost), 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, error);

	std::vector<TargetLookupKeyHost> queries;
	std::vector<uint32_t> expected_indices;
	BuildTargetLookupTag32Queries(target_keys, buckets, query_count, expected_hits, queries, expected_indices);

	std::vector<uint32_t> out_indices;
	uint32_t hit_count = 0;
	uint32_t filter_positive_count = 0;
	uint32_t false_positive_count = 0;
	double setup_seconds = 0.0;
	double dispatch_seconds = 0.0;
	double exact_verify_seconds = 0.0;
	uint64_t operations = 0;
	uint64_t target_key_bytes = target_keys.size() * sizeof(TargetLookupKeyHost);
	uint64_t target_bucket_bytes = buckets.size() * sizeof(TargetLookupTag32BucketHost);
	uint64_t target_filter_bucket_bytes = filter_buckets.size() * sizeof(uint16_t);
	if (!RunTargetLookupTag16FilterPersistentKernel(filter_buckets, buckets, target_keys, queries, min_ms, out_indices, hit_count, filter_positive_count, false_positive_count, operations, error, &setup_seconds, &dispatch_seconds, &exact_verify_seconds, threadgroup_limit, &dispatch_stats))
	{
		if (error == "no Metal device available")
			return MetalTargetLookupTag16FilterPersistentBenchJson("target_lookup_tag16_filter_persistent_exact256", 0, target_count, query_count, expected_hits, 0, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, exact_verify_seconds, setup_seconds + dispatch_seconds + exact_verify_seconds, 0.0, 0.0, 0, false, true, error);
		return MetalTargetLookupTag16FilterPersistentBenchJson("target_lookup_tag16_filter_persistent_exact256", operations ? operations : query_count, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, exact_verify_seconds, setup_seconds + dispatch_seconds + exact_verify_seconds, 0.0, 0.0, 0, false, false, error);
	}

	uint64_t checksum = 0;
	std::string reason;
	if (!ValidateTargetLookupOutputs(out_indices, expected_indices, hit_count, expected_hits, &checksum, reason))
		return MetalTargetLookupTag16FilterPersistentBenchJson("target_lookup_tag16_filter_persistent_exact256", operations, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, exact_verify_seconds, setup_seconds + dispatch_seconds + exact_verify_seconds, 0.0, 0.0, checksum, false, false, reason);

	double total_no_setup_seconds = dispatch_seconds + exact_verify_seconds;
	double total_seconds = setup_seconds + total_no_setup_seconds;
	double dispatch_lookups_per_sec = total_no_setup_seconds > 0.0 ? (double)operations / total_no_setup_seconds : 0.0;
	double lookups_per_sec = total_seconds > 0.0 ? (double)operations / total_seconds : 0.0;
	return MetalTargetLookupTag16FilterPersistentBenchJson("target_lookup_tag16_filter_persistent_exact256", operations, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, exact_verify_seconds, total_seconds, dispatch_lookups_per_sec, lookups_per_sec, checksum, true, false, "");
}

std::string RCKMetalTargetLookupTag16HashFilterPersistentBenchJson(unsigned int target_count, unsigned int query_count, unsigned int expected_hits, unsigned int min_ms, unsigned int threadgroup_limit)
{
	if (target_count == 0)
		target_count = 1;
	if (query_count == 0)
		query_count = 1;
	if (expected_hits > query_count)
		expected_hits = query_count;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveTargetLookupFilterPersistentThreadgroupLimit(threadgroup_limit, target_count);
	if (target_count > 32000000U)
	{
		std::string reason = "target lookup benchmark target_count limit is 32000000 for host memory safety";
		return MetalTargetLookupTag16HashFilterPersistentBenchJson("target_lookup_tag16_hash_filter_persistent_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, reason);
	}

	std::vector<TargetLookupKeyHost> target_keys;
	std::vector<TargetLookupTag32BucketHost> buckets;
	std::string error;
	if (!BuildTargetLookupTag32Table(target_count, target_keys, buckets, error))
		return MetalTargetLookupTag16HashFilterPersistentBenchJson("target_lookup_tag16_hash_filter_persistent_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, error);

	std::vector<uint16_t> filter_buckets;
	if (!BuildTargetLookupTag16FilterTable(target_keys, filter_buckets, error))
		return MetalTargetLookupTag16HashFilterPersistentBenchJson("target_lookup_tag16_hash_filter_persistent_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, buckets.size(), target_keys.size() * sizeof(TargetLookupKeyHost), buckets.size() * sizeof(TargetLookupTag32BucketHost), 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, error);

	std::vector<TargetLookupKeyHost> queries;
	std::vector<uint32_t> expected_indices;
	BuildTargetLookupTag32Queries(target_keys, buckets, query_count, expected_hits, queries, expected_indices);
	std::vector<uint64_t> query_hashes;
	BuildTargetLookupQueryHashes(queries, query_hashes);

	std::vector<uint32_t> out_indices;
	uint32_t hit_count = 0;
	uint32_t filter_positive_count = 0;
	uint32_t false_positive_count = 0;
	double setup_seconds = 0.0;
	double dispatch_seconds = 0.0;
	double exact_verify_seconds = 0.0;
	uint64_t operations = 0;
	uint64_t target_key_bytes = target_keys.size() * sizeof(TargetLookupKeyHost);
	uint64_t target_bucket_bytes = buckets.size() * sizeof(TargetLookupTag32BucketHost);
	uint64_t target_filter_bucket_bytes = filter_buckets.size() * sizeof(uint16_t);
	uint64_t target_query_hash_bytes = query_hashes.size() * sizeof(uint64_t);
	if (!RunTargetLookupTag16HashFilterPersistentKernel(filter_buckets, buckets, target_keys, queries, query_hashes, min_ms, out_indices, hit_count, filter_positive_count, false_positive_count, operations, error, &setup_seconds, &dispatch_seconds, &exact_verify_seconds, threadgroup_limit, &dispatch_stats))
	{
		if (error == "no Metal device available")
			return MetalTargetLookupTag16HashFilterPersistentBenchJson("target_lookup_tag16_hash_filter_persistent_exact256", 0, target_count, query_count, expected_hits, 0, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, target_query_hash_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, exact_verify_seconds, setup_seconds + dispatch_seconds + exact_verify_seconds, 0.0, 0.0, 0, false, true, error);
		return MetalTargetLookupTag16HashFilterPersistentBenchJson("target_lookup_tag16_hash_filter_persistent_exact256", operations ? operations : query_count, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, target_query_hash_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, exact_verify_seconds, setup_seconds + dispatch_seconds + exact_verify_seconds, 0.0, 0.0, 0, false, false, error);
	}

	uint64_t checksum = 0;
	std::string reason;
	if (!ValidateTargetLookupOutputs(out_indices, expected_indices, hit_count, expected_hits, &checksum, reason))
		return MetalTargetLookupTag16HashFilterPersistentBenchJson("target_lookup_tag16_hash_filter_persistent_exact256", operations, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, target_query_hash_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, exact_verify_seconds, setup_seconds + dispatch_seconds + exact_verify_seconds, 0.0, 0.0, checksum, false, false, reason);

	double total_no_setup_seconds = dispatch_seconds + exact_verify_seconds;
	double total_seconds = setup_seconds + total_no_setup_seconds;
	double dispatch_lookups_per_sec = total_no_setup_seconds > 0.0 ? (double)operations / total_no_setup_seconds : 0.0;
	double lookups_per_sec = total_seconds > 0.0 ? (double)operations / total_seconds : 0.0;
	return MetalTargetLookupTag16HashFilterPersistentBenchJson("target_lookup_tag16_hash_filter_persistent_exact256", operations, target_count, query_count, expected_hits, hit_count, filter_positive_count, false_positive_count, filter_buckets.size(), target_key_bytes, target_bucket_bytes, target_filter_bucket_bytes, target_query_hash_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, exact_verify_seconds, total_seconds, dispatch_lookups_per_sec, lookups_per_sec, checksum, true, false, "");
}

std::string RCKMetalTargetLookupTag32PersistentBenchJson(unsigned int target_count, unsigned int query_count, unsigned int expected_hits, unsigned int min_ms, unsigned int threadgroup_limit)
{
	if (target_count == 0)
		target_count = 1;
	if (query_count == 0)
		query_count = 1;
	if (expected_hits > query_count)
		expected_hits = query_count;

	MetalDispatchStats dispatch_stats;
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveTargetLookupPersistentThreadgroupLimit(threadgroup_limit, target_count);
	if (target_count > 32000000U)
	{
		std::string reason = "target lookup benchmark target_count limit is 32000000 for host memory safety";
		return MetalTargetLookupTag32PersistentBenchJson("target_lookup_tag32_persistent_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, reason);
	}

	std::vector<TargetLookupKeyHost> target_keys;
	std::vector<TargetLookupTag32BucketHost> buckets;
	std::string error;
	if (!BuildTargetLookupTag32Table(target_count, target_keys, buckets, error))
		return MetalTargetLookupTag32PersistentBenchJson("target_lookup_tag32_persistent_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, 0.0, 0.0, 0.0, 0, false, false, error);

	std::vector<TargetLookupKeyHost> queries;
	std::vector<uint32_t> expected_indices;
	BuildTargetLookupTag32Queries(target_keys, buckets, query_count, expected_hits, queries, expected_indices);

	std::vector<uint32_t> out_indices;
	uint32_t hit_count = 0;
	double setup_seconds = 0.0;
	double dispatch_seconds = 0.0;
	uint64_t operations = 0;
	uint64_t target_key_bytes = target_keys.size() * sizeof(TargetLookupKeyHost);
	uint64_t target_bucket_bytes = buckets.size() * sizeof(TargetLookupTag32BucketHost);
	if (!RunTargetLookupTag32PersistentKernel(buckets, target_keys, queries, min_ms, out_indices, hit_count, operations, error, &setup_seconds, &dispatch_seconds, threadgroup_limit, &dispatch_stats))
	{
		if (error == "no Metal device available")
			return MetalTargetLookupTag32PersistentBenchJson("target_lookup_tag32_persistent_exact256", 0, target_count, query_count, expected_hits, 0, buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, setup_seconds + dispatch_seconds, 0.0, 0.0, 0, false, true, error);
		return MetalTargetLookupTag32PersistentBenchJson("target_lookup_tag32_persistent_exact256", operations ? operations : query_count, target_count, query_count, expected_hits, hit_count, buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, setup_seconds + dispatch_seconds, 0.0, 0.0, 0, false, false, error);
	}

	uint64_t checksum = 0;
	std::string reason;
	if (!ValidateTargetLookupOutputs(out_indices, expected_indices, hit_count, expected_hits, &checksum, reason))
		return MetalTargetLookupTag32PersistentBenchJson("target_lookup_tag32_persistent_exact256", operations, target_count, query_count, expected_hits, hit_count, buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, setup_seconds + dispatch_seconds, 0.0, 0.0, checksum, false, false, reason);

	double total_seconds = setup_seconds + dispatch_seconds;
	double dispatch_lookups_per_sec = dispatch_seconds > 0.0 ? (double)operations / dispatch_seconds : 0.0;
	double lookups_per_sec = total_seconds > 0.0 ? (double)operations / total_seconds : 0.0;
	return MetalTargetLookupTag32PersistentBenchJson("target_lookup_tag32_persistent_exact256", operations, target_count, query_count, expected_hits, hit_count, buckets.size(), target_key_bytes, target_bucket_bytes, min_ms, dispatch_stats, setup_seconds, dispatch_seconds, total_seconds, dispatch_lookups_per_sec, lookups_per_sec, checksum, true, false, "");
}

std::string RCKCpuTargetLookupTag32BenchJson(unsigned int target_count, unsigned int query_count, unsigned int expected_hits, unsigned int min_ms)
{
	if (target_count == 0)
		target_count = 1;
	if (query_count == 0)
		query_count = 1;
	if (expected_hits > query_count)
		expected_hits = query_count;
	if (target_count > 32000000U)
	{
		std::string reason = "target lookup benchmark target_count limit is 32000000 for host memory safety";
		return CpuTargetLookupTag32BenchJson("target_lookup_tag32_cpu_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, min_ms, 0.0, 0.0, 0, false, reason);
	}

	std::vector<TargetLookupKeyHost> target_keys;
	std::vector<TargetLookupTag32BucketHost> buckets;
	std::string error;
	if (!BuildTargetLookupTag32Table(target_count, target_keys, buckets, error))
		return CpuTargetLookupTag32BenchJson("target_lookup_tag32_cpu_exact256", 0, target_count, query_count, expected_hits, 0, 0, 0, 0, min_ms, 0.0, 0.0, 0, false, error);

	std::vector<TargetLookupKeyHost> queries;
	std::vector<uint32_t> expected_indices;
	BuildTargetLookupTag32Queries(target_keys, buckets, query_count, expected_hits, queries, expected_indices);

	std::vector<uint32_t> out_indices;
	out_indices.resize(queries.size());
	uint32_t hit_count = 0;
	double seconds = 0.0;
	uint64_t operations = 0;
	unsigned int dispatch_count = 0;
	do
	{
		double dispatch_seconds = 0.0;
		if (!RunTargetLookupTag32Cpu(buckets, target_keys, queries, out_indices, hit_count, error, &dispatch_seconds))
			return CpuTargetLookupTag32BenchJson("target_lookup_tag32_cpu_exact256", operations, target_count, query_count, expected_hits, hit_count, buckets.size(), target_keys.size() * sizeof(TargetLookupKeyHost), buckets.size() * sizeof(TargetLookupTag32BucketHost), min_ms, seconds, 0.0, 0, false, error);
		seconds += dispatch_seconds;
		operations += query_count;
		dispatch_count++;
		if (min_ms && seconds == 0.0)
			break;
	} while (min_ms && (seconds * 1000.0 < (double)min_ms) && (dispatch_count < 100000));

	uint64_t checksum = 0;
	std::string reason;
	if (!ValidateTargetLookupOutputs(out_indices, expected_indices, hit_count, expected_hits, &checksum, reason))
		return CpuTargetLookupTag32BenchJson("target_lookup_tag32_cpu_exact256", operations, target_count, query_count, expected_hits, hit_count, buckets.size(), target_keys.size() * sizeof(TargetLookupKeyHost), buckets.size() * sizeof(TargetLookupTag32BucketHost), min_ms, seconds, 0.0, checksum, false, reason);

	double lookups_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	return CpuTargetLookupTag32BenchJson("target_lookup_tag32_cpu_exact256", operations, target_count, query_count, expected_hits, hit_count, buckets.size(), target_keys.size() * sizeof(TargetLookupKeyHost), buckets.size() * sizeof(TargetLookupTag32BucketHost), min_ms, seconds, lookups_per_sec, checksum, true, "");
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
