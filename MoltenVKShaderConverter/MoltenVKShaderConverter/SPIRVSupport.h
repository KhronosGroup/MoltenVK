/*
 * SPIRVSupport.h
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

#ifndef __SPIRVSupport_h_
#define __SPIRVSupport_h_ 1

#include <string>
#include <vector>

namespace mvk {

	/** Appends the SPIR-V in human-readable form to the specified log string. */
	void logSPIRV(std::vector<uint32_t>& spirv, std::string& spvLog);

	/** Converts the SPIR-V code to an array of bytes (suitable for writing to a file). */
	void spirvToBytes(const std::vector<uint32_t>& spv, std::vector<char>& bytes);

	/**
	 * Converts the SPIR-V code to header content (suitable for writing to a file)
	 * with the SPIR-V content assigned to a named uint32_t variable.
	 */
	void spirvToHeaderBytes(const std::vector<uint32_t>& spv, std::vector<char>& bytes, const std::string& varName);

	/** Converts an array of bytes (as read from a file) to SPIR-V code. */
	void bytesToSPIRV(const std::vector<char>& bytes, std::vector<uint32_t>& spv);

	/**
	 * Ensures that the specified SPIR-V code has the correct endianness for this system,
	 * and converts it in place if necessary. This can be used after loading SPIR-V code
	 * from a file that may have been encoded on a system with the opposite endianness.
	 *
	 * This function tests for the SPIR-V magic number (in both endian states) to determine
	 * whether conversion is required. It will not convert arrays of uint32_t values that
	 * are not SPIR-V code.
	 *
	 * Returns whether the endianness was changed.
	 */
	bool ensureSPIRVEndianness(std::vector<uint32_t>& spv);

}
#endif
