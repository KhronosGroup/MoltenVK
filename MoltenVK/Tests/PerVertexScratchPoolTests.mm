// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
// CPU only: the PerVertex scratch pool (MVK_CONFIG_PERVERTEX_SCRATCH_POOL=1). Size classes, storage modes, return
// to the pool only at the last reference (the completed handler of keepPerVertexScratchResident), residency once per
// created buffer, and the indirect and TES requests kept out of the pool. No Metal device is created.
#include "MVKPerVertexScratch.h"
#include <cassert>
#include <cstdio>
#include <set>

static unsigned liveBuffers;
static uint8_t bytes[1 << 16];

@interface PoolTestBuffer : NSObject {
@public
	NSUInteger _length;
	bool _shared;
}
@end
@implementation PoolTestBuffer
- (NSUInteger)length { return _length; }
- (void*)contents { return _shared ? bytes : nullptr; }
- (void)dealloc { --liveBuffers; [super dealloc]; }
@end

@interface PoolTestDevice : NSObject {
@public
	unsigned calls;
	unsigned failAt;
	NSUInteger lastLength;
}
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options;
@end
@implementation PoolTestDevice
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options {
	if (++calls == failAt) { return nil; }
	auto* buffer = [PoolTestBuffer new];
	++liveBuffers;
	lastLength = length;
	buffer->_length = length;
	buffer->_shared = options == MTLResourceStorageModeShared;
	return (id<MTLBuffer>)buffer;
}
@end

// The block is made outside the test body: a block literal in it would keep its own copy until the end of the scope.
using Completion = void (^)(void);
static Completion makeCompletion(std::shared_ptr<MVKPerVertexScratch> scratch) {
	return [^{ assert(scratch->buffers[0]); } copy];
}

