/*
 * MVKShaderModule.h
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

#include "MVKDevice.h"
#include "MVKSync.h"
#include "MVKCodec.h"
#include "MVKSmallVector.h"
#include <MoltenVKShaderConverter/SPIRVToMSLConverter.h>
#include <mutex>

#import <Metal/Metal.h>

class MVKPipelineCache;
class MVKShaderCacheIterator;
class MVKShaderLibraryCache;
class MVKShaderModule;

#pragma mark -
#pragma mark MVKShaderLibrary

/** A MTLFunction and corresponding result information resulting from a shader conversion. */
typedef struct MVKMTLFunction {
  mvk::SPIRVToMSLConversionResultInfo shaderConversionResults;
	MTLSize threadGroupSize;
	id<MTLFunction> getMTLFunction() { return _mtlFunction; }

	MVKMTLFunction(id<MTLFunction> mtlFunc, const mvk::SPIRVToMSLConversionResultInfo scRslts, MTLSize tgSize);
	MVKMTLFunction(const MVKMTLFunction& other);
	MVKMTLFunction& operator=(const MVKMTLFunction& other);
	MVKMTLFunction() {}
	~MVKMTLFunction();

private:
	id<MTLFunction> _mtlFunction = nil;

} MVKMTLFunction;

/** A MVKMTLFunction indicating an invalid MTLFunction. The mtlFunction member is nil. */
const MVKMTLFunction MVKMTLFunctionNull(nil, mvk::SPIRVToMSLConversionResultInfo(), MTLSizeMake(1, 1, 1));

typedef struct MVKShaderMacroValue {
	union {
		int8_t si8;
		uint8_t ui8;
		int16_t si16;
		uint16_t ui16;
		int32_t si32;
		uint32_t ui32;
		int64_t si64;
		uint64_t ui64;
		float f32;
		double f64;
	} value;
	size_t size;

	inline bool operator<(const MVKShaderMacroValue& other) const {
		return value.ui64 < other.value.ui64 ||
			   (value.ui64 == other.value.ui64 && size < other.size);
	}
} MVKShaderMacroValue;

/**
 * Wraps a single MTLLibrary or a set of MTLLibrary variants with macro-based specialization
 *
 * The latter case is used when Vulkan specialization constants cannot be realized with
 * Metal function constants. Those specialization constants are turned into macros, and
 * when specialized, we have to *recompile* the MTLLibrary from source.
 *
 * To keep the details transparent to users, when specialization on macro occurs,
 * MVKShaderLibrary creates specialized variants (each one also a MVKShaderLibrary) behind
 * the scene and cache them in a map according to the macro-value mapping.
 */
class MVKShaderLibrary : public MVKBaseDeviceObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _owner->getVulkanAPIObject(); };

	/**
	 * Sets the entry point function name.
	 *
	 * This is usually set automatically during shader conversion from SPIR-V to MSL.
	 * For a library that was created directly from MSL, this function can be used to
	 * set the name of the function if it has a different name than the default main0().
	 */
	void setEntryPointName(std::string& funcName);

    /**
	 * Sets the number of threads in a single compute kernel workgroup, per dimension.
	 *
	 * This is usually set automatically during shader conversion from SPIR-V to MSL.
	 * For a library that was created directly from MSL, this function can be used to
	 * set the workgroup size..
	 */
    void setWorkgroupSize(uint32_t x, uint32_t y, uint32_t z);
    
	MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner,
					 const mvk::SPIRVToMSLConversionResult& conversionResult);

	/**
	 * When specializationMacroDef is not null, creates a macro-specialized library
	 * specializationMacroDef contains (specialization id, value) mappings, should be sorted
	 */
	MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner,
					 const mvk::SPIRVToMSLConversionResultInfo& resultInfo,
					 const MVKCompressor<std::string> compressedMSL,
					 const std::vector<std::pair<uint32_t, MVKShaderMacroValue>>* specializationMacroDef = nullptr);

	MVKShaderLibrary(MVKVulkanAPIDeviceObject* owner,
					 const void* mslCompiledCodeData,
					 size_t mslCompiledCodeLength);

	MVKShaderLibrary(const MVKShaderLibrary& other);

	MVKShaderLibrary& operator=(const MVKShaderLibrary& other);

	~MVKShaderLibrary() override;

