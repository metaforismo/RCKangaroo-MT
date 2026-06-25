#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <string>
#include <vector>

#include "macos/CpuField.h"
#include "macos/RCKMac.h"
#include "macos/MetalField.h"
#include "macos/MetalSmoke.h"
#include "TargetSet.h"

static void PrintUsage()
{
	printf("Usage:\n");
	printf("  rck_macos selftest\n");
	printf("  rck_macos solve-small --range N --start HEX --pubkey PUBKEY\n");
	printf("  rck_macos jacobian-kangaroo-small --range N --start HEX --pubkey PUBKEY [--jumps N] [--dp-bits N] [--max-steps N]\n");
	printf("  rck_macos jacobian-kangaroo-multi-small --range N --start HEX --targets FILE [--jumps N] [--dp-bits N] [--max-steps N]\n");
	printf("  rck_macos jacobian-kangaroo-small-bench [--iterations N] [--min-ms N] [--range N] [--jumps N] [--dp-bits N] [--max-steps N] [--jump-schedule power2|scaled4-balanced] [--key-offset N]\n");
	printf("  rck_macos jacobian-kangaroo-multi-small-bench --target-count N [--iterations N] [--min-ms N] [--range N] [--jumps N] [--dp-bits N] [--max-steps N] [--jump-schedule power2|scaled4-balanced] [--key-offset N]\n");
	printf("  rck_macos bench --iterations N\n");
	printf("  rck_macos point-bench --iterations N [--min-ms N]\n");
	printf("  rck_macos jacobian-point-bench --iterations N [--min-ms N]\n");
	printf("  rck_macos jacobian-batch-affine-bench --iterations N [--min-ms N] [--points N]\n");
	printf("  rck_macos jacobian-walk-bench --iterations N [--min-ms N] [--jumps N]\n");
	printf("  rck_macos cpu-field-test\n");
	printf("  rck_macos cpu-field-bench --iterations N [--min-ms N]\n");
	printf("  rck_macos metal-smoke\n");
	printf("  rck_macos metal-target-lookup-bench --target-count N --query-count N [--hits N] [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-target-lookup-compact-bench --target-count N --query-count N [--hits N] [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-target-lookup-tag32-bench --target-count N --query-count N [--hits N] [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-target-lookup-tag32-persistent-bench --target-count N --query-count N [--hits N] [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos target-lookup-tag32-cpu-bench --target-count N --query-count N [--hits N] [--min-ms N]\n");
	printf("  rck_macos metal-field-test\n");
	printf("  rck_macos metal-field-bench --iterations N [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-field-sub-test\n");
	printf("  rck_macos metal-field-sub-bench --iterations N [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-field-double-test\n");
	printf("  rck_macos metal-field-double-bench --iterations N [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-field-mul4-test\n");
	printf("  rck_macos metal-field-mul4-bench --iterations N [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-field-neg-test\n");
	printf("  rck_macos metal-field-neg-bench --iterations N [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-field-mul-test\n");
	printf("  rck_macos metal-field-mul-bench --iterations N [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-field-square-test\n");
	printf("  rck_macos metal-field-square-bench --iterations N [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-field-square-mul-test\n");
	printf("  rck_macos metal-field-square-mul-bench --iterations N [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-jacobian-add-test\n");
	printf("  rck_macos metal-jacobian-add-bench --iterations N [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-jacobian-walk-test\n");
	printf("  rck_macos metal-jacobian-walk-bench --iterations N [--steps N] [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-jacobian-jump-walk-test\n");
	printf("  rck_macos metal-jacobian-jump-walk-bench --iterations N [--steps N] [--jumps N] [--dp-bits N] [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-jacobian-dynamic-walk-test\n");
	printf("  rck_macos metal-jacobian-dynamic-walk-bench --iterations N [--steps N] [--jumps N] [--dp-bits N] [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-jacobian-dynamic-compact-dp-test\n");
	printf("  rck_macos metal-jacobian-dynamic-compact-dp-bench --iterations N [--steps N] [--jumps N] [--dp-bits N] [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-jacobian-dynamic-dp-stream-test\n");
	printf("  rck_macos metal-jacobian-dynamic-dp-stream-bench --iterations N [--steps N] [--jumps N] [--dp-bits N] [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-jacobian-dynamic-dp-stream-inplace-test\n");
	printf("  rck_macos metal-jacobian-dynamic-dp-stream-inplace-bench --iterations N [--steps N] [--jumps N] [--dp-bits N] [--min-ms N] [--tg-limit N]\n");
	printf("  rck_macos metal-jacobian-dynamic-dp-stream-xyzz-test\n");
	printf("  rck_macos metal-jacobian-dynamic-dp-stream-xyzz-bench --iterations N [--steps N] [--jumps N] [--dp-bits N] [--min-ms N] [--tg-limit N] [--jump-schedule power2|scaled4-balanced]\n");
	printf("  rck_macos metal-jacobian-dynamic-dp-stream-xyzz-chain-bench --iterations N [--steps N] [--packets N] [--jumps N] [--dp-bits N] [--min-ms N] [--tg-limit N] [--jump-schedule power2|scaled4-balanced]\n");
	printf("  rck_macos metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench --iterations N [--steps N] [--packets N] [--rounds N] [--jumps N] [--dp-bits N] [--tg-limit N] [--jump-schedule power2|scaled4-balanced]\n");
	printf("  rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-bench --iterations N [--steps N] [--jumps N] [--dp-bits N] [--min-ms N] [--tg-limit N] [--jump-schedule power2|scaled4-balanced]\n");
	printf("  rck_macos metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench --iterations N --target-count N [--hits N] [--lookup-repeat N] [--lookup-query-mode repeat|distinct-misses] [--lookup-engine gpu|cpu] [--steps N] [--jumps N] [--dp-bits N] [--min-ms N] [--tg-limit N] [--jump-schedule power2|scaled4-balanced]\n");
	printf("  rck_macos metal-jacobian-dynamic-dp-count-bench --iterations N [--steps N] [--jumps N] [--dp-bits N] [--min-ms N] [--tg-limit N]\n");
}

