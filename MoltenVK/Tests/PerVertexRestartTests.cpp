// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#include "MVKPerVertexReplay.h"
#include <array>
#include <cassert>
#include <cstdio>
#include <vector>
using uint = uint32_t;
#ifdef MVK_RESTART_GPU_TESTS
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <cstring>
#include <cstdlib>
static id<MTLDevice> gpu;
static id<MTLCommandQueue> queue;
static id<MTLComputePipelineState> pipeline;
static id<MTLComputePipelineState> capturePipeline;
static bool serialBaseline;
#else
using std::min;
#include "PerVertexRestartKernel.inc"
#endif

static void assemble(const uint8_t* source, uint* compact, uint* pairs, uint* triplets, uint* corners, uint* args, const uint* values, uint guardWords = 0) {
    uint p[10] = {};
    std::copy_n(values, 7, p);
#ifdef MVK_RESTART_GPU_TESTS
    uint primitives = mvkPerVertexPrimitiveCount(p[0], VkPrimitiveTopology(p[3]));
    uint vertices = mvkPerVertexReplayVertexCount(VkPrimitiveTopology(p[3]));
    size_t lengths[] = {size_t(p[0]) * p[2], size_t(mvkPerVertexRestartIndexScratchSize(p[0])) + 8 * guardWords, (size_t(2) * vertices * primitives * p[1] + 2 * guardWords) * 4, (size_t(3) * primitives * p[1] + 2 * guardWords) * 4, (size_t(vertices) * primitives * p[1] + 2 * guardWords) * 4, size_t(68 + 2 * guardWords) * 4};
    const void* host[] = {source, compact - guardWords, pairs - guardWords, triplets - guardWords, corners - guardWords, args - guardWords};
    id<MTLBuffer> staging[6], buffers[6];
    id<MTLCommandBuffer> command = [queue commandBuffer];
    id<MTLBlitCommandEncoder> upload = [command blitCommandEncoder];
    for (uint slot = 0; slot < 6; ++slot) {
        staging[slot] = [gpu newBufferWithLength:std::max(lengths[slot], size_t(4)) options:MTLResourceStorageModeShared];
        assert(staging[slot]);
        if (lengths[slot]) { std::memcpy(staging[slot].contents, host[slot], lengths[slot]); }
        // Match production storage: GPU-local indices, prefix scratch and indirect arguments.
        buffers[slot] = slot == 0 || slot == 1 || slot == 5 ? [gpu newBufferWithLength:staging[slot].length options:MTLResourceStorageModePrivate] : staging[slot];
        assert(buffers[slot]);
        if (buffers[slot] != staging[slot]) { [upload copyFromBuffer:staging[slot] sourceOffset:0 toBuffer:buffers[slot] destinationOffset:0 size:staging[slot].length]; }
    }
    [upload endEncoding];
    id<MTLComputeCommandEncoder> encoder = [command computeCommandEncoder];
    [encoder setComputePipelineState:pipeline];
    for (uint slot = 0; slot < 6; ++slot) { [encoder setBuffer:buffers[slot] offset:slot ? 4 * guardWords : 0 atIndex:slot]; }
    NSUInteger width = std::min(pipeline.threadExecutionWidth, pipeline.maxTotalThreadsPerThreadgroup);
    auto dispatch = [&](uint phase, uint step, uint scanSource, uint64_t count) {
        p[7] = phase; p[8] = step; p[9] = scanSource;
        [encoder setBytes:p length:sizeof(p) atIndex:6];
        [encoder dispatchThreadgroups:MTLSizeMake((count + width - 1) / width, 1, 1) threadsPerThreadgroup:MTLSizeMake(width, 1, 1)];
        [encoder memoryBarrierWithScope:MTLBarrierScopeBuffers];
    };
    if (serialBaseline) { width = 1; dispatch(0, 0, 0, 1); }
    else { mvkDispatchPerVertexRestart(p[0], p[1], VkPrimitiveTopology(p[3]), dispatch); }
    // Exercise the SPIRV-Cross capture ABI with production's original stage-in region
    // and GPU-compacted indirect dispatch. Metal grid_size comes from the region.
    id<MTLBuffer> captured = nil;
    if (capturePipeline && p[0] && p[1]) {
        captured = [gpu newBufferWithLength:size_t(p[0]) * p[1] * 2 * sizeof(uint) options:MTLResourceStorageModeShared];
        std::memset(captured.contents, 0xcd, captured.length);
        [encoder setComputePipelineState:capturePipeline];
        [encoder setBuffer:buffers[1] offset:4 * guardWords atIndex:0];
        [encoder setBuffer:captured offset:0 atIndex:1];
        [encoder setStageInRegion:MTLRegionMake2D(uint(-3), p[5], p[0], p[1])];
        [encoder dispatchThreadgroupsWithIndirectBuffer:buffers[5] indirectBufferOffset:4 * guardWords threadsPerThreadgroup:MTLSizeMake(1, 1, 1)];
    }
    [encoder endEncoding];
    id<MTLBlitCommandEncoder> readback = [command blitCommandEncoder];
    for (uint slot : {1u, 5u}) { [readback copyFromBuffer:buffers[slot] sourceOffset:0 toBuffer:staging[slot] destinationOffset:0 size:staging[slot].length]; }
    [readback endEncoding];
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    [command addCompletedHandler:^(id<MTLCommandBuffer>) { dispatch_semaphore_signal(done); }];
    [command commit];
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
        std::fputs("FAIL: GPU command exceeded 10 seconds; stop further GPU testing\n", stderr);
        std::_Exit(124);
    }
    if (command.status != MTLCommandBufferStatusCompleted) {
        std::fprintf(stderr, "FAIL: Metal command: %s\n", command.error.description.UTF8String);
        std::exit(1);
    }
    for (uint slot = 1; slot < 6; ++slot) { if (lengths[slot]) { std::memcpy(const_cast<void*>(host[slot]), staging[slot].contents, lengths[slot]); } }
    if (captured) {
        const auto* records = static_cast<const uint*>(captured.contents);
        uint actualPrimitives = args[4] / vertices;
        for (uint instance = 0; instance < p[1]; ++instance) {
            for (uint primitive = 0; primitive < actualPrimitives; ++primitive) {
                for (uint corner = 0; corner < 3; ++corner) {
                    uint record = triplets[3 * (instance * actualPrimitives + primitive) + corner];
                    assert(record < p[0] * p[1]);
                    assert(records[2 * record] == compact[triplets[3 * primitive + corner]] + uint(-3));
                    assert(records[2 * record + 1] == p[5] + instance);
                }
            }
        }
    }
    std::printf("GPU: n=%u instances=%u width=%u topology=%u last=%u %.3f ms\n", p[0], p[1], p[2], p[3], p[4], 1000 * (command.GPUEndTime - command.GPUStartTime));
