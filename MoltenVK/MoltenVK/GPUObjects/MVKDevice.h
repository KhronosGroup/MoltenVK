/*
 * MVKDevice.h
 *
 * Copyright (c) 2014-2018 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "MVKBaseObject.h"
#include "MVKLayers.h"
#include "vk_mvk_moltenvk.h"
#include <vector>
#include <string>
#include <mutex>

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

class MVKInstance;
class MVKDevice;
class MVKQueue;
class MVKQueueFamily;
class MVKSurface;
class MVKSemaphoreImpl;
class MVKResource;
class MVKBuffer;
class MVKBufferView;
class MVKImage;
class MVKSwapchainImage;
class MVKImageView;
class MVKSwapchain;
class MVKDeviceMemory;
class MVKFence;
class MVKSemaphore;
class MVKQueryPool;
class MVKShaderModule;
class MVKPipelineCache;
class MVKPipelineLayout;
class MVKPipeline;
class MVKSampler;
class MVKDescriptorSetLayout;
class MVKDescriptorPool;
class MVKFramebuffer;
class MVKRenderPass;
class MVKCommandPool;
class MVKCommandEncoder;
class MVKCommandResourceFactory;


/** The buffer index to use for vertex content. */
const static uint32_t kMVKVertexContentBufferIndex = 0;


#pragma mark -
#pragma mark MVKPhysicalDevice

/** Represents a Vulkan physical GPU device. */
class MVKPhysicalDevice : public MVKDispatchableObject {

public:

	/** Populates the specified structure with the features of this device. */
	void getFeatures(VkPhysicalDeviceFeatures* features);

	/** Populates the specified structure with the Metal-specific features of this device. */
	void getMetalFeatures(MVKPhysicalDeviceMetalFeatures* mtlFeatures);

	/** Populates the specified structure with the properties of this device. */
	void getProperties(VkPhysicalDeviceProperties* properties);

	/** Populates the specified structure with the format properties of this device. */
	void getFormatProperties(VkFormat format, VkFormatProperties* pFormatProperties);

    /** 
     * Populates the specified structure with the image format properties
     * supported for the specified image characteristics on this device.
     */
    VkResult getImageFormatProperties(VkFormat format,
                                      VkImageType type,
                                      VkImageTiling tiling,
                                      VkImageUsageFlags usage,
                                      VkImageCreateFlags flags,
                                      VkImageFormatProperties* pImageFormatProperties);

#pragma mark Surfaces

	/**
	 * Queries whether this device supports presentation to the specified surface,
	 * using a queue of the specified queue family.
	 */
	VkResult getSurfaceSupport(uint32_t queueFamilyIndex, MVKSurface* surface, VkBool32* pSupported);

	/** Returns the capabilities of the specified surface. */
	VkResult getSurfaceCapabilities(MVKSurface* surface, VkSurfaceCapabilitiesKHR* pSurfaceCapabilities);

	/**
	 * Returns the pixel formats supported by the surface described by the specified
	 * surface description.
	 *
	 * If pSurfaceFormats is null, the value of pCount is updated with the number of
	 * pixel formats supported by the surface.
	 *
	 * If pSurfaceFormats is not null, then pCount formats are copied into the array.
	 * If the number of available formats is less than pCount, the value of pCount is
	 * updated to indicate the number of formats actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of supported
	 * formats is larger than pCount. Returns other values if an error occurs.
	 */
	VkResult getSurfaceFormats(MVKSurface* surface, uint32_t* pCount, VkSurfaceFormatKHR* pSurfaceFormats);

	/**
	 * Returns the presentation modes supported by the surface described by the specified
	 * surface description.
	 *
	 * If pPresentModes is null, the value of pCount is updated with the number of
	 * presentation modes supported by the surface.
	 *
	 * If pPresentModes is not null, then pCount presentation modes are copied into the array.
	 * If the number of available modes is less than pCount, the value of pCount is updated
	 * to indicate the number of presentation modes actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of supported
	 * presentation modes is larger than pCount. Returns other values if an error occurs.
	 */
	VkResult getSurfacePresentModes(MVKSurface* surface, uint32_t* pCount, VkPresentModeKHR* pPresentModes);


#pragma mark Queues

