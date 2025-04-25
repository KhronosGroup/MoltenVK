/*
 * MVKCommandPool.h
 *
 * Copyright (c) 2015-2025 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKDevice.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandEncodingPool.h"
#include "MVKCommand.h"
#include "MVKCmdPipeline.h"
#include "MVKCmdRendering.h"
#include "MVKCmdDispatch.h"
#include "MVKCmdDraw.h"
#include "MVKCmdTransfer.h"
#include "MVKCmdQueries.h"
#include "MVKCmdDebug.h"
#include "MVKMTLBufferAllocation.h"
#include <unordered_set>

#import <Metal/Metal.h>


#pragma mark -
#pragma mark MVKCommandPool

/** 
 * Represents a Vulkan command pool.
 *
 * Access to a command pool in Vulkan is externally synchronized.
 * As such, unless indicated otherwise, access to the content within this command pool 
 * is generally NOT thread-safe.
 *
 * Except where noted otherwise on specific member functions, all access to the content 
 * of this pool should be done during the setContent() function of each MVKCommand, and NOT 
 * during the execution of the command via the MVKCommand::encode() member function.
 */
class MVKCommandPool : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_COMMAND_POOL; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_COMMAND_POOL_EXT; }

	// Command type pool member variables.
	// Each has a form similar to (here for a draw command):  MVKCommandTypePool<MVKCmdDraw> _cmdDrawPool;
#	define MVK_CMD_TYPE_POOL(cmdType)  MVKCommandTypePool<MVKCmd ##cmdType> _cmd ##cmdType ##Pool;
#	include "MVKCommandTypePools.def"


#pragma mark Command resources

	/** Allocates command buffers from this pool. */
	VkResult allocateCommandBuffers(const VkCommandBufferAllocateInfo* pAllocateInfo,
									VkCommandBuffer* pCmdBuffer);

	/** Frees the specified command buffers from this pool. */
	void freeCommandBuffers(uint32_t commandBufferCount,
							const VkCommandBuffer* pCommandBuffers);

	/** Returns the command encoding pool. */
	inline MVKCommandEncodingPool* getCommandEncodingPool() { return &_commandEncodingPool; }

	/**
	 * Returns a retained MTLCommandBuffer created from the indexed queue
	 * within the queue family for which this command pool was created.
	 */
	id<MTLCommandBuffer> getMTLCommandBuffer(MVKCommandUse cmdUse, uint32_t queueIndex);

	/** Release any held but unused memory back to the system. */
	void trim();


#pragma mark Construction

	/** Resets the command pool. */
	VkResult reset( VkCommandPoolResetFlags flags);

	MVKCommandPool(MVKDevice* device,
				   const VkCommandPoolCreateInfo* pCreateInfo,
				   bool usePooling);

	~MVKCommandPool() override;

protected:
	void propagateDebugName() override {}
	MVKDeviceObjectPool<MVKCommandBuffer> _commandBufferPool;
	std::unordered_set<MVKCommandBuffer*> _allocatedCommandBuffers;
	MVKCommandEncodingPool _commandEncodingPool;
	uint32_t _queueFamilyIndex;
};

