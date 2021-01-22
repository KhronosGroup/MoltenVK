/*
 * MTLTextureDescriptor+MoltenVK.m
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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


#include "MTLTextureDescriptor+MoltenVK.h"

@implementation MTLTextureDescriptor (MoltenVK)

-(MTLTextureUsage) usageMVK {
	if ( [self respondsToSelector: @selector(usage)] ) { return self.usage; }
	return MTLTextureUsageUnknown;
}

-(void) setUsageMVK: (MTLTextureUsage) usage {
	if ( [self respondsToSelector: @selector(setUsage:)] ) { self.usage = usage; }
}

-(MTLStorageMode) storageModeMVK {
	if ( [self respondsToSelector: @selector(storageMode)] ) { return self.storageMode; }
	return MTLStorageModeShared;
}

-(void) setStorageModeMVK: (MTLStorageMode) storageMode {
	if ( [self respondsToSelector: @selector(setStorageMode:)] ) { self.storageMode = storageMode; }
}

@end
