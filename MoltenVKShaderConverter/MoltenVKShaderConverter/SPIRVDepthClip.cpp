/*
 * SPIRVDepthClip.cpp
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

#include "SPIRVDepthClip.h"

#include "source/opt/build_module.h"
#include "source/opt/ir_context.h"
#include "source/opt/ir_builder.h"
#include "source/opt/type_manager.h"
#include "source/opt/constants.h"
#include "source/opt/decoration_manager.h"

using namespace mvk;
using namespace spvtools;
using namespace spvtools::opt;

namespace {

class Transform {
public:
	Transform(IRContext* ctx, std::string& log) : _ctx(ctx), _log(log) {}

	bool run();

	/** Reports whether run() would rewrite this module, without changing it. */
	bool canApply() {
		uint32_t posVar; int32_t memberIdx;
		return findEntryPoint() && findPosition(posVar, memberIdx);
	}

private:
	bool findEntryPoint();
	bool findPosition(uint32_t& posVar, int32_t& memberIdx);
	void addStateBlock();
	void emitClipSpaceFixup(uint32_t posVar, int32_t memberIdx);

	// Declares the type if the shader does not already have it. A shader with no boolean or
	// unsigned arithmetic of its own has neither, and asking only for an existing id yields none.
	uint32_t T(analysis::Type* t) { return _ctx->get_type_mgr()->GetTypeInstruction(t); }
	uint32_t ptrT(uint32_t pointee, spv::StorageClass sc) {
		analysis::Pointer ptr(_ctx->get_type_mgr()->GetType(pointee), sc);
		return _ctx->get_type_mgr()->GetTypeInstruction(&ptr);
	}
	uint32_t uconst(uint32_t v) { return _ctx->get_constant_mgr()->GetUIntConstId(v); }
	uint32_t iconst(int32_t v)  { return _ctx->get_constant_mgr()->GetSIntConstId(v); }
	uint32_t fconst(float v)    { return _ctx->get_constant_mgr()->GetFloatConstId(v); }
	uint32_t bin(InstructionBuilder& b, uint32_t type, spv::Op op, uint32_t x, uint32_t y) {
		return b.AddBinaryOp(type, op, x, y)->result_id();
	}

	IRContext* _ctx;
	std::string& _log;
	Function* _entry = nullptr;
	Instruction* _entryPointInst = nullptr;
	uint32_t _stateVar = 0;

	analysis::Float _f32{32};
	analysis::Integer _u32{32, false};
	analysis::Bool _bool;
	analysis::Vector _v4f32{&_f32, 4};
	analysis::Vector _v4u32{&_u32, 4};
};

// The rewrite only has meaning for the stage that feeds the rasterizer, which is the one that
// writes a position Metal will clip against.
bool Transform::findEntryPoint() {
	for (auto& ep : _ctx->module()->entry_points()) {
		spv::ExecutionModel model = spv::ExecutionModel(ep.GetSingleWordInOperand(0));
		if (model != spv::ExecutionModel::Vertex &&
			model != spv::ExecutionModel::TessellationEvaluation &&
			model != spv::ExecutionModel::Geometry) { continue; }

		uint32_t fnId = ep.GetSingleWordInOperand(1);
		for (auto& fn : *_ctx->module()) {
			if (fn.result_id() == fnId) {
				_entry = &fn;
				_entryPointInst = &ep;
				return true;
			}
		}
	}
	_log += "no entry point writing a position";
	return false;
}

// Finds the position the shader writes, which GLSL usually places in the gl_PerVertex block and
// so decorates on the member rather than on the variable. memberIdx is -1 for a bare variable.
bool Transform::findPosition(uint32_t& posVar, int32_t& memberIdx) {
	auto* decoMgr = _ctx->get_decoration_mgr();
	auto* typeMgr = _ctx->get_type_mgr();
	posVar = 0;
	memberIdx = -1;

	for (auto& inst : _ctx->module()->types_values()) {
		if (inst.opcode() != spv::Op::OpVariable) { continue; }
		if (inst.GetSingleWordInOperand(0) != uint32_t(spv::StorageClass::Output)) { continue; }
		const analysis::Type* ptr = typeMgr->GetType(inst.type_id());
		if ( !ptr || !ptr->AsPointer() ) { continue; }
		const analysis::Type* pointee = ptr->AsPointer()->pointee_type();

		if (pointee->AsStruct()) {
			uint32_t structId = typeMgr->GetId(pointee);
			for (auto& anno : _ctx->module()->annotations()) {
				if (anno.opcode() != spv::Op::OpMemberDecorate) { continue; }
				if (anno.GetSingleWordInOperand(0) != structId) { continue; }
				if (spv::Decoration(anno.GetSingleWordInOperand(2)) != spv::Decoration::BuiltIn) { continue; }
				if (spv::BuiltIn(anno.GetSingleWordInOperand(3)) != spv::BuiltIn::Position) { continue; }
				uint32_t member = anno.GetSingleWordInOperand(1);
				const auto& members = pointee->AsStruct()->element_types();
				if (member < members.size() && typeMgr->GetId(members[member]) == T(&_v4f32)) {
					posVar = inst.result_id();
					memberIdx = int32_t(member);
					return true;
				}
			}
		} else if (typeMgr->GetId(pointee) == T(&_v4f32)) {
			for (auto* deco : decoMgr->GetDecorationsFor(inst.result_id(), false)) {
				if (spv::Decoration(deco->GetSingleWordInOperand(1)) == spv::Decoration::BuiltIn &&
					spv::BuiltIn(deco->GetSingleWordInOperand(2)) == spv::BuiltIn::Position) {
					posVar = inst.result_id();
					return true;
				}
			}
		}
	}
	_log += "the shader writes no position the mapping can reach";
	return false;
}

