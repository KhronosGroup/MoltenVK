/*
 * MVKOSExtensions.mm
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


#include "MVKOSExtensions.h"
#include "MVKLogging.h"
#include <mach/mach_time.h>

#import <Foundation/Foundation.h>


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
	MVKLogDebug("Initializing MoltenVK timestamping. Mach time: %llu. Time period: %d / %d = %.6f.",
				_mvkTimestampBase, timebase.numer, timebase.denom, _mvkTimestampPeriod);
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
	NSDictionary* env = [[NSProcessInfo processInfo] environment];
	NSString* envStr = env[@(varName.c_str())];
	if (pWasFound) { *pWasFound = envStr != nil; }
	return envStr ? envStr.UTF8String : "";
}

int64_t mvkGetEnvVarInt64(string varName, bool* pWasFound) {
	return strtoll(mvkGetEnvVar(varName, pWasFound).c_str(), NULL, 0);
}

bool mvkGetEnvVarBool(std::string varName, bool* pWasFound) {
	return mvkGetEnvVarInt64(varName, pWasFound) != 0;
}
