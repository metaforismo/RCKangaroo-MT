#pragma once

#include <unordered_map>

#include "Ec.h"

enum class TRelationAddResult
{
	Merged,
	ConsistentCycle,
	SolvedCycle,
	InvalidCycle,
};

struct TRelationToRoot
{
	u32 root;
	int sign;
	EcInt offset;
};

// Stores affine constraints value[j] = sign * value[i] + offset over signed
// 320-bit integers. Candidate scalars from solved cycles still require an EC oracle.
class TMultiTargetRelationGraph
{
public:
	void Reset(u32 target_count);
	u32 Size() const;
	TRelationToRoot RelationToRoot(u32 target_id);
	TRelationAddResult AddRelation(u32 target_i, u32 target_j, int sign, const EcInt& offset, EcInt* solved_root_value);

private:
	struct Node
	{
		u32 parent;
		u32 rank;
		int sign_to_parent;
		EcInt offset_to_parent;
	};

	Node& EnsureNode(u32 target_id);

	u32 target_count = 0;
	std::unordered_map<u32, Node> nodes;
};
