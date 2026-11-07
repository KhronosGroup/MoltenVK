/*
 * SPIRVDualSourceBlend.cpp
 *
 * Copyright (c) 2015-2026 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#include "SPIRVDualSourceBlend.h"

#ifndef MVK_EXCLUDE_SPIRV_TOOLS
#include "source/opt/build_module.h"
#include "source/opt/ir_context.h"
#include "source/opt/ir_builder.h"
#include "source/opt/type_manager.h"
#include "source/opt/constants.h"
#include "source/opt/decoration_manager.h"

using namespace spvtools;
using namespace spvtools::opt;
#endif

// Reports whether any decoration in the module is an Index, which only dual source blending uses.
// Read straight from the words, so that the overwhelming majority of shaders, which use no such
// decoration, cost a linear scan rather than a parse.
static bool usesDualSourceIndex(const std::vector<uint32_t>& spirv) {
	static constexpr size_t kHeaderWordCount = 5;
	for (size_t i = kHeaderWordCount; i + 2 < spirv.size(); ) {
		uint32_t wordCount = spirv[i] >> 16;
		if (wordCount == 0) { return false; }				// Malformed; the parser will say so.
		if (uint32_t(spirv[i] & 0xFFFF) == uint32_t(spv::Op::OpDecorate) &&
			spv::Decoration(spirv[i + 2]) == spv::Decoration::Index) { return true; }
		i += wordCount;
	}
	return false;
}

bool mvk::addMissingDualSourceOutput(std::vector<uint32_t>& spirv, std::string& log) {
#ifdef MVK_EXCLUDE_SPIRV_TOOLS
	return false;
#else
	if ( !usesDualSourceIndex(spirv) ) { return false; }

	std::unique_ptr<IRContext> ctx = BuildModule(SPV_ENV_VULKAN_1_3, nullptr, spirv.data(), spirv.size());
	if ( !ctx ) { log += "Could not parse SPIR-V."; return false; }

	Instruction* entryPoint = nullptr;
	for (auto& ep : ctx->module()->entry_points()) {
		if (ep.GetSingleWordInOperand(0) == uint32_t(spv::ExecutionModel::Fragment)) { entryPoint = &ep; }
	}
	if ( !entryPoint ) { return false; }
	Function* entry = ctx->GetFunction(entryPoint->GetSingleWordInOperand(1));
	if ( !entry ) { return false; }

	// The two sources are the outputs at location zero whose index is zero and one. An output
	// carrying no Index decoration means index zero, as an ordinary colour output does.
	auto* decoMgr = ctx->get_decoration_mgr();
	Instruction* sources[2] = { nullptr, nullptr };
	for (auto& inst : ctx->module()->types_values()) {
		if (inst.opcode() != spv::Op::OpVariable) { continue; }
		if (inst.GetSingleWordInOperand(0) != uint32_t(spv::StorageClass::Output)) { continue; }

		uint32_t location = ~0u, index = 0;
		for (auto* deco : decoMgr->GetDecorationsFor(inst.result_id(), false)) {
			switch (spv::Decoration(deco->GetSingleWordInOperand(1))) {
				case spv::Decoration::Location: location = deco->GetSingleWordInOperand(2); break;
				case spv::Decoration::Index:    index    = deco->GetSingleWordInOperand(2); break;
				default: break;
			}
		}
		if (location == 0 && index < 2) { sources[index] = &inst; }
	}

	// A shader that declares no second source is not blending from two of them, whatever else it
	// decorated with an Index, and is left exactly as it is.
	if ( !sources[1] ) { return false; }

	// An output the shader assigns needs nothing: Metal sees it because SPIRV-Cross emits it. One
	// the shader declares but never assigns is dropped as inactive, and one it never declares was
	// never there, so both have to be given a value before Metal will accept the function. The
	// returns to write them at are collected in the same walk.
	bool needs[2] = { true, true };
	std::vector<Instruction*> returns;
	for (auto& block : *entry) {
		for (auto& inst : block) {
			if (inst.opcode() == spv::Op::OpReturn) { returns.push_back(&inst); }
			for (uint32_t i = 0; i < inst.NumInOperands(); i++) {
				const auto& op = inst.GetInOperand(i);
				if (op.type != SPV_OPERAND_TYPE_ID || op.words.size() != 1) { continue; }
				for (uint32_t index = 0; index < 2; index++) {
					if (sources[index] && op.words[0] == sources[index]->result_id()) { needs[index] = false; }
				}
			}
		}
	}
	if ( !needs[0] && !needs[1] ) { return false; }

	auto* typeMgr = ctx->get_type_mgr();
	for (uint32_t index = 0; index < 2; index++) {
		if ( !needs[index] ) { continue; }

		uint32_t varId, valueTypeId;
		if (sources[index]) {
			varId = sources[index]->result_id();
			auto* ptrType = typeMgr->GetType(sources[index]->type_id())->AsPointer();
			if ( !ptrType ) { return false; }
			valueTypeId = typeMgr->GetId(ptrType->pointee_type());
		} else {
			// Only the first source can be missing entirely; the second is what got us here.
			analysis::Float f32(32);
			analysis::Vector v4f32(&f32, 4);
			valueTypeId = typeMgr->GetTypeInstruction(&v4f32);
			analysis::Pointer outPtr(typeMgr->GetRegisteredType(&v4f32), spv::StorageClass::Output);
			uint32_t outPtrTypeId = typeMgr->GetTypeInstruction(&outPtr);

			varId = ctx->TakeNextId();
			ctx->AddGlobalValue(std::unique_ptr<Instruction>(new Instruction(
				ctx.get(), spv::Op::OpVariable, outPtrTypeId, varId,
				{{SPV_OPERAND_TYPE_STORAGE_CLASS, {uint32_t(spv::StorageClass::Output)}}})));
			decoMgr->AddDecorationVal(varId, uint32_t(spv::Decoration::Location), 0);
			decoMgr->AddDecorationVal(varId, uint32_t(spv::Decoration::Index), index);
			entryPoint->AddOperand({SPV_OPERAND_TYPE_ID, {varId}});
		}
		if ( !valueTypeId ) { return false; }

		// Zeros, which the shader is free to write because Vulkan leaves the value of an output
		// it never assigns undefined.
		uint32_t zeroId = ctx->TakeNextId();
		ctx->AddGlobalValue(std::unique_ptr<Instruction>(new Instruction(
			ctx.get(), spv::Op::OpConstantNull, valueTypeId, zeroId, {})));
		for (auto* ret : returns) {
			InstructionBuilder b(ctx.get(), ret, IRContext::kAnalysisNone);
			b.AddStore(varId, zeroId);
		}
	}

	std::vector<uint32_t> out;
	ctx->module()->ToBinary(&out, true);
	spirv.swap(out);
	return true;
#endif
}
