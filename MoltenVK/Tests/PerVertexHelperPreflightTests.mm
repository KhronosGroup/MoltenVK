// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#include "MVKPerVertexScratch.h"
#include "MVKSubmissionTransaction.h"
#include "HelperPreflightVersion.inc"
#include <atomic>
#include <cassert>
#include <cstdio>
#include <mutex>
#include <thread>
#include <unordered_set>
using namespace std;

static atomic<unsigned> liveBuffers, livePipelines;
// No Metal device, queue, compiler or GPU is created. Only these selectors run.
@interface PreflightBuffer : NSObject {
@public
	NSUInteger _length;
	uint8_t _bytes[512];
}
@end
@implementation PreflightBuffer
- (NSUInteger)length { return _length; }
- (void*)contents { return _bytes; }
- (void)dealloc { --liveBuffers; [super dealloc]; }
@end
@interface PreflightDevice : NSObject {
@public
	unsigned calls, failAt;
	std::atomic<VkResult>* deviceResult;
}
@end
@implementation PreflightDevice
- (id<MTLBuffer>)newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options {
	(void)options;
	if (++calls == failAt) {
		if (deviceResult) { *deviceResult = VK_ERROR_DEVICE_LOST; }
		return nil;
	}
	auto* buffer = [PreflightBuffer new];
	++liveBuffers;
	buffer->_length = length;
	return (id<MTLBuffer>)buffer;
}
@end
@interface PreflightPipeline : NSObject {
@public
	NSUInteger width, maximum;
}
@end
@implementation PreflightPipeline
- (NSUInteger)threadExecutionWidth { return width; }
- (NSUInteger)maxTotalThreadsPerThreadgroup { return maximum; }
- (void)dealloc { --livePipelines; [super dealloc]; }
@end

enum class Failure { None, Missing, Timeout, ZeroWidth, ZeroMaximum, DeviceLostNil, DeviceLostValid };
struct TestCommandPool;
struct TestDevice {
	atomic<VkResult> result{VK_SUCCESS};
	Failure failure = Failure::None;
	atomic<unsigned> creations[5]{};
	VkResult getConfigurationResult() { return result.load(); }
	TestDevice* getCommandResourceFactory() { return this; }
	id<MTLComputePipelineState> create(unsigned slot);
	id<MTLComputePipelineState> newPerVertexRestartMTLComputePipelineState(TestCommandPool*) { return create(2); }
	id<MTLComputePipelineState> newConvertUint8IndicesMTLComputePipelineState(TestCommandPool*, bool preserveValues) { return create(preserveValues ? 1 : 0); }
	id<MTLComputePipelineState> newPerVertexIndirectMTLComputePipelineState(TestCommandPool*) { return create(3); }
	id<MTLComputePipelineState> newPerVertexTessTopologyMTLComputePipelineState(TestCommandPool*) { return create(4); }
};
struct TestCommandPool { TestDevice* device; TestDevice* getDevice() { return device; } };
id<MTLComputePipelineState> TestDevice::create(unsigned slot) {
	++creations[slot];
	if (failure == Failure::DeviceLostNil || failure == Failure::DeviceLostValid) { result = VK_ERROR_DEVICE_LOST; }
	// The real compiler returns nil for both compilation failure and timeout.
	if (failure == Failure::Missing || failure == Failure::Timeout || failure == Failure::DeviceLostNil) { return nil; }
	auto* state = [PreflightPipeline new];
	++livePipelines;
	state->width = failure == Failure::ZeroWidth ? 0 : 32;
	state->maximum = failure == Failure::ZeroMaximum ? 0 : 256;
	return (id<MTLComputePipelineState>)state;
}

