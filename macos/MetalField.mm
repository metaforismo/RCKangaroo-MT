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
static constexpr unsigned int kDefaultMetalDp12StreamThreadgroupLimit = 128;

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
		memcpy(indices_out.data(), [indices_buffer contents], indices_bytes);
		memcpy(distances_out.data(), [out_distances_buffer contents], distances_out_bytes);
		memcpy(dp_terms_out.data(), [out_dp_terms_buffer contents], dp_terms_bytes);
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
	NSUInteger effective_threadgroup_limit = EffectiveDynamicDpStreamThreadgroupLimit(threadgroup_limit, dp_bits);
	if (dispatch_stats)
		dispatch_stats->threadgroup_limit = (unsigned int)effective_threadgroup_limit;

	if (p.empty() || jumps.empty() || jumps.size() != jump_distances.size() || (steps_per_sample != 8 && steps_per_sample != 16 && steps_per_sample != 32 && steps_per_sample != 64) || dp_bits != 8 || !IsMetalPowerOfTwo((unsigned int)jumps.size()) || jumps.size() > 32)
	{
		error = "invalid jacobian dynamic dp stream in-place input";
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

		const char* function_name = steps_per_sample == 64
			? "jacobian_affine_walk_dynamic_dp_stream_inplace_steps64_dp8_pow2_u32_distance"
			: (steps_per_sample == 32
				? "jacobian_affine_walk_dynamic_dp_stream_inplace_steps32_dp8_pow2_u32_distance"
				: (steps_per_sample == 16
					? "jacobian_affine_walk_dynamic_dp_stream_inplace_steps16_dp8_pow2_u32_distance"
					: "jacobian_affine_walk_dynamic_dp_stream_inplace_steps8_dp8_pow2_u32_distance"));
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
		memcpy(indices_out.data(), [indices_buffer contents], indices_bytes);
		memcpy(distances_out.data(), [out_distances_buffer contents], distances_out_bytes);
		memcpy(dp_terms_out.data(), [out_dp_terms_buffer contents], dp_terms_bytes);
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

static void BuildJacobianJumpDistances(unsigned int jump_count, std::vector<uint64_t>& jump_distances)
{
	jump_distances.clear();
	jump_distances.reserve(jump_count);
	for (unsigned int i = 0; i < jump_count; ++i)
		jump_distances.push_back(1ULL << i);
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

static uint64_t MixCompactDpChecksum(uint64_t checksum, uint64_t dp_term, uint32_t dp_flag, size_t sample_index)
{
	if (!dp_flag)
		return checksum ^ ((uint64_t)sample_index * 0xD6E8FEB86659FD93ULL);
	return checksum ^ dp_term ^ ((uint64_t)sample_index * 0x9E3779B97F4A7C15ULL);
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
	for (size_t i = 0; i < p.size(); ++i)
	{
		uint64_t expected_distance = 0;
		CpuJacobianPoint expected = CpuJacobianDynamicJumpWalk(p[i], jumps, jump_distances, steps_per_sample, &expected_distance, jump_histogram);
		uint32_t expected_dp_flag = ProjectiveDpFlag(expected, dp_bits);
		expected_dp_flags[i] = expected_dp_flag;
		expected_distances[i] = expected_distance;
		expected_dp_terms[i] = CompactDpTerm(expected, expected_dp_flag);
		expected_dp_count += expected_dp_flag ? 1U : 0U;
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
	for (size_t i = 0; i < p.size(); ++i)
	{
		CpuJacobianPoint expected = CpuJacobianDynamicJumpWalk(p[i], jumps, jump_distances, steps_per_sample, NULL);
		if (!CpuJacobianMatches(state_out[i], expected))
		{
			reason = "dynamic state mismatch at sample " + std::to_string(i) +
				": got x=" + FieldToHex(state_out[i].x) +
				" y=" + FieldToHex(state_out[i].y) +
				" z=" + FieldToHex(state_out[i].z) +
				" inf=" + (state_out[i].infinity ? "1" : "0") +
				" expected x=" + FieldToHex(expected.x) +
				" y=" + FieldToHex(expected.y) +
				" z=" + FieldToHex(expected.z) +
				" inf=" + (expected.infinity ? "1" : "0");
			return false;
		}
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

	for (unsigned int steps_per_sample : {8U, 16U, 32U, 64U})
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
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);
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
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveThreadgroupLimit(threadgroup_limit);
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
	dispatch_stats.threadgroup_limit = (unsigned int)EffectiveDynamicDpStreamThreadgroupLimit(threadgroup_limit, dp_bits);
	if ((steps_per_sample != 8 && steps_per_sample != 16 && steps_per_sample != 32 && steps_per_sample != 64) || dp_bits != 8 || !IsMetalPowerOfTwo(jump_count))
	{
		std::string reason = "in-place stream dynamic dp supports steps=8, steps=16, steps=32, or steps=64, power-of-two jumps, dp_bits=8";
		return MetalJacobianDynamicDpStreamBenchJson("jacobian_affine_walk_dynamic_dp_stream_inplace", (uint64_t)sample_count * steps_per_sample, sample_count, steps_per_sample, jump_count, jump_index_mode, kDynamicJumpMixerName, 0, 0, 0, 0, dp_capacity, false, 0, dp_bits, 0, 0, min_ms, dispatch_stats, 0.0, 0.0, false, false, reason);
	}

	std::vector<CpuJacobianPoint> p;
	std::vector<CpuAffinePoint> jumps;
	std::vector<uint64_t> jump_distances;
	BuildJacobianJumpWalkSamples(sample_count, jump_count, p, jumps);
	BuildJacobianJumpDistances(jump_count, jump_distances);

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
