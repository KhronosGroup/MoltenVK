/*
 * SPIRVToMSLConverter.cpp
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

// Returns whether the container contains an item equal to the value.
template<class C, class T>
bool contains(const C& container, const T& val) {
	for (const T& cVal : container) { if (cVal == val) { return true; } }
	return false;
}

// Returns whether the vector contains the value (using a matches(T&) comparison member function). */
template<class T>
bool containsMatching(const vector<T>& vec, const T& val) {
    for (const T& vecVal : vec) { if (vecVal.matches(val)) { return true; } }
    return false;
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionOptions::matches(const SPIRVToMSLConversionOptions& other) const {
	if (memcmp(&mslOptions, &other.mslOptions, sizeof(mslOptions)) != 0) { return false; }
	if (entryPointStage != other.entryPointStage) { return false; }
	if (entryPointName != other.entryPointName) { return false; }
	if (tessPatchKind != other.tessPatchKind) { return false; }
	if (numTessControlPoints != other.numTessControlPoints) { return false; }
	if (shouldFlipVertexY != other.shouldFlipVertexY) { return false; }
	if (shouldFixupClipSpace != other.shouldFixupClipSpace) { return false; }
	return true;
}

MVK_PUBLIC_SYMBOL string SPIRVToMSLConversionOptions::printMSLVersion(uint32_t mslVersion, bool includePatch) {
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

MVK_PUBLIC_SYMBOL bool mvk::MSLShaderInterfaceVariable::matches(const mvk::MSLShaderInterfaceVariable& other) const {
	if (memcmp(&shaderVar, &other.shaderVar, sizeof(shaderVar)) != 0) { return false; }
	if (binding != other.binding) { return false; }
	return true;
}

MVK_PUBLIC_SYMBOL mvk::MSLShaderInterfaceVariable::MSLShaderInterfaceVariable() {
	// Explicitly set shaderVar to defaults over cleared memory to ensure all instances
	// have exactly the same memory layout when using memory comparison in matches().
	memset(&shaderVar, 0, sizeof(shaderVar));
	shaderVar = SPIRV_CROSS_NAMESPACE::MSLShaderInterfaceVariable();
}

// If requiresConstExprSampler is false, constExprSampler can be ignored
MVK_PUBLIC_SYMBOL bool mvk::MSLResourceBinding::matches(const MSLResourceBinding& other) const {
	if (memcmp(&resourceBinding, &other.resourceBinding, sizeof(resourceBinding)) != 0) { return false; }
	if (requiresConstExprSampler != other.requiresConstExprSampler) { return false; }
	if (requiresConstExprSampler) {
		if (memcmp(&constExprSampler, &other.constExprSampler, sizeof(constExprSampler)) != 0) { return false; }
	}
	return true;
}

MVK_PUBLIC_SYMBOL mvk::MSLResourceBinding::MSLResourceBinding() {
	// Explicitly set resourceBinding and constExprSampler to defaults over cleared memory to ensure
	// all instances have exactly the same memory layout when using memory comparison in matches().
	memset(&resourceBinding, 0, sizeof(resourceBinding));
	resourceBinding = SPIRV_CROSS_NAMESPACE::MSLResourceBinding();
	memset(&constExprSampler, 0, sizeof(constExprSampler));
	constExprSampler = SPIRV_CROSS_NAMESPACE::MSLConstexprSampler();
}

MVK_PUBLIC_SYMBOL bool mvk::DescriptorBinding::matches(const mvk::DescriptorBinding& other) const {
	if (stage != other.stage) { return false; }
	if (descriptorSet != other.descriptorSet) { return false; }
	if (binding != other.binding) { return false; }
	if (index != other.index) { return false; }
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
        if ((si.shaderVar.location == location) && si.outIsUsedByShader) { return true; }
    }
    return false;
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionConfiguration::isShaderInputBuiltInUsed(spv::BuiltIn builtin) const {
    for (auto& si : shaderInputs) {
        if ((si.shaderVar.builtin == builtin) && si.outIsUsedByShader) { return true; }
    }
    return false;
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionConfiguration::isShaderOutputLocationUsed(uint32_t location) const {
    for (auto& so : shaderOutputs) {
        if ((so.shaderVar.location == location) && so.outIsUsedByShader) { return true; }
    }
    return false;
}

MVK_PUBLIC_SYMBOL uint32_t SPIRVToMSLConversionConfiguration::countShaderInputsAt(uint32_t binding) const {
	uint32_t siCnt = 0;
	for (auto& si : shaderInputs) {
		if ((si.binding == binding) && si.outIsUsedByShader) { siCnt++; }
	}
	return siCnt;
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionConfiguration::isResourceUsed(ExecutionModel stage, uint32_t descSet, uint32_t binding) const {
	for (auto& rb : resourceBindings) {
		auto& rbb = rb.resourceBinding;
		if (rbb.stage == stage && rbb.desc_set == descSet && rbb.binding == binding) {
			return rb.outIsUsedByShader;
		}
	}
	return false;
}

MVK_PUBLIC_SYMBOL void SPIRVToMSLConversionConfiguration::markAllInterfaceVarsAndResourcesUsed() {
	for (auto& si : shaderInputs) { si.outIsUsedByShader = true; }
	for (auto& so : shaderOutputs) { so.outIsUsedByShader = true; }
	for (auto& rb : resourceBindings) { rb.outIsUsedByShader = true; }
}

// A single SPIRVToMSLConversionConfiguration instance is used for all pipeline shader stages,
// and the resources can be spread across these shader stages. To improve cache hits when using
// this function to find a cached shader for a particular shader stage, only consider the resources
// that are used in that shader stage. By contrast, discreteDescriptorSet apply across all stages,
// and shaderInputs and shaderOutputs are populated before each stage, so neither needs to be filtered by stage here.
MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionConfiguration::matches(const SPIRVToMSLConversionConfiguration& other) const {

    if ( !options.matches(other.options) ) { return false; }

	for (const auto& si : shaderInputs) {
		if (si.outIsUsedByShader && !containsMatching(other.shaderInputs, si)) { return false; }
	}

	for (const auto& so : shaderOutputs) {
		if (so.outIsUsedByShader && !containsMatching(other.shaderOutputs, so)) { return false; }
	}

    for (const auto& rb : resourceBindings) {
        if (rb.resourceBinding.stage == options.entryPointStage &&
			rb.outIsUsedByShader &&
			!containsMatching(other.resourceBindings, rb)) { return false; }
    }

	for (const auto& db : dynamicBufferDescriptors) {
		if (db.stage == options.entryPointStage &&
			!containsMatching(other.dynamicBufferDescriptors, db)) { return false; }
	}

	for (uint32_t dsIdx : discreteDescriptorSets) {
		if ( !contains(other.discreteDescriptorSets, dsIdx)) { return false; }
	}

    return true;
}


MVK_PUBLIC_SYMBOL void SPIRVToMSLConversionConfiguration::alignWith(const SPIRVToMSLConversionConfiguration& srcContext) {

	for (auto& si : shaderInputs) {
		si.outIsUsedByShader = false;
		for (auto& srcSI : srcContext.shaderInputs) {
			if (si.matches(srcSI)) { si.outIsUsedByShader = srcSI.outIsUsedByShader; }
		}
	}

	for (auto& so : shaderOutputs) {
		so.outIsUsedByShader = false;
		for (auto& srcSO : srcContext.shaderOutputs) {
			if (so.matches(srcSO)) { so.outIsUsedByShader = srcSO.outIsUsedByShader; }
		}
	}

    for (auto& rb : resourceBindings) {
        rb.outIsUsedByShader = false;
        for (auto& srcRB : srcContext.resourceBindings) {
			if (rb.matches(srcRB)) {
				rb.outIsUsedByShader = srcRB.outIsUsedByShader;
			}
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

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConverter::convert(SPIRVToMSLConversionConfiguration& shaderConfig,
													SPIRVToMSLConversionResult& conversionResult,
													bool shouldLogSPIRV,
													bool shouldLogMSL,
                                                    bool shouldLogGLSL) {

	// Uncomment to write SPIR-V to file as a debugging aid
//	ofstream spvFile("spirv.spv", ios::binary);
//	spvFile.write((char*)_spirv.data(), _spirv.size() << 2);
//	spvFile.close();

	if (shouldLogSPIRV) { logSPIRV(conversionResult.resultLog, "Converting"); }

	CompilerMSL* pMSLCompiler = nullptr;
	bool wasConverted = true;

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
	try {
#endif
		pMSLCompiler = new CompilerMSL(_spirv);

		if (shaderConfig.options.hasEntryPoint()) {
			pMSLCompiler->set_entry_point(shaderConfig.options.entryPointName, shaderConfig.options.entryPointStage);
		}

		// Set up tessellation parameters if needed.
		if (shaderConfig.options.entryPointStage == ExecutionModelTessellationControl ||
			shaderConfig.options.entryPointStage == ExecutionModelTessellationEvaluation) {
			if (shaderConfig.options.tessPatchKind != ExecutionModeMax) {
				pMSLCompiler->set_execution_mode(shaderConfig.options.tessPatchKind);
			}
			if (shaderConfig.options.numTessControlPoints != 0) {
				pMSLCompiler->set_execution_mode(ExecutionModeOutputVertices, shaderConfig.options.numTessControlPoints);
			}
		}

		// Establish the MSL options for the compiler
		// This needs to be done in two steps...for CompilerMSL and its superclass.
		pMSLCompiler->set_msl_options(shaderConfig.options.mslOptions);

		auto scOpts = pMSLCompiler->get_common_options();
		scOpts.vertex.flip_vert_y = shaderConfig.options.shouldFlipVertexY;
		scOpts.vertex.fixup_clipspace = shaderConfig.options.shouldFixupClipSpace;
		pMSLCompiler->set_common_options(scOpts);

		// Add shader inputs and outputs
		for (auto& si : shaderConfig.shaderInputs) {
			pMSLCompiler->add_msl_shader_input(si.shaderVar);
		}

		for (auto& so : shaderConfig.shaderOutputs) {
			pMSLCompiler->add_msl_shader_output(so.shaderVar);
		}

		// Add resource bindings and hardcoded constexpr samplers
		for (auto& rb : shaderConfig.resourceBindings) {
			auto& rbb = rb.resourceBinding;
			if (rbb.stage == shaderConfig.options.entryPointStage) {
				pMSLCompiler->add_msl_resource_binding(rbb);
				if (rb.requiresConstExprSampler) {
					pMSLCompiler->remap_constexpr_sampler_by_binding(rbb.desc_set, rbb.binding, rb.constExprSampler);
				}
			}
		}

		// Add any descriptor sets that are not using Metal argument buffers.
		// This only has an effect if SPIRVToMSLConversionConfiguration::options::mslOptions::argument_buffers is enabled.
		for (uint32_t dsIdx : shaderConfig.discreteDescriptorSets) {
			pMSLCompiler->add_discrete_descriptor_set(dsIdx);
		}

		// Add any dynamic buffer bindings.
		// This only has an applies if SPIRVToMSLConversionConfiguration::options::mslOptions::argument_buffers is enabled.
		if (shaderConfig.options.mslOptions.argument_buffers) {
			for (auto& db : shaderConfig.dynamicBufferDescriptors) {
				if (db.stage == shaderConfig.options.entryPointStage) {
					pMSLCompiler->add_dynamic_buffer(db.descriptorSet, db.binding, db.index);
				}
			}
		}
		conversionResult.msl = pMSLCompiler->compile();

        if (shouldLogMSL) { logSource(conversionResult.resultLog, conversionResult.msl, "MSL", "Converted"); }

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
	} catch (CompilerError& ex) {
		string errMsg("SPIR-V to MSL conversion error: ");
		errMsg += ex.what();
		logError(conversionResult.resultLog, errMsg.data());
        if (shouldLogMSL && pMSLCompiler) {
			auto partialMSL = pMSLCompiler->get_partial_source();
            logSource(conversionResult.resultLog, partialMSL, "MSL", "Partially converted");
        }
	}
#endif

	// Populate the shader conversion results with info from the compilation run,
	// and mark which vertex attributes and resource bindings are used by the shader
	populateEntryPoint(pMSLCompiler, shaderConfig.options, conversionResult.resultInfo.entryPoint);
	conversionResult.resultInfo.isRasterizationDisabled = pMSLCompiler && pMSLCompiler->get_is_rasterization_disabled();
	conversionResult.resultInfo.isPositionInvariant = pMSLCompiler && pMSLCompiler->is_position_invariant();
	conversionResult.resultInfo.needsSwizzleBuffer = pMSLCompiler && pMSLCompiler->needs_swizzle_buffer();
	conversionResult.resultInfo.needsOutputBuffer = pMSLCompiler && pMSLCompiler->needs_output_buffer();
	conversionResult.resultInfo.needsPatchOutputBuffer = pMSLCompiler && pMSLCompiler->needs_patch_output_buffer();
	conversionResult.resultInfo.needsBufferSizeBuffer = pMSLCompiler && pMSLCompiler->needs_buffer_size_buffer();
	conversionResult.resultInfo.needsInputThreadgroupMem = pMSLCompiler && pMSLCompiler->needs_input_threadgroup_mem();
	conversionResult.resultInfo.needsDispatchBaseBuffer = pMSLCompiler && pMSLCompiler->needs_dispatch_base_buffer();
	conversionResult.resultInfo.needsViewRangeBuffer = pMSLCompiler && pMSLCompiler->needs_view_mask_buffer();
	conversionResult.resultInfo.usesPhysicalStorageBufferAddressesCapability = usesPhysicalStorageBufferAddressesCapability(pMSLCompiler);
	populateSpecializationMacros(pMSLCompiler, conversionResult.resultInfo.specializationMacros);

	// When using Metal argument buffers, if the shader is provided with dynamic buffer offsets,
	// then it needs a buffer to hold these dynamic offsets.
	conversionResult.resultInfo.needsDynamicOffsetBuffer = false;
	if (shaderConfig.options.mslOptions.argument_buffers) {
		for (auto& db : shaderConfig.dynamicBufferDescriptors) {
			if (db.stage == shaderConfig.options.entryPointStage) {
				conversionResult.resultInfo.needsDynamicOffsetBuffer = true;
			}
		}
	}

	for (auto& ctxSI : shaderConfig.shaderInputs) {
		if (ctxSI.shaderVar.builtin != spv::BuiltInMax) {
			ctxSI.outIsUsedByShader = pMSLCompiler->has_active_builtin(ctxSI.shaderVar.builtin, spv::StorageClassInput);
		} else {
			ctxSI.outIsUsedByShader = pMSLCompiler->is_msl_shader_input_used(ctxSI.shaderVar.location);
		}
	}
	for (auto& ctxSO : shaderConfig.shaderOutputs) {
		if (ctxSO.shaderVar.builtin != spv::BuiltInMax) {
			ctxSO.outIsUsedByShader = pMSLCompiler->has_active_builtin(ctxSO.shaderVar.builtin, spv::StorageClassOutput);
		} else {
			ctxSO.outIsUsedByShader = pMSLCompiler->is_msl_shader_output_used(ctxSO.shaderVar.location);
		}
	}
	for (auto& ctxRB : shaderConfig.resourceBindings) {
		if (ctxRB.resourceBinding.stage == shaderConfig.options.entryPointStage) {
			ctxRB.outIsUsedByShader = pMSLCompiler->is_msl_resource_binding_used(ctxRB.resourceBinding.stage,
																				 ctxRB.resourceBinding.desc_set,
																				 ctxRB.resourceBinding.binding);
		}
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
            logSource(conversionResult.resultLog, glsl, "GLSL", "Estimated original");
#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
        } catch (CompilerError& ex) {
            string errMsg("Original GLSL extraction error: ");
            errMsg += ex.what();
            logMsg(conversionResult.resultLog, errMsg.data());
			if (pGLSLCompiler) {
				string glsl = pGLSLCompiler->get_partial_source();
				logSource(conversionResult.resultLog, glsl, "GLSL", "Partially converted");
			}
        }
#endif
		delete pGLSLCompiler;
	}

	return wasConverted;
}

// Appends the message text to the result log.
void SPIRVToMSLConverter::logMsg(string& log, const char* logMsg) {
	string trimMsg = trim(logMsg);
	if ( !trimMsg.empty() ) {
		log += trimMsg;
		log += "\n\n";
	}
}

// Appends the error text to the result log, and returns false to indicate an error.
bool SPIRVToMSLConverter::logError(string& log, const char* errMsg) {
	logMsg(log, errMsg);
	fprintf(stderr, "[mvk-error] %s\n", errMsg);
	return false;
}

// Appends the SPIR-V to the result log, indicating whether it is being converted or was converted.
void SPIRVToMSLConverter::logSPIRV(string& log, const char* opDesc) {

	log += opDesc;
	log += " SPIR-V:\n";
	mvk::logSPIRV(_spirv, log);
	log += "\nEnd SPIR-V\n\n";

	// Uncomment one or both of the following lines to get additional debugging and tracability capabilities.
	// The SPIR-V can be written in binary form to a file, and/or logged in human readable form to the console.
	// These can be helpful if errors occur during conversion of SPIR-V to MSL.
//	writeSPIRVToFile("spvout.spv", log);
//	printf("\n%s\n", log.c_str());
}

// Writes the SPIR-V code to a file. This can be useful for debugging
// when the SPRIR-V did not originally come from a known file
void SPIRVToMSLConverter::writeSPIRVToFile(string spvFilepath, string& log) {
	vector<char> fileContents;
	spirvToBytes(_spirv, fileContents);
	string errMsg;
	if (writeFile(spvFilepath, fileContents, errMsg)) {
		log += "Saved SPIR-V to file: " + absolutePath(spvFilepath) + "\n\n";
	} else {
		log += "Could not write SPIR-V file. " + errMsg + "\n\n";
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
void SPIRVToMSLConverter::logSource(string& log, string& src, const char* srcLang, const char* opDesc) {
    log += opDesc;
    log += " ";
    log += srcLang;
    log += ":\n";
    log += src;
    log += "\nEnd ";
    log += srcLang;
    log += "\n\n";
}

// Extracts the workgroup dimension from either the LocalSizeId, LocalSize, or WorkgroupSize Builtin.
// Although LocalSizeId is the modern mechanism, the Builtin takes precedence if it is present.
static void getWorkgroupSize(Compiler* pCompiler, SPIREntryPoint& spvEP, uint32_t& x, uint32_t& y, uint32_t& z) {
	auto& wgSz = spvEP.workgroup_size;
	if (spvEP.flags.get(ExecutionModeLocalSizeId) && !wgSz.constant) {
		x = wgSz.id_x ? pCompiler->get_constant(wgSz.id_x).scalar() : 0;
		y = wgSz.id_y ? pCompiler->get_constant(wgSz.id_y).scalar() : 0;
		z = wgSz.id_z ? pCompiler->get_constant(wgSz.id_z).scalar() : 0;
	} else {
		x = wgSz.x;
		y = wgSz.y;
		z = wgSz.z;
	}
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
											 SPIRVToMSLConversionOptions& options,
											 SPIRVEntryPoint& entryPoint) {

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

	entryPoint.mtlFunctionName = spvEP.name;
	entryPoint.supportsFastMath = !spvEP.flags.get(ExecutionModeSignedZeroInfNanPreserve);

	uint32_t x, y, z;
	getWorkgroupSize(pCompiler, spvEP, x, y, z);

	SpecializationConstant widthSC, heightSC, depthSC;
	pCompiler->get_work_group_size_specialization_constants(widthSC, heightSC, depthSC);

	auto& wgSize = entryPoint.workgroupSize;
	populateWorkgroupDimension(wgSize.width,  x, widthSC);
	populateWorkgroupDimension(wgSize.height, y, heightSC);
	populateWorkgroupDimension(wgSize.depth,  z, depthSC);
}

bool SPIRVToMSLConverter::usesPhysicalStorageBufferAddressesCapability(Compiler* pCompiler) {
	if (pCompiler) {
		auto& declaredCapabilities = pCompiler->get_declared_capabilities();
		for(auto dc: declaredCapabilities) {
			if (dc == CapabilityPhysicalStorageBufferAddresses) {
				return true;
			}
		}
	}
	return false;
}

void SPIRVToMSLConverter::populateSpecializationMacros(CompilerMSL* pMSLCompiler,
													   map<uint32_t, MSLSpecializationMacroInfo>& specializationMacros)
{
	if (pMSLCompiler) {
		auto spec_consts = pMSLCompiler->get_specialization_constants();
		for (auto& c: spec_consts) {
			uint32_t id = c.constant_id;
			if (pMSLCompiler->specialization_constant_is_macro(id)) {
				const SPIRConstant& constant = pMSLCompiler->get_constant(c.id);
				const SPIRType& type = pMSLCompiler->get_type(constant.constant_type);
				MSLSpecializationMacroInfo info;

				switch (type.basetype) {
					case SPIRType::SByte:
					case SPIRType::Short:
					case SPIRType::Int:
					case SPIRType::Int64:
						info.isFloat = false;
						info.isSigned = true;
						break;
					case SPIRType::UByte:
					case SPIRType::UShort:
					case SPIRType::UInt:
					case SPIRType::UInt64:
					case SPIRType::Boolean:
						info.isFloat = false;
						info.isSigned = false;
						break;
					case SPIRType::Half:
					case SPIRType::Float:
					case SPIRType::Double:
						info.isFloat = true;
						info.isSigned = false;
						break;
					default:
						continue;  // Ignore unsupported types
				}
				info.name = pMSLCompiler->constant_value_macro_name(id);
				specializationMacros[id] = info;
			}
		}
	}
}
