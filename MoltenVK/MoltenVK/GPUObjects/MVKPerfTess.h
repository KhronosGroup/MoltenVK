/*
 * MVKPerfTess.h
 *
 * Enshrouded perf test (C7): vertex budget for tessellated indirect draws, and GPU-side statistics.
 *
 * MVK_PERF_TESS_INDIRECT_VERTS sets how many vertices (vertexCount x instanceCount) one tessellated
 * indirect draw may produce. The scratch buffers are sized for it, and the conversion kernels clamp
 * a bigger draw instead of letting it write past them. Default: 1,048,576, MoltenVK's own
 * kMVKMaxDrawIndirectVertexCount.
 *
 * The conversion kernels also record the largest sizes they see, before clamping, into a small
 * shared buffer. The CPU reads it when a command buffer completes and prints a line to stderr
 * when a maximum grows, or (at most once a second) when draws were clamped.
 */

#pragma once

#import <Metal/Metal.h>
#include "MVKEnvironment.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <mutex>

/** Slots of the statistics buffer. Must match the kernels in MVKCommandPipelineStateFactoryShaderSource.h. */
enum MVKPerfTessStat : uint32_t {
	kMVKPerfTessMaxVertices,		// vertexCount x instanceCount
	kMVKPerfTessMaxVertexCount,
	kMVKPerfTessMaxInstanceCount,
	kMVKPerfTessMaxPatches,
	kMVKPerfTessClampedDraws,
	kMVKPerfTessStatCount
};

/** The vertex budget for one tessellated indirect draw. */
inline uint32_t mvkPerfTessIndirectVerts() {
	static const uint32_t budget = [] {
		const char* env = getenv("MVK_PERF_TESS_INDIRECT_VERTS");
		long n = env ? strtol(env, nullptr, 0) : 0;
		uint32_t b = (n >= 64 && n <= (1L << 24)) ? (uint32_t)n : (mvkPerfIsEnshrouded() ? 262144 : 1024 * 1024);
		fprintf(stderr, "[mvk-perf] tessellated indirect draw budget: %u vertices%s\n", b, (env && b == n) ? "" : " (default)");
		return b;
	}();
	return budget;
}

/** The statistics buffer, shared by all command buffers. Created once and never released. */
inline id<MTLBuffer> mvkPerfTessStatsBuffer(id<MTLDevice> mtlDevice) {
	static id<MTLBuffer> buff = [] (id<MTLDevice> dev) {
		id<MTLBuffer> b = [dev newBufferWithLength: kMVKPerfTessStatCount * sizeof(uint32_t)
										   options: MTLResourceStorageModeShared | MTLResourceHazardTrackingModeUntracked];
		memset(b.contents, 0, b.length);
		return b;
	}(mtlDevice);
	return buff;
}

/** Called when a command buffer that ran a conversion kernel completes. */
inline void mvkPerfTessReport(id<MTLBuffer> buff) {
	static std::mutex lock;
	static uint32_t logged[kMVKPerfTessStatCount] = {};
	static time_t lastClampLog = 0;

	uint32_t now[kMVKPerfTessStatCount];
	const volatile uint32_t* stats = (const volatile uint32_t*)buff.contents;
	for (uint32_t i = 0; i < kMVKPerfTessStatCount; i++) { now[i] = stats[i]; }

	std::lock_guard<std::mutex> guard(lock);
	bool grew = false;
	for (uint32_t i = 0; i < kMVKPerfTessClampedDraws; i++) { grew |= now[i] > logged[i]; }
	time_t t = time(nullptr);
	bool clamped = now[kMVKPerfTessClampedDraws] > logged[kMVKPerfTessClampedDraws] && t != lastClampLog;
	if ( !grew && !clamped ) { return; }

	fprintf(stderr, "[mvk-perf] tess indirect %ld: max vertices %u, max vertexCount %u, max instanceCount %u, max patches %u, clamped draws %u, budget %u\n",
			(long)t, now[kMVKPerfTessMaxVertices], now[kMVKPerfTessMaxVertexCount], now[kMVKPerfTessMaxInstanceCount],
			now[kMVKPerfTessMaxPatches], now[kMVKPerfTessClampedDraws], mvkPerfTessIndirectVerts());
	memcpy(logged, now, sizeof(now));
	if (clamped) { lastClampLog = t; }
}
