#include "macos/RCKMac.h"

#include <chrono>
#include <sstream>

static bool PointMatches(EcPoint a, EcPoint b)
{
	return a.IsEqual(b);
}

static u64 MixPointChecksum(u64 checksum, const EcPoint& p, u64 index)
{
	return checksum + p.x.data[0] + (p.x.data[1] ^ p.x.data[2]) + p.x.data[3] +
		p.y.data[0] + (p.y.data[1] ^ p.y.data[2]) + p.y.data[3] + index;
}

struct JacobianPoint
{
	EcInt x;
	EcInt y;
	EcInt z;
	bool infinity;
};

static EcInt FieldAdd(EcInt a, EcInt b)
{
	a.AddModP(b);
	return a;
}

static EcInt FieldSub(EcInt a, EcInt b)
{
	a.SubModP(b);
	return a;
}

static EcInt FieldMul(EcInt a, EcInt b)
{
	a.MulModP(b);
	return a;
}

static EcInt FieldSquare(EcInt a)
{
	EcInt b = a;
	a.MulModP(b);
	return a;
}

static EcInt FieldDouble(EcInt a)
{
	EcInt b = a;
	a.AddModP(b);
	return a;
}

static u64 MixJacobianChecksum(u64 checksum, const JacobianPoint& p, u64 index)
{
	return checksum + p.x.data[0] + (p.x.data[1] ^ p.x.data[2]) + p.x.data[3] +
		p.y.data[0] + (p.y.data[1] ^ p.y.data[2]) + p.y.data[3] +
		p.z.data[0] + (p.z.data[1] ^ p.z.data[2]) + p.z.data[3] + index;
}

static unsigned int JacobianJumpIndex(const JacobianPoint& p, unsigned int jump_count)
{
	u64 mixed = p.x.data[0] ^ (p.x.data[1] << 7) ^ (p.y.data[0] >> 3) ^ p.z.data[0];
	mixed ^= mixed >> 33;
	mixed *= 0xff51afd7ed558ccdULL;
	mixed ^= mixed >> 33;
	return (unsigned int)(mixed % jump_count);
}

static u64 JumpDistance(unsigned int index)
{
	return 1ull << index;
}

static JacobianPoint JacobianFromAffine(EcPoint p)
{
	JacobianPoint out;
	out.x = p.x;
	out.y = p.y;
	out.z.Set(1);
	out.infinity = false;
	return out;
}

static JacobianPoint JacobianDouble(JacobianPoint p)
{
	JacobianPoint out;
	if (p.infinity || p.y.IsZero())
	{
		out.infinity = true;
		return out;
	}

	EcInt xx = FieldSquare(p.x);
	EcInt yy = FieldSquare(p.y);
	EcInt yyyy = FieldSquare(yy);
	EcInt s = FieldDouble(FieldSub(FieldSub(FieldSquare(FieldAdd(p.x, yy)), xx), yyyy));
	EcInt m = FieldAdd(FieldDouble(xx), xx);
	EcInt t = FieldSub(FieldSquare(m), FieldDouble(s));
	EcInt eight_yyyy = FieldDouble(FieldDouble(FieldDouble(yyyy)));

	out.x = t;
	out.y = FieldSub(FieldMul(m, FieldSub(s, t)), eight_yyyy);
	out.z = FieldSub(FieldSub(FieldSquare(FieldAdd(p.y, p.z)), yy), FieldSquare(p.z));
	out.infinity = false;
	return out;
}

static EcPoint JacobianToAffine(JacobianPoint p)
{
	EcPoint out;
	if (p.infinity || p.z.IsZero())
		return out;

	EcInt z_inv = p.z;
	z_inv.InvModP();
	EcInt z2 = FieldSquare(z_inv);
	EcInt z3 = FieldMul(z2, z_inv);
	out.x = FieldMul(p.x, z2);
	out.y = FieldMul(p.y, z3);
	return out;
}

