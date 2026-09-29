/*
 * SPIRVBlendInShader.h
 *
 * Copyright (c) 2015-2026 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include <cstdint>
#include <string>
#include <vector>

namespace mvk {

	/**
	 * The layout of the blend state block a fragment shader reads after the transform below.
	 *
	 * Every Vulkan blend factor is a linear combination of one, the source, the source alpha,
	 * the destination, the destination alpha, and the alpha-saturate term. The driver knows the
	 * blend state and the blend constants when it records a draw, so it resolves each factor to
	 * those coefficients and the shader evaluates
	 *
	 *     factor = constant + k.x * src + k.y * srcAlpha + k.z * dst + k.w * dstAlpha + sat * saturate
	 *
	 * which is a few multiply-adds rather than a selection over all nineteen factors. Blend
	 * constants fold into the constant term, so they never appear in the shader.
	 *
	 * Slots are ordered source colour, destination colour, source alpha, destination alpha.
	 * Laid out as std140 arrays of vec4, which have a 16 byte stride, so this maps directly.
	 */
	static constexpr uint32_t kSPIRVBlendMaxAttachments = 8;
	static constexpr uint32_t kSPIRVBlendSlotCount = 4;		/**< srcColor, dstColor, srcAlpha, dstAlpha. */

	struct SPIRVBlendState {
		float constantTerm[kSPIRVBlendMaxAttachments * kSPIRVBlendSlotCount][4];	/**< Per slot, the constant term. */
		float coefficients[kSPIRVBlendMaxAttachments * kSPIRVBlendSlotCount][4];	/**< Per slot, (src, srcAlpha, dst, dstAlpha). */
		float saturate[kSPIRVBlendMaxAttachments][4];		/**< Per attachment, the saturate coefficient of each slot. */
		float opFactors[kSPIRVBlendMaxAttachments][4];		/**< Per attachment, (srcMul, dstMul) for colour then alpha. */
		uint32_t control[kSPIRVBlendMaxAttachments][4];		/**< Per attachment, (colorOp, alphaOp, flags, unused). */
		uint32_t multisample[4];		/**< (sampleMask, flags, sampleCount, unused); read only with dynamicMultisample. */
	};
	static_assert(sizeof(SPIRVBlendState) == 1424, "SPIRVBlendState must match the std140 layout the shader reads.");

	/** Values for the clamp mode in the control flags. */
	enum SPIRVBlendClampMode : uint32_t {
		kSPIRVBlendClampNone = 0,		/**< Floating point attachment: no clamping. */
		kSPIRVBlendClampUnorm = 1,		/**< Unsigned normalized attachment: clamp to [0, 1]. */
		kSPIRVBlendClampSnorm = 2,		/**< Signed normalized attachment: clamp to [-1, 1]. */
	};

	/** Values for the blend operation in the control block; min and max ignore the factors. */
	enum SPIRVBlendOp : uint32_t {
		kSPIRVBlendOpLinear = 0,		/**< Add, subtract and reverse subtract, distinguished by opFactors. */
		kSPIRVBlendOpMin = 1,
		kSPIRVBlendOpMax = 2,
	};

	static constexpr uint32_t kSPIRVBlendFlagEnable = 1u << 0;
	static constexpr uint32_t kSPIRVBlendFlagWriteMaskShift = 1;
	static constexpr uint32_t kSPIRVBlendFlagClampShift = 5;

	/** Flags in the multisample word. */
	static constexpr uint32_t kSPIRVBlendFlagAlphaToOne = 1u << 0;
	static constexpr uint32_t kSPIRVBlendFlagAlphaToCoverage = 1u << 1;

	/** The descriptor set and binding the transformed shader reads the blend state from. */
	static constexpr uint32_t kSPIRVBlendStateDescriptorSet = 8;
	static constexpr uint32_t kSPIRVBlendStateBinding = 0;

	/**
	 * Rewrites a fragment shader so that it performs color blending itself, instead of leaving
	 * it to the fixed-function blend state baked into a Metal pipeline.
	 *
	 * Metal fixes blend factors, operations and the color write mask when a pipeline is built,
	 * so any change to them costs a new pipeline. Apple GPUs blend in the shader anyway: the
	 * fragment function can read the framebuffer through a color input, and Metal's blend stage
	 * on those GPUs is itself implemented that way. This transform makes that explicit. For each
	 * color output it adds a subpass input on the same attachment, and before every return of the
	 * entry point it reads the output back, fetches the destination, applies the blend equation
	 * and write mask from a uniform block, and stores the result. The blend state is then a buffer
	 * that changes per draw, and the Metal pipeline is built with blending off and all channels
	 * written.
	 *
	 * The subpass inputs are decorated so that SPIRV-Cross, with use_framebuffer_fetch_subpasses
	 * enabled, emits them as [[color(n)]] arguments; the uniform block sits in descriptor set
	 * kSPIRVBlendStateDescriptorSet, which is beyond the argument buffer range and so is bound
	 * as a plain buffer through an ordinary resource binding.
	 *
	 * Returns true if the shader was transformed. Returns false, leaving the SPIR-V untouched,
	 * when the shader is not a fragment shader, has no color outputs, already reads subpass
	 * inputs, writes outputs of a width other than 32 bits, or writes a color output that is
	 * not 4-component (Metal requires the framebuffer-fetch input to match the output type, and
	 * the fetch is always 4-component); the caller then keeps blending in the pipeline as before.
	 * On failure, log describes the reason.
	 *
	 * attachmentMask has a bit set for each location that has a colour attachment behind it. A
	 * shader may declare outputs beyond the attachments that exist, and those must be left alone:
	 * there is nothing to fetch, and reading a colour input with no attachment is invalid.
	 *
	 * With dynamicMultisample, the shader also takes over the sample mask, alpha to coverage and
	 * alpha to one, which Metal likewise bakes, writing the combined coverage to gl_SampleMask.
	 * That write costs the early depth test, so the caller asks for it only when a draw actually
	 * departs from the defaults, and every draw that does then shares one pipeline.
	 */
	bool blendFragmentOutputsInShader(std::vector<uint32_t>& spirv, bool multisampled,
									  uint32_t attachmentMask, bool dynamicMultisample, std::string& log);

	/**
	 * Returns whether blendFragmentOutputsInShader() would transform this shader, without
	 * transforming it. A shader object needs to know this when it is created, because it
	 * decides whether blend state belongs in the key its pipelines are cached under.
	 *
	 * pHasCoverageOutput, when given, reports whether the shader writes the four component
	 * floating point output at location zero that alpha to coverage derives coverage from. A
	 * shader without one cannot take that state over, and leaves it in the key.
	 */
	bool canBlendFragmentOutputsInShader(const std::vector<uint32_t>& spirv, bool* pHasCoverageOutput = nullptr);

}
