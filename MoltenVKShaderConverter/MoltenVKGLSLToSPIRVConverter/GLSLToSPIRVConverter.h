/*
 * GLSLToSPIRVConverter.h
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

#ifndef __GLSLToSPIRVConverter_h_
#define __GLSLToSPIRVConverter_h_ 1


#include "GLSLConversion.h"
#include <string>
#include <vector>


namespace mvk {

#pragma mark -
#pragma mark GLSLToSPIRVConverter

	/** Converts GLSL code to SPIR-V code. */
	class GLSLToSPIRVConverter {

	public:

		/** Sets the GLSL source code that is to be converted to the specified null-terminated string. */
		void setGLSL(const std::string& glslSrc);

		/** Returns the GLSL source code that was set using the setGLSL() function. */
		const std::string& getGLSL();

		/**
		 * Converts GLSL code, set with setGLSL(), to SPIR-V code, which can be retrieved using getSPIRV().
		 *
		 * The boolean flags indicate whether the original GLSL code and resulting SPIR-V code should
		 * be logged to the result log of this converter. This can be useful during shader debugging.
		 */
		bool convert(MVKShaderStage shaderStage, bool shouldLogGLSL, bool shouldLogSPIRV);

		/** Returns the SPIRV code most recently converted by the convert() function. */
		const std::vector<uint32_t>& getSPIRV();

		/**
		 * Returns whether the most recent conversion was successful.
		 *
		 * The initial value of this property is NO. It is set to YES upon successful conversion.
		 */
		bool getWasConverted();

		/**
		 * Returns a human-readable log of the most recent conversion activity.
		 * This may be empty if the conversion was successful.
		 */
		const std::string& getResultLog();

	protected:
		void logMsg(const char* logMsg);
		bool logError(const char* errMsg);
		void logGLSL(const char* opDesc);
		void logSPIRV(const char* opDesc);
		bool validateSPIRV();
		void initGLSLCompilerResources();

		std::string _glsl;
		std::vector<uint32_t> _spirv;
		std::string _resultLog;
		bool _wasConverted = false;
	};

}

#endif
