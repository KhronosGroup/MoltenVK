/*
 * MVKStateTracking.h
 *
 * Copyright (c) 2024-2026 Evan Tang for CodeWeavers
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

#include "MVKBitArray.h"

class MVKPixelFormats;

#pragma mark -
#pragma mark MVKMTLDepthStencilDescriptorData

/** A structure to hold configuration data for the operations of a MTLStencilDescriptor. */
struct MVKMTLStencilOps {
	uint8_t stencilCompareFunction;    /**< The stencil compare function (interpreted as MTLCompareFunction). */
	uint8_t stencilFailureOperation;   /**< The operation to take when the stencil test fails (interpreted as MTLStencilOperation). */
	uint8_t depthFailureOperation;     /**< The operation to take when the stencil test passes, but the depth test fails (interpreted as MTLStencilOperation). */
	uint8_t depthStencilPassOperation; /**< The operation to take when both the stencil and depth tests pass (interpreted as MTLStencilOperation). */
	constexpr MVKMTLStencilOps()
		: stencilCompareFunction(MTLCompareFunctionAlways)
		, stencilFailureOperation(MTLStencilOperationKeep)
		, depthFailureOperation(MTLStencilOperationKeep)
		, depthStencilPassOperation(MTLStencilOperationKeep)
	{
	}
};

/** A structure to hold configuration data for creating an MTLStencilDescriptor instance. */
struct MVKMTLStencilDescriptorData {
	uint32_t readMask;                 /**< The bit-mask to apply when comparing the stencil buffer value to the reference value. */
	uint32_t writeMask;                /**< The bit-mask to apply when writing values to the stencil buffer. */
	MVKMTLStencilOps op;

	bool operator==(const MVKMTLStencilDescriptorData& rhs) const { return mvkAreEqual(this, &rhs); }
	bool operator!=(const MVKMTLStencilDescriptorData& rhs) const { return !(*this == rhs); }

	constexpr MVKMTLStencilDescriptorData(): readMask(~0u) , writeMask(~0u) {}

	/** Use default values for unused parts to reduce the number of different samplers. */
	constexpr void simplify(uint8_t depthCompare) {
		if (op.stencilCompareFunction == MTLCompareFunctionAlways)
			op.stencilFailureOperation = op.depthStencilPassOperation;
		// Writing to [[sample_mask]] in a shader that also writes depth is treated as failing the depth test on Apple GPUs.
		// If depth compare is always, we can work around this by forcing operation keep for depth failure.
		// TODO: Work around in shader by discarding based on sample_id and coverage mask for shaders that write both depth and coverage on Apple GPUs
		if (depthCompare == MTLCompareFunctionAlways)
			op.depthFailureOperation = MTLStencilOperationKeep;
		if (op.stencilCompareFunction == MTLCompareFunctionNever && depthCompare == MTLCompareFunctionNever)
			op.depthStencilPassOperation = MTLStencilOperationKeep;
		if (op.stencilCompareFunction == MTLCompareFunctionAlways || op.stencilCompareFunction == MTLCompareFunctionNever)
			readMask = ~0u;
		if (allKeep())
			writeMask = ~0u;
	}

	/** Check whether all operations are MTLStencilOperationKeep. */
	constexpr bool allKeep() const {
		return op.stencilFailureOperation == MTLStencilOperationKeep
		    && op.depthFailureOperation == MTLStencilOperationKeep
		    && op.depthStencilPassOperation == MTLStencilOperationKeep;
	}

	/** Check whether this stencil config does anything at all. */
	constexpr bool isEnabled() const {
		return !allKeep() || op.stencilCompareFunction != MTLCompareFunctionAlways;
	}

	/** Get a stencil descriptor that does nothing but write if `write`. */
	static constexpr MVKMTLStencilDescriptorData Write(bool write) {
		MVKMTLStencilDescriptorData res;
		if (write) {
			res.op.stencilFailureOperation = MTLStencilOperationReplace;
			res.op.depthFailureOperation = MTLStencilOperationReplace;
			res.op.depthStencilPassOperation = MTLStencilOperationReplace;
		}
		return res;
	}
};

static_assert(sizeof(MVKMTLStencilDescriptorData) == offsetof(MVKMTLStencilDescriptorData, op.depthStencilPassOperation) + 1, "No Padding");