static JacobianPoint JacobianAddAffine(JacobianPoint p, EcPoint q)
{
	if (p.infinity)
		return JacobianFromAffine(q);

	EcInt z2 = FieldSquare(p.z);
	EcInt z3 = FieldMul(z2, p.z);
	EcInt u2 = FieldMul(q.x, z2);
	EcInt s2 = FieldMul(q.y, z3);
	EcInt h = FieldSub(u2, p.x);
	EcInt r = FieldSub(s2, p.y);

	JacobianPoint out;
	if (h.IsZero())
	{
		if (r.IsZero())
			return JacobianDouble(p);
		out.infinity = true;
		return out;
	}

	EcInt hh = FieldSquare(h);
	EcInt hhh = FieldMul(hh, h);
	EcInt v = FieldMul(p.x, hh);
	EcInt x3 = FieldSub(FieldSub(FieldSquare(r), hhh), FieldDouble(v));
	EcInt y3 = FieldSub(FieldMul(r, FieldSub(v, x3)), FieldMul(p.y, hhh));
	EcInt z3_out = FieldMul(p.z, h);

	out.x = x3;
	out.y = y3;
	out.z = z3_out;
	out.infinity = false;
	return out;
}

static unsigned long long RangeLimit(unsigned int range_bits)
{
	if (range_bits > 24)
		return 0;
	return 1ull << range_bits;
}

bool RCKSelfTest(std::string& error)
{
	EcInt one, two, three, seven;
	one.Set(1);
	two.Set(2);
	three.Set(3);
	seven.Set(7);

	EcPoint g = Ec::MultiplyG(one);
	EcPoint two_g = Ec::MultiplyG(two);
	EcPoint two_g_by_double = Ec::DoublePoint(g);
	if (!PointMatches(two_g, two_g_by_double))
	{
		error = "2G mismatch";
		return false;
	}

	EcPoint three_g = Ec::MultiplyG(three);
	EcPoint three_g_by_add = Ec::AddPoints(two_g, g);
	if (!PointMatches(three_g, three_g_by_add))
	{
		error = "3G mismatch";
		return false;
	}

	EcPoint seven_g = Ec::MultiplyG(seven);
	RCKSmallSolveResult res = RCKSolveSmallSingle(seven_g, 0, 4);
	if (!res.found || (res.private_key != 7))
	{
		error = "tiny solve for k=7 failed";
		return false;
	}

	std::vector<EcPoint> targets;
	targets.push_back(g);
	targets.push_back(seven_g);
	RCKSmallSolveResult multi = RCKSolveSmallMulti(targets, 0, 4);
	if (!multi.found || (multi.private_key != 1) || (multi.target_index != 0))
	{
		error = "tiny multi-target solve failed";
		return false;
	}

	return true;
}

RCKSmallSolveResult RCKSolveSmallSingle(EcPoint target, unsigned long long start, unsigned int range_bits)
{
	RCKSmallSolveResult result;
	result.found = false;
	result.private_key = 0;
	result.target_index = 0;

	unsigned long long limit = RangeLimit(range_bits);
	if (!limit)
		return result;

	for (unsigned long long i = 0; i < limit; i++)
	{
		EcInt candidate;
		candidate.Set(start + i);
		EcPoint p = Ec::MultiplyG(candidate);
		if (PointMatches(p, target))
		{
			result.found = true;
			result.private_key = start + i;
			return result;
		}
	}

	return result;
}