protected:
	friend MVKShaderCacheIterator;
	friend MVKShaderLibraryCache;
	friend MVKShaderModule;

	MVKMTLFunction getMTLFunction(const VkSpecializationInfo* pSpecializationInfo,
								  VkPipelineCreationFeedback* pShaderFeedback,
								  MVKShaderModule* shaderModule);
	void handleCompilationError(NSError* err, const char* opDesc);
    MTLFunctionConstant* getFunctionConstant(NSArray<MTLFunctionConstant*>* mtlFCs, NSUInteger mtlFCID);
	void compileLibrary(const std::string& msl,
						const std::vector<std::pair<uint32_t, MVKShaderMacroValue> >* specializationMacroDef = nullptr);
	void compressMSL(const std::string& msl);
	void decompressMSL(std::string& msl);
	MVKCompressor<std::string>& getCompressedMSL() { return _compressedMSL; }

	MVKVulkanAPIDeviceObject* _owner;
	id<MTLLibrary> _mtlLibrary;
	MVKCompressor<std::string> _compressedMSL;
	mvk::SPIRVToMSLConversionResultInfo _shaderConversionResultInfo;

	/** When true, representing a library created with source, but never specialized */
	bool _maySpecializeWithMacro;
	/** Can only be populated when _maySpecializeWithMacro is true */
	std::map<std::vector<std::pair<uint32_t, MVKShaderMacroValue>>, MVKShaderLibrary *> _specializationVariants;
};


#pragma mark -
#pragma mark MVKShaderLibraryCache

/** Represents a cache of shader libraries for one shader module. */
class MVKShaderLibraryCache : public MVKBaseDeviceObject {

public:

	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return _owner->getVulkanAPIObject(); };

	/**
	 * Returns a shader library from the shader conversion configuration sourced from the
	 * shader module, lazily creating the shader library from source code in the shader
	 * module, if needed, and if the pipeline is not configured to fail if a pipeline compile
	 * is required. In that case, the new shader library is not created, and nil is returned.
	 *
	 * If pWasAdded is not nil, this function will set it to true if a new shader library was created,
	 * and to false if an existing shader library was found and returned.
	 */
	MVKShaderLibrary* getShaderLibrary(mvk::SPIRVToMSLConversionConfiguration* pShaderConfig,
									   MVKShaderModule* shaderModule, MVKPipeline* pipeline,
									   bool* pWasAdded, VkPipelineCreationFeedback* pShaderFeedback,
									   uint64_t startTime = 0);

	MVKShaderLibraryCache(MVKVulkanAPIDeviceObject* owner) : MVKBaseDeviceObject(owner->getDevice()), _owner(owner) {};

	~MVKShaderLibraryCache() override;

protected:
	friend MVKShaderCacheIterator;
	friend MVKPipelineCache;
	friend MVKShaderModule;

	MVKShaderLibrary* findShaderLibrary(mvk::SPIRVToMSLConversionConfiguration* pShaderConfig,
										VkPipelineCreationFeedback* pShaderFeedback = nullptr,
										uint64_t startTime = 0);
	MVKShaderLibrary* addShaderLibrary(const mvk::SPIRVToMSLConversionConfiguration* pShaderConfig,
									   const mvk::SPIRVToMSLConversionResult& conversionResult);
	MVKShaderLibrary* addShaderLibrary(const mvk::SPIRVToMSLConversionConfiguration* pShaderConfig,
									   const mvk::SPIRVToMSLConversionResultInfo& resultInfo,
									   const MVKCompressor<std::string> compressedMSL);
	void merge(MVKShaderLibraryCache* other);

	MVKVulkanAPIDeviceObject* _owner;
	MVKSmallVector<std::pair<mvk::SPIRVToMSLConversionConfiguration, MVKShaderLibrary*>> _shaderLibraries;
};


#pragma mark -
#pragma mark MVKShaderModule

typedef struct MVKShaderModuleKey {
	std::size_t codeSize;
	std::size_t codeHash;

	bool operator==(const MVKShaderModuleKey& rhs) const {
		return ((codeSize == rhs.codeSize) && (codeHash == rhs.codeHash));
	}
	MVKShaderModuleKey(std::size_t codeSize, std::size_t codeHash) : codeSize(codeSize), codeHash(codeHash) {}
	MVKShaderModuleKey() :  MVKShaderModuleKey(0, 0) {}
} MVKShaderModuleKey;

/**
 * Hash structure implementation for MVKShaderModuleKey in std namespace,
 * so MVKShaderModuleKey can be used as a key in a std::map and std::unordered_map.
 */
namespace std {
	template <>
	struct hash<MVKShaderModuleKey> {
		std::size_t operator()(const MVKShaderModuleKey& k) const { return k.codeHash; }
	};
}

