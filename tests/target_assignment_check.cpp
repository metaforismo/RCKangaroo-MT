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

	require(TTargetSet::CoverageCycleCount(0, 16) == 0, "zero active coverage cycle count");
	require(TTargetSet::CoverageCycleCount(8, 16) == 2, "two coverage cycles");
	require(TTargetSet::CoverageCycleCount(3, 10) == 4, "ceil coverage cycles");
	require(TTargetSet::CoverageCycleCount(32, 10) == 1, "dense active coverage cycle count");

	std::vector<unsigned char> cycled16(16, 0);
	u64 cycles16 = TTargetSet::CoverageCycleCount(4, 16);
	for (u64 cycle = 0; cycle < cycles16; cycle++)
		for (u64 i = 0; i < 4; i++)
			cycled16[TTargetSet::MapCycledActiveWildTargetId(i, 4, 16, cycle)]++;
	for (int i = 0; i < 16; i++)
		require(cycled16[i] == 1, "cycled windows must cover each divisible target once");

	std::vector<unsigned char> cycled10(10, 0);
	u64 cycles10 = TTargetSet::CoverageCycleCount(3, 10);
	for (u64 cycle = 0; cycle < cycles10; cycle++)
		for (u64 i = 0; i < 3; i++)
			cycled10[TTargetSet::MapCycledActiveWildTargetId(i, 3, 10, cycle)]++;
	for (int i = 0; i < 10; i++)
		require(cycled10[i] >= 1, "cycled windows must cover each non-divisible target");
	require(cycled10[0] == 2 && cycled10[1] == 2 && cycled10[2] == 1, "cycled remainder must wrap predictably");

	std::puts("target assignment mapping ok");
	return 0;
}