/**
 * A structure to hold configuration data for creating an MTLDepthStencilDescriptor instance.
 * Instances of this structure can be used as a map key.
 */
struct alignas(uint64_t) MVKMTLDepthStencilDescriptorData {
	MVKMTLStencilDescriptorData frontFaceStencilData;
	MVKMTLStencilDescriptorData backFaceStencilData;
	uint8_t depthCompareFunction; /**< The depth compare function (interpreted as MTLCompareFunction). */
	bool depthWriteEnabled;       /**< Indicates whether depth writing is enabled. */
	bool stencilTestEnabled;      /**< Indicates whether stencil testing is enabled. */

	bool operator==(const MVKMTLDepthStencilDescriptorData& rhs) const { return mvkAreEqual(this, &rhs); }
	bool operator!=(const MVKMTLDepthStencilDescriptorData& rhs) const { return !(*this == rhs); }

	std::size_t hash() const {
		return mvkHash((uint64_t*)this, sizeof(*this) / sizeof(uint64_t));
	}

	constexpr void disableDepth() {
		depthCompareFunction = MTLCompareFunctionAlways;
		depthWriteEnabled = false;
	}

	constexpr void disableStencil() {
		stencilTestEnabled = false;
		frontFaceStencilData = {};
		backFaceStencilData = {};
	}

	constexpr void reset() {
		disableDepth();
		disableStencil();
	}

	/**
	 * Use default values for unused parts to reduce the number of different samplers.
	 * If `ignoreStencilTestEnabled`, simplification will act as if `stencilTestEnabled` is `true`.
	 */
	constexpr void simplify(bool ignoreStencilTestEnabled) {
		if (!ignoreStencilTestEnabled && !stencilTestEnabled) {
			frontFaceStencilData = {};
			backFaceStencilData = {};
		} else {
			frontFaceStencilData.simplify(depthCompareFunction);
			backFaceStencilData.simplify(depthCompareFunction);
			stencilTestEnabled = frontFaceStencilData.isEnabled() || backFaceStencilData.isEnabled();
		}
	}

	MVKMTLDepthStencilDescriptorData() {
		mvkClear(this); // Clear all memory to ensure memory comparisons will work.
		reset();
	}

	/** Gets a depth stencil descriptor that does nothing but write depth if `depth` and stencil if `stencil`. */
	static MVKMTLDepthStencilDescriptorData Write(bool depth, bool stencil) {
		MVKMTLDepthStencilDescriptorData res;
		if (depth)
			res.depthWriteEnabled = true;
		if (stencil) {
			res.stencilTestEnabled = true;
			res.frontFaceStencilData = MVKMTLStencilDescriptorData::Write(true);
			res.backFaceStencilData = MVKMTLStencilDescriptorData::Write(true);
		}
		return res;
	}
};

template <>
struct std::hash<MVKMTLDepthStencilDescriptorData> {
	std::size_t operator()(const MVKMTLDepthStencilDescriptorData& k) const { return k.hash(); }
};

/** These buffers are dirty-tracked across draw calls, and need code to make sure they're invalidated if they ever change binding indices. */
enum class MVKNonVolatileImplicitBuffer : uint32_t {
	PushConstant,
	Swizzle,
	BufferSize,
	DynamicOffset,
	ViewRange,
	EmulatedReversedDepthViewport,
	DepthClip,
	BlendState,
	VertexPull,
	Count
};

enum class MVKImplicitBuffer : uint32_t {
	PushConstant  = static_cast<uint32_t>(MVKNonVolatileImplicitBuffer::PushConstant),
	Swizzle       = static_cast<uint32_t>(MVKNonVolatileImplicitBuffer::Swizzle),
	BufferSize    = static_cast<uint32_t>(MVKNonVolatileImplicitBuffer::BufferSize),
	DynamicOffset = static_cast<uint32_t>(MVKNonVolatileImplicitBuffer::DynamicOffset),
	ViewRange     = static_cast<uint32_t>(MVKNonVolatileImplicitBuffer::ViewRange),
	EmulatedReversedDepthViewport = static_cast<uint32_t>(MVKNonVolatileImplicitBuffer::EmulatedReversedDepthViewport),
	DepthClip     = static_cast<uint32_t>(MVKNonVolatileImplicitBuffer::DepthClip),
	BlendState    = static_cast<uint32_t>(MVKNonVolatileImplicitBuffer::BlendState),
	VertexPull    = static_cast<uint32_t>(MVKNonVolatileImplicitBuffer::VertexPull),

