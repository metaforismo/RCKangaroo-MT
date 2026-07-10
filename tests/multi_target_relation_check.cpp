#include "Ec.h"

#include <cstdio>
#include <cstdlib>

struct Relation
{
	int sign;
	i64 offset;
};

static void require(bool ok, const char* message)
{
	if (!ok)
	{
		std::fprintf(stderr, "%s\n", message);
		std::exit(1);
	}
}

static int wild_sign(int type)
{
	require(type == WILD1 || type == WILD2, "relation endpoints must be wild kangaroos");
	return type == WILD1 ? 1 : -1;
}

// For an x-coordinate collision, epsilon is +1 for equal points and -1 for
// opposite points. The centered target scalars then satisfy a_j = sign*a_i + offset.
static Relation derive_relation(int type_i, i64 distance_i, int type_j, i64 distance_j, int epsilon)
{
	require(epsilon == 1 || epsilon == -1, "collision orientation must be signed");
	const int sigma_i = wild_sign(type_i);
	const int sigma_j = wild_sign(type_j);
	return {
		epsilon * sigma_i * sigma_j,
		sigma_j * (epsilon * distance_i - distance_j),
	};
}

static EcPoint signed_multiple(i64 scalar)
{
	require(scalar != 0, "test scalar must be non-zero");
	EcInt magnitude;
	magnitude.Set((u64)(scalar < 0 ? -scalar : scalar));
	EcPoint point = Ec::MultiplyG(magnitude);
	if (scalar < 0)
		point.y.NegModP();
	return point;
}

static EcPoint wild_point(int type, i64 centered_scalar, i64 distance)
{
	EcPoint target_component = signed_multiple(wild_sign(type) * centered_scalar);
	EcPoint distance_component = signed_multiple(distance);
	return Ec::AddPoints(target_component, distance_component);
}

static Relation make_collision_relation(
	int type_i,
	i64 centered_i,
	i64 distance_i,
	int type_j,
	i64 centered_j,
	int epsilon)
{
	const i64 state_i = wild_sign(type_i) * centered_i + distance_i;
	const i64 distance_j = epsilon * state_i - wild_sign(type_j) * centered_j;
	EcPoint point_i = wild_point(type_i, centered_i, distance_i);
	EcPoint point_j = wild_point(type_j, centered_j, distance_j);

	require(point_i.x.IsEqual(point_j.x), "constructed wild points must collide in x");
	const bool same_y_parity = (point_i.y.data[0] & 1) == (point_j.y.data[0] & 1);
	require(same_y_parity == (epsilon == 1), "one y parity bit must recover collision orientation");

	Relation relation = derive_relation(type_i, distance_i, type_j, distance_j, epsilon);
	require(centered_j == relation.sign * centered_i + relation.offset, "derived relation must recover the second centered scalar");
	return relation;
}

int main()
{
	InitEc();

	const i64 centered_i = 37;
	const i64 centered_j = 61;
	const i64 distance_i = 211;
	for (int type_i = WILD1; type_i <= WILD2; ++type_i)
		for (int type_j = WILD1; type_j <= WILD2; ++type_j)
			for (int epsilon : {-1, 1})
				make_collision_relation(type_i, centered_i, distance_i, type_j, centered_j, epsilon);

	// Three independently valid cross-target collisions form a signed cycle.
	// A negative cycle has a unique scalar solution because a_0 = -a_0 + C.
	Relation edge01 = make_collision_relation(WILD1, 37, 211, WILD2, 61, 1);
	Relation edge12 = make_collision_relation(WILD2, 61, 173, WILD1, 83, 1);
	Relation edge20 = make_collision_relation(WILD1, 83, 197, WILD1, 37, -1);
	const int cycle_sign = edge20.sign * edge12.sign * edge01.sign;
	const i64 cycle_offset = edge20.sign * edge12.sign * edge01.offset
		+ edge20.sign * edge12.offset + edge20.offset;
	require(cycle_sign == -1, "test cycle must have negative sign parity");
	require((cycle_offset % 2) == 0, "negative cycle offset must be divisible by two");
	require(cycle_offset / 2 == 37, "negative relation cycle must recover the anchored centered scalar");

	// A positive cycle is only a consistency check and must not claim a key.
	Relation positive20 = make_collision_relation(WILD1, 83, 197, WILD1, 37, 1);
	const int positive_sign = positive20.sign * edge12.sign * edge01.sign;
	const i64 positive_offset = positive20.sign * edge12.sign * edge01.offset
		+ positive20.sign * edge12.offset + positive20.offset;
	require(positive_sign == 1, "control cycle must have positive sign parity");
	require(positive_offset == 0, "positive relation cycle must close without inventing a scalar");

	std::printf("multi-target signed relation oracle ok\n");
	return 0;
}
