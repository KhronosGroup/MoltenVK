/* Copyright (c) 2026 Jean-Philippe Meunier. Licensed under the Apache License, Version 2.0. */
#pragma once

#import <Metal/Metal.h>
#include "MVKPerVertexReplay.h"
#include <algorithm>
#include <cstring>
#include <functional>
#include <memory>
#include <mutex>
#include <vector>

struct MVKPerVertexScratchRequest {
	NSUInteger captureSize;
	NSUInteger occurrenceSize;
	NSUInteger primitiveSize;
	NSUInteger cornerSize = 0;
	NSUInteger indexSize = 0;
	bool restart = false;
	bool widenUint8 = false;
	// Indirect draws: record ceiling of the GPU plan, and the shared plan/status buffer. The replay scratch is
	// reserved only after the plan completes, from the counts it froze (mvkSizePerVertexIndirectReplay).
	uint32_t indirectCapacity = 0;
	NSUInteger planSize = 0;
	// Several indirect draws freeze their Vulkan commands in a separate shared buffer: 16 bytes each, 20 when indexed.
	NSUInteger snapshotSize = 0;
	// TES invocation ABI, VS output, TCS vertex and patch output, float32 levels, topology plan.
	NSUInteger tessSizes[6] = {};
};

// Read only after successful GPU phase-0 completion. The snapshot holds the Vulkan command each draw froze: four words,
// five for indexed draws; a single draw freezes it in the plan, at word 48.
// A nonzero GPU status is rejected, including the old capacity refusal; this does not change admission.
// Metadata must describe that same Metal pass (1..32 views), pipeline and execution-time restart state.
// Restart tables are bounds from frozen counts, not compacted counts: the plan has no marker census.
// On success, captureSize == 0 means skip replay entirely (do not call reserveReplay). Otherwise the
// request includes minimal table bindings even for zero primitives. Only replay fields are populated;
// retain the original plan/offset. Outputs are unchanged on failure. The supplied extent must be readable.
static inline bool mvkSizePerVertexIndirectReplay(const void* plan, NSUInteger planBytes, const void* snapshot, NSUInteger snapshotBytes, uint32_t maxDrawCount, uint32_t views, uint32_t stride, VkPrimitiveTopology topology, bool indexed, bool primitiveRestart, bool corners, uint64_t maxMTLBufferSize, MVKPerVertexScratchRequest& request, NSUInteger& gatheredOffset, uint32_t& scanSteps) {
	uint32_t rasterVertices = mvkPerVertexReplayVertexCount(topology);
	if (!plan || planBytes < 57 * sizeof(uint32_t) || !views || views > 32 || !rasterVertices) { return false; }
	auto word = [&](NSUInteger offset) { uint32_t value; memcpy(&value, static_cast<const uint8_t*>(plan) + offset, sizeof(value)); return value; };
	uint32_t draws = word(56 * sizeof(uint32_t));
	NSUInteger commandBytes = (indexed ? 5 : 4) * sizeof(uint32_t);
	if (word(0) || draws > maxDrawCount || !snapshot || draws > snapshotBytes / commandBytes) { return false; }
	auto frozen = [&](NSUInteger offset) { uint32_t value; memcpy(&value, static_cast<const uint8_t*>(snapshot) + offset, sizeof(value)); return value; };
	if (maxDrawCount == 1 && draws && word(55 * sizeof(uint32_t)) != 1) { return false; }
	uint64_t records = 0, primitives = 0;
	uint32_t vertices = 0;
	for (uint32_t draw = 0; draw < draws; ++draw) {
		NSUInteger offset = NSUInteger(draw) * commandBytes;
		uint32_t n = frozen(offset), instances = frozen(offset + sizeof(uint32_t));
		if (!n || !instances) { continue; }
		uint64_t expanded = uint64_t(instances) * views;
		if (!stride || expanded > UINT32_MAX) { return false; }
		uint64_t r = uint64_t(n) * expanded;
		if (r > UINT32_MAX) { return false; }
		uint64_t p = uint64_t(mvkPerVertexPrimitiveCount(n, topology)) * expanded;
		// Same uint32 table-index invariants as mvkCanEncodePerVertexDraw; counts are now bounded.
		if (p > UINT32_MAX / 3 || p * rasterVertices > UINT32_MAX / 2) { return false; }
		records = std::max(records, r);
		primitives = std::max(primitives, p);
		vertices = std::max(vertices, n);
	}
	MVKPerVertexScratchRequest sized{};
	NSUInteger gathered = 0;
	uint32_t scans = 0;
	if (records) {
		bool restart = mvkPerVertexRequiresRestartAssembly(indexed, primitiveRestart);
		primitives = std::max<uint64_t>(primitives, 1); // Valid bindings for active draws with no primitives.
		uint64_t occurrences = primitives * rasterVertices;
		uint64_t prefix = restart ? mvkPerVertexRestartIndexScratchSize(vertices) : 0;
		// All products fit uint64: records/stride are uint32, tables were bounded above, indices <= 40*UINT32_MAX.
		uint64_t lengths[] = {records * stride, occurrences * 8, primitives * 12, corners ? occurrences * 4 : 0, indexed ? prefix + uint64_t(vertices) * 4 : 0, restart ? 68 * sizeof(uint32_t) : sizeof(uint32_t)};
		uint64_t limit = std::min<uint64_t>(maxMTLBufferSize, NSUIntegerMax);
		for (uint64_t length : lengths) { if (length > limit) { return false; } }
		sized = {NSUInteger(lengths[0]), NSUInteger(lengths[1]), NSUInteger(lengths[2]), NSUInteger(lengths[3]), NSUInteger(lengths[4]), restart};
		gathered = NSUInteger(prefix);
		scans = restart ? mvkPerVertexIndirectRestartScanSteps(vertices) : 0;
	}
	request = sized;
	gatheredOffset = gathered;
	scanSteps = scans;
	return true;
}

