#pragma once

#include <string>

bool RCKMetalFieldAddSelfTest(std::string& error);
std::string RCKMetalFieldAddBenchJson(unsigned int iterations, unsigned int min_ms);
bool RCKMetalFieldSubSelfTest(std::string& error);
std::string RCKMetalFieldSubBenchJson(unsigned int iterations, unsigned int min_ms);
bool RCKMetalFieldDoubleSelfTest(std::string& error);
std::string RCKMetalFieldDoubleBenchJson(unsigned int iterations, unsigned int min_ms);
bool RCKMetalFieldMul4SelfTest(std::string& error);
std::string RCKMetalFieldMul4BenchJson(unsigned int iterations, unsigned int min_ms);
bool RCKMetalFieldNegSelfTest(std::string& error);
std::string RCKMetalFieldNegBenchJson(unsigned int iterations, unsigned int min_ms);
bool RCKMetalFieldMulSelfTest(std::string& error);
std::string RCKMetalFieldMulBenchJson(unsigned int iterations, unsigned int min_ms);
bool RCKMetalFieldSquareSelfTest(std::string& error);
std::string RCKMetalFieldSquareBenchJson(unsigned int iterations, unsigned int min_ms);
