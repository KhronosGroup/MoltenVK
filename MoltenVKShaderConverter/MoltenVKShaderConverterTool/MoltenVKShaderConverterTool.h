/*
 * MoltenVKShaderConverterTool.h
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

#pragma once


#include "GLSLConversion.h"
#include "SPIRVToMSLConverter.h"
#include <string>
#include <vector>


namespace mvk {

	typedef struct {
		uint32_t count = 0;
		double averageDuration = 0.0;
		double minimumDuration = 0.0;
		double maximumDuration = 0.0;

		uint64_t getTimestamp();
		void accumulate(uint64_t startTime, uint64_t endTime = 0);
	} MVKPerformanceTracker;

#pragma mark -
#pragma mark MoltenVKShaderConverterTool

	/** Converts GLSL files to SPIR-V and MSL files, and SPIR-V files to MSL files. */
	class MoltenVKShaderConverterTool {

	public:

		/**
		 * Called automatically during the conversion of all the files in a directory. 
		 * Processes the specified file (which can contain either GLSL or SPIR-V code.
		 *
		 * Returns false if the file is of the right type to be converted, but failed
		 * to be converted correctly. Returns true otherwise.
		 */
		bool processFile(std::string filePath);

		/** 
		 * Run the converter based on command line arguments.
		 * Returns zero if all went well, or an error code if not.
		 */
		int run();

		/** Constructor with specified command line arguments. */
		MoltenVKShaderConverterTool(int argc, const char* argv[]);

	protected:
		MVKGLSLConversionShaderStage shaderStageFromFileExtension(std::string& pathExtension);
		bool isGLSLFileExtension(std::string& pathExtension);
		bool isSPIRVFileExtension(std::string& pathExtension);
		bool convertGLSL(std::string& glslInFile,
						 std::string& spvOutFile,
						 std::string& mslOutFile,
						 MVKGLSLConversionShaderStage shaderStage);
		bool convertSPIRV(std::string& spvInFile,
						  std::string& mslOutFile);
		bool convertSPIRV(const std::vector<uint32_t>& spv,
						  std::string& inFile,
						  std::string& mslOutFile,
						  bool shouldLogSPV);
		bool parseArgs(int argc, const char* argv[]);
		void log(const char* logMsg);
		void showUsage();
		bool isOptionArg(std::string& arg);
		int optionalParam(std::string& optionParamResult,
						  int optionArgIndex,
						  int argc,
						  const char* argv[]);
		void reportPerformance();
		void reportPerformance(MVKPerformanceTracker& shaderCompilationEvent,
							   std::string eventDescription);

		std::string _processName;
		std::string _directoryPath;
		std::string _glslInFilePath;
		std::string _spvInFilePath;
		std::string _spvOutFilePath;
		std::string _mslOutFilePath;
		std::string _hdrOutVarName;
		std::string _origPathExtnSep;
		std::vector<std::string> _glslVtxFileExtns;
		std::vector<std::string> _glslFragFileExtns;
        std::vector<std::string> _glslCompFileExtns;
		std::vector<std::string> _spvFileExtns;
		MVKGLSLConversionShaderStage _shaderStage;
		MVKPerformanceTracker _glslConversionPerformance;
		MVKPerformanceTracker _spvConversionPerformance;
		uint32_t _mslVersionMajor;
		uint32_t _mslVersionMinor;
		uint32_t _mslVersionPatch;
		SPIRV_CROSS_NAMESPACE::CompilerMSL::Options::Platform _mslPlatform;
		bool _isActive;
		bool _shouldUseDirectoryRecursion;
		bool _shouldReadGLSL;
		bool _shouldReadSPIRV;
		bool _shouldWriteSPIRV;
		bool _shouldWriteMSL;
		bool _shouldCombineGLSLAndMSL;
        bool _shouldFlipVertexY;
		bool _shouldIncludeOrigPathExtn;
		bool _shouldLogConversions;
		bool _shouldReportPerformance;
		bool _shouldOutputAsHeaders;
		bool _quietMode;
	};


#pragma mark -
#pragma mark Support functions

	/**
	 * Extracts whitespace-delimited tokens from the specified string and
	 * appends them to the specified vector. The vector is cleared first.
	 */
	void extractTokens(std::string str, std::vector<std::string>& tokens);

	/**
	 * Extracts period-delimited tokens from the specified string and
	 * appends them to the specified vector. The vector is cleared first.
	 */
	void extractTokens(std::string str, std::vector<uint32_t>& tokens);

	/** Compares the specified strings, with or without sensitivity to case. */
	bool equal(std::string const& a, std::string const& b, bool checkCase = true);

}
