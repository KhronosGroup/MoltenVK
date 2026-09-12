/*
 * SPIRVBlendInShader.cpp
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

#include "SPIRVBlendInShader.h"

#include "source/opt/build_module.h"
#include "source/opt/ir_context.h"
#include "source/opt/ir_builder.h"
#include "source/opt/type_manager.h"
#include "source/opt/constants.h"
#include "source/opt/decoration_manager.h"
#include "source/util/string_utils.h"
#include "spirv/unified1/GLSL.std.450.h"

#include <map>

using namespace mvk;
using namespace spvtools;
using namespace spvtools::opt;

namespace {

/** A color output the shader writes, and the fetch of its destination that the transform adds. */
struct ColorOutput {
	Instruction* var = nullptr;		// The OpVariable, Output storage class.
	uint32_t location = 0;
	uint32_t index = 0;				// 0, or 1 for the second source of dual-source blending.
	uint32_t componentCount = 0;	// 1..4
	bool isFloat = false;
	bool isSigned = false;
	uint32_t fetchVar = 0;			// The subpass input variable added for index 0 outputs.
	uint32_t fetchImageType = 0;	// The OpTypeImage of that variable.
};

/** The VkBlendFactor values, in enum order. */
enum BlendFactor : uint32_t {
	kZero, kOne, kSrcColor, kOneMinusSrcColor, kDstColor, kOneMinusDstColor,
	kSrcAlpha, kOneMinusSrcAlpha, kDstAlpha, kOneMinusDstAlpha,
	kConstantColor, kOneMinusConstantColor, kConstantAlpha, kOneMinusConstantAlpha,
	kSrcAlphaSaturate, kSrc1Color, kOneMinusSrc1Color, kSrc1Alpha, kOneMinusSrc1Alpha,
	kBlendFactorCount
};

/** The VkBlendOp values, in enum order. */
enum BlendOp : uint32_t { kAdd, kSubtract, kReverseSubtract, kMin, kMax };

class Transform {
public:
	Transform(IRContext* ctx, bool multisampled, uint32_t attachmentMask, bool dynamicMultisample, std::string& log)
		: _ctx(ctx), _multisampled(multisampled), _attachmentMask(attachmentMask),
		  _dynamicMultisample(dynamicMultisample), _log(log) {}

	bool run();
	/** Reports whether run() would transform this module, without changing it. */
	bool canApply() { return findEntryPoint() && collectOutputs(); }
	/** Whether the shader has the location zero output that alpha to coverage reads. */
	bool hasCoverageOutput() const { return _coverageVar != 0; }

private:
	bool findEntryPoint();
	bool collectOutputs();
	void addBlendStateBlock();
	void addFetchVariables();
	void addEpilogueBefore(Instruction* ret);
	void emitOutput(InstructionBuilder& b, ColorOutput& out, uint32_t blendStateVar);
	void emitSampleMask(InstructionBuilder& b);
	void storeSampleMask(InstructionBuilder& b, uint32_t value);
	uint32_t ptrT(uint32_t pointee, spv::StorageClass sc);

	// Type and constant helpers.
	uint32_t floatT()  { return _ctx->get_type_mgr()->GetId(&_f32); }
	uint32_t uintT()   { return _ctx->get_type_mgr()->GetId(&_u32); }
	uint32_t intT()    { return _ctx->get_type_mgr()->GetId(&_s32); }
	uint32_t boolT()   { return _ctx->get_type_mgr()->GetId(&_bool); }
	uint32_t vec4T()   { return _ctx->get_type_mgr()->GetId(&_v4f32); }
	uint32_t vec3T()   { return _ctx->get_type_mgr()->GetId(&_v3f32); }
	uint32_t uvec4T()  { return _ctx->get_type_mgr()->GetId(&_v4u32); }
	uint32_t ivec2T()  { return _ctx->get_type_mgr()->GetId(&_v2s32); }
	uint32_t bvec4T()  { return _ctx->get_type_mgr()->GetId(&_v4bool); }
	uint32_t vecT(uint32_t n, bool isFloat, bool isSigned);

	uint32_t uconst(uint32_t v) { return _ctx->get_constant_mgr()->GetUIntConstId(v); }
	uint32_t iconst(int32_t v)  { return _ctx->get_constant_mgr()->GetSIntConstId(v); }
	uint32_t fconst(float v)    { return _ctx->get_constant_mgr()->GetFloatConstId(v); }
	uint32_t vec4const(float x, float y, float z, float w);

	// Blend arithmetic, all on vec4 float32.
	uint32_t splatScalar(InstructionBuilder& b, uint32_t scalar);
	uint32_t selectByEqual(InstructionBuilder& b, uint32_t sel, uint32_t value, uint32_t ifEqual, uint32_t elseVal);
	uint32_t splatBool(InstructionBuilder& b, uint32_t cond);
	uint32_t splat(InstructionBuilder& b, uint32_t vec, uint32_t component);
	uint32_t fsub(InstructionBuilder& b, uint32_t a, uint32_t c) { return b.AddBinaryOp(vec4T(), spv::Op::OpFSub, a, c)->result_id(); }
	uint32_t fmul(InstructionBuilder& b, uint32_t a, uint32_t c) { return b.AddBinaryOp(vec4T(), spv::Op::OpFMul, a, c)->result_id(); }
	uint32_t fadd(InstructionBuilder& b, uint32_t a, uint32_t c) { return b.AddBinaryOp(vec4T(), spv::Op::OpFAdd, a, c)->result_id(); }
	uint32_t glsl(InstructionBuilder& b, uint32_t type, uint32_t inst, std::vector<uint32_t> args);
	uint32_t clampVec(InstructionBuilder& b, uint32_t v, uint32_t mode);

