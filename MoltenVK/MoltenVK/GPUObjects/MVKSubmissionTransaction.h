/* Copyright (c) 2026 Jean-Philippe Meunier. Licensed under the Apache License, Version 2.0. */
#pragma once

#include <vulkan/vulkan.h>
#include <memory>
#include <vector>

// Keep preparation and dispatch separate even when a later batch fails. This helper
// is also exercised with CPU-only submissions that inject allocation failures.
template<class Submission, class Create, class Reserve, class Dispatch>
VkResult mvkSubmitTransaction(uint32_t count, Create create, Reserve reserve, Dispatch dispatch) {
	std::vector<std::unique_ptr<Submission>> pending;
	try {
		pending.reserve(count);
		for (uint32_t i = 0; i < count; ++i) {
			pending.emplace_back(create(i));
			VkResult result = reserve(*pending.back());
			if (result != VK_SUCCESS) { return result; }
		}
	} catch (const std::bad_alloc&) { return VK_ERROR_OUT_OF_HOST_MEMORY; }
	VkResult result = VK_SUCCESS;
	for (auto& submission : pending) {
		VkResult dispatched = dispatch(submission.release());
		if (result == VK_SUCCESS) { result = dispatched; }
	}
	return result;
}
