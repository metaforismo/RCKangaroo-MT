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

	if (!two_g.IsEqual(two_g_by_double))
		return fail("2G mismatch");
	if (!three_g.IsEqual(three_g_by_add))
		return fail("3G mismatch");

	DeInitEc();
	printf("ec vectors ok\n");
	return 0;
}
