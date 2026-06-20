#include "macos/RCKMac.h"

#include <chrono>
#include <cmath>
#include <sstream>
#include <utility>

static bool IntMatches(const EcInt& a, const EcInt& b)
{
	for (unsigned int i = 0; i < 5; i++)
	{
		if (a.data[i] != b.data[i])
			return false;
	}
	return true;
}

static bool IntIsZero(const EcInt& a)
{
	for (unsigned int i = 0; i < 5; i++)
	{
		if (a.data[i])
			return false;
	}
	return true;
}

static bool PointMatches(const EcPoint& a, const EcPoint& b)
{
	return IntMatches(a.x, b.x) && IntMatches(a.y, b.y);
}

static const char* FieldRhsPassingMode()
{
	return "const_ref";
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

static EcInt FieldAdd(EcInt a, const EcInt& b)
{
	a.AddModP(b);
	return a;
}

static EcInt FieldSub(EcInt a, const EcInt& b)
{
	a.SubModP(b);
	return a;
}

static EcInt FieldMul(EcInt a, const EcInt& b)
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

static bool IsPowerOfTwo(unsigned int value)
{
	return value && ((value & (value - 1)) == 0);
}

static const char* JumpIndexMode(unsigned int jump_count)
{
	return IsPowerOfTwo(jump_count) ? "power2_mask" : "modulo";
}

static unsigned int JacobianJumpIndex(const JacobianPoint& p, unsigned int jump_count)
{
	u64 mixed = p.x.data[0] ^ (p.x.data[1] << 7) ^ (p.y.data[0] >> 3) ^ p.z.data[0];
	mixed ^= mixed >> 33;
	mixed *= 0xff51afd7ed558ccdULL;
	mixed ^= mixed >> 33;
	if (IsPowerOfTwo(jump_count))
		return (unsigned int)(mixed & (jump_count - 1));
	return (unsigned int)(mixed % jump_count);
}

static u64 JumpDistance(unsigned int index)
{
	return 1ull << index;
}

struct KangarooJumpTable
{
	std::vector<EcPoint> points;
	std::vector<u64> distances;
};

static unsigned int NormalizeJumpCount(unsigned int jump_count)
{
	if (jump_count < 2)
		return 2;
	if (jump_count > 32)
		return 32;
	return jump_count;
}

static KangarooJumpTable BuildKangarooJumpTable(unsigned int jump_count)
{
	jump_count = NormalizeJumpCount(jump_count);

	KangarooJumpTable table;
	table.points.reserve(jump_count);
	table.distances.reserve(jump_count);
	for (unsigned int i = 0; i < jump_count; i++)
	{
		u64 distance = JumpDistance(i);
		EcInt k;
		k.Set(distance);
		table.distances.push_back(distance);
		table.points.push_back(Ec::MultiplyG(k));
	}
	return table;
}

static JacobianPoint JacobianFromAffine(const EcPoint& p)
{
	JacobianPoint out;
	out.x = p.x;
	out.y = p.y;
	out.z.Set(1);
	out.infinity = false;
	return out;
}

static const char* JacobianStepPassingMode()
{
	return "const_ref";
}

static JacobianPoint JacobianDouble(const JacobianPoint& p)
{
	JacobianPoint out;
	if (p.infinity || IntIsZero(p.y))
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

static EcPoint JacobianToAffine(const JacobianPoint& p)
{
	EcPoint out;
	if (p.infinity || IntIsZero(p.z))
		return out;

	EcInt z_inv = p.z;
	z_inv.InvModP();
	EcInt z2 = FieldSquare(z_inv);
	EcInt z3 = FieldMul(z2, z_inv);
	out.x = FieldMul(p.x, z2);
	out.y = FieldMul(p.y, z3);
	return out;
}

static void JacobianAffineWithZInv(const JacobianPoint& p, const EcInt& z_inv, EcPoint& out)
{
	EcInt z2 = FieldSquare(z_inv);
	EcInt z3 = FieldMul(z2, z_inv);
	out.x = FieldMul(p.x, z2);
	out.y = FieldMul(p.y, z3);
}

static void JacobianPairToAffine(const JacobianPoint& a, const JacobianPoint& b, EcPoint& a_affine, EcPoint& b_affine)
{
	a_affine = EcPoint();
	b_affine = EcPoint();

	EcInt a_z = a.z;
	EcInt b_z = b.z;
	bool a_active = !a.infinity && !a_z.IsZero();
	bool b_active = !b.infinity && !b_z.IsZero();
	if (!a_active && !b_active)
		return;

	if (a_active && b_active)
	{
		EcInt product_inv = FieldMul(a_z, b_z);
		product_inv.InvModP();
		JacobianAffineWithZInv(a, FieldMul(product_inv, b_z), a_affine);
		JacobianAffineWithZInv(b, FieldMul(product_inv, a_z), b_affine);
		return;
	}

	EcInt z_inv = a_active ? a_z : b_z;
	z_inv.InvModP();
	if (a_active)
		JacobianAffineWithZInv(a, z_inv, a_affine);
	else
		JacobianAffineWithZInv(b, z_inv, b_affine);
}

static const char* JacobianBatchZAccessMode()
{
	return "const_ref";
}

static const char* JacobianBatchBufferMode()
{
	return "resize_reuse";
}

static const char* JacobianBatchActivePathMode()
{
	return "all_active_fast";
}

static void JacobianBatchToAffine(const JacobianPoint& tame, const std::vector<JacobianPoint>& wilds, std::vector<EcPoint>& affines, std::vector<EcInt>& prefixes, std::vector<unsigned char>& active)
{
	size_t point_count = wilds.size() + 1;
	affines.resize(point_count);
	prefixes.resize(point_count);
	active.resize(point_count);

	EcInt acc;
	acc.Set(1);
	bool all_active = true;
	for (size_t i = 0; i < point_count; i++)
	{
		const JacobianPoint& p = i ? wilds[i - 1] : tame;
		const EcInt& z = p.z;
		if (p.infinity || IntIsZero(z))
		{
			all_active = false;
			break;
		}

		prefixes[i] = acc;
		acc = FieldMul(acc, z);
	}

	if (all_active)
	{
		acc.InvModP();
		for (size_t remaining = point_count; remaining > 0; remaining--)
		{
			size_t i = remaining - 1;
			const JacobianPoint& p = i ? wilds[i - 1] : tame;
			EcInt z_inv = FieldMul(acc, prefixes[i]);
			acc = FieldMul(acc, p.z);
			EcInt z2 = FieldSquare(z_inv);
			EcInt z3 = FieldMul(z2, z_inv);
			affines[i].x = FieldMul(p.x, z2);
			affines[i].y = FieldMul(p.y, z3);
		}
		return;
	}

	acc.Set(1);
	unsigned int active_count = 0;
	for (size_t i = 0; i < point_count; i++)
	{
		const JacobianPoint& p = i ? wilds[i - 1] : tame;
		const EcInt& z = p.z;
		if (p.infinity || IntIsZero(z))
		{
			affines[i] = EcPoint();
			active[i] = 0;
			continue;
		}

		prefixes[i] = acc;
		acc = FieldMul(acc, z);
		active[i] = 1;
		active_count++;
	}

	if (!active_count)
		return;

	acc.InvModP();
	for (size_t remaining = point_count; remaining > 0; remaining--)
	{
		size_t i = remaining - 1;
		if (!active[i])
			continue;

		const JacobianPoint& p = i ? wilds[i - 1] : tame;
		EcInt z_inv = FieldMul(acc, prefixes[i]);
		acc = FieldMul(acc, p.z);
		EcInt z2 = FieldSquare(z_inv);
		EcInt z3 = FieldMul(z2, z_inv);
		affines[i].x = FieldMul(p.x, z2);
		affines[i].y = FieldMul(p.y, z3);
	}
}

static JacobianPoint JacobianAddAffine(const JacobianPoint& p, const EcPoint& q)
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

struct KangarooRangeContext
{
	u64 start;
	u64 limit;
	u64 end;
	JacobianPoint tame_start;
};

static KangarooRangeContext BuildKangarooRangeContext(unsigned long long start, unsigned int range_bits)
{
	KangarooRangeContext context;
	context.start = start;
	context.limit = RangeLimit(range_bits);
	context.end = start;
	if (!context.limit)
		return context;

	context.end = start + context.limit - 1;
	EcInt end_k;
	end_k.Set(context.end);
	context.tame_start = JacobianFromAffine(Ec::MultiplyG(end_k));
	return context;
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

RCKSmallSolveResult RCKSolveSmallSingle(const EcPoint& target, unsigned long long start, unsigned int range_bits)
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
			const EcPoint& target = targets[target_index];
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
	out << "\"ecint_carry_impl\":\"" << EcIntCarryImplMode() << "\",";
	out << "\"jacobian_step_passing\":\"" << JacobianStepPassingMode() << "\",";
	out << "\"jump_index\":\"" << JumpIndexMode(jump_count) << "\",";
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

struct KangarooPointKey
{
	u64 x[4];
	u64 y_parity;

	bool operator==(const KangarooPointKey& other) const
	{
		if (y_parity != other.y_parity)
			return false;
		for (unsigned int i = 0; i < 4; i++)
		{
			if (x[i] != other.x[i])
				return false;
		}
		return true;
	}
};

struct KangarooPointKeyHash
{
	size_t operator()(const KangarooPointKey& key) const
	{
		return (size_t)(key.x[0] ^ (key.y_parity << 63) ^ (key.x[1] >> 7) ^ (key.x[2] << 17));
	}
};

static const char* KangarooDpHashMode()
{
	return "partial_limb_mix";
}

static const char* KangarooDpKeyMode()
{
	return "x_parity";
}

struct KangarooDp
{
	u64 distance;
	bool tame;
	unsigned int target_index;
};

struct KangarooDpBucket
{
	KangarooDp first;
	bool has_first;
	std::vector<KangarooDp> overflow;

	KangarooDpBucket() : has_first(false)
	{
	}

	void Clear()
	{
		has_first = false;
		overflow.clear();
	}
};

struct KangarooDpSlot
{
	KangarooPointKey key;
	KangarooDpBucket bucket;
	bool occupied;

	KangarooDpSlot() : occupied(false)
	{
	}
};

struct KangarooDpTable
{
	std::vector<KangarooDpSlot> slots;
	std::vector<size_t> occupied_slots;
	size_t mask;

	KangarooDpTable() : mask(0)
	{
	}

	static size_t CapacityFor(size_t reserve)
	{
		size_t wanted = reserve < 4 ? 8 : reserve * 2;
		size_t capacity = 8;
		while (capacity < wanted)
			capacity <<= 1;
		return capacity;
	}

	static size_t IndexHash(const KangarooPointKey& key)
	{
		size_t h = KangarooPointKeyHash()(key);
		h ^= h >> 33;
		h *= (size_t)0xff51afd7ed558ccdULL;
		h ^= h >> 33;
		return h;
	}

	void Clear(size_t reserve)
	{
		size_t capacity = CapacityFor(reserve);
		if (slots.size() != capacity)
		{
			slots.clear();
			slots.resize(capacity);
			occupied_slots.clear();
			occupied_slots.reserve(reserve);
			mask = capacity - 1;
			return;
		}

		for (size_t i = 0; i < occupied_slots.size(); i++)
		{
			KangarooDpSlot& slot = slots[occupied_slots[i]];
			slot.occupied = false;
			slot.bucket.Clear();
		}
		occupied_slots.clear();
		if (occupied_slots.capacity() < reserve)
			occupied_slots.reserve(reserve);
		mask = capacity - 1;
	}

	const KangarooDpBucket* Find(const KangarooPointKey& key) const
	{
		if (slots.empty())
			return 0;

		size_t index = IndexHash(key) & mask;
		while (slots[index].occupied)
		{
			if (slots[index].key == key)
				return &slots[index].bucket;
			index = (index + 1) & mask;
		}
		return 0;
	}

	KangarooDpBucket& FindOrInsert(const KangarooPointKey& key)
	{
		if (slots.empty())
			Clear(8);
		if ((occupied_slots.size() + 1) * 2 > slots.size())
			Rehash(slots.size() * 2);

		size_t index = IndexHash(key) & mask;
		while (slots[index].occupied)
		{
			if (slots[index].key == key)
				return slots[index].bucket;
			index = (index + 1) & mask;
		}

		KangarooDpSlot& slot = slots[index];
		slot.key = key;
		slot.bucket.Clear();
		slot.occupied = true;
		occupied_slots.push_back(index);
		return slot.bucket;
	}

	void Rehash(size_t capacity)
	{
		std::vector<KangarooDpSlot> old_slots;
		old_slots.swap(slots);
		slots.resize(capacity);
		occupied_slots.clear();
		mask = capacity - 1;

		for (size_t old_index = 0; old_index < old_slots.size(); old_index++)
		{
			if (!old_slots[old_index].occupied)
				continue;

			size_t index = IndexHash(old_slots[old_index].key) & mask;
			while (slots[index].occupied)
				index = (index + 1) & mask;

			slots[index].key = old_slots[old_index].key;
			slots[index].bucket = std::move(old_slots[old_index].bucket);
			slots[index].occupied = true;
			occupied_slots.push_back(index);
		}
	}
};

struct KangarooSolveScratch
{
	KangarooDpTable buckets;
	std::vector<JacobianPoint> wilds;
	std::vector<u64> wild_distances;
	std::vector<EcPoint> affine_points;
	std::vector<EcInt> affine_prefixes;
	std::vector<unsigned char> affine_active;
};

static KangarooPointKey RawPointKey(const EcPoint& p)
{
	KangarooPointKey key;
	for (unsigned int i = 0; i < 4; i++)
		key.x[i] = p.x.data[i];
	key.y_parity = p.y.data[0] & 1;
	return key;
}

static bool IsDistinguished(const EcPoint& p, unsigned int dp_bits)
{
	if (!dp_bits)
		return true;
	if (dp_bits >= 63)
		dp_bits = 62;
	u64 mask = (1ull << dp_bits) - 1;
	return (p.x.data[0] & mask) == 0;
}

static const char* KangarooDpReserveMode()
{
	return "sqrt_range_estimate";
}

static const char* KangarooCandidateVerificationMode()
{
	return "full_point_collision";
}

static u64 CeilSqrtU64(u64 value)
{
	if (!value)
		return 0;

	u64 root = (u64)std::sqrt((double)value);
	while (root * root < value)
		root++;
	while (root && ((root - 1) * (root - 1) >= value))
		root--;
	return root;
}

static size_t EstimateKangarooDpReserve(u64 range_limit, unsigned int max_steps, unsigned int state_count, unsigned int dp_bits)
{
	u64 step_limit = (u64)max_steps + 2;
	if (range_limit)
	{
		u64 sqrt_step_limit = CeilSqrtU64(range_limit) + 2;
		if (sqrt_step_limit < step_limit)
			step_limit = sqrt_step_limit;
	}

	if (dp_bits)
	{
		if (dp_bits >= 63)
			dp_bits = 62;
		u64 stride = 1ull << dp_bits;
		step_limit = (step_limit + stride - 1) / stride;
		if (!step_limit)
			step_limit = 1;
	}

	u64 reserve = step_limit * (u64)state_count;
	u64 floor = (u64)state_count * 4;
	if (reserve < floor)
		reserve = floor;
	return (size_t)reserve;
}

static bool CheckKangarooDpCollision(const KangarooDp& other,
	bool tame,
	u64 distance,
	u64 start,
	u64 limit,
	u64* candidate)
{
	if (other.tame == tame)
		return false;

	u64 tame_distance = tame ? distance : other.distance;
	u64 wild_distance = tame ? other.distance : distance;
	if (tame_distance < wild_distance)
		return false;

	u64 found = tame_distance - wild_distance;
	if ((found < start) || (found >= start + limit))
		return false;

	*candidate = found;
	return true;
}

static bool CheckKangarooCollision(const KangarooDpTable& buckets,
	const KangarooPointKey& key,
	bool tame,
	u64 distance,
	u64 start,
	u64 limit,
	u64* candidate)
{
	const KangarooDpBucket* bucket = buckets.Find(key);
	if (!bucket)
		return false;

	if (bucket->has_first && CheckKangarooDpCollision(bucket->first, tame, distance, start, limit, candidate))
		return true;

	for (size_t i = 0; i < bucket->overflow.size(); i++)
	{
		if (CheckKangarooDpCollision(bucket->overflow[i], tame, distance, start, limit, candidate))
			return true;
	}
	return false;
}

static bool CheckKangarooMultiDpCollision(const KangarooDp& other,
	bool tame,
	unsigned int target_index,
	u64 distance,
	u64 start,
	u64 limit,
	const std::vector<EcPoint>& targets,
	u64* candidate,
	unsigned int* matched_target_index)
{
	if (other.tame == tame)
		return false;

	unsigned int check_target_index = tame ? other.target_index : target_index;
	if (check_target_index >= targets.size())
		return false;

	u64 tame_distance = tame ? distance : other.distance;
	u64 wild_distance = tame ? other.distance : distance;
	if (tame_distance < wild_distance)
		return false;

	u64 found = tame_distance - wild_distance;
	if ((found < start) || (found >= start + limit))
		return false;

	*candidate = found;
	*matched_target_index = check_target_index;
	return true;
}

static bool CheckKangarooMultiCollision(const KangarooDpTable& buckets,
	const KangarooPointKey& key,
	bool tame,
	unsigned int target_index,
	u64 distance,
	u64 start,
	u64 limit,
	const std::vector<EcPoint>& targets,
	u64* candidate,
	unsigned int* matched_target_index)
{
	const KangarooDpBucket* bucket = buckets.Find(key);
	if (!bucket)
		return false;

	if (bucket->has_first && CheckKangarooMultiDpCollision(bucket->first, tame, target_index, distance, start, limit, targets, candidate, matched_target_index))
		return true;

	for (size_t i = 0; i < bucket->overflow.size(); i++)
	{
		if (CheckKangarooMultiDpCollision(bucket->overflow[i], tame, target_index, distance, start, limit, targets, candidate, matched_target_index))
			return true;
	}
	return false;
}

static void RecordKangarooDp(KangarooDpTable& buckets, const KangarooPointKey& key, bool tame, u64 distance, unsigned int target_index, u64* dp_count)
{
	KangarooDp dp;
	dp.tame = tame;
	dp.distance = distance;
	dp.target_index = target_index;
	KangarooDpBucket& bucket = buckets.FindOrInsert(key);
	if (!bucket.has_first)
	{
		bucket.first = dp;
		bucket.has_first = true;
	}
	else
	{
		bucket.overflow.push_back(dp);
	}
	(*dp_count)++;
}

static void KangarooStep(JacobianPoint& p, u64* distance, const KangarooJumpTable& jumps)
{
	unsigned int jump_index = JacobianJumpIndex(p, (unsigned int)jumps.points.size());
	p = JacobianAddAffine(p, jumps.points[jump_index]);
	*distance += jumps.distances[jump_index];
}

static RCKSmallSolveResult RCKSolveSmallJacobianKangarooWithJumps(const EcPoint& target, const KangarooRangeContext& range, const KangarooJumpTable& jumps, KangarooSolveScratch& scratch, unsigned int dp_bits, unsigned int max_steps)
{
	RCKSmallSolveResult result;
	result.found = false;
	result.private_key = 0;
	result.target_index = 0;
	result.target_count = 1;
	result.tame_state_count = 1;
	result.wild_state_count = 1;

	if (!range.limit || !max_steps)
		return result;

	JacobianPoint tame = range.tame_start;
	JacobianPoint wild = JacobianFromAffine(target);
	u64 tame_distance = range.end;
	u64 wild_distance = 0;
	KangarooDpTable& buckets = scratch.buckets;
	buckets.Clear(EstimateKangarooDpReserve(range.limit, max_steps, 2, dp_bits));
	u64 dp_count = 0;

	for (unsigned int step = 0; step <= max_steps; step++)
	{
		EcPoint tame_affine;
		EcPoint wild_affine;
		JacobianPairToAffine(tame, wild, tame_affine, wild_affine);
		if (IsDistinguished(tame_affine, dp_bits))
		{
			KangarooPointKey key = RawPointKey(tame_affine);
			u64 candidate = 0;
			if (CheckKangarooCollision(buckets, key, true, tame_distance, range.start, range.limit, &candidate))
			{
				result.found = true;
				result.private_key = candidate;
				result.dp_count = (unsigned int)dp_count;
				return result;
			}
			RecordKangarooDp(buckets, key, true, tame_distance, 0, &dp_count);
		}

		if (IsDistinguished(wild_affine, dp_bits))
		{
			KangarooPointKey key = RawPointKey(wild_affine);
			u64 candidate = 0;
			if (CheckKangarooCollision(buckets, key, false, wild_distance, range.start, range.limit, &candidate))
			{
				result.found = true;
				result.private_key = candidate;
				result.dp_count = (unsigned int)dp_count;
				return result;
			}
			RecordKangarooDp(buckets, key, false, wild_distance, 0, &dp_count);
		}

		KangarooStep(tame, &tame_distance, jumps);
		KangarooStep(wild, &wild_distance, jumps);
	}

	result.dp_count = (unsigned int)dp_count;
	return result;
}

RCKSmallSolveResult RCKSolveSmallJacobianKangaroo(const EcPoint& target, unsigned long long start, unsigned int range_bits, unsigned int jump_count, unsigned int dp_bits, unsigned int max_steps)
{
	KangarooRangeContext range = BuildKangarooRangeContext(start, range_bits);
	KangarooJumpTable jumps = BuildKangarooJumpTable(jump_count);
	KangarooSolveScratch scratch;
	return RCKSolveSmallJacobianKangarooWithJumps(target, range, jumps, scratch, dp_bits, max_steps);
}

static RCKSmallSolveResult RCKSolveSmallJacobianKangarooMultiWithJumps(const std::vector<EcPoint>& targets, const KangarooRangeContext& range, const KangarooJumpTable& jumps, KangarooSolveScratch& scratch, unsigned int dp_bits, unsigned int max_steps)
{
	RCKSmallSolveResult result;
	result.target_count = (unsigned int)targets.size();
	result.tame_state_count = targets.empty() ? 0 : 1;
	result.wild_state_count = (unsigned int)targets.size();

	if (targets.empty() || !range.limit || !max_steps)
		return result;

	JacobianPoint tame = range.tame_start;
	u64 tame_distance = range.end;

	std::vector<JacobianPoint>& wilds = scratch.wilds;
	std::vector<u64>& wild_distances = scratch.wild_distances;
	wilds.clear();
	wild_distances.clear();
	wilds.reserve(targets.size());
	wild_distances.reserve(targets.size());
	for (size_t i = 0; i < targets.size(); i++)
	{
		wilds.push_back(JacobianFromAffine(targets[i]));
		wild_distances.push_back(0);
	}

	KangarooDpTable& buckets = scratch.buckets;
	buckets.Clear(EstimateKangarooDpReserve(range.limit, max_steps, (unsigned int)targets.size() + 1, dp_bits));
	u64 dp_count = 0;
	std::vector<EcPoint>& affine_points = scratch.affine_points;
	std::vector<EcInt>& affine_prefixes = scratch.affine_prefixes;
	std::vector<unsigned char>& affine_active = scratch.affine_active;
	affine_points.reserve(targets.size() + 1);
	affine_prefixes.reserve(targets.size() + 1);
	affine_active.reserve(targets.size() + 1);

	for (unsigned int step = 0; step <= max_steps; step++)
	{
		JacobianBatchToAffine(tame, wilds, affine_points, affine_prefixes, affine_active);

		const EcPoint& tame_affine = affine_points[0];
		if (IsDistinguished(tame_affine, dp_bits))
		{
			KangarooPointKey key = RawPointKey(tame_affine);
			u64 candidate = 0;
			unsigned int matched_target_index = 0;
			if (CheckKangarooMultiCollision(buckets, key, true, 0, tame_distance, range.start, range.limit, targets, &candidate, &matched_target_index))
			{
				result.found = true;
				result.private_key = candidate;
				result.target_index = matched_target_index;
				result.dp_count = (unsigned int)dp_count;
				return result;
			}
			RecordKangarooDp(buckets, key, true, tame_distance, 0, &dp_count);
		}

		for (unsigned int target_index = 0; target_index < wilds.size(); target_index++)
		{
			const EcPoint& wild_affine = affine_points[target_index + 1];
			if (IsDistinguished(wild_affine, dp_bits))
			{
				KangarooPointKey key = RawPointKey(wild_affine);
				u64 candidate = 0;
				unsigned int matched_target_index = 0;
				if (CheckKangarooMultiCollision(buckets, key, false, target_index, wild_distances[target_index], range.start, range.limit, targets, &candidate, &matched_target_index))
				{
					result.found = true;
					result.private_key = candidate;
					result.target_index = matched_target_index;
					result.dp_count = (unsigned int)dp_count;
					return result;
				}
				RecordKangarooDp(buckets, key, false, wild_distances[target_index], target_index, &dp_count);
			}
		}

		KangarooStep(tame, &tame_distance, jumps);
		for (unsigned int target_index = 0; target_index < wilds.size(); target_index++)
			KangarooStep(wilds[target_index], &wild_distances[target_index], jumps);
	}

	result.dp_count = (unsigned int)dp_count;
	return result;
}

RCKSmallSolveResult RCKSolveSmallJacobianKangarooMulti(const std::vector<EcPoint>& targets, unsigned long long start, unsigned int range_bits, unsigned int jump_count, unsigned int dp_bits, unsigned int max_steps)
{
	KangarooRangeContext range = BuildKangarooRangeContext(start, range_bits);
	KangarooJumpTable jumps = BuildKangarooJumpTable(jump_count);
	KangarooSolveScratch scratch;
	return RCKSolveSmallJacobianKangarooMultiWithJumps(targets, range, jumps, scratch, dp_bits, max_steps);
}

static std::vector<EcPoint> BuildSyntheticMultiTargets(unsigned int target_count, u64 start, u64 limit, u64 solved_private_key)
{
	std::vector<EcPoint> targets;
	targets.reserve(target_count);
	u64 end = start + limit - 1;

	for (unsigned int i = 0; i + 1 < target_count; i++)
	{
		u64 scalar = (i == 0 && start > 1) ? start - 1 : end + 17 + i;
		if (((scalar >= start) && (scalar < start + limit)) || (scalar == solved_private_key))
			scalar = end + 1024 + i;

		EcInt k;
		k.Set(scalar);
		targets.push_back(Ec::MultiplyG(k));
	}

	EcInt solved_k;
	solved_k.Set(solved_private_key);
	targets.push_back(Ec::MultiplyG(solved_k));
	return targets;
}

struct KangarooSingleBenchReference
{
	double ops_per_sec;
	bool correctness;
	std::string reason;
};

static KangarooSingleBenchReference MeasureSingleTargetKangarooSmall(unsigned int iterations, unsigned int min_ms, unsigned int range_bits, unsigned int jump_count, unsigned int dp_bits, unsigned int max_steps)
{
	KangarooSingleBenchReference reference;
	reference.ops_per_sec = 0.0;
	reference.correctness = true;

	if (!iterations)
		iterations = 1;

	u64 start = 0;
	u64 limit = RangeLimit(range_bits);
	if (!limit)
	{
		reference.correctness = false;
		reference.reason = "range_bits must be <= 24";
		return reference;
	}

	u64 solved_private_key = start + (limit > 7 ? 7 : limit - 1);
	EcInt solved_k;
	solved_k.Set(solved_private_key);
	EcPoint target = Ec::MultiplyG(solved_k);
	KangarooRangeContext range = BuildKangarooRangeContext(start, range_bits);
	KangarooJumpTable jumps = BuildKangarooJumpTable(jump_count);
	KangarooSolveScratch scratch;

	u64 operations = 0;
	auto t0 = std::chrono::steady_clock::now();
	auto t1 = t0;
	do
	{
		for (unsigned int i = 0; i < iterations; i++)
		{
			RCKSmallSolveResult result = RCKSolveSmallJacobianKangarooWithJumps(target, range, jumps, scratch, dp_bits, max_steps);
			operations++;
			if (!result.found || (result.private_key != solved_private_key) || (result.target_index != 0))
			{
				reference.correctness = false;
				reference.reason = "single-target reference solve mismatch";
			}
		}
		t1 = std::chrono::steady_clock::now();
	} while (min_ms && (std::chrono::duration<double, std::milli>(t1 - t0).count() < (double)min_ms));

	double seconds = std::chrono::duration<double>(t1 - t0).count();
	reference.ops_per_sec = seconds > 0 ? operations / seconds : 0.0;
	return reference;
}

std::string RCKJacobianKangarooSmallBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int range_bits, unsigned int jump_count, unsigned int dp_bits, unsigned int max_steps)
{
	if (!iterations)
		iterations = 1;

	u64 start = 0;
	u64 limit = RangeLimit(range_bits);
	bool correctness = true;
	std::string reason;
	if (!limit)
	{
		correctness = false;
		reason = "range_bits must be <= 24";
	}

	u64 solved_private_key = limit ? start + (limit > 7 ? 7 : limit - 1) : start;
	EcPoint target;
	if (limit)
	{
		EcInt solved_k;
		solved_k.Set(solved_private_key);
		target = Ec::MultiplyG(solved_k);
	}
	KangarooJumpTable jumps;
	if (limit)
		jumps = BuildKangarooJumpTable(jump_count);
	KangarooRangeContext range;
	if (limit)
		range = BuildKangarooRangeContext(start, range_bits);
	KangarooSolveScratch scratch;

	u64 operations = 0;
	u64 total_dp_count = 0;
	unsigned int last_dp_count = 0;
	unsigned int found_target_index = 0;
	u64 found_private_key = 0;
	auto t0 = std::chrono::steady_clock::now();
	auto t1 = t0;
	if (limit)
	{
		do
		{
			for (unsigned int i = 0; i < iterations; i++)
			{
				RCKSmallSolveResult result = RCKSolveSmallJacobianKangarooWithJumps(target, range, jumps, scratch, dp_bits, max_steps);
				operations++;
				last_dp_count = result.dp_count;
				total_dp_count += result.dp_count;
				found_target_index = result.target_index;
				found_private_key = result.private_key;
				if (!result.found || (result.private_key != solved_private_key) || (result.target_index != 0))
				{
					correctness = false;
					reason = "single-target solve mismatch";
				}
			}
			t1 = std::chrono::steady_clock::now();
		} while (min_ms && (std::chrono::duration<double, std::milli>(t1 - t0).count() < (double)min_ms));
	}

	double seconds = std::chrono::duration<double>(t1 - t0).count();
	double ops_per_sec = seconds > 0 ? operations / seconds : 0.0;
	double avg_dp_count = operations > 0 ? (double)total_dp_count / (double)operations : 0.0;

	std::ostringstream out;
	out.setf(std::ios::fixed);
	out.precision(6);
	out << "{\"backend\":\"macos_cpu\",";
	out << "\"operation\":\"jacobian_kangaroo_small\",";
	out << "\"architecture\":\"single_target\",";
	out << "\"ecint_carry_impl\":\"" << EcIntCarryImplMode() << "\",";
	out << "\"field_rhs_passing\":\"" << FieldRhsPassingMode() << "\",";
	out << "\"jacobian_step_passing\":\"" << JacobianStepPassingMode() << "\",";
	out << "\"dp_lookup\":\"open_address_linear\",";
	out << "\"dp_hash\":\"" << KangarooDpHashMode() << "\",";
	out << "\"dp_key\":\"" << KangarooDpKeyMode() << "\",";
	out << "\"candidate_verification\":\"" << KangarooCandidateVerificationMode() << "\",";
	out << "\"dp_reserve\":\"" << KangarooDpReserveMode() << "\",";
	out << "\"dp_bucket_storage\":\"inline_first\",";
	out << "\"point_passing\":\"const_ref\",";
	out << "\"affine_conversion\":\"batch\",";
	out << "\"jump_index\":\"" << JumpIndexMode(jump_count) << "\",";
	out << "\"jump_table\":\"precomputed\",";
	out << "\"scratch\":\"reused\",";
	out << "\"range_context\":\"precomputed\",";
	out << "\"iterations\":" << operations << ",";
	out << "\"sample_count\":" << iterations << ",";
	out << "\"min_ms\":" << min_ms << ",";
	out << "\"target_count\":1,";
	out << "\"tame_states\":1,";
	out << "\"wild_states\":1,";
	out << "\"range_bits\":" << range_bits << ",";
	out << "\"jump_count\":" << jump_count << ",";
	out << "\"dp_bits\":" << dp_bits << ",";
	out << "\"max_steps\":" << max_steps << ",";
	out << "\"seconds\":" << seconds << ",";
	out << "\"ops_per_sec\":" << ops_per_sec << ",";
	out << "\"avg_dp_count\":" << avg_dp_count << ",";
	out << "\"last_dp_count\":" << last_dp_count << ",";
	out << "\"start_scalar\":\"0x" << std::hex << start << std::dec << "\",";
	out << "\"expected_private_key\":\"0x" << std::hex << solved_private_key << std::dec << "\",";
	out << "\"found_target_index\":" << found_target_index << ",";
	out << "\"found_private_key\":\"0x" << std::hex << found_private_key << std::dec << "\",";
	out << "\"correctness\":" << (correctness ? "true" : "false");
	if (!correctness)
		out << ",\"reason\":\"" << reason << "\"";
	out << "}";
	return out.str();
}

std::string RCKJacobianKangarooMultiSmallBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int target_count, unsigned int range_bits, unsigned int jump_count, unsigned int dp_bits, unsigned int max_steps)
{
	if (!iterations)
		iterations = 1;
	if (!target_count)
		target_count = 1;
	if (target_count > 64)
		target_count = 64;

	u64 start = 2;
	u64 limit = RangeLimit(range_bits);
	bool correctness = true;
	std::string reason;
	if (!limit)
	{
		correctness = false;
		reason = "range_bits must be <= 24";
	}

	u64 solved_private_key = limit ? start + (limit > 5 ? 5 : limit - 1) : start;
	std::vector<EcPoint> targets;
	if (limit)
		targets = BuildSyntheticMultiTargets(target_count, start, limit, solved_private_key);
	KangarooJumpTable jumps;
	if (limit)
		jumps = BuildKangarooJumpTable(jump_count);
	KangarooRangeContext range;
	if (limit)
		range = BuildKangarooRangeContext(start, range_bits);
	KangarooSingleBenchReference single_reference = MeasureSingleTargetKangarooSmall(iterations, min_ms, range_bits, jump_count, dp_bits, max_steps);
	if (limit && !single_reference.correctness)
	{
		correctness = false;
		reason = single_reference.reason;
	}

	u64 operations = 0;
	u64 total_dp_count = 0;
	unsigned int last_dp_count = 0;
	unsigned int found_target_index = 0;
	u64 found_private_key = 0;
	KangarooSolveScratch scratch;
	auto t0 = std::chrono::steady_clock::now();
	auto t1 = t0;
	if (limit)
	{
		do
		{
			for (unsigned int i = 0; i < iterations; i++)
			{
				RCKSmallSolveResult result = RCKSolveSmallJacobianKangarooMultiWithJumps(targets, range, jumps, scratch, dp_bits, max_steps);
				operations++;
				last_dp_count = result.dp_count;
				total_dp_count += result.dp_count;
				found_target_index = result.target_index;
				found_private_key = result.private_key;
				if (!result.found || (result.private_key != solved_private_key) || (result.target_index != target_count - 1))
				{
					correctness = false;
					reason = "shared-tame multi-target solve mismatch";
				}
			}
			t1 = std::chrono::steady_clock::now();
		} while (min_ms && (std::chrono::duration<double, std::milli>(t1 - t0).count() < (double)min_ms));
	}

	double seconds = std::chrono::duration<double>(t1 - t0).count();
	double ops_per_sec = seconds > 0 ? operations / seconds : 0.0;
	double avg_dp_count = operations > 0 ? (double)total_dp_count / (double)operations : 0.0;
	double speedup_vs_single = single_reference.ops_per_sec > 0.0 ? ops_per_sec / single_reference.ops_per_sec : 0.0;
	double target_throughput_vs_single = single_reference.ops_per_sec > 0.0 ? (ops_per_sec * (double)target_count) / single_reference.ops_per_sec : 0.0;

	std::ostringstream out;
	out.setf(std::ios::fixed);
	out.precision(6);
	out << "{\"backend\":\"macos_cpu\",";
	out << "\"operation\":\"jacobian_kangaroo_multi_small\",";
	out << "\"architecture\":\"shared_tame\",";
	out << "\"ecint_carry_impl\":\"" << EcIntCarryImplMode() << "\",";
	out << "\"field_rhs_passing\":\"" << FieldRhsPassingMode() << "\",";
	out << "\"jacobian_step_passing\":\"" << JacobianStepPassingMode() << "\",";
	out << "\"dp_lookup\":\"open_address_linear\",";
	out << "\"dp_hash\":\"" << KangarooDpHashMode() << "\",";
	out << "\"dp_key\":\"" << KangarooDpKeyMode() << "\",";
	out << "\"candidate_verification\":\"" << KangarooCandidateVerificationMode() << "\",";
	out << "\"dp_reserve\":\"" << KangarooDpReserveMode() << "\",";
	out << "\"dp_bucket_storage\":\"inline_first\",";
	out << "\"point_passing\":\"const_ref\",";
	out << "\"affine_conversion\":\"batch\",";
	out << "\"affine_z_access\":\"" << JacobianBatchZAccessMode() << "\",";
	out << "\"affine_buffer\":\"" << JacobianBatchBufferMode() << "\",";
	out << "\"affine_active_path\":\"" << JacobianBatchActivePathMode() << "\",";
	out << "\"jump_index\":\"" << JumpIndexMode(jump_count) << "\",";
	out << "\"jump_table\":\"precomputed\",";
	out << "\"scratch\":\"reused\",";
	out << "\"range_context\":\"precomputed\",";
	out << "\"iterations\":" << operations << ",";
	out << "\"sample_count\":" << iterations << ",";
	out << "\"min_ms\":" << min_ms << ",";
	out << "\"target_count\":" << target_count << ",";
	out << "\"tame_states\":1,";
	out << "\"wild_states\":" << target_count << ",";
	out << "\"range_bits\":" << range_bits << ",";
	out << "\"jump_count\":" << jump_count << ",";
	out << "\"dp_bits\":" << dp_bits << ",";
	out << "\"max_steps\":" << max_steps << ",";
	out << "\"seconds\":" << seconds << ",";
	out << "\"ops_per_sec\":" << ops_per_sec << ",";
	out << "\"single_target_ops_per_sec\":" << single_reference.ops_per_sec << ",";
	out << "\"speedup_vs_single\":" << speedup_vs_single << ",";
	out << "\"target_throughput_vs_single\":" << target_throughput_vs_single << ",";
	out << "\"avg_dp_count\":" << avg_dp_count << ",";
	out << "\"last_dp_count\":" << last_dp_count << ",";
	out << "\"start_scalar\":\"0x" << std::hex << start << std::dec << "\",";
	out << "\"expected_private_key\":\"0x" << std::hex << solved_private_key << std::dec << "\",";
	out << "\"found_target_index\":" << found_target_index << ",";
	out << "\"found_private_key\":\"0x" << std::hex << found_private_key << std::dec << "\",";
	out << "\"correctness\":" << (correctness ? "true" : "false");
	if (!correctness)
		out << ",\"reason\":\"" << reason << "\"";
	out << "}";
	return out.str();
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

std::string RCKJacobianBatchAffineBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int batch_points)
{
	if (!iterations)
		iterations = 1;
	if (batch_points < 2)
		batch_points = 2;
	if (batch_points > 129)
		batch_points = 129;

	std::vector<EcPoint> expected;
	std::vector<JacobianPoint> wilds;
	expected.reserve(batch_points);
	wilds.reserve(batch_points - 1);

	for (unsigned int i = 0; i < batch_points; i++)
	{
		EcInt k;
		k.Set((u64)i + 2);
		EcPoint p = Ec::MultiplyG(k);
		expected.push_back(p);
		if (i > 0)
			wilds.push_back(JacobianFromAffine(p));
	}

	JacobianPoint tame = JacobianFromAffine(expected[0]);
	std::vector<EcPoint> affines;
	std::vector<EcInt> prefixes;
	std::vector<unsigned char> active;
	affines.reserve(batch_points);
	prefixes.reserve(batch_points);
	active.reserve(batch_points);

	u64 checksum = 0;
	u64 operations = 0;
	auto t0 = std::chrono::steady_clock::now();
	auto t1 = t0;
	do
	{
		for (unsigned int i = 0; i < iterations; i++)
		{
			JacobianBatchToAffine(tame, wilds, affines, prefixes, active);
			for (size_t point_index = 0; point_index < affines.size(); point_index++)
				checksum = MixPointChecksum(checksum, affines[point_index], operations + i + point_index);
		}
		operations += iterations;
		t1 = std::chrono::steady_clock::now();
	} while (min_ms && (std::chrono::duration<double, std::milli>(t1 - t0).count() < (double)min_ms));

	bool correctness = affines.size() == expected.size();
	for (size_t i = 0; correctness && (i < expected.size()); i++)
		correctness = PointMatches(affines[i], expected[i]);

	double seconds = std::chrono::duration<double>(t1 - t0).count();
	double ops_per_sec = seconds > 0 ? operations / seconds : 0.0;
	double points_per_sec = seconds > 0 ? (operations * (double)batch_points) / seconds : 0.0;

	std::ostringstream out;
	out.setf(std::ios::fixed);
	out.precision(6);
	out << "{\"backend\":\"macos_cpu\",";
	out << "\"operation\":\"jacobian_batch_affine\",";
	out << "\"field_rhs_passing\":\"" << FieldRhsPassingMode() << "\",";
	out << "\"affine_conversion\":\"batch\",";
	out << "\"affine_z_access\":\"" << JacobianBatchZAccessMode() << "\",";
	out << "\"affine_buffer\":\"" << JacobianBatchBufferMode() << "\",";
	out << "\"affine_active_path\":\"" << JacobianBatchActivePathMode() << "\",";
	out << "\"batch_points\":" << batch_points << ",";
	out << "\"wild_points\":" << (batch_points - 1) << ",";
	out << "\"iterations\":" << operations << ",";
	out << "\"sample_count\":" << iterations << ",";
	out << "\"min_ms\":" << min_ms << ",";
	out << "\"seconds\":" << seconds << ",";
	out << "\"ops_per_sec\":" << ops_per_sec << ",";
	out << "\"points_per_sec\":" << points_per_sec << ",";
	out << "\"checksum\":\"0x" << std::hex << checksum << std::dec << "\",";
	out << "\"correctness\":" << (correctness ? "true" : "false");
	if (!correctness)
		out << ",\"reason\":\"batch affine output mismatch against scalar affine references\"";
	out << "}";
	return out.str();
}