struct MVKCommandEncodingPool {
	explicit MVKCommandEncodingPool(TestCommandPool* pool) : _commandPool(pool) {}
	TestCommandPool* _commandPool;
	mutex _lock;
	id<MTLComputePipelineState> _mtlPerVertexRestartComputePipelineState = nil;
	id<MTLComputePipelineState> _mtlConvertUint8IndicesComputePipelineState[2] = {};
	id<MTLComputePipelineState> _mtlPerVertexIndirectComputePipelineState = nil;
	id<MTLComputePipelineState> _mtlPerVertexTessTopologyComputePipelineState = nil;
	id<MTLComputePipelineState> getPerVertexRestartMTLComputePipelineState();
	id<MTLComputePipelineState> getPerVertexIndirectMTLComputePipelineState();
	id<MTLComputePipelineState> getPerVertexTessTopologyMTLComputePipelineState();
	id<MTLComputePipelineState> getConvertUint8IndicesMTLComputePipelineState(bool preserveValues = false);
	void clear() {
		lock_guard<mutex> lock(_lock);
		[_mtlPerVertexRestartComputePipelineState release]; _mtlPerVertexRestartComputePipelineState = nil;
		for (auto& state : _mtlConvertUint8IndicesComputePipelineState) { [state release]; state = nil; }
		[_mtlPerVertexIndirectComputePipelineState release]; _mtlPerVertexIndirectComputePipelineState = nil;
		[_mtlPerVertexTessTopologyComputePipelineState release]; _mtlPerVertexTessTopologyComputePipelineState = nil;
	}
	~MVKCommandEncodingPool() { clear(); }
};
struct RecordingPool : TestCommandPool {
	MVKCommandEncodingPool encoding{this};
	MVKCommandEncodingPool* getCommandEncodingPool() { return &encoding; }
};
struct MVKCommandBuffer {
	TestDevice* _device;
	RecordingPool* _commandPool;
	id<MTLDevice> metal;
	VkResult configuration = VK_SUCCESS;
	bool _prefilledMTLCmdBuffer = false;
	vector<MVKPerVertexScratchRequest> _perVertexScratchRequests;
	MVKPerVertexScratchReservations _prefilledPerVertexScratch;
	id<MTLDevice> getMTLDevice() { return metal; }
	VkResult getConfigurationResult() { return configuration; }
	bool wasConfigurationSuccessful() { return configuration == VK_SUCCESS; }
	VkResult reportError(VkResult result, const char*, ...) { return result; }
	VkResult reservePrefilledPerVertexScratch(size_t firstRequest);
	VkResult reservePerVertexScratch(MVKPerVertexScratchReservations& scratch, unordered_set<MVKCommandBuffer*>& prefilledExecutions);
	VkResult reservePerVertexScratch(const vector<MVKPerVertexScratchRequest>& requests, MVKPerVertexScratchReservations& scratch);
};
#include "HelperPreflightMethods.inc"

static MVKPerVertexScratchRequest request(bool restart) { return {48, 24, 12, 12, restart ? 12u : 6u, restart}; }
#if MVK_TEST_HAS_INDIRECT
// Indirect scratch prepares its planning helper instead of an index helper; the plan fits the fake buffer.
static MVKPerVertexScratchRequest indirectRequest() {
	MVKPerVertexScratchRequest indirect = {48, 24, 12, 12, 16};
	indirect.indirectCapacity = 4;
	indirect.planSize = 256;
	return indirect;
}
#endif
struct Submission { MVKPerVertexScratchReservations scratch; };