#else
    (void)guardWords;
    mvkDispatchPerVertexRestart(p[0], p[1], VkPrimitiveTopology(p[3]), [&](uint phase, uint step, uint scanSource, uint64_t count) {
        p[7] = phase; p[8] = step; p[9] = scanSource;
        // Reverse traversal checks that scatter/instance work does not rely on invocation order.
        for (uint64_t i = count; i; --i) { perVertexRestart(source, compact, pairs, triplets, corners, args, p, uint(i - 1)); }
    });
#endif
}

static void check(const std::vector<int64_t>& input, uint bytes, VkPrimitiveTopology topology, bool last, uint instances, bool withCorners) {
    constexpr uint guard = 0xabcdef01;
    uint vertices = mvkPerVertexReplayVertexCount(topology);
    uint maxPrimitives = mvkPerVertexPrimitiveCount(uint(input.size()), topology);
    std::vector<uint8_t> source(bytes * (input.size() + 2), 0xcc);
    std::vector<uint> expectedCompact, expectedTriplets;
    std::vector<uint> segment;
    auto flush = [&] {
        uint primitiveCount = mvkPerVertexPrimitiveCount(uint(segment.size()), topology);
        std::vector<uint> pairs(2 * vertices * primitiveCount), triplets(3 * primitiveCount);
        mvkPopulatePerVertexReplay(uint(segment.size()), 1, topology, last, pairs.data(), triplets.data(), nullptr);
        uint base = uint(expectedCompact.size());
        for (uint record : triplets) { expectedTriplets.push_back(base + record); }
        expectedCompact.insert(expectedCompact.end(), segment.begin(), segment.end());
        segment.clear();
    };
    for (uint i = 0; i < input.size(); ++i) {
        uint index = input[i] < 0 ? ~0u : uint(input[i]);
        for (uint b = 0; b < bytes; ++b) { source[(i + 1) * bytes + b] = uint8_t(index >> (8 * b)); }
        if (input[i] < 0) { flush(); } else { segment.push_back(index); }
    }
    flush();
    uint primitives = uint(expectedTriplets.size()) / 3;
    std::vector<uint> compact(mvkPerVertexRestartIndexScratchSize(uint(input.size())) / sizeof(uint) + 2, guard), pairs(2 * vertices * maxPrimitives * instances + 2, guard), triplets(3 * maxPrimitives * instances + 2, guard), corners(vertices * maxPrimitives * instances + 2, guard);
    std::array<uint, 70> args; args.fill(guard);
    uint p[] = {uint(input.size()), instances, bytes, uint(topology), uint(last), 17, uint(withCorners)};
    assemble(source.data() + bytes, compact.data() + 1, pairs.data() + 1, triplets.data() + 1, corners.data() + 1, args.data() + 1, p, 1);
    assert(compact.front() == guard && compact.back() == guard && pairs.front() == guard && pairs.back() == guard && triplets.front() == guard && triplets.back() == guard && corners.front() == guard && corners.back() == guard && args.front() == guard && args.back() == guard);
    for (uint i = 0; i < expectedCompact.size(); ++i) { assert(compact[1 + i] == expectedCompact[i]); }
    assert(args[1] == expectedCompact.size() && args[2] == (expectedCompact.empty() ? 0 : instances) && args[3] == 1);
    assert(args[5] == primitives * vertices && args[6] == (primitives ? instances : 0) && args[7] == 0 && args[8] == 17);
    assert(args[65] == 0 && args[66] == 0 && args[67] == 17 && args[68] == primitives * vertices);
    for (uint instance = 0; instance < instances; ++instance) {
        for (uint primitive = 0; primitive < primitives; ++primitive) {
            uint key = instance * primitives + primitive;
            for (uint corner = 0; corner < 3; ++corner) {
                uint record = instance * uint(input.size()) + expectedTriplets[3 * primitive + corner];
                assert(triplets[1 + 3 * key + corner] == record);
                if (corner >= vertices) { continue; }
                uint occurrence = key * vertices + corner;
                assert(pairs[1 + 2 * occurrence] == record && pairs[2 + 2 * occurrence] == key);
                assert(corners[1 + occurrence] == (withCorners ? corner : guard));
                // Compacted occurrences retain the original per-instance capture stride.
                assert(compact[1 + record % input.size()] + uint(-3) == expectedCompact[record % input.size()] + uint(-3));
                assert(record / input.size() + 17 == instance + 17);
            }
        }
    }
    for (uint i = uint(expectedCompact.size()); i < input.size(); ++i) { assert(compact[1 + i] == guard); }
    for (uint i = primitives * instances * 3; i < maxPrimitives * instances * 3; ++i) { assert(triplets[1 + i] == guard); }
}