static bool ReadOption(int argc, char* argv[], const char* name, const char** value)
{
	for (int i = 2; i + 1 < argc; i++)
	{
		if (strcmp(argv[i], name) == 0)
		{
			*value = argv[i + 1];
			return true;
		}
	}
	return false;
}

static bool ParseU32(const char* s, unsigned int* out)
{
	char* end = NULL;
	unsigned long v = strtoul(s, &end, 10);
	if (!s[0] || (end && *end))
		return false;
	*out = (unsigned int)v;
	return true;
}

static bool ParseHexU64(const char* s, unsigned long long* out)
{
	char* end = NULL;
	unsigned long long v = strtoull(s, &end, 16);
	if (!s[0] || (end && *end))
		return false;
	*out = v;
	return true;
}

static bool ReadBenchTimingOptions(int argc, char* argv[], unsigned int* iterations, unsigned int* min_ms)
{
	const char* iter_s = NULL;
	const char* min_ms_s = NULL;
	*iterations = 1024;
	*min_ms = 0;
	if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, iterations))
		return false;
	if (ReadOption(argc, argv, "--min-ms", &min_ms_s) && !ParseU32(min_ms_s, min_ms))
		return false;
	return true;
}

static bool ReadMetalBenchOptions(int argc, char* argv[], unsigned int* iterations, unsigned int* min_ms, unsigned int* threadgroup_limit)
{
	const char* tg_s = NULL;
	*threadgroup_limit = 0;
	if (!ReadBenchTimingOptions(argc, argv, iterations, min_ms))
		return false;
	if (ReadOption(argc, argv, "--tg-limit", &tg_s) && !ParseU32(tg_s, threadgroup_limit))
		return false;
	return true;
}

static bool ReadMetalWalkBenchOptions(int argc, char* argv[], unsigned int* iterations, unsigned int* steps, unsigned int* min_ms, unsigned int* threadgroup_limit)
{
	const char* steps_s = NULL;
	*steps = 8;
	if (!ReadMetalBenchOptions(argc, argv, iterations, min_ms, threadgroup_limit))
		return false;
	if (ReadOption(argc, argv, "--steps", &steps_s) && !ParseU32(steps_s, steps))
		return false;
	return true;
}

static bool ReadMetalJumpWalkBenchOptions(int argc, char* argv[], unsigned int* iterations, unsigned int* steps, unsigned int* jumps, unsigned int* dp_bits, unsigned int* min_ms, unsigned int* threadgroup_limit)
{
	const char* jumps_s = NULL;
	const char* dp_bits_s = NULL;
	*jumps = 16;
	*dp_bits = 0;
	if (!ReadMetalWalkBenchOptions(argc, argv, iterations, steps, min_ms, threadgroup_limit))
		return false;
	if (ReadOption(argc, argv, "--jumps", &jumps_s) && !ParseU32(jumps_s, jumps))
		return false;
	if (ReadOption(argc, argv, "--dp-bits", &dp_bits_s) && !ParseU32(dp_bits_s, dp_bits))
		return false;
	return true;
}

static bool ReadMetalJumpWalkChainBenchOptions(int argc, char* argv[], unsigned int* iterations, unsigned int* steps, unsigned int* packets, unsigned int* jumps, unsigned int* dp_bits, unsigned int* min_ms, unsigned int* threadgroup_limit)
{
	const char* packets_s = NULL;
	*packets = 2;
	if (!ReadMetalJumpWalkBenchOptions(argc, argv, iterations, steps, jumps, dp_bits, min_ms, threadgroup_limit))
		return false;
	if (ReadOption(argc, argv, "--packets", &packets_s) && !ParseU32(packets_s, packets))
		return false;
	return true;
}

static bool ReadMetalJumpWalkPersistentChainBenchOptions(int argc, char* argv[], unsigned int* iterations, unsigned int* steps, unsigned int* packets, unsigned int* rounds, unsigned int* jumps, unsigned int* dp_bits, unsigned int* threadgroup_limit)
{
	unsigned int min_ms = 0;
	const char* rounds_s = NULL;
	*rounds = 2;
	if (!ReadMetalJumpWalkChainBenchOptions(argc, argv, iterations, steps, packets, jumps, dp_bits, &min_ms, threadgroup_limit))
		return false;
	if (ReadOption(argc, argv, "--rounds", &rounds_s) && !ParseU32(rounds_s, rounds))
		return false;
	return true;
}

