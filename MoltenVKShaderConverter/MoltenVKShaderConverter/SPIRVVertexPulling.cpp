/*
 * SPIRVVertexPulling.cpp
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

#include "SPIRVVertexPulling.h"

#include "source/opt/build_module.h"
#include "source/opt/ir_context.h"
#include "source/opt/ir_builder.h"
#include "source/opt/type_manager.h"
#include "source/opt/constants.h"
#include "source/opt/decoration_manager.h"
#include "source/util/string_utils.h"
#include "spirv/unified1/GLSL.std.450.h"

#include <unordered_set>

using namespace mvk;
using namespace spvtools;
using namespace spvtools::opt;

namespace {

/** A vertex attribute input the shader reads, and how its type breaks down into locations. */
struct VertexInput {
	Instruction* var = nullptr;		// The OpVariable, Input storage class.
	uint32_t location = 0;
	uint32_t valueType = 0;			// The type the variable holds.
	uint32_t elementType = 0;		// valueType, or its element type for an array.
	uint32_t columnType = 0;		// elementType, or its column type for a matrix.
	uint32_t arrayLength = 0;		// 0 when not an array.
	uint32_t columns = 1;			// 1 unless a matrix.
	uint32_t rows = 1;				// Components in a column: 1..4.
	bool isFloat = false;
	bool isSigned = false;
};

class Transform {
public:
	Transform(IRContext* ctx, std::string& log) : _ctx(ctx), _log(log) {}

	bool run();
	/** Reports whether run() would transform this module, without changing it. */
	bool canApply() { return findEntryPoint() && collectInputs(); }

private:
	bool findEntryPoint();
	bool collectInputs();
	bool analyzeType(VertexInput& in);
	void addCapabilities();
	void addStateBlock();
	uint32_t builtInInput(spv::BuiltIn builtIn);
	void makePrivate(VertexInput& in);
	void emitPrologue();
	uint32_t decodeLocation(InstructionBuilder& b, uint32_t location, const VertexInput& in);

	// Type and constant helpers.
	uint32_t T(analysis::Type* t) { return _ctx->get_type_mgr()->GetId(t); }
	uint32_t vecT(uint32_t n, bool isFloat, bool isSigned);
	uint32_t ptrT(uint32_t pointee, spv::StorageClass sc);
	uint32_t uconst(uint32_t v) { return _ctx->get_constant_mgr()->GetUIntConstId(v); }
	uint32_t iconst(int32_t v)  { return _ctx->get_constant_mgr()->GetSIntConstId(v); }
	uint32_t fconst(float v)    { return _ctx->get_constant_mgr()->GetFloatConstId(v); }
	uint32_t vec4const(analysis::Type* vecType, std::vector<uint32_t> ids);
	uint32_t uvec4const(uint32_t x, uint32_t y, uint32_t z, uint32_t w) { return vec4const(&_v4u32, {uconst(x), uconst(y), uconst(z), uconst(w)}); }

	// Arithmetic helpers.
	uint32_t bin(InstructionBuilder& b, uint32_t type, spv::Op op, uint32_t x, uint32_t y) { return b.AddBinaryOp(type, op, x, y)->result_id(); }
	uint32_t un(InstructionBuilder& b, uint32_t type, spv::Op op, uint32_t x) { return b.AddUnaryOp(type, op, x)->result_id(); }
	uint32_t splat4(InstructionBuilder& b, uint32_t type, uint32_t s) { return b.AddCompositeConstruct(type, {s, s, s, s})->result_id(); }
	uint32_t splatBool(InstructionBuilder& b, uint32_t cond) { return b.AddCompositeConstruct(T(&_v4bool), {cond, cond, cond, cond})->result_id(); }
	uint32_t selectByEqual(InstructionBuilder& b, uint32_t type, uint32_t sel, uint32_t value, uint32_t ifEqual, uint32_t elseVal);
	uint32_t glsl(InstructionBuilder& b, uint32_t type, uint32_t inst, std::vector<uint32_t> args) {
		return b.AddNaryExtendedInstruction(type, _glslStd450, inst, args)->result_id();
	}
	uint32_t toU64(InstructionBuilder& b, uint32_t u32) { return un(b, T(&_u64), spv::Op::OpUConvert, u32); }

	IRContext* _ctx;
	std::string& _log;
	Function* _entry = nullptr;
	Instruction* _entryPointInst = nullptr;
	std::vector<VertexInput> _inputs;
	uint32_t _stateVar = 0;
	uint32_t _glslStd450 = 0;

