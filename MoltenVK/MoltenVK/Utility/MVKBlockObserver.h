/*
 * MVKBlockObserver.h
 *
 * Copyright (c) 2019-2021 Chip Davis for CodeWeavers
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


#import <Foundation/NSObject.h>
#import <Foundation/NSKeyValueObserving.h>


#pragma mark MVKBlockObserver

typedef void (^MVKKeyValueObserverBlock)(NSString* keyPath, id object, NSDictionary* changeDict, void* context);

/** Class that calls a block on any key-value observation callback. */
@interface MVKBlockObserver : NSObject {
	MVKKeyValueObserverBlock _block;
	id _target;
	NSString* _keyPath;
}

- (instancetype)initWithBlock:(MVKKeyValueObserverBlock) block;
- (instancetype)initWithBlock:(MVKKeyValueObserverBlock) block forObject: object atKeyPath:(NSString*) keyPath;

+ (instancetype)observerWithBlock:(MVKKeyValueObserverBlock) block;
+ (instancetype)observerWithBlock:(MVKKeyValueObserverBlock) block forObject: object atKeyPath:(NSString*) keyPath;

- (void)observeValueForKeyPath:(NSString*) path ofObject: object change:(NSDictionary*) changeDict context: (void*)context;

- (void)startObservingObject: object atKeyPath:(NSString*) keyPath;
- (void)stopObserving;

@end