	IRContext* _ctx;
	bool _multisampled;
	uint32_t _attachmentMask;
	bool _dynamicMultisample;
	uint32_t _alphaToOne = 0;		// Set by emitSampleMask(), read when each output is written.
	uint32_t _coverageVar = 0;		// The location zero output, which alpha to coverage reads.
	std::string& _log;
	Function* _entry = nullptr;
	Instruction* _entryPointInst = nullptr;
	std::vector<ColorOutput> _outputs;
	uint32_t _blendStateVar = 0;
	uint32_t _glslStd450 = 0;
	uint32_t _sampleId = 0;			// gl_SampleID, needed to read a multisampled subpass input.
	std::map<uint32_t, std::pair<uint32_t, uint32_t>> _fetchTypes;	// sampled type id -> (image type, pointer type)
	std::pair<uint32_t, uint32_t> fetchTypesFor(uint32_t sampledId);
	uint32_t sampleId();

	analysis::Float _f32{32};
	analysis::Integer _u32{32, false};
	analysis::Integer _s32{32, true};
	analysis::Bool _bool;
	analysis::Vector _v4f32{&_f32, 4};
	analysis::Vector _v3f32{&_f32, 3};
	analysis::Vector _v4u32{&_u32, 4};
	analysis::Vector _v2s32{&_s32, 2};
	analysis::Vector _v4bool{&_bool, 4};
};

bool Transform::findEntryPoint() {
	for (auto& ep : _ctx->module()->entry_points()) {
		if (ep.GetSingleWordInOperand(0) == uint32_t(spv::ExecutionModel::Fragment)) {
			_entryPointInst = &ep;
			_entry = _ctx->GetFunction(ep.GetSingleWordInOperand(1));
			return _entry != nullptr;
		}
	}
	_log += "Not a fragment shader.";
	return false;
}

bool Transform::collectOutputs() {
	auto* decoMgr = _ctx->get_decoration_mgr();
	auto* typeMgr = _ctx->get_type_mgr();

	// A shader that already reads subpass inputs would need its own attachment indices
	// remapped alongside the ones added here, which this transform does not attempt.
	for (auto& inst : _ctx->module()->types_values()) {
		if (inst.opcode() == spv::Op::OpTypeImage &&
			inst.GetSingleWordInOperand(1) == uint32_t(spv::Dim::SubpassData)) {
			_log += "Shader already uses subpass inputs.";
			return false;
		}
	}

	for (auto& inst : _ctx->module()->types_values()) {
		if (inst.opcode() != spv::Op::OpVariable) { continue; }
		if (inst.GetSingleWordInOperand(0) != uint32_t(spv::StorageClass::Output)) { continue; }

		bool hasLocation = false, isBuiltIn = false;
		uint32_t location = 0, index = 0;
		for (auto* deco : decoMgr->GetDecorationsFor(inst.result_id(), false)) {
			switch (spv::Decoration(deco->GetSingleWordInOperand(1))) {
				case spv::Decoration::Location: hasLocation = true; location = deco->GetSingleWordInOperand(2); break;
				case spv::Decoration::Index:    index = deco->GetSingleWordInOperand(2); break;
				case spv::Decoration::BuiltIn:  isBuiltIn = true; break;
				default: break;
			}
		}
		if (isBuiltIn || !hasLocation) { continue; }

		const analysis::Type* ptrType = typeMgr->GetType(inst.type_id());
		const analysis::Type* valType = ptrType->AsPointer()->pointee_type();
		const analysis::Type* scalar = valType;
		uint32_t count = 1;
		if (auto* vec = valType->AsVector()) { scalar = vec->element_type(); count = vec->element_count(); }

		ColorOutput out;
		out.var = &inst; out.location = location; out.index = index; out.componentCount = count;
		if (auto* f = scalar->AsFloat()) {
			if (f->width() != 32) { _log += "Output is not 32-bit."; return false; }
			out.isFloat = true;
		} else if (auto* i = scalar->AsInteger()) {
			if (i->width() != 32) { _log += "Output is not 32-bit."; return false; }
			out.isSigned = i->IsSigned();
		} else {
			_log += "Output is not a scalar or vector.";
			return false;
		}
		if (location >= kSPIRVBlendMaxAttachments || index > 1) { _log += "Output location or index out of range."; return false; }
		if (out.index != 0) {
			_log += "Dual source blending is not supported by the in-shader blend.";
			return false;
		}
		// Alpha to coverage reads location zero whether or not an attachment sits behind it, so
		// the coverage source is noted before the outputs with no attachment are dropped.
		if (location == 0 && out.isFloat && count == 4) { _coverageVar = inst.result_id(); }
		if ( !(_attachmentMask & (1u << location)) ) { continue; }		// No attachment: leave it alone.
		if (out.componentCount != 4) {
			_log += "Blended color output is not 4-component; Metal requires the fetch to match its width.";
			return false;
		}
		_outputs.push_back(out);
	}

	// An empty set is not a failure. The shader writes no colour this draw can blend, but it can
	// still take over the sample mask, and the caller has already dropped blend state from its key.
	return true;
}

