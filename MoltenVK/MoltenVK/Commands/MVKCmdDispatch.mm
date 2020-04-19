/*
 * MVKCmdDispatch.mm
 *
 * Copyright (c) 2015-2020 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "MVKCmdDispatch.h"
#include "MVKCommandBuffer.h"
#include "MVKCommandPool.h"
#include "MVKBuffer.h"
#include "MVKPipeline.h"
#include "MVKFoundation.h"
#include "mvk_datatypes.hpp"


#pragma mark -
#pragma mark MVKCmdDispatch

MVKFuncionOverride_getTypePool(Dispatch)

VkResult MVKCmdDispatch::setContent(MVKCommandBuffer* cmdBuff,
									uint32_t baseGroupX, uint32_t baseGroupY, uint32_t baseGroupZ,
									uint32_t groupCountX, uint32_t groupCountY, uint32_t groupCountZ) {
    _mtlThreadgroupCount = MTLRegionMake3D(baseGroupX, baseGroupY, baseGroupZ, groupCountX, groupCountY, groupCountZ);

	return VK_SUCCESS;
}

void MVKCmdDispatch::encode(MVKCommandEncoder* cmdEncoder) {
//    MVKLogDebug("vkCmdDispatch() dispatching (%d, %d, %d) threadgroups.", _x, _y, _z);

	cmdEncoder->finalizeDispatchState();	// Ensure all updated state has been submitted to Metal
	id<MTLComputeCommandEncoder> mtlEncoder = cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch);
	auto* pipeline = (MVKComputePipeline*)cmdEncoder->_computePipelineState.getPipeline();
	if (pipeline->allowsDispatchBase()) {
		if ([mtlEncoder respondsToSelector: @selector(setStageInRegion:)]) {
			// We'll use the stage-input region to pass the base along to the shader.
			// Hopefully Metal won't complain that we didn't set up a stage-input descriptor.
			[mtlEncoder setStageInRegion: _mtlThreadgroupCount];
		} else {
			// We have to pass the base group in a buffer.
			unsigned int base[3] = {(uint32_t)_mtlThreadgroupCount.origin.x, (uint32_t)_mtlThreadgroupCount.origin.y, (uint32_t)_mtlThreadgroupCount.origin.z};
			cmdEncoder->setComputeBytes(mtlEncoder, base, sizeof(base), pipeline->getIndirectParamsIndex().stages[kMVKShaderStageCompute]);
		}
	}
	[mtlEncoder dispatchThreadgroups: _mtlThreadgroupCount.size
			   threadsPerThreadgroup: cmdEncoder->_mtlThreadgroupSize];
}


#pragma mark -
#pragma mark MVKCmdDispatchIndirect

MVKFuncionOverride_getTypePool(DispatchIndirect)

VkResult MVKCmdDispatchIndirect::setContent(MVKCommandBuffer* cmdBuff, VkBuffer buffer, VkDeviceSize offset) {
	MVKBuffer* mvkBuffer = (MVKBuffer*)buffer;
	_mtlIndirectBuffer = mvkBuffer->getMTLBuffer();
	_mtlIndirectBufferOffset = mvkBuffer->getMTLBufferOffset() + offset;

	return VK_SUCCESS;
}

void MVKCmdDispatchIndirect::encode(MVKCommandEncoder* cmdEncoder) {
//    MVKLogDebug("vkCmdDispatchIndirect() dispatching indirectly.");

    cmdEncoder->finalizeDispatchState();	// Ensure all updated state has been submitted to Metal
    [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) dispatchThreadgroupsWithIndirectBuffer: _mtlIndirectBuffer
																				indirectBufferOffset: _mtlIndirectBufferOffset
																			   threadsPerThreadgroup: cmdEncoder->_mtlThreadgroupSize];
}

