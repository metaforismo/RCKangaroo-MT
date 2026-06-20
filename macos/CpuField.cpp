#include "macos/CpuField.h"

#include <stdint.h>
#include <string.h>

#include <array>
#include <chrono>
#include <iomanip>
#include <sstream>
#include <vector>

#include "Ec.h"

typedef std::array<uint64_t, 4> CpuFieldElement;

static const CpuFieldElement kSecp256k1P = {
	0xFFFFFFFEFFFFFC2FULL,
	0xFFFFFFFFFFFFFFFFULL,
	0xFFFFFFFFFFFFFFFFULL,
	0xFFFFFFFFFFFFFFFFULL,
};

static const uint64_t kPRev = 0x00000001000003D1ULL;

static inline uint64_t Mul64(uint64_t a, uint64_t b, uint64_t* hi)
{
	unsigned __int128 product = (unsigned __int128)a * (unsigned __int128)b;
	*hi = (uint64_t)(product >> 64);
	return (uint64_t)product;
}

static inline uint8_t AddCarry(uint8_t carry, uint64_t a, uint64_t b, uint64_t* out)
{
#if defined(__clang__)
	unsigned long long carry_out = 0;
	*out = (uint64_t)__builtin_addcll((unsigned long long)a, (unsigned long long)b, (unsigned long long)carry, &carry_out);
	return (uint8_t)carry_out;
#else
	unsigned __int128 sum = (unsigned __int128)a + (unsigned __int128)b + carry;
	*out = (uint64_t)sum;
	return (uint8_t)(sum >> 64);
#endif
}

static inline uint8_t SubBorrow(uint8_t borrow, uint64_t a, uint64_t b, uint64_t* out)
{
#if defined(__clang__)
	unsigned long long borrow_out = 0;
	*out = (uint64_t)__builtin_subcll((unsigned long long)a, (unsigned long long)b, (unsigned long long)borrow, &borrow_out);
	return (uint8_t)borrow_out;
#else
	uint64_t sub = b + borrow;
	*out = a - sub;
	return (uint8_t)((a < b) || (borrow && a == b));
#endif
}

static const char* CarryImplMode()
{
#if defined(__clang__)
	return "clang_builtin";
#else
	return "uint128";
#endif
}

static bool FieldGeP(const CpuFieldElement& v)
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

static void SubP5(uint64_t v[5])
{
	uint8_t borrow = SubBorrow(0, v[0], kSecp256k1P[0], v + 0);
	borrow = SubBorrow(borrow, v[1], kSecp256k1P[1], v + 1);
	borrow = SubBorrow(borrow, v[2], kSecp256k1P[2], v + 2);
	borrow = SubBorrow(borrow, v[3], kSecp256k1P[3], v + 3);
	SubBorrow(borrow, v[4], 0, v + 4);
}

static void SubP(CpuFieldElement& v)
{
	uint64_t tmp[5] = {v[0], v[1], v[2], v[3], 0};
	SubP5(tmp);
	v = {tmp[0], tmp[1], tmp[2], tmp[3]};
}

static CpuFieldElement FieldAdd(const CpuFieldElement& a, const CpuFieldElement& b)
{
	CpuFieldElement out;
	uint8_t carry = AddCarry(0, a[0], b[0], &out[0]);
	carry = AddCarry(carry, a[1], b[1], &out[1]);
	carry = AddCarry(carry, a[2], b[2], &out[2]);
	carry = AddCarry(carry, a[3], b[3], &out[3]);
	if (carry || FieldGeP(out))
		SubP(out);
	return out;
}

