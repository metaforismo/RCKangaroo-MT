// This file is a part of RCKangaroo-MT software
// (c) 2026
// License: GPLv3, see "LICENSE.TXT" file

#pragma once

#include <string>
#include <vector>

#include "Ec.h"

struct TTargetPoint
{
	u8 p[64];
	u32 source_line;
};

class TTargetSet
{
private:
	std::vector<TTargetPoint> Targets;
	std::string LastError;

public:
	void Clear();
	bool LoadFromFile(const char* fn, EcInt& start);
	u32 Count() const;
	const char* GetLastError() const;
	EcPoint GetPoint(u32 index) const;
	u32 GetSourceLine(u32 index) const;

	static std::string NormalizeLine(const std::string& line);
	static u32 MapActiveWildTargetId(u64 active_index, u64 active_count, u32 target_count);
};