	/**
	 * If properties is null, the value of pCount is updated with the number of
	 * queue families supported by this instance.
	 *
	 * If properties is not null, then pCount queue family properties are copied into the 
	 * array. If the number of available queue families is less than pCount, the value of 
	 * pCount is updated to indicate the number of queue families actually returned in the array.
	 *
	 * Returns VK_SUCCESS if successful. Returns VK_INCOMPLETE if the number of queue families
	 * available in this instance is larger than the specified pCount. Returns other values if
	 * an error occurs.
	 */
	VkResult getQueueFamilyProperties(uint32_t* pCount, VkQueueFamilyProperties* properties);

	/** Returns a pointer to the layer manager for this device. */
	inline MVKLayerManager* getLayerManager() { return MVKLayerManager::globalManager(); }


#pragma mark Memory models

	/** Returns a pointer to the memory characteristics of this device. */
    inline const VkPhysicalDeviceMemoryProperties* getPhysicalDeviceMemoryProperties() { return &_memoryProperties; }

	/** Populates the specified memory properties with the memory characteristics of this device. */
	VkResult getPhysicalDeviceMemoryProperties(VkPhysicalDeviceMemoryProperties* pMemoryProperties);

	/**
	 * Returns a bit mask of all memory type indices. 
	 * Each bit [0..31] in the returned bit mask indicates a distinct memory type.
	 */
	inline uint32_t getAllMemoryTypes() { return _allMemoryTypes; }

	/**
	 * Returns a bit mask of all memory type indices that allow host visibility to the memory. 
	 * Each bit [0..31] in the returned bit mask indicates a distinct memory type.
	 */
	inline uint32_t getHostVisibleMemoryTypes() { return _hostVisibleMemoryTypes; }

	/**
	 * Returns a bit mask of all memory type indices that do NOT allow host visibility to the memory.
	 * Each bit [0..31] in the returned bit mask indicates a distinct memory type.
	 */
	inline uint32_t getPrivateMemoryTypes() { return _privateMemoryTypes; }

	
#pragma mark Metal

	/** Returns the underlying Metal device. */
	inline id<MTLDevice> getMTLDevice() { return _mtlDevice; }


#pragma mark Construction

	/** Constructs an instance wrapping the specified Vulkan instance and Metal device. */
	MVKPhysicalDevice(MVKInstance* mvkInstance, id<MTLDevice> mtlDevice);

	/** Default destructor. */
	~MVKPhysicalDevice() override;

    /**
     * Returns a reference to this object suitable for use as a Vulkan API handle.
     * This is the compliment of the getMVKPhysicalDevice() method.
     */
    inline VkPhysicalDevice getVkPhysicalDevice() { return (VkPhysicalDevice)getVkHandle(); }

    /**
     * Retrieves the MVKPhysicalDevice instance referenced by the VkPhysicalDevice handle.
     * This is the compliment of the getVkPhysicalDevice() method.
     */
    static inline MVKPhysicalDevice* getMVKPhysicalDevice(VkPhysicalDevice vkPhysicalDevice) {
        return (MVKPhysicalDevice*)getDispatchableObject(vkPhysicalDevice);
    }

protected:
	friend class MVKDevice;

	MTLFeatureSet getMaximalMTLFeatureSet();
    void initMetalFeatures();
	void initFeatures();
	void initProperties();
	void initMemoryProperties();
	void initQueueFamilies();
	void initPipelineCacheUUID();
	MTLFeatureSet getHighestMTLFeatureSet();
	void logGPUInfo();