	// Values loaded once at the top of the entry point.
	uint32_t _vertexIndex = 0, _instanceIndex = 0, _baseInstance = 0, _nullAddress = 0;

	analysis::Float _f32{32};
	analysis::Integer _u32{32, false};
	analysis::Integer _s32{32, true};
	analysis::Integer _u64{64, false};
	analysis::Bool _bool;
	analysis::Vector _v2u32{&_u32, 2};
	analysis::Vector _v2f32{&_f32, 2};
	analysis::Vector _v4u32{&_u32, 4};
	analysis::Vector _v4s32{&_s32, 4};
	analysis::Vector _v4f32{&_f32, 4};
	analysis::Vector _v4bool{&_bool, 4};
};

bool Transform::findEntryPoint() {
	for (auto& ep : _ctx->module()->entry_points()) {
		if (ep.GetSingleWordInOperand(0) == uint32_t(spv::ExecutionModel::Vertex)) {
			_entryPointInst = &ep;
			_entry = _ctx->GetFunction(ep.GetSingleWordInOperand(1));
			return _entry != nullptr;
		}
	}
	_log += "Not a vertex shader.";
	return false;
}

// Breaks an input type down into the locations it occupies. Vulkan gives each column of a
// matrix, and each element of an array, its own consecutive location.
bool Transform::analyzeType(VertexInput& in) {
	auto* typeMgr = _ctx->get_type_mgr();
	const analysis::Type* t = typeMgr->GetType(in.valueType);
	in.elementType = in.valueType;

	if (auto* arr = t->AsArray()) {
		if (arr->length_info().words[0] != analysis::Array::LengthInfo::kConstant) { _log += "Input array length is not constant."; return false; }
		in.arrayLength = arr->length_info().words[1];
		t = arr->element_type();
		in.elementType = typeMgr->GetId(t);
		if (in.arrayLength == 0) { _log += "Input array is empty."; return false; }
	}
	in.columnType = in.elementType;
	if (auto* mat = t->AsMatrix()) {
		in.columns = mat->element_count();
		t = mat->element_type();
		in.columnType = typeMgr->GetId(t);
	}
	const analysis::Type* scalar = t;
	if (auto* vec = t->AsVector()) { scalar = vec->element_type(); in.rows = vec->element_count(); }

	if (auto* f = scalar->AsFloat()) {
		if (f->width() != 32) { _log += "Input is not 32-bit."; return false; }
		in.isFloat = true;
	} else if (auto* i = scalar->AsInteger()) {
		if (i->width() != 32) { _log += "Input is not 32-bit."; return false; }
		in.isSigned = i->IsSigned();
	} else {
		_log += "Input is not a scalar, vector, matrix, or array of those.";
		return false;
	}
	uint32_t locationCount = in.columns * std::max(in.arrayLength, 1u);
	if (in.location + locationCount > kSPIRVVertexPullMaxLocations) { _log += "Input location out of range."; return false; }
	return true;
}

bool Transform::collectInputs() {
	auto* decoMgr = _ctx->get_decoration_mgr();
	auto* typeMgr = _ctx->get_type_mgr();

	for (auto& inst : _ctx->module()->types_values()) {
		if (inst.opcode() != spv::Op::OpVariable) { continue; }
		if (inst.GetSingleWordInOperand(0) != uint32_t(spv::StorageClass::Input)) { continue; }

		bool hasLocation = false, isBuiltIn = false, hasComponent = false;
		uint32_t location = 0;
		for (auto* deco : decoMgr->GetDecorationsFor(inst.result_id(), false)) {
			switch (spv::Decoration(deco->GetSingleWordInOperand(1))) {
				case spv::Decoration::Location:  hasLocation = true; location = deco->GetSingleWordInOperand(2); break;
				case spv::Decoration::Component: hasComponent = true; break;
				case spv::Decoration::BuiltIn:   isBuiltIn = true; break;
				default: break;
			}
		}
		if (isBuiltIn) { continue; }
		// A block of built-ins carries its decorations on the members rather than the variable.
		const analysis::Type* ptrType = typeMgr->GetType(inst.type_id());
		if (ptrType->AsPointer()->pointee_type()->AsStruct()) { continue; }
		if ( !hasLocation ) { _log += "Input has no location."; return false; }
		if (hasComponent) { _log += "Input uses the Component decoration."; return false; }

		VertexInput in;
		in.var = &inst;
		in.location = location;
		in.valueType = typeMgr->GetId(ptrType->AsPointer()->pointee_type());
		if ( !analyzeType(in) ) { return false; }
		_inputs.push_back(in);
	}
	return true;
}

