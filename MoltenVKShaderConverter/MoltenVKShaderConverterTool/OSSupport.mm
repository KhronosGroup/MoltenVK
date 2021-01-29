/*
 * OSSupport.mm
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

#include "OSSupport.h"
#include "FileSupport.h"
#include "MoltenVKShaderConverterTool.h"
#include "MVKOSExtensions.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

using namespace std;
using namespace mvk;

template <typename FileProcessor>
bool mvk::iterateDirectory(const string& dirPath,
						   FileProcessor& fileProcessor,
						   bool isRecursive,
						   string& errMsg) {
	NSString* nsAbsDirPath = @(absolutePath(dirPath).data());
	NSFileManager* fileMgr = NSFileManager.defaultManager;
	BOOL isDir = false;
	BOOL exists = [fileMgr fileExistsAtPath: nsAbsDirPath isDirectory: &isDir];
	if ( !exists ) {
		errMsg = "Could not locate directory: " + absolutePath(dirPath);
		return false;
	}
	if ( !isDir ) {
		errMsg = absolutePath(dirPath) + " is not a directory.";
		return false;
	}

	bool success = true;
	NSDirectoryEnumerator* dirEnum = [fileMgr enumeratorAtPath: nsAbsDirPath];
	NSString* filePath;
	while ((filePath = dirEnum.nextObject)) {
		if ( !isRecursive ) { [dirEnum skipDescendants]; }
		NSString* absFilePath = [nsAbsDirPath stringByAppendingPathComponent: filePath];
		if( !fileProcessor.processFile(absFilePath.UTF8String) ) { success = false; }
	}
	return success;
}

// Concrete template implementation to allow MoltenVKShaderConverterTool to iterate the files in a directory.
template bool mvk::iterateDirectory<MoltenVKShaderConverterTool>(const string& dirPath,
																  MoltenVKShaderConverterTool& fileProcessor,
																  bool isRecursive,
																  string& errMsg);

bool mvk::compile(const string& mslSourceCode,
				  string& errMsg,
				  uint32_t mslVersionMajor,
				  uint32_t mslVersionMinor,
				  uint32_t mslVersionPoint) {

#define mslVer(MJ, MN, PT)	mslVersionMajor == MJ && mslVersionMinor == MN && mslVersionPoint == PT

	MTLLanguageVersion mslVerEnum = (MTLLanguageVersion)0;
#if MVK_XCODE_12
	if (mslVer(2, 3, 0)) {
		mslVerEnum = MTLLanguageVersion2_3;
	} else
#endif
	if (mslVer(2, 2, 0)) {
		mslVerEnum = MTLLanguageVersion2_2;
	} else if (mslVer(2, 1, 0)) {
		mslVerEnum = MTLLanguageVersion2_1;
	} else if (mslVer(2, 0, 0)) {
		mslVerEnum = MTLLanguageVersion2_0;
	} else if (mslVer(1, 2, 0)) {
		mslVerEnum = MTLLanguageVersion1_2;
	} else if (mslVer(1, 1, 0)) {
		mslVerEnum = MTLLanguageVersion1_1;
	}

	if ( !mslVerEnum ) {
		errMsg = [NSString stringWithFormat: @"%d.%d.%d is not a valid MSL version number on this device",
				  mslVersionMajor, mslVersionMinor, mslVersionPoint].UTF8String;
		return false;
	}

	@autoreleasepool {
		MTLCompileOptions* mtlCompileOptions  = [[MTLCompileOptions new] autorelease];
		mtlCompileOptions.languageVersion = mslVerEnum;
		NSError* err = nil;
		id<MTLLibrary> mtlLib = [[MTLCreateSystemDefaultDevice() newLibraryWithSource: @(mslSourceCode.c_str())
																			  options: mtlCompileOptions
																				error: &err] autorelease];
		errMsg = err ? [NSString stringWithFormat: @"(Error code %li):\n%@", (long)err.code, err.localizedDescription].UTF8String : "";
		return !!mtlLib;
	}
}