/** Represents a Vulkan shader module. */
class MVKShaderModule : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_SHADER_MODULE; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_SHADER_MODULE_EXT; }

	/** Returns the Metal shader function, possibly specialized. */
	MVKMTLFunction getMTLFunction(mvk::SPIRVToMSLConversionConfiguration* pShaderConfig,
								  const VkSpecializationInfo* pSpecializationInfo,
								  MVKPipeline* pipeline,
								  VkPipelineCreationFeedback* pShaderFeedback);

	/** Convert the SPIR-V to MSL, using the specified shader conversion configuration. */
	bool convert(mvk::SPIRVToMSLConversionConfiguration* pShaderConfig,
               mvk::SPIRVToMSLConversionResult& conversionResult);

	/** Returns the original SPIR-V code that was specified when this object was created. */
	const std::vector<uint32_t>& getSPIRV() { return _spvConverter.getSPIRV(); }

    /** Sets the number of threads in a single compute kernel workgroup, per dimension. */
    void setWorkgroupSize(uint32_t x, uint32_t y, uint32_t z);
    
	/** Returns a key as a means of identifying this shader module in a pipeline cache. */
	MVKShaderModuleKey getKey() { return _key; }

	MVKShaderModule(MVKDevice* device, const VkShaderModuleCreateInfo* pCreateInfo);

	~MVKShaderModule() override;

protected:
	friend MVKShaderCacheIterator;

	void propagateDebugName() override {}

	MVKShaderLibraryCache _shaderLibraryCache;
	mvk::SPIRVToMSLConverter _spvConverter;
	MVKShaderLibrary* _directMSLLibrary;
	MVKShaderModuleKey _key;
    std::mutex _accessLock;
};


#pragma mark -
#pragma mark MVKMTLBinaryArchive

/**
 * A Metal binary archive of compiled pipelines, and the bytes it serializes to.
 *
 * Metal will only hand back a compiled pipeline it has been given beforehand, so a pipeline built
 * against an archive that already holds it is loaded instead of compiled. This is the only part of
 * pipeline creation a later run can avoid outright: a cached shader saves the front end, but the
 * pipeline state itself was compiled again on every run.
 *
 * https://developer.apple.com/documentation/metal/mtlbinaryarchive
 */
class MVKMTLBinaryArchive {

public:

	/**
	 * Returns the archive a pipeline should be built against, or nil when there is nothing in it
	 * to find. An archive that no earlier run seeded holds no pipeline this run has not already
	 * built, so searching it costs a build without ever saving one.
	 */
	id<MTLBinaryArchive> getMTLBinaryArchiveForLookup();

	/**
	 * Records a pipeline to be written into the archive when its bytes are next asked for.
	 *
	 * Adding to a Metal archive costs about as much as building the pipeline again, so it is left
	 * until something is going to keep the result. Until then this only retains the descriptor,
	 * which holds onto the functions the archive will need.
	 */
	void recordRenderPipeline(MTLRenderPipelineDescriptor* mtlRPLDesc);

	/** Returns the serialized archive, including every pipeline recorded into it. */
	const std::vector<char>& getBytes();

	/** Seeds the archive from an earlier run. Must be called before the archive is first used. */
	void setBytes(const void* pBytes, size_t byteCount);

	/** Returns whether a pipeline has been recorded since the bytes were last brought up to date. */
	bool isDirty();

	MVKMTLBinaryArchive(MVKDevice* device) : _device(device) {}

	~MVKMTLBinaryArchive();

protected:
	id<MTLBinaryArchive> getMTLBinaryArchiveLocked();
	void addRecordedPipelinesLocked();
	void refreshBytesLocked();

	MVKDevice* _device;
	std::vector<char> _bytes;
	std::vector<MTLRenderPipelineDescriptor*> _recordedRPLDescs;
	id<MTLBinaryArchive> _mtlBinaryArchive = nil;
	std::mutex _lock;
	bool _isDirty = false;
};


#pragma mark -
#pragma mark MVKShader

class MVKPipelineLayout;

/**
 * The header prefixed to the binary returned by vkGetShaderBinaryDataEXT.
 *
 * Metal offers no way to link a MTLFunction to its neighbours after the fact, and MoltenVK
 * generates MSL that depends on the adjoining stages, so a shader cannot be translated until
 * the stages it will be used with are known. A binary therefore carries the original SPIR-V,
 * and translation is deferred to the draw that first pairs the stages up.
 *
 * Only what identifies the code is stored. Fields such as nextStage and flags come from the
 * create info every time, and would break the requirement that a binary round-trips to an
 * identical binary, because an application may legitimately supply different ones when it
 * recreates a shader from a binary it was handed.
 */