int main() {
	@autoreleasepool {
		// Classes are powers of two from 256 bytes.
		assert(MVKPerVertexScratchPool::sizeClass(1) == 8 && MVKPerVertexScratchPool::sizeClass(256) == 8);
		assert(MVKPerVertexScratchPool::sizeClass(257) == 9 && MVKPerVertexScratchPool::sizeClass(512) == 9 && MVKPerVertexScratchPool::sizeClass(513) == 10);
		assert(MVKPerVertexScratchPool::sizeClass(NSUInteger(1) << 40) == 40 && MVKPerVertexScratchPool::sizeClass((NSUInteger(1) << 40) + 1) == 41);

		auto* device = [PoolTestDevice new];
		std::set<id> residents;
		unsigned residentCalls = 0;
		auto pool = std::make_shared<MVKPerVertexScratchPool>(NSUInteger(1) << 20, [&](id<MTLBuffer> buffer) { residents.insert(buffer); ++residentCalls; });

		// A direct indexed draw with restart: capture (private), params, occurrences, primitives, corners (shared), index and
		// restart arguments (private). Every buffer is taken from the pool, at its class size, and made resident once.
		MVKPerVertexScratchRequest direct{300, 24, 12, 600, 1000, true};
		MVKPerVertexScratchReservations first;
		assert(mvkReservePerVertexScratch((id<MTLDevice>)device, {direct}, first, pool));
		MVKPerVertexScratch* scratch = first[0].get();
		assert(scratch->pool == pool && device->calls == 7 && liveBuffers == 7 && residentCalls == 7);
		NSUInteger expected[] = {512, 256, 256, 256, 1024, 1024, 512};
		for (size_t i = 0; i < 7; ++i) { assert(scratch->buffers[i].length == expected[i] && residents.count(scratch->buffers[i])); }
		assert(!scratch->buffers[0].contents && scratch->buffers[1].contents && scratch->buffers[4].contents && !scratch->buffers[5].contents);
		id<MTLBuffer> taken[7];
		for (size_t i = 0; i < 7; ++i) { taken[i] = scratch->buffers[i]; }

		// The completed handler of the Metal command buffer that encoded the draw holds the last reference: while it is
		// pending, the submission releasing its reservations returns nothing, and the next draw gets new buffers.
		Completion handler = makeCompletion(first[0]);
		first.clear();
		MVKPerVertexScratchReservations second;
		assert(mvkReservePerVertexScratch((id<MTLDevice>)device, {direct}, second, pool));
		assert(device->calls == 14 && liveBuffers == 14);
		for (size_t i = 0; i < 7; ++i) { assert(second[0]->buffers[i] != taken[i]); }
		second.clear();	// never encoded: its buffers return at once

		// Completion: the handler runs, then Metal releases it. The buffers return to their class and storage mode.
		handler();
		[handler release];
		assert(liveBuffers == 14);
		MVKPerVertexScratchReservations third;
		assert(mvkReservePerVertexScratch((id<MTLDevice>)device, {direct, direct}, third, pool));
		assert(device->calls == 14 && residentCalls == 14);
		std::set<id> reused;
		for (auto& s : third) { for (size_t i = 0; i < 7; ++i) { assert(s->buffers[i].length == expected[i]); reused.insert(s->buffers[i]); } }
		for (size_t i = 0; i < 7; ++i) { assert(reused.count(taken[i])); }
		third.clear();

		// A smaller request of the same class reuses a buffer; a larger class or the other storage mode does not.
		MVKPerVertexScratchReservations smaller;
		assert(mvkReservePerVertexScratch((id<MTLDevice>)device, {{257, 4, 4}}, smaller, pool));
		assert(device->calls == 14 && smaller[0]->buffers[0].length == 512 && !smaller[0]->buffers[0].contents);
		smaller.clear();
		MVKPerVertexScratchReservations larger;
		assert(mvkReservePerVertexScratch((id<MTLDevice>)device, {{1025, 4, 4}}, larger, pool));
		assert(device->calls == 15 && device->lastLength == 2048 && larger[0]->buffers[0].length == 2048);
		larger.clear();
		// The free 2048-byte buffer is private: shared corners of that class get a new buffer (and so does the 256-byte
		// private capture, a class with no free buffer).
		MVKPerVertexScratchReservations otherMode;
		assert(mvkReservePerVertexScratch((id<MTLDevice>)device, {{4, 4, 4, 2000}}, otherMode, pool));
		assert(device->calls == 17 && otherMode[0]->buffers[4].length == 2048 && otherMode[0]->buffers[4].contents);
		otherMode.clear();

		// The class size never exceeds the device limit: a 600 KiB request in the 1 MiB class with a 700 KiB limit.
		auto clamped = std::make_shared<MVKPerVertexScratchPool>(NSUInteger(700) << 10, nullptr);
		MVKPerVertexScratchReservations limit;
		assert(mvkReservePerVertexScratch((id<MTLDevice>)device, {{NSUInteger(600) << 10, 4, 4}}, limit, clamped));
		assert(limit[0]->buffers[0].length == NSUInteger(700) << 10);
		limit.clear();

		// A failed reservation publishes nothing and returns what it took: the retry reuses it.
		unsigned before = device->calls;
		device->failAt = before + 2;
		MVKPerVertexScratchReservations failed;
		assert(!mvkReservePerVertexScratch((id<MTLDevice>)device, {{4096, 4096, 4096}}, failed, pool) && failed.empty());
		device->failAt = 0;
		assert(mvkReservePerVertexScratch((id<MTLDevice>)device, {{4096, 4096, 4096}}, failed, pool));
		assert(device->calls == before + 4);	// the private capture taken before the failure is reused
		failed.clear();

		// Indirect plans and TES draws keep individually owned buffers: no pool, released at destruction.
		MVKPerVertexScratchRequest indirect{};
		indirect.indirectCapacity = 8;
		indirect.planSize = 1024;
		MVKPerVertexScratchRequest tes{48, 24, 12};
		tes.tessSizes[0] = 64;
		tes.tessSizes[5] = 512;
		unsigned live = liveBuffers;
		MVKPerVertexScratchReservations outside;
		assert(mvkReservePerVertexScratch((id<MTLDevice>)device, {indirect, tes}, outside, pool));
		assert(!outside[0]->pool && !outside[1]->pool && liveBuffers == live + 1 + 6);
		outside.clear();
		assert(liveBuffers == live);

		// Without a pool, the reservation is unchanged: exact lengths, released at destruction.
		MVKPerVertexScratchReservations plain;
		assert(mvkReservePerVertexScratch((id<MTLDevice>)device, {direct}, plain));
		assert(!plain[0]->pool && plain[0]->buffers[0].length == 300 && liveBuffers == live + 7);
		plain.clear();
		assert(liveBuffers == live);

		// The pool releases its free buffers with it.
		pool.reset();
		clamped.reset();
		assert(liveBuffers == 0);
		[device release];
	}
	puts("scratch pool: all cases passed");
	return 0;
}