	// Volatile implicit buffers
	// These buffers are updated per draw call, and are therefore always considered dirty
	IndirectParams,
	Output,
	PatchOutput,
	TessLevel,
	Index,
	DispatchBase,
	DrawId,
	Count,
};

typedef MVKFlagList<MVKImplicitBuffer> MVKImplicitBufferList;
static constexpr MVKImplicitBufferList MVKNonVolatileImplicitBuffers = MVKImplicitBufferList::fromBits(MVKFlagList<MVKNonVolatileImplicitBuffer>::all().bits);

struct MVKImplicitBufferBindings {
	MVKImplicitBufferList needed;
	MVKOnePerEnumEntry<uint8_t, MVKImplicitBuffer> ids;

	void set(MVKImplicitBuffer buffer, uint8_t idx) {
		needed.add(buffer);
		ids[buffer] = idx;
	}
	void clear(MVKImplicitBuffer buffer) {
		needed.remove(buffer);
	}
};

/** Contains one bit for each resource that can be bound to a pipeline stage. */
union MVKStageResourceBits {
	struct {
		MVKStaticBitSet<kMVKMaxTextureCount> textures;
		MVKStaticBitSet<kMVKMaxBufferCount>  buffers;
		MVKStaticBitSet<kMVKMaxSamplerCount> samplers;
		MVKStaticBitSet<kMVKMaxDescriptorSetCount> descriptorSetData;
	};
	MVKStaticBitSet<192> allBits;
	constexpr MVKStageResourceBits(): allBits{} {}
	// Note: Reset is done with a large memset over multiple StageResourceBits
};
static_assert(sizeof(MVKStageResourceBits) == sizeof(MVKStageResourceBits::allBits), "Make sure we can quickly process all bits");

enum class MVKRenderStateFlag {
	BlendConstants,
	ColorBlend,
	ColorBlendEnable,
	CullMode,
	DepthBias,
	DepthBiasEnable,
	DepthBounds,
	DepthBoundsTestEnable,
	DepthClipEnable,
	DepthCompareOp,
	DepthTestEnable,
	DepthWriteEnable,
	FrontFace,
	LineRasterizationMode,
	LineWidth,
	LogicOp,
	LogicOpEnable,
	PatchControlPoints,
	PolygonMode,
	PrimitiveRestartEnable,
	PrimitiveTopology,
	ProvokingVertexMode,
	RasterizerDiscardEnable,
	SampleLocations,
	SampleLocationsEnable,
	Scissors,
	StencilCompareMask,
	StencilOp,
	StencilReference,
	StencilTestEnable,
	StencilWriteMask,
	VertexStride,
	Viewports,
	Count
};

using MVKRenderStateFlags = MVKFlagList<MVKRenderStateFlag>;

enum class MVKRenderStateEnableFlag {
	CullBothFaces,
	DepthBias,
	DepthBoundsTest,
	DepthClamp,
	DepthTest,
	PrimitiveRestart,
	RasterizerDiscard,
	SampleLocations,
	Count
};

using MVKRenderStateEnableFlags = MVKFlagList<MVKRenderStateEnableFlag>;

struct MVKDepthBias {
	float depthBiasConstantFactor;
	float depthBiasClamp;
	float depthBiasSlopeFactor;
};

struct MVKDepthBounds {
	float minDepthBound;
	float maxDepthBound;
};

struct MVKStencilReference {
	uint32_t frontFaceValue;
	uint32_t backFaceValue;
};

enum class MVKPolygonMode : uint8_t {
	Fill = MTLTriangleFillModeFill,
	Lines = MTLTriangleFillModeLines,
	Point,
};

enum class MVKLineRasterizationMode : uint8_t {
	Default,
	Bresenham,
};

