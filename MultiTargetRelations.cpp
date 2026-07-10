#include "MultiTargetRelations.h"

static EcInt SignedScale(const EcInt& value, int sign)
{
	EcInt result = value;
	if (sign < 0)
		result.Neg();
	return result;
}

static EcInt SignedAdd(const EcInt& left, const EcInt& right)
{
	EcInt result = left;
	result.Add(right);
	return result;
}

static EcInt SignedSub(const EcInt& left, const EcInt& right)
{
	EcInt result = left;
	result.Sub(right);
	return result;
}

static bool SignedIsZero(const EcInt& value)
{
	EcInt copy = value;
	return copy.IsZero();
}

static bool SignedDivideByTwoExact(const EcInt& value, EcInt* result)
{
	if (!result || (value.data[0] & 1ULL))
		return false;
	*result = value;
	result->ShiftRight(1);
	return true;
}

void TMultiTargetRelationGraph::Reset(u32 target_count)
{
	nodes.clear();
	this->target_count = target_count;
}

u32 TMultiTargetRelationGraph::Size() const
{
	return (u32)nodes.size();
}

TMultiTargetRelationGraph::Node& TMultiTargetRelationGraph::EnsureNode(u32 target_id)
{
	std::unordered_map<u32, Node>::iterator found = nodes.find(target_id);
	if (found != nodes.end())
		return found->second;
	Node node;
	node.parent = target_id;
	node.rank = 0;
	node.sign_to_parent = 1;
	node.offset_to_parent.SetZero();
	return nodes.emplace(target_id, node).first->second;
}

TRelationToRoot TMultiTargetRelationGraph::RelationToRoot(u32 target_id)
{
	TRelationToRoot result;
	result.root = target_id;
	result.sign = 1;
	result.offset.SetZero();
	if (target_id >= target_count)
		return result;

	Node& node = EnsureNode(target_id);
	if (node.parent == target_id)
		return result;

	TRelationToRoot parent_relation = RelationToRoot(node.parent);
	result.root = parent_relation.root;
	result.sign = node.sign_to_parent * parent_relation.sign;
	result.offset = SignedAdd(node.offset_to_parent, SignedScale(parent_relation.offset, node.sign_to_parent));
	node.parent = result.root;
	node.sign_to_parent = result.sign;
	node.offset_to_parent = result.offset;
	return result;
}

TRelationAddResult TMultiTargetRelationGraph::AddRelation(
	u32 target_i,
	u32 target_j,
	int sign,
	const EcInt& offset,
	EcInt* solved_root_value)
{
	if (solved_root_value)
		solved_root_value->SetZero();
	if (target_i >= target_count || target_j >= target_count || (sign != 1 && sign != -1))
		return TRelationAddResult::InvalidCycle;
	EnsureNode(target_i);
	EnsureNode(target_j);

	TRelationToRoot relation_i = RelationToRoot(target_i);
	TRelationToRoot relation_j = RelationToRoot(target_j);
	if (relation_i.root != relation_j.root)
	{
		// value[root_j] = root_sign * value[root_i] + root_offset.
		int root_sign = relation_j.sign * sign * relation_i.sign;
		EcInt root_offset = SignedAdd(SignedScale(relation_i.offset, sign), offset);
		root_offset = SignedSub(root_offset, relation_j.offset);
		root_offset = SignedScale(root_offset, relation_j.sign);

		u32 root_i = relation_i.root;
		u32 root_j = relation_j.root;
		Node& node_i = nodes.at(root_i);
		Node& node_j = nodes.at(root_j);
		if (node_i.rank < node_j.rank)
		{
			// Invert root_j = s*root_i+c into root_i = s*root_j-s*c.
			node_i.parent = root_j;
			node_i.sign_to_parent = root_sign;
			node_i.offset_to_parent = SignedScale(root_offset, -root_sign);
		}
		else
		{
			node_j.parent = root_i;
			node_j.sign_to_parent = root_sign;
			node_j.offset_to_parent = root_offset;
			if (node_i.rank == node_j.rank)
				node_i.rank++;
		}
		return TRelationAddResult::Merged;
	}

	// relation_j.sign*root + relation_j.offset =
	// sign*(relation_i.sign*root + relation_i.offset) + offset.
	const int coefficient = relation_j.sign - sign * relation_i.sign;
	EcInt rhs = SignedAdd(SignedScale(relation_i.offset, sign), offset);
	rhs = SignedSub(rhs, relation_j.offset);
	if (coefficient == 0)
		return SignedIsZero(rhs) ? TRelationAddResult::ConsistentCycle : TRelationAddResult::InvalidCycle;

	if (coefficient == -2)
		rhs.Neg();
	EcInt root_value;
	if (!SignedDivideByTwoExact(rhs, &root_value))
		return TRelationAddResult::InvalidCycle;
	if (solved_root_value)
		*solved_root_value = root_value;
	return TRelationAddResult::SolvedCycle;
}