// struct { uvec4 negativeOneToOne; } in std140, matching SPIRVDepthClipState.
void Transform::addStateBlock() {
	auto* typeMgr = _ctx->get_type_mgr();
	auto* decoMgr = _ctx->get_decoration_mgr();

	analysis::Struct block({typeMgr->GetRegisteredType(&_v4u32)});
	uint32_t blockId = typeMgr->GetTypeInstruction(&block);
	decoMgr->AddDecoration(blockId, uint32_t(spv::Decoration::Block));
	decoMgr->AddMemberDecoration(blockId, 0, uint32_t(spv::Decoration::Offset), 0);

	uint32_t ptrId = ptrT(blockId, spv::StorageClass::Uniform);
	_stateVar = _ctx->TakeNextId();
	_ctx->AddGlobalValue(std::unique_ptr<Instruction>(new Instruction(
		_ctx, spv::Op::OpVariable, ptrId, _stateVar,
		{{SPV_OPERAND_TYPE_STORAGE_CLASS, {uint32_t(spv::StorageClass::Uniform)}}})));
	decoMgr->AddDecorationVal(_stateVar, uint32_t(spv::Decoration::DescriptorSet), kSPIRVDepthClipDescriptorSet);
	decoMgr->AddDecorationVal(_stateVar, uint32_t(spv::Decoration::Binding), kSPIRVDepthClipBinding);
}

// At every return of the entry point the position is read back and its depth mapped, or left
// alone, according to the flag the driver wrote when it recorded the draw. The arithmetic is the
// one SPIRV-Cross would have written, chosen at draw time rather than at compile time.
void Transform::emitClipSpaceFixup(uint32_t posVar, int32_t memberIdx) {
	std::vector<Instruction*> returns;
	for (auto& block : *_entry) {
		for (auto& inst : block) {
			if (inst.opcode() == spv::Op::OpReturn) { returns.push_back(&inst); }
		}
	}

	uint32_t f32T = T(&_f32), u32T = T(&_u32), vec4T = T(&_v4f32), uvec4T = T(&_v4u32);
	uint32_t vec4OutPtr = ptrT(vec4T, spv::StorageClass::Output);
	uint32_t uvec4UniPtr = ptrT(uvec4T, spv::StorageClass::Uniform);

	for (auto* ret : returns) {
		InstructionBuilder b(_ctx, ret, IRContext::kAnalysisNone);

		uint32_t state = b.AddLoad(uvec4T, b.AddAccessChain(uvec4UniPtr, _stateVar, {iconst(0)})->result_id())->result_id();
		uint32_t flag = b.AddCompositeExtract(u32T, state, {0})->result_id();
		uint32_t mapsDepth = bin(b, T(&_bool), spv::Op::OpINotEqual, flag, uconst(0));

		uint32_t target = memberIdx < 0 ? posVar
										: b.AddAccessChain(vec4OutPtr, posVar, {iconst(memberIdx)})->result_id();
		uint32_t pos = b.AddLoad(vec4T, target)->result_id();
		uint32_t z = b.AddCompositeExtract(f32T, pos, {2})->result_id();
		uint32_t w = b.AddCompositeExtract(f32T, pos, {3})->result_id();
		uint32_t mapped = bin(b, f32T, spv::Op::OpFMul, bin(b, f32T, spv::Op::OpFAdd, z, w), fconst(0.5f));
		uint32_t chosen = b.AddSelect(f32T, mapsDepth, mapped, z)->result_id();
		uint32_t x = b.AddCompositeExtract(f32T, pos, {0})->result_id();
		uint32_t y = b.AddCompositeExtract(f32T, pos, {1})->result_id();
		b.AddStore(target, b.AddCompositeConstruct(vec4T, {x, y, chosen, w})->result_id());
	}
}

bool Transform::run() {
	uint32_t posVar = 0;
	int32_t memberIdx = -1;
	if ( !findEntryPoint() || !findPosition(posVar, memberIdx) ) { return false; }

	addStateBlock();
	emitClipSpaceFixup(posVar, memberIdx);

	// From SPIR-V 1.4 the entry point lists every global the shader uses, and the state block is
	// now one of them.
	if (_ctx->module()->version() >= 0x00010400) {
		_entryPointInst->AddOperand({SPV_OPERAND_TYPE_ID, {_stateVar}});
	}
	return true;
}

std::unique_ptr<IRContext> buildContext(const std::vector<uint32_t>& spirv, std::string& log) {
	auto ctx = BuildModule(SPV_ENV_UNIVERSAL_1_6, nullptr, spirv.data(), spirv.size());
	if ( !ctx ) { log += "the shader could not be read"; }
	return ctx;
}

}

namespace mvk {

	bool mapDepthClipInShader(std::vector<uint32_t>& spirv, std::string& log) {
		auto ctx = buildContext(spirv, log);
		if ( !ctx ) { return false; }

		Transform xform(ctx.get(), log);
		if ( !xform.run() ) { return false; }

		std::vector<uint32_t> rewritten;
		ctx->module()->ToBinary(&rewritten, true);
		spirv = std::move(rewritten);
		return true;
	}

	bool canMapDepthClipInShader(const std::vector<uint32_t>& spirv, std::string& log) {
		auto ctx = buildContext(spirv, log);
		if ( !ctx ) { return false; }

		Transform xform(ctx.get(), log);
		return xform.canApply();
	}

}
