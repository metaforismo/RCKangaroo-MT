#pragma once

#include <string>

bool RCKCpuFieldSelfTest(std::string& error);
std::string RCKCpuFieldBenchJson(unsigned int iterations, unsigned int min_ms = 0);