static CpuFieldElement FieldSub(const CpuFieldElement& a, const CpuFieldElement& b)
{
	CpuFieldElement out;
	uint8_t borrow = SubBorrow(0, a[0], b[0], &out[0]);
	borrow = SubBorrow(borrow, a[1], b[1], &out[1]);
	borrow = SubBorrow(borrow, a[2], b[2], &out[2]);
	borrow = SubBorrow(borrow, a[3], b[3], &out[3]);
	if (borrow)
	{
		uint8_t carry = AddCarry(0, out[0], kSecp256k1P[0], &out[0]);
		carry = AddCarry(carry, out[1], kSecp256k1P[1], &out[1]);
		carry = AddCarry(carry, out[2], kSecp256k1P[2], &out[2]);
		AddCarry(carry, out[3], kSecp256k1P[3], &out[3]);
	}
	return out;
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

static CpuFieldElement FieldMul(const CpuFieldElement& a, const CpuFieldElement& b)
{
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

	Mul256By64(buff + 4, kPRev, tmp);
	uint8_t carry = AddCarry(0, buff[0], tmp[0], buff + 0);
	carry = AddCarry(carry, buff[1], tmp[1], buff + 1);
	carry = AddCarry(carry, buff[2], tmp[2], buff + 2);
	tmp[4] += AddCarry(carry, buff[3], tmp[3], buff + 3);

	uint64_t reduced[5] = {0};
	carry = AddCarry(0, buff[0], Mul64(tmp[4], kPRev, &high), reduced + 0);
	carry = AddCarry(carry, buff[1], high, reduced + 1);
	carry = AddCarry(carry, 0, buff[2], reduced + 2);
	reduced[4] = AddCarry(carry, buff[3], 0, reduced + 3);

	CpuFieldElement out = {reduced[0], reduced[1], reduced[2], reduced[3]};
	while (reduced[4] || FieldGeP(out))
	{
		SubP5(reduced);
		out = {reduced[0], reduced[1], reduced[2], reduced[3]};
	}
	return out;
}

static CpuFieldElement DeterministicElement(uint64_t i, uint64_t salt)
{
	CpuFieldElement v = {
		0x9E3779B97F4A7C15ULL * (i + 1) + salt,
		0xD1B54A32D192ED03ULL * (i + 3) + (salt << 1),
		0x94D049BB133111EBULL * (i + 5) + (salt << 2),
		((i + salt) << 17) ^ (0xA5A5A5A5ULL + salt),
	};
	if (FieldGeP(v))
		SubP(v);
	return v;
}

static EcInt ToEcInt(const CpuFieldElement& v)
{
	EcInt out;
	out.SetZero();
	out.data[0] = v[0];
	out.data[1] = v[1];
	out.data[2] = v[2];
	out.data[3] = v[3];
	return out;
}

static CpuFieldElement FromEcInt(EcInt& v)
{
	return {v.data[0], v.data[1], v.data[2], v.data[3]};
}

static CpuFieldElement FromEcIntCanonical(EcInt& v)
{
	CpuFieldElement out = FromEcInt(v);
	while (v.data[4] || FieldGeP(out))
	{
		uint64_t tmp[5] = {out[0], out[1], out[2], out[3], v.data[4]};
		SubP5(tmp);
		v.data[4] = tmp[4];
		out = {tmp[0], tmp[1], tmp[2], tmp[3]};
	}
	return out;
}

static std::string FieldToHex(const CpuFieldElement& v)
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

static uint64_t MixChecksum(uint64_t checksum, const CpuFieldElement& v, uint64_t index)
{
	return checksum + v[0] + (v[1] ^ v[2]) + v[3] + index;
}

static bool CheckVector(const CpuFieldElement& a, const CpuFieldElement& b, std::string& error)
{
	EcInt ea = ToEcInt(a);
	EcInt eb = ToEcInt(b);

	CpuFieldElement got_add = FieldAdd(a, b);
	EcInt exp_add = ea;
	exp_add.AddModP(eb);
	CpuFieldElement expected_add = FromEcIntCanonical(exp_add);
	if (got_add != expected_add)
	{
		error = "add mismatch got " + FieldToHex(got_add) + " expected " + FieldToHex(expected_add);
		return false;
	}

	CpuFieldElement got_sub = FieldSub(a, b);
	EcInt exp_sub = ea;
	exp_sub.SubModP(eb);
	CpuFieldElement expected_sub = FromEcIntCanonical(exp_sub);
	if (got_sub != expected_sub)
	{
		error = "sub mismatch got " + FieldToHex(got_sub) + " expected " + FieldToHex(expected_sub);
		return false;
	}

	CpuFieldElement got_mul = FieldMul(a, b);
	EcInt exp_mul = ea;
	exp_mul.MulModP(eb);
	CpuFieldElement expected_mul = FromEcIntCanonical(exp_mul);
	if (got_mul != expected_mul)
	{
		error = "mul mismatch got " + FieldToHex(got_mul) + " expected " + FieldToHex(expected_mul);
		return false;
	}

	return true;
}

bool RCKCpuFieldSelfTest(std::string& error)
{
	std::vector<CpuFieldElement> vectors;
	vectors.push_back({0, 0, 0, 0});
	vectors.push_back({1, 0, 0, 0});
	vectors.push_back({2, 0, 0, 0});
	vectors.push_back({0xFFFFFFFFFFFFFFFFULL, 0, 0, 0});
	vectors.push_back({0xFFFFFFFEFFFFFC2EULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	vectors.push_back({0xFFFFFFFEFFFFFC2DULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFFULL});
	for (uint64_t i = 0; i < 96; ++i)
		vectors.push_back(DeterministicElement(i, 0x1234ULL + i * 17));

	for (size_t i = 0; i < vectors.size(); ++i)
	{
		for (size_t j = 0; j < vectors.size(); ++j)
		{
			if (!CheckVector(vectors[i], vectors[j], error))
			{
				error += " at vector pair " + std::to_string(i) + "," + std::to_string(j);
				return false;
			}
		}
	}
	return true;
}

static std::string CpuFieldBenchJson(uint64_t operations,
		unsigned int sample_count,
		unsigned int min_ms,
		double seconds,
		double ops_per_sec,
		double reference_seconds,
	double reference_ops_per_sec,
	uint64_t checksum,
	bool correctness,
	const std::string& reason)
{
	std::ostringstream oss;
	oss << std::fixed << std::setprecision(6);
	oss << "{\"backend\":\"macos_cpu\",";
	oss << "\"operation\":\"field_mul_mod_p\",";
	oss << "\"carry_impl\":\"" << CarryImplMode() << "\",";
	oss << "\"iterations\":" << operations << ",";
	oss << "\"sample_count\":" << sample_count << ",";
	oss << "\"min_ms\":" << min_ms << ",";
	oss << "\"seconds\":" << seconds << ",";
	oss << "\"ops_per_sec\":" << ops_per_sec << ",";
	oss << "\"reference_backend\":\"ecint\",";
	oss << "\"reference_seconds\":" << reference_seconds << ",";
	oss << "\"reference_ops_per_sec\":" << reference_ops_per_sec << ",";
	oss << "\"speedup_vs_ecint\":" << (reference_ops_per_sec > 0.0 ? ops_per_sec / reference_ops_per_sec : 0.0) << ",";
	oss << "\"checksum\":\"0x" << std::hex << checksum << std::dec << "\",";
	oss << "\"correctness\":" << (correctness ? "true" : "false");
	if (!reason.empty())
		oss << ",\"reason\":\"" << reason << "\"";
	oss << "}";
	return oss.str();
}

std::string RCKCpuFieldBenchJson(unsigned int iterations, unsigned int min_ms)
{
	if (!iterations)
		iterations = 1;

	std::string error;
	if (!RCKCpuFieldSelfTest(error))
		return CpuFieldBenchJson(0, iterations, min_ms, 0.0, 0.0, 0.0, 0.0, 0, false, error);

	std::vector<CpuFieldElement> a;
	std::vector<CpuFieldElement> b;
	a.reserve(iterations);
	b.reserve(iterations);
	for (unsigned int i = 0; i < iterations; ++i)
	{
		a.push_back(DeterministicElement(i, 0xCAFEULL));
		b.push_back(DeterministicElement(i, 0xBEEFULL));
	}

	uint64_t checksum = 0;
	uint64_t operations = 0;
	auto t0 = std::chrono::steady_clock::now();
	auto t1 = t0;
	do
	{
		for (unsigned int i = 0; i < iterations; ++i)
		{
			CpuFieldElement out = FieldMul(a[i], b[i]);
			checksum = MixChecksum(checksum, out, operations + i);
		}
		operations += iterations;
		t1 = std::chrono::steady_clock::now();
	} while (min_ms && (std::chrono::duration<double, std::milli>(t1 - t0).count() < (double)min_ms));

	uint64_t reference_checksum = 0;
	auto r0 = std::chrono::steady_clock::now();
	for (uint64_t done = 0; done < operations;)
	{
		for (unsigned int i = 0; i < iterations; ++i, ++done)
		{
			EcInt ea = ToEcInt(a[i]);
			EcInt eb = ToEcInt(b[i]);
			ea.MulModP(eb);
			CpuFieldElement out = FromEcIntCanonical(ea);
			reference_checksum = MixChecksum(reference_checksum, out, done);
		}
	}
	auto r1 = std::chrono::steady_clock::now();

	double seconds = std::chrono::duration<double>(t1 - t0).count();
	double reference_seconds = std::chrono::duration<double>(r1 - r0).count();
	double ops_per_sec = seconds > 0.0 ? (double)operations / seconds : 0.0;
	double reference_ops_per_sec = reference_seconds > 0.0 ? (double)operations / reference_seconds : 0.0;
	bool correctness = checksum == reference_checksum;
	std::string reason = correctness ? "" : "checksum mismatch against EcInt reference";
	return CpuFieldBenchJson(operations, iterations, min_ms, seconds, ops_per_sec, reference_seconds, reference_ops_per_sec, checksum, correctness, reason);
}
