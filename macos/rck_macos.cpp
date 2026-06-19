#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <string>

#include "macos/CpuField.h"
#include "macos/RCKMac.h"
#include "macos/MetalField.h"
#include "macos/MetalSmoke.h"

static void PrintUsage()
{
	printf("Usage:\n");
	printf("  rck_macos selftest\n");
	printf("  rck_macos solve-small --range N --start HEX --pubkey PUBKEY\n");
	printf("  rck_macos bench --iterations N\n");
	printf("  rck_macos point-bench --iterations N [--min-ms N]\n");
	printf("  rck_macos jacobian-point-bench --iterations N [--min-ms N]\n");
	printf("  rck_macos cpu-field-test\n");
	printf("  rck_macos cpu-field-bench --iterations N [--min-ms N]\n");
	printf("  rck_macos metal-smoke\n");
	printf("  rck_macos metal-field-test\n");
	printf("  rck_macos metal-field-bench --iterations N\n");
	printf("  rck_macos metal-field-mul-test\n");
	printf("  rck_macos metal-field-mul-bench --iterations N\n");
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
	else
	{
		PrintUsage();
		rc = 1;
	}

	DeInitEc();
	return rc;
}
