// This file is a part of RCKangaroo-MT software
// (c) 2026
// License: GPLv3, see "LICENSE.TXT" file

#include "TargetSet.h"

#include <fstream>

void TTargetSet::Clear()
{
	Targets.clear();
	LastError.clear();
}

std::string TTargetSet::NormalizeLine(const std::string& line)
{
	size_t begin = 0;
	while ((begin < line.size()) && ((line[begin] == ' ') || (line[begin] == '\t') || (line[begin] == '\r') || (line[begin] == '\n')))
		begin++;

	size_t end = line.size();
	while ((end > begin) && ((line[end - 1] == ' ') || (line[end - 1] == '\t') || (line[end - 1] == '\r') || (line[end - 1] == '\n')))
		end--;

	if (begin >= end)
		return std::string();

	if (line[begin] == '#')
		return std::string();

	return line.substr(begin, end - begin);
}

u32 TTargetSet::MapActiveWildTargetId(u64 active_index, u64 active_count, u32 target_count)
{
	if (!target_count || !active_count)
		return 0;
	if (active_index >= active_count)
		active_index = active_count - 1;
	u32 target_id = (u32)((active_index * (u64)target_count) / active_count);
	if (target_id >= target_count)
		target_id = target_count - 1;
	return target_id;
}

bool TTargetSet::LoadFromFile(const char* fn, EcInt& start)
{
	Clear();

	std::ifstream fp(fn);
	if (!fp)
	{
		LastError = "cannot open target file";
		return false;
	}

	EcPoint neg_start;
	bool has_start = !start.IsZero();
	if (has_start)
	{
		neg_start = Ec::MultiplyG(start);
		neg_start.y.NegModP();
	}

	std::string line;
	u32 line_no = 0;
	while (std::getline(fp, line))
	{
		line_no++;
		std::string s = NormalizeLine(line);
		if (s.empty())
			continue;

		EcPoint p;
		if (!p.SetHexStr(s.c_str()))
		{
			LastError = "invalid public key at line " + std::to_string(line_no);
			Targets.clear();
			return false;
		}

		if (has_start)
			p = Ec::AddPoints(p, neg_start);

		TTargetPoint rec;
		p.SaveToBuffer64(rec.p);
		rec.source_line = line_no;
		Targets.push_back(rec);
	}

	if (Targets.empty())
	{
		LastError = "target file does not contain public keys";
		return false;
	}

	return true;
}

u32 TTargetSet::Count() const
{
	return (u32)Targets.size();
}

const char* TTargetSet::GetLastError() const
{
	return LastError.c_str();
}

EcPoint TTargetSet::GetPoint(u32 index) const
{
	EcPoint p;
	p.LoadFromBuffer64((u8*)Targets[index].p);
	return p;
}

u32 TTargetSet::GetSourceLine(u32 index) const
{
	return Targets[index].source_line;
}
