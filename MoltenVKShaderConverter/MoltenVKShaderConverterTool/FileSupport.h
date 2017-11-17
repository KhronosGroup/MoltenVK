/*
 * FileSupport.h
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

#pragma once


#include <string>
#include <vector>


namespace mvk {


	/** Returns an absolute path from the specified path, which may be absolute or relative. */
	std::string absolutePath(const std::string& path);

	/** Returns the last component of the specified path. */
	std::string lastPathComponent(const std::string& path);

	/** Returns the extension component (after the .) of the specified path. */
	std::string pathExtension(const std::string& path);

	/** Returns whether the specified path exists and is a readable file. */
	bool canReadFile(const std::string& path);

	/** Returns whether the specified path is a file that is writable. */
	bool canWriteFile(const std::string& path);

	/** 
	 * Returns a copy of the specified path, with the extension of the path set or changed 
	 * to the specified extension. If includeOrigPathExtn is true, the original file extension
	 * of the path will be appended to the file name (before the new separator), separated
	 * by origPathExtnSep string (eg. myshader.vsh -> myshader_vsh.spv).
	 */
	std::string pathWithExtension(const std::string& path,
								  const std::string pathExtn,
								  bool includeOrigPathExtn,
								  const std::string origPathExtnSep);

	/** 
	 * Reads the contents of the specified file path into the specified contents vector.
	 * and returns whether the file read was successful.
	 *
	 * If successful, copies the file contents into the contents vector and returns true.
	 * If unsuccessful, places an explanatory error message in the errMsg string and returns false.
	 * If file was partially read, copies what could be read into the contents vector, places an
	 * error message in errMsg, and returns false.
	 */
	bool readFile(const std::string& path, std::vector<char>& contents, std::string& errMsg);

	/**
	 * Writes the contents of the specified contents string to the file in the specified file 
	 * path, creating the file if necessary, and returns whether the file write was successful.
	 *
	 * If successful, overwrites the entire contents of the file and returns true.
	 * If unsuccessful, places an explanatory error message in the errMsg string and returns false.
	 */
	bool writeFile(const std::string& path, const std::vector<char>& contents, std::string& errMsg);

	/** 
	 * Iterates through the directory at the specified path, which may be either a relative
	 * or absolute path, and calls the processFile(std::string filePath) member function
	 * on the fileProcessor for each file in the directory. If the isRecursive parameter
	 * is true, the iteration will include all files in all sub-directories as well.
	 * The processFile(std::string filePath) member function on the fileProcessor should
	 * return true to cause the processing of any further files to halt, and this function
	 * to return, or should return false to allow further files to be iterated.
	 * Returns false if the directory could not be found or iterated. Returns true otherwise.
	 */
	template <typename FileProcessor>
	bool iterateDirectory(const std::string& dirPath,
						  FileProcessor& fileProcessor,
						  bool isRecursive,
						  std::string& errMsg);

}