RCKSmallSolveResult RCKSolveSmallMulti(const std::vector<EcPoint>& targets, unsigned long long start, unsigned int range_bits)
{
	RCKSmallSolveResult result;
	result.found = false;
	result.private_key = 0;
	result.target_index = 0;

	unsigned long long limit = RangeLimit(range_bits);
	if (!limit)
		return result;

	for (unsigned long long i = 0; i < limit; i++)
	{
		EcInt candidate;
		candidate.Set(start + i);
		EcPoint p = Ec::MultiplyG(candidate);
		for (unsigned int target_index = 0; target_index < targets.size(); target_index++)
		{
			EcPoint target = targets[target_index];
			if (PointMatches(p, target))
			{
				result.found = true;
				result.private_key = start + i;
				result.target_index = target_index;
				return result;
			}
		}
	}

	return result;
}

std::string RCKBenchJson(unsigned int iterations)
{
	if (!iterations)
		iterations = 1;

	bool correctness = true;
	auto t0 = std::chrono::steady_clock::now();
	for (unsigned int i = 1; i <= iterations; i++)
	{
		EcInt k;
		k.Set(i);
		EcPoint p = Ec::MultiplyG(k);
		if (p.x.IsZero())
			correctness = false;
	}
	auto t1 = std::chrono::steady_clock::now();
	double seconds = std::chrono::duration<double>(t1 - t0).count();
	double ops_per_sec = seconds > 0 ? iterations / seconds : 0.0;

	std::ostringstream out;
	out.setf(std::ios::fixed);
	out.precision(6);
	out << "{\"backend\":\"cpu\",";
	out << "\"operation\":\"multiply_g\",";
	out << "\"iterations\":" << iterations << ",";
	out << "\"seconds\":" << seconds << ",";
	out << "\"ops_per_sec\":" << ops_per_sec << ",";
	out << "\"correctness\":" << (correctness ? "true" : "false") << "}";
	return out.str();
}

std::string RCKPointAddBenchJson(unsigned int iterations, unsigned int min_ms)
{
	if (!iterations)
		iterations = 1;

	EcInt one;
	one.Set(1);
	EcPoint g = Ec::MultiplyG(one);
	EcPoint p = Ec::DoublePoint(g);

	u64 checksum = 0;
	u64 operations = 0;
	auto t0 = std::chrono::steady_clock::now();
	auto t1 = t0;
	do
	{
		for (unsigned int i = 0; i < iterations; i++)
		{
			p = Ec::AddPoints(p, g);
			checksum = MixPointChecksum(checksum, p, operations + i);
		}
		operations += iterations;
		t1 = std::chrono::steady_clock::now();
	} while (min_ms && (std::chrono::duration<double, std::milli>(t1 - t0).count() < (double)min_ms));

	EcInt expected_k;
	expected_k.Set(operations + 2);
	EcPoint expected = Ec::MultiplyG(expected_k);
	bool correctness = PointMatches(p, expected);

	double seconds = std::chrono::duration<double>(t1 - t0).count();
	double ops_per_sec = seconds > 0 ? operations / seconds : 0.0;

	std::ostringstream out;
	out.setf(std::ios::fixed);
	out.precision(6);
	out << "{\"backend\":\"macos_cpu\",";
	out << "\"operation\":\"point_add_g\",";
	out << "\"iterations\":" << operations << ",";
	out << "\"sample_count\":" << iterations << ",";
	out << "\"min_ms\":" << min_ms << ",";
	out << "\"seconds\":" << seconds << ",";
	out << "\"ops_per_sec\":" << ops_per_sec << ",";
	out << "\"checksum\":\"0x" << std::hex << checksum << std::dec << "\",";
	out << "\"final_scalar\":\"0x" << std::hex << (operations + 2) << std::dec << "\",";
	out << "\"correctness\":" << (correctness ? "true" : "false");
	if (!correctness)
		out << ",\"reason\":\"final point mismatch against MultiplyG reference\"";
	out << "}";
	return out.str();
}