static bool checkRejection() {
	bool passed = true;
	for (unsigned kind : {0u, 1u, 2u}) {
		bool restart = kind == 1;
#if !MVK_TEST_HAS_INDIRECT
		if (kind == 2) { continue; }
#endif
		for (Failure failure : {Failure::Missing, Failure::Timeout, Failure::ZeroWidth, Failure::ZeroMaximum, Failure::DeviceLostNil, Failure::DeviceLostValid}) {
			for (unsigned prefill : {0u, 1u, 2u}) {
				TestDevice device;
				RecordingPool pool{{&device}};
				auto* metal = [PreflightDevice new];
#if MVK_TEST_HAS_INDIRECT
				MVKCommandBuffer cb{&device, &pool, (id<MTLDevice>)metal, VK_SUCCESS, false, {kind == 2 ? indirectRequest() : request(restart)}, {}};
#else
				MVKCommandBuffer cb{&device, &pool, (id<MTLDevice>)metal, VK_SUCCESS, false, {request(restart)}, {}};
#endif
				device.failure = failure;
				unsigned dispatched = 0;
				unordered_set<MVKCommandBuffer*> prefilled;
				VkResult result;
				if (prefill) {
					// Immediate recording reserves the appended request; deferred end
					// reserves the whole list. Neither may enter encode after failure.
					result = cb.reservePrefilledPerVertexScratch(0);
					if (result == VK_SUCCESS) { ++dispatched; }
				} else {
					// A late batch failure must prevent dispatch of earlier batches too.
					result = mvkSubmitTransaction<Submission>(2, [](uint32_t) { return new Submission; }, [&](Submission& submission) {
						return cb.reservePerVertexScratch(submission.scratch, prefilled);
					}, [&](Submission* submission) { ++dispatched; delete submission; return VK_SUCCESS; });
				}
				VkResult expected = failure == Failure::DeviceLostNil || failure == Failure::DeviceLostValid ? VK_ERROR_DEVICE_LOST : VK_ERROR_INITIALIZATION_FAILED;
				if (result != expected || dispatched || liveBuffers || !cb._prefilledPerVertexScratch.empty()) {
					fprintf(stderr, "FAIL: restart=%d failure=%u prefill=%u returned %d, expected %d before dispatch (dispatched=%u, liveBuffers=%u)\n", restart, unsigned(failure), prefill, result, expected, dispatched, liveBuffers.load());
					[metal release];
					passed = false;
					continue;
				}
				assert(device.creations[kind == 2 ? 3 : restart ? 2 : 1] == 1);
				[metal release];
			}
		}
	}
	return passed;
}