uint32_t Transform::ptrT(uint32_t pointee, spv::StorageClass sc) {
	auto* typeMgr = _ctx->get_type_mgr();
	analysis::Pointer ptr(typeMgr->GetType(pointee), sc);
	return typeMgr->GetTypeInstruction(&ptr);
}

uint32_t Transform::vecT(uint32_t n, bool isFloat, bool isSigned) {
	auto* typeMgr = _ctx->get_type_mgr();
	const analysis::Type* scalar = isFloat ? (const analysis::Type*)&_f32 : (isSigned ? (const analysis::Type*)&_s32 : (const analysis::Type*)&_u32);
	if (n == 1) { return typeMgr->GetId(scalar); }
	analysis::Vector v(scalar, n);
	return typeMgr->GetTypeInstruction(&v);
}

uint32_t Transform::vec4const(float x, float y, float z, float w) {
	auto* constMgr = _ctx->get_constant_mgr();
	auto* typeMgr = _ctx->get_type_mgr();
	const analysis::Type* v4 = typeMgr->GetRegisteredType(&_v4f32);
	std::vector<uint32_t> ids = { fconst(x), fconst(y), fconst(z), fconst(w) };
	const analysis::Constant* c = constMgr->GetConstant(v4, ids);
	return constMgr->GetDefiningInstruction(c)->result_id();
}

void Transform::addBlendStateBlock() {
	auto* typeMgr = _ctx->get_type_mgr();
	auto* decoMgr = _ctx->get_decoration_mgr();

	// struct { vec4 constantTerm[32]; vec4 coefficients[32]; vec4 saturate[8];
	//          vec4 opFactors[8]; uvec4 control[8]; } in std140.
	const uint32_t slotCount = kSPIRVBlendMaxAttachments * kSPIRVBlendSlotCount;
	auto makeArray = [&](const analysis::Type* elem, uint32_t count) {
		analysis::Array arr(elem, analysis::Array::LengthInfo{uconst(count), {analysis::Array::LengthInfo::kConstant, count}});
		uint32_t id = typeMgr->GetTypeInstruction(&arr);
		decoMgr->AddDecorationVal(id, uint32_t(spv::Decoration::ArrayStride), 16);
		return id;
	};
	uint32_t vec4Arr32 = makeArray(typeMgr->GetRegisteredType(&_v4f32), slotCount);
	uint32_t vec4Arr8  = makeArray(typeMgr->GetRegisteredType(&_v4f32), kSPIRVBlendMaxAttachments);
	uint32_t uvec4Arr8 = makeArray(typeMgr->GetRegisteredType(&_v4u32), kSPIRVBlendMaxAttachments);

	analysis::Struct block({typeMgr->GetType(vec4Arr32), typeMgr->GetType(vec4Arr32),
							typeMgr->GetType(vec4Arr8), typeMgr->GetType(vec4Arr8), typeMgr->GetType(uvec4Arr8),
							typeMgr->GetRegisteredType(&_v4u32)});
	uint32_t blockId = typeMgr->GetTypeInstruction(&block);
	decoMgr->AddDecoration(blockId, uint32_t(spv::Decoration::Block));
	const uint32_t offsets[] = { 0, 16 * slotCount, 32 * slotCount,
								 32 * slotCount + 16 * kSPIRVBlendMaxAttachments,
								 32 * slotCount + 32 * kSPIRVBlendMaxAttachments,
								 32 * slotCount + 48 * kSPIRVBlendMaxAttachments };
	for (uint32_t m = 0; m < 6; m++) { decoMgr->AddMemberDecoration(blockId, m, uint32_t(spv::Decoration::Offset), offsets[m]); }

	analysis::Pointer ptr(typeMgr->GetType(blockId), spv::StorageClass::Uniform);
	uint32_t ptrId = typeMgr->GetTypeInstruction(&ptr);

	_blendStateVar = _ctx->TakeNextId();
	_ctx->AddGlobalValue(std::unique_ptr<Instruction>(new Instruction(
		_ctx, spv::Op::OpVariable, ptrId, _blendStateVar,
		{{SPV_OPERAND_TYPE_STORAGE_CLASS, {uint32_t(spv::StorageClass::Uniform)}}})));
	decoMgr->AddDecorationVal(_blendStateVar, uint32_t(spv::Decoration::DescriptorSet), kSPIRVBlendStateDescriptorSet);
	decoMgr->AddDecorationVal(_blendStateVar, uint32_t(spv::Decoration::Binding), kSPIRVBlendStateBinding);
}

