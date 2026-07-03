#include <stdio.h>

#include "Ec.h"

static int fail(const char* msg)
{
	printf("%s\n", msg);
	return 1;
}

int main()
{
	InitEc();
	EcInt one, two, three;
	one.Set(1);
	two.Set(2);
	three.Set(3);

	EcPoint g = Ec::MultiplyG(one);
	EcPoint two_g = Ec::MultiplyG(two);
	EcPoint two_g_by_double = Ec::DoublePoint(g);
	EcPoint three_g = Ec::MultiplyG(three);
	EcPoint three_g_by_add = Ec::AddPoints(two_g, g);
	EcPoint lower_g;
	EcInt lower_scalar;

	if (!two_g.IsEqual(two_g_by_double))
		return fail("2G mismatch");
	if (!three_g.IsEqual(three_g_by_add))
		return fail("3G mismatch");
	if (!lower_g.SetHexStr("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"))
		return fail("lowercase compressed G parse failed");
	if (!lower_g.IsEqual(g))
		return fail("lowercase compressed G mismatch");
	if (!lower_scalar.SetHexStr("0a") || lower_scalar.data[0] != 10)
		return fail("lowercase scalar hex parse failed");

	DeInitEc();
	printf("ec vectors ok\n");
	return 0;
}
