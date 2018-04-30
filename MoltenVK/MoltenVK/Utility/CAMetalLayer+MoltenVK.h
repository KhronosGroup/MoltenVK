/*
 * CAMetalLayer+MoltenVK.h
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


#import <QuartzCore/QuartzCore.h>

/** Extensions to CAMetalLayer to support MoltenVK. */
@interface CAMetalLayer (MoltenVK)

/**
 * Ensures the drawableSize property of this layer is up to date, by combining the size
 * of the bounds property and the contentScale property, and returns the updated value.
 */
-(CGSize) updatedDrawableSizeMVK;

/**
 * Replacement for the displaySyncEnabled property.
 *
 * This property allows support under all OS versions. Delegates to the displaySyncEnabled
 * property if it is available. otherwise, returns YES when read and does nothing when set.
 */
@property(nonatomic, readwrite) BOOL displaySyncEnabledMVK;

@end
