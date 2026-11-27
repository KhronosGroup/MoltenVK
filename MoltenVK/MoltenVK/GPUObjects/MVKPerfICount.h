/*
 * MVKPerfICount.h
 *
 * Enshrouded perf debug (D12, for C4): how many of the Metal draws MoltenVK encodes for
 * vkCmdDraw[Indexed]IndirectCount are real.
 *
 * MoltenVK encodes maxDrawCount Metal indirect draws on the CPU for every such command; a conversion
 * kernel then zeroes the ones at or beyond the GPU-side count. The
 * conversion kernels record, per command, the real count min(count, maxDrawCount) into a small shared
 * buffer (slots below), and the CPU keeps the encoded totals and a histogram of maxDrawCount values.
 * On by default since C4's cap corrects itself from these counters; MVK_PERF_ICOUNT_STATS=0 turns them off.
 * Every 20,000 commands a summary goes to stderr as "[mvk-perf] icount" lines.
 */

#pragma once

#import <Metal/Metal.h>
#include <algorithm>
#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <vector>

/** Slots of the GPU statistics buffer. Must match the count-conversion kernels. */
enum MVKPerfICountStat : uint32_t {
	kMVKPerfICountRealDraws,		// sum of min(count, maxDrawCount), wraps
	kMVKPerfICountMaxReal,			// largest real count in one command
	kMVKPerfICountMaxFillPerMille,	// largest real count / maxDrawCount, in 1/1000
	kMVKPerfICountEmptyCommands,	// commands whose count was 0
	kMVKPerfICountOverMax,			// commands whose count exceeded maxDrawCount
	kMVKPerfICountStatCount
};

/**
 * Enshrouded perf C4: the most Metal draws to encode for one vkCmdDraw[Indexed]IndirectCount.
 * MoltenVK encodes maxDrawCount draws on the CPU and zeroes the unused ones on the GPU; Enshrouded asks
 * for up to 10,368 per command but uses at most ~106 (D12, 25 Oct 2026). MVK_PERF_ICOUNT_MAX_DRAWS caps
 * maxDrawCount (default 256; 0 = no cap).
 *
 * The cap corrects itself: the conversion kernels count commands whose real count exceeded the capped
 * maxDrawCount (truncated: objects would be missing for that frame), and whenever that count grows the
 * cap doubles for commands recorded afterwards (never lowered), with a "[mvk-perf] C4" line on stderr.
 * That needs the counters, which are on unless MVK_PERF_ICOUNT_STATS=0.
 */
inline std::atomic<uint32_t>& mvkPerfICountCapValue() {
	static std::atomic<uint32_t> cap { [] {
		const char* s = getenv("MVK_PERF_ICOUNT_MAX_DRAWS");
		long n = s ? strtol(s, nullptr, 0) : 128;
		uint32_t c = n > 0 ? (uint32_t)std::min(n, 1L << 20) : 0;
		if (c) { fprintf(stderr, "[mvk-perf] C4 indirect-count draws capped at %u per command (self-correcting)\n", c); }
		else   { fprintf(stderr, "[mvk-perf] C4 indirect-count cap off\n"); }
		return c;
	}() };
	return cap;
}

inline uint32_t mvkPerfICountCap(uint32_t maxDrawCount) {
	uint32_t cap = mvkPerfICountCapValue().load(std::memory_order_relaxed);
	return cap ? std::min(maxDrawCount, cap) : maxDrawCount;
}

/**
 * C4s: one cap per site. Enshrouded's indirect-count commands come in a few kinds, told apart by the app's
 * maxDrawCount. With one shared cap, the rare kind that needs ~226 draws raised the cap for every command
 * (most use ~12), so 97% of encoded Metal draws were empty. Each of the first kMVKPerfICountSites-1 distinct
 * maxDrawCount values gets its own cap and its own GPU statistics slot, and raises only its own cap.
 * Site 0 is the shared fallback (the C4/C4d cap above). MVK_PERF_ICOUNT_PER_SITE=0 puts every command on site 0.
 */