int main(int argc, char* argv[])
{
	if (argc < 2)
	{
		PrintUsage();
		return 1;
	}

	InitEc();
	std::string error;
	int rc = 0;

	if (strcmp(argv[1], "selftest") == 0)
	{
		if (RCKSelfTest(error))
			printf("selftest ok\n");
		else
		{
			printf("selftest failed: %s\n", error.c_str());
			rc = 1;
		}
	}
	else if (strcmp(argv[1], "solve-small") == 0)
	{
		const char* range_s = NULL;
		const char* start_s = NULL;
		const char* pubkey_s = NULL;
		unsigned int range_bits = 0;
		unsigned long long start = 0;
		EcPoint target;

		if (!ReadOption(argc, argv, "--range", &range_s) ||
			!ReadOption(argc, argv, "--start", &start_s) ||
			!ReadOption(argc, argv, "--pubkey", &pubkey_s) ||
			!ParseU32(range_s, &range_bits) ||
			!ParseHexU64(start_s, &start) ||
			!target.SetHexStr(pubkey_s))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}

		RCKSmallSolveResult result = RCKSolveSmallSingle(target, start, range_bits);
		if (result.found)
			printf("FOUND private_key=%llu private_key_hex=%llX target_index=%u\n", result.private_key, result.private_key, result.target_index);
		else
		{
			printf("NOT FOUND\n");
			rc = 2;
		}
	}
	else if (strcmp(argv[1], "jacobian-kangaroo-small") == 0)
	{
		const char* range_s = NULL;
		const char* start_s = NULL;
		const char* pubkey_s = NULL;
		const char* jumps_s = NULL;
		const char* dp_bits_s = NULL;
		const char* max_steps_s = NULL;
		unsigned int range_bits = 0;
		unsigned int jumps = 8;
		unsigned int dp_bits = 0;
		unsigned int max_steps = 4096;
		unsigned long long start = 0;
		EcPoint target;

		if (!ReadOption(argc, argv, "--range", &range_s) ||
			!ReadOption(argc, argv, "--start", &start_s) ||
			!ReadOption(argc, argv, "--pubkey", &pubkey_s) ||
			!ParseU32(range_s, &range_bits) ||
			!ParseHexU64(start_s, &start) ||
			!target.SetHexStr(pubkey_s))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--jumps", &jumps_s) && !ParseU32(jumps_s, &jumps))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--dp-bits", &dp_bits_s) && !ParseU32(dp_bits_s, &dp_bits))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--max-steps", &max_steps_s) && !ParseU32(max_steps_s, &max_steps))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}

		RCKSmallSolveResult result = RCKSolveSmallJacobianKangaroo(target, start, range_bits, jumps, dp_bits, max_steps);
		if (result.found)
			printf("FOUND private_key=%llu private_key_hex=%llX target_index=%u method=jacobian_kangaroo_small dp_lookup=open_address_linear affine_conversion=batch affine_initial_conversion=unit_z_copy dp_count=%u\n", result.private_key, result.private_key, result.target_index, result.dp_count);
		else
		{
			printf("NOT FOUND method=jacobian_kangaroo_small dp_lookup=open_address_linear affine_conversion=batch affine_initial_conversion=unit_z_copy dp_count=%u\n", result.dp_count);
			rc = 2;
		}
	}
	else if (strcmp(argv[1], "jacobian-kangaroo-multi-small") == 0)
	{
		const char* range_s = NULL;
		const char* start_s = NULL;
		const char* targets_s = NULL;
		const char* jumps_s = NULL;
		const char* dp_bits_s = NULL;
		const char* max_steps_s = NULL;
		unsigned int range_bits = 0;
		unsigned int jumps = 8;
		unsigned int dp_bits = 0;
		unsigned int max_steps = 4096;
		unsigned long long start = 0;

		if (!ReadOption(argc, argv, "--range", &range_s) ||
			!ReadOption(argc, argv, "--start", &start_s) ||
			!ReadOption(argc, argv, "--targets", &targets_s) ||
			!ParseU32(range_s, &range_bits) ||
			!ParseHexU64(start_s, &start))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--jumps", &jumps_s) && !ParseU32(jumps_s, &jumps))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--dp-bits", &dp_bits_s) && !ParseU32(dp_bits_s, &dp_bits))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--max-steps", &max_steps_s) && !ParseU32(max_steps_s, &max_steps))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}

		EcInt zero;
		zero.SetZero();
		TTargetSet target_set;
		if (!target_set.LoadFromFile(targets_s, zero))
		{
			printf("target load failed: %s\n", target_set.GetLastError());
			DeInitEc();
			return 1;
		}

		std::vector<EcPoint> targets;
		targets.reserve(target_set.Count());
		for (u32 i = 0; i < target_set.Count(); i++)
			targets.push_back(target_set.GetPoint(i));

		RCKSmallSolveResult result = RCKSolveSmallJacobianKangarooMulti(targets, start, range_bits, jumps, dp_bits, max_steps);
		if (result.found)
		{
			printf("FOUND private_key=%llu private_key_hex=%llX target_index=%u method=jacobian_kangaroo_multi_small architecture=shared_tame dp_lookup=open_address_linear affine_conversion=batch affine_initial_conversion=unit_z_copy target_count=%u tame_states=%u wild_states=%u dp_count=%u\n",
				result.private_key,
				result.private_key,
				result.target_index,
				result.target_count,
				result.tame_state_count,
				result.wild_state_count,
				result.dp_count);
		}
		else
		{
			printf("NOT FOUND method=jacobian_kangaroo_multi_small architecture=shared_tame dp_lookup=open_address_linear affine_conversion=batch affine_initial_conversion=unit_z_copy target_count=%u tame_states=%u wild_states=%u dp_count=%u\n",
				result.target_count,
				result.tame_state_count,
				result.wild_state_count,
				result.dp_count);
			rc = 2;
		}
	}
	else if (strcmp(argv[1], "bench") == 0)
	{
		const char* iter_s = NULL;
		unsigned int iterations = 64;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKBenchJson(iterations).c_str());
	}
	else if (strcmp(argv[1], "jacobian-kangaroo-small-bench") == 0)
	{
		const char* iter_s = NULL;
		const char* min_ms_s = NULL;
		const char* range_s = NULL;
		const char* jumps_s = NULL;
		const char* dp_bits_s = NULL;
		const char* max_steps_s = NULL;
		const char* jump_schedule_s = "power2";
		const char* key_offset_s = NULL;
		unsigned int iterations = 1;
		unsigned int min_ms = 0;
		unsigned int range_bits = 8;
		unsigned int jumps = 8;
		unsigned int dp_bits = 0;
		unsigned int max_steps = 4096;
		unsigned int key_offset = 0xFFFFFFFFU;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--min-ms", &min_ms_s) && !ParseU32(min_ms_s, &min_ms))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--range", &range_s) && !ParseU32(range_s, &range_bits))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--jumps", &jumps_s) && !ParseU32(jumps_s, &jumps))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--dp-bits", &dp_bits_s) && !ParseU32(dp_bits_s, &dp_bits))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--max-steps", &max_steps_s) && !ParseU32(max_steps_s, &max_steps))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		ReadOption(argc, argv, "--jump-schedule", &jump_schedule_s);
		if (ReadOption(argc, argv, "--key-offset", &key_offset_s) && !ParseU32(key_offset_s, &key_offset))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKJacobianKangarooSmallBenchJson(iterations, min_ms, range_bits, jumps, dp_bits, max_steps, jump_schedule_s, key_offset).c_str());
	}
	else if (strcmp(argv[1], "jacobian-kangaroo-multi-small-bench") == 0)
	{
		const char* iter_s = NULL;
		const char* min_ms_s = NULL;
		const char* target_count_s = NULL;
		const char* range_s = NULL;
		const char* jumps_s = NULL;
		const char* dp_bits_s = NULL;
		const char* max_steps_s = NULL;
		const char* jump_schedule_s = "power2";
		const char* key_offset_s = NULL;
		unsigned int iterations = 1;
		unsigned int min_ms = 0;
		unsigned int target_count = 4;
		unsigned int range_bits = 8;
		unsigned int jumps = 8;
		unsigned int dp_bits = 0;
		unsigned int max_steps = 4096;
		unsigned int key_offset = 0xFFFFFFFFU;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--min-ms", &min_ms_s) && !ParseU32(min_ms_s, &min_ms))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--target-count", &target_count_s) && !ParseU32(target_count_s, &target_count))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--range", &range_s) && !ParseU32(range_s, &range_bits))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--jumps", &jumps_s) && !ParseU32(jumps_s, &jumps))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--dp-bits", &dp_bits_s) && !ParseU32(dp_bits_s, &dp_bits))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--max-steps", &max_steps_s) && !ParseU32(max_steps_s, &max_steps))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		ReadOption(argc, argv, "--jump-schedule", &jump_schedule_s);
		if (ReadOption(argc, argv, "--key-offset", &key_offset_s) && !ParseU32(key_offset_s, &key_offset))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKJacobianKangarooMultiSmallBenchJson(iterations, min_ms, target_count, range_bits, jumps, dp_bits, max_steps, jump_schedule_s, key_offset).c_str());
	}
	else if (strcmp(argv[1], "point-bench") == 0)
	{
		const char* iter_s = NULL;
		const char* min_ms_s = NULL;
		unsigned int iterations = 256;
		unsigned int min_ms = 0;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--min-ms", &min_ms_s) && !ParseU32(min_ms_s, &min_ms))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKPointAddBenchJson(iterations, min_ms).c_str());
	}
	else if (strcmp(argv[1], "jacobian-point-bench") == 0)
	{
		const char* iter_s = NULL;
		const char* min_ms_s = NULL;
		unsigned int iterations = 256;
		unsigned int min_ms = 0;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--min-ms", &min_ms_s) && !ParseU32(min_ms_s, &min_ms))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKJacobianPointAddBenchJson(iterations, min_ms).c_str());
	}
	else if (strcmp(argv[1], "jacobian-batch-affine-bench") == 0)
	{
		const char* iter_s = NULL;
		const char* min_ms_s = NULL;
		const char* points_s = NULL;
		unsigned int iterations = 256;
		unsigned int min_ms = 0;
		unsigned int points = 17;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--min-ms", &min_ms_s) && !ParseU32(min_ms_s, &min_ms))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--points", &points_s) && !ParseU32(points_s, &points))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKJacobianBatchAffineBenchJson(iterations, min_ms, points).c_str());
	}
	else if (strcmp(argv[1], "jacobian-walk-bench") == 0)
	{
		const char* iter_s = NULL;
		const char* min_ms_s = NULL;
		const char* jumps_s = NULL;
		unsigned int iterations = 256;
		unsigned int min_ms = 0;
		unsigned int jumps = 16;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--min-ms", &min_ms_s) && !ParseU32(min_ms_s, &min_ms))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--jumps", &jumps_s) && !ParseU32(jumps_s, &jumps))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKJacobianWalkBenchJson(iterations, min_ms, jumps).c_str());
	}
	else if (strcmp(argv[1], "cpu-field-test") == 0)
	{
		if (RCKCpuFieldSelfTest(error))
			printf("cpu field ok\n");
		else
		{
			printf("cpu field failed: %s\n", error.c_str());
			rc = 1;
		}
	}
	else if (strcmp(argv[1], "cpu-field-bench") == 0)
	{
		const char* iter_s = NULL;
		const char* min_ms_s = NULL;
		unsigned int iterations = 4096;
		unsigned int min_ms = 0;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--min-ms", &min_ms_s) && !ParseU32(min_ms_s, &min_ms))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKCpuFieldBenchJson(iterations, min_ms).c_str());
	}
	else if (strcmp(argv[1], "metal-smoke") == 0)
	{
		if (RCKMetalSmoke(error))
			printf("metal smoke ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal smoke skipped: %s\n", error.c_str());
			else
			{
				printf("metal smoke failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-target-lookup-bench") == 0)
	{
		const char* target_count_s = NULL;
		const char* query_count_s = NULL;
		const char* hits_s = NULL;
		const char* min_ms_s = NULL;
		const char* tg_s = NULL;
		unsigned int target_count = 0;
		unsigned int query_count = 0;
		unsigned int hits = 0;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadOption(argc, argv, "--target-count", &target_count_s) ||
			!ReadOption(argc, argv, "--query-count", &query_count_s) ||
			!ParseU32(target_count_s, &target_count) ||
			!ParseU32(query_count_s, &query_count))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--min-ms", &min_ms_s) && !ParseU32(min_ms_s, &min_ms))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--tg-limit", &tg_s) && !ParseU32(tg_s, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--hits", &hits_s))
		{
			if (!ParseU32(hits_s, &hits))
			{
				PrintUsage();
				DeInitEc();
				return 1;
			}
		}
		else
			hits = query_count / 64U;
		printf("%s\n", RCKMetalTargetLookupBenchJson(target_count, query_count, hits, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "metal-target-lookup-compact-bench") == 0)
	{
		const char* target_count_s = NULL;
		const char* query_count_s = NULL;
		const char* hits_s = NULL;
		const char* min_ms_s = NULL;
		const char* tg_s = NULL;
		unsigned int target_count = 0;
		unsigned int query_count = 0;
		unsigned int hits = 0;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadOption(argc, argv, "--target-count", &target_count_s) ||
			!ReadOption(argc, argv, "--query-count", &query_count_s) ||
			!ParseU32(target_count_s, &target_count) ||
			!ParseU32(query_count_s, &query_count))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--min-ms", &min_ms_s) && !ParseU32(min_ms_s, &min_ms))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--tg-limit", &tg_s) && !ParseU32(tg_s, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--hits", &hits_s))
		{
			if (!ParseU32(hits_s, &hits))
			{
				PrintUsage();
				DeInitEc();
				return 1;
			}
		}
		else
			hits = query_count / 64U;
		printf("%s\n", RCKMetalTargetLookupCompactBenchJson(target_count, query_count, hits, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "metal-target-lookup-tag32-bench") == 0)
	{
		const char* target_count_s = NULL;
		const char* query_count_s = NULL;
		const char* hits_s = NULL;
		const char* min_ms_s = NULL;
		const char* tg_s = NULL;
		unsigned int target_count = 0;
		unsigned int query_count = 0;
		unsigned int hits = 0;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadOption(argc, argv, "--target-count", &target_count_s) ||
			!ReadOption(argc, argv, "--query-count", &query_count_s) ||
			!ParseU32(target_count_s, &target_count) ||
			!ParseU32(query_count_s, &query_count))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--min-ms", &min_ms_s) && !ParseU32(min_ms_s, &min_ms))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--tg-limit", &tg_s) && !ParseU32(tg_s, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--hits", &hits_s))
		{
			if (!ParseU32(hits_s, &hits))
			{
				PrintUsage();
				DeInitEc();
				return 1;
			}
		}
		else
			hits = query_count / 64U;
		printf("%s\n", RCKMetalTargetLookupTag32BenchJson(target_count, query_count, hits, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "metal-target-lookup-tag32-persistent-bench") == 0)
	{
		const char* target_count_s = NULL;
		const char* query_count_s = NULL;
		const char* hits_s = NULL;
		const char* min_ms_s = NULL;
		const char* tg_s = NULL;
		unsigned int target_count = 0;
		unsigned int query_count = 0;
		unsigned int hits = 0;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadOption(argc, argv, "--target-count", &target_count_s) ||
			!ReadOption(argc, argv, "--query-count", &query_count_s) ||
			!ParseU32(target_count_s, &target_count) ||
			!ParseU32(query_count_s, &query_count))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--min-ms", &min_ms_s) && !ParseU32(min_ms_s, &min_ms))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--tg-limit", &tg_s) && !ParseU32(tg_s, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--hits", &hits_s))
		{
			if (!ParseU32(hits_s, &hits))
			{
				PrintUsage();
				DeInitEc();
				return 1;
			}
		}
		else
			hits = query_count / 64U;
		printf("%s\n", RCKMetalTargetLookupTag32PersistentBenchJson(target_count, query_count, hits, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "target-lookup-tag32-cpu-bench") == 0)
	{
		const char* target_count_s = NULL;
		const char* query_count_s = NULL;
		const char* hits_s = NULL;
		const char* min_ms_s = NULL;
		unsigned int target_count = 0;
		unsigned int query_count = 0;
		unsigned int hits = 0;
		unsigned int min_ms = 0;
		if (!ReadOption(argc, argv, "--target-count", &target_count_s) ||
			!ReadOption(argc, argv, "--query-count", &query_count_s) ||
			!ParseU32(target_count_s, &target_count) ||
			!ParseU32(query_count_s, &query_count))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--min-ms", &min_ms_s) && !ParseU32(min_ms_s, &min_ms))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (ReadOption(argc, argv, "--hits", &hits_s))
		{
			if (!ParseU32(hits_s, &hits))
			{
				PrintUsage();
				DeInitEc();
				return 1;
			}
		}
		else
			hits = query_count / 64U;
		printf("%s\n", RCKCpuTargetLookupTag32BenchJson(target_count, query_count, hits, min_ms).c_str());
	}
	else if (strcmp(argv[1], "metal-field-test") == 0)
	{
		if (RCKMetalFieldAddSelfTest(error))
			printf("metal field add ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal field add skipped: %s\n", error.c_str());
			else
			{
				printf("metal field add failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-field-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalBenchOptions(argc, argv, &iterations, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldAddBenchJson(iterations, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "metal-field-sub-test") == 0)
	{
		if (RCKMetalFieldSubSelfTest(error))
			printf("metal field sub ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal field sub skipped: %s\n", error.c_str());
			else
			{
				printf("metal field sub failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-field-sub-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalBenchOptions(argc, argv, &iterations, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldSubBenchJson(iterations, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "metal-field-double-test") == 0)
	{
		if (RCKMetalFieldDoubleSelfTest(error))
			printf("metal field double ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal field double skipped: %s\n", error.c_str());
			else
			{
				printf("metal field double failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-field-double-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalBenchOptions(argc, argv, &iterations, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldDoubleBenchJson(iterations, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "metal-field-mul4-test") == 0)
	{
		if (RCKMetalFieldMul4SelfTest(error))
			printf("metal field mul4 ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal field mul4 skipped: %s\n", error.c_str());
			else
			{
				printf("metal field mul4 failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-field-mul4-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalBenchOptions(argc, argv, &iterations, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldMul4BenchJson(iterations, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "metal-field-neg-test") == 0)
	{
		if (RCKMetalFieldNegSelfTest(error))
			printf("metal field neg ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal field neg skipped: %s\n", error.c_str());
			else
			{
				printf("metal field neg failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-field-neg-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalBenchOptions(argc, argv, &iterations, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldNegBenchJson(iterations, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "metal-field-mul-test") == 0)
	{
		if (RCKMetalFieldMulSelfTest(error))
			printf("metal field mul ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal field mul skipped: %s\n", error.c_str());
			else
			{
				printf("metal field mul failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-field-mul-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalBenchOptions(argc, argv, &iterations, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldMulBenchJson(iterations, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "metal-field-square-test") == 0)
	{
		if (RCKMetalFieldSquareSelfTest(error))
			printf("metal field square ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal field square skipped: %s\n", error.c_str());
			else
			{
				printf("metal field square failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-field-square-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalBenchOptions(argc, argv, &iterations, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldSquareBenchJson(iterations, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "metal-field-square-mul-test") == 0)
	{
		if (RCKMetalFieldSquareMulSelfTest(error))
			printf("metal field square-mul ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal field square-mul skipped: %s\n", error.c_str());
			else
			{
				printf("metal field square-mul failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-field-square-mul-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalBenchOptions(argc, argv, &iterations, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldSquareMulBenchJson(iterations, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "metal-jacobian-add-test") == 0)
	{
		if (RCKMetalJacobianAddSelfTest(error))
			printf("metal jacobian add ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal jacobian add skipped: %s\n", error.c_str());
			else
			{
				printf("metal jacobian add failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-jacobian-add-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalBenchOptions(argc, argv, &iterations, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalJacobianAddBenchJson(iterations, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "metal-jacobian-walk-test") == 0)
	{
		if (RCKMetalJacobianWalkSelfTest(error))
			printf("metal jacobian walk ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal jacobian walk skipped: %s\n", error.c_str());
			else
			{
				printf("metal jacobian walk failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-jacobian-walk-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int steps = 8;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalWalkBenchOptions(argc, argv, &iterations, &steps, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalJacobianWalkBenchJson(iterations, steps, min_ms, threadgroup_limit).c_str());
	}
	else if (strcmp(argv[1], "metal-jacobian-jump-walk-test") == 0)
	{
		if (RCKMetalJacobianJumpWalkSelfTest(error))
			printf("metal jacobian jump walk ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal jacobian jump walk skipped: %s\n", error.c_str());
			else
			{
				printf("metal jacobian jump walk failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-jacobian-jump-walk-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int steps = 8;
		unsigned int jumps = 16;
		unsigned int dp_bits = 0;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalJumpWalkBenchOptions(argc, argv, &iterations, &steps, &jumps, &dp_bits, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalJacobianJumpWalkBenchJson(iterations, steps, jumps, min_ms, threadgroup_limit, dp_bits).c_str());
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-walk-test") == 0)
	{
		if (RCKMetalJacobianDynamicWalkSelfTest(error))
			printf("metal jacobian dynamic walk ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal jacobian dynamic walk skipped: %s\n", error.c_str());
			else
			{
				printf("metal jacobian dynamic walk failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-walk-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int steps = 8;
		unsigned int jumps = 16;
		unsigned int dp_bits = 0;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalJumpWalkBenchOptions(argc, argv, &iterations, &steps, &jumps, &dp_bits, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalJacobianDynamicWalkBenchJson(iterations, steps, jumps, min_ms, threadgroup_limit, dp_bits).c_str());
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-compact-dp-test") == 0)
	{
		if (RCKMetalJacobianDynamicCompactDpSelfTest(error))
			printf("metal jacobian dynamic compact dp ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal jacobian dynamic compact dp skipped: %s\n", error.c_str());
			else
			{
				printf("metal jacobian dynamic compact dp failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-compact-dp-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int steps = 8;
		unsigned int jumps = 16;
		unsigned int dp_bits = 0;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalJumpWalkBenchOptions(argc, argv, &iterations, &steps, &jumps, &dp_bits, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalJacobianDynamicCompactDpBenchJson(iterations, steps, jumps, min_ms, threadgroup_limit, dp_bits).c_str());
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-dp-stream-test") == 0)
	{
		if (RCKMetalJacobianDynamicDpStreamSelfTest(error))
			printf("metal jacobian dynamic dp stream ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal jacobian dynamic dp stream skipped: %s\n", error.c_str());
			else
			{
				printf("metal jacobian dynamic dp stream failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-dp-stream-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int steps = 8;
		unsigned int jumps = 16;
		unsigned int dp_bits = 0;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalJumpWalkBenchOptions(argc, argv, &iterations, &steps, &jumps, &dp_bits, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalJacobianDynamicDpStreamBenchJson(iterations, steps, jumps, min_ms, threadgroup_limit, dp_bits).c_str());
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-dp-stream-inplace-test") == 0)
	{
		if (RCKMetalJacobianDynamicDpStreamInplaceSelfTest(error))
			printf("metal jacobian dynamic dp stream in-place ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal jacobian dynamic dp stream in-place skipped: %s\n", error.c_str());
			else
			{
				printf("metal jacobian dynamic dp stream in-place failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-dp-stream-inplace-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int steps = 8;
		unsigned int jumps = 16;
		unsigned int dp_bits = 8;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalJumpWalkBenchOptions(argc, argv, &iterations, &steps, &jumps, &dp_bits, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalJacobianDynamicDpStreamInplaceBenchJson(iterations, steps, jumps, min_ms, threadgroup_limit, dp_bits).c_str());
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-dp-stream-xyzz-test") == 0)
	{
		if (RCKMetalJacobianDynamicDpStreamXyzzSelfTest(error))
			printf("metal jacobian dynamic dp stream XYZZ ok\n");
		else
		{
			if (error == "no Metal device available")
				printf("metal jacobian dynamic dp stream XYZZ skipped: %s\n", error.c_str());
			else
			{
				printf("metal jacobian dynamic dp stream XYZZ failed: %s\n", error.c_str());
				rc = 1;
			}
		}
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-dp-stream-xyzz-bench") == 0)
	{
		const char* steps_s = NULL;
		const char* jump_schedule_s = "power2";
		unsigned int iterations = 1024;
		unsigned int steps = 256;
		unsigned int jumps = 16;
		unsigned int dp_bits = 8;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalJumpWalkBenchOptions(argc, argv, &iterations, &steps, &jumps, &dp_bits, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (!ReadOption(argc, argv, "--steps", &steps_s))
			steps = 256;
		ReadOption(argc, argv, "--jump-schedule", &jump_schedule_s);
		printf("%s\n", RCKMetalJacobianDynamicDpStreamXyzzBenchJson(iterations, steps, jumps, min_ms, threadgroup_limit, dp_bits, jump_schedule_s).c_str());
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-dp-stream-xyzz-chain-bench") == 0)
	{
		const char* steps_s = NULL;
		const char* jump_schedule_s = "power2";
		unsigned int iterations = 1024;
		unsigned int steps = 256;
		unsigned int packets = 2;
		unsigned int jumps = 16;
		unsigned int dp_bits = 8;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalJumpWalkChainBenchOptions(argc, argv, &iterations, &steps, &packets, &jumps, &dp_bits, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (!ReadOption(argc, argv, "--steps", &steps_s))
			steps = 256;
		ReadOption(argc, argv, "--jump-schedule", &jump_schedule_s);
		printf("%s\n", RCKMetalJacobianDynamicDpStreamXyzzChainBenchJson(iterations, steps, packets, jumps, min_ms, threadgroup_limit, dp_bits, jump_schedule_s).c_str());
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-dp-stream-xyzz-persistent-chain-bench") == 0)
	{
		const char* steps_s = NULL;
		const char* jump_schedule_s = "power2";
		unsigned int iterations = 1024;
		unsigned int steps = 256;
		unsigned int packets = 2;
		unsigned int rounds = 2;
		unsigned int jumps = 16;
		unsigned int dp_bits = 8;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalJumpWalkPersistentChainBenchOptions(argc, argv, &iterations, &steps, &packets, &rounds, &jumps, &dp_bits, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (!ReadOption(argc, argv, "--steps", &steps_s))
			steps = 256;
		ReadOption(argc, argv, "--jump-schedule", &jump_schedule_s);
		printf("%s\n", RCKMetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson(iterations, steps, packets, rounds, jumps, threadgroup_limit, dp_bits, jump_schedule_s).c_str());
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-bench") == 0)
	{
		const char* steps_s = NULL;
		const char* jump_schedule_s = "power2";
		unsigned int iterations = 1024;
		unsigned int steps = 256;
		unsigned int jumps = 16;
		unsigned int dp_bits = 8;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalJumpWalkBenchOptions(argc, argv, &iterations, &steps, &jumps, &dp_bits, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (!ReadOption(argc, argv, "--steps", &steps_s))
			steps = 256;
		ReadOption(argc, argv, "--jump-schedule", &jump_schedule_s);
		printf("%s\n", RCKMetalJacobianDynamicDpStreamXyzzAffineScanBenchJson(iterations, steps, jumps, min_ms, threadgroup_limit, dp_bits, jump_schedule_s).c_str());
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-dp-stream-xyzz-affine-scan-target-lookup-tag32-bench") == 0)
	{
		const char* steps_s = NULL;
		const char* jump_schedule_s = "power2";
		const char* target_count_s = NULL;
		const char* hits_s = NULL;
		const char* lookup_repeat_s = NULL;
		const char* lookup_query_mode_s = "repeat";
		const char* lookup_engine_s = "gpu";
		unsigned int iterations = 1024;
		unsigned int steps = 256;
		unsigned int jumps = 16;
		unsigned int dp_bits = 8;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		unsigned int target_count = 0;
		unsigned int hits = 0;
		unsigned int lookup_repeat = 1;
		if (!ReadMetalJumpWalkBenchOptions(argc, argv, &iterations, &steps, &jumps, &dp_bits, &min_ms, &threadgroup_limit) ||
			!ReadOption(argc, argv, "--target-count", &target_count_s) ||
			!ParseU32(target_count_s, &target_count))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		if (!ReadOption(argc, argv, "--steps", &steps_s))
			steps = 256;
		if (ReadOption(argc, argv, "--hits", &hits_s))
		{
			if (!ParseU32(hits_s, &hits))
			{
				PrintUsage();
				DeInitEc();
				return 1;
			}
		}
		else
			hits = 0;
		if (ReadOption(argc, argv, "--lookup-repeat", &lookup_repeat_s) && !ParseU32(lookup_repeat_s, &lookup_repeat))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		ReadOption(argc, argv, "--lookup-query-mode", &lookup_query_mode_s);
		ReadOption(argc, argv, "--lookup-engine", &lookup_engine_s);
		ReadOption(argc, argv, "--jump-schedule", &jump_schedule_s);
		printf("%s\n", RCKMetalJacobianDynamicDpStreamXyzzAffineScanTargetLookupTag32BenchJson(iterations, steps, jumps, min_ms, target_count, hits, lookup_repeat, threadgroup_limit, dp_bits, jump_schedule_s, lookup_query_mode_s, lookup_engine_s).c_str());
	}
	else if (strcmp(argv[1], "metal-jacobian-dynamic-dp-count-bench") == 0)
	{
		unsigned int iterations = 1024;
		unsigned int steps = 8;
		unsigned int jumps = 16;
		unsigned int dp_bits = 0;
		unsigned int min_ms = 0;
		unsigned int threadgroup_limit = 0;
		if (!ReadMetalJumpWalkBenchOptions(argc, argv, &iterations, &steps, &jumps, &dp_bits, &min_ms, &threadgroup_limit))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalJacobianDynamicDpCountBenchJson(iterations, steps, jumps, min_ms, threadgroup_limit, dp_bits).c_str());
	}
	else
	{
		PrintUsage();
		rc = 1;
	}

	DeInitEc();
	return rc;
}
