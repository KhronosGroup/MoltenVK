/*
 * DemoViewController.mm
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

#import "DemoViewController.h"


#pragma mark -
#pragma mark VulkanSamples extension for iOS & macOS support

#include "Samples.h"			// The LunarG VulkanSamples code


static UIView* sampleView;		// Global variable to pass UIView to LunarG sample code

/** 
 * Called from sample. 
 * Initialize sample from view, and resize view in accordance with the sample. 
 */
void init_window(struct sample_info &info) {
	info.window = sampleView.layer;
	sampleView.bounds = CGRectMake(0, 0, info.width, info.height);
}

/** Called from sample. Return path to resource folder. */
std::string get_base_data_dir() {
	return [NSBundle.mainBundle.resourcePath stringByAppendingString: @"/"].UTF8String;
}


#pragma mark -
#pragma mark DemoViewController

@implementation DemoViewController {}

/** Since this is a single-view app, init Vulkan when the view is loaded. */
-(void) viewDidLoad {
	[super viewDidLoad];

	sampleView = self.view;			// Pass the view to the sample code
	sample_main(0, NULL);			// Run the LunarG sample
}

@end


#pragma mark -
#pragma mark DemoView

@implementation DemoView

/** Returns a Metal-compatible layer. */
+(Class) layerClass { return [CAMetalLayer class]; }

@end

