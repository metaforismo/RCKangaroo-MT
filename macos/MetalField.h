#pragma once

#include <string>

bool RCKMetalFieldAddSelfTest(std::string& error);
std::string RCKMetalFieldAddBenchJson(unsigned int iterations);
bool RCKMetalFieldMulSelfTest(std::string& error);
std::string RCKMetalFieldMulBenchJson(unsigned int iterations);
bool RCKMetalFieldSquareSelfTest(std::string& error);
std::string RCKMetalFieldSquareBenchJson(unsigned int iterations);
