#include "TargetSet.h"

#include <cstdio>
#include <cstdlib>
#include <fstream>
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
	InitEc();

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

	const char* target_path = "/tmp/rckangaroo-targetset-map-check.txt";
	{
		std::ofstream out(target_path);
		out << "# comment\n\n";
		out << "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798\n";
		out << "  0379BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798  \n";
	}

	EcInt start;
	start.Set(2);
	EcPoint neg_start = Ec::MultiplyG(start);
	neg_start.y.NegModP();

	EcPoint expected0;
	require(expected0.SetHexStr("0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"), "valid expected compressed target 0");
	expected0 = Ec::AddPoints(expected0, neg_start);
	EcPoint expected1;
	require(expected1.SetHexStr("0379BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"), "valid expected compressed target 1");
	expected1 = Ec::AddPoints(expected1, neg_start);

	TTargetSet loaded;
	require(loaded.LoadFromFile(target_path, start), "target set with start offset must load");
	require(loaded.Count() == 2, "target set with start offset must preserve target count");
	EcPoint got0 = loaded.GetPoint(0);
	EcPoint got1 = loaded.GetPoint(1);
	require(got0.IsEqual(expected0), "batched target start mapping must match legacy add for target 0");
	require(got1.IsEqual(expected1), "batched target start mapping must match legacy add for target 1");
	require(loaded.GetSourceLine(0) == 3, "target source line 0 must survive batched mapping");
	require(loaded.GetSourceLine(1) == 4, "target source line 1 must survive batched mapping");
	std::remove(target_path);

	const u32 large_count = 32770;
	const u32 boundary_index = 32768;
	{
		std::ofstream out(target_path);
		out << "# batch-boundary check\n";
		for (u32 i = 0; i < large_count; i++)
		{
			out << ((i & 1) ?
				"0379BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798" :
				"0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798") << "\n";
		}
	}
	TTargetSet large_loaded;
	require(large_loaded.LoadFromFile(target_path, start), "large target set with start offset must load");
	require(large_loaded.Count() == large_count, "large target set must preserve target count across batch boundary");
	require(large_loaded.GetPoint(0).IsEqual(expected0), "large batch first target must match legacy add");
	require(large_loaded.GetPoint(boundary_index).IsEqual(expected0), "large batch boundary target must match legacy add");
	require(large_loaded.GetPoint(large_count - 1).IsEqual(expected1), "large batch final target must match legacy add");
	require(large_loaded.GetSourceLine(0) == 2, "large batch first source line must survive");
	require(large_loaded.GetSourceLine(boundary_index) == boundary_index + 2, "large batch boundary source line must survive");
	require(large_loaded.GetSourceLine(large_count - 1) == large_count + 1, "large batch final source line must survive");
	std::remove(target_path);

	DeInitEc();
	std::puts("target assignment mapping ok");
	return 0;
}
