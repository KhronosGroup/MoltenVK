// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <vulkan/vulkan.h>
#include <cassert>
#include <cstdio>
#include <unordered_map>
#include <vector>
struct MVKGraphicsPipeline {
    struct States { id<MTLRenderPipelineState> direct = nil; id<MTLComputePipelineState> index16 = nil, index32 = nil; };
    std::unordered_map<uint32_t, States> _perVertexCapturePipelineStates;
    id<MTLRenderPipelineState> _mtlPerVertexCapturePipelineState = nil;
    struct Translation { uint32_t binding, translationBinding; };
    std::vector<Translation> _translatedVertexBindings{{0, 5}};
    struct Device {
        std::vector<uint32_t> groups{2, 1, 2, 3};
        uint32_t getMultiviewMetalPassCount(uint32_t) { return uint32_t(groups.size()); }
        uint32_t getViewCountInMetalPass(uint32_t, uint32_t pass) { return groups[pass]; }
    } device;
    VkPipelineRenderingCreateInfo rendering{};
    VkResult result = VK_SUCCESS;
    const auto* getRenderingCreateInfo(const VkGraphicsPipelineCreateInfo*) { return &rendering; }
    auto* getDevice() { return &device; }
    uint32_t getMetalBufferIndexForVertexAttributeBinding(uint32_t binding) { return binding; }
    VkResult reportError(VkResult result, const char*) { return result; }
    void setConfigurationResult(VkResult error) { result = error; }
    void adjustVertexInputForMultiview(MTLVertexDescriptor*, const VkPipelineVertexInputStateCreateInfo*, uint32_t, uint32_t = 1);
    bool addPerVertexIndexedCapturePipelines(MTLVertexDescriptor*, int, const void*, uint32_t);
    bool build(MTLRenderPipelineDescriptor*, const VkGraphicsPipelineCreateInfo*);
    bool getOrCompilePipeline(MTLRenderPipelineDescriptor* desc, id<MTLRenderPipelineState>& state) { state = (id<MTLRenderPipelineState>)[desc copy]; return true; }
    id<MTLRenderPipelineState> getPerVertexCapturePipelineState(uint32_t) const;
    id<MTLComputePipelineState> getPerVertexIndexedCapturePipelineState(bool, uint32_t) const;
    ~MVKGraphicsPipeline() {
        for (auto& entry : _perVertexCapturePipelineStates) { [entry.second.direct release]; [entry.second.index16 release]; [entry.second.index32 release]; }
        [_mtlPerVertexCapturePipelineState release];
    }
};
#include "CaptureVariantMethods.inc"
int main() {
    @autoreleasepool {
        VkVertexInputBindingDescription bindings[] = {{0, 16, VK_VERTEX_INPUT_RATE_INSTANCE}, {1, 16, VK_VERTEX_INPUT_RATE_INSTANCE}, {2, 16, VK_VERTEX_INPUT_RATE_VERTEX}};
        VkPipelineVertexInputStateCreateInfo input{};
        input.vertexBindingDescriptionCount = 3; input.pVertexBindingDescriptions = bindings;
        VkGraphicsPipelineCreateInfo info{}; info.pVertexInputState = &input;
        auto* descriptor = [MTLRenderPipelineDescriptor new];
        descriptor.vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
        for (uint32_t i : {0u, 5u}) {
            descriptor.vertexDescriptor.layouts[i].stride = 16;
            descriptor.vertexDescriptor.layouts[i].stepFunction = MTLVertexStepFunctionPerInstance;
            descriptor.vertexDescriptor.layouts[i].stepRate = 3;
        }
        descriptor.vertexDescriptor.layouts[1].stepFunction = MTLVertexStepFunctionConstant;
        descriptor.vertexDescriptor.layouts[1].stepRate = 0;
        descriptor.vertexDescriptor.layouts[2].stepFunction = MTLVertexStepFunctionPerVertex;
        descriptor.vertexDescriptor.layouts[2].stepRate = 1;
        {
            MVKGraphicsPipeline pipeline;
            pipeline.rendering.viewMask = 0x71b;
            assert(pipeline.build(descriptor, &info));
            assert(pipeline._perVertexCapturePipelineStates.size() == 3);
            for (uint32_t views : {1u, 2u, 3u}) {
                auto* direct = (MTLRenderPipelineDescriptor*)pipeline.getPerVertexCapturePipelineState(views);
                assert(direct && direct.vertexDescriptor.layouts[0].stepRate == 3 * views);
                assert(direct.vertexDescriptor.layouts[5].stepRate == 3 * views);
                assert(direct.vertexDescriptor.layouts[1].stepRate == 0 && direct.vertexDescriptor.layouts[2].stepRate == 1);
                for (bool index32 : {false, true}) {
                    auto* indexed = (MTLStageInputOutputDescriptor*)pipeline.getPerVertexIndexedCapturePipelineState(index32, views);
                    assert(indexed && indexed.layouts[0].stepRate == 3 * views && indexed.layouts[5].stepRate == 3 * views);
                    assert(indexed.layouts[0].stepFunction == MTLStepFunctionThreadPositionInGridY);
                    assert(indexed.layouts[2].stepFunction == MTLStepFunctionThreadPositionInGridXIndexed);
                    assert(indexed.layouts[1].stepRate == 0 && indexed.layouts[2].stepRate == 1);
                }
            }
            assert(!pipeline.getPerVertexCapturePipelineState(4) && !pipeline.getPerVertexIndexedCapturePipelineState(false, 4));
        }
        {
            MVKGraphicsPipeline pipeline;
            pipeline.rendering.viewMask = 3;
            descriptor.vertexDescriptor.layouts[0].stepRate = UINT32_MAX;
            descriptor.vertexDescriptor.layouts[5].stepRate = UINT32_MAX;
            assert(!pipeline.build(descriptor, &info));
            assert(pipeline.result == VK_ERROR_FEATURE_NOT_PRESENT && pipeline._perVertexCapturePipelineStates.empty());
        }
        [descriptor release];
    }
    puts("production capture variants, translated/divisor-zero layouts, indexed step mapping, runtime getters and divisor overflow: PASS (no GPU)");
}