typedef struct MVKShaderBinaryHeader {
	uint32_t magic;
	uint32_t version;
	uint8_t  uuid[VK_UUID_SIZE];
	uint32_t stage;
	uint32_t codeSize;
	uint32_t nameSize;
	uint32_t archiveSize;
} MVKShaderBinaryHeader;

static constexpr uint32_t kMVKShaderBinaryMagic = 0x4D564B53;	// 'MVKS'

// Raised whenever the layout changes, so that a binary from an older MoltenVK is rejected rather
// than misread. Vulkan expects shaderBinaryVersion to be raised alongside it.
static constexpr uint32_t kMVKShaderBinaryVersion = 1;

/** Represents a Vulkan shader object. */
class MVKShader : public MVKVulkanAPIDeviceObject {

public:

	/** Returns the Vulkan type of this object. */
	VkObjectType getVkObjectType() override { return VK_OBJECT_TYPE_SHADER_EXT; }

	/** Returns the debug report object type of this object. */
	VkDebugReportObjectTypeEXT getVkDebugReportObjectType() override { return VK_DEBUG_REPORT_OBJECT_TYPE_UNKNOWN_EXT; }

	/** Returns the single stage this shader was created for. */
	VkShaderStageFlagBits getStage() const { return _stage; }

	/** Returns the stages this shader permits as its successor. */
	VkShaderStageFlags getNextStage() const { return _nextStage; }

	/** Returns the flags this shader was created with. */
	VkShaderCreateFlagsEXT getFlags() const { return _flags; }

	/** Returns the shader module holding this shader's SPIR-V. */
	MVKShaderModule* getShaderModule() { return _shaderModule; }

	/** Returns the name of the SPIR-V entry point to use. */
	const char* getEntryPointName() const { return _entryPointName.c_str(); }

	/** Returns the specialization constants to apply, or null if there are none. */
	const VkSpecializationInfo* getSpecializationInfo() const { return _hasSpecializationInfo ? &_specializationInfo : nullptr; }

	/** Returns the pipeline layout describing this shader's descriptor bindings and push constants. */
	MVKPipelineLayout* getPipelineLayout() const { return _pipelineLayout; }

	/**
	 * Returns whether this fragment shader can be rewritten to blend its own outputs.
	 *
	 * Answered when the shader is created, because it decides whether blend state belongs in
	 * the key its pipelines are cached under, which must be known before one is built.
	 */
	bool canBlendInShader() const { return _canBlendInShader; }

	/**
	 * Returns whether this vertex shader can be rewritten to load its own attributes.
	 *
	 * Answered when the shader is created, for the same reason as canBlendInShader().
	 */
	bool canPullVertices() const { return _canPullVertices; }

	/** Writes this shader's binary representation, following the vkGetShaderBinaryDataEXT rules. */
	VkResult getBinaryData(size_t* pDataSize, void* pData);

	/**
	 * Returns the archive of pipelines that were built from this shader, which a binary carries
	 * so that a later run loads them instead of compiling them again.
	 */
	MVKMTLBinaryArchive* getBinaryArchive() { return &_binaryArchive; }

	/**
	 * Returns whether this fragment shader writes the location zero output that alpha to
	 * coverage derives coverage from, which decides whether it can take that state over.
	 */
	bool canDeriveCoverage() const { return _canDeriveCoverage; }

	/**
	 * Returns whether this shader writes the layer built-in, which decides whether a pipeline
	 * built from it has to declare a topology class.
	 */
	bool writesLayer() const { return _writesLayer; }

	/**
	 * Populates a mask of the vertex input locations this shader reads, and returns whether that
	 * mask can be trusted. Where it cannot, every location must be treated as read.
	 */
	bool getConsumedVertexLocations(uint64_t& locationMask) const {
		locationMask = _consumedVertexLocations;
		return _consumedVertexLocationsValid;
	}

	/**
	 * Returns whether this shader can map the depth clip convention itself, which decides whether
	 * the convention has to stay in the key of the pipelines built from it.
	 */
	bool canMapDepthClip() const { return _canMapDepthClip; }

	MVKShader(MVKDevice* device, const VkShaderCreateInfoEXT* pCreateInfo);