uint32_t Transform::vecT(uint32_t n, bool isFloat, bool isSigned) {
	auto* typeMgr = _ctx->get_type_mgr();
	analysis::Type* scalar = isFloat ? (analysis::Type*)&_f32 : (isSigned ? (analysis::Type*)&_s32 : (analysis::Type*)&_u32);
	if (n == 1) { return typeMgr->GetTypeInstruction(scalar); }
	analysis::Vector v(scalar, n);
	return typeMgr->GetTypeInstruction(&v);
}

uint32_t Transform::ptrT(uint32_t pointee, spv::StorageClass sc) {
	auto* typeMgr = _ctx->get_type_mgr();
	analysis::Pointer ptr(typeMgr->GetType(pointee), sc);
	return typeMgr->GetTypeInstruction(&ptr);
}

uint32_t Transform::vec4const(analysis::Type* vecType, std::vector<uint32_t> ids) {
	auto* constMgr = _ctx->get_constant_mgr();
	const analysis::Type* reg = _ctx->get_type_mgr()->GetRegisteredType(vecType);
	return constMgr->GetDefiningInstruction(constMgr->GetConstant(reg, ids))->result_id();
}

uint32_t Transform::selectByEqual(InstructionBuilder& b, uint32_t type, uint32_t sel, uint32_t value, uint32_t ifEqual, uint32_t elseVal) {
	uint32_t eq = bin(b, T(&_bool), spv::Op::OpIEqual, sel, uconst(value));
	return b.AddSelect(type, splatBool(b, eq), ifEqual, elseVal)->result_id();
}

void Transform::addCapabilities() {
	// The attribute data is reached through 64-bit addresses supplied by the driver, and the
	// instanced element needs the base instance the draw started at.
	_ctx->AddCapability(spv::Capability::Int64);
	_ctx->AddCapability(spv::Capability::PhysicalStorageBufferAddresses);
	_ctx->AddCapability(spv::Capability::DrawParameters);
	_ctx->AddExtension("SPV_KHR_physical_storage_buffer");
	_ctx->module()->GetMemoryModel()->SetInOperand(0, {uint32_t(spv::AddressingModel::PhysicalStorageBuffer64)});
}

void Transform::addStateBlock() {
	auto* typeMgr = _ctx->get_type_mgr();
	auto* decoMgr = _ctx->get_decoration_mgr();

	// struct { uvec4 attributes[2 * kSPIRVVertexPullMaxLocations]; uvec4 header; } in std140.
	const uint32_t rowCount = 2 * kSPIRVVertexPullMaxLocations;
	analysis::Array arr(typeMgr->GetRegisteredType(&_v4u32), analysis::Array::LengthInfo{uconst(rowCount), {analysis::Array::LengthInfo::kConstant, rowCount}});
	uint32_t arrId = typeMgr->GetTypeInstruction(&arr);
	decoMgr->AddDecorationVal(arrId, uint32_t(spv::Decoration::ArrayStride), 16);

	analysis::Struct block({typeMgr->GetType(arrId), typeMgr->GetRegisteredType(&_v4u32)});
	uint32_t blockId = typeMgr->GetTypeInstruction(&block);
	decoMgr->AddDecoration(blockId, uint32_t(spv::Decoration::Block));
	decoMgr->AddMemberDecoration(blockId, 0, uint32_t(spv::Decoration::Offset), 0);
	decoMgr->AddMemberDecoration(blockId, 1, uint32_t(spv::Decoration::Offset), 16 * rowCount);

	uint32_t ptrId = ptrT(blockId, spv::StorageClass::Uniform);
	_stateVar = _ctx->TakeNextId();
	_ctx->AddGlobalValue(std::unique_ptr<Instruction>(new Instruction(
		_ctx, spv::Op::OpVariable, ptrId, _stateVar,
		{{SPV_OPERAND_TYPE_STORAGE_CLASS, {uint32_t(spv::StorageClass::Uniform)}}})));
	decoMgr->AddDecorationVal(_stateVar, uint32_t(spv::Decoration::DescriptorSet), kSPIRVVertexPullDescriptorSet);
	decoMgr->AddDecorationVal(_stateVar, uint32_t(spv::Decoration::Binding), kSPIRVVertexPullBinding);
}

