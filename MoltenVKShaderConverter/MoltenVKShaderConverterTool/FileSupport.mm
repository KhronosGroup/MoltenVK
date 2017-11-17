/*
 * FileSupport.mm
 *
 * Copyright (c) 2014-2017 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "FileSupport.h"
#include "MoltenVKShaderConverterTool.h"
#include <fstream>

#import <Foundation/Foundation.h>

using namespace std;
using namespace mvk;


string mvk::absolutePath(const string& path) {
	NSString* nsPath = @(path.data());
	if(nsPath.absolutePath) return path;
	nsPath = [NSFileManager.defaultManager.currentDirectoryPath stringByAppendingPathComponent: nsPath];
	return nsPath.UTF8String;
}

string mvk::lastPathComponent(const string& path) {
	NSString* nsPath = @(path.data());
	return nsPath.lastPathComponent.UTF8String;
}

string mvk::pathExtension(const string& path) {
	NSString* nsPath = @(path.data());
	return nsPath.pathExtension.UTF8String;
}

string mvk::pathWithExtension(const string& path,
									  const string pathExtn,
									  bool includeOrigPathExtn,
									  const string origPathExtnSep) {
	NSString* nsPath = @(path.data());
	NSString* currExtn = nsPath.pathExtension;
	nsPath = nsPath.stringByDeletingPathExtension;
	if (includeOrigPathExtn) {
		nsPath = [nsPath stringByAppendingString: @(origPathExtnSep.data())];
		nsPath = [nsPath stringByAppendingString: currExtn];
	}
	nsPath = [nsPath stringByAppendingPathExtension: @(pathExtn.data())];
	return nsPath.UTF8String;
}

bool mvk::canReadFile(const string& path) {
	NSString* nsAbsDirPath = @(absolutePath(path).data());
	NSFileManager* fileMgr = NSFileManager.defaultManager;
	BOOL isDir = false;
	BOOL exists = [fileMgr fileExistsAtPath: nsAbsDirPath isDirectory: &isDir];
	return exists && !isDir && [fileMgr isReadableFileAtPath: nsAbsDirPath];
}

bool mvk::canWriteFile(const string& path) {
	NSString* nsAbsDirPath = @(absolutePath(path).data());
	NSFileManager* fileMgr = NSFileManager.defaultManager;
	BOOL isDir = false;
	BOOL exists = [fileMgr fileExistsAtPath: nsAbsDirPath isDirectory: &isDir];
	return !exists || (!isDir && [fileMgr isWritableFileAtPath: nsAbsDirPath]);
}

bool mvk::readFile(const string& path, vector<char>& contents, string& errMsg) {

	contents.clear();	// Ensure contents are empty in case we leave early
	errMsg.clear();		// Assume success, so clear the error message

	string absPath = absolutePath(path);

	if ( !canReadFile(absPath) ) {
		errMsg = absPath + " is not a readable file";
		return false;
	}

	ifstream inFile(absPath, (ifstream::in | ifstream::binary));		// Stream closed when destroyed
	if (inFile.fail()) {
		errMsg = "Could not open file for reading: " + absPath;
		return false;
	}

	// Get file length
	inFile.seekg (0, inFile.end);
	streampos filePos = inFile.tellg();
	inFile.seekg (0, inFile.beg);
	size_t fileLen = filePos;

	// Read the contents of file into the vector
	contents.reserve(fileLen);
	char c;
	while (inFile.get(c))  { contents.push_back(c); }

	// Check if successful
	if (inFile.bad()) {
		errMsg = "Could not read entire contents of file: " + absPath;
		return false;
	}

	return true;
}

bool mvk::writeFile(const string& path, const vector<char>& contents, string& errMsg) {

	errMsg.clear();		// Assume success, so clear the error message

	string absPath = absolutePath(path);

	if ( !canWriteFile(path) ) {
		errMsg = "Cannot write to file:" + absPath;
		return false;
	}

	ofstream outFile(absPath);		// Stream closed when destroyed
	if (outFile.fail()) {
		errMsg = "Could not open file for writing: " + absPath;
		return false;
	}

	for (auto iter = contents.begin(), end = contents.end(); iter != end; iter++) {
		outFile.put(*iter);
		if (outFile.bad()) {
			errMsg = "Could not write entire contents of file: " + absPath;
			return false;
		}
	}
	return true;
}

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

