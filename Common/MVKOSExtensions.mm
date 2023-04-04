/*
 * MVKOSExtensions.mm
 *
 * Copyright (c) 2015-2023 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#import <Foundation/Foundation.h>


using namespace std;

MVKOSVersion mvkOSVersion() {
	static MVKOSVersion _mvkOSVersion = 0;
	if ( !_mvkOSVersion ) {
		NSOperatingSystemVersion osVer = [[NSProcessInfo processInfo] operatingSystemVersion];
		_mvkOSVersion = mvkMakeOSVersion((uint32_t)osVer.majorVersion, (uint32_t)osVer.minorVersion, (uint32_t)osVer.patchVersion);
	}
	return _mvkOSVersion;
}

static uint64_t _mvkTimestampBase;
static double _mvkTimestampPeriod;

uint64_t mvkGetTimestamp() { return mach_absolute_time() - _mvkTimestampBase; }

double mvkGetTimestampPeriod() { return _mvkTimestampPeriod; }

double mvkGetElapsedMilliseconds(uint64_t startTimestamp, uint64_t endTimestamp) {
	if (endTimestamp == 0) { endTimestamp = mvkGetTimestamp(); }
	return (double)(endTimestamp - startTimestamp) * _mvkTimestampPeriod / 1e6;
}

// Initialize timestamping capabilities on app startup.
//Called automatically when the framework is loaded and initialized.
static bool _mvkTimestampsInitialized = false;
__attribute__((constructor)) static void MVKInitTimestamps() {
	if (_mvkTimestampsInitialized ) { return; }
	_mvkTimestampsInitialized = true;

	_mvkTimestampBase = mach_absolute_time();
	mach_timebase_info_data_t timebase;
	mach_timebase_info(&timebase);
	_mvkTimestampPeriod = (double)timebase.numer / (double)timebase.denom;
}

void mvkDispatchToMainAndWait(dispatch_block_t block) {
	if (NSThread.isMainThread) {
		block();
	} else {
		dispatch_sync(dispatch_get_main_queue(), block);
	}
}


#pragma mark -
#pragma mark Process environment

string mvkGetEnvVar(string varName, bool* pWasFound) {
	@autoreleasepool {
		NSDictionary* nsEnv = [[NSProcessInfo processInfo] environment];
		NSString* envStr = nsEnv[@(varName.c_str())];
		if (pWasFound) { *pWasFound = envStr != nil; }
		return envStr ? envStr.UTF8String : "";
	}
}

int64_t mvkGetEnvVarInt64(string varName, bool* pWasFound) {
	return strtoll(mvkGetEnvVar(varName, pWasFound).c_str(), NULL, 0);
}

bool mvkGetEnvVarBool(std::string varName, bool* pWasFound) {
	return mvkGetEnvVarInt64(varName, pWasFound) != 0;
}


#pragma mark -
#pragma mark System memory

uint64_t mvkGetSystemMemorySize() {
#if MVK_MACOS_OR_IOS
	mach_msg_type_number_t host_size = HOST_BASIC_INFO_COUNT;
	host_basic_info_data_t info;
	if (host_info(mach_host_self(), HOST_BASIC_INFO, (host_info_t)&info, &host_size) == KERN_SUCCESS) {
		return info.max_mem;
	}
	return 0;
#endif
#if MVK_TVOS
	return 0;
#endif
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
		return task_vm_info.phys_footprint;
	}
	return 0;
}

uint64_t mvkGetHostMemoryPageSize() { return sysconf(_SC_PAGESIZE); }