// Returns the Input variable for a built-in, adding one if the shader does not declare it.
uint32_t Transform::builtInInput(spv::BuiltIn builtIn) {
	auto* decoMgr = _ctx->get_decoration_mgr();
	for (auto& inst : _ctx->module()->types_values()) {
		if (inst.opcode() != spv::Op::OpVariable) { continue; }
		for (auto* deco : decoMgr->GetDecorationsFor(inst.result_id(), false)) {
			if (spv::Decoration(deco->GetSingleWordInOperand(1)) == spv::Decoration::BuiltIn &&
				spv::BuiltIn(deco->GetSingleWordInOperand(2)) == builtIn) {
				return inst.result_id();
			}
		}
	}
	uint32_t ptrId = ptrT(T(&_s32), spv::StorageClass::Input);
	uint32_t id = _ctx->TakeNextId();
	_ctx->AddGlobalValue(std::unique_ptr<Instruction>(new Instruction(
		_ctx, spv::Op::OpVariable, ptrId, id,
		{{SPV_OPERAND_TYPE_STORAGE_CLASS, {uint32_t(spv::StorageClass::Input)}}})));
	decoMgr->AddDecorationVal(id, uint32_t(spv::Decoration::BuiltIn), uint32_t(builtIn));
	_entryPointInst->AddOperand({SPV_OPERAND_TYPE_ID, {id}});
	return id;
}

// Turns an attribute input into a private variable the prologue stores into. Every pointer
// derived from it changes storage class with it, and it leaves the entry point interface,
// unless the SPIR-V version lists private variables there too.
void Transform::makePrivate(VertexInput& in) {
	auto* decoMgr = _ctx->get_decoration_mgr();
	auto* typeMgr = _ctx->get_type_mgr();

	in.var->SetInOperand(0, {uint32_t(spv::StorageClass::Private)});
	in.var->SetResultType(ptrT(in.valueType, spv::StorageClass::Private));
	decoMgr->RemoveDecorationsFrom(in.var->result_id());

	std::unordered_set<uint32_t> pointers = { in.var->result_id() };
	bool changed = true;
	while (changed) {
		changed = false;
		for (auto& fn : *_ctx->module()) {
			for (auto& block : fn) {
				for (auto& inst : block) {
					switch (inst.opcode()) {
						case spv::Op::OpAccessChain:
						case spv::Op::OpInBoundsAccessChain:
						case spv::Op::OpCopyObject:
							break;
						default:
							continue;
					}
					if ( !pointers.count(inst.GetSingleWordInOperand(0)) || pointers.count(inst.result_id()) ) { continue; }
					const analysis::Type* ptr = typeMgr->GetType(inst.type_id());
					uint32_t pointee = typeMgr->GetId(ptr->AsPointer()->pointee_type());
					inst.SetResultType(ptrT(pointee, spv::StorageClass::Private));
					pointers.insert(inst.result_id());
					changed = true;
				}
			}
		}
	}

	if (_ctx->module()->version() < 0x00010400) {
		uint32_t opCount = _entryPointInst->NumInOperands();
		for (uint32_t i = 3; i < opCount; i++) {
			if (_entryPointInst->GetSingleWordInOperand(i) == in.var->result_id()) {
				_entryPointInst->RemoveInOperand(i);
				break;
			}
		}
	}
}

