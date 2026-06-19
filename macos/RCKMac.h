#pragma once

#include <string>
#include <vector>

#include "Ec.h"

struct RCKSmallSolveResult
{
	bool found;
	unsigned long long private_key;
	unsigned int target_index;
};

bool RCKSelfTest(std::string& error);
RCKSmallSolveResult RCKSolveSmallSingle(EcPoint target, unsigned long long start, unsigned int range_bits);
RCKSmallSolveResult RCKSolveSmallMulti(const std::vector<EcPoint>& targets, unsigned long long start, unsigned int range_bits);
std::string RCKBenchJson(unsigned int iterations);
std::string RCKPointAddBenchJson(unsigned int iterations, unsigned int min_ms = 0);
std::string RCKJacobianPointAddBenchJson(unsigned int iterations, unsigned int min_ms = 0);
std::string RCKJacobianWalkBenchJson(unsigned int iterations, unsigned int min_ms = 0, unsigned int jump_count = 16);
