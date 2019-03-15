/*
 * SPIRVToMSLConverter.cpp
 *
 * Copyright (c) 2014-2019 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "SPIRVToMSLConverter.h"
#include "MVKCommonEnvironment.h"
#include "MVKStrings.h"
#include "FileSupport.h"
#include "spirv_msl.hpp"
#include "SPIRVSupport.h"

using namespace mvk;
using namespace std;

// Verify that the spvAux structure used to pass auxilliary info between MoltenVK and SPIRV-Cross has not changed.
#define MVK_SUPPORTED_MSL_AUX_BUFFER_STRUCT_VERSION		1
#if MVK_SUPPORTED_MSL_AUX_BUFFER_STRUCT_VERSION != SPIRV_CROSS_MSL_AUX_BUFFER_STRUCT_VERSION
#	error "The version number of the MSL spvAux struct used to pass auxilliary info to shaders does not match between MoltenVK and SPIRV-Cross. If the spvAux struct definition is not the same between MoltenVK and shaders created by SPRIV-Cross, memory errors will occur."
#endif


#pragma mark -
#pragma mark SPIRVToMSLConverterContext

// Returns whether the vector contains the value (using a matches(T&) comparison member function). */
template<class T>
bool contains(const vector<T>& vec, const T& val) {
    for (const T& vecVal : vec) { if (vecVal.matches(val)) { return true; } }
    return false;
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConverterOptions::matches(const SPIRVToMSLConverterOptions& other) const {
	if (entryPointStage != other.entryPointStage) { return false; }
    if (mslVersion != other.mslVersion) { return false; }
	if (texelBufferTextureWidth != other.texelBufferTextureWidth) { return false; }
	if (auxBufferIndex != other.auxBufferIndex) { return false; }
    if (!!shouldFlipVertexY != !!other.shouldFlipVertexY) { return false; }
    if (!!isRenderingPoints != !!other.isRenderingPoints) { return false; }
	if (!!shouldSwizzleTextureSamples != !!other.shouldSwizzleTextureSamples) { return false; }
	if (entryPointName != other.entryPointName) { return false; }
    return true;
}

MVK_PUBLIC_SYMBOL std::string SPIRVToMSLConverterOptions::printMSLVersion(uint32_t mslVersion, bool includePatch) {
	string verStr;

	uint32_t major = mslVersion / 10000;
	verStr += to_string(major);

	uint32_t minor = (mslVersion - makeMSLVersion(major)) / 100;
	verStr += ".";
	verStr += to_string(minor);

	if (includePatch) {
		uint32_t patch = mslVersion - makeMSLVersion(major, minor);
		verStr += ".";
		verStr += to_string(patch);
	}

	return verStr;
}

MVK_PUBLIC_SYMBOL bool MSLVertexAttribute::matches(const MSLVertexAttribute& other) const {
    if (location != other.location) { return false; }
    if (mslBuffer != other.mslBuffer) { return false; }
    if (mslOffset != other.mslOffset) { return false; }
    if (mslStride != other.mslStride) { return false; }
    if (format != other.format) { return false; }
    if (!!isPerInstance != !!other.isPerInstance) { return false; }
    return true;
}

MVK_PUBLIC_SYMBOL bool MSLResourceBinding::matches(const MSLResourceBinding& other) const {
    if (stage != other.stage) { return false; }
    if (descriptorSet != other.descriptorSet) { return false; }
    if (binding != other.binding) { return false; }
    if (mslBuffer != other.mslBuffer) { return false; }
    if (mslTexture != other.mslTexture) { return false; }
    if (mslSampler != other.mslSampler) { return false; }
    return true;
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConverterContext::stageSupportsVertexAttributes() const {
	return (options.entryPointStage == spv::ExecutionModelVertex ||
			options.entryPointStage == spv::ExecutionModelTessellationControl ||
			options.entryPointStage == spv::ExecutionModelTessellationEvaluation);
}

// Check them all in case inactive VA's duplicate locations used by active VA's.
MVK_PUBLIC_SYMBOL bool SPIRVToMSLConverterContext::isVertexAttributeLocationUsed(uint32_t location) const {
    for (auto& va : vertexAttributes) {
        if ((va.location == location) && va.isUsedByShader) { return true; }
    }
    return false;
}

// Check them all in case inactive VA's duplicate buffers used by active VA's.
MVK_PUBLIC_SYMBOL bool SPIRVToMSLConverterContext::isVertexBufferUsed(uint32_t mslBuffer) const {
    for (auto& va : vertexAttributes) {
        if ((va.mslBuffer == mslBuffer) && va.isUsedByShader) { return true; }
    }
    return false;
}

MVK_PUBLIC_SYMBOL void SPIRVToMSLConverterContext::markAllAttributesAndResourcesUsed() {

	if (stageSupportsVertexAttributes()) {
		for (auto& va : vertexAttributes) { va.isUsedByShader = true; }
	}

	for (auto& rb : resourceBindings) { rb.isUsedByShader = true; }
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConverterContext::matches(const SPIRVToMSLConverterContext& other) const {

    if ( !options.matches(other.options) ) { return false; }

	if (stageSupportsVertexAttributes()) {
		for (const auto& va : vertexAttributes) {
			if (va.isUsedByShader && !contains(other.vertexAttributes, va)) { return false; }
		}
	}

    for (const auto& rb : resourceBindings) {
        if (rb.isUsedByShader && !contains(other.resourceBindings, rb)) { return false; }
    }

    return true;
}

MVK_PUBLIC_SYMBOL void SPIRVToMSLConverterContext::alignWith(const SPIRVToMSLConverterContext& srcContext) {

	options.isRasterizationDisabled = srcContext.options.isRasterizationDisabled;
	options.needsAuxBuffer = srcContext.options.needsAuxBuffer;

	if (stageSupportsVertexAttributes()) {
		for (auto& va : vertexAttributes) {
			va.isUsedByShader = false;
			for (auto& srcVA : srcContext.vertexAttributes) {
				if (va.matches(srcVA)) { va.isUsedByShader = srcVA.isUsedByShader; }
			}
		}
	}

    for (auto& rb : resourceBindings) {
        rb.isUsedByShader = false;
        for (auto& srcRB : srcContext.resourceBindings) {
            if (rb.matches(srcRB)) { rb.isUsedByShader = srcRB.isUsedByShader; }
        }
    }
}


#pragma mark -
#pragma mark SPIRVToMSLConverter

// Populates the entry point with info extracted from the SPRI-V compiler.
void populateEntryPoint(SPIRVEntryPoint& entryPoint, spirv_cross::Compiler* pCompiler, SPIRVToMSLConverterOptions& options);

MVK_PUBLIC_SYMBOL void SPIRVToMSLConverter::setSPIRV(const vector<uint32_t>& spirv) { _spirv = spirv; }

MVK_PUBLIC_SYMBOL void SPIRVToMSLConverter::setSPIRV(const uint32_t* spirvCode, size_t length) {
	_spirv.clear();			// Clear for reuse
	_spirv.reserve(length);
	for (size_t i = 0; i < length; i++) {
		_spirv.push_back(spirvCode[i]);
	}
}

MVK_PUBLIC_SYMBOL const vector<uint32_t>& SPIRVToMSLConverter::getSPIRV() { return _spirv; }

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConverter::convert(SPIRVToMSLConverterContext& context,
													bool shouldLogSPIRV,
													bool shouldLogMSL,
                                                    bool shouldLogGLSL) {
	_wasConverted = true;
	_resultLog.clear();
	_msl.clear();

	if (shouldLogSPIRV) { logSPIRV("Converting"); }

	spirv_cross::CompilerMSL* pMSLCompiler = nullptr;

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
	try {
#endif
		pMSLCompiler = new spirv_cross::CompilerMSL(_spirv);

		if (context.options.hasEntryPoint()) {
			pMSLCompiler->set_entry_point(context.options.entryPointName, context.options.entryPointStage);
		}

		// Establish the MSL options for the compiler
		// This needs to be done in two steps...for CompilerMSL and its superclass.
		auto mslOpts = pMSLCompiler->get_msl_options();

#if MVK_MACOS
		mslOpts.platform = spirv_cross::CompilerMSL::Options::macOS;
#endif
#if MVK_IOS
		mslOpts.platform = spirv_cross::CompilerMSL::Options::iOS;
#endif

		mslOpts.msl_version = context.options.mslVersion;
		mslOpts.texel_buffer_texture_width = context.options.texelBufferTextureWidth;
		mslOpts.aux_buffer_index = context.options.auxBufferIndex;
		mslOpts.enable_point_size_builtin = context.options.isRenderingPoints;
		mslOpts.disable_rasterization = context.options.isRasterizationDisabled;
		mslOpts.swizzle_texture_samples = context.options.shouldSwizzleTextureSamples;
		mslOpts.pad_fragment_output_components = true;
		pMSLCompiler->set_msl_options(mslOpts);

		auto scOpts = pMSLCompiler->get_common_options();
		scOpts.vertex.flip_vert_y = context.options.shouldFlipVertexY;
		pMSLCompiler->set_common_options(scOpts);

		// Add vertex attributes
		if (context.stageSupportsVertexAttributes()) {
			spirv_cross::MSLVertexAttr va;
			for (auto& ctxVA : context.vertexAttributes) {
				va.location = ctxVA.location;
				va.msl_buffer = ctxVA.mslBuffer;
				va.msl_offset = ctxVA.mslOffset;
				va.msl_stride = ctxVA.mslStride;
				va.per_instance = ctxVA.isPerInstance;
				switch (ctxVA.format) {
					case MSLVertexFormat::Other:
						va.format = spirv_cross::MSL_VERTEX_FORMAT_OTHER;
						break;
					case MSLVertexFormat::UInt8:
						va.format = spirv_cross::MSL_VERTEX_FORMAT_UINT8;
						break;
					case MSLVertexFormat::UInt16:
						va.format = spirv_cross::MSL_VERTEX_FORMAT_UINT16;
						break;
				}
				pMSLCompiler->add_msl_vertex_attribute(va);
			}
		}

		// Add resource bindings
		spirv_cross::MSLResourceBinding rb;
		for (auto& ctxRB : context.resourceBindings) {
			rb.desc_set = ctxRB.descriptorSet;
			rb.binding = ctxRB.binding;
			rb.stage = ctxRB.stage;
			rb.msl_buffer = ctxRB.mslBuffer;
			rb.msl_texture = ctxRB.mslTexture;
			rb.msl_sampler = ctxRB.mslSampler;
			pMSLCompiler->add_msl_resource_binding(rb);
		}

		_msl = pMSLCompiler->compile();

        if (shouldLogMSL) { logSource(_msl, "MSL", "Converted"); }

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
	} catch (spirv_cross::CompilerError& ex) {
		string errMsg("MSL conversion error: ");
		errMsg += ex.what();
		logError(errMsg.data());
        if (shouldLogMSL && pMSLCompiler) {
            _msl = pMSLCompiler->get_partial_source();
            logSource(_msl, "MSL", "Partially converted");
        }
	}
#endif

    // Populate the shader context with info from the compilation run, including
	// which vertex attributes and resource bindings are used by the shader
	populateEntryPoint(_entryPoint, pMSLCompiler, context.options);
	context.options.isRasterizationDisabled = pMSLCompiler && pMSLCompiler->get_is_rasterization_disabled();
	context.options.needsAuxBuffer = pMSLCompiler && pMSLCompiler->needs_aux_buffer();
	if (context.stageSupportsVertexAttributes()) {
		for (auto& ctxVA : context.vertexAttributes) {
			ctxVA.isUsedByShader = pMSLCompiler->is_msl_vertex_attribute_used(ctxVA.location);
		}
	}
	for (auto& ctxRB : context.resourceBindings) {
		ctxRB.isUsedByShader = pMSLCompiler->is_msl_resource_binding_used(ctxRB.stage, ctxRB.descriptorSet, ctxRB.binding);
	}

	delete pMSLCompiler;

    // To check GLSL conversion
    if (shouldLogGLSL) {
		spirv_cross::CompilerGLSL* pGLSLCompiler = nullptr;

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
		try {
#endif
			pGLSLCompiler = new spirv_cross::CompilerGLSL(_spirv);
			auto options = pGLSLCompiler->get_common_options();
			options.vulkan_semantics = true;
			options.separate_shader_objects = true;
			pGLSLCompiler->set_common_options(options);
			string glsl = pGLSLCompiler->compile();
            logSource(glsl, "GLSL", "Estimated original");
#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
        } catch (spirv_cross::CompilerError& ex) {
            string errMsg("Original GLSL extraction error: ");
            errMsg += ex.what();
            logMsg(errMsg.data());
			if (pGLSLCompiler) {
				string glsl = pGLSLCompiler->get_partial_source();
				logSource(glsl, "GLSL", "Partially converted");
			}
        }
#endif
		delete pGLSLCompiler;
	}

	return _wasConverted;
}

/** Appends the message text to the result log. */
void SPIRVToMSLConverter::logMsg(const char* logMsg) {
	string trimMsg = trim(logMsg);
	if ( !trimMsg.empty() ) {
		_resultLog += trimMsg;
		_resultLog += "\n\n";
	}
}

/** Appends the error text to the result log, sets the wasConverted property to false, and returns it. */
bool SPIRVToMSLConverter::logError(const char* errMsg) {
	logMsg(errMsg);
	_wasConverted = false;
	return _wasConverted;
}

/** Appends the SPIR-V to the result log, indicating whether it is being converted or was converted. */
void SPIRVToMSLConverter::logSPIRV(const char* opDesc) {

	string spvLog;
	mvk::logSPIRV(_spirv, spvLog);

	_resultLog += opDesc;
	_resultLog += " SPIR-V:\n";
	_resultLog += spvLog;
	_resultLog += "\nEnd SPIR-V\n\n";

	// Uncomment one or both of the following lines to get additional debugging and tracability capabilities.
	// The SPIR-V can be written in binary form to a file, and/or logged in human readable form to the console.
	// These can be helpful if errors occur during conversion of SPIR-V to MSL.
//	writeSPIRVToFile("spvout.spv");
//	printf("\n%s\n", getResultLog().c_str());
}

/**
 * Writes the SPIR-V code to a file. This can be useful for debugging
 * when the SPRIR-V did not originally come from a known file
 */
void SPIRVToMSLConverter::writeSPIRVToFile(string spvFilepath) {
	vector<char> fileContents;
	spirvToBytes(_spirv, fileContents);
	string errMsg;
	if (writeFile(spvFilepath, fileContents, errMsg)) {
		_resultLog += "Saved SPIR-V to file: " + absolutePath(spvFilepath) + "\n\n";
	} else {
		_resultLog += "Could not write SPIR-V file. " + errMsg + "\n\n";
	}
}

/** Validates that the SPIR-V code will disassemble during logging. */
bool SPIRVToMSLConverter::validateSPIRV() {
	if (_spirv.size() < 5) { return false; }
	if (_spirv[0] != spv::MagicNumber) { return false; }
	if (_spirv[4] != 0) { return false; }
	return true;
}

/** Appends the source to the result log, prepending with the operation. */
void SPIRVToMSLConverter::logSource(string& src, const char* srcLang, const char* opDesc) {
    _resultLog += opDesc;
    _resultLog += " ";
    _resultLog += srcLang;
    _resultLog += ":\n";
    _resultLog += src;
    _resultLog += "\nEnd ";
    _resultLog += srcLang;
    _resultLog += "\n\n";
}


#pragma mark Support functions

// Populate a workgroup size dimension.
void populateWorkgroupDimension(SPIRVWorkgroupSizeDimension& wgDim, uint32_t size, spirv_cross::SpecializationConstant& spvSpecConst) {
	wgDim.size = max(size, 1u);
	wgDim.isSpecialized = (spvSpecConst.id != 0);
	wgDim.specializationID = spvSpecConst.constant_id;
}

void populateEntryPoint(SPIRVEntryPoint& entryPoint, spirv_cross::Compiler* pCompiler, SPIRVToMSLConverterOptions& options) {

	if ( !pCompiler ) { return; }

	spirv_cross::SPIREntryPoint spvEP;
	if (options.hasEntryPoint()) {
		spvEP = pCompiler->get_entry_point(options.entryPointName, options.entryPointStage);
	} else {
		const auto& entryPoints = pCompiler->get_entry_points_and_stages();
		if ( !entryPoints.empty() ) {
			auto& ep = entryPoints[0];
			spvEP = pCompiler->get_entry_point(ep.name, ep.execution_model);
		}
	}

	spirv_cross::SpecializationConstant widthSC, heightSC, depthSC;
	pCompiler->get_work_group_size_specialization_constants(widthSC, heightSC, depthSC);

	entryPoint.mtlFunctionName = spvEP.name;
	populateWorkgroupDimension(entryPoint.workgroupSize.width, spvEP.workgroup_size.x, widthSC);
	populateWorkgroupDimension(entryPoint.workgroupSize.height, spvEP.workgroup_size.y, heightSC);
	populateWorkgroupDimension(entryPoint.workgroupSize.depth, spvEP.workgroup_size.z, depthSC);
}