void Transform::addFetchVariables() {
	auto* decoMgr = _ctx->get_decoration_mgr();
	if (_outputs.empty()) { return; }		// Nothing to fetch, so the capability is not needed.
	_ctx->AddCapability(spv::Capability::InputAttachment);

	for (auto& out : _outputs) {
		if (out.index != 0) { continue; }
		uint32_t sampledId = out.isFloat ? floatT() : (out.isSigned ? intT() : uintT());
		auto types = fetchTypesFor(sampledId);
		out.fetchImageType = types.first;
		uint32_t ptrId = types.second;

		out.fetchVar = _ctx->TakeNextId();
		_ctx->AddGlobalValue(std::unique_ptr<Instruction>(new Instruction(
			_ctx, spv::Op::OpVariable, ptrId, out.fetchVar,
			{{SPV_OPERAND_TYPE_STORAGE_CLASS, {uint32_t(spv::StorageClass::UniformConstant)}}})));
		// SPIRV-Cross takes the [[color(n)]] index from InputAttachmentIndex. The set and
		// binding keep the variable out of any set the application uses.
		decoMgr->AddDecorationVal(out.fetchVar, uint32_t(spv::Decoration::InputAttachmentIndex), out.location);
		decoMgr->AddDecorationVal(out.fetchVar, uint32_t(spv::Decoration::DescriptorSet), kSPIRVBlendStateDescriptorSet);
		decoMgr->AddDecorationVal(out.fetchVar, uint32_t(spv::Decoration::Binding), kSPIRVBlendStateBinding + 1 + out.location);
	}
}

std::pair<uint32_t, uint32_t> Transform::fetchTypesFor(uint32_t sampledId) {
	auto found = _fetchTypes.find(sampledId);
	if (found != _fetchTypes.end()) { return found->second; }

	// Built directly rather than through the type manager, which always writes the optional
	// access qualifier operand, and that operand requires the Kernel capability.
	uint32_t imgId = _ctx->TakeNextId();
	_ctx->AddType(std::unique_ptr<Instruction>(new Instruction(
		_ctx, spv::Op::OpTypeImage, 0, imgId,
		{{SPV_OPERAND_TYPE_ID, {sampledId}},
		 {SPV_OPERAND_TYPE_DIMENSIONALITY, {uint32_t(spv::Dim::SubpassData)}},
		 {SPV_OPERAND_TYPE_LITERAL_INTEGER, {0}},
		 {SPV_OPERAND_TYPE_LITERAL_INTEGER, {0}},
		 {SPV_OPERAND_TYPE_LITERAL_INTEGER, {_multisampled ? 1u : 0u}},
		 {SPV_OPERAND_TYPE_LITERAL_INTEGER, {2}},
		 {SPV_OPERAND_TYPE_SAMPLER_IMAGE_FORMAT, {uint32_t(spv::ImageFormat::Unknown)}}})));
	uint32_t ptrId = _ctx->TakeNextId();
	_ctx->AddType(std::unique_ptr<Instruction>(new Instruction(
		_ctx, spv::Op::OpTypePointer, 0, ptrId,
		{{SPV_OPERAND_TYPE_STORAGE_CLASS, {uint32_t(spv::StorageClass::UniformConstant)}},
		 {SPV_OPERAND_TYPE_ID, {imgId}}})));
	_fetchTypes[sampledId] = { imgId, ptrId };
	return _fetchTypes[sampledId];
}

uint32_t Transform::sampleId() {
	// Reading a multisampled subpass input needs the sample being shaded, which also makes the
	// shader run per sample, as blending against a multisampled attachment must.
	if (_sampleId) { return _sampleId; }
	auto* decoMgr = _ctx->get_decoration_mgr();
	for (auto& inst : _ctx->module()->types_values()) {
		if (inst.opcode() != spv::Op::OpVariable) { continue; }
		for (auto* deco : decoMgr->GetDecorationsFor(inst.result_id(), false)) {
			if (spv::Decoration(deco->GetSingleWordInOperand(1)) == spv::Decoration::BuiltIn &&
				spv::BuiltIn(deco->GetSingleWordInOperand(2)) == spv::BuiltIn::SampleId) {
				_sampleId = inst.result_id();
				return _sampleId;
			}
		}
	}
	_ctx->AddCapability(spv::Capability::SampleRateShading);
	analysis::Pointer ptr(_ctx->get_type_mgr()->GetRegisteredType(&_s32), spv::StorageClass::Input);
	uint32_t ptrId = _ctx->get_type_mgr()->GetTypeInstruction(&ptr);
	_sampleId = _ctx->TakeNextId();
	_ctx->AddGlobalValue(std::unique_ptr<Instruction>(new Instruction(
		_ctx, spv::Op::OpVariable, ptrId, _sampleId,
		{{SPV_OPERAND_TYPE_STORAGE_CLASS, {uint32_t(spv::StorageClass::Input)}}})));
	decoMgr->AddDecorationVal(_sampleId, uint32_t(spv::Decoration::BuiltIn), uint32_t(spv::BuiltIn::SampleId));
	decoMgr->AddDecoration(_sampleId, uint32_t(spv::Decoration::Flat));
	_entryPointInst->AddOperand({SPV_OPERAND_TYPE_ID, {_sampleId}});
	return _sampleId;
}

uint32_t Transform::glsl(InstructionBuilder& b, uint32_t type, uint32_t inst, std::vector<uint32_t> args) {
	return b.AddNaryExtendedInstruction(type, _glslStd450, inst, args)->result_id();
}