std::string RCKJacobianWalkBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int jump_count)
{
	if (!iterations)
		iterations = 1;
	if (jump_count < 2)
		jump_count = 2;
	if (jump_count > 32)
		jump_count = 32;

	std::vector<EcPoint> jump_points;
	std::vector<u64> jump_distances;
	jump_points.reserve(jump_count);
	jump_distances.reserve(jump_count);
	for (unsigned int i = 0; i < jump_count; i++)
	{
		u64 distance = JumpDistance(i);
		EcInt k;
		k.Set(distance);
		jump_distances.push_back(distance);
		jump_points.push_back(Ec::MultiplyG(k));
	}

	EcInt start_k;
	start_k.Set(2);
	JacobianPoint p = JacobianFromAffine(Ec::MultiplyG(start_k));

	u64 checksum = 0;
	u64 operations = 0;
	u64 scalar_distance = 0;
	auto t0 = std::chrono::steady_clock::now();
	auto t1 = t0;
	do
	{
		for (unsigned int i = 0; i < iterations; i++)
		{
			unsigned int jump_index = JacobianJumpIndex(p, jump_count);
			p = JacobianAddAffine(p, jump_points[jump_index]);
			scalar_distance += jump_distances[jump_index];
			checksum = MixJacobianChecksum(checksum, p, scalar_distance ^ (operations + i));
		}
		operations += iterations;
		t1 = std::chrono::steady_clock::now();
	} while (min_ms && (std::chrono::duration<double, std::milli>(t1 - t0).count() < (double)min_ms));

	u64 final_scalar = 2 + scalar_distance;
	EcInt expected_k;
	expected_k.Set(final_scalar);
	EcPoint final_point = JacobianToAffine(p);
	EcPoint expected = Ec::MultiplyG(expected_k);
	bool correctness = PointMatches(final_point, expected);

	double seconds = std::chrono::duration<double>(t1 - t0).count();
	double ops_per_sec = seconds > 0 ? operations / seconds : 0.0;
	double avg_jump_distance = operations > 0 ? (double)scalar_distance / (double)operations : 0.0;

	std::ostringstream out;
	out.setf(std::ios::fixed);
	out.precision(6);
	out << "{\"backend\":\"macos_cpu\",";
	out << "\"operation\":\"jacobian_jump_walk\",";
	out << "\"iterations\":" << operations << ",";
	out << "\"sample_count\":" << iterations << ",";
	out << "\"min_ms\":" << min_ms << ",";
	out << "\"jump_count\":" << jump_count << ",";
	out << "\"seconds\":" << seconds << ",";
	out << "\"ops_per_sec\":" << ops_per_sec << ",";
	out << "\"avg_jump_distance\":" << avg_jump_distance << ",";
	out << "\"start_scalar\":\"0x2\",";
	out << "\"scalar_distance\":\"0x" << std::hex << scalar_distance << std::dec << "\",";
	out << "\"final_scalar\":\"0x" << std::hex << final_scalar << std::dec << "\",";
	out << "\"checksum\":\"0x" << std::hex << checksum << std::dec << "\",";
	out << "\"correctness\":" << (correctness ? "true" : "false");
	if (!correctness)
		out << ",\"reason\":\"final walk point mismatch against scalar oracle\"";
	out << "}";
	return out.str();
}

struct KangarooDp
{
	std::string key;
	u64 distance;
	bool tame;
};

static std::string PointKey(EcPoint p)
{
	char x[65];
	char y[65];
	p.x.GetHexStr(x);
	p.y.GetHexStr(y);
	return std::string(x) + ":" + std::string(y);
}

static bool IsDistinguished(EcPoint p, unsigned int dp_bits)
{
	if (!dp_bits)
		return true;
	if (dp_bits >= 63)
		dp_bits = 62;
	u64 mask = (1ull << dp_bits) - 1;
	return (p.x.data[0] & mask) == 0;
}

static bool VerifyCandidate(EcPoint target, u64 candidate)
{
	EcInt k;
	k.Set(candidate);
	EcPoint p = Ec::MultiplyG(k);
	return PointMatches(p, target);
}

