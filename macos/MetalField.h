#pragma once

#include <string>

bool RCKMetalFieldAddSelfTest(std::string& error);
std::string RCKMetalFieldAddBenchJson(unsigned int iterations);
bool RCKMetalFieldSubSelfTest(std::string& error);
std::string RCKMetalFieldSubBenchJson(unsigned int iterations);
bool RCKMetalFieldDoubleSelfTest(std::string& error);
std::string RCKMetalFieldDoubleBenchJson(unsigned int iterations);
bool RCKMetalFieldMulSelfTest(std::string& error);
std::string RCKMetalFieldMulBenchJson(unsigned int iterations);
bool RCKMetalFieldSquareSelfTest(std::string& error);
std::string RCKMetalFieldSquareBenchJson(unsigned int iterations);
