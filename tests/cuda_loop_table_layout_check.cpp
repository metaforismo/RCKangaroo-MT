#include "defs.h"

#include <cstdint>
#include <iostream>
#include <string>
#include <unordered_set>
#include <vector>

namespace {

struct Layout {
    const char* name;
    std::uint64_t block_size;
    std::uint64_t group_count;
};

std::uint64_t loop_table_index(const Layout& layout,
                               std::uint64_t block,
                               std::uint64_t group_pair,
                               std::uint64_t history_slot,
                               std::uint64_t lane)
{
    return MD_LEN * layout.block_size * layout.group_count * block +
           2 * MD_LEN * layout.block_size * group_pair +
           history_slot * layout.block_size +
           lane;
}

bool check_fixed_layout(const Layout& layout)
{
    if ((layout.group_count % 2) != 0) {
        std::cerr << layout.name << ": group_count must be even\n";
        return false;
    }

    const std::uint64_t block_entries = MD_LEN * layout.block_size * layout.group_count;
    std::vector<unsigned char> seen(block_entries, 0);

    for (std::uint64_t group_pair = 0; group_pair < layout.group_count / 2; ++group_pair) {
        for (std::uint64_t history_slot = 0; history_slot < 2 * MD_LEN; ++history_slot) {
            for (std::uint64_t lane = 0; lane < layout.block_size; ++lane) {
                const std::uint64_t index = loop_table_index(layout, 0, group_pair, history_slot, lane);
                if (index >= block_entries) {
                    std::cerr << layout.name << ": index outside block-local LoopTable span\n";
                    return false;
                }
                if ((index % layout.block_size) != lane) {
                    std::cerr << layout.name << ": final LoopTable dimension is not the thread lane\n";
                    return false;
                }
                if (seen[index] != 0) {
                    std::cerr << layout.name << ": duplicate LoopTable slot\n";
                    return false;
                }
                seen[index] = 1;
            }
        }
    }

    for (std::uint64_t index = 0; index < block_entries; ++index) {
        if (seen[index] == 0) {
            std::cerr << layout.name << ": uncovered LoopTable slot\n";
            return false;
        }
    }

    return true;
}

bool check_old_block_lane_would_alias(const Layout& layout)
{
    std::unordered_set<std::uint64_t> indices;
    constexpr std::uint64_t block = 0;
    constexpr std::uint64_t group_pair = 0;
    constexpr std::uint64_t history_slot = 0;

    for (std::uint64_t lane = 0; lane < layout.block_size; ++lane) {
        (void)lane;
        indices.insert(loop_table_index(layout, block, group_pair, history_slot, block));
    }

    if (indices.size() != 1) {
        std::cerr << layout.name << ": old BLOCK_X-as-lane model did not alias as expected\n";
        return false;
    }
    if (layout.block_size <= 1) {
        std::cerr << layout.name << ": test layout needs multiple thread lanes\n";
        return false;
    }

    return true;
}

} // namespace

int main()
{
    const Layout layouts[] = {
        {"new_gpu", BLOCK_SIZE_NEW_GPU, PNT_GROUP_NEW_GPU},
        {"old_gpu", BLOCK_SIZE_OLD_GPU, PNT_GROUP_OLD_GPU},
    };

    for (const Layout& layout : layouts) {
        if (!check_fixed_layout(layout)) {
            return 1;
        }
        if (!check_old_block_lane_would_alias(layout)) {
            return 1;
        }
    }

    std::cout << "cuda loop table layout ok\n";
    return 0;
}
