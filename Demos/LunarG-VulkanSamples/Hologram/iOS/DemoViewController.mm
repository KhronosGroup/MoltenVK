/*
 * DemoViewController.mm
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

#import "DemoViewController.h"

#include "ShellMVK.h"
#include "Hologram.h"


#pragma mark -
#pragma mark DemoViewController

@implementation DemoViewController {
	CADisplayLink* _displayLink;
    ShellMVK* _shell;
    Game* _game;
}

-(void) dealloc {
    delete _shell;
    delete _game;
	[_displayLink release];
	[super dealloc];
}

/** Since this is a single-view app, init Vulkan when the view is loaded. */
-(void) viewDidLoad {
	[super viewDidLoad];

	self.view.contentScaleFactor = UIScreen.mainScreen.nativeScale;

    std::vector<std::string> args;
    args.push_back("-p");           // Use push constants
//  args.push_back("-s");           // Use a single thread
    _game = new Hologram(args);

    _shell = new ShellMVK(*_game);
    _shell->run(self.view.layer);

	uint32_t fps = 60;
	_displayLink = [CADisplayLink displayLinkWithTarget: self selector: @selector(renderLoop)];
	[_displayLink setFrameInterval: 60 / fps];
	[_displayLink addToRunLoop: NSRunLoop.currentRunLoop forMode: NSDefaultRunLoopMode];
}

-(void) renderLoop {
    _shell->update_and_draw();
}

@end


#pragma mark -
#pragma mark DemoView

@implementation DemoView

/** Returns a Metal-compatible layer. */
+(Class) layerClass { return [CAMetalLayer class]; }

@end