uint32_t Transform::splat(InstructionBuilder& b, uint32_t vec, uint32_t component) {
	return b.AddVectorShuffle(vec4T(), vec, vec, {component, component, component, component})->result_id();
}

uint32_t Transform::splatBool(InstructionBuilder& b, uint32_t cond) {
	// A vector OpSelect needs a vector condition before SPIR-V 1.4.
	return b.AddCompositeConstruct(bvec4T(), {cond, cond, cond, cond})->result_id();
}

uint32_t Transform::selectByEqual(InstructionBuilder& b, uint32_t sel, uint32_t value, uint32_t ifEqual, uint32_t elseVal) {
	uint32_t eq = b.AddBinaryOp(boolT(), spv::Op::OpIEqual, sel, uconst(value))->result_id();
	return b.AddSelect(vec4T(), splatBool(b, eq), ifEqual, elseVal)->result_id();
}

uint32_t Transform::splatScalar(InstructionBuilder& b, uint32_t scalar) {
	return b.AddCompositeConstruct(vec4T(), {scalar, scalar, scalar, scalar})->result_id();
}

uint32_t Transform::clampVec(InstructionBuilder& b, uint32_t v, uint32_t mode) {
	uint32_t unormLo = vec4const(0, 0, 0, 0), snormLo = vec4const(-1, -1, -1, -1), hi = vec4const(1, 1, 1, 1);
	uint32_t asUnorm = glsl(b, vec4T(), GLSLstd450FClamp, {v, unormLo, hi});
	uint32_t asSnorm = glsl(b, vec4T(), GLSLstd450FClamp, {v, snormLo, hi});
	uint32_t r = selectByEqual(b, mode, kSPIRVBlendClampUnorm, asUnorm, v);
	return selectByEqual(b, mode, kSPIRVBlendClampSnorm, asSnorm, r);
}