// Fetches and converts the attribute at one location, returning a value of the input's column
// type: a scalar, or a vector of in.rows components.
uint32_t Transform::decodeLocation(InstructionBuilder& b, uint32_t location, const VertexInput& in) {
	uint32_t u32T = T(&_u32), f32T = T(&_f32), boolT = T(&_bool), u64T = T(&_u64);
	uint32_t uvec4T = T(&_v4u32), ivec4T = T(&_v4s32), vec4T = T(&_v4f32), bvec4T = T(&_v4bool);
	uint32_t uvec4PtrT = ptrT(uvec4T, spv::StorageClass::Uniform);

	// attributes[2L] = (addressLo, addressHi, stride, divisor); attributes[2L + 1] = (control, byteBound, 0, 0).
	uint32_t row0 = b.AddLoad(uvec4T, b.AddAccessChain(uvec4PtrT, _stateVar, {iconst(0), iconst(int32_t(2 * location))})->result_id())->result_id();
	uint32_t row1 = b.AddLoad(uvec4T, b.AddAccessChain(uvec4PtrT, _stateVar, {iconst(0), iconst(int32_t(2 * location + 1))})->result_id())->result_id();
	uint32_t addressLo = b.AddCompositeExtract(u32T, row0, {0})->result_id();
	uint32_t addressHi = b.AddCompositeExtract(u32T, row0, {1})->result_id();
	uint32_t stride    = b.AddCompositeExtract(u32T, row0, {2})->result_id();
	uint32_t divisor   = b.AddCompositeExtract(u32T, row0, {3})->result_id();
	uint32_t control   = b.AddCompositeExtract(u32T, row1, {0})->result_id();
	uint32_t byteBound = b.AddCompositeExtract(u32T, row1, {1})->result_id();

	uint32_t compCount = bin(b, u32T, spv::Op::OpBitwiseAnd, control, uconst(7));
	uint32_t sizeLog2  = bin(b, u32T, spv::Op::OpBitwiseAnd, bin(b, u32T, spv::Op::OpShiftRightLogical, control, uconst(kSPIRVVertexPullComponentSizeShift)), uconst(3));
	uint32_t kind      = bin(b, u32T, spv::Op::OpBitwiseAnd, bin(b, u32T, spv::Op::OpShiftRightLogical, control, uconst(kSPIRVVertexPullKindShift)), uconst(15));
	auto flag = [&](uint32_t bit) {
		return bin(b, boolT, spv::Op::OpINotEqual, bin(b, u32T, spv::Op::OpBitwiseAnd, control, uconst(bit)), uconst(0));
	};
	uint32_t isPacked = flag(kSPIRVVertexPullFlagPacked);
	uint32_t isSwapped = flag(kSPIRVVertexPullFlagSwapRedBlue);
	uint32_t isInstanced = flag(kSPIRVVertexPullFlagInstanced);
	uint32_t bits = bin(b, u32T, spv::Op::OpShiftLeftLogical, uconst(8), sizeLog2);
	uint32_t attrBytes = b.AddSelect(u32T, isPacked, uconst(4), bin(b, u32T, spv::Op::OpShiftLeftLogical, compCount, sizeLog2))->result_id();

	// The element: the vertex index, or for an instanced attribute the base instance plus the
	// instance divided by the divisor, with a divisor of zero meaning the base instance alone.
	uint32_t instance = bin(b, u32T, spv::Op::OpISub, _instanceIndex, _baseInstance);
	uint32_t safeDivisor = glsl(b, u32T, GLSLstd450UMax, {divisor, uconst(1)});
	uint32_t quotient = bin(b, u32T, spv::Op::OpUDiv, instance, safeDivisor);
	uint32_t divisorIsZero = bin(b, boolT, spv::Op::OpIEqual, divisor, uconst(0));
	quotient = b.AddSelect(u32T, divisorIsZero, uconst(0), quotient)->result_id();
	uint32_t instanceElement = bin(b, u32T, spv::Op::OpIAdd, quotient, _baseInstance);
	uint32_t element = b.AddSelect(u32T, isInstanced, instanceElement, _vertexIndex)->result_id();

	// An element whose bytes end past the bound reads from the zeroed null buffer instead.
	uint32_t offset64 = bin(b, u64T, spv::Op::OpIMul, toU64(b, element), toU64(b, stride));
	uint32_t end64 = bin(b, u64T, spv::Op::OpIAdd, offset64, toU64(b, attrBytes));
	uint32_t outOfBounds = bin(b, boolT, spv::Op::OpUGreaterThan, end64, toU64(b, byteBound));
	uint32_t base64 = un(b, u64T, spv::Op::OpBitcast, b.AddCompositeConstruct(T(&_v2u32), {addressLo, addressHi})->result_id());
	uint32_t address = b.AddSelect(u64T, outOfBounds, _nullAddress, bin(b, u64T, spv::Op::OpIAdd, base64, offset64))->result_id();

	// Whole words are loaded from the aligned address below the attribute, and shifted into
	// place, so that no load depends on the component width. A word past the ones needed is
	// loaded from the first word again, keeping every load inside the attribute's bytes.
	uint32_t misalign = bin(b, u32T, spv::Op::OpBitwiseAnd, un(b, u32T, spv::Op::OpUConvert, address), uconst(3));
	uint32_t aligned = bin(b, u64T, spv::Op::OpISub, address, toU64(b, misalign));
	uint32_t shift = bin(b, u32T, spv::Op::OpIMul, misalign, uconst(8));
	uint32_t needed = bin(b, u32T, spv::Op::OpShiftRightLogical, bin(b, u32T, spv::Op::OpIAdd, bin(b, u32T, spv::Op::OpIAdd, attrBytes, misalign), uconst(3)), uconst(2));
	uint32_t wordPtrT = ptrT(u32T, spv::StorageClass::PhysicalStorageBuffer);
	uint32_t loadCount = in.rows + 1;
	std::vector<uint32_t> loaded(loadCount);
	for (uint32_t i = 0; i < loadCount; i++) {
		uint32_t isNeeded = bin(b, boolT, spv::Op::OpULessThan, uconst(i), needed);
		uint32_t wordAddress = b.AddSelect(u64T, isNeeded, bin(b, u64T, spv::Op::OpIAdd, aligned, toU64(b, uconst(4 * i))), aligned)->result_id();
		uint32_t ptr = b.AddNaryOp(wordPtrT, spv::Op::OpConvertUToPtr, {wordAddress})->result_id();
		loaded[i] = b.AddLoad(u32T, ptr, 4)->result_id();
	}
	uint32_t noShift = bin(b, boolT, spv::Op::OpIEqual, shift, uconst(0));
	uint32_t backShift = bin(b, u32T, spv::Op::OpISub, uconst(32), shift);
	std::vector<uint32_t> words(in.rows);
	for (uint32_t i = 0; i < in.rows; i++) {
		uint32_t shifted = bin(b, u32T, spv::Op::OpBitwiseOr,
							   bin(b, u32T, spv::Op::OpShiftRightLogical, loaded[i], shift),
							   bin(b, u32T, spv::Op::OpShiftLeftLogical, loaded[i + 1], backShift));
		words[i] = b.AddSelect(u32T, noShift, loaded[i], shifted)->result_id();
	}
	uint32_t wordVec = in.rows > 1 ? b.AddCompositeConstruct(vecT(in.rows, false, false), words)->result_id() : 0;

	// Each component's bit offset and width, then the raw components, all four at once.
	uint32_t bitsVec = splat4(b, uvec4T, bits);
	uint32_t offsets = b.AddSelect(uvec4T, splatBool(b, isPacked), uvec4const(0, 10, 20, 30),
								   bin(b, uvec4T, spv::Op::OpIMul, bitsVec, uvec4const(0, 1, 2, 3)))->result_id();
	uint32_t widths = b.AddSelect(uvec4T, splatBool(b, isPacked), uvec4const(10, 10, 10, 2), bitsVec)->result_id();
	uint32_t wordIndices = bin(b, uvec4T, spv::Op::OpShiftRightLogical, offsets, uvec4const(5, 5, 5, 5));
	uint32_t shifts = bin(b, uvec4T, spv::Op::OpBitwiseAnd, offsets, uvec4const(31, 31, 31, 31));
	std::vector<uint32_t> rawWords(4);
	for (uint32_t i = 0; i < 4; i++) {
		if (wordVec) {
			uint32_t idx = b.AddCompositeExtract(u32T, wordIndices, {i})->result_id();
			rawWords[i] = b.AddNaryOp(u32T, spv::Op::OpVectorExtractDynamic, {wordVec, idx})->result_id();
		} else {
			rawWords[i] = words[0];
		}
	}
	uint32_t raw = b.AddCompositeConstruct(uvec4T, rawWords)->result_id();
	uint32_t masks = bin(b, uvec4T, spv::Op::OpShiftRightLogical, uvec4const(~0u, ~0u, ~0u, ~0u),
						 bin(b, uvec4T, spv::Op::OpISub, uvec4const(32, 32, 32, 32), widths));
	uint32_t unsignedComps = bin(b, uvec4T, spv::Op::OpBitwiseAnd, bin(b, uvec4T, spv::Op::OpShiftRightLogical, raw, shifts), masks);
	uint32_t signExtend = bin(b, uvec4T, spv::Op::OpISub, uvec4const(32, 32, 32, 32), widths);
	uint32_t signedComps = bin(b, ivec4T, spv::Op::OpShiftRightArithmetic,
							   un(b, ivec4T, spv::Op::OpBitcast, bin(b, uvec4T, spv::Op::OpShiftLeftLogical, unsignedComps, signExtend)),
							   signExtend);

	uint32_t value, valueT, defaults;
	if (in.isFloat) {
		uint32_t asUnsigned = un(b, vec4T, spv::Op::OpConvertUToF, unsignedComps);
		uint32_t asSigned = un(b, vec4T, spv::Op::OpConvertSToF, signedComps);
		uint32_t maxUnsigned = un(b, vec4T, spv::Op::OpConvertUToF, masks);
		uint32_t maxSigned = un(b, vec4T, spv::Op::OpConvertUToF, bin(b, uvec4T, spv::Op::OpShiftRightLogical, masks, uvec4const(1, 1, 1, 1)));
		uint32_t unorm = bin(b, vec4T, spv::Op::OpFDiv, asUnsigned, maxUnsigned);
		uint32_t snorm = glsl(b, vec4T, GLSLstd450FMax, {bin(b, vec4T, spv::Op::OpFDiv, asSigned, maxSigned), vec4const(&_v4f32, {fconst(-1), fconst(-1), fconst(-1), fconst(-1)})});
		std::vector<uint32_t> halves(4);
		for (uint32_t i = 0; i < 4; i++) {
			uint32_t pair = glsl(b, T(&_v2f32), GLSLstd450UnpackHalf2x16, {b.AddCompositeExtract(u32T, unsignedComps, {i})->result_id()});
			halves[i] = b.AddCompositeExtract(f32T, pair, {0})->result_id();
		}
		uint32_t half = b.AddCompositeConstruct(vec4T, halves)->result_id();
		uint32_t single = un(b, vec4T, spv::Op::OpBitcast, unsignedComps);
		uint32_t isHalf = bin(b, boolT, spv::Op::OpIEqual, bits, uconst(16));
		uint32_t sfloat = b.AddSelect(vec4T, splatBool(b, isHalf), half, single)->result_id();

		value = sfloat;
		value = selectByEqual(b, vec4T, kind, kSPIRVVertexPullUnorm, unorm, value);
		value = selectByEqual(b, vec4T, kind, kSPIRVVertexPullSnorm, snorm, value);
		value = selectByEqual(b, vec4T, kind, kSPIRVVertexPullUInt, asUnsigned, value);
		value = selectByEqual(b, vec4T, kind, kSPIRVVertexPullSInt, asSigned, value);
		value = selectByEqual(b, vec4T, kind, kSPIRVVertexPullUScaled, asUnsigned, value);
		value = selectByEqual(b, vec4T, kind, kSPIRVVertexPullSScaled, asSigned, value);
		valueT = vec4T;
		defaults = vec4const(&_v4f32, {fconst(0), fconst(0), fconst(0), fconst(1)});
	} else if (in.isSigned) {
		value = signedComps;
		valueT = ivec4T;
		defaults = vec4const(&_v4s32, {iconst(0), iconst(0), iconst(0), iconst(1)});
	} else {
		value = unsignedComps;
		valueT = uvec4T;
		defaults = uvec4const(0, 0, 0, 1);
	}

	// Components the format does not supply read as (0, 0, 0, 1), as they do from a vertex
	// descriptor, and a format stored blue-first is put back in order.
	uint32_t present = bin(b, bvec4T, spv::Op::OpULessThan, uvec4const(0, 1, 2, 3), splat4(b, uvec4T, compCount));
	value = b.AddSelect(valueT, present, value, defaults)->result_id();
	uint32_t swapped = b.AddVectorShuffle(valueT, value, value, {2, 1, 0, 3})->result_id();
	value = b.AddSelect(valueT, splatBool(b, isSwapped), swapped, value)->result_id();

	if (in.rows == 4) { return value; }
	if (in.rows == 1) { return b.AddCompositeExtract(vecT(1, in.isFloat, in.isSigned), value, {0})->result_id(); }
	std::vector<uint32_t> comps;
	for (uint32_t i = 0; i < in.rows; i++) { comps.push_back(i); }
	return b.AddVectorShuffle(in.columnType, value, value, comps)->result_id();
}

