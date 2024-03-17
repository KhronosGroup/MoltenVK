/*
 * MVKCountingEvent.h
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


#pragma once

#include <atomic>
#include <condition_variable>
#include <mutex>


#pragma mark Counting events

/**
 * A class that wraps a condition variable with a counter. Waits for this
 * object block as long as the counter is greater than zero. This class supports
 * the BasicLockable concept, meaning it can be used with std::lock_guard et al.
 */
class MVKCountingEvent {

public:

	/** Increments the counter, causing the wait() method to block. */
	void lock();

	/** Decrements the counter. Unblocks the wait() method if it reaches zero. */
	void unlock();

	/** Waits for the counter to reach zero. */
	void wait();

	/** Constructor. */
	MVKCountingEvent() : _counter(0) {}

private:

	std::atomic<uint32_t> _counter;
	std::mutex _lock;
	std::condition_variable _cond;
	std::string _name;

};