	id<MTLDevice> _mtlDevice;
	MVKInstance* _mvkInstance;
	VkPhysicalDeviceFeatures _features;
	MVKPhysicalDeviceMetalFeatures _metalFeatures;
	VkPhysicalDeviceProperties _properties;
	VkPhysicalDeviceMemoryProperties _memoryProperties;
	std::vector<MVKQueueFamily*> _queueFamilies;
	uint32_t _allMemoryTypes;
	uint32_t _hostVisibleMemoryTypes;
	uint32_t _privateMemoryTypes;
};


#pragma mark -
#pragma mark MVKDevice

/** Represents a Vulkan logical GPU device, associated with a physical device. */
class MVKDevice : public MVKDispatchableObject {

public:

	/** Returns the physical device underlying this logical device. */
	inline MVKPhysicalDevice* getPhysicalDevice() { return _physicalDevice; }

    /** Returns the common resource factory for creating command resources. */
    inline MVKCommandResourceFactory* getCommandResourceFactory() { return _commandResourceFactory; }

	/** Returns the function pointer corresponding to the specified named entry point. */
	PFN_vkVoidFunction getProcAddr(const char* pName);

	/** Retrieves a queue at the specified index within the specified family. */
	VkResult getDeviceQueue(uint32_t queueFamilyIndex, uint32_t queueIndex, VkQueue* pQueue);

	/** Block the current thread until all queues in this device are idle. */
	VkResult waitIdle();


#pragma mark Object lifecycle

	MVKBuffer* createBuffer(const VkBufferCreateInfo* pCreateInfo,
							const VkAllocationCallbacks* pAllocator);
	void destroyBuffer(MVKBuffer* mvkBuff,
					   const VkAllocationCallbacks* pAllocator);

    MVKBufferView* createBufferView(const VkBufferViewCreateInfo* pCreateInfo,
                                    const VkAllocationCallbacks* pAllocator);
    void destroyBufferView(MVKBufferView* mvkBuffView,
                       const VkAllocationCallbacks* pAllocator);

	MVKImage* createImage(const VkImageCreateInfo* pCreateInfo,
						  const VkAllocationCallbacks* pAllocator);
	void destroyImage(MVKImage* mvkImg,
					  const VkAllocationCallbacks* pAllocator);

	MVKImageView* createImageView(const VkImageViewCreateInfo* pCreateInfo,
								  const VkAllocationCallbacks* pAllocator);
	void destroyImageView(MVKImageView* mvkImgView, const VkAllocationCallbacks* pAllocator);

	MVKSwapchain* createSwapchain(const VkSwapchainCreateInfoKHR* pCreateInfo,
								  const VkAllocationCallbacks* pAllocator);
	void destroySwapchain(MVKSwapchain* mvkSwpChn,
						  const VkAllocationCallbacks* pAllocator);

	MVKSwapchainImage* createSwapchainImage(const VkImageCreateInfo* pCreateInfo,
											MVKSwapchain* swapchain,
											const VkAllocationCallbacks* pAllocator);
	void destroySwapchainImage(MVKSwapchainImage* mvkImg,
							   const VkAllocationCallbacks* pAllocator);

	MVKFence* createFence(const VkFenceCreateInfo* pCreateInfo,
						  const VkAllocationCallbacks* pAllocator);
	void destroyFence(MVKFence* mvkFence,
					  const VkAllocationCallbacks* pAllocator);

	MVKSemaphore* createSemaphore(const VkSemaphoreCreateInfo* pCreateInfo,
								  const VkAllocationCallbacks* pAllocator);
	void destroySemaphore(MVKSemaphore* mvkSem4,
						  const VkAllocationCallbacks* pAllocator);

	MVKQueryPool* createQueryPool(const VkQueryPoolCreateInfo* pCreateInfo,
								  const VkAllocationCallbacks* pAllocator);
	void destroyQueryPool(MVKQueryPool* mvkQP,
						  const VkAllocationCallbacks* pAllocator);

