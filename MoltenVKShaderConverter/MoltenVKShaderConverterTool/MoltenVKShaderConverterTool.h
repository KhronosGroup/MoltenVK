/*
 * MoltenVKShaderConverterTool.h
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

#pragma once


#include "GLSLConversion.h"
#include <string>
#include <vector>


namespace mvk {


#pragma mark -
#pragma mark MoltenVKShaderConverterTool

	/** Converts GLSL files to SPIR-V and MSL files, and SPIR-V files to MSL files. */
	class MoltenVKShaderConverterTool {

	public:

		/**
		 * Called automatically during the conversion of all the files in a directory. 
		 * Processes the specified file (which can contain either GLSL or SPIR-V code.
		 * Always returns false.
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
		MVKShaderStage shaderStageFromFileExtension(std::string& pathExtension);
		bool isGLSLFileExtension(std::string& pathExtension);
		bool isSPIRVFileExtension(std::string& pathExtension);
		bool convertGLSL(std::string& glslInFile,
						 std::string& spvOutFile,
						 std::string& mslOutFile,
						 MVKShaderStage shaderStage);
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
		int optionParam(std::string& optionParamResult,
						int optionArgIndex,
						int argc,
						const char* argv[]);

		std::string _processName;
		std::string _directoryPath;
		std::string _glslInFilePath;
		std::string _spvInFilePath;
		std::string _spvOutFilePath;
		std::string _mslOutFilePath;
		std::string _origPathExtnSep;
		std::vector<std::string> _glslVtxFileExtns;
		std::vector<std::string> _glslFragFileExtns;
        std::vector<std::string> _glslCompFileExtns;
		std::vector<std::string> _spvFileExtns;
		MVKShaderStage _shaderStage;
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
	};


#pragma mark -
#pragma mark Support functions

	/**
	 * Extracts whitespace-delimited tokens from the specified string and
	 * appends them to the specified vector. The vector is not cleared first.
	 */
	void extractTokens(std::string str, std::vector<std::string>& tokens);

	/** Compares the specified strings, with or without sensitivity to case. */
	bool equal(std::string const& a, std::string const& b, bool checkCase = true);

}