static bool CheckKangarooCollision(const std::vector<KangarooDp>& table,
	const std::string& key,
	bool tame,
	u64 distance,
	u64 start,
	u64 limit,
	EcPoint target,
	u64* candidate)
{
	for (size_t i = 0; i < table.size(); i++)
	{
		const KangarooDp& other = table[i];
		if ((other.tame == tame) || (other.key != key))
			continue;

		u64 tame_distance = tame ? distance : other.distance;
		u64 wild_distance = tame ? other.distance : distance;
		if (tame_distance < wild_distance)
			continue;

		u64 found = tame_distance - wild_distance;
		if ((found < start) || (found >= start + limit))
			continue;
		if (!VerifyCandidate(target, found))
			continue;

		*candidate = found;
		return true;
	}
	return false;
}

static void RecordKangarooDp(std::vector<KangarooDp>& table, const std::string& key, bool tame, u64 distance)
{
	KangarooDp dp;
	dp.key = key;
	dp.tame = tame;
	dp.distance = distance;
	table.push_back(dp);
}

static void KangarooStep(JacobianPoint& p, u64* distance, const std::vector<EcPoint>& jumps, const std::vector<u64>& jump_distances)
{
	unsigned int jump_index = JacobianJumpIndex(p, (unsigned int)jumps.size());
	p = JacobianAddAffine(p, jumps[jump_index]);
	*distance += jump_distances[jump_index];
}

RCKSmallSolveResult RCKSolveSmallJacobianKangaroo(EcPoint target, unsigned long long start, unsigned int range_bits, unsigned int jump_count, unsigned int dp_bits, unsigned int max_steps)
{
	RCKSmallSolveResult result;
	result.found = false;
	result.private_key = 0;
	result.target_index = 0;

	u64 limit = RangeLimit(range_bits);
	if (!limit || !max_steps)
		return result;
	if (jump_count < 2)
		jump_count = 2;
	if (jump_count > 32)
		jump_count = 32;

	std::vector<EcPoint> jumps;
	std::vector<u64> jump_distances;
	jumps.reserve(jump_count);
	jump_distances.reserve(jump_count);
	for (unsigned int i = 0; i < jump_count; i++)
	{
		u64 distance = JumpDistance(i);
		EcInt k;
		k.Set(distance);
		jump_distances.push_back(distance);
		jumps.push_back(Ec::MultiplyG(k));
	}

	u64 end = start + limit - 1;
	EcInt end_k;
	end_k.Set(end);
	JacobianPoint tame = JacobianFromAffine(Ec::MultiplyG(end_k));
	JacobianPoint wild = JacobianFromAffine(target);
	u64 tame_distance = end;
	u64 wild_distance = 0;
	std::vector<KangarooDp> table;
	table.reserve(max_steps + 2);

	for (unsigned int step = 0; step <= max_steps; step++)
	{
		EcPoint tame_affine = JacobianToAffine(tame);
		if (IsDistinguished(tame_affine, dp_bits))
		{
			std::string key = PointKey(tame_affine);
			u64 candidate = 0;
			if (CheckKangarooCollision(table, key, true, tame_distance, start, limit, target, &candidate))
			{
				result.found = true;
				result.private_key = candidate;
				return result;
			}
			RecordKangarooDp(table, key, true, tame_distance);
		}

		EcPoint wild_affine = JacobianToAffine(wild);
		if (IsDistinguished(wild_affine, dp_bits))
		{
			std::string key = PointKey(wild_affine);
			u64 candidate = 0;
			if (CheckKangarooCollision(table, key, false, wild_distance, start, limit, target, &candidate))
			{
				result.found = true;
				result.private_key = candidate;
				return result;
			}
			RecordKangarooDp(table, key, false, wild_distance);
		}

		KangarooStep(tame, &tame_distance, jumps, jump_distances);
		KangarooStep(wild, &wild_distance, jumps, jump_distances);
	}

	return result;
}