static void checkTransactions() {
	TestDevice device;
	RecordingPool pool{{&device}};
	auto* metal = [PreflightDevice new];
	MVKCommandBuffer cb{&device, &pool, (id<MTLDevice>)metal, VK_SUCCESS, false, {request(false), request(true)}, {}};
	unordered_set<MVKCommandBuffer*> prefilled;
	MVKPerVertexScratchReservations saved;
	// Allocation failure never reaches helper compilation and leaves no reservation.
	metal->failAt = 3;
	assert(cb.reservePerVertexScratch(saved, prefilled) == VK_ERROR_OUT_OF_DEVICE_MEMORY);
	assert(saved.empty() && !liveBuffers && !device.creations[1] && !device.creations[2]);
	metal->failAt = metal->calls + 1;
	metal->deviceResult = &device.result;
	assert(cb.reservePerVertexScratch(saved, prefilled) == VK_ERROR_DEVICE_LOST);
	assert(saved.empty() && !liveBuffers);
	device.result = VK_SUCCESS;
	metal->deviceResult = nullptr;
	metal->failAt = 0;
	assert(cb.reservePerVertexScratch(saved, prefilled) == VK_SUCCESS);
	assert(saved.size() == 2 && liveBuffers == 13);
#if MVK_TEST_HAS_PREPARED_HELPER
	assert(saved[0]->indexPipeline && saved[1]->indexPipeline);
#endif
	// Failed replacement leaves existing reservations intact, including helper ownership.
	auto* previous = saved[0].get();
	pool.encoding.clear();
	device.failure = Failure::Timeout;
	assert(cb.reservePerVertexScratch(saved, prefilled) == VK_ERROR_INITIALIZATION_FAILED);
	assert(saved[0].get() == previous && liveBuffers == 13);
	device.failure = Failure::None;
	// A failure in the later batch rolls back earlier scratch without dispatch/signals.
	unsigned batch = 0, dispatched = 0;
	assert(mvkSubmitTransaction<Submission>(2, [](uint32_t) { return new Submission; }, [&](Submission& submission) {
		if (batch++) { pool.encoding.clear(); device.failure = Failure::Timeout; }
		return cb.reservePerVertexScratch(submission.scratch, prefilled);
	}, [&](Submission* submission) { ++dispatched; delete submission; return VK_SUCCESS; }) == VK_ERROR_INITIALIZATION_FAILED);
	assert(dispatched == 0 && liveBuffers == 13);
	device.failure = Failure::None;
	cb._prefilledMTLCmdBuffer = true;
	cb._prefilledPerVertexScratch = saved;
	// Repeated prefilled command buffers consume the prefill only once; the later
	// execution prepares independently. Failure leaves the prefill available.
	batch = 0;
	assert(mvkSubmitTransaction<Submission>(2, [](uint32_t) { return new Submission; }, [&](Submission& submission) {
		if (batch++) { device.failure = Failure::Timeout; }
		return cb.reservePerVertexScratch(submission.scratch, prefilled);
	}, [](Submission*) { assert(false); return VK_SUCCESS; }) == VK_ERROR_INITIALIZATION_FAILED);
	assert(saved[0].use_count() == 2 && liveBuffers == 13);
	device.failure = Failure::None;
	prefilled.clear();
	vector<unique_ptr<Submission>> executions;
	assert(mvkSubmitTransaction<Submission>(2, [](uint32_t) { return new Submission; }, [&](Submission& submission) {
		return cb.reservePerVertexScratch(submission.scratch, prefilled);
	}, [&](Submission* submission) { executions.emplace_back(submission); return VK_SUCCESS; }) == VK_SUCCESS);
	assert(executions[0]->scratch[0] == saved[0] && executions[1]->scratch[0] != saved[0]);
	assert(liveBuffers == 26);
	// A pre-existing device failure also rejects cached/prefilled success.
	device.result = VK_ERROR_DEVICE_LOST;
	prefilled.clear();
	MVKPerVertexScratchReservations rejected;
	assert(cb.reservePerVertexScratch(rejected, prefilled) == VK_ERROR_DEVICE_LOST && rejected.empty());
	[metal release];
}

static void checkConcurrentCache() {
	TestDevice device;
	RecordingPool pool{{&device}};
	vector<thread> threads;
	atomic<unsigned> ready{0};
	atomic<bool> go{false};
	id<MTLComputePipelineState> results[24][3]{};
	for (unsigned i = 0; i < 24; ++i) {
		threads.emplace_back([&, i] {
			@autoreleasepool {
				++ready;
				while (!go) { this_thread::yield(); }
				for (unsigned repeat = 0; repeat < 100; ++repeat) {
					results[i][0] = pool.encoding.getConvertUint8IndicesMTLComputePipelineState(false);
					results[i][1] = pool.encoding.getConvertUint8IndicesMTLComputePipelineState(true);
					results[i][2] = pool.encoding.getPerVertexRestartMTLComputePipelineState();
				}
			}
		});
	}
	while (ready != 24) { this_thread::yield(); }
	go = true;
	for (auto& thread : threads) { thread.join(); }
	for (unsigned slot = 0; slot < 3; ++slot) {
		assert(device.creations[slot] == 1);
		for (unsigned i = 0; i < 24; ++i) { assert(results[i][slot] == results[0][slot]); }
	}
	assert(results[0][0] != results[0][1]); // Regular UINT8 keeps its sentinel semantics.
}