static constexpr uint32_t kMVKPerfICountSites = 32;
static constexpr NSUInteger kMVKPerfICountSiteStride = 256;	// bytes per site's statistics, keeps buffer offsets aligned

struct MVKPerfICountSite {
	uint32_t appMax = 0;
	std::atomic<uint32_t> cap { 0 };
	uint32_t lastOverMax = 0;
	uint32_t windowOverMax = 0;	// OverMax at the last summary window
	uint32_t floor = 0;			// largest cap a truncation has needed; lowering never goes below it
	uint32_t quietWindows = 0;
};

inline MVKPerfICountSite* mvkPerfICountSites() {
	static MVKPerfICountSite sites[kMVKPerfICountSites];
	return sites;
}

inline std::mutex& mvkPerfICountSiteLock() {
	static std::mutex lock;
	return lock;
}

/** Returns the site for the app's maxDrawCount, assigning a new one if there is room, else 0. */
inline uint32_t mvkPerfICountSiteFor(uint32_t appMax) {
	static const bool perSite = [] { const char* s = getenv("MVK_PERF_ICOUNT_PER_SITE"); return !s || atoi(s) != 0; }();
	static const uint32_t startCap = mvkPerfICountCapValue().load(std::memory_order_relaxed);
	if ( !perSite || !startCap ) { return 0; }

	std::lock_guard<std::mutex> guard(mvkPerfICountSiteLock());
	auto* sites = mvkPerfICountSites();
	for (uint32_t i = 1; i < kMVKPerfICountSites; i++) {
		if (sites[i].appMax == appMax) { return i; }
		if (sites[i].appMax == 0) {
			sites[i].appMax = appMax;
			sites[i].cap.store(startCap, std::memory_order_relaxed);
			return i;
		}
	}
	return 0;
}

/** The capped draw count for the app's maxDrawCount, and the site it belongs to. */
inline uint32_t mvkPerfICountCap(uint32_t appMax, uint8_t& site) {
	site = (uint8_t)mvkPerfICountSiteFor(appMax);
	if (site == 0) { return mvkPerfICountCap(appMax); }
	uint32_t cap = mvkPerfICountSites()[site].cap.load(std::memory_order_relaxed);
	return std::min(appMax, cap);
}

inline bool mvkPerfICountStatsEnabled() {
	static const bool on = [] { const char* s = getenv("MVK_PERF_ICOUNT_STATS"); return !s || atoi(s) != 0; }();
	return on;
}

inline id<MTLBuffer> mvkPerfICountStatsBuffer(id<MTLDevice> mtlDevice) {
	static id<MTLBuffer> buff = [] (id<MTLDevice> dev) {
		id<MTLBuffer> b = [dev newBufferWithLength: kMVKPerfICountSites * kMVKPerfICountSiteStride
										   options: MTLResourceStorageModeShared | MTLResourceHazardTrackingModeUntracked];
		memset(b.contents, 0, b.length);
		return b;
	}(mtlDevice);
	return buff;
}