	~MVKShader() override;

protected:
	void propagateDebugName() override {}
	void initFromSPIRV(const VkShaderCreateInfoEXT* pCreateInfo, const void* pCode, size_t codeSize, const char* pName);
	void reflectForPipelineKeys();
	void initFromBinary(const VkShaderCreateInfoEXT* pCreateInfo);
	void initLayout(const VkShaderCreateInfoEXT* pCreateInfo);
	void initSpecialization(const VkSpecializationInfo* pSpecInfo);

	const std::vector<char>& getBinaryArchiveBytes();

	MVKShaderModule* _shaderModule = nullptr;
	MVKPipelineLayout* _pipelineLayout = nullptr;
	MVKMTLBinaryArchive _binaryArchive;
	// Vulkan requires a binary to be invariant for the lifetime of the shader, so the archive is
	// captured the first time one is asked for, and every later binary repeats that capture even
	// if more pipelines have been built from this shader since.
	std::vector<char> _binaryArchiveSnapshot;
	std::mutex _binaryArchiveSnapshotLock;
	bool _hasBinaryArchiveSnapshot = false;
	uint64_t _consumedVertexLocations = 0;
	bool _consumedVertexLocationsValid = false;
	bool _writesLayer = false;
	bool _canMapDepthClip = false;
	std::string _entryPointName;
	MVKSmallVector<VkSpecializationMapEntry, 8> _specializationEntries;
	MVKSmallVector<uint8_t, 64> _specializationData;
	VkSpecializationInfo _specializationInfo = {};
	VkShaderStageFlagBits _stage = VK_SHADER_STAGE_VERTEX_BIT;
	VkShaderStageFlags _nextStage = 0;
	VkShaderCreateFlagsEXT _flags = 0;
	bool _hasSpecializationInfo = false;
	bool _canBlendInShader = false;
	bool _canDeriveCoverage = false;
	bool _canPullVertices = false;
};


#pragma mark -
#pragma mark MVKShaderLibraryCompiler

/**
 * Creates a MTLLibrary from source code.
 *
 * Instances of this class are one-shot, and can only be used for a single library compilation.
 */
class MVKShaderLibraryCompiler : public MVKMetalCompiler {

public:

	/**
	 * Returns a new (retained) MTLLibrary object compiled from the MSL source code.
	 *
	 * If the Metal library compiler does not return within MVKConfiguration::metalCompileTimeout
	 * nanoseconds, an error will be generated and logged, and nil will be returned.
	 */
	id<MTLLibrary> newMTLLibrary(NSString* mslSourceCode,
								 const mvk::SPIRVToMSLConversionResultInfo& shaderConversionResults,
								 const std::vector<std::pair<mvk::MSLSpecializationMacroInfo, MVKShaderMacroValue>>& macroDef);


#pragma mark Construction

	MVKShaderLibraryCompiler(MVKVulkanAPIDeviceObject* owner) : MVKMetalCompiler(owner) {
		_compilerType = "Shader library";
		_pPerformanceTracker = &getPerformanceStats().shaderCompilation.mslCompile;
	}

	~MVKShaderLibraryCompiler() override;

protected:
	NSNumber *getMacroValue(const mvk::MSLSpecializationMacroInfo& info, const MVKShaderMacroValue& value);
	bool compileComplete(id<MTLLibrary> mtlLibrary, NSError *error);
	void handleError() override;
	void logCompilation(MTLCompileOptions*);

	id<MTLLibrary> _mtlLibrary = nil;
};


#pragma mark -
#pragma mark MVKFunctionSpecializer

/**
 * Compiles a specialized MTLFunction.
 *
 * Instances of this class are one-shot, and can only be used for a single function compilation.
 */
class MVKFunctionSpecializer : public MVKMetalCompiler {

public:

	/**
	 * Returns a new (retained) MTLFunction object compiled from the MTLLibrary and specialization constants.
	 *
	 * If the Metal function compiler does not return within MVKConfiguration::metalCompileTimeout
	 * nanoseconds, an error will be generated and logged, and nil will be returned.
	 */
	id<MTLFunction> newMTLFunction(id<MTLLibrary> mtlLibrary, NSString* funcName, MTLFunctionConstantValues* constantValues);


#pragma mark Construction

	MVKFunctionSpecializer(MVKVulkanAPIDeviceObject* owner) : MVKMetalCompiler(owner) {
		_compilerType = "Function specialization";
		_pPerformanceTracker = &getPerformanceStats().shaderCompilation.functionSpecialization;
	}

	~MVKFunctionSpecializer() override;

protected:
	bool compileComplete(id<MTLFunction> mtlFunction, NSError *error);

	id<MTLFunction> _mtlFunction = nil;
};