#if MVK_TEST_HAS_INDIRECT
static void checkIndirect() {
	TestDevice device;
	RecordingPool pool{{&device}};
	auto* metal = [PreflightDevice new];
	MVKCommandBuffer cb{&device, &pool, (id<MTLDevice>)metal, VK_SUCCESS, false, {indirectRequest(), indirectRequest()}, {}};
	unordered_set<MVKCommandBuffer*> prefilled;
	MVKPerVertexScratchReservations saved;
	assert(cb.reservePerVertexScratch(saved, prefilled) == VK_SUCCESS && saved.size() == 2);
	for (auto& scratch : saved) {
		// Planning helper retained, no index helper, plan buffer present and zeroed before any submission.
		assert(scratch->indirectPipeline && !scratch->indexPipeline && scratch->indirectCapacity == 4);
		assert(scratch->buffers[12] && scratch->buffers[12].length == 256);
		auto* bytes = (const uint8_t*)scratch->buffers[12].contents;
		for (unsigned i = 0; i < 256; ++i) { assert(!bytes[i]); }
	}
	assert(saved[0]->buffers[12] != saved[1]->buffers[12] && device.creations[3] == 1 && !device.creations[1] && !device.creations[2]);
	// Restart-capable indirect scratch also retains the restart assembly helper. Its replay tables, including the
	// restart state, are reserved only after the GPU plan completes, from the counts it froze.
	auto restart = indirectRequest();
	restart.restart = true;
	cb._perVertexScratchRequests = {restart};
	MVKPerVertexScratchReservations restarted;
	assert(cb.reservePerVertexScratch(restarted, prefilled) == VK_SUCCESS && restarted.size() == 1);
	assert(restarted[0]->indirectPipeline && restarted[0]->indexPipeline && device.creations[2] == 1 && !device.creations[1]);
	for (auto buffer : restarted[0]->buffers) { assert(!buffer || buffer == restarted[0]->buffers[12]); }
	[metal release];
}
#endif

#if MVK_TEST_HAS_TES_TOPOLOGY
// TES scratch prepares the GPU topology generator before submission; failures reject the whole call.
static void checkTessTopology() {
	for (Failure failure : {Failure::None, Failure::Missing, Failure::ZeroWidth, Failure::DeviceLostValid}) {
		TestDevice device;
		RecordingPool pool{{&device}};
		auto* metal = [PreflightDevice new];
		MVKPerVertexScratchRequest tes = {48, 24, 12, 12};
		NSUInteger sizes[] = {48, 16, 16, 16, 24, 256};
		std::copy(std::begin(sizes), std::end(sizes), tes.tessSizes);
		MVKCommandBuffer cb{&device, &pool, (id<MTLDevice>)metal, VK_SUCCESS, false, {tes}, {}};
		device.failure = failure;
		unordered_set<MVKCommandBuffer*> prefilled;
		MVKPerVertexScratchReservations saved;
		VkResult result = cb.reservePerVertexScratch(saved, prefilled);
		if (failure == Failure::None) {
			assert(result == VK_SUCCESS && saved.size() == 1 && saved[0]->tessTopologyPipeline && !saved[0]->indexPipeline);
			assert(saved[0]->getTessEvalStatus() == 0 && device.creations[4] == 1 && !device.creations[2] && !device.creations[3]);
		} else {
			assert(result == (failure == Failure::DeviceLostValid ? VK_ERROR_DEVICE_LOST : VK_ERROR_INITIALIZATION_FAILED) && saved.empty() && !liveBuffers);
		}
		saved.clear();
		[metal release];
	}
}
#endif

int main() {
	@autoreleasepool {
		if (!checkRejection()) { return 1; }
		checkTransactions();
#if MVK_TEST_HAS_INDIRECT
		checkIndirect();
#endif
#if MVK_TEST_HAS_TES_TOPOLOGY
		checkTessTopology();
#endif
		assert(!liveBuffers && !livePipelines);
		checkConcurrentCache();
		assert(!liveBuffers && !livePipelines);
	}
	puts("PASS: production preflight/cache methods; nil/timeout/invalid dimensions/device loss; no dispatch on failure; prefill/repeated execution/rollback/retry; helper lifetime; concurrent warm and cold caches (CPU only)");
}