static void checkReexecution() {
    uint8_t source[] = {7, 8, 9};
    uint compact[27] = {}, pairs[6] = {}, triplets[3] = {}, corners[3] = {}, args[68] = {};
    uint p[] = {3, 1, 1, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, 0, 19, 1};
    assemble(source, compact, pairs, triplets, corners, args, p);
    assert(args[0] == 3 && args[4] == 3 && args[5] == 1);
    // A later GPU execution can see different index data; all consumer counts must be overwritten.
    for (auto& index : source) { index = 255; }
    assemble(source, compact, pairs, triplets, corners, args, p);
    assert(args[0] == 0 && args[1] == 0 && args[4] == 0 && args[5] == 0 && args[67] == 0);
    source[1] = 42;
    assemble(source, compact, pairs, triplets, corners, args, p);
    assert(args[0] == 1 && args[1] == 1 && compact[0] == 42 && args[4] == 0 && args[5] == 0);
}

#ifdef MVK_RESTART_GPU_TESTS
int main(int argc, char** argv) {
    @autoreleasepool {
        assert(argc == 2 || argc == 3);
        serialBaseline = argc == 3 && std::strcmp(argv[2], "serial") == 0;
        gpu = MTLCreateSystemDefaultDevice();
        if (!gpu) { std::fputs("FAIL: no Metal device\n", stderr); return 1; }
        queue = [gpu newCommandQueue];
        NSError* error = nil;
        NSString* source = [NSString stringWithContentsOfFile:[NSString stringWithUTF8String:argv[1]] encoding:NSUTF8StringEncoding error:&error];
        if (!source || serialBaseline != [source containsString:@"for (uint i = 0; i < p[0]; ++i)"]) { std::fputs("FAIL: serial mode requires the pre-parallel restart kernel; parallel mode requires the current kernel\n", stderr); return 1; }
        source = [source stringByAppendingString:@"\nkernel void testCapture(const device uint* indices [[buffer(0)]], device uint2* records [[buffer(1)]], uint3 gid [[thread_position_in_grid]], uint3 size [[grid_size]], uint3 origin [[grid_origin]]) { if (any(gid >= size)) return; records[gid.y * size.x + gid.x] = uint2(indices[gid.x] + origin.x, gid.y + origin.y); }\n"];
        MTLCompileOptions* options = [MTLCompileOptions new];
        options.languageVersion = MTLLanguageVersion2_4;
        id<MTLLibrary> library = [gpu newLibraryWithSource:source options:options error:&error];
        if (!library) { std::fprintf(stderr, "FAIL: Metal library: %s\n", error.description.UTF8String); return 1; }
        pipeline = [gpu newComputePipelineStateWithFunction:[library newFunctionWithName:@"perVertexRestart"] error:&error];
        if (!pipeline) { std::fprintf(stderr, "FAIL: Metal pipeline: %s\n", error.description.UTF8String); return 1; }
        capturePipeline = [gpu newComputePipelineStateWithFunction:[library newFunctionWithName:@"testCapture"] error:&error];
        if (!capturePipeline) { std::fprintf(stderr, "FAIL: capture pipeline: %s\n", error.description.UTF8String); return 1; }
        std::printf("Device: %s\n", gpu.name.UTF8String);
        // Optional comparison stays inside the original serial kernel's admitted boundary.
        if (argc == 3) {
            assert(serialBaseline || std::strcmp(argv[2], "parallel") == 0);
            capturePipeline = nil; // Keep the optional serial/parallel timings assembly-only.
            std::vector<int64_t> input(65536, 9);
            for (uint i = 127; i < input.size(); i += 257) { input[i] = -1; }
            for (uint repeat = 0; repeat < 6; ++repeat) { check(input, 4, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, 1, true); }
            std::puts("PASS: bounded 65536-index comparison, exact CPU oracle and guards");
            return 0;
        }
        checkReexecution();
        check({7, 8, 9, -1, 10, 11, 12}, 4, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, false, 2, true);
        for (uint topology = 0; topology <= 5; ++topology) {
            @autoreleasepool {
                check({}, 4, VkPrimitiveTopology(topology), false, 1, true);
                check(std::vector<int64_t>(65537, 9), 4, VkPrimitiveTopology(topology), false, 2, true);
                check(std::vector<int64_t>(131073, -1), 1, VkPrimitiveTopology(topology), true, 3, true);
                for (uint bytes : {1u, 2u, 4u}) {
                    for (bool last : {false, true}) {
                        std::vector<int64_t> input(131073, 9);
                        for (uint i = 0; i < input.size(); ++i) { input[i] = i % 31; }
                        for (uint step = 1; step < input.size(); step *= 2) { input[step - 1] = -1; input[step] = -1; if (step + 1 < input.size()) { input[step + 1] = -1; } }
                        check(input, bytes, VkPrimitiveTopology(topology), last, 3, bytes != 1);
                    }
                }
            }
        }
        check(std::vector<int64_t>(1048577, 9), 4, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, 2, true);
        std::puts("PASS: bounded GPU restart matrix, exact CPU oracle and guards");
    }
}
#else
int main() {
    checkReexecution();
    assert(mvkCanAssemblePerVertexRestart(65536, 1, true));
    assert(mvkCanAssemblePerVertexRestart(16384, 4, true));
    assert(mvkCanAssemblePerVertexRestart(65537, 1, true));
    assert(mvkCanAssemblePerVertexRestart(16385, 4, true));
    assert(!mvkCanAssemblePerVertexRestart(UINT32_MAX, UINT32_MAX, true));
    assert(!mvkCanAssemblePerVertexRestart(3, 1, false));
    assert(mvkPerVertexRestartIndexScratchSize(UINT32_MAX) == uint64_t(UINT32_MAX) * 36);
    unsigned cases = 0;
    for (uint topology = 0; topology <= 5; ++topology) {
        for (uint bytes : {1u, 2u, 4u}) {
            for (bool last : {false, true}) {
                for (uint instances : {1u, 3u}) {
                    for (uint mask = 0; mask < 1024; ++mask) {
                        std::vector<int64_t> input;
                        for (uint i = 0; i < 10; ++i) { input.push_back(mask & (1u << i) ? -1 : int(i % 4 + 7)); }
                        check(input, bytes, VkPrimitiveTopology(topology), last, instances, mask & 1);
                        ++cases;
                    }
                    for (const auto& input : std::vector<std::vector<int64_t>>{{}, {7}, {-1}, {7, 8}, {-1, 7, 8, 9, 10, 11, -1, -1, 12, 13, 14, 15, 16, 17, -1}}) { check(input, bytes, VkPrimitiveTopology(topology), last, instances, true); ++cases; }
                    // Width-specific sentinels: 255/65535 remain ordinary larger-width indices.
                    check({int64_t(bytes == 1 ? 254 : bytes == 2 ? 65534 : UINT32_MAX - 1), 255 - (bytes == 1), 7, -1, 8, 9, 10}, bytes, VkPrimitiveTopology(topology), last, instances, true);
                }
            }
        }
    }
    check(std::vector<int64_t>(65536, 9), 4, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, 1, true);
    check(std::vector<int64_t>(16384, 9), 1, VK_PRIMITIVE_TOPOLOGY_LINE_STRIP, false, 4, true);
    for (uint topology = 0; topology <= 5; ++topology) {
        for (bool last : {false, true}) {
            for (uint count : {65535u, 65536u, 65537u, 131073u}) {
                std::vector<int64_t> input(count, 9);
                check(input, 4, VkPrimitiveTopology(topology), last, 2, true);
                // Restart boundaries around prefix-pass powers of two, including consecutive markers.
                for (uint step = 1; step < count; step *= 2) {
                    input[step - 1] = -1;
                    input[step] = -1;
                    if (step + 1 < count) { input[step + 1] = -1; }
                }
                check(input, 2, VkPrimitiveTopology(topology), last, 3, true);
                ++cases;
            }
        }
    }
    std::printf("PASS: %u restart patterns plus large boundaries, all portable topologies/widths/provoking modes, instances and guards (production parallel kernel, CPU only)\n", cases);
}
#endif
