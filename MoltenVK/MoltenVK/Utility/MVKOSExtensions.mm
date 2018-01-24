/*
 * MVKOSExtensions.mm
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


#include "MVKOSExtensions.h"
#include "MVKFoundation.h"

#import <mach/mach.h>
#import <mach/mach_host.h>


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


#pragma mark -
#pragma mark MTLTextureDescriptor

@implementation MTLTextureDescriptor (MoltenVK)

-(MTLTextureUsage) usageMVK {
	if ( [self respondsToSelector: @selector(usage)]) { return self.usage; }
	return MTLTextureUsageUnknown;
}

-(void) setUsageMVK: (MTLTextureUsage) usage {
	if ( [self respondsToSelector: @selector(setUsage:)]) { self.usage = usage; }
}

-(MTLStorageMode) storageModeMVK {
	if ( [self respondsToSelector: @selector(storageMode)]) { return self.storageMode; }
	return MTLStorageModeShared;
}

-(void) setStorageModeMVK: (MTLStorageMode) storageMode {
	if ( [self respondsToSelector: @selector(setStorageMode:)]) { self.storageMode = storageMode; }
}

@end


#pragma mark -
#pragma mark MTLSamplerDescriptor

@implementation MTLSamplerDescriptor (MoltenVK)

-(MTLCompareFunction) compareFunctionMVK {
	if ( [self respondsToSelector: @selector(compareFunction)]) { return self.compareFunction; }
	return MTLCompareFunctionNever;
}

-(void) setCompareFunctionMVK: (MTLCompareFunction) cmpFunc {
	if ( [self respondsToSelector: @selector(setCompareFunction:)]) { self.compareFunction = cmpFunc; }
}

@end


#pragma mark -
#pragma mark CAMetalLayer

@implementation CAMetalLayer (MoltenVK)

-(CGSize) updatedDrawableSizeMVK {
    CGSize drawSize = self.bounds.size;
    CGFloat scaleFactor = self.contentsScale;
    drawSize.width = trunc(drawSize.width * scaleFactor);
    drawSize.height = trunc(drawSize.height * scaleFactor);

    // Only update property value if it needs to be, in case
    // updating to same value causes internal reconfigurations.
    if ( !CGSizeEqualToSize(drawSize, self.drawableSize) ) {
        self.drawableSize = drawSize;
    }

    return drawSize;
}

@end


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