static inline id<MTLBuffer> mvkNewPerVertexScratchBuffer(id<MTLDevice> device, NSUInteger length, bool shared) {
	return [device newBufferWithLength:length options:shared ? MTLResourceStorageModeShared : MTLResourceStorageModePrivate];
}

// MVK_CONFIG_PERVERTEX_SCRATCH_POOL=1: the scratch buffers of direct draws come from free lists by storage mode
// and power-of-two size class, instead of a new Metal buffer per draw. A buffer returns to its list only when its
// MVKPerVertexScratch is destroyed, at the release of its last reference: the completed handler that
// keepPerVertexScratchResident adds to every Metal command buffer encoding it, or the submission, destroyed once all
// its Metal command buffers completed. Pool buffers enter the residency set once, at creation, and stay there: the
// set does not count references, so removing one after a draw would evict it while a later draw reuses it.
// ponytail: the pool keeps its high-water mark until it is destroyed; trim the free lists if memory matters.
struct MVKPerVertexScratchPool {
	static constexpr uint8_t kMinSizeClass = 8;	// 256 bytes
	static uint8_t sizeClass(NSUInteger length) {
		uint8_t sizeClass = kMinSizeClass;
		while (sizeClass < 63 && (NSUInteger(1) << sizeClass) < length) { ++sizeClass; }
		return sizeClass;
	}

	MVKPerVertexScratchPool(NSUInteger maxLength, std::function<void(id<MTLBuffer>)> makeResident) : _maxLength(maxLength), _makeResident(std::move(makeResident)) {}
	MVKPerVertexScratchPool(const MVKPerVertexScratchPool&) = delete;
	MVKPerVertexScratchPool& operator=(const MVKPerVertexScratchPool&) = delete;
	~MVKPerVertexScratchPool() { for (auto& lists : _free) { for (auto& list : lists) { for (id<MTLBuffer> buffer : list) { [buffer release]; } } } }

	// Returns a retained buffer of at least length bytes (at most maxLength), and its class for give().
	id<MTLBuffer> take(id<MTLDevice> device, NSUInteger length, bool shared, uint8_t& sizeClassOut) {
		uint8_t c = sizeClassOut = sizeClass(length);
		{
			std::lock_guard<std::mutex> lock(_lock);
			auto& list = _free[shared][c];
			if ( !list.empty() ) {
				id<MTLBuffer> buffer = list.back();
				list.pop_back();
				return buffer;
			}
		}
		// Every request of this class is at most min(2^c, maxLength) bytes: a power of two above the limit would fail.
		id<MTLBuffer> buffer = mvkNewPerVertexScratchBuffer(device, std::min(NSUInteger(1) << c, _maxLength), shared);
		if (buffer && _makeResident) { _makeResident(buffer); }
		return buffer;
	}

	// Only once no Metal command buffer can use the buffer any more. Runs on completion threads.
	void give(id<MTLBuffer> buffer, bool shared, uint8_t c) {
		std::lock_guard<std::mutex> lock(_lock);
		try { _free[shared][c].push_back(buffer); } catch (const std::bad_alloc&) { [buffer release]; }
	}

private:
	std::mutex _lock;
	std::vector<id<MTLBuffer>> _free[2][64];
	NSUInteger _maxLength;
	std::function<void(id<MTLBuffer>)> _makeResident;
};

