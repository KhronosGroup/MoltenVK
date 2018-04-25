/*
 * MVKOSExtensions.mm
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


#include "MVKOSExtensions.h"
#include "MVKFoundation.h"

#include <vector>
#include <mach/mach_host.h>
#include <mach/mach_time.h>

#if MVK_MACOS
#import <CoreFoundation/CFData.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOKitKeys.h>
#endif

#if MVK_IOS
#import <UIKit/UIDevice.h>
#endif

using namespace std;

static const MVKOSVersion kMVKOSVersionUnknown = 0.0f;
static MVKOSVersion _mvkOSVersion = kMVKOSVersionUnknown;
MVKOSVersion mvkOSVersion() {
    if (_mvkOSVersion == kMVKOSVersionUnknown) {
        NSOperatingSystemVersion osVer = [[NSProcessInfo processInfo] operatingSystemVersion];
        float maj = osVer.majorVersion;
        float min = osVer.minorVersion;
        float pat = osVer.patchVersion;
        _mvkOSVersion = maj + (min / 100.0f) +  + (pat / 10000.0f);
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


#pragma mark Library initialization

/**
 * Initialize timestamping capabilities on app startup.
 * Called automatically when the framework is loaded and initialized.
 */
static bool _mvkTimestampsInitialized = false;
__attribute__((constructor)) static void MVKInitTimestamps() {
	if (_mvkTimestampsInitialized ) { return; }
	_mvkTimestampsInitialized = true;

	_mvkTimestampBase = mach_absolute_time();
	mach_timebase_info_data_t timebase;
	mach_timebase_info(&timebase);
	_mvkTimestampPeriod = (double)timebase.numer / (double)timebase.denom;
	MVKLogDebug("Initializing MoltenVK timestamping. Mach time: %llu. Time period: %d / %d = %.6f.", _mvkTimestampBase, timebase.numer, timebase.denom, _mvkTimestampPeriod);

}


#pragma mark -
#pragma mark MTLDevice

uint64_t mvkRecommendedMaxWorkingSetSize(id<MTLDevice> mtlDevice) {

#if MVK_MACOS
	if ( [mtlDevice respondsToSelector: @selector(recommendedMaxWorkingSetSize)]) {
		return mtlDevice.recommendedMaxWorkingSetSize;
	}
#endif
#if MVK_IOS
	// GPU and CPU use shared memory. Estimate the current free memory in the system.
	mach_port_t host_port;
	mach_msg_type_number_t host_size;
	vm_size_t pagesize;
	host_port = mach_host_self();
	host_size = sizeof(vm_statistics_data_t) / sizeof(integer_t);
	host_page_size(host_port, &pagesize);
	vm_statistics_data_t vm_stat;
	if (host_statistics(host_port, HOST_VM_INFO, (host_info_t)&vm_stat, &host_size) == KERN_SUCCESS ) {
		return vm_stat.free_count * pagesize;
	}
#endif

	return 128 * MEBI;		// Conservative minimum for macOS GPU's & iOS shared memory
}

#if MVK_MACOS

static uint32_t mvkGetEntryProperty(io_registry_entry_t entry, CFStringRef propertyName) {

	uint32_t value = 0;

	CFTypeRef cfProp = IORegistryEntrySearchCFProperty(entry,
													   kIOServicePlane,
													   propertyName,
													   kCFAllocatorDefault,
													   kIORegistryIterateRecursively |
													   kIORegistryIterateParents);
	if (cfProp) {
		const uint32_t* pValue = reinterpret_cast<const uint32_t*>(CFDataGetBytePtr((CFDataRef)cfProp));
		if (pValue) { value = *pValue; }
		CFRelease(cfProp);
	}

	return value;
}

void mvkPopulateGPUInfo(VkPhysicalDeviceProperties& devProps, id<MTLDevice> mtlDevice) {

	static const uint32_t kIntelVendorId = 0x8086;
	bool isFound = false;

	bool isIntegrated = mtlDevice.isLowPower;
	devProps.deviceType = isIntegrated ? VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU : VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU;
	strlcpy(devProps.deviceName, mtlDevice.name.UTF8String, VK_MAX_PHYSICAL_DEVICE_NAME_SIZE);

	// Iterate all GPU's, looking for a match.
	// The match dictionary is consumed by IOServiceGetMatchingServices and does not need to be released
	io_iterator_t entryIterator;
	if (IOServiceGetMatchingServices(kIOMasterPortDefault,
									 IOServiceMatching("IOPCIDevice"),
									 &entryIterator) == kIOReturnSuccess) {
		io_registry_entry_t entry;
		while ( !isFound && (entry = IOIteratorNext(entryIterator)) ) {
			if (mvkGetEntryProperty(entry, CFSTR("class-code")) == 0x30000) {	// 0x30000 : DISPLAY_VGA

				// The Intel GPU will always be marked as integrated.
				// Return on a match of either Intel && low power, or non-Intel and non-low-power.
				uint32_t vendorID = mvkGetEntryProperty(entry, CFSTR("vendor-id"));
				if ( (vendorID == kIntelVendorId) == isIntegrated) {
					isFound = true;
					devProps.vendorID = vendorID;
					devProps.deviceID = mvkGetEntryProperty(entry, CFSTR("device-id"));
				}
			}
		}
		IOObjectRelease(entryIterator);
	}
}

#endif	//MVK_MACOS

#if MVK_IOS

void mvkPopulateGPUInfo(VkPhysicalDeviceProperties& devProps, id<MTLDevice> mtlDevice) {
	// For iOS devices, the Device ID is the SoC model (A8, A10X...), in the hex form 0xaMMX, where
	//"a" is the Apple brand, MM is the SoC model number (8, 10...) and X is 1 for X version, 0 for other.
	NSUInteger coreCnt = NSProcessInfo.processInfo.processorCount;
	uint32_t devID = 0xa070;
	if ([mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily4_v1]) {
		devID = 0xa110;
	} else if ([mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily3_v1]) {
		devID = coreCnt > 2 ? 0xa101 : 0xa100;
	} else if ([mtlDevice supportsFeatureSet: MTLFeatureSet_iOS_GPUFamily2_v1]) {
		devID = coreCnt > 2 ? 0xa081 : 0xa080;
	}

	devProps.vendorID = 0x0000106b;	// Apple's PCI ID
	devProps.deviceID = devID;
	devProps.deviceType = VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU;
	strlcpy(devProps.deviceName, mtlDevice.name.UTF8String, VK_MAX_PHYSICAL_DEVICE_NAME_SIZE);
}
#endif	//MVK_IOS


