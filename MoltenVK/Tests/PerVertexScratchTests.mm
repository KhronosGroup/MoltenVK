// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#include "MVKPerVertexScratch.h"
#include "MVKSubmissionTransaction.h"
#include <cassert>
#include <cstdio>
#include <cstddef>

static_assert(sizeof(MTLDispatchThreadgroupsIndirectArguments) == 12);
static_assert(sizeof(MTLDrawPrimitivesIndirectArguments) == 16);
static_assert(offsetof(MTLDrawPrimitivesIndirectArguments, instanceCount) == 4);
static_assert(offsetof(MTLDrawPrimitivesIndirectArguments, vertexStart) == 8);
static_assert(offsetof(MTLDrawPrimitivesIndirectArguments, baseInstance) == 12);

static unsigned liveBuffers;

// These objects only implement selectors used by the reservation code. No Metal
// device, queue, command buffer, Vulkan instance, or GPU process is created.
@interface ScratchTestBuffer : NSObject {
@public
	NSUInteger _length;
	bool _visible;
	alignas(uint32_t) uint8_t _bytes[512];
}
@end
@implementation ScratchTestBuffer
- (NSUInteger)length { return _length; }
- (void*)contents { return _visible ? _bytes : nullptr; }
- (void)dealloc { --liveBuffers; [super dealloc]; }
@end

@interface ScratchTestDevice : NSObject {
@public
	unsigned calls;
	unsigned failAt;
	unsigned failureMode;
}
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options;
@end
@implementation ScratchTestDevice
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options {
	bool fail = ++calls == failAt;
	if (fail && failureMode == 0) { return nil; }
	auto* buffer = [ScratchTestBuffer new];
	++liveBuffers;
	buffer->_length = length - (fail && failureMode == 1 ? 1 : 0);
	buffer->_visible = options == MTLResourceStorageModeShared && !(fail && failureMode == 2);
	return (id<MTLBuffer>)buffer;
}
@end

static const std::vector<MVKPerVertexScratchRequest> requests = {{48, 24, 12}, {32, 0, 0}, {48, 24, 12}};

struct Submission {
	MVKPerVertexScratchReservations executions[2];
};

using Completion = void (^)(void);
static Completion makeCompletion(std::shared_ptr<MVKPerVertexScratch> scratch) {
	return [^{ assert(scratch->buffers[0].length == 48); } copy];
}

