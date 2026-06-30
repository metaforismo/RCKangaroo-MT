#include "TargetSet.h"

#include <cstdio>
#include <cstdlib>
#include <vector>

static void require(bool ok, const char* msg)
{
	if (!ok)
	{
		std::fprintf(stderr, "%s\n", msg);
		std::exit(1);
	}
}

int main()
{
	require(TTargetSet::MapActiveWildTargetId(0, 0, 10) == 0, "zero active slots must map safely");
	require(TTargetSet::MapActiveWildTargetId(0, 4, 8) == 0, "single gpu map slot 0");
	require(TTargetSet::MapActiveWildTargetId(1, 4, 8) == 2, "single gpu map slot 1");
	require(TTargetSet::MapActiveWildTargetId(2, 4, 8) == 4, "single gpu map slot 2");
	require(TTargetSet::MapActiveWildTargetId(3, 4, 8) == 6, "single gpu map slot 3");
	require(TTargetSet::MapActiveWildTargetId(9, 4, 8) == 6, "out-of-range active slot must clamp");

	std::vector<unsigned char> seen(16, 0);
	for (u64 i = 0; i < 4; i++)
		seen[TTargetSet::MapActiveWildTargetId(i, 8, 16)]++;
	for (u64 i = 0; i < 4; i++)
		seen[TTargetSet::MapActiveWildTargetId(4 + i, 8, 16)]++;
	for (int i = 0; i < 16; i += 2)
		require(seen[i] == 1, "two gpu shards must cover each active target once");
	for (int i = 1; i < 16; i += 2)
		require(seen[i] == 0, "two gpu shards must not invent extra active targets");

	std::vector<unsigned char> dense(3, 0);
	for (u64 i = 0; i < 8; i++)
		dense[TTargetSet::MapActiveWildTargetId(i, 8, 3)]++;
	require(dense[0] && dense[1] && dense[2], "dense active slots must cover all targets");

	std::puts("target assignment mapping ok");
	return 0;
}
