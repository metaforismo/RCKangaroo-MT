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
	printf("  rck_macos jacobian-kangaroo-small-bench [--iterations N] [--min-ms N] [--range N] [--jumps N] [--dp-bits N] [--max-steps N]\n");
	printf("  rck_macos jacobian-kangaroo-multi-small-bench --target-count N [--iterations N] [--min-ms N] [--range N] [--jumps N] [--dp-bits N] [--max-steps N]\n");
	printf("  rck_macos bench --iterations N\n");
	printf("  rck_macos point-bench --iterations N [--min-ms N]\n");
	printf("  rck_macos jacobian-point-bench --iterations N [--min-ms N]\n");
	printf("  rck_macos jacobian-batch-affine-bench --iterations N [--min-ms N] [--points N]\n");
	printf("  rck_macos jacobian-walk-bench --iterations N [--min-ms N] [--jumps N]\n");
	printf("  rck_macos cpu-field-test\n");
	printf("  rck_macos cpu-field-bench --iterations N [--min-ms N]\n");
	printf("  rck_macos metal-smoke\n");
	printf("  rck_macos metal-field-test\n");
	printf("  rck_macos metal-field-bench --iterations N\n");
	printf("  rck_macos metal-field-sub-test\n");
	printf("  rck_macos metal-field-sub-bench --iterations N\n");
	printf("  rck_macos metal-field-double-test\n");
	printf("  rck_macos metal-field-double-bench --iterations N\n");
	printf("  rck_macos metal-field-neg-test\n");
	printf("  rck_macos metal-field-neg-bench --iterations N\n");
	printf("  rck_macos metal-field-mul-test\n");
	printf("  rck_macos metal-field-mul-bench --iterations N\n");
	printf("  rck_macos metal-field-square-test\n");
	printf("  rck_macos metal-field-square-bench --iterations N\n");
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
			printf("FOUND private_key=%llu private_key_hex=%llX target_index=%u method=jacobian_kangaroo_small dp_lookup=hash affine_conversion=batch dp_count=%u\n", result.private_key, result.private_key, result.target_index, result.dp_count);
		else
		{
			printf("NOT FOUND method=jacobian_kangaroo_small dp_lookup=hash affine_conversion=batch dp_count=%u\n", result.dp_count);
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
			printf("FOUND private_key=%llu private_key_hex=%llX target_index=%u method=jacobian_kangaroo_multi_small architecture=shared_tame dp_lookup=hash affine_conversion=batch target_count=%u tame_states=%u wild_states=%u dp_count=%u\n",
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
			printf("NOT FOUND method=jacobian_kangaroo_multi_small architecture=shared_tame dp_lookup=hash affine_conversion=batch target_count=%u tame_states=%u wild_states=%u dp_count=%u\n",
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
		unsigned int iterations = 1;
		unsigned int min_ms = 0;
		unsigned int range_bits = 8;
		unsigned int jumps = 8;
		unsigned int dp_bits = 0;
		unsigned int max_steps = 4096;
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
		printf("%s\n", RCKJacobianKangarooSmallBenchJson(iterations, min_ms, range_bits, jumps, dp_bits, max_steps).c_str());
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
		unsigned int iterations = 1;
		unsigned int min_ms = 0;
		unsigned int target_count = 4;
		unsigned int range_bits = 8;
		unsigned int jumps = 8;
		unsigned int dp_bits = 0;
		unsigned int max_steps = 4096;
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
		printf("%s\n", RCKJacobianKangarooMultiSmallBenchJson(iterations, min_ms, target_count, range_bits, jumps, dp_bits, max_steps).c_str());
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
		const char* iter_s = NULL;
		unsigned int iterations = 1024;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldAddBenchJson(iterations).c_str());
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
		const char* iter_s = NULL;
		unsigned int iterations = 1024;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldSubBenchJson(iterations).c_str());
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
		const char* iter_s = NULL;
		unsigned int iterations = 1024;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldDoubleBenchJson(iterations).c_str());
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
		const char* iter_s = NULL;
		unsigned int iterations = 1024;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldNegBenchJson(iterations).c_str());
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
		const char* iter_s = NULL;
		unsigned int iterations = 1024;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldMulBenchJson(iterations).c_str());
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
		const char* iter_s = NULL;
		unsigned int iterations = 1024;
		if (ReadOption(argc, argv, "--iterations", &iter_s) && !ParseU32(iter_s, &iterations))
		{
			PrintUsage();
			DeInitEc();
			return 1;
		}
		printf("%s\n", RCKMetalFieldSquareBenchJson(iterations).c_str());
	}
	else
	{
		PrintUsage();
		rc = 1;
	}

	DeInitEc();
	return rc;
}
