#pragma once

#include <string>
#include <vector>

#include "Ec.h"

struct RCKSmallSolveResult
{
	bool found = false;
	unsigned long long private_key = 0;
	unsigned int target_index = 0;
	unsigned int target_count = 0;
	unsigned int tame_state_count = 0;
	unsigned int wild_state_count = 0;
	unsigned int dp_count = 0;
	unsigned int portfolio_probe_dp_count = 0;
	bool portfolio_fallback_used = false;
};

bool RCKSelfTest(std::string& error);
RCKSmallSolveResult RCKSolveSmallSingle(const EcPoint& target, unsigned long long start, unsigned int range_bits);
RCKSmallSolveResult RCKSolveSmallMulti(const std::vector<EcPoint>& targets, unsigned long long start, unsigned int range_bits);
RCKSmallSolveResult RCKSolveSmallJacobianKangaroo(const EcPoint& target, unsigned long long start, unsigned int range_bits, unsigned int jump_count = 8, unsigned int dp_bits = 0, unsigned int max_steps = 4096);
RCKSmallSolveResult RCKSolveSmallJacobianKangarooMulti(const std::vector<EcPoint>& targets, unsigned long long start, unsigned int range_bits, unsigned int jump_count = 8, unsigned int dp_bits = 0, unsigned int max_steps = 4096);
std::string RCKBenchJson(unsigned int iterations);
std::string RCKPointAddBenchJson(unsigned int iterations, unsigned int min_ms = 0);
std::string RCKJacobianPointAddBenchJson(unsigned int iterations, unsigned int min_ms = 0);
std::string RCKJacobianBatchAffineBenchJson(unsigned int iterations, unsigned int min_ms = 0, unsigned int batch_points = 17);
std::string RCKJacobianWalkBenchJson(unsigned int iterations, unsigned int min_ms = 0, unsigned int jump_count = 16);
std::string RCKJacobianKangarooSmallBenchJson(unsigned int iterations, unsigned int min_ms = 0, unsigned int range_bits = 8, unsigned int jump_count = 8, unsigned int dp_bits = 0, unsigned int max_steps = 4096, const char* jump_schedule = "power2", unsigned int key_offset = 0xFFFFFFFFU, unsigned int portfolio_probe_steps = 0);
std::string RCKJacobianKangarooMultiSmallBenchJson(unsigned int iterations, unsigned int min_ms = 0, unsigned int target_count = 4, unsigned int range_bits = 8, unsigned int jump_count = 8, unsigned int dp_bits = 0, unsigned int max_steps = 4096, const char* jump_schedule = "power2", unsigned int key_offset = 0xFFFFFFFFU, unsigned int portfolio_probe_steps = 0);
