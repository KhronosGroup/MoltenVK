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
#import <QuartzCore/CAMetalLayer.h>

#include "ShellMVK.h"
#include "Hologram.h"


#pragma mark -
#pragma mark DemoViewController

@implementation DemoViewController {
	CVDisplayLinkRef	_displayLink;
	ShellMVK* _shell;
    Game* _game;
}

-(void) dealloc {
    delete _shell;
    delete _game;
	CVDisplayLinkRelease(_displayLink);
	[super dealloc];
}

/** Since this is a single-view app, initialize Vulkan during view loading. */
-(void) viewDidLoad {
	[super viewDidLoad];

	self.view.wantsLayer = YES;		// Back the view with a layer created by the makeBackingLayer method.

    std::vector<std::string> args;
//  args.push_back("-p");           // Uncomment to use push constants
//  args.push_back("-s");           // Uncomment to use a single thread
    _game = new Hologram(args);

    _shell = new ShellMVK(*_game);
    _shell->run(self.view);

	CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
	CVDisplayLinkSetOutputCallback(_displayLink, &DisplayLinkCallback, _shell);
	CVDisplayLinkStart(_displayLink);
}


#pragma mark Display loop callback function

/** Rendering loop callback function for use with a CVDisplayLink. */
static CVReturn DisplayLinkCallback(CVDisplayLinkRef displayLink,
									const CVTimeStamp* now,
									const CVTimeStamp* outputTime,
									CVOptionFlags flagsIn,
									CVOptionFlags* flagsOut,
									void* target) {
   ((ShellMVK*)target)->update_and_draw();
	return kCVReturnSuccess;
}

-(void) viewDidAppear {
    self.view.window.initialFirstResponder = self.view;
}

// Delegated from the view as first responder.
-(void) keyDown:(NSEvent*) theEvent {
    Game::Key key;
    switch (theEvent.keyCode) {
        case 53:
            key = Game::KEY_ESC;
            break;
        case 126:
            key = Game::KEY_UP;
            break;
        case 125:
            key = Game::KEY_DOWN;
            break;
        case 49:
            key = Game::KEY_SPACE;
            break;
        case 3:
            key = Game::KEY_F;
            break;
        default:
            key = Game::KEY_UNKNOWN;
            break;
    }

    _game->on_key(key);
}

@end


#pragma mark -
#pragma mark DemoView

@implementation DemoView

/** Indicates that the view wants to draw using the backing layer instead of using drawRect:.  */
-(BOOL) wantsUpdateLayer { return YES; }

/** Returns a Metal-compatible layer. */
+(Class) layerClass { return [CAMetalLayer class]; }

/** If the wantsLayer property is set to YES, this method will be invoked to return a layer instance. */
-(CALayer*) makeBackingLayer {
	CALayer* layer = [self.class.layerClass layer];
	CGSize viewScale = [self convertSizeToBacking: CGSizeMake(1.0, 1.0)];
	layer.contentsScale = MIN(viewScale.width, viewScale.height);
	return layer;
}

-(BOOL) acceptsFirstResponder { return YES; }

@end