// Individually owned allocations: the shared scratch pool cannot recover from a nil Metal buffer.
struct MVKPerVertexScratch {
	id<MTLBuffer> buffers[14] = {};
	id<MTLComputePipelineState> indexPipeline = nil;
	id<MTLComputePipelineState> widenUint8Pipeline = nil;
	id<MTLComputePipelineState> indirectPipeline = nil;
	uint32_t indirectCapacity = 0;
	id<MTLComputePipelineState> tessTopologyPipeline = nil;
	// Direct draws with MVK_CONFIG_PERVERTEX_SCRATCH_POOL=1: the pool of the replay buffers, and their size classes.
	std::shared_ptr<MVKPerVertexScratchPool> pool;
	uint8_t poolSizeClasses[14] = {};
	MVKPerVertexScratch() = default;
	MVKPerVertexScratch(const MVKPerVertexScratch&) = delete;
	MVKPerVertexScratch& operator=(const MVKPerVertexScratch&) = delete;
	~MVKPerVertexScratch() {
		for (size_t i = 0; i < std::size(buffers); ++i) {
			if (poolSizeClasses[i]) { pool->give(buffers[i], isSharedReplayBuffer(i), poolSizeClasses[i]); } else { [buffers[i] release]; }
		}
		[indexPipeline release]; [widenUint8Pipeline release]; [indirectPipeline release]; [tessTopologyPipeline release];
	}

	static bool isSharedReplayBuffer(size_t i) { return (i > 0 && i < 5) || i == 7; }

	bool reserveReplay(id<MTLDevice> device, const MVKPerVertexScratchRequest& request) {
		NSUInteger lengths[] = {request.captureSize, sizeof(uint32_t), request.occurrenceSize, request.primitiveSize, request.cornerSize, request.indexSize, request.restart ? 68 * sizeof(uint32_t) : 0, request.tessSizes[0], request.tessSizes[1], request.tessSizes[2], request.tessSizes[3], request.tessSizes[4]};
		for (size_t i = 0; i < std::size(lengths); ++i) {
			if (!lengths[i]) { continue; }
			if (buffers[i]) { return false; }
			bool shared = isSharedReplayBuffer(i);
			id<MTLBuffer> buffer = pool ? pool->take(device, lengths[i], shared, poolSizeClasses[i]) : mvkNewPerVertexScratchBuffer(device, lengths[i], shared);
			if (!buffer || buffer.length < lengths[i] || (shared && !buffer.contents)) { [buffer release]; poolSizeClasses[i] = 0; return false; }
			buffers[i] = buffer;
		}
		return true;
	}

	bool reservePlan(id<MTLDevice> device, const MVKPerVertexScratchRequest& request) {
		// Indirect dispatch/draw arguments and replay constants share a 256-byte-aligned plan.
		NSUInteger length = std::max(request.planSize, request.tessSizes[5]);
		if (length) {
			if (buffers[12]) { return false; }
			id<MTLBuffer> buffer = mvkNewPerVertexScratchBuffer(device, length, true);
			if (!buffer || buffer.length < length || !buffer.contents) { [buffer release]; return false; }
			buffers[12] = buffer;
			// The GPU ORs admission failures into the status word; each submission starts admitted.
			memset(buffer.contents, 0, buffer.length);
		}
		if (request.snapshotSize) {
			if (buffers[13]) { return false; }
			id<MTLBuffer> snapshot = mvkNewPerVertexScratchBuffer(device, request.snapshotSize, true);
			if (!snapshot || snapshot.length < request.snapshotSize || !snapshot.contents) { [snapshot release]; return false; }
			buffers[13] = snapshot;
		}
		indirectCapacity = request.indirectCapacity;
		return true;
	}

	bool reserve(id<MTLDevice> device, const MVKPerVertexScratchRequest& request) { return reserveReplay(device, request) && reservePlan(device, request); }

	// Admission failures ORed by the GPU into the plan buffer; read only after the work completed.
	uint32_t getIndirectStatus() const { return indirectCapacity && buffers[12] ? *(volatile const uint32_t*)buffers[12].contents : 0; }

	// Nonzero when the GPU refused a TES draw whose levels have no proven topology. Read once the encoder waited.
	uint32_t getTessEvalStatus() const { return !indirectCapacity && buffers[12] ? *(volatile const uint32_t*)buffers[12].contents : 0; }
};

using MVKPerVertexScratchReservations = std::vector<std::shared_ptr<MVKPerVertexScratch>>;

// Publish only a complete reservation. Failure releases all allocations made by this attempt, or returns them to the pool.
// Indirect draws (sized while encoding, read back by length) and TES draws (test-only) never use the pool.
static inline bool mvkReservePerVertexScratch(id<MTLDevice> device, const std::vector<MVKPerVertexScratchRequest>& requests, MVKPerVertexScratchReservations& reservations, const std::shared_ptr<MVKPerVertexScratchPool>& pool = nullptr) {
	MVKPerVertexScratchReservations pending;
	pending.reserve(requests.size());
	for (const auto& request : requests) {
		auto scratch = std::make_shared<MVKPerVertexScratch>();
		if (!request.indirectCapacity && std::none_of(std::begin(request.tessSizes), std::end(request.tessSizes), [](NSUInteger size) { return size != 0; })) { scratch->pool = pool; }
		if (request.indirectCapacity ? !scratch->reservePlan(device, request) : !scratch->reserve(device, request)) { return false; }
		pending.push_back(std::move(scratch));
	}
	reservations = std::move(pending);
	return true;
}