// One CPU-only sizing test: independent maxima, frozen Count, restart layout and hostile bounds.
static void testFrozenIndirectReplaySizing() {
	uint32_t plan[276] = {};
	plan[56] = 2;
	// Frozen indexed commands, five words: vertices, instances, first index, vertex offset, first instance.
	uint32_t indexed[20] = {6, 1, 3, uint32_t(-4), 7, 3, 4};
	indexed[10] = UINT32_MAX; indexed[11] = UINT32_MAX; // Beyond frozen Count: must not participate.
	// The same draws as nonindexed commands, four words each.
	uint32_t nonindexed[16] = {6, 1, 3, 7, 3, 4};
	nonindexed[8] = UINT32_MAX; nonindexed[9] = UINT32_MAX;
	MVKPerVertexScratchRequest request{};
	NSUInteger gathered = 0;
	uint32_t scans = 0;
	auto size = [&](const void* data, NSUInteger bytes, const void* snapshot, NSUInteger snapshotBytes, uint32_t count, uint32_t views, uint32_t stride, VkPrimitiveTopology topology, bool isIndexed, bool restart, uint64_t limit) {
		return mvkSizePerVertexIndirectReplay(data, bytes, snapshot, snapshotBytes, count, views, stride, topology, isIndexed, restart, true, limit, request, gathered, scans);
	};
	auto run = [&] { return size(plan, sizeof(plan), indexed, sizeof(indexed), 3, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, 4096); };
	assert(run());
	assert(request.captureSize == 384 && request.occurrenceSize == 192 && request.primitiveSize == 96 && request.cornerSize == 96);
	assert(request.indexSize == 240 && request.restart && gathered == 216 && scans == 3);
	assert(!request.planSize && !request.snapshotSize && !request.indirectCapacity && !request.widenUint8 && !request.tessSizes[5]);
	for (uint32_t status : {1u, 2u, 4u}) { plan[0] = status; assert(!run()); }
	plan[0] = 0;
	assert(!size(nullptr, sizeof(plan), indexed, sizeof(indexed), 3, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, 4096));
	assert(!size(plan, 56 * 4, indexed, sizeof(indexed), 3, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, 4096));
	assert(!size(plan, sizeof(plan), nullptr, sizeof(indexed), 3, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, 4096)); // No snapshot.
	assert(!size(plan, sizeof(plan), indexed, 39, 3, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, 4096)); // Two indexed draws need 40 bytes.
	assert(!size(plan, sizeof(plan), nonindexed, 31, 3, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, false, true, 4096)); // Two nonindexed draws need 32.
	for (uint32_t views : {0u, 33u, UINT32_MAX}) { assert(!size(plan, sizeof(plan), indexed, sizeof(indexed), 3, views, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, 4096)); }
	assert(!size(plan, sizeof(plan), indexed, sizeof(indexed), 3, 2, 0, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, 4096));
	assert(!size(plan, sizeof(plan), indexed, sizeof(indexed), 3, 2, 16, VK_PRIMITIVE_TOPOLOGY_PATCH_LIST, true, true, 4096));
	assert(!size(plan, sizeof(plan), indexed, sizeof(indexed), 3, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, 383));
	plan[56] = 4; assert(!run());
	plan[56] = UINT32_MAX; assert(!size(plan, sizeof(plan), indexed, sizeof(indexed), UINT32_MAX, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, UINT64_MAX));
	plan[56] = 2;
	indexed[1] = UINT32_MAX; assert(!run()); // Expanded instances overflow uint32.
	indexed[1] = 1; indexed[0] = UINT32_MAX; assert(!run()); // Dense records overflow uint32.
	nonindexed[0] = UINT32_MAX;
	assert(!size(plan, sizeof(plan), nonindexed, sizeof(nonindexed), 3, 1, 1, VK_PRIMITIVE_TOPOLOGY_POINT_LIST, false, false, UINT64_MAX)); // Triplet word indices overflow.
	nonindexed[0] = UINT32_MAX / 6 + 3;
	assert(!size(plan, sizeof(plan), nonindexed, sizeof(nonindexed), 3, 1, 1, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, false, false, UINT64_MAX)); // Pair word indices overflow.
	assert(request.captureSize == 384 && request.indexSize == 240 && gathered == 216 && scans == 3); // Failure never publishes partial output.
	indexed[0] = 6; nonindexed[0] = 6;
	assert(size(plan, sizeof(plan), indexed, sizeof(indexed), 3, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, 384)); // Exact Metal limit, no power-of-two rounding.
	assert(size(plan, sizeof(plan), indexed, sizeof(indexed), 3, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, false, 384));
	assert(request.indexSize == 24 && !request.restart && !gathered && !scans);
	assert(size(plan, sizeof(plan), nonindexed, sizeof(nonindexed), 3, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, false, true, 384));
	assert(request.captureSize == 384 && !request.indexSize && !request.restart); // Vulkan ignores restart for nonindexed draws.
	plan[56] = 0;
	assert(size(plan, sizeof(plan), indexed, sizeof(indexed), 3, 2, 0, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, 0));
	assert(!request.captureSize && !request.occurrenceSize && !request.restart && !gathered && !scans);
	plan[56] = 2; indexed[0] = 0; indexed[1] = UINT32_MAX; indexed[5] = UINT32_MAX; indexed[6] = 0;
	assert(run() && !request.captureSize); // Inactive slots bypass count multiplication.
	// A single draw freezes its command in the plan, at word 48.
	plan[56] = 1; plan[48] = 1; plan[49] = 1;
	assert(!size(plan, 57 * 4, plan + 48, 9 * 4, 1, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, 272)); // Missing single-draw snapshot.
	plan[55] = 1;
	assert(size(plan, 57 * 4, plan + 48, 9 * 4, 1, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, 272));
	assert(request.captureSize == 32 && request.occurrenceSize == 24 && request.primitiveSize == 12 && request.cornerSize == 12);
	assert(request.indexSize == 40 && gathered == 36 && scans == 0); // Active capture, zero primitives.
	assert(!size(plan, 57 * 4, plan + 48, 9 * 4, 1, 2, 16, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP, true, true, 271)); // Restart arguments also obey Metal limits.
	plan[48] = 100; plan[49] = 1;
	assert(!size(plan, 57 * 4, plan + 48, 9 * 4, 1, 1, 1, VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST, true, true, 3999)); // Index scratch, not capture, exceeds limit.
	std::puts("PASS: frozen indirect replay sizing, two-view restart maxima, indexed and nonindexed snapshots, malformed snapshots, overflow and Metal limits (CPU only)");
}

