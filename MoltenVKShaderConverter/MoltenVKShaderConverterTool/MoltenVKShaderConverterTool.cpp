/*
 * MoltenVKShaderConverterTool.cpp
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

#include "MoltenVKShaderConverterTool.h"
#include "FileSupport.h"
#include "OSSupport.h"
#include "SPIRVToMSLConverter.h"
#include "SPIRVSupport.h"
#include "MVKOSExtensions.h"

using namespace std;
using namespace mvk;


// The default list of vertex file extensions.
static const char* _defaultVertexShaderExtns = "vs vsh vert vertex";

// The default list of tessellation control file extensions.
static const char* _defaultTescShaderExtns = "tcs tcsh tesc";

// The default list of tessellation evaluation file extensions.
static const char* _defaultTeseShaderExtns = "tes tesh tese";

// The default list of fragment file extensions.
static const char* _defaultFragShaderExtns = "fs fsh frag fragment";

// The default list of compute file extensions.
static const char* _defaultCompShaderExtns = "cs csh cp cmp comp compute kn kl krn kern kernel";

// The default list of SPIR-V file extensions.
static const char* _defaultSPIRVShaderExtns = "spv spirv";


uint64_t MVKPerformanceTracker::getTimestamp() { return mvkGetTimestamp(); }

void MVKPerformanceTracker::accumulate(uint64_t startTime, uint64_t endTime) {
	double currInterval = mvkGetElapsedMilliseconds(startTime, endTime);
	minimumDuration = (minimumDuration == 0.0) ? currInterval : min(currInterval, minimumDuration);
	maximumDuration = max(currInterval, maximumDuration);
	double totalInterval = (averageDuration * count++) + currInterval;
	averageDuration = totalInterval / count;
}


#pragma mark -
#pragma mark MoltenVKShaderConverterTool


int MoltenVKShaderConverterTool::run() {
	if ( !_isActive ) { return EXIT_FAILURE; }

	bool success = false;
	if ( !_directoryPath.empty() ) {
		string errMsg;
		success = iterateDirectory(_directoryPath, *this, _shouldUseDirectoryRecursion, errMsg);
		if ( !success ) { log(errMsg.data()); }
	} else {
		if (_shouldReadSPIRV) {
			success = convertSPIRV(_spvInFilePath, _mslOutFilePath);
		} else {
			showUsage();
		}
	}
	reportPerformance();

	return success ? EXIT_SUCCESS : EXIT_FAILURE;
}

bool MoltenVKShaderConverterTool::processFile(string filePath) {
	string absPath = absolutePath(filePath);
	string emptyPath;

	string pathExtn = pathExtension(absPath);
	if (_shouldReadSPIRV && isSPIRVFileExtension(pathExtn)) {
		return convertSPIRV(absPath, emptyPath);
	}

	return true;
}

// Read SPIR-V code from a SPIR-V file, convert to MSL, and write the MSL code to files.
bool MoltenVKShaderConverterTool::convertSPIRV(string& spvInFile, string& mslOutFile) {
	string path;
	vector<char> fileContents;
	vector<uint32_t> spv;
	string errMsg;

	// Read the SPIRV
	if (spvInFile.empty()) {
		log("The SPIR-V file to read from was not specified");
		return false;
	}

	path = spvInFile;
	if (readFile(path, fileContents, errMsg)) {
		string logMsg = "Read SPIR-V from file: " + fileName(path);
		log(logMsg.data());
	} else {
		errMsg = "Could not read SPIR-V file. " + errMsg;
		log(errMsg.data());
		return false;
	}
	bytesToSPIRV(fileContents, spv);

	return convertSPIRV(spv, spvInFile, mslOutFile, _shouldLogConversions);
}

// Read SPIR-V code from an array, convert to MSL, and write the MSL code to files.
bool MoltenVKShaderConverterTool::convertSPIRV(const vector<uint32_t>& spv,
											   string& inFile,
											   string& mslOutFile,
											   bool shouldLogSPV) {
	if ( !_shouldWriteMSL ) { return true; }

	// Derive the context under which conversion will occur
	SPIRVToMSLConversionConfiguration mslContext;
	mslContext.options.mslOptions.platform = _mslPlatform;
	mslContext.options.mslOptions.set_msl_version(_mslVersionMajor, _mslVersionMinor, _mslVersionPatch);
	mslContext.options.shouldFlipVertexY = _shouldFlipVertexY;
	mslContext.options.mslOptions.argument_buffers = _useMetalArgumentBuffers;
	mslContext.options.mslOptions.force_active_argument_buffer_resources = false;
	mslContext.options.mslOptions.pad_argument_buffer_resources = false;
	mslContext.options.mslOptions.argument_buffers_tier = SPIRV_CROSS_NAMESPACE::CompilerMSL::Options::ArgumentBuffersTier::Tier2;
	mslContext.options.mslOptions.replace_recursive_inputs = mvkOSVersionIsAtLeast(14.0, 17.0, 1.0);
	mslContext.options.mslOptions.multi_patch_workgroup = true;

	SPIRVToMSLConverter spvConverter;
	spvConverter.setSPIRV(spv);

	uint64_t startTime = _spvConversionPerformance.getTimestamp();
	SPIRVToMSLConversionResult conversionResult;
	bool wasConverted = spvConverter.convert(mslContext, conversionResult, shouldLogSPV, _shouldLogConversions, (_shouldLogConversions && shouldLogSPV));
	_spvConversionPerformance.accumulate(startTime);

	if (wasConverted) {
		if (_shouldLogConversions) { log(conversionResult.resultLog.data()); }
	} else {
		string errMsg = "Could not convert SPIR-V in file: " + absolutePath(inFile);
		log(errMsg.data());
		log(conversionResult.resultLog.data());
		return false;
	}

	// Write the MSL to file
	string path = mslOutFile;
	if (mslOutFile.empty()) { path = pathWithExtension(inFile, "metal", _shouldIncludeOrigPathExtn, _origPathExtnSep); }

	string compileErrMsg;
	bool wasCompiled = compile(conversionResult.msl, compileErrMsg, _mslVersionMajor, _mslVersionMinor, _mslVersionPatch);
	if (compileErrMsg.size() > 0) {
		string preamble = wasCompiled ? "is valid but the validation compilation produced warnings: " : "failed a validation compilation: ";
		compileErrMsg = "Generated MSL " + preamble + compileErrMsg;
		log(compileErrMsg.c_str());
	} else {
		log("Generated MSL was validated by a successful compilation with no warnings.");
	}

	vector<char> fileContents;
	fileContents.insert(fileContents.end(), conversionResult.msl.begin(), conversionResult.msl.end());
	string writeErrMsg;
	if (writeFile(path, fileContents, writeErrMsg)) {
		string logMsg = "Saved MSL to file: " + fileName(path);
		log(logMsg.c_str());
		return true;
	} else {
		writeErrMsg = "Could not write MSL file. " + writeErrMsg;
		log(writeErrMsg.c_str());
		return false;
	}
}

bool MoltenVKShaderConverterTool::isSPIRVFileExtension(string& pathExtension) {
    for (auto& fx : _spvFileExtns) { if (fx == pathExtension) { return true; } }
	return false;
}

// Log the specified message to the console.
void MoltenVKShaderConverterTool::log(const char* logMsg) {
	if ( !_quietMode ) { printf("%s\n", logMsg); }
}

// Display usage information about this application on the console.
void MoltenVKShaderConverterTool::showUsage() {
	bool qm = _quietMode;
	_quietMode = false;

	string line = "\n\e[1m" + _processName + "\e[0m converts SPIR-V code to Metal Shading Language source code.";
	log((const char*)line.c_str());
	log("\nTo convert a single SPIR-V file, include a file reference with the -si");
	log("option. To convert an entire directory of shader files, use the -d option");
	log("along with the -si option. When using the -d option, any file name supplied");
	log("with the -si option will be ignored.");
	log("\nUse the -so or -mo option to indicate the desired type of output");
	log("(SPIR-V or MSL, respectively).");
	log("\nUsage:");
	log("  -d [\"dirPath\"]     - Path to a directory containing GLSL or SPIR-V shader");
	log("                       source code files. The dirPath may be omitted to use");
	log("                       the current working directory.");
	log("  -r                 - (when using -d) Process directories recursively.");
	log("  -si [\"spvInFile\"]  - Indicates that SPIR-V shader code should be input.");
	log("                       The optional spvInFile parameter specifies the path to a");
	log("                       single file containing SPIR-V code to be converted.");
	log("                       When using the -d option, the spvInFile parameter is ignored.");
	log("  -so [\"spvOutFile\"] - Indicates that SPIR-V shader code should be output.");
	log("                       The optional spvOutFile parameter specifies the path to a single");
	log("                       file to contain the SPIR-V code. When using the -d option,");
	log("                       the spvOutFile parameter is ignored.");
	log("  -mo [\"mslOutFile\"] - Indicates that MSL shader source code should be output.");
	log("                       The optional mslOutFile parameter specifies the path to a single");
	log("                       file to contain the MSL code. When using the -d option,");
	log("                       the mslOutFile parameter is ignored.");
	log("  -mv mslVersion     - MSL version to output.");
	log("                       Must be in form n[.n][.n] (eg. 2, 2.1, or 2.1.0).");
	log("                       Defaults to the most recent MSL version for the platform");
	log("                       on which this tool is executed.");
	log("  -mp mslPlatform    - MSL platform. Must be one of macos or ios.");
	log("                       Defaults to the platform on which this tool is executed (macos).");
	log("  -oh [varName]      - Save the output as header (.h) files.");
	log("                       Affects the output of the -so option.");
	log("                       The optional varName parameter specifies the name of the");
	log("                       variable in the header file to which the output code is assigned.");
	log("                       When using the -d option, the varName parameter is ignored.");
	log("  -Iv                - Disable inversion of the vertex coordinate Y-axis");
    log("                       (default is to invert vertex coordinates).");
	log("  -xs \"xtnSep\"       - Separator to use when including file extension of original");
	log("                       code file name in derived converted code file name.");
	log("                       Default is \"_\" (myshdr.vsh -> myshdr_vsh.metal).");
	log("  -XS                - Disable including file extension of original code");
	log("                       file name in derived converted code file name");
	log("                       (myshdr.vsh -> myshdr.metal).");
	log("  -sx \"fileExtns\"    - List of SPIR-V shader file extensions.");
	log("                       May be omitted for defaults (\"spv spirv\").");
	log("  -mab               - Use Metal Argument Buffers to hold resources in the shaders.");
	log("  -l                 - Log the conversion results to the console (to aid debugging).");
	log("  -p                 - Log the performance of the shader conversions.");
	log("  -q                 - Quiet mode. Stops logging of informational messages.");
	log("");

	_quietMode = qm;
}

void MoltenVKShaderConverterTool::reportPerformance() {
	if ( !_shouldReportPerformance ) { return; }

	reportPerformance(_spvConversionPerformance, "SPIR-V to MSL");
}

void MoltenVKShaderConverterTool::reportPerformance(MVKPerformanceTracker& shaderCompilationEvent, string eventDescription) {
	string logMsg;
	logMsg += "Performance to convert ";
	logMsg += eventDescription;
	logMsg += " count: ";
	logMsg += to_string(shaderCompilationEvent.count);
	logMsg += ", min: ";
	logMsg += to_string(shaderCompilationEvent.minimumDuration);
	logMsg += " ms, max: ";
	logMsg += to_string(shaderCompilationEvent.maximumDuration);
	logMsg += " ms, avg: ";
	logMsg += to_string(shaderCompilationEvent.averageDuration);
	logMsg += " ms.\n";
	log(logMsg.c_str());
}


#pragma mark Construction

MoltenVKShaderConverterTool::MoltenVKShaderConverterTool(int argc, const char* argv[]) {
	extractTokens(_defaultSPIRVShaderExtns, _spvFileExtns);
	_origPathExtnSep = "_";
	_shouldUseDirectoryRecursion = false;
	_shouldReadSPIRV = false;
	_shouldWriteSPIRV = false;
	_shouldWriteMSL = false;
    _shouldFlipVertexY = true;
	_shouldIncludeOrigPathExtn = true;
	_shouldLogConversions = false;
	_shouldReportPerformance = false;
	_shouldOutputAsHeaders = false;
	_quietMode = false;
	_useMetalArgumentBuffers = false;

	if (mvkOSVersionIsAtLeast(14.0)) {
		_mslVersionMajor = 3;
		_mslVersionMinor = 1;
	} else 	if (mvkOSVersionIsAtLeast(13.0)) {
		_mslVersionMajor = 3;
		_mslVersionMinor = 0;
	} else if (mvkOSVersionIsAtLeast(12.0)) {
		_mslVersionMajor = 2;
		_mslVersionMinor = 4;
	} else if (mvkOSVersionIsAtLeast(11.0)) {
		_mslVersionMajor = 2;
		_mslVersionMinor = 3;
	} else if (mvkOSVersionIsAtLeast(10.15)) {
		_mslVersionMajor = 2;
		_mslVersionMinor = 2;
	} else if (mvkOSVersionIsAtLeast(10.14)) {
		_mslVersionMajor = 2;
		_mslVersionMinor = 1;
	} else if (mvkOSVersionIsAtLeast(10.13)) {
		_mslVersionMajor = 2;
		_mslVersionMinor = 0;
	} else if (mvkOSVersionIsAtLeast(10.12)) {
		_mslVersionMajor = 1;
		_mslVersionMinor = 2;
	} else {
		_mslVersionMajor = 1;
		_mslVersionMinor = 1;
	}

	_mslVersionPatch = 0;

	_mslPlatform = SPIRVToMSLConversionOptions().mslOptions.platform;

	_isActive = parseArgs(argc, argv);
	if ( !_isActive ) { showUsage(); }
}

bool MoltenVKShaderConverterTool::parseArgs(int argc, const char* argv[]) {
	if (argc == 0) { return false; }

	string execPath(argv[0]);
	_processName = fileName(execPath, false);

	for (int argIdx = 1; argIdx < argc; argIdx++) {
		string arg = argv[argIdx];

		if ( !isOptionArg(arg) ) { return false; }

		if (equal(arg, "-d", false)) {
			int optIdx = argIdx;
			argIdx = optionalParam(_directoryPath, argIdx, argc, argv);
			if (argIdx == optIdx) { return false; }
			_directoryPath = absolutePath(_directoryPath);
			continue;
		}

		if(equal(arg, "-r", true)) {
			_shouldUseDirectoryRecursion = true;
			continue;
		}

		if (equal(arg, "-si", true)) {
			_shouldReadSPIRV = true;
			argIdx = optionalParam(_spvInFilePath, argIdx, argc, argv);
			continue;
		}

		if (equal(arg, "-so", true)) {
			_shouldWriteSPIRV = true;
			argIdx = optionalParam(_spvOutFilePath, argIdx, argc, argv);
			continue;
		}

		if (equal(arg, "-mo", true)) {
			_shouldWriteMSL = true;
			argIdx = optionalParam(_mslOutFilePath, argIdx, argc, argv);
			continue;
		}

		if (equal(arg, "-mv", true)) {
			int optIdx = argIdx;
			string mslVerStr;
			argIdx = optionalParam(mslVerStr, argIdx, argc, argv);
			if (argIdx == optIdx || mslVerStr.length() == 0) { return false; }
			vector<uint32_t> mslVerTokens;
			extractTokens(mslVerStr, mslVerTokens);
			auto tknCnt = mslVerTokens.size();
			_mslVersionMajor = (tknCnt > 0) ? mslVerTokens[0] : 0;
			_mslVersionMinor = (tknCnt > 1) ? mslVerTokens[1] : 0;
			_mslVersionPatch = (tknCnt > 2) ? mslVerTokens[2] : 0;
			continue;
		}

		if (equal(arg, "-mp", true)) {
			int optIdx = argIdx;
			string shdrTypeStr;
			argIdx = optionalParam(shdrTypeStr, argIdx, argc, argv);
			if (argIdx == optIdx || shdrTypeStr.length() == 0) { return false; }

			switch (shdrTypeStr.front()) {
				case 'm':
					_mslPlatform = SPIRV_CROSS_NAMESPACE::CompilerMSL::Options::macOS;
					break;
				case 'i':
					_mslPlatform = SPIRV_CROSS_NAMESPACE::CompilerMSL::Options::iOS;
					break;
				default:
					return false;
			}
			continue;
		}

		if(equal(arg, "-oh", true)) {
			_shouldOutputAsHeaders = true;
			argIdx = optionalParam(_hdrOutVarName, argIdx, argc, argv);
			continue;
		}

        if(equal(arg, "-Iv", true)) {
            _shouldFlipVertexY = false;
            continue;
        }

		if (equal(arg, "-xs", true)) {
			_shouldIncludeOrigPathExtn = true;
			argIdx++;
			if (argIdx < argc) { _origPathExtnSep = argv[argIdx]; }
			continue;
		}

		if(equal(arg, "-XS", true)) {
			_shouldIncludeOrigPathExtn = false;
			continue;
		}

		if (equal(arg, "-sx", true)) {
			int optIdx = argIdx;
			string shdrExtnStr;
			argIdx = optionalParam(shdrExtnStr, argIdx, argc, argv);
			if (argIdx == optIdx || shdrExtnStr.length() == 0) { return false; }
			extractTokens(shdrExtnStr, _spvFileExtns);
			continue;
		}

		if(equal(arg, "-mab", true)) {
			_useMetalArgumentBuffers = true;
			continue;
		}

		if(equal(arg, "-l", true)) {
			_shouldLogConversions = true;
			continue;
		}

		if(equal(arg, "-p", true)) {
			_shouldReportPerformance = true;
			continue;
		}

		if(equal(arg, "-q", true)) {
			_quietMode = true;
			continue;
		}

	}

	return true;
}

// Returns whether the specified command line arg is an option arg.
bool MoltenVKShaderConverterTool::isOptionArg(string& arg) {
	return (arg.length() > 1 && arg.front() == '-');
}

// Sets the contents of the specified string to the parameter part of the option at the
// specified arg index, and increments and returns the option index. If no parameter was
// provided for the option, the string will be set to an empty string, and the returned
// index will be the same as the specified index.
int MoltenVKShaderConverterTool::optionalParam(string& optionParamResult,
											   int optionArgIndex,
											   int argc,
											   const char* argv[]) {
	int optParamIdx = optionArgIndex + 1;
	if (optParamIdx < argc) {
		string arg(argv[optParamIdx]);
		if ( !isOptionArg(arg) ) {
			optionParamResult = arg;
			return optParamIdx;
		}
	}
	optionParamResult.clear();
	return optionArgIndex;
}


#pragma mark -
#pragma mark Support functions

// Template function for tokenizing the components of a string into a vector.
template <typename Container>
Container& split(Container& result,
				 const typename Container::value_type& s,
				 const typename Container::value_type& delimiters,
				 bool includeEmptyElements) {
	result.clear();
	size_t current;
	size_t next = -1;
	do {
		if (includeEmptyElements) {
			next = s.find_first_not_of( delimiters, next + 1 );
			if (next == Container::value_type::npos) break;
			next -= 1;
		}
		current = next + 1;
		next = s.find_first_of( delimiters, current );
		result.push_back( s.substr( current, next - current ) );
	} while (next != Container::value_type::npos);
	return result;
}

void mvk::extractTokens(string str, vector<string>& tokens) {
	split(tokens, str, " \t\n\f", false);
}

void mvk::extractTokens(string str, vector<uint32_t>& tokens) {
	vector<string> stringTokens;
	split(stringTokens, str, ".", false);
	for (auto& st : stringTokens) {
		tokens.push_back((uint32_t)strtol(st.c_str(), nullptr, 0));
	}
}

// Compares the specified characters ignoring case.
static bool compareIgnoringCase(unsigned char a, unsigned char b) {
	return tolower(a) == tolower(b);
}

bool mvk::equal(string const& a, string const& b, bool checkCase) {
	if (a.length() != b.length()) { return false; }
	return checkCase ? (a == b) : (equal(b.begin(), b.end(), a.begin(), compareIgnoringCase));
}