void Transform::emitOutput(InstructionBuilder& b, ColorOutput& out, uint32_t blendStateVar) {
	auto* typeMgr = _ctx->get_type_mgr();
	uint32_t valT = vecT(out.componentCount, out.isFloat, out.isSigned);
	uint32_t vec4OfT = vecT(4, out.isFloat, out.isSigned);
	uint32_t att = out.location;

	analysis::Pointer uvec4Ptr(typeMgr->GetRegisteredType(&_v4u32), spv::StorageClass::Uniform);
	uint32_t uvec4PtrId = typeMgr->GetTypeInstruction(&uvec4Ptr);
	analysis::Pointer v4fPtr(typeMgr->GetRegisteredType(&_v4f32), spv::StorageClass::Uniform);
	uint32_t v4fPtrId = typeMgr->GetTypeInstruction(&v4fPtr);

	// control[att] = (colorOp, alphaOp, flags, unused)
	uint32_t ctlPtr = b.AddAccessChain(uvec4PtrId, blendStateVar, {iconst(4), iconst(int32_t(att))})->result_id();
	uint32_t ctl = b.AddLoad(uvec4T(), ctlPtr)->result_id();
	uint32_t colorOp = b.AddCompositeExtract(uintT(), ctl, {0})->result_id();
	uint32_t alphaOp = b.AddCompositeExtract(uintT(), ctl, {1})->result_id();
	uint32_t flags   = b.AddCompositeExtract(uintT(), ctl, {2})->result_id();
	uint32_t enable  = b.AddBinaryOp(uintT(), spv::Op::OpBitwiseAnd, flags, uconst(kSPIRVBlendFlagEnable))->result_id();
	uint32_t maskBits = b.AddBinaryOp(uintT(), spv::Op::OpShiftRightLogical, flags, uconst(kSPIRVBlendFlagWriteMaskShift))->result_id();
	uint32_t clampMode = b.AddBinaryOp(uintT(), spv::Op::OpBitwiseAnd,
									   b.AddBinaryOp(uintT(), spv::Op::OpShiftRightLogical, flags, uconst(kSPIRVBlendFlagClampShift))->result_id(),
									   uconst(3))->result_id();

	uint32_t srcRaw = b.AddLoad(valT, out.var->result_id())->result_id();
	uint32_t img = b.AddLoad(out.fetchImageType, out.fetchVar)->result_id();
	std::vector<uint32_t> zeroPair = { iconst(0), iconst(0) };
	analysis::Vector v2s(&_s32, 2);
	uint32_t coord = _ctx->get_constant_mgr()->GetDefiningInstruction(
		_ctx->get_constant_mgr()->GetConstant(typeMgr->GetRegisteredType(&v2s), zeroPair))->result_id();
	uint32_t dstRaw;
	if (_multisampled) {
		uint32_t sid = b.AddLoad(intT(), sampleId())->result_id();
		dstRaw = b.AddNaryOp(vec4OfT, spv::Op::OpImageRead, {img, coord, uint32_t(spv::ImageOperandsMask::Sample), sid})->result_id();
	} else {
		dstRaw = b.AddBinaryOp(vec4OfT, spv::Op::OpImageRead, img, coord)->result_id();
	}

	uint32_t result4;
	if (out.isFloat) {
		uint32_t src = clampVec(b, srcRaw, clampMode);
		// Alpha to one replaces the source alpha before blending, and so also before the store.
		// The coverage above has already been taken from the alpha as the shader wrote it.
		if (_dynamicMultisample) {
			uint32_t withOneAlpha = b.AddVectorShuffle(vec4T(), src, vec4const(1, 1, 1, 1), {0, 1, 2, 7})->result_id();
			src = b.AddSelect(vec4T(), splatBool(b, _alphaToOne), withOneAlpha, src)->result_id();
		}
		uint32_t dst = clampVec(b, dstRaw, clampMode);
		uint32_t srcA = splat(b, src, 3);
		uint32_t dstA = splat(b, dst, 3);
		uint32_t one = vec4const(1, 1, 1, 1);
		uint32_t sat = glsl(b, vec4T(), GLSLstd450FMin, {srcA, fsub(b, one, dstA)});

		uint32_t satPtr = b.AddAccessChain(v4fPtrId, blendStateVar, {iconst(2), iconst(int32_t(att))})->result_id();
		uint32_t satCoefs = b.AddLoad(vec4T(), satPtr)->result_id();

		// factor = constant + k.x*src + k.y*srcAlpha + k.z*dst + k.w*dstAlpha + sat*saturate
		uint32_t f[kSPIRVBlendSlotCount];
		for (uint32_t slot = 0; slot < kSPIRVBlendSlotCount; slot++) {
			int32_t idx = int32_t(att * kSPIRVBlendSlotCount + slot);
			uint32_t cPtr = b.AddAccessChain(v4fPtrId, blendStateVar, {iconst(0), iconst(idx)})->result_id();
			uint32_t kPtr = b.AddAccessChain(v4fPtrId, blendStateVar, {iconst(1), iconst(idx)})->result_id();
			uint32_t C = b.AddLoad(vec4T(), cPtr)->result_id();
			uint32_t K = b.AddLoad(vec4T(), kPtr)->result_id();
			uint32_t acc = C;
			acc = fadd(b, acc, fmul(b, splat(b, K, 0), src));
			acc = fadd(b, acc, fmul(b, splat(b, K, 1), srcA));
			acc = fadd(b, acc, fmul(b, splat(b, K, 2), dst));
			acc = fadd(b, acc, fmul(b, splat(b, K, 3), dstA));
			acc = fadd(b, acc, fmul(b, splatScalar(b, b.AddCompositeExtract(floatT(), satCoefs, {slot})->result_id()), sat));
			f[slot] = acc;
		}

		uint32_t opPtr = b.AddAccessChain(v4fPtrId, blendStateVar, {iconst(3), iconst(int32_t(att))})->result_id();
		uint32_t opF = b.AddLoad(vec4T(), opPtr)->result_id();
		uint32_t mn = glsl(b, vec4T(), GLSLstd450FMin, {src, dst});
		uint32_t mx = glsl(b, vec4T(), GLSLstd450FMax, {src, dst});

		auto combine = [&](uint32_t op, uint32_t fs, uint32_t fd, uint32_t mulS, uint32_t mulD) {
			uint32_t lin = fadd(b, fmul(b, splat(b, opF, mulS), fmul(b, src, fs)),
								   fmul(b, splat(b, opF, mulD), fmul(b, dst, fd)));
			uint32_t r = selectByEqual(b, op, kSPIRVBlendOpMin, mn, lin);
			return selectByEqual(b, op, kSPIRVBlendOpMax, mx, r);
		};
		uint32_t rgbV = combine(colorOp, f[0], f[1], 0, 1);
		uint32_t aV   = combine(alphaOp, f[2], f[3], 2, 3);
		uint32_t blended = b.AddVectorShuffle(vec4T(), rgbV, aV, {0, 1, 2, 7})->result_id();

		uint32_t isEnabled = b.AddBinaryOp(boolT(), spv::Op::OpINotEqual, enable, uconst(0))->result_id();
		result4 = b.AddSelect(vec4T(), splatBool(b, isEnabled), blended, src)->result_id();
	} else {
		// Integer attachments never blend; only the write mask applies.
		result4 = srcRaw;
	}

	// Channels the write mask excludes keep the destination exactly as it was found.
	uint32_t maskVec = b.AddCompositeConstruct(uvec4T(), {maskBits, maskBits, maskBits, maskBits})->result_id();
	std::vector<uint32_t> bitIds = { uconst(1), uconst(2), uconst(4), uconst(8) };
	uint32_t bits = _ctx->get_constant_mgr()->GetDefiningInstruction(
		_ctx->get_constant_mgr()->GetConstant(typeMgr->GetRegisteredType(&_v4u32), bitIds))->result_id();
	std::vector<uint32_t> zeroIds = { uconst(0), uconst(0), uconst(0), uconst(0) };
	uint32_t zeros = _ctx->get_constant_mgr()->GetDefiningInstruction(
		_ctx->get_constant_mgr()->GetConstant(typeMgr->GetRegisteredType(&_v4u32), zeroIds))->result_id();
	uint32_t masked = b.AddBinaryOp(uvec4T(), spv::Op::OpBitwiseAnd, maskVec, bits)->result_id();
	uint32_t writeCh = b.AddBinaryOp(bvec4T(), spv::Op::OpINotEqual, masked, zeros)->result_id();
	result4 = b.AddSelect(vec4OfT, writeCh, result4, dstRaw)->result_id();

	b.AddStore(out.var->result_id(), result4);
}