RCKSmallSolveResult RCKSolveSmallJacobianKangarooMulti(const std::vector<EcPoint>& targets, unsigned long long start, unsigned int range_bits, unsigned int jump_count, unsigned int dp_bits, unsigned int max_steps)
{
	RCKSmallSolveResult result;
	result.found = false;
	result.private_key = 0;
	result.target_index = 0;

	for (unsigned int target_index = 0; target_index < targets.size(); target_index++)
	{
		RCKSmallSolveResult one = RCKSolveSmallJacobianKangaroo(targets[target_index], start, range_bits, jump_count, dp_bits, max_steps);
		if (one.found)
		{
			one.target_index = target_index;
			return one;
		}
	}

	return result;
}

std::string RCKJacobianPointAddBenchJson(unsigned int iterations, unsigned int min_ms)
{
	if (!iterations)
		iterations = 1;

	EcInt one;
	one.Set(1);
	EcPoint g = Ec::MultiplyG(one);
	JacobianPoint p = JacobianFromAffine(Ec::DoublePoint(g));

	u64 checksum = 0;
	u64 operations = 0;
	auto t0 = std::chrono::steady_clock::now();
	auto t1 = t0;
	do
	{
		for (unsigned int i = 0; i < iterations; i++)
		{
			p = JacobianAddAffine(p, g);
			checksum = MixJacobianChecksum(checksum, p, operations + i);
		}
		operations += iterations;
		t1 = std::chrono::steady_clock::now();
	} while (min_ms && (std::chrono::duration<double, std::milli>(t1 - t0).count() < (double)min_ms));

	EcPoint final_point = JacobianToAffine(p);
	EcInt expected_k;
	expected_k.Set(operations + 2);
	EcPoint expected = Ec::MultiplyG(expected_k);
	bool correctness = PointMatches(final_point, expected);

	u64 reference_iterations = operations < 8192 ? operations : 8192;
	EcPoint affine = Ec::DoublePoint(g);
	auto r0 = std::chrono::steady_clock::now();
	for (u64 i = 0; i < reference_iterations; i++)
		affine = Ec::AddPoints(affine, g);
	auto r1 = std::chrono::steady_clock::now();

	double seconds = std::chrono::duration<double>(t1 - t0).count();
	double reference_seconds = std::chrono::duration<double>(r1 - r0).count();
	double ops_per_sec = seconds > 0 ? operations / seconds : 0.0;
	double reference_ops_per_sec = reference_seconds > 0 ? reference_iterations / reference_seconds : 0.0;

	std::ostringstream out;
	out.setf(std::ios::fixed);
	out.precision(6);
	out << "{\"backend\":\"macos_cpu\",";
	out << "\"operation\":\"jacobian_point_add_g\",";
	out << "\"iterations\":" << operations << ",";
	out << "\"sample_count\":" << iterations << ",";
	out << "\"min_ms\":" << min_ms << ",";
	out << "\"seconds\":" << seconds << ",";
	out << "\"ops_per_sec\":" << ops_per_sec << ",";
	out << "\"reference_backend\":\"affine_point_add_g\",";
	out << "\"reference_iterations\":" << reference_iterations << ",";
	out << "\"reference_seconds\":" << reference_seconds << ",";
	out << "\"reference_ops_per_sec\":" << reference_ops_per_sec << ",";
	out << "\"speedup_vs_affine\":" << (reference_ops_per_sec > 0.0 ? ops_per_sec / reference_ops_per_sec : 0.0) << ",";
	out << "\"checksum\":\"0x" << std::hex << checksum << std::dec << "\",";
	out << "\"final_scalar\":\"0x" << std::hex << (operations + 2) << std::dec << "\",";
	out << "\"correctness\":" << (correctness ? "true" : "false");
	if (!correctness)
		out << ",\"reason\":\"final point mismatch against MultiplyG reference\"";
	out << "}";
	return out.str();
}