	MVKShaderModule* createShaderModule(const VkShaderModuleCreateInfo* pCreateInfo,
										const VkAllocationCallbacks* pAllocator);
	void destroyShaderModule(MVKShaderModule* mvkShdrMod,
							 const VkAllocationCallbacks* pAllocator);

	MVKPipelineCache* createPipelineCache(const VkPipelineCacheCreateInfo* pCreateInfo,
										  const VkAllocationCallbacks* pAllocator);
	void destroyPipelineCache(MVKPipelineCache* mvkPLC,
							  const VkAllocationCallbacks* pAllocator);

	MVKPipelineLayout* createPipelineLayout(const VkPipelineLayoutCreateInfo* pCreateInfo,
											const VkAllocationCallbacks* pAllocator);
	void destroyPipelineLayout(MVKPipelineLayout* mvkPLL,
							   const VkAllocationCallbacks* pAllocator);

    /**
     * Template function that creates count number of pipelines of type PipelineType,
     * using a collection of configuration information of type PipelineInfoType,
     * and adds the new pipelines to the specified pipeline cache.
     */
    template<typename PipelineType, typename PipelineInfoType>
    VkResult createPipelines(VkPipelineCache pipelineCache,
                             uint32_t count,
                             const PipelineInfoType* pCreateInfos,
                             const VkAllocationCallbacks* pAllocator,
                             VkPipeline* pPipelines);
    void destroyPipeline(MVKPipeline* mvkPPL,
                         const VkAllocationCallbacks* pAllocator);

	MVKSampler* createSampler(const VkSamplerCreateInfo* pCreateInfo,
							  const VkAllocationCallbacks* pAllocator);
	void destroySampler(MVKSampler* mvkSamp,
						const VkAllocationCallbacks* pAllocator);

	MVKDescriptorSetLayout* createDescriptorSetLayout(const VkDescriptorSetLayoutCreateInfo* pCreateInfo,
													  const VkAllocationCallbacks* pAllocator);
	void destroyDescriptorSetLayout(MVKDescriptorSetLayout* mvkDSL,
									const VkAllocationCallbacks* pAllocator);

	MVKDescriptorPool* createDescriptorPool(const VkDescriptorPoolCreateInfo* pCreateInfo,
											const VkAllocationCallbacks* pAllocator);
	void destroyDescriptorPool(MVKDescriptorPool* mvkDP,
							   const VkAllocationCallbacks* pAllocator);

	MVKFramebuffer* createFramebuffer(const VkFramebufferCreateInfo* pCreateInfo,
									  const VkAllocationCallbacks* pAllocator);
	void destroyFramebuffer(MVKFramebuffer* mvkFB,
							const VkAllocationCallbacks* pAllocator);

	MVKRenderPass* createRenderPass(const VkRenderPassCreateInfo* pCreateInfo,
									const VkAllocationCallbacks* pAllocator);
	void destroyRenderPass(MVKRenderPass* mvkRP,
						   const VkAllocationCallbacks* pAllocator);

	MVKCommandPool* createCommandPool(const VkCommandPoolCreateInfo* pCreateInfo,
									  const VkAllocationCallbacks* pAllocator);
	void destroyCommandPool(MVKCommandPool* mvkCmdPool,
							const VkAllocationCallbacks* pAllocator);

	MVKDeviceMemory* allocateMemory(const VkMemoryAllocateInfo* pAllocateInfo,
									const VkAllocationCallbacks* pAllocator);
	void freeMemory(MVKDeviceMemory* mvkDevMem,
					const VkAllocationCallbacks* pAllocator);

	/** Applies the specified global memory barrier to all resource issued by this device. */
	void applyMemoryBarrier(VkPipelineStageFlags srcStageMask,
							VkPipelineStageFlags dstStageMask,
							VkMemoryBarrier* pMemoryBarrier,
                            MVKCommandEncoder* cmdEncoder,
                            MVKCommandUse cmdUse);

