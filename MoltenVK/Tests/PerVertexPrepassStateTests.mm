/*
 * Copyright (c) 2026 Jean-Philippe Meunier
 * SPDX-License-Identifier: Apache-2.0
 */
// CPU only, no Metal device: the Vulkan encoder state the PerVertex prepass saves before a subpass, changes by applying
// the state commands of that subpass, then restores before encoding it (MVK_CONFIG_PERVERTEX_PREPASS=1). Linked against
// libMoltenVK, whose copy operators of MVKVulkanCommonEncoderState it exercises.
#include "MVKCommandEncoderState.h"
#include <cstdio>
#include <cstring>

static int failures = 0;
#define EXPECT(cond) do { if (!(cond)) { std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

// Binds and fills a push descriptor, as vkCmdPushDescriptorSetKHR does through a layout with a push descriptor set 0.
static void pushDescriptor(MVKCommandEncoderState& state, uint32_t size, uint8_t value) {
	auto& graphics = state.updateDynamicState(MVKRenderStateFlags());
	graphics.ensurePushDescriptorSize(size);
	graphics._pushDescriptor.cpuBufferSize = size;
	graphics._descriptorSets[0] = &graphics._pushDescriptor;
	memset(graphics._pushDescriptor.cpuBuffer, value, size);
}

static void bindVertexBuffer(MVKCommandEncoderState& state, VkDeviceSize offset) {
	MVKVertexMTLBufferBinding binding = {};
	binding.offset = offset;
	state.bindVertexBuffers(2, MVKArrayRef<const MVKVertexMTLBufferBinding>(&binding, 1));
}

// grow: the subpass pushes a larger descriptor, which reallocates the live push descriptor storage.
static void expectRestored(bool grow) {
	MVKCommandEncoderState state{};
	pushDescriptor(state, 64, 0x11);
	const uint8_t constants[8] = {1, 2, 3, 4, 5, 6, 7, 8};
	state.pushConstants(0, sizeof(constants), constants);
	bindVertexBuffer(state, 48);
	{
		MVKVulkanStateSnapshot saved = state.saveVulkanState();
		pushDescriptor(state, grow ? 4096 : 64, 0x22);
		const uint8_t later[8] = {9, 9, 9, 9, 9, 9, 9, 9};
		state.pushConstants(0, sizeof(later), later);
		bindVertexBuffer(state, 96);
		state.restoreVulkanState(std::move(saved));
	}
	// The snapshot is destroyed: the restored state must own everything it points to.
	const auto& graphics = state.vkGraphics();
	bool owned = graphics._pushDescriptor.cpuBuffer == reinterpret_cast<const char*>(graphics._pushDescData.data());
	EXPECT(owned);
	EXPECT(graphics._descriptorSets[0] == &graphics._pushDescriptor);
	EXPECT(graphics._pushDescriptor.cpuBufferSize == 64);
	if (owned) {
		bool same = true;
		for (uint32_t i = 0; i < 64; i++) { same = same && uint8_t(graphics._pushDescriptor.cpuBuffer[i]) == 0x11; }
		EXPECT(same);
	}
	// Small push constants live in the vector's inline storage: after the move, inside the live state, not the snapshot.
	const char* pushConstants = reinterpret_cast<const char*>(state.vkShared()._pushConstants.data());
	EXPECT(pushConstants >= reinterpret_cast<const char*>(&state) && pushConstants < reinterpret_cast<const char*>(&state + 1));
	EXPECT(state.vkShared()._pushConstants.size() >= sizeof(constants) && !memcmp(pushConstants, constants, sizeof(constants)));
	EXPECT(graphics._vertexBuffers[2].offset == 48);
}

int main() {
	expectRestored(false);
	expectRestored(true);
	if (failures) { std::fprintf(stderr, "prepass state: %d failures\n", failures); return 1; }
	std::printf("prepass state: snapshot and restore passed (in place and grown push descriptor)\n");
	return 0;
}
