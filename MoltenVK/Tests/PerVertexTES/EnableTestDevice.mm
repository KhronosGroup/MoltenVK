// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
// Linked only by the TES and mesh test drivers, never by shipping CMake/Xcode targets.
#include "MVKDevice.h"
#include "MVKCommandPool.h"
#include "MVKSwapchain.h"
struct TestPhysicalDevice : MVKPhysicalDevice {
    static void enable(MVKPhysicalDevice* device) {
        // Use the same initialization convention as MVKPhysicalDevice::initExtensions.
        auto& extensions = const_cast<MVKExtensionList&>(device->* &TestPhysicalDevice::_supportedExtensions);
        // The adapter selects the experimental capture and replay path, where Metal has barycentric coordinates.
        extensions.vk_KHR_fragment_shader_barycentric.enabled = device->getMetalFeatures()->shaderBarycentricCoordinates;
        device->* &TestPhysicalDevice::_portablePerVertexEnabled = extensions.vk_KHR_fragment_shader_barycentric.enabled;
    }
    // Reproduces a GPU whose Metal buffers are smaller, before the device is created.
    static void limitMetalBufferSize(MVKPhysicalDevice* device, uint64_t size) {
        auto& features = const_cast<MVKPhysicalDeviceMetalFeatures&>(device->* &TestPhysicalDevice::_metalFeatures);
        features.maxMTLBufferSize = std::min<uint64_t>(features.maxMTLBufferSize, size);
    }
    // Mesh shaders need a Metal 3 GPU.
    static void enableMesh(MVKPhysicalDevice* device) {
        auto& extensions = const_cast<MVKExtensionList&>(device->* &TestPhysicalDevice::_supportedExtensions);
        extensions.vk_EXT_mesh_shader.enabled = [device->getMTLDevice() supportsFamily:MTLGPUFamilyMetal3];
    }
};
extern "C" void mvkEnableTESFixtureDevice(VkPhysicalDevice device) {
    TestPhysicalDevice::enable(MVKPhysicalDevice::getMVKPhysicalDevice(device));
}
extern "C" void mvkEnableMeshTestDevice(VkPhysicalDevice device) {
    TestPhysicalDevice::enableMesh(MVKPhysicalDevice::getMVKPhysicalDevice(device));
}
extern "C" void mvkTestLimitMetalBufferSize(VkPhysicalDevice device, uint64_t size) {
    TestPhysicalDevice::limitMetalBufferSize(MVKPhysicalDevice::getMVKPhysicalDevice(device), size);
}
// Loses the device as an encoder does, so that device loss tests choose the moment of the loss.
extern "C" void mvkTestMarkDeviceLost(VkDevice device) {
    MVKDevice::getMVKDevice(device)->markLost();
}
struct TestDevice : MVKDevice {
    static void getLossCounters(MVKDevice* device, int64_t* pendingHandlers, uint32_t* activeEncodings) {
        *pendingHandlers = (device->* &TestDevice::_pendingMTLCommandBufferHandlers).load();
        *activeEncodings = (device->* &TestDevice::_activeEncodings).load();
    }
};
// The counts that a device loss report waits for: handlers of committed Metal command buffers, and queue submissions
// still encoding. A loss test reads them when a host wait returns the loss, which must find both at zero.
extern "C" void mvkTestGetLossCounters(VkDevice device, int64_t* pendingHandlers, uint32_t* activeEncodings) {
    TestDevice::getLossCounters(MVKDevice::getMVKDevice(device), pendingHandlers, activeEncodings);
}

struct TestAllocationPool : MVKMTLBufferAllocationPool {
    static uint64_t outstanding(MVKMTLBufferAllocationPool* pool) {
        uint64_t count = 0;
        for (auto& tracker : pool->* &TestAllocationPool::_mtlBuffers) { count += tracker.allocationCount; }
        return count;
    }
};
struct TestAllocator : MVKMTLBufferAllocator {
    static uint64_t outstanding(MVKMTLBufferAllocator* allocator) {
        uint64_t count = 0;
        for (auto* pool : allocator->* &TestAllocator::_regionPools) { count += TestAllocationPool::outstanding(pool); }
        return count;
    }
};
struct TestEncodingPool : MVKCommandEncodingPool {
    static uint64_t outstanding(MVKCommandEncodingPool* pool) {
        return TestAllocator::outstanding(&(pool->* &TestEncodingPool::_mtlBufferAllocator))
             + TestAllocator::outstanding(&(pool->* &TestEncodingPool::_privateMtlBufferAllocator))
             + TestAllocator::outstanding(&(pool->* &TestEncodingPool::_dedicatedMtlBufferAllocator));
    }
};
// The temporary Metal buffer allocations of a command pool that have not been returned to it: a cleanup test checks
// that each one returns exactly once.
extern "C" uint64_t mvkTestGetOutstandingCommandPoolAllocations(VkCommandPool commandPool) {
    return TestEncodingPool::outstanding(((MVKCommandPool*)commandPool)->getCommandEncodingPool());
}
struct TestSwapchain : MVKSwapchain {
    static uint32_t unpresented(MVKSwapchain* swapchain) { return (swapchain->* &TestSwapchain::_unpresentedImageCount).load(); }
};
// The presentations of a swapchain that have begun and not ended: a presentation test checks that its presentations
// have begun before it destroys the swapchain.
extern "C" uint32_t mvkTestGetUnpresentedImageCount(VkSwapchainKHR swapchain) {
    return TestSwapchain::unpresented((MVKSwapchain*)swapchain);
}