    /**
	 * If performance is being tracked, returns a monotonic timestamp value for use performance timestamping.
	 *
	 * The returned value corresponds to the number of CPU "ticks" since the app was initialized.
	 *
	 * Calling this value twice, subtracting the first value from the second, and then multiplying
	 * the result by the value returned by mvkGetTimestampPeriod() will provide an indication of the
	 * number of nanoseconds between the two calls. The convenience function mvkGetElapsedMilliseconds()
	 * can be used to perform this calculation.
     */
    inline uint64_t getPerformanceTimestamp() {
		return _mvkConfig.performanceTracking ? getPerformanceTimestampImpl() : 0;
	}

    /**
     * If performance is being tracked, adds the performance for an activity with a duration
     * interval between the start and end times, to the given performance statistics.
     *
     * If endTime is zero or not supplied, the current time is used.
     */
    inline void addActivityPerformance(MVKPerformanceTracker& shaderCompilationEvent,
									   uint64_t startTime, uint64_t endTime = 0) {
		if (_mvkConfig.performanceTracking) {
			addActivityPerformanceImpl(shaderCompilationEvent, startTime, endTime);
		}
	};

    /** Populates the specified statistics structure from the current activity performance statistics. */
    void getPerformanceStatistics(MVKPerformanceStatistics* pPerf);


#pragma mark Metal

	/** Returns the underlying Metal device. */
	inline id<MTLDevice> getMTLDevice() { return _physicalDevice->getMTLDevice(); }

	/** Returns the Metal vertex buffer index to use for the specified vertex attribute binding number.  */
	uint32_t getMetalBufferIndexForVertexAttributeBinding(uint32_t binding);

	/**
	 * Returns the Metal MTLPixelFormat corresponding to the specified Vulkan VkFormat,
	 * or returns MTLPixelFormatInvalid if no corresponding MTLPixelFormat exists.
	 *
	 * This function uses the MoltenVK API function mvkMTLPixelFormatFromVkFormat(), but 
     * not all MTLPixelFormats returned by that API function are supported by all GPU's.
	 * This function may substitute and return a MTLPixelFormat value that is different than
	 * the value returned by the mvkMTLPixelFormatFromVkFormat() function, but is compatible
	 * with the GPU underlying this instance.
	 *
	 * Not all macOS GPU's support the MTLPixelFormatDepth24Unorm_Stencil8 pixel format, and
	 * in that case, this function will return MTLPixelFormatDepth32Float_Stencil8 instead.
	 *
	 * All other pixel formats are returned unchanged.
	 */
	MTLPixelFormat mtlPixelFormatFromVkFormat(VkFormat vkFormat);

    /** 
     * Returns the MTLBuffer used to hold occlusion query results, 
     * when all query pools use the same MTLBuffer.
     */
    id<MTLBuffer> getGlobalVisibilityResultMTLBuffer();

    /**
     * Expands the visibility results buffer, used for occlusion queries, by replacing the
     * existing buffer with a new MTLBuffer that is large enough to accommodate all occlusion
     * queries created to date, including those defined in the specified query pool.
     * Returns the previous query count, before the new queries were added, which can
     * be used by the new query pool to locate its queries within the single large buffer.
     */
    uint32_t expandVisibilityResultMTLBuffer(uint32_t queryCount);

    /** Returns the memory type index corresponding to the specified Metal memory storage mode. */
    uint32_t getVulkanMemoryTypeIndex(MTLStorageMode mtlStorageMode);


#pragma mark Properties directly accessible

	/** Pointer to the feature set of the underlying physical device. */
	const VkPhysicalDeviceFeatures* _pFeatures;

	/** Pointer to the Metal-specific features of the underlying physical device. */
	const MVKPhysicalDeviceMetalFeatures* _pMetalFeatures;

	/** Pointer to the properties of the underlying physical device. */
	const VkPhysicalDeviceProperties* _pProperties;

