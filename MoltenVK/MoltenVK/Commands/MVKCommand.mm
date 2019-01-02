/*
 * MVKCommand.mm
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

#include "MVKCommand.h"
#include "MVKCommandPool.h"


#pragma mark -
#pragma mark MVKCommand

// TODO: Manage command resources in Command Pool
//	Opt 1: Leave arrays & rezs allocated in command, per current practice
//  Opt 2: Allocate arrays & rezs from pools in Command pool, and return in returnToPool

void MVKCommand::returnToPool() { _pool->returnObject(this); }

MVKCommandPool* MVKCommand::getCommandPool() { return _pool->getCommandPool(); }

MVKCommandEncodingPool* MVKCommand::getCommandEncodingPool() { return getCommandPool()->getCommandEncodingPool(); }

MVKDevice* MVKCommand::getDevice() { return getCommandPool()->getDevice(); }

id<MTLDevice> MVKCommand::getMTLDevice() { return getCommandPool()->getMTLDevice(); }

