/*
 * MVKCommandEncoderState.mm
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

#include "MVKCommandEncoderState.h"
#include "MVKCommandEncodingPool.h"
#include "MVKCommandBuffer.h"
#include "MVKRenderPass.h"
#include "MVKPipeline.h"
#include "MVKQueryPool.h"

using namespace std;

#define shouldUpdateFace(face)  mvkAreAllFlagsEnabled(faceMask, VK_STENCIL_FACE_##face##_BIT)


#pragma mark -
#pragma mark MVKCommandEncoderState

MVKVulkanAPIObject* MVKCommandEncoderState::getVulkanAPIObject() { return _cmdEncoder->getVulkanAPIObject(); };

MVKDevice* MVKCommandEncoderState::getDevice() { return _cmdEncoder->getDevice(); }

bool MVKCommandEncoderState::isDynamicState(MVKRenderStateType state) {
	auto* gpl = _cmdEncoder->getGraphicsPipeline();
	return !gpl || gpl->isDynamicState(state);
}


#pragma mark -
#pragma mark MVKPipelineCommandEncoderState

void MVKPipelineCommandEncoderState::bindPipeline(MVKPipeline* pipeline) {
	if (pipeline == _pipeline) { return; }

	_pipeline = pipeline;
	_pipeline->wasBound(_cmdEncoder);
	markDirty();
}

MVKPipeline* MVKPipelineCommandEncoderState::getPipeline() { return _pipeline; }

void MVKPipelineCommandEncoderState::encodeImpl(uint32_t stage) {
    if (_pipeline) {
		_pipeline->encode(_cmdEncoder, stage);
		_pipeline->bindPushConstants(_cmdEncoder);
	}
}


#pragma mark -
#pragma mark MVKPushConstantsCommandEncoderState

void MVKPushConstantsCommandEncoderState:: setPushConstants(uint32_t offset, MVKArrayRef<char> pushConstants) {
	// MSL structs can have a larger size than the equivalent C struct due to MSL alignment needs.
	// Typically any MSL struct that contains a float4 will also have a size that is rounded up to a multiple of a float4 size.
	// Ensure that we pass along enough content to cover this extra space even if it is never actually accessed by the shader.
	size_t pcSizeAlign = _cmdEncoder->getMetalFeatures().pushConstantSizeAlignment;
    size_t pcSize = pushConstants.size();
	size_t pcBuffSize = mvkAlignByteCount(offset + pcSize, pcSizeAlign);
    mvkEnsureSize(_pushConstants, pcBuffSize);
    copy(pushConstants.begin(), pushConstants.end(), _pushConstants.begin() + offset);
    if (pcBuffSize > 0) { markDirty(); }
}

void MVKPushConstantsCommandEncoderState::setMTLBufferIndex(uint32_t mtlBufferIndex, bool pipelineStageUsesPushConstants) {
	if ((mtlBufferIndex != _mtlBufferIndex) || (pipelineStageUsesPushConstants != _pipelineStageUsesPushConstants)) {
		_mtlBufferIndex = mtlBufferIndex;
		_pipelineStageUsesPushConstants = pipelineStageUsesPushConstants;
		markDirty();
	}
}

// At this point, I have been marked not-dirty, under the assumption that I will make changes to the encoder.
// However, some of the paths below decide not to actually make any changes to the encoder. In that case,
// I should remain dirty until I actually do make encoder changes.
void MVKPushConstantsCommandEncoderState::encodeImpl(uint32_t stage) {
    if ( !_pipelineStageUsesPushConstants || _pushConstants.empty() ) { return; }

	_isDirty = true;	// Stay dirty until I actually decide to make a change to the encoder

    switch (_shaderStage) {
        case VK_SHADER_STAGE_VERTEX_BIT:
			if (stage == kMVKGraphicsStageVertex) {
                _cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                             _pushConstants.data(),
                                             _pushConstants.size(),
                                             _mtlBufferIndex, true);
				_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageVertex);
				_isDirty = false;	// Okay, I changed the encoder
			} else if (!isTessellating() && stage == kMVKGraphicsStageRasterization) {
                _cmdEncoder->setVertexBytes(_cmdEncoder->_mtlRenderEncoder,
                                            _pushConstants.data(),
                                            _pushConstants.size(),
                                            _mtlBufferIndex, true);
				_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageVertex);
				_isDirty = false;	// Okay, I changed the encoder
            }
            break;
        case VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT:
            if (stage == kMVKGraphicsStageTessControl) {
                _cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                             _pushConstants.data(),
                                             _pushConstants.size(),
                                             _mtlBufferIndex, true);
				_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageTessCtl);
				_isDirty = false;	// Okay, I changed the encoder
            }
            break;
        case VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT:
            if (isTessellating() && stage == kMVKGraphicsStageRasterization) {
                _cmdEncoder->setVertexBytes(_cmdEncoder->_mtlRenderEncoder,
                                            _pushConstants.data(),
                                            _pushConstants.size(),
                                            _mtlBufferIndex, true);
				_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageTessEval);
				_isDirty = false;	// Okay, I changed the encoder
            }
            break;
        case VK_SHADER_STAGE_FRAGMENT_BIT:
            if (stage == kMVKGraphicsStageRasterization) {
                _cmdEncoder->setFragmentBytes(_cmdEncoder->_mtlRenderEncoder,
                                              _pushConstants.data(),
                                              _pushConstants.size(),
                                              _mtlBufferIndex, true);
				_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageFragment);
				_isDirty = false;	// Okay, I changed the encoder
            }
            break;
        case VK_SHADER_STAGE_COMPUTE_BIT:
            _cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
                                         _pushConstants.data(),
                                         _pushConstants.size(),
                                         _mtlBufferIndex, true);
			_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageCompute);
			_isDirty = false;	// Okay, I changed the encoder
            break;
        default:
            MVKAssert(false, "Unsupported shader stage: %d", _shaderStage);
            break;
    }
}

bool MVKPushConstantsCommandEncoderState::isTessellating() {
	auto* gp = _cmdEncoder->getGraphicsPipeline();
	return gp ? gp->isTessellationPipeline() : false;
}


#pragma mark -
#pragma mark MVKDepthStencilCommandEncoderState

void MVKDepthStencilCommandEncoderState:: setDepthStencilState(const VkPipelineDepthStencilStateCreateInfo& vkDepthStencilInfo) {
	auto& depthEnabled = _depthTestEnabled[StateScope::Static];
	auto oldDepthEnabled = depthEnabled;
	depthEnabled = static_cast<bool>(vkDepthStencilInfo.depthTestEnable);

	auto& dsData = _depthStencilData[StateScope::Static];
	auto oldData = dsData;
	dsData.depthCompareFunction = mvkMTLCompareFunctionFromVkCompareOp(vkDepthStencilInfo.depthCompareOp);
	dsData.depthWriteEnabled = vkDepthStencilInfo.depthWriteEnable;

	dsData.stencilTestEnabled = static_cast<bool>(vkDepthStencilInfo.stencilTestEnable);
	setStencilState(dsData.frontFaceStencilData, vkDepthStencilInfo.front);
	setStencilState(dsData.backFaceStencilData, vkDepthStencilInfo.back);

	if (depthEnabled != oldDepthEnabled || dsData != oldData) { markDirty(); }
}

void MVKDepthStencilCommandEncoderState::setStencilState(MVKMTLStencilDescriptorData& sData,
                                                         const VkStencilOpState& vkStencil) {
	sData.readMask = vkStencil.compareMask;
	sData.writeMask = vkStencil.writeMask;
    sData.stencilCompareFunction = mvkMTLCompareFunctionFromVkCompareOp(vkStencil.compareOp);
    sData.stencilFailureOperation = mvkMTLStencilOperationFromVkStencilOp(vkStencil.failOp);
    sData.depthFailureOperation = mvkMTLStencilOperationFromVkStencilOp(vkStencil.depthFailOp);
    sData.depthStencilPassOperation = mvkMTLStencilOperationFromVkStencilOp(vkStencil.passOp);
}

void MVKDepthStencilCommandEncoderState::setDepthTestEnable(VkBool32 depthTestEnable) {
	setContent(_depthTestEnabled[StateScope::Dynamic], static_cast<bool>(depthTestEnable));
}

void MVKDepthStencilCommandEncoderState::setDepthWriteEnable(VkBool32 depthWriteEnable) {
	setContent(_depthStencilData[StateScope::Dynamic].depthWriteEnabled, static_cast<bool>(depthWriteEnable));
}

void MVKDepthStencilCommandEncoderState::setDepthCompareOp(VkCompareOp depthCompareOp) {
	setContent(_depthStencilData[StateScope::Dynamic].depthCompareFunction,
			   (uint8_t)mvkMTLCompareFunctionFromVkCompareOp(depthCompareOp));
}

void MVKDepthStencilCommandEncoderState::setStencilTestEnable(VkBool32 stencilTestEnable) {
	setContent(_depthStencilData[StateScope::Dynamic].stencilTestEnabled, static_cast<bool>(stencilTestEnable));
}

void MVKDepthStencilCommandEncoderState::setStencilOp(MVKMTLStencilDescriptorData& sData,
													  VkStencilOp failOp,
													  VkStencilOp passOp,
													  VkStencilOp depthFailOp,
													  VkCompareOp compareOp) {
	auto oldData = sData;
	sData.stencilCompareFunction = mvkMTLCompareFunctionFromVkCompareOp(compareOp);
	sData.stencilFailureOperation = mvkMTLStencilOperationFromVkStencilOp(failOp);
	sData.depthFailureOperation = mvkMTLStencilOperationFromVkStencilOp(depthFailOp);
	sData.depthStencilPassOperation = mvkMTLStencilOperationFromVkStencilOp(passOp);
	if (sData != oldData) { markDirty(); }
}

void MVKDepthStencilCommandEncoderState::setStencilOp(VkStencilFaceFlags faceMask,
													  VkStencilOp failOp,
													  VkStencilOp passOp,
													  VkStencilOp depthFailOp,
													  VkCompareOp compareOp) {
	auto& dsData = _depthStencilData[StateScope::Dynamic];
	if (shouldUpdateFace(FRONT)) { setStencilOp(dsData.frontFaceStencilData, failOp, passOp, depthFailOp, compareOp); }
	if (shouldUpdateFace(BACK)) { setStencilOp(dsData.backFaceStencilData, failOp, passOp, depthFailOp, compareOp); }
}

void MVKDepthStencilCommandEncoderState::setStencilCompareMask(VkStencilFaceFlags faceMask,
															   uint32_t stencilCompareMask) {
	auto& dsData = _depthStencilData[StateScope::Dynamic];
	if (shouldUpdateFace(FRONT)) { setContent(dsData.frontFaceStencilData.readMask, stencilCompareMask); }
	if (shouldUpdateFace(BACK)) { setContent(dsData.backFaceStencilData.readMask, stencilCompareMask); }
}

void MVKDepthStencilCommandEncoderState::setStencilWriteMask(VkStencilFaceFlags faceMask,
															 uint32_t stencilWriteMask) {
	auto& dsData = _depthStencilData[StateScope::Dynamic];
	if (shouldUpdateFace(FRONT)) { setContent(dsData.frontFaceStencilData.writeMask, stencilWriteMask); }
	if (shouldUpdateFace(BACK)) { setContent(dsData.backFaceStencilData.writeMask, stencilWriteMask); }
}

void MVKDepthStencilCommandEncoderState::beginMetalRenderPass() {
    MVKCommandEncoderState::beginMetalRenderPass();

	MVKRenderSubpass* mvkSubpass = _cmdEncoder->getSubpass();
	bool prevHasDepthAttachment = _hasDepthAttachment;
	_hasDepthAttachment = mvkSubpass->isDepthAttachmentUsed();
	if (_hasDepthAttachment != prevHasDepthAttachment) { markDirty(); }

	bool prevHasStencilAttachment = _hasStencilAttachment;
	_hasStencilAttachment = mvkSubpass->isStencilAttachmentUsed();
	if (_hasStencilAttachment != prevHasStencilAttachment) { markDirty(); }
}

// Combine static and dynamic depth/stencil data
void MVKDepthStencilCommandEncoderState::encodeImpl(uint32_t stage) {
	if (stage != kMVKGraphicsStageRasterization) { return; }

	MVKMTLDepthStencilDescriptorData dsData;

	if (_hasDepthAttachment && getContent(_depthTestEnabled, DepthTestEnable)) {
		dsData.depthCompareFunction = getData(DepthCompareOp).depthCompareFunction;
		dsData.depthWriteEnabled = getData(DepthWriteEnable).depthWriteEnabled;
	}

	if (_hasStencilAttachment && getData(StencilTestEnable).stencilTestEnabled) {
		dsData.stencilTestEnabled = true;

		auto& frontFace = dsData.frontFaceStencilData;
		auto& backFace  = dsData.backFaceStencilData;

		const auto& srcRM = getData(StencilCompareMask);
		frontFace.readMask  = srcRM.frontFaceStencilData.readMask;
		backFace.readMask   = srcRM.backFaceStencilData.readMask;

		const auto& srcWM = getData(StencilWriteMask);
		frontFace.writeMask = srcWM.frontFaceStencilData.writeMask;
		backFace.writeMask  = srcWM.backFaceStencilData.writeMask;

		const auto& srcSOp = getData(StencilOp);
		frontFace.stencilCompareFunction    = srcSOp.frontFaceStencilData.stencilCompareFunction;
		frontFace.stencilFailureOperation   = srcSOp.frontFaceStencilData.stencilFailureOperation;
		frontFace.depthFailureOperation     = srcSOp.frontFaceStencilData.depthFailureOperation;
		frontFace.depthStencilPassOperation = srcSOp.frontFaceStencilData.depthStencilPassOperation;

		backFace.stencilCompareFunction     = srcSOp.backFaceStencilData.stencilCompareFunction;
		backFace.stencilFailureOperation    = srcSOp.backFaceStencilData.stencilFailureOperation;
		backFace.depthFailureOperation      = srcSOp.backFaceStencilData.depthFailureOperation;
		backFace.depthStencilPassOperation  = srcSOp.backFaceStencilData.depthStencilPassOperation;
	}

	[_cmdEncoder->_mtlRenderEncoder setDepthStencilState: _cmdEncoder->getCommandEncodingPool()->getMTLDepthStencilState(dsData)];
}


#pragma mark -
#pragma mark MVKRenderingCommandEncoderState

#define getMTLContent(state)  getContent(_mtl##state, state)
#define setMTLContent(state, val)  setContent(state, _mtl##state, val, isDynamic)

void MVKRenderingCommandEncoderState::setCullMode(VkCullModeFlags cullMode, bool isDynamic) {
	setMTLContent(CullMode, mvkMTLCullModeFromVkCullModeFlags(cullMode));
	getContent(_cullBothFaces, isDynamic) = (cullMode == VK_CULL_MODE_FRONT_AND_BACK);
}

void MVKRenderingCommandEncoderState::setFrontFace(VkFrontFace frontFace, bool isDynamic) {
	setMTLContent(FrontFace, mvkMTLWindingFromVkFrontFace(frontFace));
}

void MVKRenderingCommandEncoderState::setPolygonMode(VkPolygonMode polygonMode, bool isDynamic) {
	setMTLContent(PolygonMode, mvkMTLTriangleFillModeFromVkPolygonMode(polygonMode));
	getContent(_isPolygonModePoint, isDynamic) = (polygonMode == VK_POLYGON_MODE_POINT);
}

void MVKRenderingCommandEncoderState::setLineWidth(float lineWidth, bool isDynamic) {
	setMTLContent(LineWidth, lineWidth);
}

void MVKRenderingCommandEncoderState::setBlendConstants(MVKColor32 blendConstants, bool isDynamic) {
	setMTLContent(BlendConstants, blendConstants);
}

void MVKRenderingCommandEncoderState::setDepthBias(const VkPipelineRasterizationStateCreateInfo& vkRasterInfo) {
	setDepthBiasEnable(vkRasterInfo.depthBiasEnable, false);
	setDepthBias( { vkRasterInfo.depthBiasConstantFactor, vkRasterInfo.depthBiasClamp, vkRasterInfo.depthBiasSlopeFactor } , false);
}

void MVKRenderingCommandEncoderState::setDepthBias(MVKDepthBias depthBias, bool isDynamic) {
	setMTLContent(DepthBias, depthBias);
}

void MVKRenderingCommandEncoderState::setDepthBiasEnable(VkBool32 depthBiasEnable, bool isDynamic) {
	setMTLContent(DepthBiasEnable, static_cast<bool>(depthBiasEnable));
}

void MVKRenderingCommandEncoderState::setDepthClipEnable(bool depthClip, bool isDynamic) {
	setMTLContent(DepthClipEnable, depthClip ? MTLDepthClipModeClip : MTLDepthClipModeClamp);
}

void MVKRenderingCommandEncoderState::setDepthBounds(MVKDepthBounds depthBounds, bool isDynamic) {
	setMTLContent(DepthBounds, depthBounds);
}

void MVKRenderingCommandEncoderState::setDepthBoundsTestEnable(VkBool32 depthBoundsTestEnable, bool isDynamic) {
	setMTLContent(DepthBoundsTestEnable, static_cast<bool>(depthBoundsTestEnable));
}

void MVKRenderingCommandEncoderState::setStencilReferenceValues(const VkPipelineDepthStencilStateCreateInfo& vkDepthStencilInfo) {
	bool isDynamic = false;
	MVKStencilReference mtlStencilReference = { vkDepthStencilInfo.front.reference, vkDepthStencilInfo.back.reference };
	setMTLContent(StencilReference, &mtlStencilReference);
}

void MVKRenderingCommandEncoderState::setStencilReferenceValues(VkStencilFaceFlags faceMask, uint32_t stencilReference) {
	bool isDynamic = true;
	MVKStencilReference mtlStencilReference = _mtlStencilReference[StateScope::Dynamic];
	if (shouldUpdateFace(FRONT)) { mtlStencilReference.frontFaceValue = stencilReference; }
	if (shouldUpdateFace(BACK)) { mtlStencilReference.backFaceValue = stencilReference; }
	setMTLContent(StencilReference, &mtlStencilReference);
}

void MVKRenderingCommandEncoderState::setViewports(const MVKArrayRef<VkViewport> viewports,
													 uint32_t firstViewport,
													 bool isDynamic) {
	uint32_t maxViewports = _cmdEncoder->getDeviceProperties().limits.maxViewports;
	if (firstViewport >= maxViewports) { return; }

	MVKMTLViewports mtlViewports = isDynamic ? _mtlViewports[StateScope::Dynamic] : _mtlViewports[StateScope::Static];
	size_t vpCnt = min((uint32_t)viewports.size(), maxViewports - firstViewport);
	for (uint32_t vpIdx = 0; vpIdx < vpCnt; vpIdx++) {
		mtlViewports.viewports[firstViewport + vpIdx] = mvkMTLViewportFromVkViewport(viewports[vpIdx]);
		mtlViewports.viewportCount = max(mtlViewports.viewportCount, vpIdx + 1);
	}
	setMTLContent(Viewports, &mtlViewports);
}

void MVKRenderingCommandEncoderState::setScissors(const MVKArrayRef<VkRect2D> scissors,
													uint32_t firstScissor,
													bool isDynamic) {
	uint32_t maxScissors = _cmdEncoder->getDeviceProperties().limits.maxViewports;
	if (firstScissor >= maxScissors) { return; }

	MVKMTLScissors mtlScissors = isDynamic ? _mtlScissors[StateScope::Dynamic] : _mtlScissors[StateScope::Static];
	size_t sCnt = min((uint32_t)scissors.size(), maxScissors - firstScissor);
	for (uint32_t sIdx = 0; sIdx < sCnt; sIdx++) {
		mtlScissors.scissors[firstScissor + sIdx] = mvkMTLScissorRectFromVkRect2D(scissors[sIdx]);
		mtlScissors.scissorCount = max(mtlScissors.scissorCount, sIdx + 1);
	}
	setMTLContent(Scissors, &mtlScissors);
}

void MVKRenderingCommandEncoderState::setPrimitiveRestartEnable(VkBool32 primitiveRestartEnable, bool isDynamic) {
	setMTLContent(PrimitiveRestartEnable, static_cast<bool>(primitiveRestartEnable));
}

void MVKRenderingCommandEncoderState::setRasterizerDiscardEnable(VkBool32 rasterizerDiscardEnable, bool isDynamic) {
	setMTLContent(RasterizerDiscardEnable, static_cast<bool>(rasterizerDiscardEnable));
}

// This value is retrieved, not encoded, so don't mark this encoder as dirty.
void MVKRenderingCommandEncoderState::setPrimitiveTopology(VkPrimitiveTopology topology, bool isDynamic) {
	getContent(_mtlPrimitiveTopology, isDynamic) = mvkMTLPrimitiveTypeFromVkPrimitiveTopology(topology);
}

// Metal does not support VK_POLYGON_MODE_POINT, but it can be emulated if the polygon mode
// is static, which allows both the topology and the pipeline topology-class to be set to points.
// This cannot be accomplished if the dynamic polygon mode has been changed to points when the
// pipeline is expecting triangles or lines, because the pipeline topology class will be incorrect.
MTLPrimitiveType MVKRenderingCommandEncoderState::getPrimitiveType() {
	if (isDynamicState(PolygonMode) &&
		_isPolygonModePoint[StateScope::Dynamic] &&
		!_isPolygonModePoint[StateScope::Static]) {
		
		reportWarning(VK_ERROR_FEATURE_NOT_PRESENT, "vkCmdSetPolygonMode(): Metal does not support setting VK_POLYGON_MODE_POINT dynamically.");
		return getMTLContent(PrimitiveTopology);
	}

	return getContent(_isPolygonModePoint, PolygonMode) ? MTLPrimitiveTypePoint : getMTLContent(PrimitiveTopology);
}

bool MVKRenderingCommandEncoderState::isDrawingTriangles() {
	switch (getPrimitiveType()) {
		case MTLPrimitiveTypeTriangle:      return true;
		case MTLPrimitiveTypeTriangleStrip: return true;
		default:                            return false;
	}
}

// This value is retrieved, not encoded, so don't mark this encoder as dirty.
void MVKRenderingCommandEncoderState::setPatchControlPoints(uint32_t patchControlPoints, bool isDynamic) {
	getContent(_mtlPatchControlPoints, isDynamic) = patchControlPoints;
}

uint32_t MVKRenderingCommandEncoderState::getPatchControlPoints() {
	return getMTLContent(PatchControlPoints);
}

void MVKRenderingCommandEncoderState::setSampleLocationsEnable(VkBool32 sampleLocationsEnable, bool isDynamic) {
	bool slEnbl = static_cast<bool>(sampleLocationsEnable);
	auto& mtlSampLocEnbl = getContent(_mtlSampleLocationsEnable, isDynamic);

	if (slEnbl == mtlSampLocEnbl) { return; }

	mtlSampLocEnbl = slEnbl;

	// This value is retrieved, not encoded, so don't mark this encoder as dirty.
	_dirtyStates.enable(SampleLocationsEnable);
}

void MVKRenderingCommandEncoderState::setSampleLocations(MVKArrayRef<VkSampleLocationEXT> sampleLocations, bool isDynamic) {
	auto& mtlSampPosns = getContent(_mtlSampleLocations, isDynamic);
	size_t slCnt = sampleLocations.size();

	// When comparing new vs current, make use of fact that MTLSamplePosition & VkSampleLocationEXT have same memory footprint.
	if (slCnt == mtlSampPosns.size() &&
		mvkAreEqual((MTLSamplePosition*)sampleLocations.data(),
					mtlSampPosns.data(), slCnt)) {
		return;
	}

	mtlSampPosns.clear();
	for (uint32_t slIdx = 0; slIdx < slCnt; slIdx++) {
		auto& sl = sampleLocations[slIdx];
		mtlSampPosns.push_back(MTLSamplePositionMake(mvkClamp(sl.x, kMVKMinSampleLocationCoordinate, kMVKMaxSampleLocationCoordinate),
													 mvkClamp(sl.y, kMVKMinSampleLocationCoordinate, kMVKMaxSampleLocationCoordinate)));
	}

	// This value is retrieved, not encoded, so don't mark this encoder as dirty.
	_dirtyStates.enable(SampleLocations);
}

MVKArrayRef<MTLSamplePosition> MVKRenderingCommandEncoderState::getSamplePositions() {
	return getMTLContent(SampleLocationsEnable) ? getMTLContent(SampleLocations).contents() : MVKArrayRef<MTLSamplePosition>();
}

// Return whether state is dirty, and mark it not dirty
bool MVKRenderingCommandEncoderState::isDirty(MVKRenderStateType state) {
	bool rslt = _dirtyStates.isEnabled(state);
	_dirtyStates.disable(state);
	return rslt;
}

// Don't force sample location & sample location enable to become dirty if they weren't already, because
// this may cause needsMetalRenderPassRestart() to trigger an unnecessary Metal renderpass restart.
void MVKRenderingCommandEncoderState::markDirty() {
	MVKCommandEncoderState::markDirty();

	bool wasSLDirty = _dirtyStates.isEnabled(SampleLocations);
	bool wasSLEnblDirty = _dirtyStates.isEnabled(SampleLocationsEnable);
	
	_dirtyStates.enableAll();

	_dirtyStates.set(SampleLocations, wasSLDirty);
	_dirtyStates.set(SampleLocationsEnable, wasSLEnblDirty);
}

// Don't call parent beginMetalRenderPass() because it 
// will call local markDirty() which is too aggressive.
void MVKRenderingCommandEncoderState::beginMetalRenderPass() {
	if (_isModified) {
		_dirtyStates = _modifiedStates;
		MVKCommandEncoderState::markDirty();
	}
}

// Don't use || on isDirty calls, to ensure they both get called, so that the dirty flag of each will be cleared.
bool MVKRenderingCommandEncoderState::needsMetalRenderPassRestart() {
	bool isSLDirty = isDirty(SampleLocations);
	bool isSLEnblDirty = isDirty(SampleLocationsEnable);
	return isSLDirty || isSLEnblDirty;
}

#pragma mark Encoding

#if MVK_USE_METAL_PRIVATE_API
// An extension of the MTLRenderCommandEncoder protocol to declare the setLineWidth: method.
@protocol MVKMTLRenderCommandEncoderLineWidth <MTLRenderCommandEncoder>
-(void) setLineWidth: (float) width;
@end

// An extension of the MTLRenderCommandEncoder protocol containing a declaration of the
// -setDepthBoundsTestAMD:minDepth:maxDepth: method.
@protocol MVKMTLRenderCommandEncoderDepthBoundsAMD <MTLRenderCommandEncoder>

- (void)setDepthBoundsTestAMD:(BOOL)enable minDepth:(float)minDepth maxDepth:(float)maxDepth;

@end
#endif

void MVKRenderingCommandEncoderState::encodeImpl(uint32_t stage) {
	if (stage != kMVKGraphicsStageRasterization) { return; }

	auto& rendEnc = _cmdEncoder->_mtlRenderEncoder;
	auto& enabledFeats = _cmdEncoder->getEnabledFeatures();

	if (isDirty(PolygonMode)) { [rendEnc setTriangleFillMode: getMTLContent(PolygonMode)]; }
	if (isDirty(CullMode)) { [rendEnc setCullMode: getMTLContent(CullMode)]; }
	if (isDirty(FrontFace)) { [rendEnc setFrontFacingWinding: getMTLContent(FrontFace)]; }
	if (isDirty(BlendConstants)) {
		auto& bcFlt = getMTLContent(BlendConstants).float32;
		[rendEnc setBlendColorRed: bcFlt[0] green: bcFlt[1] blue: bcFlt[2] alpha: bcFlt[3]];
	}

#if MVK_USE_METAL_PRIVATE_API
	if (isDirty(LineWidth)) {
		auto lineWidthRendEnc = (id<MVKMTLRenderCommandEncoderLineWidth>)rendEnc;
		if ([lineWidthRendEnc respondsToSelector: @selector(setLineWidth:)]) {
			[lineWidthRendEnc setLineWidth: getMTLContent(LineWidth)];
		}
	}
#endif

	if (isDirty(DepthBiasEnable) || isDirty(DepthBias)) {
		if (getMTLContent(DepthBiasEnable)) {
			auto& db = getMTLContent(DepthBias);
			[rendEnc setDepthBias: db.depthBiasConstantFactor
					   slopeScale: db.depthBiasSlopeFactor
							clamp: db.depthBiasClamp];
		} else {
			[rendEnc setDepthBias: 0 slopeScale: 0 clamp: 0];
		}
	}
	if (isDirty(DepthClipEnable) && enabledFeats.depthClamp) {
		[rendEnc setDepthClipMode: getMTLContent(DepthClipEnable)];
	}

#if MVK_USE_METAL_PRIVATE_API
    if (getMVKConfig().useMetalPrivateAPI && (isDirty(DepthBoundsTestEnable) || isDirty(DepthBounds)) &&
		enabledFeats.depthBounds) {
		if (getMTLContent(DepthBoundsTestEnable)) {
			auto& db = getMTLContent(DepthBounds);
			[(id<MVKMTLRenderCommandEncoderDepthBoundsAMD>)_cmdEncoder->_mtlRenderEncoder setDepthBoundsTestAMD: YES
					   minDepth: db.minDepthBound
					   maxDepth: db.maxDepthBound];
		} else {
			[(id<MVKMTLRenderCommandEncoderDepthBoundsAMD>)_cmdEncoder->_mtlRenderEncoder setDepthBoundsTestAMD: NO
					   minDepth: 0.0f
					   maxDepth: 1.0f];
		}
	}
#endif
	if (isDirty(StencilReference)) {
		auto& sr = getMTLContent(StencilReference);
		[rendEnc setStencilFrontReferenceValue: sr.frontFaceValue backReferenceValue: sr.backFaceValue];
	}

	if (isDirty(Viewports)) {
		auto& mtlViewports = getMTLContent(Viewports);
		if (enabledFeats.multiViewport) {
#if MVK_MACOS_OR_IOS
			[rendEnc setViewports: mtlViewports.viewports count: mtlViewports.viewportCount];
#endif
		} else {
			[rendEnc setViewport: mtlViewports.viewports[0]];
		}
	}

	// If rasterizing discard has been dynamically enabled, or culling has been dynamically 
	// set to front-and-back, emulate this by using zeroed scissor rectangles.
	if (isDirty(Scissors)) {
		static MTLScissorRect zeroRect = {};
		auto mtlScissors = getMTLContent(Scissors);
		bool shouldDiscard = ((_mtlRasterizerDiscardEnable[StateScope::Dynamic] && isDynamicState(RasterizerDiscardEnable)) ||
							  (isDrawingTriangles() && _cullBothFaces[StateScope::Dynamic] && isDynamicState(CullMode)));
		for (uint32_t sIdx = 0; sIdx < mtlScissors.scissorCount; sIdx++) {
			mtlScissors.scissors[sIdx] = shouldDiscard ? zeroRect : _cmdEncoder->clipToRenderArea(mtlScissors.scissors[sIdx]);
		}

		if (enabledFeats.multiViewport) {
#if MVK_MACOS_OR_IOS
			[rendEnc setScissorRects: mtlScissors.scissors count: mtlScissors.scissorCount];
#endif
		} else {
			[rendEnc setScissorRect: mtlScissors.scissors[0]];
		}
	}
}

#undef getMTLContent
#undef setMTLContent


#pragma mark -
#pragma mark MVKResourcesCommandEncoderState

void MVKResourcesCommandEncoderState::bindDescriptorSet(uint32_t descSetIndex,
														MVKDescriptorSet* descSet,
														MVKShaderResourceBinding& dslMTLRezIdxOffsets,
														MVKArrayRef<uint32_t> dynamicOffsets,
														uint32_t& dynamicOffsetIndex) {

	bool dsChanged = (descSet != _boundDescriptorSets[descSetIndex]);

	_boundDescriptorSets[descSetIndex] = descSet;

	if (descSet->hasMetalArgumentBuffer()) {
		// If the descriptor set has changed, track new resource usage.
		if (dsChanged) {
			auto& usageDirty = _metalUsageDirtyDescriptors[descSetIndex];
			usageDirty.resize(descSet->getDescriptorCount());
			usageDirty.enableAllBits();
		}

		// Update dynamic buffer offsets
		uint32_t baseDynOfstIdx = dslMTLRezIdxOffsets.getMetalResourceIndexes().dynamicOffsetBufferIndex;
		uint32_t doCnt = descSet->getDynamicOffsetDescriptorCount();
		for (uint32_t doIdx = 0; doIdx < doCnt && dynamicOffsetIndex < dynamicOffsets.size(); doIdx++) {
			updateImplicitBuffer(_dynamicOffsets, baseDynOfstIdx + doIdx, dynamicOffsets[dynamicOffsetIndex++]);
		}

		// If something changed, mark dirty
		if (dsChanged || doCnt > 0) { MVKCommandEncoderState::markDirty(); }
	}
}

// Encode the Metal command encoder usage for each resource,
// and bind the Metal argument buffer to the command encoder.
void MVKResourcesCommandEncoderState::encodeMetalArgumentBuffer(MVKShaderStage stage) {
	if ( !_cmdEncoder->isUsingMetalArgumentBuffers() ) { return; }

	bool isUsingResidencySet = getDevice()->hasResidencySet();
	MVKPipeline* pipeline = getPipeline();
	uint32_t dsCnt = pipeline->getDescriptorSetCount();
	for (uint32_t dsIdx = 0; dsIdx < dsCnt; dsIdx++) {
		auto* descSet = _boundDescriptorSets[dsIdx];
		if ( !(descSet && descSet->hasMetalArgumentBuffer()) ) { continue; }

		auto* dsLayout = descSet->getLayout();
		auto& resourceUsageDirtyDescs = _metalUsageDirtyDescriptors[dsIdx];
		auto& shaderBindingUsage = pipeline->getDescriptorBindingUse(dsIdx, stage);
		bool shouldBindArgBuffToStage = false;
		
		// Iterate the bindings. If we're using a residency set, the only thing we need to determine
		// is whether to bind the Metal arg buffer for the desc set. Once we know that, we can abort fast.
		// Otherwise, we have to labouriously set the residency usage for each resource.
		uint32_t dslBindCnt = dsLayout->getBindingCount();
		for (uint32_t dslBindIdx = 0; dslBindIdx < dslBindCnt; dslBindIdx++) {
			auto* dslBind = dsLayout->getBindingAt(dslBindIdx);
			if (dslBind->getApplyToStage(stage) && shaderBindingUsage.getBit(dslBindIdx)) {
				shouldBindArgBuffToStage = true;
				if (isUsingResidencySet) break;	// Now that we know we need to bind arg buffer, we're done with this desc layout.
				uint32_t elemCnt = dslBind->getDescriptorCount(descSet->getVariableDescriptorCount());
				for (uint32_t elemIdx = 0; elemIdx < elemCnt; elemIdx++) {
					uint32_t descIdx = dslBind->getDescriptorIndex(elemIdx);
					if (resourceUsageDirtyDescs.getBit(descIdx, true)) {
						auto* mvkDesc = descSet->getDescriptorAt(descIdx);
						mvkDesc->encodeResourceUsage(this, dslBind, stage);
					}
				}
			}
		}
		descSet->encodeAuxBufferUsage(this, stage);


		// If it is needed, bind the Metal argument buffer itself to the command encoder,
		if (shouldBindArgBuffToStage) {
			auto& mvkArgBuff = descSet->getMetalArgumentBuffer();
			MVKMTLBufferBinding bb;
			bb.mtlBuffer = mvkArgBuff.getMetalArgumentBuffer();
			bb.offset = mvkArgBuff.getMetalArgumentBufferOffset();
			bb.index = dsIdx;
			bindMetalArgumentBuffer(stage, bb);
		}

		// For some unexpected reason, GPU capture on Xcode 12 doesn't always correctly expose
		// the contents of Metal argument buffers. Triggering an extraction of the arg buffer
		// contents here, after filling it, seems to correct that.
		// Sigh. A bug report has been filed with Apple.
		if (getDevice()->isCurrentlyAutoGPUCapturing()) { [descSet->getMetalArgumentBuffer().getMetalArgumentBuffer() contents]; }
	}
}

// Mark the resource usage as needing an update for each Metal render encoder.
void MVKResourcesCommandEncoderState::markDirty() {
	MVKCommandEncoderState::markDirty();
	if (_cmdEncoder->isUsingMetalArgumentBuffers()) {
		for (uint32_t dsIdx = 0; dsIdx < kMVKMaxDescriptorSetCount; dsIdx++) {
			_metalUsageDirtyDescriptors[dsIdx].enableAllBits();
		}
	}
}

// If a swizzle is needed for this stage, iterates all the bindings and logs errors for those that need texture swizzling.
void MVKResourcesCommandEncoderState::assertMissingSwizzles(bool needsSwizzle, const char* stageName, MVKArrayRef<const MVKMTLTextureBinding> texBindings) {
	if (needsSwizzle) {
		for (auto& tb : texBindings) {
			VkComponentMapping vkcm = mvkUnpackSwizzle(tb.swizzle);
			if (!mvkVkComponentMappingsMatch(vkcm, {VK_COMPONENT_SWIZZLE_R, VK_COMPONENT_SWIZZLE_G, VK_COMPONENT_SWIZZLE_B, VK_COMPONENT_SWIZZLE_A})) {
				MVKLogError("Pipeline does not support component swizzle (%s, %s, %s, %s) required by a VkImageView used in the %s shader."
							" Full VkImageView component swizzling will be supported by a pipeline if the MVKConfiguration::fullImageViewSwizzle"
							" config parameter or MVK_CONFIG_FULL_IMAGE_VIEW_SWIZZLE environment variable was enabled when the pipeline is compiled.",
							mvkVkComponentSwizzleName(vkcm.r), mvkVkComponentSwizzleName(vkcm.g),
							mvkVkComponentSwizzleName(vkcm.b), mvkVkComponentSwizzleName(vkcm.a), stageName);
				MVKAssert(false, "See previous logged error.");
			}
		}
	}
}


#pragma mark -
#pragma mark MVKGraphicsResourcesCommandEncoderState

void MVKGraphicsResourcesCommandEncoderState::bindBuffer(MVKShaderStage stage, const MVKMTLBufferBinding& binding) {
    bind(binding, _shaderStageResourceBindings[stage].bufferBindings, _shaderStageResourceBindings[stage].areBufferBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::bindTexture(MVKShaderStage stage, const MVKMTLTextureBinding& binding) {
    bind(binding, _shaderStageResourceBindings[stage].textureBindings, _shaderStageResourceBindings[stage].areTextureBindingsDirty, _shaderStageResourceBindings[stage].needsSwizzle);
}

void MVKGraphicsResourcesCommandEncoderState::bindSamplerState(MVKShaderStage stage, const MVKMTLSamplerStateBinding& binding) {
    bind(binding, _shaderStageResourceBindings[stage].samplerStateBindings, _shaderStageResourceBindings[stage].areSamplerStateBindingsDirty);
}

void MVKGraphicsResourcesCommandEncoderState::bindSwizzleBuffer(const MVKShaderImplicitRezBinding& binding,
																bool needVertexSwizzleBuffer,
																bool needTessCtlSwizzleBuffer,
																bool needTessEvalSwizzleBuffer,
																bool needFragmentSwizzleBuffer) {
    for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
        _shaderStageResourceBindings[i].swizzleBufferBinding.index = binding.stages[i];
    }
    _shaderStageResourceBindings[kMVKShaderStageVertex].swizzleBufferBinding.isDirty = needVertexSwizzleBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessCtl].swizzleBufferBinding.isDirty = needTessCtlSwizzleBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessEval].swizzleBufferBinding.isDirty = needTessEvalSwizzleBuffer;
    _shaderStageResourceBindings[kMVKShaderStageFragment].swizzleBufferBinding.isDirty = needFragmentSwizzleBuffer;
}

void MVKGraphicsResourcesCommandEncoderState::bindBufferSizeBuffer(const MVKShaderImplicitRezBinding& binding,
																   bool needVertexSizeBuffer,
																   bool needTessCtlSizeBuffer,
																   bool needTessEvalSizeBuffer,
																   bool needFragmentSizeBuffer) {
    for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
        _shaderStageResourceBindings[i].bufferSizeBufferBinding.index = binding.stages[i];
    }
    _shaderStageResourceBindings[kMVKShaderStageVertex].bufferSizeBufferBinding.isDirty = needVertexSizeBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessCtl].bufferSizeBufferBinding.isDirty = needTessCtlSizeBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessEval].bufferSizeBufferBinding.isDirty = needTessEvalSizeBuffer;
    _shaderStageResourceBindings[kMVKShaderStageFragment].bufferSizeBufferBinding.isDirty = needFragmentSizeBuffer;
}

void MVKGraphicsResourcesCommandEncoderState::bindDynamicOffsetBuffer(const MVKShaderImplicitRezBinding& binding,
																	  bool needVertexDynamicOffsetBuffer,
																	  bool needTessCtlDynamicOffsetBuffer,
																	  bool needTessEvalDynamicOffsetBuffer,
																	  bool needFragmentDynamicOffsetBuffer) {
	for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
		_shaderStageResourceBindings[i].dynamicOffsetBufferBinding.index = binding.stages[i];
	}
	_shaderStageResourceBindings[kMVKShaderStageVertex].dynamicOffsetBufferBinding.isDirty = needVertexDynamicOffsetBuffer;
	_shaderStageResourceBindings[kMVKShaderStageTessCtl].dynamicOffsetBufferBinding.isDirty = needTessCtlDynamicOffsetBuffer;
	_shaderStageResourceBindings[kMVKShaderStageTessEval].dynamicOffsetBufferBinding.isDirty = needTessEvalDynamicOffsetBuffer;
	_shaderStageResourceBindings[kMVKShaderStageFragment].dynamicOffsetBufferBinding.isDirty = needFragmentDynamicOffsetBuffer;
}

void MVKGraphicsResourcesCommandEncoderState::bindViewRangeBuffer(const MVKShaderImplicitRezBinding& binding,
																  bool needVertexViewBuffer,
																  bool needFragmentViewBuffer) {
    for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
        _shaderStageResourceBindings[i].viewRangeBufferBinding.index = binding.stages[i];
    }
    _shaderStageResourceBindings[kMVKShaderStageVertex].viewRangeBufferBinding.isDirty = needVertexViewBuffer;
    _shaderStageResourceBindings[kMVKShaderStageTessCtl].viewRangeBufferBinding.isDirty = false;
    _shaderStageResourceBindings[kMVKShaderStageTessEval].viewRangeBufferBinding.isDirty = false;
    _shaderStageResourceBindings[kMVKShaderStageFragment].viewRangeBufferBinding.isDirty = needFragmentViewBuffer;
}

void MVKGraphicsResourcesCommandEncoderState::encodeBindings(MVKShaderStage stage,
                                                             const char* pStageName,
                                                             bool fullImageViewSwizzle,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLBufferBinding&)> bindBuffer,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLBufferBinding&, MVKArrayRef<const uint32_t>)> bindImplicitBuffer,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLTextureBinding&)> bindTexture,
                                                             std::function<void(MVKCommandEncoder*, MVKMTLSamplerStateBinding&)> bindSampler) {

	encodeMetalArgumentBuffer(stage);

    auto& shaderStage = _shaderStageResourceBindings[stage];

    if (shaderStage.swizzleBufferBinding.isDirty) {

        for (auto& b : shaderStage.textureBindings) {
            if (b.isDirty) { updateImplicitBuffer(shaderStage.swizzleConstants, b.index, b.swizzle); }
        }

        bindImplicitBuffer(_cmdEncoder, shaderStage.swizzleBufferBinding, shaderStage.swizzleConstants.contents());

    } else {
        assertMissingSwizzles(shaderStage.needsSwizzle && !fullImageViewSwizzle, pStageName, shaderStage.textureBindings.contents());
    }

    if (shaderStage.bufferSizeBufferBinding.isDirty) {
        for (auto& b : shaderStage.bufferBindings) {
            if (b.isDirty) { updateImplicitBuffer(shaderStage.bufferSizes, b.index, b.size); }
        }

        bindImplicitBuffer(_cmdEncoder, shaderStage.bufferSizeBufferBinding, shaderStage.bufferSizes.contents());
    }

	if (shaderStage.dynamicOffsetBufferBinding.isDirty) {
		bindImplicitBuffer(_cmdEncoder, shaderStage.dynamicOffsetBufferBinding, _dynamicOffsets.contents());
	}

    if (shaderStage.viewRangeBufferBinding.isDirty) {
        MVKSmallVector<uint32_t, 2> viewRange;
        viewRange.push_back(_cmdEncoder->getSubpass()->getFirstViewIndexInMetalPass(_cmdEncoder->getMultiviewPassIndex()));
        viewRange.push_back(_cmdEncoder->getSubpass()->getViewCountInMetalPass(_cmdEncoder->getMultiviewPassIndex()));
        bindImplicitBuffer(_cmdEncoder, shaderStage.viewRangeBufferBinding, viewRange.contents());
    }

	bool wereBufferBindingsDirty = shaderStage.areBufferBindingsDirty;
    encodeBinding<MVKMTLBufferBinding>(shaderStage.bufferBindings, shaderStage.areBufferBindingsDirty, bindBuffer);
    encodeBinding<MVKMTLTextureBinding>(shaderStage.textureBindings, shaderStage.areTextureBindingsDirty, bindTexture);
    encodeBinding<MVKMTLSamplerStateBinding>(shaderStage.samplerStateBindings, shaderStage.areSamplerStateBindingsDirty, bindSampler);

	// If any buffers have been bound, mark the GPU addressable buffers as needed.
	if (wereBufferBindingsDirty && !shaderStage.areBufferBindingsDirty ) {
		_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(MVKShaderStage(stage));
	}
}

void MVKGraphicsResourcesCommandEncoderState::offsetZeroDivisorVertexBuffers(MVKGraphicsStage stage,
                                                                             MVKGraphicsPipeline* pipeline,
                                                                             uint32_t firstInstance) {
    auto& shaderStage = _shaderStageResourceBindings[kMVKShaderStageVertex];
    for (auto& binding : pipeline->getZeroDivisorVertexBindings()) {
        uint32_t mtlBuffIdx = pipeline->getMetalBufferIndexForVertexAttributeBinding(binding.first);
        auto iter = std::find_if(shaderStage.bufferBindings.begin(), shaderStage.bufferBindings.end(), [mtlBuffIdx](const MVKMTLBufferBinding& b) { return b.index == mtlBuffIdx; });
		if (!iter) { continue; }
        switch (stage) {
            case kMVKGraphicsStageVertex:
                [_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setBufferOffset: iter->offset + firstInstance * binding.second
                                                                                                    atIndex: mtlBuffIdx];
                break;
            case kMVKGraphicsStageRasterization:
                [_cmdEncoder->_mtlRenderEncoder setVertexBufferOffset: iter->offset + firstInstance * binding.second
                                                              atIndex: mtlBuffIdx];
                break;
            default:
                assert(false);      // If we hit this, something went wrong.
                break;
        }
    }
}

void MVKGraphicsResourcesCommandEncoderState::endMetalRenderPass() {
	MVKResourcesCommandEncoderState::endMetalRenderPass();
	_renderUsageStages.clear();
}

// Mark everything as dirty
void MVKGraphicsResourcesCommandEncoderState::markDirty() {
	MVKResourcesCommandEncoderState::markDirty();
    for (uint32_t i = kMVKShaderStageVertex; i <= kMVKShaderStageFragment; i++) {
        MVKResourcesCommandEncoderState::markDirty(_shaderStageResourceBindings[i].bufferBindings, _shaderStageResourceBindings[i].areBufferBindingsDirty);
        MVKResourcesCommandEncoderState::markDirty(_shaderStageResourceBindings[i].textureBindings, _shaderStageResourceBindings[i].areTextureBindingsDirty);
        MVKResourcesCommandEncoderState::markDirty(_shaderStageResourceBindings[i].samplerStateBindings, _shaderStageResourceBindings[i].areSamplerStateBindingsDirty);
    }
}

void MVKGraphicsResourcesCommandEncoderState::encodeImpl(uint32_t stage) {

	auto* pipeline = _cmdEncoder->getGraphicsPipeline();
    bool fullImageViewSwizzle = pipeline->fullImageViewSwizzle() || _cmdEncoder->getMetalFeatures().nativeTextureSwizzle;
    bool forTessellation = pipeline->isTessellationPipeline();
	bool isDynamicVertexStride = pipeline->isDynamicState(VertexStride) && _cmdEncoder->getMetalFeatures().dynamicVertexStride;

	if (stage == kMVKGraphicsStageVertex) {
        encodeBindings(kMVKShaderStageVertex, "vertex", fullImageViewSwizzle,
                       [isDynamicVertexStride](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           if (isDynamicVertexStride) {
#if MVK_XCODE_15
                               if (b.isInline)
                                   cmdEncoder->setComputeBytesWithStride(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                                         b.mtlBytes,
                                                                         b.size,
                                                                         b.index,
                                                                         b.stride);
                               else if (b.justOffset)
                                   [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl)
                                                setBufferOffset: b.offset
                                                attributeStride: b.stride
                                                atIndex: b.index];
                               else
                                   [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl)
                                                setBuffer: b.mtlBuffer
                                                   offset: b.offset
                                          attributeStride: b.stride
                                                  atIndex: b.index];
#endif
                           } else {
                               if (b.isInline)
                                   cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                               b.mtlBytes,
                                                               b.size,
                                                               b.index);
                               else if (b.justOffset)
                                   [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl)
                                                setBufferOffset: b.offset
                                                atIndex: b.index];
                               else
                                   [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl)
                                                setBuffer: b.mtlBuffer
                                                   offset: b.offset
                                                  atIndex: b.index];
                           }
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKArrayRef<const uint32_t> s)->void {
                           cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                       s.data(),
                                                       s.byteSize(),
                                                       b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setTexture: b.mtlTexture
                                                                                                         atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setSamplerState: b.mtlSamplerState
                                                                                                              atIndex: b.index];
                       });

	} else if (!forTessellation && stage == kMVKGraphicsStageRasterization) {
        auto& shaderStage = _shaderStageResourceBindings[kMVKShaderStageVertex];
        encodeBindings(kMVKShaderStageVertex, "vertex", fullImageViewSwizzle,
					   [pipeline, isDynamicVertexStride](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           // The app may have bound more vertex attribute buffers than used by the pipeline.
                           // We must not bind those extra buffers to the shader because they might overwrite
                           // any implicit buffers used by the pipeline.
                           if (pipeline->isValidVertexBufferIndex(kMVKShaderStageVertex, b.index)) {
                               cmdEncoder->encodeVertexAttributeBuffer(b, isDynamicVertexStride);

							   // Add any translated vertex bindings for this binding
							   if ( !b.isInline ) {
                                   auto xltdVtxBindings = pipeline->getTranslatedVertexBindings();
                                   for (auto& xltdBind : xltdVtxBindings) {
                                       if (b.index == pipeline->getMetalBufferIndexForVertexAttributeBinding(xltdBind.binding)) {
                                           MVKMTLBufferBinding bx = { 
                                               .mtlBuffer = b.mtlBuffer,
                                               .offset = b.offset + xltdBind.translationOffset,
                                               .stride = b.stride,
											   .index = static_cast<uint16_t>(pipeline->getMetalBufferIndexForVertexAttributeBinding(xltdBind.translationBinding)) };
										   cmdEncoder->encodeVertexAttributeBuffer(bx, isDynamicVertexStride);
                                       }
                                   }
                               }
                           } else {
                               b.isDirty = true;	// We haven't written it out, so leave dirty until next time.
						   }
                       },
                       [&shaderStage](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKArrayRef<const uint32_t> s)->void {
                           cmdEncoder->setVertexBytes(cmdEncoder->_mtlRenderEncoder,
                                                      s.data(),
                                                      s.byteSize(),
                                                      b.index);
                           for (auto& bufb : shaderStage.bufferBindings) {
                               if (bufb.index == b.index) {
                                   // Vertex attribute occupying the same index should be marked dirty
                                   // so it will be updated when enabled
                                   bufb.markDirty();
                               }
                           }
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexTexture: b.mtlTexture
                                                                   atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexSamplerState: b.mtlSamplerState
                                                                        atIndex: b.index];
                       });

    }

    if (stage == kMVKGraphicsStageTessControl) {
        encodeBindings(kMVKShaderStageTessCtl, "tessellation control", fullImageViewSwizzle,
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           if (b.isInline)
                               cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                           b.mtlBytes,
                                                           b.size,
                                                           b.index);
                           else if (b.justOffset)
                               [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setBufferOffset: b.offset
                                                                                                                  atIndex: b.index];
                           else
                               [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setBuffer: b.mtlBuffer
                                                                                                             offset: b.offset
                                                                                                            atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKArrayRef<const uint32_t> s)->void {
                           cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl),
                                                       s.data(),
                                                       s.byteSize(),
                                                       b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setTexture: b.mtlTexture
                                                                                                         atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl) setSamplerState: b.mtlSamplerState
                                                                                                              atIndex: b.index];
                       });

    }

    if (forTessellation && stage == kMVKGraphicsStageRasterization) {
        encodeBindings(kMVKShaderStageTessEval, "tessellation evaluation", fullImageViewSwizzle,
					   [isDynamicVertexStride](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           cmdEncoder->encodeVertexAttributeBuffer(b, isDynamicVertexStride);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKArrayRef<const uint32_t> s)->void {
                           cmdEncoder->setVertexBytes(cmdEncoder->_mtlRenderEncoder,
                                                      s.data(),
                                                      s.byteSize(),
                                                      b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexTexture: b.mtlTexture
                                                                   atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setVertexSamplerState: b.mtlSamplerState
                                                                        atIndex: b.index];
                       });

    }

    if (stage == kMVKGraphicsStageRasterization) {
        encodeBindings(kMVKShaderStageFragment, "fragment", fullImageViewSwizzle,
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
                           if (b.isInline)
                               cmdEncoder->setFragmentBytes(cmdEncoder->_mtlRenderEncoder,
                                                            b.mtlBytes,
                                                            b.size,
                                                            b.index);
                           else if (b.justOffset)
                               [cmdEncoder->_mtlRenderEncoder setFragmentBufferOffset: b.offset
                                                                              atIndex: b.index];
                           else
                               [cmdEncoder->_mtlRenderEncoder setFragmentBuffer: b.mtlBuffer
                                                                         offset: b.offset
                                                                        atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b, MVKArrayRef<const uint32_t> s)->void {
                           cmdEncoder->setFragmentBytes(cmdEncoder->_mtlRenderEncoder,
                                                        s.data(),
                                                        s.byteSize(),
                                                        b.index);
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setFragmentTexture: b.mtlTexture
                                                                     atIndex: b.index];
                       },
                       [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                           [cmdEncoder->_mtlRenderEncoder setFragmentSamplerState: b.mtlSamplerState
                                                                          atIndex: b.index];
                       });
    }
}

MVKPipeline* MVKGraphicsResourcesCommandEncoderState::getPipeline() {
	return _cmdEncoder->_graphicsPipelineState.getPipeline();
}

void MVKGraphicsResourcesCommandEncoderState::bindMetalArgumentBuffer(MVKShaderStage stage, MVKMTLBufferBinding& buffBind) {
	bindBuffer(stage, buffBind);
}

void MVKGraphicsResourcesCommandEncoderState::encodeResourceUsage(MVKShaderStage stage,
																  id<MTLResource> mtlResource,
																  MTLResourceUsage mtlUsage,
																  MTLRenderStages mtlStages) {
	if (mtlResource && mtlStages) {
		if (stage == kMVKShaderStageTessCtl) {
			auto* mtlCompEnc = _cmdEncoder->getMTLComputeEncoder(kMVKCommandUseTessellationVertexTessCtl);
			[mtlCompEnc useResource: mtlResource usage: mtlUsage];
		} else {
			auto* mtlRendEnc = _cmdEncoder->_mtlRenderEncoder;
			if ([mtlRendEnc respondsToSelector: @selector(useResource:usage:stages:)]) {
				// Within a renderpass, a resource may be used by multiple descriptor bindings,
				// each of which may assign a different usage stage. Dynamically accumulate
				// usage stages across all descriptor bindings using the resource.
				auto& accumStages = _renderUsageStages[mtlResource];
				accumStages |= mtlStages;
				[mtlRendEnc useResource: mtlResource usage: mtlUsage stages: accumStages];
			} else {
				[mtlRendEnc useResource: mtlResource usage: mtlUsage];
			}
		}
	}
}

void MVKGraphicsResourcesCommandEncoderState::markBufferIndexOverridden(MVKShaderStage stage, uint32_t mtlBufferIndex) {
	auto& stageRezBinds = _shaderStageResourceBindings[stage];
	MVKResourcesCommandEncoderState::markBufferIndexOverridden(stageRezBinds.bufferBindings, mtlBufferIndex);
}

void MVKGraphicsResourcesCommandEncoderState::markOverriddenBufferIndexesDirty() {
	for (auto& stageRezBinds : _shaderStageResourceBindings) {
		MVKResourcesCommandEncoderState::markOverriddenBufferIndexesDirty(stageRezBinds.bufferBindings, stageRezBinds.areBufferBindingsDirty);
	}
}


#pragma mark -
#pragma mark MVKComputeResourcesCommandEncoderState

void MVKComputeResourcesCommandEncoderState::bindBuffer(const MVKMTLBufferBinding& binding) {
	bind(binding, _resourceBindings.bufferBindings, _resourceBindings.areBufferBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::bindTexture(const MVKMTLTextureBinding& binding) {
    bind(binding, _resourceBindings.textureBindings, _resourceBindings.areTextureBindingsDirty, _resourceBindings.needsSwizzle);
}

void MVKComputeResourcesCommandEncoderState::bindSamplerState(const MVKMTLSamplerStateBinding& binding) {
    bind(binding, _resourceBindings.samplerStateBindings, _resourceBindings.areSamplerStateBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::bindSwizzleBuffer(const MVKShaderImplicitRezBinding& binding,
															   bool needSwizzleBuffer) {
    _resourceBindings.swizzleBufferBinding.index = binding.stages[kMVKShaderStageCompute];
    _resourceBindings.swizzleBufferBinding.isDirty = needSwizzleBuffer;
}

void MVKComputeResourcesCommandEncoderState::bindBufferSizeBuffer(const MVKShaderImplicitRezBinding& binding,
																  bool needBufferSizeBuffer) {
    _resourceBindings.bufferSizeBufferBinding.index = binding.stages[kMVKShaderStageCompute];
    _resourceBindings.bufferSizeBufferBinding.isDirty = needBufferSizeBuffer;
}

void MVKComputeResourcesCommandEncoderState::bindDynamicOffsetBuffer(const MVKShaderImplicitRezBinding& binding,
																	 bool needDynamicOffsetBuffer) {
	_resourceBindings.dynamicOffsetBufferBinding.index = binding.stages[kMVKShaderStageCompute];
	_resourceBindings.dynamicOffsetBufferBinding.isDirty = needDynamicOffsetBuffer;
}

// Mark everything as dirty
void MVKComputeResourcesCommandEncoderState::markDirty() {
    MVKResourcesCommandEncoderState::markDirty();
    MVKResourcesCommandEncoderState::markDirty(_resourceBindings.bufferBindings, _resourceBindings.areBufferBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_resourceBindings.textureBindings, _resourceBindings.areTextureBindingsDirty);
    MVKResourcesCommandEncoderState::markDirty(_resourceBindings.samplerStateBindings, _resourceBindings.areSamplerStateBindingsDirty);
}

void MVKComputeResourcesCommandEncoderState::encodeImpl(uint32_t) {

	encodeMetalArgumentBuffer(kMVKShaderStageCompute);

    if (_resourceBindings.swizzleBufferBinding.isDirty) {
		for (auto& b : _resourceBindings.textureBindings) {
			if (b.isDirty) { updateImplicitBuffer(_resourceBindings.swizzleConstants, b.index, b.swizzle); }
		}

		_cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
                                     _resourceBindings.swizzleConstants.data(),
                                     _resourceBindings.swizzleConstants.size() * sizeof(uint32_t),
                                     _resourceBindings.swizzleBufferBinding.index);

	} else {
		MVKPipeline* pipeline = getPipeline();
		bool fullImageViewSwizzle = pipeline ? pipeline->fullImageViewSwizzle() : false;
		assertMissingSwizzles(_resourceBindings.needsSwizzle && !fullImageViewSwizzle, "compute", _resourceBindings.textureBindings.contents());
    }

    if (_resourceBindings.bufferSizeBufferBinding.isDirty) {
		for (auto& b : _resourceBindings.bufferBindings) {
			if (b.isDirty) { updateImplicitBuffer(_resourceBindings.bufferSizes, b.index, b.size); }
		}

		_cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
                                     _resourceBindings.bufferSizes.data(),
                                     _resourceBindings.bufferSizes.size() * sizeof(uint32_t),
                                     _resourceBindings.bufferSizeBufferBinding.index);

    }

	if (_resourceBindings.dynamicOffsetBufferBinding.isDirty) {
		_cmdEncoder->setComputeBytes(_cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
									 _dynamicOffsets.data(),
									 _dynamicOffsets.size() * sizeof(uint32_t),
									 _resourceBindings.dynamicOffsetBufferBinding.index);

	}

	bool wereBufferBindingsDirty = _resourceBindings.areBufferBindingsDirty;
	encodeBinding<MVKMTLBufferBinding>(_resourceBindings.bufferBindings, _resourceBindings.areBufferBindingsDirty,
									   [](MVKCommandEncoder* cmdEncoder, MVKMTLBufferBinding& b)->void {
		if (b.isInline) {
			cmdEncoder->setComputeBytes(cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch),
										b.mtlBytes,
										b.size,
										b.index);
        } else if (b.justOffset) {
            [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch)
                        setBufferOffset: b.offset
                                atIndex: b.index];

        } else {
			[cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setBuffer: b.mtlBuffer
																		 offset: b.offset
																		atIndex: b.index];
		}
	});

    encodeBinding<MVKMTLTextureBinding>(_resourceBindings.textureBindings, _resourceBindings.areTextureBindingsDirty,
                                        [](MVKCommandEncoder* cmdEncoder, MVKMTLTextureBinding& b)->void {
                                            [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setTexture: b.mtlTexture
																										 atIndex: b.index];
                                        });

    encodeBinding<MVKMTLSamplerStateBinding>(_resourceBindings.samplerStateBindings, _resourceBindings.areSamplerStateBindingsDirty,
                                             [](MVKCommandEncoder* cmdEncoder, MVKMTLSamplerStateBinding& b)->void {
                                                 [cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch) setSamplerState: b.mtlSamplerState
																												   atIndex: b.index];
                                             });

	// If any buffers have been bound, mark the GPU addressable buffers as needed.
	if (wereBufferBindingsDirty && !_resourceBindings.areBufferBindingsDirty ) {
		_cmdEncoder->_gpuAddressableBuffersState.useGPUAddressableBuffersInStage(kMVKShaderStageCompute);
	}
}

MVKPipeline* MVKComputeResourcesCommandEncoderState::getPipeline() {
	return _cmdEncoder->_computePipelineState.getPipeline();
}

void MVKComputeResourcesCommandEncoderState::bindMetalArgumentBuffer(MVKShaderStage stage, MVKMTLBufferBinding& buffBind) {
	bindBuffer(buffBind);
}

void MVKComputeResourcesCommandEncoderState::encodeResourceUsage(MVKShaderStage stage,
																 id<MTLResource> mtlResource,
																 MTLResourceUsage mtlUsage,
																 MTLRenderStages mtlStages) {
	if (mtlResource) {
		auto* mtlCompEnc = _cmdEncoder->getMTLComputeEncoder(kMVKCommandUseDispatch);
		[mtlCompEnc useResource: mtlResource usage: mtlUsage];
	}
}

void MVKComputeResourcesCommandEncoderState::markBufferIndexOverridden(uint32_t mtlBufferIndex) {
	MVKResourcesCommandEncoderState::markBufferIndexOverridden(_resourceBindings.bufferBindings, mtlBufferIndex);
}

void MVKComputeResourcesCommandEncoderState::markOverriddenBufferIndexesDirty() {
	MVKResourcesCommandEncoderState::markOverriddenBufferIndexesDirty(_resourceBindings.bufferBindings, _resourceBindings.areBufferBindingsDirty);
}


#pragma mark -
#pragma mark MVKGPUAddressableBuffersCommandEncoderState

void MVKGPUAddressableBuffersCommandEncoderState::useGPUAddressableBuffersInStage(MVKShaderStage shaderStage) {
	MVKPipeline* pipeline = (shaderStage == kMVKShaderStageCompute
							 ? (MVKPipeline*)_cmdEncoder->getComputePipeline()
							 : (MVKPipeline*)_cmdEncoder->getGraphicsPipeline());
	if (pipeline && pipeline->usesPhysicalStorageBufferAddressesCapability(shaderStage)) {
		_usageStages[shaderStage] = true;
		markDirty();
	}
}

void MVKGPUAddressableBuffersCommandEncoderState::encodeImpl(uint32_t stage) {
	auto* mvkDev = getDevice();
	for (uint32_t i = kMVKShaderStageVertex; i < kMVKShaderStageCount; i++) {
		MVKShaderStage shaderStage = MVKShaderStage(i);
		if (_usageStages[shaderStage]) {
			MVKResourcesCommandEncoderState* rezEncState = (shaderStage == kMVKShaderStageCompute
															? (MVKResourcesCommandEncoderState*)&_cmdEncoder->_computeResourcesState
															: (MVKResourcesCommandEncoderState*)&_cmdEncoder->_graphicsResourcesState);
			mvkDev->encodeGPUAddressableBuffers(rezEncState, shaderStage);
		}
	}
	mvkClear(_usageStages, kMVKShaderStageCount);
}


#pragma mark -
#pragma mark MVKOcclusionQueryCommandEncoderState

// Metal resets the query counter at a render pass boundary, so copy results to the query pool's accumulation buffer.
// Don't copy occlusion info until after rasterization, as Metal renderpasses can be ended prematurely during tessellation.
void MVKOcclusionQueryCommandEncoderState::endMetalRenderPass() {
	const MVKMTLBufferAllocation* vizBuff = _cmdEncoder->_pEncodingContext->visibilityResultBuffer;
    if ( !_hasRasterized || !vizBuff || _mtlRenderPassQueries.empty() ) { return; }  // Nothing to do.

	id<MTLComputePipelineState> mtlAccumState = _cmdEncoder->getCommandEncodingPool()->getAccumulateOcclusionQueryResultsMTLComputePipelineState();
    id<MTLComputeCommandEncoder> mtlAccumEncoder = _cmdEncoder->getMTLComputeEncoder(kMVKCommandUseAccumOcclusionQuery, true);
    [mtlAccumEncoder setComputePipelineState: mtlAccumState];
    for (auto& qryLoc : _mtlRenderPassQueries) {
        // Accumulate the current results to the query pool's buffer.
        [mtlAccumEncoder setBuffer: qryLoc.queryPool->getVisibilityResultMTLBuffer()
                            offset: qryLoc.queryPool->getVisibilityResultOffset(qryLoc.query)
                           atIndex: 0];
        [mtlAccumEncoder setBuffer: vizBuff->_mtlBuffer
                            offset: vizBuff->_offset + qryLoc.visibilityBufferOffset
                           atIndex: 1];
        [mtlAccumEncoder dispatchThreadgroups: MTLSizeMake(1, 1, 1)
                        threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
    }
    _mtlRenderPassQueries.clear();
	_hasRasterized = false;
}

// The Metal visibility buffer has a finite size, and on some Metal platforms (looking at you M1),
// query offsets cannnot be reused with the same MTLCommandBuffer. If enough occlusion queries are
// begun within a single MTLCommandBuffer, it may exhaust the visibility buffer. If that occurs,
// report an error and disable further visibility tracking for the remainder of the MTLCommandBuffer.
// In most cases, a MTLCommandBuffer corresponds to a Vulkan command submit (VkSubmitInfo),
// and so the error text is framed in terms of the Vulkan submit.
void MVKOcclusionQueryCommandEncoderState::beginOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query, VkQueryControlFlags flags) {
	if (_cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset + kMVKQuerySlotSizeInBytes <= _cmdEncoder->getMetalFeatures().maxQueryBufferSize) {
		bool shouldCount = _cmdEncoder->getEnabledFeatures().occlusionQueryPrecise && mvkAreAllFlagsEnabled(flags, VK_QUERY_CONTROL_PRECISE_BIT);
		_mtlVisibilityResultMode = shouldCount ? MTLVisibilityResultModeCounting : MTLVisibilityResultModeBoolean;
		_mtlRenderPassQueries.emplace_back(pQueryPool, query, _cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset);
	} else {
		reportError(VK_ERROR_OUT_OF_DEVICE_MEMORY, "vkCmdBeginQuery(): The maximum number of queries in a single Vulkan command submission is %llu.", _cmdEncoder->getMetalFeatures().maxQueryBufferSize / kMVKQuerySlotSizeInBytes);
		_mtlVisibilityResultMode = MTLVisibilityResultModeDisabled;
		_cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset -= kMVKQuerySlotSizeInBytes;
	}
	_hasRasterized = false;
    markDirty();
}

void MVKOcclusionQueryCommandEncoderState::endOcclusionQuery(MVKOcclusionQueryPool* pQueryPool, uint32_t query) {
	_mtlVisibilityResultMode = MTLVisibilityResultModeDisabled;
	_cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset += kMVKQuerySlotSizeInBytes;
	_hasRasterized = true;	// Handle begin and end query with no rasterizing before end of renderpass.
	markDirty();
}

void MVKOcclusionQueryCommandEncoderState::encodeImpl(uint32_t stage) {
	if (stage != kMVKGraphicsStageRasterization) { return; }

	_hasRasterized = true;
	[_cmdEncoder->_mtlRenderEncoder setVisibilityResultMode: _mtlVisibilityResultMode
													 offset: _cmdEncoder->_pEncodingContext->mtlVisibilityResultOffset];
}
