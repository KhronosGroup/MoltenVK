/*
 * DirectorySupport.mm
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

#include "DirectorySupport.h"
#include "FileSupport.h"
#include "MoltenVKShaderConverterTool.h"

#import <Foundation/Foundation.h>

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

	NSDirectoryEnumerator* dirEnum = [fileMgr enumeratorAtPath: nsAbsDirPath];
	NSString* filePath;
	while ((filePath = dirEnum.nextObject)) {
		if ( !isRecursive ) { [dirEnum skipDescendants]; }
		NSString* absFilePath = [nsAbsDirPath stringByAppendingPathComponent: filePath];
		if(fileProcessor.processFile(absFilePath.UTF8String)) { return true; }
	}
	return true;
}

/** Concrete template implementation to allow MoltenVKShaderConverterTool to iterate the files in a directory. */
template bool mvk::iterateDirectory<MoltenVKShaderConverterTool>(const string& dirPath,
																  MoltenVKShaderConverterTool& fileProcessor,
																  bool isRecursive,
																  string& errMsg);

