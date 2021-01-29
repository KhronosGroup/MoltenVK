/*
 * SPIRVToMSLConverter.cpp
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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
#include "SPIRVSupport.h"
#include <fstream>

using namespace mvk;
using namespace std;
using namespace spv;
using namespace SPIRV_CROSS_NAMESPACE;


#pragma mark -
#pragma mark SPIRVToMSLConversionConfiguration

// Returns whether the vector contains the value (using a matches(T&) comparison member function). */
template<class T>
bool containsMatching(const vector<T>& vec, const T& val) {
    for (const T& vecVal : vec) { if (vecVal.matches(val)) { return true; } }
    return false;
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionOptions::matches(const SPIRVToMSLConversionOptions& other) const {
	if (entryPointStage != other.entryPointStage) { return false; }
	if (entryPointName != other.entryPointName) { return false; }
	if (tessPatchKind != other.tessPatchKind) { return false; }
	if (numTessControlPoints != other.numTessControlPoints) { return false; }
	if (shouldFlipVertexY != other.shouldFlipVertexY) { return false; }

	if (memcmp(&mslOptions, &other.mslOptions, sizeof(mslOptions)) != 0) { return false; }

	return true;
}

MVK_PUBLIC_SYMBOL std::string SPIRVToMSLConversionOptions::printMSLVersion(uint32_t mslVersion, bool includePatch) {
	string verStr;

	uint32_t major = mslVersion / 10000;
	verStr += to_string(major);

	uint32_t minor = (mslVersion - CompilerMSL::Options::make_msl_version(major)) / 100;
	verStr += ".";
	verStr += to_string(minor);

	if (includePatch) {
		uint32_t patch = mslVersion - CompilerMSL::Options::make_msl_version(major, minor);
		verStr += ".";
		verStr += to_string(patch);
	}

	return verStr;
}

MVK_PUBLIC_SYMBOL SPIRVToMSLConversionOptions::SPIRVToMSLConversionOptions() {
	// Explicitly set mslOptions to defaults over cleared memory to ensure all instances
	// have exactly the same memory layout when using memory comparison in matches().
	memset(&mslOptions, 0, sizeof(mslOptions));
	mslOptions = CompilerMSL::Options();

#if MVK_MACOS
	mslOptions.platform = CompilerMSL::Options::macOS;
#endif
#if MVK_IOS
	mslOptions.platform = CompilerMSL::Options::iOS;
#endif
#if MVK_TVOS
 	mslOptions.platform = CompilerMSL::Options::iOS;
#endif

	mslOptions.pad_fragment_output_components = true;
}

MVK_PUBLIC_SYMBOL bool mvk::MSLShaderInput::matches(const mvk::MSLShaderInput& other) const {
	if (shaderInput.location != other.shaderInput.location) { return false; }
	if (shaderInput.format != other.shaderInput.format) { return false; }
	if (shaderInput.builtin != other.shaderInput.builtin) { return false; }
	if (shaderInput.vecsize != other.shaderInput.vecsize) { return false; }
	if (binding != other.binding) { return false; }
	return true;
}

MVK_PUBLIC_SYMBOL bool mvk::MSLResourceBinding::matches(const MSLResourceBinding& other) const {
	if (resourceBinding.stage != other.resourceBinding.stage) { return false; }
	if (resourceBinding.desc_set != other.resourceBinding.desc_set) { return false; }
	if (resourceBinding.binding != other.resourceBinding.binding) { return false; }
	if (resourceBinding.count != other.resourceBinding.count) { return false; }
	if (resourceBinding.msl_buffer != other.resourceBinding.msl_buffer) { return false; }
	if (resourceBinding.msl_texture != other.resourceBinding.msl_texture) { return false; }
	if (resourceBinding.msl_sampler != other.resourceBinding.msl_sampler) { return false; }

	if (requiresConstExprSampler != other.requiresConstExprSampler) { return false; }

	// If requiresConstExprSampler is false, constExprSampler can be ignored
	if (requiresConstExprSampler) {
		if (constExprSampler.coord != other.constExprSampler.coord) { return false; }
		if (constExprSampler.min_filter != other.constExprSampler.min_filter) { return false; }
		if (constExprSampler.mag_filter != other.constExprSampler.mag_filter) { return false; }
		if (constExprSampler.mip_filter != other.constExprSampler.mip_filter) { return false; }
		if (constExprSampler.s_address != other.constExprSampler.s_address) { return false; }
		if (constExprSampler.t_address != other.constExprSampler.t_address) { return false; }
		if (constExprSampler.r_address != other.constExprSampler.r_address) { return false; }
		if (constExprSampler.compare_func != other.constExprSampler.compare_func) { return false; }
		if (constExprSampler.border_color != other.constExprSampler.border_color) { return false; }
		if (constExprSampler.lod_clamp_min != other.constExprSampler.lod_clamp_min) { return false; }
		if (constExprSampler.lod_clamp_max != other.constExprSampler.lod_clamp_max) { return false; }
		if (constExprSampler.max_anisotropy != other.constExprSampler.max_anisotropy) { return false; }

		if (constExprSampler.planes != other.constExprSampler.planes) { return false; }
		if (constExprSampler.resolution != other.constExprSampler.resolution) { return false; }
		if (constExprSampler.chroma_filter != other.constExprSampler.chroma_filter) { return false; }
		if (constExprSampler.x_chroma_offset != other.constExprSampler.x_chroma_offset) { return false; }
		if (constExprSampler.y_chroma_offset != other.constExprSampler.y_chroma_offset) { return false; }
		for(uint32_t i = 0; i < 4; ++i)
			if (constExprSampler.swizzle[i] != other.constExprSampler.swizzle[i]) { return false; }
		if (constExprSampler.ycbcr_model != other.constExprSampler.ycbcr_model) { return false; }
		if (constExprSampler.ycbcr_range != other.constExprSampler.ycbcr_range) { return false; }
		if (constExprSampler.bpc != other.constExprSampler.bpc) { return false; }

		if (constExprSampler.compare_enable != other.constExprSampler.compare_enable) { return false; }
		if (constExprSampler.lod_clamp_enable != other.constExprSampler.lod_clamp_enable) { return false; }
		if (constExprSampler.anisotropy_enable != other.constExprSampler.anisotropy_enable) { return false; }
		if (constExprSampler.ycbcr_conversion_enable != other.constExprSampler.ycbcr_conversion_enable) { return false; }
	}

	return true;
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionConfiguration::stageSupportsVertexAttributes() const {
	return (options.entryPointStage == ExecutionModelVertex ||
			options.entryPointStage == ExecutionModelTessellationControl ||
			options.entryPointStage == ExecutionModelTessellationEvaluation);
}

// Check them all in case inactive VA's duplicate locations used by active VA's.
MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionConfiguration::isShaderInputLocationUsed(uint32_t location) const {
    for (auto& si : shaderInputs) {
        if ((si.shaderInput.location == location) && si.isUsedByShader) { return true; }
    }
    return false;
}

MVK_PUBLIC_SYMBOL uint32_t SPIRVToMSLConversionConfiguration::countShaderInputsAt(uint32_t binding) const {
	uint32_t siCnt = 0;
	for (auto& si : shaderInputs) {
		if ((si.binding == binding) && si.isUsedByShader) { siCnt++; }
	}
	return siCnt;
}

MVK_PUBLIC_SYMBOL void SPIRVToMSLConversionConfiguration::markAllInputsAndResourcesUsed() {
	for (auto& si : shaderInputs) { si.isUsedByShader = true; }
	for (auto& rb : resourceBindings) { rb.isUsedByShader = true; }
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionConfiguration::matches(const SPIRVToMSLConversionConfiguration& other) const {

    if ( !options.matches(other.options) ) { return false; }

	for (const auto& si : shaderInputs) {
		if (si.isUsedByShader && !containsMatching(other.shaderInputs, si)) { return false; }
	}

    for (const auto& rb : resourceBindings) {
        if (rb.isUsedByShader && !containsMatching(other.resourceBindings, rb)) { return false; }
    }

    return true;
}


MVK_PUBLIC_SYMBOL void SPIRVToMSLConversionConfiguration::alignWith(const SPIRVToMSLConversionConfiguration& srcContext) {

	for (auto& si : shaderInputs) {
		si.isUsedByShader = false;
		for (auto& srcSI : srcContext.shaderInputs) {
			if (si.matches(srcSI)) { si.isUsedByShader = srcSI.isUsedByShader; }
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

MVK_PUBLIC_SYMBOL void SPIRVToMSLConverter::setSPIRV(const uint32_t* spirvCode, size_t length) {
	_spirv.clear();			// Clear for reuse
	_spirv.reserve(length);
	for (size_t i = 0; i < length; i++) {
		_spirv.push_back(spirvCode[i]);
	}
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConverter::convert(SPIRVToMSLConversionConfiguration& context,
													bool shouldLogSPIRV,
													bool shouldLogMSL,
                                                    bool shouldLogGLSL) {

	// Uncomment to write SPIR-V to file as a debugging aid
//	ofstream spvFile("spirv.spv", ios::binary);
//	spvFile.write((char*)_spirv.data(), _spirv.size() << 2);
//	spvFile.close();

	_wasConverted = true;
	_resultLog.clear();
	_msl.clear();
	_shaderConversionResults.reset();

	if (shouldLogSPIRV) { logSPIRV("Converting"); }

	CompilerMSL* pMSLCompiler = nullptr;

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
	try {
#endif
		pMSLCompiler = new CompilerMSL(_spirv);

		if (context.options.hasEntryPoint()) {
			pMSLCompiler->set_entry_point(context.options.entryPointName, context.options.entryPointStage);
		}

		// Set up tessellation parameters if needed.
		if (context.options.entryPointStage == ExecutionModelTessellationControl ||
			context.options.entryPointStage == ExecutionModelTessellationEvaluation) {
			if (context.options.tessPatchKind != ExecutionModeMax) {
				pMSLCompiler->set_execution_mode(context.options.tessPatchKind);
			}
			if (context.options.numTessControlPoints != 0) {
				pMSLCompiler->set_execution_mode(ExecutionModeOutputVertices, context.options.numTessControlPoints);
			}
		}

		// Establish the MSL options for the compiler
		// This needs to be done in two steps...for CompilerMSL and its superclass.
		pMSLCompiler->set_msl_options(context.options.mslOptions);

		auto scOpts = pMSLCompiler->get_common_options();
		scOpts.vertex.flip_vert_y = context.options.shouldFlipVertexY;
		pMSLCompiler->set_common_options(scOpts);

		// Add shader inputs
		for (auto& si : context.shaderInputs) {
			pMSLCompiler->add_msl_shader_input(si.shaderInput);
		}

		// Add resource bindings and hardcoded constexpr samplers
		for (auto& rb : context.resourceBindings) {
			auto& rbb = rb.resourceBinding;
			pMSLCompiler->add_msl_resource_binding(rbb);

			if (rb.requiresConstExprSampler) {
				pMSLCompiler->remap_constexpr_sampler_by_binding(rbb.desc_set, rbb.binding, rb.constExprSampler);
			}
		}

		_msl = pMSLCompiler->compile();

        if (shouldLogMSL) { logSource(_msl, "MSL", "Converted"); }

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
	} catch (CompilerError& ex) {
		string errMsg("MSL conversion error: ");
		errMsg += ex.what();
		logError(errMsg.data());
        if (shouldLogMSL && pMSLCompiler) {
            _msl = pMSLCompiler->get_partial_source();
            logSource(_msl, "MSL", "Partially converted");
        }
	}
#endif

	// Populate the shader conversion results with info from the compilation run,
	// and mark which vertex attributes and resource bindings are used by the shader
	populateEntryPoint(pMSLCompiler, context.options);
	_shaderConversionResults.isRasterizationDisabled = pMSLCompiler && pMSLCompiler->get_is_rasterization_disabled();
	_shaderConversionResults.isPositionInvariant = pMSLCompiler && pMSLCompiler->is_position_invariant();
	_shaderConversionResults.needsSwizzleBuffer = pMSLCompiler && pMSLCompiler->needs_swizzle_buffer();
	_shaderConversionResults.needsOutputBuffer = pMSLCompiler && pMSLCompiler->needs_output_buffer();
	_shaderConversionResults.needsPatchOutputBuffer = pMSLCompiler && pMSLCompiler->needs_patch_output_buffer();
	_shaderConversionResults.needsBufferSizeBuffer = pMSLCompiler && pMSLCompiler->needs_buffer_size_buffer();
	_shaderConversionResults.needsInputThreadgroupMem = pMSLCompiler && pMSLCompiler->needs_input_threadgroup_mem();
	_shaderConversionResults.needsDispatchBaseBuffer = pMSLCompiler && pMSLCompiler->needs_dispatch_base_buffer();
	_shaderConversionResults.needsViewRangeBuffer = pMSLCompiler && pMSLCompiler->needs_view_mask_buffer();

	for (auto& ctxSI : context.shaderInputs) {
		ctxSI.isUsedByShader = pMSLCompiler->is_msl_shader_input_used(ctxSI.shaderInput.location);
	}
	for (auto& ctxRB : context.resourceBindings) {
		ctxRB.isUsedByShader = pMSLCompiler->is_msl_resource_binding_used(ctxRB.resourceBinding.stage,
																		  ctxRB.resourceBinding.desc_set,
																		  ctxRB.resourceBinding.binding);
	}

	delete pMSLCompiler;

    // To check GLSL conversion
    if (shouldLogGLSL) {
		CompilerGLSL* pGLSLCompiler = nullptr;

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
		try {
#endif
			pGLSLCompiler = new CompilerGLSL(_spirv);
			auto options = pGLSLCompiler->get_common_options();
			options.vulkan_semantics = true;
			options.separate_shader_objects = true;
			pGLSLCompiler->set_common_options(options);
			string glsl = pGLSLCompiler->compile();
            logSource(glsl, "GLSL", "Estimated original");
#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
        } catch (CompilerError& ex) {
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

// Appends the message text to the result log.
void SPIRVToMSLConverter::logMsg(const char* logMsg) {
	string trimMsg = trim(logMsg);
	if ( !trimMsg.empty() ) {
		_resultLog += trimMsg;
		_resultLog += "\n\n";
	}
}

// Appends the error text to the result log, sets the wasConverted property to false, and returns it.
bool SPIRVToMSLConverter::logError(const char* errMsg) {
	logMsg(errMsg);
	_wasConverted = false;
	return _wasConverted;
}

// Appends the SPIR-V to the result log, indicating whether it is being converted or was converted.
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

// Writes the SPIR-V code to a file. This can be useful for debugging
// when the SPRIR-V did not originally come from a known file
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

// Validates that the SPIR-V code will disassemble during logging.
bool SPIRVToMSLConverter::validateSPIRV() {
	if (_spirv.size() < 5) { return false; }
	if (_spirv[0] != MagicNumber) { return false; }
	if (_spirv[4] != 0) { return false; }
	return true;
}

// Appends the source to the result log, prepending with the operation.
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

void SPIRVToMSLConverter::populateWorkgroupDimension(SPIRVWorkgroupSizeDimension& wgDim,
													 uint32_t size,
													 SpecializationConstant& spvSpecConst) {
	wgDim.size = max(size, 1u);
	wgDim.isSpecialized = (uint32_t(spvSpecConst.id) != 0);
	wgDim.specializationID = spvSpecConst.constant_id;
}

// Populates the entry point with info extracted from the SPRI-V compiler.
void SPIRVToMSLConverter::populateEntryPoint(Compiler* pCompiler,
											 SPIRVToMSLConversionOptions& options) {

	if ( !pCompiler ) { return; }

	SPIREntryPoint spvEP;
	if (options.hasEntryPoint()) {
		spvEP = pCompiler->get_entry_point(options.entryPointName, options.entryPointStage);
	} else {
		const auto& entryPoints = pCompiler->get_entry_points_and_stages();
		if ( !entryPoints.empty() ) {
			auto& ep = entryPoints[0];
			spvEP = pCompiler->get_entry_point(ep.name, ep.execution_model);
		}
	}

	auto& ep = _shaderConversionResults.entryPoint;
	ep.mtlFunctionName = spvEP.name;
	ep.supportsFastMath = !spvEP.flags.get(ExecutionModeSignedZeroInfNanPreserve);

	SpecializationConstant widthSC, heightSC, depthSC;
	pCompiler->get_work_group_size_specialization_constants(widthSC, heightSC, depthSC);

	auto& wgSize = ep.workgroupSize;
	populateWorkgroupDimension(wgSize.width, spvEP.workgroup_size.x, widthSC);
	populateWorkgroupDimension(wgSize.height, spvEP.workgroup_size.y, heightSC);
	populateWorkgroupDimension(wgSize.depth, spvEP.workgroup_size.z, depthSC);
}
