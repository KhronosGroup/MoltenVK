/*
 * MVKAddressMap.h
 *
 * Copyright (c) 2015-2024 The Brenwill Workshop Ltd. (http://www.brenwill.com)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#pragma once

#include "MVKFoundation.h"
#include "MVKSmallVector.h"
#include <mutex>

/**
 * Maintains a mapping from memory address ranges as keys to arbitrary pointer values.
 * 
 * This data structure is thread-safe.
 *
 * The map can be queried with any arbitrary address within an inserted range's min and max,
 * and they will all map to the same value.
 *
 * Because not all bits are used in 64-bit memory addresses, this map may not work with
 * any arbitrary 64-bit integer range. However, it can always be used with 32-bit integers
 * for more generalized use cases.
 */
class MVKAddressMap
{
public:

    /**
     * A key-value entry for the map
     */
    struct Entry
    {
        uint64_t baseAddress;
        uint64_t size;

        void* value;
    };

public:

    /**
     * Add an entry to the map. Thread-safe.
     * 
     * The address range must not overlap an existing range, otherwise removal
     * and querying are no longer well-defined.
     */
    void addEntry(const Entry& entry);

    /**
     * Remove an entry to the map. Thread-safe.
     *
     * The address range must exactly match an existing range, otherwise removal
     * and querying are no longer well-defined.
     */
    void removeEntry(const Entry& entry);

    /**
     * Query the map given an arbitrary address, and return true if it exists. Thread-safe.
     *
     * Sets outEntry with the queried entry if it exists
     */
    bool getEntry(uint64_t addr, Entry& outEntry) const;

    /**
     * Query the map given an arbitrary address, and return true if it exists. Thread-safe.
     *
     * Sets outValue with the queried value if it exists
     */
    bool getValue(uint64_t addr, void*& outValue) const;

    ~MVKAddressMap();

private:

    static constexpr uint64_t BlockSizeBits = 21; // 2mb
    static constexpr uint64_t BlockSize = 1 << BlockSizeBits;

    static constexpr uint64_t BlockCountBits = 18;
    static constexpr uint64_t BlockCount = 1 << BlockCountBits;
    static constexpr uint64_t BlockCountMask = BlockCount - 1;

    static constexpr uint64_t NodeCountBits = 12;
    static constexpr uint64_t NodeCount = 1 << NodeCountBits;
    static constexpr uint64_t NodeCountMask = NodeCount - 1;

private:

    /** Dynamically allocated storage for memory blocks smaller than BlockSize */
    struct SmallStorage
    {
        std::mutex lock;
        MVKSmallVector<Entry, 3> entries;
    };

    /** Storage for one contiguous memory block of size BlockSize */
    struct Block
    {
        std::atomic<Entry> left;
        std::atomic<Entry> right;

        std::atomic<SmallStorage*> small;
    };

    /** Dynamically allocated region with all blocks for that region */
    struct Node
    {
        Block blocks[BlockCount] = {};
    };

private:

    /**
     * Load corresponding block where addr is located. Will never return nullptr
     * and will allocate if the block was not previously allocated.
     */
    Block* loadBlock(uint64_t addr);

    /**
     * Get corresponding block where addr is located. Will return nullptr if the
     * block was not previously allocated.
     */
    Block* getBlock(uint64_t addr) const;

    /** Adds or removes an entry from the map, depending on the value of 'add' */
    void processEntry(const Entry& entry, bool add);

    /** Gets the node index associated with the provided address */
    inline uint64_t getNodeIndex(uint64_t addr) const { return (addr >> (BlockSizeBits + BlockCountBits)) & NodeCountMask; }

    /** Gets the block index associated with the provided address */
    inline uint64_t getBlockIndex(uint64_t addr) const { return (addr >> BlockSizeBits) & BlockCountMask; }

private:
    std::atomic<Node*> _nodes[NodeCount] = {};
};