void Transform::emitPrologue() {
	// The prologue goes at the top of the entry point, after its local variable declarations,
	// so that every function reading an attribute sees the decoded value.
	BasicBlock& first = *_entry->begin();
	Instruction* insertBefore = nullptr;
	for (auto& inst : first) {
		if (inst.opcode() != spv::Op::OpVariable) { insertBefore = &inst; break; }
	}
	InstructionBuilder b(_ctx, insertBefore, IRContext::kAnalysisNone);

	uint32_t u32T = T(&_u32), s32T = T(&_s32), u64T = T(&_u64);
	_vertexIndex = un(b, u32T, spv::Op::OpBitcast, b.AddLoad(s32T, builtInInput(spv::BuiltIn::VertexIndex))->result_id());
	_instanceIndex = un(b, u32T, spv::Op::OpBitcast, b.AddLoad(s32T, builtInInput(spv::BuiltIn::InstanceIndex))->result_id());
	_baseInstance = un(b, u32T, spv::Op::OpBitcast, b.AddLoad(s32T, builtInInput(spv::BuiltIn::BaseInstance))->result_id());
	uint32_t uvec4T = T(&_v4u32);
	uint32_t header = b.AddLoad(uvec4T, b.AddAccessChain(ptrT(uvec4T, spv::StorageClass::Uniform), _stateVar, {iconst(1)})->result_id())->result_id();
	_nullAddress = un(b, u64T, spv::Op::OpBitcast, b.AddVectorShuffle(T(&_v2u32), header, header, {0, 1})->result_id());

	for (auto& in : _inputs) {
		uint32_t elementCount = std::max(in.arrayLength, 1u);
		std::vector<uint32_t> elements;
		uint32_t location = in.location;
		for (uint32_t e = 0; e < elementCount; e++) {
			std::vector<uint32_t> columns;
			for (uint32_t c = 0; c < in.columns; c++) { columns.push_back(decodeLocation(b, location++, in)); }
			elements.push_back(in.columns > 1 ? b.AddCompositeConstruct(in.elementType, columns)->result_id() : columns[0]);
		}
		uint32_t value = in.arrayLength ? b.AddCompositeConstruct(in.valueType, elements)->result_id() : elements[0];
		b.AddStore(in.var->result_id(), value);
	}
}

