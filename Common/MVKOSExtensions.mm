/*
 * MVKOSExtensions.mm
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


#include "MVKOSExtensions.h"
#include "MVKCommonEnvironment.h"
#include <mach/mach_host.h>
#include <mach/mach_time.h>
#include <mach/task.h>
#include <os/proc.h>
#include <sys/sysctl.h>

#import <Foundation/Foundation.h>


using namespace std;


#pragma mark -
#pragma mark Operating System versions

MVKOSVersion mvkOSVersion() {
	static MVKOSVersion _mvkOSVersion = 0;
	if ( !_mvkOSVersion ) {
		NSOperatingSystemVersion osVer = [[NSProcessInfo processInfo] operatingSystemVersion];
		_mvkOSVersion = mvkMakeOSVersion((uint32_t)osVer.majorVersion, (uint32_t)osVer.minorVersion, (uint32_t)osVer.patchVersion);
	}
	return _mvkOSVersion;
}


#pragma mark -
#pragma mark Timestamps

static mach_timebase_info_data_t _mvkMachTimebase;

uint64_t mvkGetTimestamp() { return mach_absolute_time(); }

uint64_t mvkGetRuntimeNanoseconds() { return mach_absolute_time() * _mvkMachTimebase.numer / _mvkMachTimebase.denom; }

uint64_t mvkGetContinuousNanoseconds() { return mach_continuous_time() * _mvkMachTimebase.numer / _mvkMachTimebase.denom; }

uint64_t mvkGetElapsedNanoseconds(uint64_t startTimestamp, uint64_t endTimestamp) {
	if (endTimestamp == 0) { endTimestamp = mvkGetTimestamp(); }
	return (endTimestamp - startTimestamp) * _mvkMachTimebase.numer / _mvkMachTimebase.denom;
}

double mvkGetElapsedMilliseconds(uint64_t startTimestamp, uint64_t endTimestamp) {
	return mvkGetElapsedNanoseconds(startTimestamp, endTimestamp) / 1e6;
}

// Initialize timestamp capabilities on app startup.
// Called automatically when the framework is loaded and initialized.
static bool _mvkTimestampsInitialized = false;
__attribute__((constructor)) static void MVKInitTimestamps() {
	if (_mvkTimestampsInitialized ) { return; }
	_mvkTimestampsInitialized = true;

	mach_timebase_info(&_mvkMachTimebase);
}


#pragma mark -
#pragma mark Process environment

bool mvkGetEnvVar(const char* varName, string& evStr) {
	@autoreleasepool {
		NSDictionary* nsEnv = [[NSProcessInfo processInfo] environment];
		NSString* nsStr = nsEnv[@(varName)];
		if (nsStr) { evStr = nsStr.UTF8String; }
		return nsStr != nil;
	}
}

const char* mvkGetEnvVarString(const char* varName, string& evStr, const char* defaultValue) {
	return mvkGetEnvVar(varName, evStr) ? evStr.c_str() : defaultValue;
}

double mvkGetEnvVarNumber(const char* varName, double defaultValue) {
	string evStr;
	return mvkGetEnvVar(varName, evStr) ? strtod(evStr.c_str(), nullptr) : defaultValue;
}


#pragma mark -
#pragma mark System memory

uint64_t mvkGetSystemMemorySize() {
	uint64_t host_memsize = 0;
	size_t size = sizeof(host_memsize);
	if (sysctlbyname("hw.memsize", &host_memsize, &size, NULL, 0) == KERN_SUCCESS) {
		return host_memsize;
	}
	return 0;
}

uint64_t mvkGetAvailableMemorySize() {
#if MVK_IOS_OR_TVOS
	if (mvkOSVersionIsAtLeast(13.0)) { return os_proc_available_memory(); }
#endif
	mach_port_t host_port;
	mach_msg_type_number_t host_size;
	vm_size_t pagesize;
	host_port = mach_host_self();
	host_size = HOST_VM_INFO_COUNT;
	host_page_size(host_port, &pagesize);
	vm_statistics_data_t vm_stat;
	if (host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size) == KERN_SUCCESS ) {
		return vm_stat.free_count * pagesize;
	}
	return 0;
}

uint64_t mvkGetUsedMemorySize() {
	task_vm_info_data_t task_vm_info;
	mach_msg_type_number_t task_size = TASK_VM_INFO_COUNT;
	if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&task_vm_info, &task_size) == KERN_SUCCESS) {
#ifdef TASK_VM_INFO_REV3_COUNT	// check for rev3 version of task_vm_info
		if (task_size >= TASK_VM_INFO_REV3_COUNT) {
			return task_vm_info.ledger_tag_graphics_footprint;
		}
		else
#endif
			return task_vm_info.phys_footprint;
	}
	return 0;
}

uint64_t mvkGetHostMemoryPageSize() { return sysconf(_SC_PAGESIZE); }


#pragma mark -
#pragma mark Threading

/** Returns the amount of avaliable CPU cores. */
uint32_t mvkGetAvaliableCPUCores() {
    return (uint32_t)[[NSProcessInfo processInfo] activeProcessorCount];
}

void mvkDispatchToMainAndWait(dispatch_block_t block) {
	if (NSThread.isMainThread) {
		block();
	} else {
		dispatch_sync(dispatch_get_main_queue(), block);
	}
}
