#pragma once

#include <string>

bool RCKMetalFieldAddSelfTest(std::string& error);
std::string RCKMetalFieldAddBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit = 0);
bool RCKMetalFieldSubSelfTest(std::string& error);
std::string RCKMetalFieldSubBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit = 0);
bool RCKMetalFieldDoubleSelfTest(std::string& error);
std::string RCKMetalFieldDoubleBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit = 0);
bool RCKMetalFieldMul4SelfTest(std::string& error);
std::string RCKMetalFieldMul4BenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit = 0);
bool RCKMetalFieldNegSelfTest(std::string& error);
std::string RCKMetalFieldNegBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit = 0);
bool RCKMetalFieldMulSelfTest(std::string& error);
std::string RCKMetalFieldMulBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit = 0);
bool RCKMetalFieldSquareSelfTest(std::string& error);
std::string RCKMetalFieldSquareBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit = 0);
bool RCKMetalFieldSquareMulSelfTest(std::string& error);
std::string RCKMetalFieldSquareMulBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit = 0);
bool RCKMetalJacobianAddSelfTest(std::string& error);
std::string RCKMetalJacobianAddBenchJson(unsigned int iterations, unsigned int min_ms, unsigned int threadgroup_limit = 0);
bool RCKMetalJacobianWalkSelfTest(std::string& error);
std::string RCKMetalJacobianWalkBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int min_ms, unsigned int threadgroup_limit = 0);
bool RCKMetalJacobianJumpWalkSelfTest(std::string& error);
std::string RCKMetalJacobianJumpWalkBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit = 0, unsigned int dp_bits = 0);
bool RCKMetalJacobianDynamicWalkSelfTest(std::string& error);
std::string RCKMetalJacobianDynamicWalkBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit = 0, unsigned int dp_bits = 0);
bool RCKMetalJacobianDynamicCompactDpSelfTest(std::string& error);
std::string RCKMetalJacobianDynamicCompactDpBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit = 0, unsigned int dp_bits = 0);
bool RCKMetalJacobianDynamicDpStreamSelfTest(std::string& error);
std::string RCKMetalJacobianDynamicDpStreamBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit = 0, unsigned int dp_bits = 0);
bool RCKMetalJacobianDynamicDpStreamInplaceSelfTest(std::string& error);
std::string RCKMetalJacobianDynamicDpStreamInplaceBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit = 0, unsigned int dp_bits = 0);
bool RCKMetalJacobianDynamicDpStreamXyzzSelfTest(std::string& error);
std::string RCKMetalJacobianDynamicDpStreamXyzzBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit = 0, unsigned int dp_bits = 0, const char* jump_schedule = "power2");
std::string RCKMetalJacobianDynamicDpStreamXyzzChainBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int packet_count, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit = 0, unsigned int dp_bits = 0);
std::string RCKMetalJacobianDynamicDpStreamXyzzPersistentChainBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int packet_count, unsigned int round_count, unsigned int jump_count, unsigned int threadgroup_limit = 0, unsigned int dp_bits = 0);
std::string RCKMetalJacobianDynamicDpCountBenchJson(unsigned int iterations, unsigned int steps_per_sample, unsigned int jump_count, unsigned int min_ms, unsigned int threadgroup_limit = 0, unsigned int dp_bits = 0);