	/** Pointer to the memory properties of the underlying physical device. */
	const VkPhysicalDeviceMemoryProperties* _pMemoryProperties;

    /** The MoltenVK configuration settings for this device. */
    const MVKDeviceConfiguration _mvkConfig;

    /** Performance statistics. */
    MVKPerformanceStatistics _performanceStatistics;


#pragma mark Construction

	/** Constructs an instance on the specified physical device. */
	MVKDevice(MVKPhysicalDevice* physicalDevice, const VkDeviceCreateInfo* pCreateInfo);

	~MVKDevice() override;

    /**
     * Returns a reference to this object suitable for use as a Vulkan API handle.
     * This is the compliment of the getMVKDevice() method.
     */
    inline VkDevice getVkDevice() { return (VkDevice)getVkHandle(); }

    /**
     * Retrieves the MVKDevice instance referenced by the VkDevice handle.
     * This is the compliment of the getVkDevice() method.
     */
    static inline MVKDevice* getMVKDevice(VkDevice vkDevice) {
        return (MVKDevice*)getDispatchableObject(vkDevice);
    }

protected:
	MVKResource* addResource(MVKResource* rez);
	MVKResource* removeResource(MVKResource* rez);
    void initPerformanceTracking();
    const char* getActivityPerformanceDescription(MVKPerformanceTracker& shaderCompilationEvent);
	uint64_t getPerformanceTimestampImpl();
	void addActivityPerformanceImpl(MVKPerformanceTracker& shaderCompilationEvent,
									uint64_t startTime, uint64_t endTime);

	MVKPhysicalDevice* _physicalDevice;
    MVKCommandResourceFactory* _commandResourceFactory;
	std::vector<std::vector<MVKQueue*>> _queuesByQueueFamilyIndex;
	std::vector<MVKResource*> _resources;
	std::mutex _rezLock;
    std::mutex _perfLock;
    id<MTLBuffer> _globalVisibilityResultMTLBuffer;
    uint32_t _globalVisibilityQueryCount;
    std::mutex _vizLock;
};


#pragma mark -
#pragma mark MVKBaseDeviceObject

/** Represents an object that is spawned from a Vulkan device, and tracks that device. */
class MVKBaseDeviceObject : public MVKConfigurableObject {

public:

	/** Returns the device for which this object was created. */
	inline MVKDevice* getDevice() { return _device; }

	/** Returns the underlying Metal device. */
	inline id<MTLDevice> getMTLDevice() { return _device->getMTLDevice(); }

	/**
	 * Returns the Metal MTLPixelFormat corresponding to the specified Vulkan VkFormat,
	 * or returns MTLPixelFormatInvalid if no corresponding MTLPixelFormat exists.
	 *
	 * This function delegates to the MVKDevice::mtlPixelFormatFromVkFormat() function.
	 * See the notes for that function for more information about how MTLPixelFormats
	 * are managed for each platform device.
	 */
    inline MTLPixelFormat mtlPixelFormatFromVkFormat(VkFormat vkFormat) {
        return _device->mtlPixelFormatFromVkFormat(vkFormat);
    }

	/** Constructs an instance for the specified device. */
    MVKBaseDeviceObject(MVKDevice* device) : _device(device) {}

protected:
	MVKDevice* _device;
};


#pragma mark -
#pragma mark MVKDispatchableDeviceObject

/** Represents a dispatchable object that is spawned from a Vulkan device, and tracks that device. */
class MVKDispatchableDeviceObject : public MVKDispatchableObject {

public:

    /** Returns the device for which this object was created. */
    inline MVKDevice* getDevice() { return _device; }

    /** Returns the underlying Metal device. */
    inline id<MTLDevice> getMTLDevice() { return _device->getMTLDevice(); }

    /** Constructs an instance for the specified device. */
    MVKDispatchableDeviceObject(MVKDevice* device) : _device(device) {}

protected:
    MVKDevice* _device;
};