bool Transform::run() {
	if ( !findEntryPoint() ) { return false; }
	if ( !collectInputs() ) { return false; }
	if (_inputs.empty()) { return true; }		// No layout to pull; the shader is already independent of it.

	auto* typeMgr = _ctx->get_type_mgr();
	for (analysis::Type* t : { (analysis::Type*)&_f32, (analysis::Type*)&_u32, (analysis::Type*)&_s32, (analysis::Type*)&_u64, (analysis::Type*)&_bool,
							  (analysis::Type*)&_v2u32, (analysis::Type*)&_v2f32, (analysis::Type*)&_v4u32, (analysis::Type*)&_v4s32, (analysis::Type*)&_v4f32, (analysis::Type*)&_v4bool }) {
		typeMgr->GetTypeInstruction(t);
	}
	_glslStd450 = _ctx->get_feature_mgr()->GetExtInstImportId_GLSLstd450();
	if (_glslStd450 == 0) {
		_glslStd450 = _ctx->TakeNextId();
		_ctx->AddExtInstImport(std::unique_ptr<Instruction>(new Instruction(
			_ctx, spv::Op::OpExtInstImport, 0, _glslStd450, {{SPV_OPERAND_TYPE_LITERAL_STRING, utils::MakeVector("GLSL.std.450")}})));
	}

	addCapabilities();
	addStateBlock();
	for (auto& in : _inputs) { makePrivate(in); }
	emitPrologue();

	// SPIR-V 1.4 requires every global the entry point touches to be in its interface.
	if (_ctx->module()->version() >= 0x00010400) {
		_entryPointInst->AddOperand({SPV_OPERAND_TYPE_ID, {_stateVar}});
	}
	return true;
}

}	// anonymous namespace

