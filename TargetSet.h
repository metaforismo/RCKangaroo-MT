// This file is a part of RCKangaroo-MT software
// (c) 2026
// License: GPLv3, see "LICENSE.TXT" file

#pragma once

#include <cstddef>
#include <string>
#include <vector>

#include "Ec.h"

struct TTargetPoint
{
	u8 p[64];
};
static_assert(sizeof(TTargetPoint) == 64, "target records must stay full-point dense");

class TTargetSet
{
private:
	std::vector<TTargetPoint> Targets;
	std::vector<u32> SourceLines;
	u32 DenseSourceLineBase;
	std::string LastError;

public:
	void Clear();
	bool LoadFromFile(const char* fn, EcInt& start);
	u32 Count() const;
	const char* GetLastError() const;
	EcPoint GetPoint(u32 index) const;
	u32 GetSourceLine(u32 index) const;
	size_t TargetRecordBytes() const;
	size_t ExplicitSourceLineBytes() const;
	size_t TargetStorageBytes() const;
	const char* SourceLineStorageMode() const;
	u32 SourceLineBase() const;

	static std::string NormalizeLine(const std::string& line);
	static u32 MapActiveWildTargetId(u64 active_index, u64 active_count, u32 target_count);
	static u32 MapCycledActiveWildTargetId(u64 active_index, u64 active_count, u32 target_count, u64 cycle_index);
	static u64 CoverageCycleCount(u64 active_count, u32 target_count);
};