static inline MVKPolygonMode mvkPolygonModeFromVkPolygonMode(VkPolygonMode mode) {
	switch (mode) {
		case VK_POLYGON_MODE_FILL:  return MVKPolygonMode::Fill;
		case VK_POLYGON_MODE_LINE:  return MVKPolygonMode::Lines;
		case VK_POLYGON_MODE_POINT: return MVKPolygonMode::Point;
		default:                    return MVKPolygonMode::Fill;
	}
}

static inline MVKLineRasterizationMode mvkLineRasterizationModeFromVkLineRasterizationMode(VkLineRasterizationMode mode) {
	return mode == VK_LINE_RASTERIZATION_MODE_BRESENHAM ? MVKLineRasterizationMode::Bresenham : MVKLineRasterizationMode::Default;
}

struct MVKRenderStateData {
	uint8_t numViewports = 0;
	uint8_t numScissors = 0;
	uint8_t numSampleLocations = 0;
	uint8_t patchControlPoints = 0;
	uint8_t cullMode = MTLCullModeNone;
	uint8_t frontFace = MTLWindingClockwise;
	uint8_t primitiveType = MTLPrimitiveTypePoint;
	MVKPolygonMode polygonMode = MVKPolygonMode::Fill;
	MVKLineRasterizationMode lineRasterizationMode = MVKLineRasterizationMode::Default;
	MVKRenderStateEnableFlags enable;
	float lineWidth = 1;
	MVKColor32 blendConstants = {};
	MVKDepthBias depthBias = {};
	MVKDepthBounds depthBounds = {};
	MVKStencilReference stencilReference = {};
	MVKMTLDepthStencilDescriptorData depthStencil;
#if MVK_USE_METAL_PRIVATE_API
	uint8_t provokingVertexMode = MTLProvokingVertexModeFirst;
#else
	uint8_t provokingVertexMode = 0;
#endif
	void setCullMode(VkCullModeFlags cull) {
		cull &= VK_CULL_MODE_FRONT_AND_BACK;
		if (cull == VK_CULL_MODE_FRONT_BIT)
			cullMode = MTLCullModeFront;
		else if (cull == VK_CULL_MODE_BACK_BIT)
			cullMode = MTLCullModeBack;
		else
			cullMode = MTLCullModeNone;
		enable.set(MVKRenderStateEnableFlag::CullBothFaces, cull == VK_CULL_MODE_FRONT_AND_BACK);
	}
	void setFrontFace(VkFrontFace face) {
		frontFace = face == VK_FRONT_FACE_CLOCKWISE ? MTLWindingClockwise : MTLWindingCounterClockwise;
	}
	void setPolygonMode(VkPolygonMode mode) {
		polygonMode = mvkPolygonModeFromVkPolygonMode(mode);
	}
	void setLineRasterizationMode(VkLineRasterizationMode mode) {
		lineRasterizationMode = mvkLineRasterizationModeFromVkLineRasterizationMode(mode);
	}
};


#pragma mark -
#pragma mark Shader object state

/** A vertex buffer binding set by vkCmdSetVertexInputEXT. */
struct MVKDynamicVertexBinding {
	uint32_t binding;
	uint32_t stride;
	uint32_t divisor;
	uint32_t inputRate;
};

/** A vertex attribute set by vkCmdSetVertexInputEXT. */
struct MVKDynamicVertexAttribute {
	uint32_t location;
	uint32_t binding;
	uint32_t format;
	uint32_t offset;
};

/**
 * The vertex input state set by vkCmdSetVertexInputEXT.
 *
 * Metal bakes the vertex layout into a MTLRenderPipelineState, so this is held as plain data
 * until a draw, and contributes to the identity of the pipeline built to satisfy that draw.
 */
struct MVKDynamicVertexInput {
	MVKDynamicVertexBinding bindings[kMVKMaxVertexInputBindingCount];
	MVKDynamicVertexAttribute attributes[kMVKMaxVertexInputAttributeCount];
	uint32_t bindingCount = 0;
	uint32_t attributeCount = 0;
	/**
	 * Whether a pipeline built for this state takes the stride from the vertex buffer bindings
	 * rather than from the layout baked into it.
	 *
	 * Set when vkCmdBindVertexBuffers2 supplied the stride more recently than
	 * vkCmdSetVertexInputEXT, since Vulkan lets the later call win, and also set when the key
	 * has had its strides canonicalized so that draws differing only in stride share a
	 * pipeline. Part of the pipeline key, because it decides how the pipeline is built.
	 */
	uint32_t stridesFromVertexBuffers = 0;
};

