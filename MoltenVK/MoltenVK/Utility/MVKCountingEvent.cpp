/*
 * MVKCountingEvent.cpp
 *
 * Copyright (c) 2019 Chip Davis for CodeWeavers
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


#include "MVKCountingEvent.h"

using namespace std;


void MVKCountingEvent::lock() {
	lock_guard<mutex> lock(_lock);
	++_counter;
}

void MVKCountingEvent::unlock() {
	lock_guard<mutex> lock(_lock);
	if (--_counter == 0)
		_cond.notify_all();
}

void MVKCountingEvent::wait() {
	unique_lock<mutex> lock(_lock);
	_cond.wait(lock, [this]{ return _counter == 0; });
}

