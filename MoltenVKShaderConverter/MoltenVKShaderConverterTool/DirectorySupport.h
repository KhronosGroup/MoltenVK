/*
 * DirectorySupport.h
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


#include <string>


namespace mvk {

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