// Writes the sample mask the draw asks for, narrowed by the coverage alpha to coverage derives.
// Runs before the colour outputs are rewritten, so the alpha it reads is the one the shader wrote.
void Transform::emitSampleMask(InstructionBuilder& b) {
	auto* typeMgr = _ctx->get_type_mgr();
	analysis::Pointer uvec4Ptr(typeMgr->GetRegisteredType(&_v4u32), spv::StorageClass::Uniform);
	uint32_t uvec4PtrId = typeMgr->GetTypeInstruction(&uvec4Ptr);
	uint32_t msPtr = b.AddAccessChain(uvec4PtrId, _blendStateVar, {iconst(5)})->result_id();
	uint32_t ms = b.AddLoad(uvec4T(), msPtr)->result_id();
	uint32_t apiMask     = b.AddCompositeExtract(uintT(), ms, {0})->result_id();
	uint32_t flags       = b.AddCompositeExtract(uintT(), ms, {1})->result_id();
	uint32_t sampleCount = b.AddCompositeExtract(uintT(), ms, {2})->result_id();

	auto flag = [&](uint32_t bit) {
		return b.AddBinaryOp(boolT(), spv::Op::OpINotEqual,
							 b.AddBinaryOp(uintT(), spv::Op::OpBitwiseAnd, flags, uconst(bit))->result_id(), uconst(0))->result_id();
	};
	_alphaToOne = flag(kSPIRVBlendFlagAlphaToOne);

	// Vulkan derives coverage from the alpha of the output at location zero. The mapping is up
	// to the implementation as long as it is monotonic and maps zero and one to no coverage and
	// full coverage, so the alpha is scaled to a sample count and that many samples are covered.
	uint32_t mask = apiMask;
	if (_coverageVar) {
		uint32_t src = b.AddLoad(vec4T(), _coverageVar)->result_id();
		uint32_t alpha = b.AddCompositeExtract(floatT(), src, {3})->result_id();
		uint32_t cntF = b.AddUnaryOp(floatT(), spv::Op::OpConvertUToF, sampleCount)->result_id();
		uint32_t scaled = b.AddBinaryOp(floatT(), spv::Op::OpFMul, alpha, cntF)->result_id();
		uint32_t n = b.AddUnaryOp(uintT(), spv::Op::OpConvertFToU,
								  glsl(b, floatT(), GLSLstd450FClamp,
									   {glsl(b, floatT(), GLSLstd450RoundEven, {scaled}), fconst(0), cntF}))->result_id();
		uint32_t covered = b.AddBinaryOp(uintT(), spv::Op::OpISub,
										 b.AddBinaryOp(uintT(), spv::Op::OpShiftLeftLogical, uconst(1), n)->result_id(),
										 uconst(1))->result_id();
		uint32_t coverage = b.AddSelect(uintT(), flag(kSPIRVBlendFlagAlphaToCoverage), covered, uconst(~0u))->result_id();
		mask = b.AddBinaryOp(uintT(), spv::Op::OpBitwiseAnd, mask, coverage)->result_id();
	}
	storeSampleMask(b, mask);
}

void Transform::storeSampleMask(InstructionBuilder& b, uint32_t value) {
	auto* typeMgr = _ctx->get_type_mgr();
	auto* decoMgr = _ctx->get_decoration_mgr();

	// A shader that writes gl_SampleMask itself keeps its value, which is combined with this one,
	// because Vulkan intersects the shader's mask with the API's and with the coverage.
	uint32_t var = 0, elemType = 0;
	for (auto& inst : _ctx->module()->types_values()) {
		if (inst.opcode() != spv::Op::OpVariable) { continue; }
		if (inst.GetSingleWordInOperand(0) != uint32_t(spv::StorageClass::Output)) { continue; }
		for (auto* deco : decoMgr->GetDecorationsFor(inst.result_id(), false)) {
			if (spv::Decoration(deco->GetSingleWordInOperand(1)) == spv::Decoration::BuiltIn &&
				spv::BuiltIn(deco->GetSingleWordInOperand(2)) == spv::BuiltIn::SampleMask) { var = inst.result_id(); }
		}
	}
	bool existed = var != 0;
	if (existed) {
		const analysis::Type* ptr = typeMgr->GetType(_ctx->get_def_use_mgr()->GetDef(var)->type_id());
		const analysis::Type* arr = ptr->AsPointer()->pointee_type();
		elemType = typeMgr->GetId(arr->AsArray()->element_type());
	} else {
		elemType = intT();
		analysis::Array arr(typeMgr->GetRegisteredType(&_s32),
							analysis::Array::LengthInfo{uconst(1), {analysis::Array::LengthInfo::kConstant, 1}});
		uint32_t arrId = typeMgr->GetTypeInstruction(&arr);
		var = _ctx->TakeNextId();
		_ctx->AddGlobalValue(std::unique_ptr<Instruction>(new Instruction(
			_ctx, spv::Op::OpVariable, ptrT(arrId, spv::StorageClass::Output), var,
			{{SPV_OPERAND_TYPE_STORAGE_CLASS, {uint32_t(spv::StorageClass::Output)}}})));
		decoMgr->AddDecorationVal(var, uint32_t(spv::Decoration::BuiltIn), uint32_t(spv::BuiltIn::SampleMask));
		// An output the entry point writes belongs to its interface, at every SPIR-V version.
		_entryPointInst->AddOperand({SPV_OPERAND_TYPE_ID, {var}});
	}

	uint32_t ptr = b.AddAccessChain(ptrT(elemType, spv::StorageClass::Output), var, {iconst(0)})->result_id();
	bool isInt = elemType == intT();
	if (existed) {
		uint32_t cur = b.AddLoad(elemType, ptr)->result_id();
		if (isInt) { cur = b.AddUnaryOp(uintT(), spv::Op::OpBitcast, cur)->result_id(); }
		value = b.AddBinaryOp(uintT(), spv::Op::OpBitwiseAnd, value, cur)->result_id();
	}
	if (isInt) { value = b.AddUnaryOp(elemType, spv::Op::OpBitcast, value)->result_id(); }
	b.AddStore(ptr, value);
}

