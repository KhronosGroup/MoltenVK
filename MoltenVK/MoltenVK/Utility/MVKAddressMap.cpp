/*
 * MVKAddressMap.cpp
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

#include "MVKAddressMap.h"
#include <atomic>

/**
 * Loads the value of an atomic pointer or allocates if it is null in a thread-safe way.
 * Returned pointer will never be null.
 */
template<typename T>
T* loadAtomic(std::atomic<T*>& ptr)
{
    T* obj = ptr.load(std::memory_order_acquire);
    if (!obj)
    {
        T* newObj = new T();

        bool swapped = ptr.compare_exchange_strong(obj, newObj, std::memory_order_release, std::memory_order_acquire);
        if (swapped)
            obj = newObj;
        else
            // Someone else allocated, so a new object is no longer needed
            delete newObj;
    }

    return obj;
}

MVKAddressMap::~MVKAddressMap()
{
    for (uint64_t i = 0; i < NodeCount; i++)
    {
        Node* node = _nodes[i].load(std::memory_order_acquire);
        if (!node) continue;

        for (uint64_t j = 0; j < BlockCount; j++)
        {
            SmallStorage* small = node->blocks[j].small.load(std::memory_order_acquire);
            if (!small) continue;

            delete small;
        }

        delete node;
    }
}

MVKAddressMap::Block* MVKAddressMap::loadBlock(uint64_t addr)
{
    uint64_t blockIdx = getBlockIndex(addr);
    uint64_t nodeIdx = getNodeIndex(addr);

    Node* node = loadAtomic(_nodes[nodeIdx]);

    return &node->blocks[blockIdx];
}

MVKAddressMap::Block* MVKAddressMap::getBlock(uint64_t addr) const
{
    uint64_t nodeIdx = getNodeIndex(addr);

    Node* node = _nodes[nodeIdx].load(std::memory_order_acquire);
    if (!node)
        return nullptr;

    uint64_t blockIdx = getBlockIndex(addr);

    return &node->blocks[blockIdx];
}

void MVKAddressMap::processEntry(const Entry& entry, bool add)
{
    if (entry.size >= BlockSize)
    {
        uint64_t low = entry.baseAddress;
        uint64_t high = low + entry.size;

        Entry empty{};
        while (low <= high)
        {
            Block* block = loadBlock(low);
            
            // If we are adding, insert right only on the first entry, and otherwise
            // insert left. If we are removing, we should always reset right and left
            // if the value matches.
            if (add)
            {
                if (low == entry.baseAddress)
                    block->right.store(entry, std::memory_order_relaxed);
                else
                    block->left.store(entry, std::memory_order_relaxed);
            }
            else
            {
                if (block->right.load(std::memory_order_relaxed).value == entry.value)
                    block->right.store(empty, std::memory_order_relaxed);
                else if (block->left.load(std::memory_order_relaxed).value == entry.value)
                    block->left.store(empty, std::memory_order_relaxed);
            }

            low += BlockSize;
        }
    }
    else
    {
        // If the entry is smaller than BlockSize, it is not well-defined to
        // mark blocks since one could have multiple small ranges within the same
        // block. Thus, these must be stored separately. We will assume that most
        // allocations are larger and thus this path is less common. We could optimize
        // here and store in a sorted order and binary search later, but that may
        // be an unnecessary optimization.

        Block* block = loadBlock(entry.baseAddress);

        SmallStorage* small = loadAtomic(block->small);

        std::lock_guard<std::mutex> lock(small->lock);
        if (add)
            small->entries.emplace_back(entry);
        else
        {
            auto found = std::find_if(
                small->entries.begin(),
                small->entries.end(),
                [&entry](Entry& e) { return e.value == entry.value; }
            );
            if (found != small->entries.end())
                small->entries.erase(found);
        }
    }
}

void MVKAddressMap::addEntry(const Entry& entry)
{
    processEntry(entry, true);
}

void MVKAddressMap::removeEntry(const Entry& entry)
{
    processEntry(entry, false);
}

bool MVKAddressMap::getEntry(uint64_t addr, Entry& outEntry) const
{
    Block* block = getBlock(addr);
    if (!block)
        return false;

    // First check left. This means the address is within the range and the base
    // address is to the left.
    Entry left = block->left.load(std::memory_order_relaxed);
    if (left.baseAddress && addr < left.baseAddress + left.size)
    {
        outEntry = left;
        return true;
    }

    // Next check right. This means the base address is within the same block.
    Entry right = block->right.load(std::memory_order_relaxed);
    if (right.baseAddress && addr >= right.baseAddress)
    {
        outEntry = right;
        return true;
    }

    // Otherwise, we need to search for small entries.
    SmallStorage* small = block->small.load(std::memory_order_acquire);
    if (!small)
        return false;
    
    // Find the small entry where the address is within the range.
    std::lock_guard<std::mutex> lock(small->lock);
    auto found = std::find_if(
        small->entries.begin(),
        small->entries.end(),
        [addr](Entry& e) { return addr >= e.baseAddress && addr < e.baseAddress + e.size; }
    );
    if (found != small->entries.end())
    {
        outEntry = *found;
        return true;
    }

    return false;
}

bool MVKAddressMap::getValue(uint64_t addr, void*& outValue) const
{
    Entry entry;
    if (getEntry(addr, entry))
    {
        outValue = entry.value;
        return true;
    }

    return false;
}