bool mvk::canPullVerticesInShader(const std::vector<uint32_t>& spirv) {
#ifdef MVK_EXCLUDE_SPIRV_TOOLS
	return false;
#else
	std::string log;
	std::unique_ptr<IRContext> ctx = BuildModule(SPV_ENV_VULKAN_1_3, nullptr, spirv.data(), spirv.size());
	if ( !ctx ) { return false; }
	Transform xf(ctx.get(), log);
	return xf.canApply();
#endif
}

bool mvk::pullVerticesInShader(std::vector<uint32_t>& spirv, std::string& log) {
#ifdef MVK_EXCLUDE_SPIRV_TOOLS
	log += "MoltenVK was built without SPIRV-Tools.";
	return false;
#else
	auto consumer = [&log](spv_message_level_t, const char*, const spv_position_t&, const char* msg) {
		log += msg; log += "\n";
	};
	std::unique_ptr<IRContext> ctx = BuildModule(SPV_ENV_VULKAN_1_3, consumer, spirv.data(), spirv.size());
	if ( !ctx ) { log += "Could not parse SPIR-V."; return false; }

	Transform xf(ctx.get(), log);
	if ( !xf.run() ) { return false; }

	std::vector<uint32_t> out;
	ctx->module()->ToBinary(&out, true);
	spirv.swap(out);
	return true;
#endif
}