int main() {
	testFrozenIndirectReplaySizing();
	@autoreleasepool {
		auto* device = [ScratchTestDevice new];
		// Three batches, two executions each, including repeated secondary draws
		// and a short draw needing capture but no replay. Ten allocations/execution.
		constexpr unsigned allocationCount = 60;
		for (unsigned mode = 0; mode < 2; ++mode) {
			for (unsigned fail = 1; fail <= allocationCount; ++fail) {
				device->calls = 0; device->failAt = fail; device->failureMode = mode;
				unsigned dispatched = 0;
				VkResult result = mvkSubmitTransaction<Submission>(3, [](uint32_t) { return new Submission; }, [&](Submission& submission) {
					for (auto& execution : submission.executions) {
						if (!mvkReservePerVertexScratch((id<MTLDevice>)device, requests, execution)) { return VK_ERROR_OUT_OF_DEVICE_MEMORY; }
					}
					return VK_SUCCESS;
				}, [&](Submission* submission) {
					++dispatched; delete submission; return VK_SUCCESS;
				});
				assert(result == VK_ERROR_OUT_OF_DEVICE_MEMORY);
				assert(device->calls == fail && liveBuffers == 0 && dispatched == 0);
			}
		}
		// The optional corner allocation belongs to the same pre-submit transaction.
		for (unsigned mode = 0; mode < 3; ++mode) {
			device->calls = 0; device->failAt = 5; device->failureMode = mode;
			MVKPerVertexScratchReservations corners;
			assert(!mvkReservePerVertexScratch((id<MTLDevice>)device, {{48, 24, 12, 12}}, corners));
			assert(corners.empty() && liveBuffers == 0 && device->calls == 5);
		}
		device->calls = 0; device->failAt = 0;
		{
			MVKPerVertexScratchReservations corners;
			assert(mvkReservePerVertexScratch((id<MTLDevice>)device, {{48, 24, 12, 12}}, corners));
			assert(corners[0]->buffers[4].length == 12 && corners[0]->buffers[4].contents);
		}
		assert(liveBuffers == 0);
		// UINT8 widening is private GPU scratch and participates in the same transaction.
		for (unsigned mode = 0; mode < 2; ++mode) {
			device->calls = 0; device->failAt = 6; device->failureMode = mode;
			MVKPerVertexScratchReservations widened;
			assert(!mvkReservePerVertexScratch((id<MTLDevice>)device, {{48, 24, 12, 12, 6}}, widened));
			assert(widened.empty() && liveBuffers == 0 && device->calls == 6);
		}
		device->calls = 0; device->failAt = 0;
		{
			MVKPerVertexScratchReservations widened;
			assert(mvkReservePerVertexScratch((id<MTLDevice>)device, {{48, 24, 12, 12, 6}}, widened));
			assert(widened[0]->buffers[5].length == 6 && !widened[0]->buffers[5].contents);
		}
		assert(liveBuffers == 0);
		// Restart's compact index and indirect argument buffers are reserved before any submission.
		for (unsigned mode = 0; mode < 2; ++mode) {
			for (unsigned fail = 1; fail <= 7; ++fail) {
				device->calls = 0; device->failAt = fail; device->failureMode = mode;
				MVKPerVertexScratchReservations restart;
				assert(!mvkReservePerVertexScratch((id<MTLDevice>)device, {{48, 24, 12, 12, 16, true}}, restart));
				assert(restart.empty() && liveBuffers == 0 && device->calls == fail);
			}
		}
		device->calls = 0; device->failAt = 0;
		{
			MVKPerVertexScratchReservations restart;
			assert(mvkReservePerVertexScratch((id<MTLDevice>)device, {{48, 24, 12, 12, 16, true}, {48, 24, 12, 12, 16, true}}, restart));
			assert(restart[0]->buffers[6].length == 272 && !restart[0]->buffers[6].contents);
			for (unsigned i = 0; i < 7; ++i) { assert(restart[0]->buffers[i] != restart[1]->buffers[i]); }
		}
		assert(liveBuffers == 0);
		// The GPU plan must survive a later replay reservation, including its failure path.
		MVKPerVertexScratchRequest planRequest{0, 0, 0};
		planRequest.planSize = 256;
		planRequest.indirectCapacity = 6;
		MVKPerVertexScratchRequest replayRequest{48, 24, 12};
		device->calls = 0; device->failAt = 0;
		{
			MVKPerVertexScratch staged;
			assert(staged.reservePlan((id<MTLDevice>)device, planRequest));
			assert(staged.buffers[12] && !staged.buffers[0]);
			*(uint32_t*)staged.buffers[12].contents = 2;
			device->failAt = device->calls + 2; device->failureMode = 0;
			assert(!staged.reserveReplay((id<MTLDevice>)device, replayRequest));
			assert(staged.getIndirectStatus() == 2);
		}
		assert(liveBuffers == 0);
		device->calls = 0; device->failAt = 0;
		{
			MVKPerVertexScratch staged;
			assert(staged.reservePlan((id<MTLDevice>)device, planRequest));
			*(uint32_t*)staged.buffers[12].contents = 2;
			assert(staged.reserveReplay((id<MTLDevice>)device, replayRequest));
			assert(staged.buffers[0].length == 48 && staged.getIndirectStatus() == 2);
		}
		assert(liveBuffers == 0);
		// Several indirect draws freeze their commands in a separate shared buffer, sized by the request alone.
		MVKPerVertexScratchRequest snapshotPlan = planRequest;
		snapshotPlan.snapshotSize = 32;
		device->calls = 0; device->failAt = 0;
		{
			MVKPerVertexScratch staged;
			assert(staged.reservePlan((id<MTLDevice>)device, snapshotPlan));
			assert(staged.buffers[12].length == 256 && staged.buffers[13].length == 32 && staged.buffers[13].contents);
			assert(!staged.reservePlan((id<MTLDevice>)device, snapshotPlan)); // Never twice.
		}
		assert(liveBuffers == 0);
		device->calls = 0; device->failAt = 2; device->failureMode = 0;
		{
			MVKPerVertexScratch staged;
			assert(!staged.reservePlan((id<MTLDevice>)device, snapshotPlan)); // A failed snapshot allocation fails the plan.
		}
		assert(liveBuffers == 0);
		MVKPerVertexScratchRequest tesPlan{0, 0, 0};
		tesPlan.tessSizes[5] = 256;
		device->calls = 0; device->failAt = 0;
		{
			MVKPerVertexScratch staged;
			assert(staged.reservePlan((id<MTLDevice>)device, tesPlan));
			*(uint32_t*)staged.buffers[12].contents = 2;
			assert(staged.reserveReplay((id<MTLDevice>)device, replayRequest));
			assert(staged.getTessEvalStatus() == 2);
		}
		assert(liveBuffers == 0);
		// Reject a real-looking shared buffer with no CPU mapping.
		device->calls = 0; device->failAt = 2; device->failureMode = 2;
		MVKPerVertexScratchReservations unmapped;
		assert(!mvkReservePerVertexScratch((id<MTLDevice>)device, requests, unmapped));
		assert(unmapped.empty() && liveBuffers == 0);

		// Failure of a later batch releases temporary references to a prefill but
		// preserves the recorded reservation, so retry does not consume it.
		device->calls = 0; device->failAt = 0;
		MVKPerVertexScratchReservations prefilled;
		assert(mvkReservePerVertexScratch((id<MTLDevice>)device, requests, prefilled));
		device->failAt = device->calls + 2;
		unsigned prepared = 0;
		assert(mvkSubmitTransaction<Submission>(2, [](uint32_t) { return new Submission; }, [&](Submission& submission) {
			if (!prepared++) { submission.executions[0] = prefilled; return VK_SUCCESS; }
			return mvkReservePerVertexScratch((id<MTLDevice>)device, requests, submission.executions[0]) ? VK_SUCCESS : VK_ERROR_OUT_OF_DEVICE_MEMORY;
		}, [](Submission*) { assert(false); return VK_SUCCESS; }) == VK_ERROR_OUT_OF_DEVICE_MEMORY);
		assert(liveBuffers == 10 && prefilled[0].use_count() == 1);
		prefilled.clear();
		assert(liveBuffers == 0);

		// Successful retry reserves every batch before the first dispatch. Reusable
		// and simultaneous executions must never share their writable scratch.
		device->calls = 0; device->failAt = 0;
		std::vector<std::unique_ptr<Submission>> inFlight;
		assert(mvkSubmitTransaction<Submission>(3, [](uint32_t) { return new Submission; }, [&](Submission& submission) {
			for (auto& execution : submission.executions) { assert(mvkReservePerVertexScratch((id<MTLDevice>)device, requests, execution)); }
			return VK_SUCCESS;
		}, [&](Submission* submission) {
			assert(device->calls == allocationCount);
			inFlight.emplace_back(submission); return VK_SUCCESS;
		}) == VK_SUCCESS);
		for (const auto& first : inFlight) {
			for (const auto& second : inFlight) {
				for (const auto& a : first->executions) {
					for (const auto& b : second->executions) {
						if (&a != &b) { assert(a[0]->buffers[0] != b[0]->buffers[0]); }
					}
				}
			}
		}
		// The same C++ shared ownership captured by production's Metal completion
		// block survives deletion/reset of submission and recorded-command owners.
		Completion completion = makeCompletion(inFlight[0]->executions[0][0]);
		inFlight.clear();
		assert(liveBuffers == 4);
		completion();
		[completion release];
		assert(liveBuffers == 0);

		// Host allocation failure during preparation also rolls back earlier batches.
		assert(mvkSubmitTransaction<Submission>(2, [](uint32_t i) { if (i) { throw std::bad_alloc(); } return new Submission; }, [&](Submission& submission) {
			assert(mvkReservePerVertexScratch((id<MTLDevice>)device, requests, submission.executions[0])); return VK_SUCCESS;
		}, [](Submission*) { assert(false); return VK_SUCCESS; }) == VK_ERROR_OUT_OF_HOST_MEMORY);
		assert(liveBuffers == 0);
		[device release];
	}
	std::puts("PASS: 120 allocation failures, optional corner/restart allocation failures/success, unmapped buffer, whole-call rollback, prefill retry, independent executions, completion ownership, staged plan/replay, host OOM (CPU only)");
}
