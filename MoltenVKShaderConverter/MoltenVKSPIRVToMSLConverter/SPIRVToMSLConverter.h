/*
 * SPIRVToMSLConverter.h
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

#ifndef __SPIRVToMSLConverter_h_
#define __SPIRVToMSLConverter_h_ 1

#include "../SPIRV-Cross/spirv.hpp"
#include <string>
#include <vector>
#include <unordered_map>

namespace mvk {


#pragma mark -
#pragma mark SPIRVToMSLConverterContext

	/** Options for converting SPIR-V to Metal Shading Language */
	typedef struct SPIRVToMSLConverterOptions {
		std::string entryPointName;
		spv::ExecutionModel entryPointStage = spv::ExecutionModelMax;

        uint32_t mslVersion = makeMSLVersion(2);
		uint32_t texelBufferTextureWidth = 4096;
		uint32_t auxBufferIndex = 0;
		bool shouldFlipVertexY = true;
		bool isRenderingPoints = false;
		bool shouldSwizzleTextureSamples = false;

		bool isRasterizationDisabled = false;
		bool needsAuxBuffer = false;

        /** 
         * Returns whether the specified options match this one.
         * It does if all corresponding elements are equal.
         */
        bool matches(const SPIRVToMSLConverterOptions& other) const;

		bool hasEntryPoint() const {
			return !entryPointName.empty() && entryPointStage != spv::ExecutionModelMax;
		}

        void setMSLVersion(uint32_t major, uint32_t minor = 0, uint32_t point = 0) {
            mslVersion = makeMSLVersion(major, minor, point);
        }

        bool supportsMSLVersion(uint32_t major, uint32_t minor = 0, uint32_t point = 0) const {
            return mslVersion >= makeMSLVersion(major, minor, point);
        }

        static uint32_t makeMSLVersion(uint32_t major, uint32_t minor = 0, uint32_t patch = 0) {
            return (major * 10000) + (minor * 100) + patch;
        }

		static std::string printMSLVersion(uint32_t mslVersion, bool includePatch = false);

    } SPIRVToMSLConverterOptions;

	/**
	 * Defines the format of a vertex attribute. Currently limited to describing
	 * whether or not the attribute is of an 8-bit unsigned format, a 16-bit
	 * unsigned format, or some other format.
	 */
	enum class MSLVertexFormat {
		Other,
		UInt8,
		UInt16
	};

	/**
	 * Defines MSL characteristics of a vertex attribute at a particular location.
	 * The isUsedByShader flag is set to true during conversion of SPIR-V to MSL
	 * if the shader makes use of this vertex attribute.
	 */
	typedef struct MSLVertexAttribute {
		uint32_t location = 0;
		uint32_t mslBuffer = 0;
        uint32_t mslOffset = 0;
        uint32_t mslStride = 0;
		MSLVertexFormat format = MSLVertexFormat::Other;
        bool isPerInstance = false;

		bool isUsedByShader = false;

        /**
         * Returns whether the specified vertex attribute match this one.
         * It does if all corresponding elements except isUsedByShader are equal.
         */
        bool matches(const MSLVertexAttribute& other) const;
        
	} MSLVertexAttribute;

	/**
	 * Matches the binding index of a MSL resource for a binding within a descriptor set.
	 * Taken together, the stage, desc_set and binding combine to form a reference to a resource
	 * descriptor used in a particular shading stage. Generally, only one of the buffer, texture,
	 * or sampler elements will be populated. The isUsedByShader flag is set to true during
	 * compilation of SPIR-V to MSL if the shader makes use of this vertex attribute.
	 */
	typedef struct MSLResourceBinding {
		spv::ExecutionModel stage;
		uint32_t descriptorSet = 0;
		uint32_t binding = 0;

		uint32_t mslBuffer = 0;
		uint32_t mslTexture = 0;
		uint32_t mslSampler = 0;

		bool isUsedByShader = false;

        /**
         * Returns whether the specified resource binding match this one.
         * It does if all corresponding elements except isUsedByShader are equal.
         */
        bool matches(const MSLResourceBinding& other) const;

    } MSLResourceBinding;

	/** Context passed to the SPIRVToMSLConverter to map SPIR-V descriptors to Metal resource indices. */
	typedef struct SPIRVToMSLConverterContext {
		SPIRVToMSLConverterOptions options;
		std::vector<MSLVertexAttribute> vertexAttributes;
		std::vector<MSLResourceBinding> resourceBindings;

		/** Returns whether the pipeline stage being converted supports vertex attributes. */
		bool stageSupportsVertexAttributes() const;

        /** Returns whether the vertex attribute at the specified location is used by the shader. */
        bool isVertexAttributeLocationUsed(uint32_t location) const;

        /** Returns whether the vertex buffer at the specified Metal binding index is used by the shader. */
        bool isVertexBufferUsed(uint32_t mslBuffer) const;

		/** Marks all vertex attributes and resources as being used by the shader. */
		void markAllAttributesAndResourcesUsed();

        /**
         * Returns whether this context matches the other context. It does if the respective 
         * options match and any vertex attributes and resource bindings used by this context
         * can be found in the other context. Vertex attributes and resource bindings that are
         * in the other context but are not used by the shader that created this context, are ignored.
         */
        bool matches(const SPIRVToMSLConverterContext& other) const;

        /** Aligns certain aspects of this context with the source context. */
        void alignWith(const SPIRVToMSLConverterContext& srcContext);

	} SPIRVToMSLConverterContext;

    /**
     * Describes one dimension of the workgroup size of a SPIR-V entry point, including whether
	 * it is specialized, and if so, the value of the corresponding specialization ID, which
	 * is used to map to a value which will be provided when the MSL is compiled into a pipeline.
     */
	typedef struct {
		uint32_t size = 1;
		uint32_t specializationID = 0;
		bool isSpecialized = false;
	} SPIRVWorkgroupSizeDimension;

	/**
     * Describes a SPIRV entry point, including the Metal function name (which may be
     * different than the Vulkan entry point name if the original name was illegal in Metal),
     * and the size of each workgroup, if the shader is a compute shader.
     */
	typedef struct {
		std::string mtlFunctionName = "main0";
		struct {
			SPIRVWorkgroupSizeDimension width;
			SPIRVWorkgroupSizeDimension height;
			SPIRVWorkgroupSizeDimension depth;
		} workgroupSize;
	} SPIRVEntryPoint;

	/** Special constant used in a MSLResourceBinding descriptorSet element to indicate the bindings for the push constants. */
    static const uint32_t kPushConstDescSet = std::numeric_limits<uint32_t>::max();

	/** Special constant used in a MSLResourceBinding binding element to indicate the bindings for the push constants. */
	static const uint32_t kPushConstBinding = 0;


