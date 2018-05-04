/*
 * SPIRVToMSLConverter.cpp
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

#include "SPIRVToMSLConverter.h"
#include "MVKCommonEnvironment.h"
#include "MVKStrings.h"
#include "FileSupport.h"
#include "spirv_msl.hpp"
#include <spirv-tools/libspirv.h>
#import <CoreFoundation/CFByteOrder.h>

using namespace mvk;
using namespace std;


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
    if (!!shouldFlipVertexY != !!other.shouldFlipVertexY) { return false; }
    if (!!isRenderingPoints != !!other.isRenderingPoints) { return false; }
	if (entryPointName != other.entryPointName) { return false; }
    return true;
}

MVK_PUBLIC_SYMBOL bool MSLVertexAttribute::matches(const MSLVertexAttribute& other) const {
    if (location != other.location) { return false; }
    if (mslBuffer != other.mslBuffer) { return false; }
    if (mslOffset != other.mslOffset) { return false; }
    if (mslStride != other.mslStride) { return false; }
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

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConverterContext::matches(const SPIRVToMSLConverterContext& other) const {

    if ( !options.matches(other.options) ) { return false; }

    for (const auto& va : vertexAttributes) {
        if (va.isUsedByShader && !contains(other.vertexAttributes, va)) { return false; }
    }

    for (const auto& rb : resourceBindings) {
        if (rb.isUsedByShader && !contains(other.resourceBindings, rb)) { return false; }
    }
    
    return true;
}

// Aligns the usage of the destination context to that of the source context.
MVK_PUBLIC_SYMBOL void SPIRVToMSLConverterContext::alignUsageWith(const SPIRVToMSLConverterContext& srcContext) {

    for (auto& va : vertexAttributes) {
        va.isUsedByShader = false;
        for (auto& srcVA : srcContext.vertexAttributes) {
            if (va.matches(srcVA)) { va.isUsedByShader = srcVA.isUsedByShader; }
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

/** Populates content extracted from the SPRI-V compiler. */
void populateFromCompiler(spirv_cross::Compiler* pCompiler, SPIRVEntryPoint& entryPoint, SPIRVToMSLConverterOptions& options);

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

	// Add vertex attributes
	vector<spirv_cross::MSLVertexAttr> vtxAttrs;
	spirv_cross::MSLVertexAttr va;
	for (auto& ctxVA : context.vertexAttributes) {
		va.location = ctxVA.location;
        va.msl_buffer = ctxVA.mslBuffer;
        va.msl_offset = ctxVA.mslOffset;
        va.msl_stride = ctxVA.mslStride;
        va.per_instance = ctxVA.isPerInstance;
        va.used_by_shader = ctxVA.isUsedByShader;
		vtxAttrs.push_back(va);
	}

	// Add resource bindings
	vector<spirv_cross::MSLResourceBinding> resBindings;
	spirv_cross::MSLResourceBinding rb;
	for (auto& ctxRB : context.resourceBindings) {
		rb.desc_set = ctxRB.descriptorSet;
		rb.binding = ctxRB.binding;
		rb.stage = ctxRB.stage;
		rb.msl_buffer = ctxRB.mslBuffer;
		rb.msl_texture = ctxRB.mslTexture;
		rb.msl_sampler = ctxRB.mslSampler;
        rb.used_by_shader = ctxRB.isUsedByShader;
		resBindings.push_back(rb);
	}


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
		mslOpts.enable_point_size_builtin = context.options.isRenderingPoints;
		mslOpts.resolve_specialized_array_lengths = true;
		pMSLCompiler->set_msl_options(mslOpts);

		auto scOpts = pMSLCompiler->get_common_options();
		scOpts.vertex.flip_vert_y = context.options.shouldFlipVertexY;
		pMSLCompiler->set_common_options(scOpts);

		_msl = pMSLCompiler->compile(&vtxAttrs, &resBindings);
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

    // Populate content extracted from the SPRI-V compiler.
	populateFromCompiler(pMSLCompiler, _entryPoint, context.options);

    // To check GLSL conversion
    if (shouldLogGLSL) {
		spirv_cross::CompilerGLSL* pGLSLCompiler = nullptr;

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
		try {
#endif
			pGLSLCompiler = new spirv_cross::CompilerGLSL(_spirv);
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
    }

	// Copy whether the vertex attributes and resource bindings are used by the shader
	uint32_t vaCnt = (uint32_t)vtxAttrs.size();
	for (uint32_t vaIdx = 0; vaIdx < vaCnt; vaIdx++) {
		context.vertexAttributes[vaIdx].isUsedByShader = vtxAttrs[vaIdx].used_by_shader;
	}
	uint32_t rbCnt = (uint32_t)resBindings.size();
	for (uint32_t rbIdx = 0; rbIdx < rbCnt; rbIdx++) {
		context.resourceBindings[rbIdx].isUsedByShader = resBindings[rbIdx].used_by_shader;
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

void populateFromCompiler(spirv_cross::Compiler* pCompiler, SPIRVEntryPoint& entryPoint, SPIRVToMSLConverterOptions& options) {

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

	uint32_t minDim = 1;
	auto& wgSize = spvEP.workgroup_size;

	entryPoint.mtlFunctionName = spvEP.name;
	entryPoint.workgroupSize.width = max(wgSize.x, minDim);
	entryPoint.workgroupSize.height = max(wgSize.y, minDim);
	entryPoint.workgroupSize.depth = max(wgSize.z, minDim);

	spirv_cross::SpecializationConstant width, height, depth;
	entryPoint.workgroupSizeId.constant = pCompiler->get_work_group_size_specialization_constants(width, height, depth);
	entryPoint.workgroupSizeId.width = width.constant_id;
	entryPoint.workgroupSizeId.height = height.constant_id;
	entryPoint.workgroupSizeId.depth = depth.constant_id;
}

MVK_PUBLIC_SYMBOL void mvk::logSPIRV(vector<uint32_t>& spirv, string& spvLog) {
	if ( !((spirv.size() > 4) &&
		   (spirv[0] == spv::MagicNumber) &&
		   (spirv[4] == 0)) ) { return; }

	uint32_t options = (SPV_BINARY_TO_TEXT_OPTION_INDENT);
	spv_text text;
	spv_diagnostic diagnostic = nullptr;
	spv_context context = spvContextCreate(SPV_ENV_VULKAN_1_0);
	spv_result_t error = spvBinaryToText(context, spirv.data(), spirv.size(), options, &text, &diagnostic);
	spvContextDestroy(context);
	if (error) {
		spvDiagnosticPrint(diagnostic);
		spvDiagnosticDestroy(diagnostic);
		return;
	}
	spvLog.append(text->str, text->length);
	spvTextDestroy(text);
}

MVK_PUBLIC_SYMBOL void mvk::spirvToBytes(const vector<uint32_t>& spv, vector<char>& bytes) {
	// Assumes desired endianness.
	size_t byteCnt = spv.size() * sizeof(uint32_t);
	char* cBytes = (char*)spv.data();
	bytes.clear();
	bytes.insert(bytes.end(), cBytes, cBytes + byteCnt);
}

MVK_PUBLIC_SYMBOL void mvk::bytesToSPIRV(const vector<char>& bytes, vector<uint32_t>& spv) {
	size_t spvCnt = bytes.size() / sizeof(uint32_t);
	uint32_t* cSPV = (uint32_t*)bytes.data();
	spv.clear();
	spv.insert(spv.end(), cSPV, cSPV + spvCnt);
	ensureSPIRVEndianness(spv);
}

MVK_PUBLIC_SYMBOL bool mvk::ensureSPIRVEndianness(vector<uint32_t>& spv) {
	if (spv.empty()) { return false; }					// Nothing to convert

	uint32_t magNum = spv.front();
	if (magNum == spv::MagicNumber) { return false; }	// No need to convert

	if (CFSwapInt32(magNum) == spv::MagicNumber) {		// Yep, it's SPIR-V, but wrong endianness
		for (auto& elem : spv) { elem = CFSwapInt32(elem); }
		return true;
	}
	return false;		// Not SPIR-V, so don't convert
}


