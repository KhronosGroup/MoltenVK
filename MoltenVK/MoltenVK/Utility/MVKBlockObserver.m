/*
 * MVKBlockObserver.m
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


#import "MVKBlockObserver.h"


@implementation MVKBlockObserver

- (instancetype)initWithBlock:(MVKKeyValueObserverBlock) block {
	if ((self = [super init])) {
		_block = [block copy];
	}
	return self;
}

- (instancetype)initWithBlock:(MVKKeyValueObserverBlock) block forObject: object atKeyPath:(NSString*) keyPath {
	if ((self = [super init])) {
		_block = [block copy];
		[self startObservingObject: object atKeyPath: keyPath];
	}
	return self;
}

+ (instancetype)observerWithBlock:(MVKKeyValueObserverBlock) block {
	return [[self alloc] initWithBlock: block];
}

+ (instancetype)observerWithBlock:(MVKKeyValueObserverBlock) block forObject: object atKeyPath:(NSString*) keyPath {
	return [[self alloc] initWithBlock: block forObject: object atKeyPath: keyPath];
}

- (void)dealloc {
	[self stopObserving];
	[super dealloc];
}

- (void)observeValueForKeyPath:(NSString*) path ofObject: object change:(NSDictionary*) changeDict context:(void*) context {
	_block(path, object, changeDict, context);
}

- (void)startObservingObject: object atKeyPath:(NSString*) path {
	if ( !_target ) {
		_target = [object retain];
		_keyPath = [path copy];
		[_target addObserver: self forKeyPath: _keyPath options: 0 context: NULL];
	}
}

- (void)stopObserving {
	[_target removeObserver: self forKeyPath: _keyPath context: NULL];
	[_target release];
	[_keyPath release];
	_target = nil;
	_keyPath = nil;
}

@end