#pragma mark -
#pragma mark SPIRVToMSLConverter

	/** Converts SPIR-V code to Metal Shading Language code. */
	class SPIRVToMSLConverter {

	public:

		/** Sets the SPIRV code. */
		void setSPIRV(const std::vector<uint32_t>& spirv);

		/**
		 * Sets the SPIRV code from the specified array of values.
		 * The length parameter indicates the number of uint values to store.
		 */
		void setSPIRV(const uint32_t* spirvCode, size_t length);

		/** Returns a reference to the SPIRV code, set by one of the setSPIRV() functions. */
		const std::vector<uint32_t>& getSPIRV();

		/**
		 * Converts SPIR-V code, set using setSPIRV() to MSL code, which can be retrieved using getMSL().
		 *
		 * The boolean flags indicate whether the original SPIR-V code, the resulting MSL code, 
         * and optionally, the original GLSL (as converted from the SPIR_V), should be logged 
         * to the result log of this converter. This can be useful during shader debugging.
		 */
		bool convert(SPIRVToMSLConverterContext& context,
                     bool shouldLogSPIRV = false,
                     bool shouldLogMSL = false,
                     bool shouldLogGLSL = false);

		/**
		 * Returns the Metal Shading Language source code most recently converted
         * by the convert() function, or set directly using the setMSL() function.
		 */
		const std::string& getMSL() { return _msl; }

        /** Returns information about the shader entry point. */
        const SPIRVEntryPoint& getEntryPoint() { return _entryPoint; }

		/**
		 * Returns whether the most recent conversion was successful.
		 *
		 * The initial value of this property is NO. It is set to YES upon successful conversion.
		 */
		bool getWasConverted() { return _wasConverted; }

		/**
		 * Returns a human-readable log of the most recent conversion activity.
		 * This may be empty if the conversion was successful.
		 */
		const std::string& getResultLog() { return _resultLog; }

        /** Sets MSL source code. This can be used when MSL is supplied directly. */
        void setMSL(const std::string& msl, const SPIRVEntryPoint* pEntryPoint) {
            _msl = msl;
			if (pEntryPoint) { _entryPoint = *pEntryPoint; }
        }

	protected:
		void logMsg(const char* logMsg);
		bool logError(const char* errMsg);
		void logSPIRV(const char* opDesc);
		bool validateSPIRV();
		void writeSPIRVToFile(std::string spvFilepath);
        void logSource(std::string& src, const char* srcLang, const char* opDesc);

		std::vector<uint32_t> _spirv;
		std::string _msl;
		std::string _resultLog;
		SPIRVEntryPoint _entryPoint;
		bool _wasConverted = false;
	};

}
#endif