void Transform::addEpilogueBefore(Instruction* ret) {
	InstructionBuilder b(_ctx, ret, IRContext::kAnalysisNone);
	if (_dynamicMultisample) { emitSampleMask(b); }
	for (auto& out : _outputs) { emitOutput(b, out, _blendStateVar); }
}

bool Transform::run() {
	if ( !findEntryPoint() ) { return false; }
	if ( !collectOutputs() ) { return false; }

	// Register the scalar and vector types the arithmetic uses.
	auto* typeMgr = _ctx->get_type_mgr();
	for (analysis::Type* t : { (analysis::Type*)&_f32, (analysis::Type*)&_u32, (analysis::Type*)&_s32, (analysis::Type*)&_bool,
							  (analysis::Type*)&_v4f32, (analysis::Type*)&_v3f32, (analysis::Type*)&_v4u32, (analysis::Type*)&_v2s32, (analysis::Type*)&_v4bool }) {
		typeMgr->GetTypeInstruction(t);
	}
	_glslStd450 = _ctx->get_feature_mgr()->GetExtInstImportId_GLSLstd450();
	if (_glslStd450 == 0) {
		_glslStd450 = _ctx->TakeNextId();
		_ctx->AddExtInstImport(std::unique_ptr<Instruction>(new Instruction(
			_ctx, spv::Op::OpExtInstImport, 0, _glslStd450, {{SPV_OPERAND_TYPE_LITERAL_STRING, utils::MakeVector("GLSL.std.450")}})));
	}

	addBlendStateBlock();
	addFetchVariables();

	// The epilogue runs before every return of the entry point, so a fragment that discards
	// stores nothing, exactly as fixed-function blending would have.
	std::vector<Instruction*> returns;
	for (auto& block : *_entry) {
		for (auto& inst : block) {
			if (inst.opcode() == spv::Op::OpReturn) { returns.push_back(&inst); }
		}
	}
	for (auto* ret : returns) { addEpilogueBefore(ret); }

	// SPIR-V 1.4 requires every global the entry point touches to be in its interface.
	if (_ctx->module()->version() >= 0x00010400) {
		_entryPointInst->AddOperand({SPV_OPERAND_TYPE_ID, {_blendStateVar}});
		for (auto& out : _outputs) { if (out.fetchVar) { _entryPointInst->AddOperand({SPV_OPERAND_TYPE_ID, {out.fetchVar}}); } }
	}
	return true;
}

}	// anonymous namespace

bool mvk::canBlendFragmentOutputsInShader(const std::vector<uint32_t>& spirv, bool* pHasCoverageOutput) {
	if (pHasCoverageOutput) { *pHasCoverageOutput = false; }
#ifdef MVK_EXCLUDE_SPIRV_TOOLS
	return false;
#else
	std::string log;
	std::unique_ptr<IRContext> ctx = BuildModule(SPV_ENV_VULKAN_1_3, nullptr, spirv.data(), spirv.size());
	if ( !ctx ) { return false; }
	Transform xf(ctx.get(), false, ~0u, false, log);
	bool ok = xf.canApply();
	if (pHasCoverageOutput) { *pHasCoverageOutput = xf.hasCoverageOutput(); }
	return ok;
#endif
}

bool mvk::blendFragmentOutputsInShader(std::vector<uint32_t>& spirv, bool multisampled,
									   uint32_t attachmentMask, bool dynamicMultisample, std::string& log) {
#ifdef MVK_EXCLUDE_SPIRV_TOOLS
	log += "MoltenVK was built without SPIRV-Tools.";
	return false;
#else
	auto consumer = [&log](spv_message_level_t, const char*, const spv_position_t&, const char* msg) {
		log += msg; log += "\n";
	};
	std::unique_ptr<IRContext> ctx = BuildModule(SPV_ENV_VULKAN_1_3, consumer, spirv.data(), spirv.size());
	if ( !ctx ) { log += "Could not parse SPIR-V."; return false; }

	Transform xf(ctx.get(), multisampled, attachmentMask, dynamicMultisample, log);
	if ( !xf.run() ) { return false; }

	std::vector<uint32_t> out;
	ctx->module()->ToBinary(&out, true);
	spirv.swap(out);
	return true;
#endif
}
