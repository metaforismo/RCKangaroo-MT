// This file is a part of RCKangaroo-MT software
// (c) 2026
// License: GPLv3, see "LICENSE.TXT" file

#include "TargetSet.h"

#include <fstream>

static constexpr size_t kTargetMapBatchSize = 32768;
static constexpr size_t kTargetReserveSampleCount = 1024;
static constexpr u64 kTargetReserveSlack = 1024;

static bool TargetFieldIsZero(const EcInt& v)
{
	return (v.data[0] | v.data[1] | v.data[2] | v.data[3] | v.data[4]) == 0;
}

static EcPoint AddTargetOffsetWithInverse(const EcPoint& target, const EcPoint& offset, const EcInt& dx_inv)
{
	EcPoint res;
	EcInt dy, lambda, lambda2;

	dy = offset.y;
	dy.SubModP(target.y);

	lambda = dy;
	lambda.MulModP(dx_inv);
	lambda2 = lambda;
	lambda2.MulModP(lambda);

	res.x = lambda2;
	res.x.SubModP(target.x);
	res.x.SubModP(offset.x);

	res.y = offset.x;
	res.y.SubModP(res.x);
	res.y.MulModP(lambda);
	res.y.SubModP(offset.y);
	return res;
}

static void MapTargetBatchByOffset(std::vector<EcPoint>& points, EcPoint& offset)
{
	std::vector<size_t> active_indices;
	std::vector<EcInt> denominators;
	std::vector<EcInt> prefix_products;
	active_indices.reserve(points.size());
	denominators.reserve(points.size());
	prefix_products.reserve(points.size());

	EcInt product;
	product.Set(1);
	for (size_t i = 0; i < points.size(); ++i)
	{
		EcInt dx = offset.x;
		dx.SubModP(points[i].x);
		if (TargetFieldIsZero(dx))
		{
			points[i] = Ec::AddPoints(points[i], offset);
			continue;
		}
		product.MulModP(dx);
		active_indices.push_back(i);
		denominators.push_back(dx);
		prefix_products.push_back(product);
	}

	if (active_indices.empty())
		return;

	EcInt inverse_suffix = prefix_products.back();
	inverse_suffix.InvModP();
	for (size_t remaining = active_indices.size(); remaining > 0; --remaining)
	{
		size_t pos = remaining - 1;
		EcInt dx_inv = inverse_suffix;
		if (pos)
			dx_inv.MulModP(prefix_products[pos - 1]);
		points[active_indices[pos]] = AddTargetOffsetWithInverse(points[active_indices[pos]], offset, dx_inv);
		inverse_suffix.MulModP(denominators[pos]);
	}
}

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

u32 TTargetSet::MapCycledActiveWildTargetId(u64 active_index, u64 active_count, u32 target_count, u64 cycle_index)
{
	if (!target_count || !active_count)
		return 0;
	if (active_count >= target_count)
		return MapActiveWildTargetId(active_index, active_count, target_count);
	if (active_index >= active_count)
		active_index = active_count - 1;
	u64 cycle_offset = ((cycle_index % target_count) * (active_count % target_count)) % target_count;
	return (u32)((cycle_offset + active_index) % target_count);
}

u64 TTargetSet::CoverageCycleCount(u64 active_count, u32 target_count)
{
	if (!target_count || !active_count)
		return 0;
	if (active_count >= target_count)
		return 1;
	return ((u64)target_count + active_count - 1) / active_count;
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
	u64 file_size = 0;
	fp.seekg(0, std::ios::end);
	std::streampos end_pos = fp.tellg();
	if (end_pos > 0)
		file_size = (u64)end_pos;
	fp.clear();
	fp.seekg(0, std::ios::beg);

	EcPoint neg_start;
	bool has_start = !start.IsZero();
	if (has_start)
	{
		neg_start = Ec::MultiplyG(start);
		neg_start.y.NegModP();
	}

	std::vector<EcPoint> pending_points;
	std::vector<u32> pending_lines;
	pending_points.reserve(kTargetMapBatchSize);
	pending_lines.reserve(kTargetMapBatchSize);
	bool target_reserve_estimated = false;
	auto maybe_reserve_targets = [&]() {
		if (target_reserve_estimated || !file_size || (pending_points.size() < kTargetReserveSampleCount))
			return;
		std::streampos pos = fp.tellg();
		if (pos <= 0)
			return;
		u64 consumed = (u64)pos;
		u64 estimate = ((file_size * (u64)pending_points.size()) / consumed) + kTargetReserveSlack;
		if (estimate > 0xFFFFFFFFULL)
			estimate = 0xFFFFFFFFULL;
		if (estimate > Targets.capacity())
			Targets.reserve((size_t)estimate);
		target_reserve_estimated = true;
	};
	auto flush_pending = [&]() {
		if (pending_points.empty())
			return;
		if (has_start)
			MapTargetBatchByOffset(pending_points, neg_start);
		for (size_t i = 0; i < pending_points.size(); ++i)
		{
			TTargetPoint rec;
			pending_points[i].SaveToBuffer64(rec.p);
			rec.source_line = pending_lines[i];
			Targets.push_back(rec);
		}
		pending_points.clear();
		pending_lines.clear();
	};

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

		pending_points.push_back(p);
		pending_lines.push_back(line_no);
		maybe_reserve_targets();
		if (pending_points.size() >= kTargetMapBatchSize)
			flush_pending();
	}
	flush_pending();

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