/**
 * Returns the control word a vertex shader that loads its own attributes decodes this format
 * by, or zero for a format it cannot decode. See SPIRVVertexPulling.h.
 */
uint32_t mvkVertexPullFormatControl(VkFormat format);

/**
 * Returns whether every attribute in this vertex layout can be loaded by such a shader, which
 * needs each format to be one it decodes, and one the device offers for vertex buffers.
 */
bool mvkCanPullVertexInput(const MVKDynamicVertexInput& vertexInput, MVKPixelFormats* pixFmts);

/**
 * Reduces a primitive topology to the value a shader object pipeline is keyed and built on.
 *
 * The pipeline only ever consults the topology class, plus whether it is a triangle fan, which
 * the draw path emulates. Every list, strip and adjacency variant within a class therefore
 * shares one pipeline, instead of each forcing its own Metal build.
 */
/**
 * Placed in a shader object pipeline key in place of the topology, where the pipeline needs no
 * topology class at all and therefore serves points, lines and triangles alike.
 */
static constexpr VkPrimitiveTopology kMVKTopologyClassNotNeeded = VK_PRIMITIVE_TOPOLOGY_MAX_ENUM;

static inline VkPrimitiveTopology mvkShaderObjectKeyTopology(VkPrimitiveTopology t) {
	switch (t) {
		case VK_PRIMITIVE_TOPOLOGY_POINT_LIST:
			return VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
		case VK_PRIMITIVE_TOPOLOGY_LINE_LIST:
		case VK_PRIMITIVE_TOPOLOGY_LINE_STRIP:
		case VK_PRIMITIVE_TOPOLOGY_LINE_LIST_WITH_ADJACENCY:
		case VK_PRIMITIVE_TOPOLOGY_LINE_STRIP_WITH_ADJACENCY:
			return VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST:
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP:
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST_WITH_ADJACENCY:
		case VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP_WITH_ADJACENCY:
			return VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
		default:
			return t;		// Triangle fan and patch list carry meaning of their own.
	}
}

/**
 * The state that Vulkan allows to be set dynamically but Metal bakes into a MTLRenderPipelineState.
 *
 * None of this can be changed on an already built Metal pipeline, so a draw that uses shader
 * objects builds one from these values, and draws that agree on all of them share it. Everything
 * is plain data, and the constructor clears the whole struct before applying the Vulkan defaults,
 * so the bytes can be hashed and compared directly.
 */
struct MVKDynamicPipelineState {
	VkPipelineColorBlendAttachmentState blendAttachments[kMVKMaxColorAttachmentCount];
	VkBool32 colorWriteEnables[kMVKMaxColorAttachmentCount];
	uint32_t sampleMask;
	uint32_t rasterizationSamples;
	uint32_t logicOp;
	uint32_t domainOrigin;
	uint32_t topology;
	uint8_t logicOpEnable;
	uint8_t alphaToCoverageEnable;
	uint8_t alphaToOneEnable;
	uint8_t negativeOneToOne;
	/**
	 * Whether the fragment shader carries the fragment output operations for itself, reading the
	 * state for them from a buffer.
	 *
	 * This is the only thing blending, the write masks, the sample mask and the alpha operations
	 * leave in the key. It is set for a draw that departs from writing every channel straight
	 * through at full coverage, and cleared for one that does not, because a shader that reads the
	 * attachment and writes a sample mask gives up hidden surface removal and the early depth
	 * test, which opaque geometry must not pay for.
	 */
	uint8_t blendInShader;

	MVKDynamicPipelineState() {
		memset(this, 0, sizeof(*this));
		for (auto& ba : blendAttachments) { ba.colorWriteMask = (VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
															     VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT); }
		for (auto& cwe : colorWriteEnables) { cwe = VK_TRUE; }
		sampleMask = ~0u;
		rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
		logicOp = VK_LOGIC_OP_COPY;
		domainOrigin = VK_TESSELLATION_DOMAIN_ORIGIN_UPPER_LEFT;
		topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
	}
};