/** Called once per encoded IndirectCount command, with its site and (capped) maxDrawCount. */
inline void mvkPerfICountRecord(id<MTLBuffer> buff, uint32_t site, uint32_t maxDrawCount) {
	static std::mutex lock;
	static uint64_t commands = 0, encoded = 0, lastCommands = 0, lastEncoded = 0;
	static uint32_t lastReal = 0;
	static std::map<uint32_t, uint64_t> histogram;

	std::lock_guard<std::mutex> guard(lock);
	commands++; encoded += maxDrawCount; histogram[maxDrawCount]++;

	// MVK_PERF_ICOUNT_NO_RAISE=1 holds the cap (measurement only: truncated commands lose objects).
	static const bool noRaise = [] { const char* s = getenv("MVK_PERF_ICOUNT_NO_RAISE"); return s && atoi(s) != 0; }();

	// C4s: a site raises only its own cap when its own commands were truncated.
	if (site) {
		auto& s = mvkPerfICountSites()[site];
		uint32_t siteOverMax = ((const volatile uint32_t*)((const char*)buff.contents + site * kMVKPerfICountSiteStride))[kMVKPerfICountOverMax];
		if (siteOverMax != s.lastOverMax && !noRaise) {
			uint32_t cap = s.cap.load(std::memory_order_relaxed);
			if (cap < s.appMax) {
				uint32_t raised = std::min(cap * 2, s.appMax);
				s.cap.store(raised, std::memory_order_relaxed);
				s.floor = std::max(s.floor, raised);
				fprintf(stderr, "[mvk-perf] C4s: site %u (maxDrawCount %u) truncated %u more commands; cap raised %u -> %u\n",
						site, s.appMax, siteOverMax - s.lastOverMax, cap, raised);
				fflush(stderr);
			}
		}
		s.lastOverMax = siteOverMax;
	}

	// C4d: the starting cap, read at the first command (before any raise), and the high-water mark: the
	// largest cap a real truncation has needed this session. The fall-back never goes below either.
	static const uint32_t startCap = mvkPerfICountCapValue().load(std::memory_order_relaxed);
	static uint32_t floorCap = 0;

	// C4 self-correction: more truncated commands since the last look -> double the cap.
	const volatile uint32_t* stats = (const volatile uint32_t*)buff.contents;
	static uint32_t lastOverMax = 0;
	uint32_t overMax = stats[kMVKPerfICountOverMax];
	if (noRaise) { lastOverMax = overMax; }
	if (overMax != lastOverMax) {
		auto& capValue = mvkPerfICountCapValue();
		uint32_t cap = capValue.load(std::memory_order_relaxed);
		if (cap && cap < (1u << 20)) {
			capValue.store(cap * 2, std::memory_order_relaxed);
			floorCap = std::max(floorCap, cap * 2);
			fprintf(stderr, "[mvk-perf] C4: %u more truncated commands (largest real count so far %u); cap raised %u -> %u (floor now %u)\n",
					overMax - lastOverMax, stats[kMVKPerfICountMaxReal], cap, cap * 2, floorCap);
			fflush(stderr);
		}
		lastOverMax = overMax;
	}
	if (commands % 20000 != 0) { return; }

	// C4d: the cap also comes back down. kMVKPerfICountMaxReal is reset after every window of 20,000 commands
	// (~2-3 s), so it holds the largest real count of the last window. When that stayed at or below 40% of the
	// cap for 3 windows in a row, with no truncation, the cap halves (so the new cap is still >= 1.25x the recent
	// maximum), never below its starting value. Truncations still double it at once (above).
	// MVK_PERF_ICOUNT_DECAY=0 keeps the old rise-only behaviour.
	static const bool decay = [] { const char* s = getenv("MVK_PERF_ICOUNT_DECAY"); return !s || atoi(s) != 0; }();
	static uint32_t quietWindows = 0, lastOverMaxSeen = 0;
	uint32_t windowMax = stats[kMVKPerfICountMaxReal];
	if (decay && startCap) {
		auto& capValue = mvkPerfICountCapValue();
		uint32_t cap = capValue.load(std::memory_order_relaxed);
		bool truncated = stats[kMVKPerfICountOverMax] != lastOverMaxSeen;
		lastOverMaxSeen = stats[kMVKPerfICountOverMax];
		quietWindows = (!truncated && windowMax * 5 <= cap * 2) ? quietWindows + 1 : 0;
		uint32_t lowest = std::max(startCap, floorCap);	// high-water mark: never below what this session needed
		if (cap > lowest && quietWindows >= 3) {
			uint32_t lower = std::max(cap / 2, lowest);
			capValue.store(lower, std::memory_order_relaxed);
			fprintf(stderr, "[mvk-perf] C4d: largest real count %u in the last windows; cap lowered %u -> %u (floor %u)\n", windowMax, cap, lower, lowest);
			quietWindows = 0;
		}
		((volatile uint32_t*)buff.contents)[kMVKPerfICountMaxReal] = 0;	// next window (a GPU max may race this; harmless)
	}

	// Totals over all sites (C4s). GPU lags the CPU a little; fine for a summary.
	uint32_t real = 0, maxReal = windowMax, maxFill = 0, empty = 0, overMaxAll = 0;
	for (uint32_t i = 0; i < kMVKPerfICountSites; i++) {
		const volatile uint32_t* st = (const volatile uint32_t*)((const char*)buff.contents + i * kMVKPerfICountSiteStride);
		real += st[kMVKPerfICountRealDraws];
		if (i) { maxReal = std::max(maxReal, (uint32_t)st[kMVKPerfICountMaxReal]); }
		maxFill = std::max(maxFill, (uint32_t)st[kMVKPerfICountMaxFillPerMille]);
		empty += st[kMVKPerfICountEmptyCommands];
		overMaxAll += st[kMVKPerfICountOverMax];
	}
	uint64_t dCmd = commands - lastCommands, dEnc = encoded - lastEncoded, dReal = (uint32_t)(real - lastReal);
	fprintf(stderr, "[mvk-perf] icount: last %llu commands encoded %llu Metal draws, %llu real (%.2f%%); "
			"max real per command %u, max fill %.1f%%, empty commands %u, truncated %u (totals so far)\n",
			(unsigned long long)dCmd, (unsigned long long)dEnc, (unsigned long long)dReal, dEnc ? 100.0 * dReal / dEnc : 0.0,
			maxReal, maxFill / 10.0, empty, overMaxAll);
	{
		std::lock_guard<std::mutex> siteGuard(mvkPerfICountSiteLock());
		auto* sites = mvkPerfICountSites();
		fprintf(stderr, "[mvk-perf] icount: site caps (maxDrawCount->cap):");
		for (uint32_t i = 1; i < kMVKPerfICountSites && sites[i].appMax; i++) {
			fprintf(stderr, " %u->%u", sites[i].appMax, sites[i].cap.load(std::memory_order_relaxed));
		}
		fprintf(stderr, "\n");
	}
	// C4s: each site's cap also comes down to fit what it uses. When a site's largest real count stayed at or
	// below half its cap for 3 windows with no truncation, the cap drops to the next power of two above 1.5x
	// that count (at least 16), never below the site's floor. Truncations still raise it at once (above).
	if (decay) {
		std::lock_guard<std::mutex> siteGuard(mvkPerfICountSiteLock());
		auto* sites = mvkPerfICountSites();
		for (uint32_t i = 1; i < kMVKPerfICountSites && sites[i].appMax; i++) {
			auto& s = sites[i];
			volatile uint32_t* st = (volatile uint32_t*)((char*)buff.contents + i * kMVKPerfICountSiteStride);
			uint32_t wmax = st[kMVKPerfICountMaxReal];
			uint32_t overMaxNow = st[kMVKPerfICountOverMax];
			bool truncated = overMaxNow != s.windowOverMax;
			s.windowOverMax = overMaxNow;
			uint32_t cap = s.cap.load(std::memory_order_relaxed);
			s.quietWindows = (!truncated && wmax * 2 <= cap) ? s.quietWindows + 1 : 0;
			if (s.quietWindows >= 3) {
				uint32_t target = 16;
				while (target < wmax + wmax / 2 + 1) { target *= 2; }
				target = std::max(target, s.floor);
				if (target < cap) {
					s.cap.store(target, std::memory_order_relaxed);
					fprintf(stderr, "[mvk-perf] C4s: site %u (maxDrawCount %u) largest real count %u; cap lowered %u -> %u (floor %u)\n",
							i, s.appMax, wmax, cap, target, s.floor);
				}
				s.quietWindows = 0;
			}
			st[kMVKPerfICountMaxReal] = 0;	// next window (a GPU max may race this; harmless)
		}
	}

	std::vector<std::pair<uint64_t, uint32_t>> v;
	for (auto& kv : histogram) { v.emplace_back(kv.second, kv.first); }
	std::sort(v.rbegin(), v.rend());
	fprintf(stderr, "[mvk-perf] icount: maxDrawCount values (commands so far):");
	for (size_t i = 0; i < v.size() && i < 12; i++) { fprintf(stderr, " %u x%llu", v[i].second, (unsigned long long)v[i].first); }
	fprintf(stderr, "\n");
	fflush(stderr);
	lastCommands = commands; lastEncoded = encoded; lastReal = real;
}
