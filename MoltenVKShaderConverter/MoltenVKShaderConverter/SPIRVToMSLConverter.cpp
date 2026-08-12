/*
 * SPIRVToMSLConverter.cpp
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

#include "SPIRVToMSLConverter.h"
#include "MVKCommonEnvironment.h"
#include "MVKStrings.h"
#include "FileSupport.h"
#include "SPIRVSupport.h"
#include <fstream>

using namespace mvk;
using namespace std;
using namespace spv;
using namespace SPIRV_CROSS_NAMESPACE;

static const string& getAccelerationStructureAddressMSL() {
	static const string source = R"MVKRT(
#include <metal_stdlib>
#include <metal_raytracing>
using namespace metal;
using namespace metal::raytracing;

template<typename T>
static inline device const ulong* spvAccelerationStructureFromAddress(ulong key, T table) {
	if (!key) return nullptr;
	if (table && table[0].y) {
		ulong mask = table[0].x, hash = key;
		hash = (hash ^ (hash >> 30)) * 0xbf58476d1ce4e5b9ul;
		hash = (hash ^ (hash >> 27)) * 0x94d049bb133111ebul;
		hash ^= hash >> 31;
		for (ulong slot = hash & mask, remaining = min(table[0].y, mask) + 1;
		     remaining; --remaining, slot = (slot + 1) & mask) {
			ulong2 entry = table[slot + 1];
			if (entry.x == key) return reinterpret_cast<device const ulong*>(entry.y);
			if (!entry.x) break;
		}
	}
	return reinterpret_cast<device const ulong*>(key);
}
)MVKRT";
	return source;
}

MVK_PUBLIC_SYMBOL const string& mvk::getRayTracingRuntimePreludeMSL() {
	static const string source = getAccelerationStructureAddressMSL() + R"MVKRT(
#ifndef SPV_RAY_IFB
#define SPV_RAY_IFB 0
#endif
#ifndef SPV_RAY_PROCEDURAL_IFB
#define SPV_RAY_PROCEDURAL_IFB 0
#endif
#ifndef SPV_RAY_PROCEDURAL_IFB_WRAPPER
#define SPV_RAY_PROCEDURAL_IFB_WRAPPER 0
#endif
#if SPV_RAY_CONTEXT_KIND == 0
#define SPV_RAY_CONTEXT_ARGS(Payload) thread spvRayTracingState& spvRayState
#define SPV_RAY_CONTEXT_NAMES spvRayState
#define SPV_RAY_SHADER_RECORD_ARGS(Miss) spvRayState
#elif SPV_RAY_CONTEXT_KIND == 1
#define SPV_RAY_CONTEXT_ARGS(Payload) thread spvRayInvocation& spvRay, thread spvRayTracingState& spvRayState
#define SPV_RAY_CONTEXT_NAMES spvRay, spvRayState
#define SPV_RAY_INCOMING_DATA spvRay.data
#define SPV_RAY_SHADER_RECORD_ARGS(Miss) spvRay, spvRayState, Miss
#elif SPV_RAY_CONTEXT_KIND == 2
#define SPV_RAY_CONTEXT_ARGS(Payload) thread spvCallableInvocation& spvRay, thread spvRayTracingState& spvRayState
#define SPV_RAY_CONTEXT_NAMES spvRay, spvRayState
#define SPV_RAY_INCOMING_DATA spvRay.data
#define SPV_RAY_SHADER_RECORD_ARGS(Miss) spvRay
#elif SPV_RAY_CONTEXT_KIND == 3
#define SPV_RAY_CONTEXT_ARGS(Payload) ray_data spvIFBPayload<Payload>& spvRayPayload, thread spvRayTracingContext& spvRayContext, thread uint& spvRayAction, thread spvRayTracingIFBState& spvRayState
#define SPV_RAY_CONTEXT_NAMES spvRayPayload, spvRayContext, spvRayAction, spvRayState
#define SPV_RAY_INCOMING_DATA &spvRayPayload.data
#define SPV_RAY_SHADER_RECORD_ARGS(Miss) spvRayContext, spvRayState
#else
#define SPV_RAY_CONTEXT_ARGS(Payload) ray_data spvIFBPayload<Payload>& spvRayPayload, thread spvRayTracingContext& spvRayContext, thread uint& spvRayAction, thread spvRayTracingState& spvRayState
#define SPV_RAY_CONTEXT_NAMES spvRayPayload, spvRayContext, spvRayAction, spvRayState
#define SPV_RAY_INCOMING_DATA &spvRayPayload.data
#define SPV_RAY_SHADER_RECORD_ARGS(Miss) spvRayContext, spvRayState
#endif
#define SPV_RAY_IFB_ENTRY_POINT(Name, Payload) using Name##_ifb_payload = Payload; SPV_RAY_IFB_ENTRY(Name, Name##_ifb_payload)

struct spvRayHitAttribute {
	ulong4 data;
};

struct spvRayTracingContext {
	uint3 LaunchIdKHR;
	uint3 LaunchSizeKHR;
	float3 WorldRayOriginKHR;
	float3 WorldRayDirectionKHR;
	float3 ObjectRayOriginKHR;
	float3 ObjectRayDirectionKHR;
	float RayTminKHR;
	float RayTmaxKHR;
	uint InstanceCustomIndexKHR;
	uint InstanceId;
	float4x3 ObjectToWorldKHR;
	float4x3 WorldToObjectKHR;
	spvRayHitAttribute hitAttribute;
	uint HitKindKHR;
	uint IncomingRayFlagsKHR;
	uint RayGeometryIndexKHR;
	uint PrimitiveId;
	uint CullMaskKHR;
	float traceRayTmax;
	float reportedDistance;
	spvRayHitAttribute reportedHitAttribute;
	uint reportedHitKind;
	bool reportAccepted;
	bool candidateNonOpaque;
	uint shaderRecordIndex;
};

struct spvRayTracingDispatch {
	ulong missAddress;
	ulong missStride;
	ulong hitAddress;
	ulong hitStride;
	ulong hitSize;
	ulong callableAddress;
	ulong callableStride;
	ulong raygenAddress;
	ulong swizzleAddress;
	ulong bufferSizeAddress;
	ulong dynamicOffsetsAddress;
	ulong accelerationStructureAddressTableAddress;
	ulong pushConstantsAddress;
	ulong indirectLaunchSizeAddress;
	device const ulong* descriptorSetAddresses;
	uint pipelineFlags;
	uint usesIFB;
};

struct spvRayTracingState;
struct spvRayInvocation {
	thread void* data;
	spvRayTracingContext context;
	uint action;
};
struct spvCallableInvocation {
	thread void* data;
	ulong shaderRecordAddress;
};
using spvRayFunctionTable = visible_function_table<void(thread spvRayInvocation&, thread spvRayTracingState&)>;
using spvCallableFunctionTable = visible_function_table<void(thread spvCallableInvocation&, thread spvRayTracingState&)>;

struct spvRayTracingState {
	spvRayFunctionTable functions;
	spvRayFunctionTable intersections;
	spvCallableFunctionTable callables;
	constant spvRayTracingDispatch* dispatch;
	ulong dispatchAddress;
	uint3 LaunchIdKHR;
	uint3 LaunchSizeKHR;
	uint SubgroupSize;
	uint SubgroupLocalInvocationId;
};

#if SPV_RAY_PROCEDURAL_IFB_WRAPPER
constant spvRayFunctionTable spvIFBFunctions [[buffer(SPV_RAY_FUNCTION_TABLE_BUFFER_INDEX)]];
constant spvRayFunctionTable spvIFBIntersections [[buffer(SPV_RAY_INTERSECTION_TABLE_BUFFER_INDEX)]];
constant spvCallableFunctionTable spvIFBCallables [[buffer(SPV_RAY_CALLABLE_TABLE_BUFFER_INDEX)]];
#endif

#if SPV_RAY_IFB
struct spvIFBDecision {
	bool accept [[accept_intersection]];
	bool continueSearch [[continue_search]];
};

struct spvIFBIntersectionDecision {
	bool accept [[accept_intersection]];
	bool continueSearch [[continue_search]];
	float distance [[distance]];
};
#endif

using spvRayGenerationFunctionTable = visible_function_table<void(uint3, uint3, thread spvRayTracingState&)>;
)MVKRT";
	return source;
}

static const string& getRayTracingRuntimeMSL() {
	static const string source = getRayTracingRuntimePreludeMSL() + R"MVKRT(
#if SPV_RAY_IFB
template<typename T>
struct spvIFBPayload {
	T data;
	uint3 launchId;
	uint3 launchSize;
	uint subgroupSize;
	uint subgroupInvocationId;
	uint rayFlags;
	uint cullMask;
#if SPV_RAY_PROCEDURAL_IFB
	spvRayHitAttribute hitAttribute;
	float reportedDistance;
	uint hitKind;
#endif
};
struct spvRayTracingIFBState {
	const device spvRayTracingDispatch* dispatch;
	uint3 launchId;
	uint3 launchSize;
	uint SubgroupSize;
	uint SubgroupLocalInvocationId;
};

static inline __attribute__((always_inline)) spvRayTracingContext spvMakeIFBContext(
	uint3 launchId, uint3 launchSize, float3 objectOrigin, float3 objectDirection,
	float rayTmin, float rayTmax, float3 worldOrigin, float3 worldDirection,
	float2 barycentrics, bool frontFacing, uint customIndex, uint instanceId,
	float4x3 objectToWorld, float4x3 worldToObject, uint geometryId, uint primitiveId,
	uint functionId, uint rayFlags, uint cullMask) {
	spvRayTracingContext context;
	context.LaunchIdKHR = launchId; context.LaunchSizeKHR = launchSize;
	context.ObjectRayOriginKHR = objectOrigin; context.ObjectRayDirectionKHR = objectDirection;
	context.RayTminKHR = rayTmin; context.RayTmaxKHR = rayTmax;
	context.WorldRayOriginKHR = worldOrigin; context.WorldRayDirectionKHR = worldDirection;
	*reinterpret_cast<thread float2*>(&context.hitAttribute) = barycentrics;
	context.HitKindKHR = frontFacing ? 0xfeu : 0xffu;
	context.InstanceCustomIndexKHR = customIndex; context.InstanceId = instanceId;
	context.ObjectToWorldKHR = objectToWorld; context.WorldToObjectKHR = worldToObject;
	context.RayGeometryIndexKHR = geometryId; context.PrimitiveId = primitiveId;
	context.shaderRecordIndex = functionId;
	context.IncomingRayFlagsKHR = rayFlags; context.CullMaskKHR = cullMask;
	return context;
}
#endif

static inline __attribute__((always_inline)) intersection_params spvTraceIntersectionParams(uint flags) {
	intersection_params params;
	if (flags & 1u) params.force_opacity(forced_opacity::opaque);
	if (flags & 2u) params.force_opacity(forced_opacity::non_opaque);
	if (flags & 4u) params.accept_any_intersection(true);
	if (flags & 16u) params.set_triangle_cull_mode(triangle_cull_mode::back);
	if (flags & 32u) params.set_triangle_cull_mode(triangle_cull_mode::front);
	if (flags & 64u) params.set_opacity_cull_mode(opacity_cull_mode::opaque);
	if (flags & 128u) params.set_opacity_cull_mode(opacity_cull_mode::non_opaque);
	if (flags & 256u) params.set_geometry_cull_mode(geometry_cull_mode::triangle);
	if (flags & 512u) params.set_geometry_cull_mode(geometry_cull_mode::bounding_box);
	return params;
}

static inline __attribute__((always_inline)) ulong spvShaderRecordAddress(ulong base, ulong stride, uint index) {
	return base + ulong(index) * stride + 32;
}

template<typename T>
static inline __attribute__((always_inline)) thread T& spvRayData(thread void* address) {
	return *reinterpret_cast<thread T*>(address);
}

#if SPV_RAY_IFB
template<typename T, typename U>
static inline __attribute__((always_inline)) ray_data T& spvRayData(ray_data U* address) {
	return *reinterpret_cast<ray_data T*>(address);
}
#endif

template<typename T>
static inline __attribute__((always_inline)) const device T& spvRayData(ulong address) {
	return *reinterpret_cast<const device T*>(address);
}

template<typename T>
static inline __attribute__((always_inline)) const device T& spvPushConstant(thread spvRayTracingState& state) {
	return spvRayData<T>(state.dispatch->pushConstantsAddress);
}

template<uint I>
static inline __attribute__((always_inline)) const device uint* spvRuntimeBuffer(thread spvRayTracingState& state) {
	ulong address = I == 0 ? state.dispatch->swizzleAddress : I == 1 ? state.dispatch->bufferSizeAddress :
		I == 2 ? state.dispatch->dynamicOffsetsAddress : state.dispatch->accelerationStructureAddressTableAddress;
	return reinterpret_cast<const device uint*>(address);
}

template<typename T>
static inline __attribute__((always_inline)) const device T& spvShaderRecord(thread spvRayTracingState& state) {
	return spvRayData<T>(spvShaderRecordAddress(state.dispatch->raygenAddress, 0, 0));
}

template<typename T>
static inline __attribute__((always_inline)) const device T& spvShaderRecord(thread spvCallableInvocation& ray) {
	return spvRayData<T>(ray.shaderRecordAddress);
}

template<typename T>
static inline __attribute__((always_inline)) const device T& spvShaderRecord(
	thread spvRayInvocation& ray, thread spvRayTracingState& state, bool miss) {
	return spvRayData<T>(spvShaderRecordAddress(miss ? state.dispatch->missAddress : state.dispatch->hitAddress,
		miss ? state.dispatch->missStride : state.dispatch->hitStride, ray.context.shaderRecordIndex));
}

template<typename T, typename S>
static inline __attribute__((always_inline)) const device T& spvShaderRecord(
	thread spvRayTracingContext& context, thread S& state) {
	return spvRayData<T>(spvShaderRecordAddress(state.dispatch->hitAddress, state.dispatch->hitStride,
		context.shaderRecordIndex));
}

template<typename T>
static inline __attribute__((always_inline)) thread T& spvHitAttribute(thread spvRayTracingContext& context) {
	return *reinterpret_cast<thread T*>(&context.hitAttribute);
}

template<typename T>
static inline __attribute__((always_inline)) thread const T& spvReadHitAttribute(thread spvRayTracingContext& context) {
	return *reinterpret_cast<thread const T*>(&context.hitAttribute);
}

static inline __attribute__((always_inline)) uint spvIntersectionFunctionHandle(ulong base, ulong stride, uint index) {
	return reinterpret_cast<device const uint*>(base + ulong(index) * stride)[4];
}

static inline __attribute__((always_inline)) void spvCallRayFunction(
	uint handle, thread spvRayInvocation& ray, thread spvRayTracingState& state) {
	state.functions[handle](ray, state);
}

static inline __attribute__((always_inline)) void spvCallIntersectionFunction(
	uint handle, thread spvRayInvocation& ray, thread spvRayTracingState& state) {
	state.intersections[handle](ray, state);
}

#if SPV_RAY_PROCEDURAL_IFB_WRAPPER
template<typename T>
static inline __attribute__((always_inline)) spvIFBIntersectionDecision spvRunProceduralIFB(
	ray_data spvIFBPayload<T>& payload, float3 objectOrigin, float3 objectDirection,
	float rayTmin, float rayTmax, float3 worldOrigin, float3 worldDirection, bool opaque,
	uint customIndex, uint instanceId, float4x3 objectToWorld, float4x3 worldToObject,
	uint geometryId, uint primitiveId, uint functionId, const device spvRayTracingDispatch* dispatch) {
	spvRayTracingContext context = spvMakeIFBContext(payload.launchId, payload.launchSize,
		objectOrigin, objectDirection, rayTmin, rayTmax, worldOrigin, worldDirection, float2(0.0f), true,
		customIndex, instanceId, objectToWorld, worldToObject, geometryId, primitiveId,
		functionId, payload.rayFlags, payload.cullMask);
	context.traceRayTmax = rayTmax;
	context.reportedDistance = min(rayTmax, payload.reportedDistance);
	context.reportAccepted = false;
	context.candidateNonOpaque = !opaque;
	spvRayTracingState state = { spvIFBFunctions, spvIFBIntersections, spvIFBCallables,
		reinterpret_cast<const constant spvRayTracingDispatch*>(reinterpret_cast<ulong>(dispatch)),
		reinterpret_cast<ulong>(dispatch), payload.launchId, payload.launchSize,
		payload.subgroupSize, payload.subgroupInvocationId };
	T data = payload.data;
	spvRayInvocation ray = { reinterpret_cast<thread void*>(&data), context, 0 };
	uint intersection = spvIntersectionFunctionHandle(dispatch->hitAddress, dispatch->hitStride, functionId);
	if (intersection) spvCallIntersectionFunction(intersection, ray, state);
	payload.data = data;
	if (ray.context.reportAccepted && ray.context.reportedDistance <= payload.reportedDistance) {
		payload.reportedDistance = ray.context.reportedDistance;
		payload.hitAttribute = ray.context.reportedHitAttribute;
		payload.hitKind = ray.context.reportedHitKind;
	}
	return { ray.context.reportAccepted, ray.action != 2u, ray.context.reportedDistance };
}
#endif

#if SPV_RAY_PROCEDURAL_IFB_WRAPPER
#define SPV_RAY_IFB_ENTRY(NAME, PAYLOAD) \
[[intersection(bounding_box, instancing, world_space_data, intersection_function_buffer, user_data)]] \
spvIFBIntersectionDecision NAME(ray_data spvIFBPayload<PAYLOAD>& payload [[payload]], \
	float3 objectOrigin [[origin]], float3 objectDirection [[direction]], \
	float rayTmin [[min_distance]], float rayTmax [[max_distance]], \
	float3 worldOrigin [[world_space_origin]], float3 worldDirection [[world_space_direction]], bool opaque [[opaque]], \
	uint customIndex [[user_instance_id]], uint instanceId [[instance_id]], \
	float4x3 objectToWorld [[object_to_world_transform]], float4x3 worldToObject [[world_to_object_transform]], \
	uint geometryId [[geometry_id]], uint primitiveId [[primitive_id]], uint functionId [[function_id]], \
	const device spvRayTracingDispatch* dispatch [[user_data_buffer]]) { \
	return spvRunProceduralIFB(payload, objectOrigin, objectDirection, rayTmin, rayTmax, worldOrigin, worldDirection, opaque, \
		customIndex, instanceId, objectToWorld, worldToObject, geometryId, primitiveId, functionId, dispatch); \
}
#else
#define SPV_RAY_IFB_ENTRY(NAME, PAYLOAD) \
[[intersection(triangle, instancing, triangle_data, world_space_data, intersection_function_buffer, user_data)]] \
spvIFBDecision NAME(ray_data spvIFBPayload<PAYLOAD>& payload [[payload]], \
	float3 objectOrigin [[origin]], float3 objectDirection [[direction]], \
	float rayTmin [[min_distance]], float rayTmax [[distance]], \
	float3 worldOrigin [[world_space_origin]], float3 worldDirection [[world_space_direction]], \
	float2 barycentrics [[barycentric_coord]], bool frontFacing [[front_facing]], \
	uint customIndex [[user_instance_id]], uint instanceId [[instance_id]], \
	float4x3 objectToWorld [[object_to_world_transform]], float4x3 worldToObject [[world_to_object_transform]], \
	uint geometryId [[geometry_id]], uint primitiveId [[primitive_id]], uint functionId [[function_id]], \
	const device spvRayTracingDispatch* dispatch [[user_data_buffer]]) { \
	thread spvRayTracingContext context = spvMakeIFBContext(payload.launchId, payload.launchSize, objectOrigin, objectDirection, \
		rayTmin, rayTmax, worldOrigin, worldDirection, barycentrics, frontFacing, customIndex, instanceId, objectToWorld, \
		worldToObject, geometryId, primitiveId, functionId, payload.rayFlags, payload.cullMask); \
	thread spvRayTracingIFBState state = { dispatch, payload.launchId, payload.launchSize, payload.subgroupSize, payload.subgroupInvocationId }; \
	uint action = 0; NAME##_ifb_impl(payload, context, action, state); \
	return { action != 1u, action != 2u }; \
}
#endif

static inline __attribute__((always_inline)) void spvCallMiss(
	uint index, thread spvRayInvocation& ray, thread spvRayTracingState& state) {
	constant spvRayTracingDispatch& dispatch = *state.dispatch;
	if (!dispatch.missAddress) return;
	ray.context.shaderRecordIndex = index & 65535u;
	ulong record = dispatch.missAddress + ulong(ray.context.shaderRecordIndex) * dispatch.missStride;
	uint handle = *reinterpret_cast<device const uint*>(record + 8);
	if (handle) spvCallRayFunction(handle, ray, state);
}

template<typename T>
static inline __attribute__((always_inline)) void spvExecuteCallable(
	uint index, thread T& data, thread spvRayTracingState& state) {
	constant spvRayTracingDispatch& dispatch = *state.dispatch;
	ulong record = dispatch.callableAddress + ulong(index) * dispatch.callableStride;
	uint handle = *reinterpret_cast<device const uint*>(record + 8);
	spvCallableInvocation ray = { reinterpret_cast<thread void*>(&data), record + 32 };
	if (handle) state.callables[handle](ray, state);
}

static inline __attribute__((always_inline)) bool spvReportIntersection(
	float distance, uint hitKind, thread spvRayInvocation& ray, thread spvRayTracingState& state) {
	constant spvRayTracingDispatch& dispatch = *state.dispatch;
	if (ray.action == 2) return true;
	bool accepted = distance >= ray.context.RayTminKHR && distance <= ray.context.RayTmaxKHR;
	ray.action = 0;
	uint anyHit = reinterpret_cast<device const uint*>(
		dispatch.hitAddress + ulong(ray.context.shaderRecordIndex) * dispatch.hitStride)[3];
	if (accepted && ray.context.candidateNonOpaque && anyHit) {
		float savedTmax = ray.context.RayTmaxKHR;
		ray.context.RayTmaxKHR = distance;
		ray.context.HitKindKHR = hitKind;
		spvCallRayFunction(anyHit, ray, state);
		ray.context.RayTmaxKHR = savedTmax;
		accepted = ray.action != 1;
	}
	if (accepted) {
		ray.context.reportAccepted = true;
		if (distance <= ray.context.reportedDistance) {
			ray.context.reportedDistance = distance;
			ray.context.RayTmaxKHR = distance;
			ray.context.reportedHitKind = hitKind;
			ray.context.reportedHitAttribute = ray.context.hitAttribute;
		}
		if (ray.context.IncomingRayFlagsKHR & 4u) ray.action = 2;
	}
	return accepted;
}

template<typename T>
static inline __attribute__((always_inline)) void spvTraceRay(
	device const ulong* scene, uint rayFlags, uint cullMask, uint sbtOffset, uint sbtStride,
	uint missIndex, float3 origin, float tmin, float3 direction, float tmax,
	thread T& payload, thread spvRayTracingState& state) {
	constant spvRayTracingDispatch& dispatch = *state.dispatch;
	spvRayInvocation invocation = { reinterpret_cast<thread void*>(&payload), {}, 0 };
	thread spvRayTracingContext& context = invocation.context;
	thread uint& action = invocation.action;
	context.LaunchIdKHR = state.LaunchIdKHR;
	context.LaunchSizeKHR = state.LaunchSizeKHR;
	context.WorldRayOriginKHR = origin;
	context.WorldRayDirectionKHR = direction;
	context.RayTminKHR = tmin;
	context.RayTmaxKHR = tmax;
	context.traceRayTmax = tmax;
	context.IncomingRayFlagsKHR = rayFlags;
	context.CullMaskKHR = cullMask & 255u;
	uint flags = rayFlags | dispatch.pipelineFlags;
	constexpr uint nativeFlags = 1u | 8u | 512u;
	constexpr uint incompatibleFlags = 2u | 64u | 128u | 256u | 1024u;
	if ((flags & (nativeFlags | incompatibleFlags)) == nativeFlags && (flags & 48u) != 48u) {
		intersector<instancing> nativeIntersector;
		nativeIntersector.force_opacity(forced_opacity::opaque);
		nativeIntersector.set_geometry_cull_mode(geometry_cull_mode::bounding_box);
		if (flags & 4u) nativeIntersector.accept_any_intersection(true);
		if (flags & 16u) nativeIntersector.set_triangle_cull_mode(triangle_cull_mode::back);
		if (flags & 32u) nativeIntersector.set_triangle_cull_mode(triangle_cull_mode::front);
		auto result = nativeIntersector.intersect(ray(origin, direction, tmin, tmax),
			*reinterpret_cast<device const acceleration_structure<instancing>*>(scene), context.CullMaskKHR);
		if (result.type == intersection_type::none) spvCallMiss(missIndex, invocation, state);
		return;
	}
	device const uint* metadata = dispatch.hitSize
		? reinterpret_cast<device const uint*>(scene[1]) : nullptr;

#if SPV_RAY_IFB
	if (dispatch.usesIFB &&
#if !SPV_RAY_PROCEDURAL_IFB
		!(flags & 256u) &&
#endif
		(flags & 48u) != 48u &&
		!((flags & 3u) && (flags & 192u))) {
		intersector<instancing, triangle_data, world_space_data,
			intersection_function_buffer, user_data> nativeIntersector;
#if SPV_RAY_PROCEDURAL_IFB
		if (flags & 256u) nativeIntersector.set_geometry_cull_mode(geometry_cull_mode::triangle);
		if (flags & 512u) nativeIntersector.set_geometry_cull_mode(geometry_cull_mode::bounding_box);
#else
		nativeIntersector.set_geometry_cull_mode(geometry_cull_mode::bounding_box);
#endif
		if (flags & 1u) nativeIntersector.force_opacity(forced_opacity::opaque);
		if (flags & 2u) nativeIntersector.force_opacity(forced_opacity::non_opaque);
		if (flags & 4u) nativeIntersector.accept_any_intersection(true);
		if (flags & 16u) nativeIntersector.set_triangle_cull_mode(triangle_cull_mode::back);
		if (flags & 32u) nativeIntersector.set_triangle_cull_mode(triangle_cull_mode::front);
		if (flags & 64u) nativeIntersector.set_opacity_cull_mode(opacity_cull_mode::opaque);
		if (flags & 128u) nativeIntersector.set_opacity_cull_mode(opacity_cull_mode::non_opaque);
		nativeIntersector.set_base_id(sbtOffset & 15u);
		nativeIntersector.set_geometry_multiplier(sbtStride & 15u);
		intersection_function_buffer_arguments arguments;
		arguments.intersection_function_buffer = reinterpret_cast<const device void*>(dispatch.hitAddress);
		arguments.intersection_function_buffer_size = dispatch.hitSize;
		arguments.intersection_function_stride = dispatch.hitStride;
		spvIFBPayload<T> ifbPayload = {
			payload, state.LaunchIdKHR, state.LaunchSizeKHR, state.SubgroupSize,
			state.SubgroupLocalInvocationId, rayFlags, context.CullMaskKHR,
#if SPV_RAY_PROCEDURAL_IFB
			{}, tmax, 0,
#endif
		};
		auto result = nativeIntersector.intersect(
			ray(origin, direction, tmin, tmax),
			*reinterpret_cast<device const acceleration_structure<instancing>*>(scene),
			context.CullMaskKHR, arguments,
			reinterpret_cast<const device void*>(state.dispatchAddress), ifbPayload);
		payload = ifbPayload.data;
		if (result.type == intersection_type::none) {
			spvCallMiss(missIndex, invocation, state);
			return;
		}
		if ((rayFlags & 8u) || !dispatch.hitSize) return;
		context.ObjectRayOriginKHR = result.world_to_object_transform * float4(origin, 1.0f);
		context.ObjectRayDirectionKHR = result.world_to_object_transform * float4(direction, 0.0f);
		context.RayTmaxKHR = result.distance;
		context.InstanceId = result.instance_id;
		context.InstanceCustomIndexKHR = result.user_instance_id;
		context.ObjectToWorldKHR = result.object_to_world_transform;
		context.WorldToObjectKHR = result.world_to_object_transform;
		if (result.type == intersection_type::triangle) {
			*reinterpret_cast<thread float2*>(&context.hitAttribute) = result.triangle_barycentric_coord;
			context.HitKindKHR = result.triangle_front_facing ? 0xfeu : 0xffu;
		} else {
#if SPV_RAY_PROCEDURAL_IFB
			context.hitAttribute = ifbPayload.hitAttribute;
			context.HitKindKHR = ifbPayload.hitKind;
#endif
		}
		context.RayGeometryIndexKHR = result.geometry_id;
		context.PrimitiveId = result.primitive_id;
		context.shaderRecordIndex = context.RayGeometryIndexKHR * (sbtStride & 15u) +
			(sbtOffset & 15u) + metadata[context.InstanceId];
		uint closestHit = *reinterpret_cast<device const uint*>(
			dispatch.hitAddress + ulong(context.shaderRecordIndex) * dispatch.hitStride + 8);
		if (closestHit) spvCallRayFunction(closestHit, invocation, state);
		return;
	}
#endif

	intersection_query<instancing, triangle_data> query;
	query.reset(ray(origin, direction, tmin, tmax),
		*reinterpret_cast<device const acceleration_structure<instancing>*>(scene),
		context.CullMaskKHR, spvTraceIntersectionParams(flags));
	while (query.next()) {
		if (query.get_candidate_intersection_type() == intersection_type::triangle) {
			action = 0;
			if (dispatch.hitSize) {
				context.ObjectRayOriginKHR = query.get_candidate_ray_origin();
				context.ObjectRayDirectionKHR = query.get_candidate_ray_direction();
				context.RayTmaxKHR = query.get_candidate_triangle_distance();
				context.InstanceId = query.get_candidate_instance_id();
				context.InstanceCustomIndexKHR = query.get_candidate_user_instance_id();
				context.ObjectToWorldKHR = query.get_candidate_object_to_world_transform();
				context.WorldToObjectKHR = query.get_candidate_world_to_object_transform();
				*reinterpret_cast<thread float2*>(&context.hitAttribute) = query.get_candidate_triangle_barycentric_coord();
				context.HitKindKHR = query.is_candidate_triangle_front_facing() ? 0xfeu : 0xffu;
				context.RayGeometryIndexKHR = query.get_candidate_geometry_id();
				context.PrimitiveId = query.get_candidate_primitive_id();
				context.shaderRecordIndex = context.RayGeometryIndexKHR * (sbtStride & 15u) +
					(sbtOffset & 15u) + metadata[context.InstanceId];
				uint anyHit = reinterpret_cast<device const uint*>(
					dispatch.hitAddress + ulong(context.shaderRecordIndex) * dispatch.hitStride)[3];
				if (anyHit) spvCallRayFunction(anyHit, invocation, state);
			}
			if (action != 1) query.commit_triangle_intersection();
			if (action == 2) query.abort();
		} else if (query.get_candidate_intersection_type() == intersection_type::bounding_box && dispatch.hitSize) {
			context.ObjectRayOriginKHR = query.get_candidate_ray_origin();
			context.ObjectRayDirectionKHR = query.get_candidate_ray_direction();
			context.RayTmaxKHR = query.get_committed_intersection_type() == intersection_type::none
				? context.traceRayTmax : query.get_committed_distance();
			context.InstanceId = query.get_candidate_instance_id();
			context.InstanceCustomIndexKHR = query.get_candidate_user_instance_id();
			context.ObjectToWorldKHR = query.get_candidate_object_to_world_transform();
			context.WorldToObjectKHR = query.get_candidate_world_to_object_transform();
			context.RayGeometryIndexKHR = query.get_candidate_geometry_id();
			context.PrimitiveId = query.get_candidate_primitive_id();
			context.shaderRecordIndex = context.RayGeometryIndexKHR * (sbtStride & 15u) +
				(sbtOffset & 15u) + metadata[context.InstanceId];
			context.reportAccepted = false;
			context.reportedDistance = context.RayTmaxKHR;
			context.candidateNonOpaque = query.is_candidate_non_opaque_bounding_box();
			uint intersection = reinterpret_cast<device const uint*>(
				dispatch.hitAddress + ulong(context.shaderRecordIndex) * dispatch.hitStride)[4];
			action = 0;
			if (intersection) spvCallIntersectionFunction(intersection, invocation, state);
			if (context.reportAccepted) query.commit_bounding_box_intersection(context.reportedDistance);
			if (action == 2) query.abort();
		}
	}

	if (query.get_committed_intersection_type() == intersection_type::none) {
		context.RayTmaxKHR = context.traceRayTmax;
		action = 0;
		spvCallMiss(missIndex, invocation, state);
		return;
	}

	if ((rayFlags & 8u) || !dispatch.hitSize) return;
	context.ObjectRayOriginKHR = query.get_committed_ray_origin();
	context.ObjectRayDirectionKHR = query.get_committed_ray_direction();
	context.RayTmaxKHR = query.get_committed_distance();
	context.InstanceId = query.get_committed_instance_id();
	context.InstanceCustomIndexKHR = query.get_committed_user_instance_id();
	context.ObjectToWorldKHR = query.get_committed_object_to_world_transform();
	context.WorldToObjectKHR = query.get_committed_world_to_object_transform();
	if (query.get_committed_intersection_type() == intersection_type::triangle) {
		*reinterpret_cast<thread float2*>(&context.hitAttribute) = query.get_committed_triangle_barycentric_coord();
		context.HitKindKHR = query.is_committed_triangle_front_facing() ? 0xfeu : 0xffu;
	} else {
		context.hitAttribute = context.reportedHitAttribute;
		context.HitKindKHR = context.reportedHitKind;
	}
	context.RayGeometryIndexKHR = query.get_committed_geometry_id();
	context.PrimitiveId = query.get_committed_primitive_id();
	context.shaderRecordIndex = context.RayGeometryIndexKHR * (sbtStride & 15u) +
		(sbtOffset & 15u) + metadata[context.InstanceId];
	uint closestHit = *reinterpret_cast<device const uint*>(
		dispatch.hitAddress + ulong(context.shaderRecordIndex) * dispatch.hitStride + 8);
	action = 0;
	if (closestHit) spvCallRayFunction(closestHit, invocation, state);
}

)MVKRT";
	return source;
}


#pragma mark -
#pragma mark SPIRVToMSLConversionConfiguration

// Returns whether the container contains an item equal to the value.
template<class C, class T>
bool contains(const C& container, const T& val) {
	for (const T& cVal : container) { if (cVal == val) { return true; } }
	return false;
}

// Returns whether the vector contains the value (using a matches(T&) comparison member function). */
template<class T>
bool containsMatching(const vector<T>& vec, const T& val) {
    for (const T& vecVal : vec) { if (vecVal.matches(val)) { return true; } }
    return false;
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionOptions::matches(const SPIRVToMSLConversionOptions& other) const {
	if (memcmp(&mslOptions, &other.mslOptions, sizeof(mslOptions)) != 0) { return false; }
	if (descriptorSetCount != other.descriptorSetCount) { return false; }
	if (entryPointStage != other.entryPointStage) { return false; }
	if (entryPointName != other.entryPointName) { return false; }
	if (rayTracingFunctionHash != other.rayTracingFunctionHash) { return false; }
	if (enableRayTracingIFB != other.enableRayTracingIFB) { return false; }
	if (enableRayTracingProceduralIFB != other.enableRayTracingProceduralIFB) { return false; }
	if (rayTracingFunctionTableBufferIndex != other.rayTracingFunctionTableBufferIndex) { return false; }
	if (rayTracingIntersectionTableBufferIndex != other.rayTracingIntersectionTableBufferIndex) { return false; }
	if (rayTracingCallableTableBufferIndex != other.rayTracingCallableTableBufferIndex) { return false; }
	if (tessPatchKind != other.tessPatchKind) { return false; }
	if (numTessControlPoints != other.numTessControlPoints) { return false; }
	if (shouldFlipVertexY != other.shouldFlipVertexY) { return false; }
	if (shouldFixupClipSpace != other.shouldFixupClipSpace) { return false; }
	return true;
}

MVK_PUBLIC_SYMBOL string SPIRVToMSLConversionOptions::printMSLVersion(uint32_t mslVersion, bool includePatch) {
	string verStr;

	uint32_t major = mslVersion / 10000;
	verStr += to_string(major);

	uint32_t minor = (mslVersion - CompilerMSL::Options::make_msl_version(major)) / 100;
	verStr += ".";
	verStr += to_string(minor);

	if (includePatch) {
		uint32_t patch = mslVersion - CompilerMSL::Options::make_msl_version(major, minor);
		verStr += ".";
		verStr += to_string(patch);
	}

	return verStr;
}

MVK_PUBLIC_SYMBOL SPIRVToMSLConversionOptions::SPIRVToMSLConversionOptions() {
	// Explicitly set mslOptions to defaults over cleared memory to ensure all instances
	// have exactly the same memory layout when using memory comparison in matches().
	memset(&mslOptions, 0, sizeof(mslOptions));
	mslOptions = CompilerMSL::Options();

#if MVK_MACOS
	mslOptions.platform = CompilerMSL::Options::macOS;
#else
	mslOptions.platform = CompilerMSL::Options::iOS;
#endif

	mslOptions.pad_fragment_output_components = true;
}

static string getMSLEntryPointName(const SPIRVToMSLConversionOptions& options) {
	string name = options.entryPointName;
	if (!options.rayTracingFunctionHash) { return name; }
	switch (options.entryPointStage) {
		case ExecutionModelMissKHR: name += "_mvkMiss"; break;
		case ExecutionModelClosestHitKHR: name += "_mvkClosestHit"; break;
		case ExecutionModelAnyHitKHR: name += "_mvkAnyHit"; break;
		case ExecutionModelIntersectionKHR: name += "_mvkIntersection"; break;
		case ExecutionModelCallableKHR: name += "_mvkCallable"; break;
		default: break;
	}
	name += "_mvk" + to_string(options.rayTracingFunctionHash);
#if MVK_SPIRV_CROSS_RT_PIPELINE
	if (options.mslOptions.ray_tracing_any_hit_ifb) { name += "IFB"; }
	if (options.mslOptions.ray_tracing_intersection_ifb) { name += "ProceduralIFB"; }
#endif
	return name;
}

MVK_PUBLIC_SYMBOL bool mvk::MSLShaderInterfaceVariable::matches(const mvk::MSLShaderInterfaceVariable& other) const {
	if (memcmp(&shaderVar, &other.shaderVar, sizeof(shaderVar)) != 0) { return false; }
	if (binding != other.binding) { return false; }
	return true;
}

MVK_PUBLIC_SYMBOL mvk::MSLShaderInterfaceVariable::MSLShaderInterfaceVariable() {
	// Explicitly set shaderVar to defaults over cleared memory to ensure all instances
	// have exactly the same memory layout when using memory comparison in matches().
	memset(&shaderVar, 0, sizeof(shaderVar));
	shaderVar = SPIRV_CROSS_NAMESPACE::MSLShaderInterfaceVariable();
}

// If requiresConstExprSampler is false, constExprSampler can be ignored
MVK_PUBLIC_SYMBOL bool mvk::MSLResourceBinding::matches(const MSLResourceBinding& other) const {
	if (memcmp(&resourceBinding, &other.resourceBinding, sizeof(resourceBinding)) != 0) { return false; }
	if (requiresConstExprSampler != other.requiresConstExprSampler) { return false; }
	if (requiresConstExprSampler) {
		if (memcmp(&constExprSampler, &other.constExprSampler, sizeof(constExprSampler)) != 0) { return false; }
	}
	return true;
}

MVK_PUBLIC_SYMBOL mvk::MSLResourceBinding::MSLResourceBinding() {
	// Explicitly set resourceBinding and constExprSampler to defaults over cleared memory to ensure
	// all instances have exactly the same memory layout when using memory comparison in matches().
	memset(&resourceBinding, 0, sizeof(resourceBinding));
	resourceBinding = SPIRV_CROSS_NAMESPACE::MSLResourceBinding();
	memset(&constExprSampler, 0, sizeof(constExprSampler));
	constExprSampler = SPIRV_CROSS_NAMESPACE::MSLConstexprSampler();
}

MVK_PUBLIC_SYMBOL bool mvk::DescriptorBinding::matches(const mvk::DescriptorBinding& other) const {
	if (stage != other.stage) { return false; }
	if (descriptorSet != other.descriptorSet) { return false; }
	if (binding != other.binding) { return false; }
	if (index != other.index) { return false; }
	return true;
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionConfiguration::stageSupportsVertexAttributes() const {
	return (options.entryPointStage == ExecutionModelVertex ||
			options.entryPointStage == ExecutionModelTessellationControl ||
			options.entryPointStage == ExecutionModelTessellationEvaluation);
}

// Check them all in case inactive VA's duplicate locations used by active VA's.
MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionConfiguration::isShaderInputLocationUsed(uint32_t location) const {
    for (auto& si : shaderInputs) {
        if ((si.shaderVar.location == location) && si.outIsUsedByShader) { return true; }
    }
    return false;
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionConfiguration::isShaderInputBuiltInUsed(spv::BuiltIn builtin) const {
    for (auto& si : shaderInputs) {
        if ((si.shaderVar.builtin == builtin) && si.outIsUsedByShader) { return true; }
    }
    return false;
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionConfiguration::isShaderOutputLocationUsed(uint32_t location) const {
    for (auto& so : shaderOutputs) {
        if ((so.shaderVar.location == location) && so.outIsUsedByShader) { return true; }
    }
    return false;
}

MVK_PUBLIC_SYMBOL uint32_t SPIRVToMSLConversionConfiguration::countShaderInputsAt(uint32_t binding) const {
	uint32_t siCnt = 0;
	for (auto& si : shaderInputs) {
		if ((si.binding == binding) && si.outIsUsedByShader) { siCnt++; }
	}
	return siCnt;
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionConfiguration::isResourceUsed(ExecutionModel stage, uint32_t descSet, uint32_t binding) const {
	for (auto& rb : resourceBindings) {
		auto& rbb = rb.resourceBinding;
		if (rbb.stage == stage && rbb.desc_set == descSet && rbb.binding == binding) {
			return rb.outIsUsedByShader;
		}
	}
	return false;
}

MVK_PUBLIC_SYMBOL void SPIRVToMSLConversionConfiguration::markAllInterfaceVarsAndResourcesUsed() {
	for (auto& si : shaderInputs) { si.outIsUsedByShader = true; }
	for (auto& so : shaderOutputs) { so.outIsUsedByShader = true; }
	for (auto& rb : resourceBindings) { rb.outIsUsedByShader = true; }
}

// A single SPIRVToMSLConversionConfiguration instance is used for all pipeline shader stages,
// and the resources can be spread across these shader stages. To improve cache hits when using
// this function to find a cached shader for a particular shader stage, only consider the resources
// that are used in that shader stage. By contrast, discreteDescriptorSet apply across all stages,
// and shaderInputs and shaderOutputs are populated before each stage, so neither needs to be filtered by stage here.
MVK_PUBLIC_SYMBOL bool SPIRVToMSLConversionConfiguration::matches(const SPIRVToMSLConversionConfiguration& other) const {

    if ( !options.matches(other.options) ) { return false; }

	for (const auto& si : shaderInputs) {
		if (si.outIsUsedByShader && !containsMatching(other.shaderInputs, si)) { return false; }
	}

	for (const auto& so : shaderOutputs) {
		if (so.outIsUsedByShader && !containsMatching(other.shaderOutputs, so)) { return false; }
	}

    for (const auto& rb : resourceBindings) {
        if (rb.resourceBinding.stage == options.entryPointStage &&
			rb.outIsUsedByShader &&
			!containsMatching(other.resourceBindings, rb)) { return false; }
    }

	for (const auto& db : dynamicBufferDescriptors) {
		if (db.stage == options.entryPointStage &&
			!containsMatching(other.dynamicBufferDescriptors, db)) { return false; }
	}
	for (const auto& db : other.dynamicBufferDescriptors) {
		if (db.stage == options.entryPointStage &&
			!containsMatching(dynamicBufferDescriptors, db)) { return false; }
	}

	for (uint32_t dsIdx : discreteDescriptorSets) {
		if ( !contains(other.discreteDescriptorSets, dsIdx)) { return false; }
	}
	for (uint32_t dsIdx : other.discreteDescriptorSets) {
		if ( !contains(discreteDescriptorSets, dsIdx)) { return false; }
	}

    return true;
}


MVK_PUBLIC_SYMBOL void SPIRVToMSLConversionConfiguration::alignWith(const SPIRVToMSLConversionConfiguration& srcContext) {

	for (auto& si : shaderInputs) {
		si.outIsUsedByShader = false;
		for (auto& srcSI : srcContext.shaderInputs) {
			if (si.matches(srcSI)) { si.outIsUsedByShader = srcSI.outIsUsedByShader; }
		}
	}

	for (auto& so : shaderOutputs) {
		so.outIsUsedByShader = false;
		for (auto& srcSO : srcContext.shaderOutputs) {
			if (so.matches(srcSO)) { so.outIsUsedByShader = srcSO.outIsUsedByShader; }
		}
	}

    for (auto& rb : resourceBindings) {
        rb.outIsUsedByShader = false;
        for (auto& srcRB : srcContext.resourceBindings) {
			if (rb.matches(srcRB)) {
				rb.outIsUsedByShader = srcRB.outIsUsedByShader;
			}
        }
    }
}


#pragma mark -
#pragma mark SPIRVToMSLConverter

MVK_PUBLIC_SYMBOL void SPIRVToMSLConverter::setSPIRV(const uint32_t* spirvCode, size_t length) {
	_spirv.clear();			// Clear for reuse
	_spirv.reserve(length);
	for (size_t i = 0; i < length; i++) {
		_spirv.push_back(spirvCode[i]);
	}
}

MVK_PUBLIC_SYMBOL bool SPIRVToMSLConverter::convert(SPIRVToMSLConversionConfiguration& shaderConfig,
													SPIRVToMSLConversionResult& conversionResult,
													bool shouldLogSPIRV,
													bool shouldLogMSL,
                                                    bool shouldLogGLSL) {

	// Uncomment to write SPIR-V to file as a debugging aid
//	ofstream spvFile("spirv.spv", ios::binary);
//	spvFile.write((char*)_spirv.data(), _spirv.size() << 2);
//	spvFile.close();

	if (shouldLogSPIRV) { logSPIRV(conversionResult.resultLog, "Converting"); }

	CompilerMSL* pMSLCompiler = nullptr;
	bool wasConverted = true;

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
	try {
#endif
		pMSLCompiler = new CompilerMSL(_spirv);

		if (shaderConfig.options.hasEntryPoint()) {
			auto mslEntryPointName = getMSLEntryPointName(shaderConfig.options);
			if (mslEntryPointName != shaderConfig.options.entryPointName) {
				pMSLCompiler->rename_entry_point(shaderConfig.options.entryPointName, mslEntryPointName,
				                                 shaderConfig.options.entryPointStage);
			}
			pMSLCompiler->set_entry_point(mslEntryPointName, shaderConfig.options.entryPointStage);
		}

		// Set up tessellation parameters if needed.
		if (shaderConfig.options.entryPointStage == ExecutionModelTessellationControl ||
			shaderConfig.options.entryPointStage == ExecutionModelTessellationEvaluation) {
			if (shaderConfig.options.tessPatchKind != ExecutionModeMax) {
				pMSLCompiler->set_execution_mode(shaderConfig.options.tessPatchKind);
			}
			if (shaderConfig.options.numTessControlPoints != 0) {
				pMSLCompiler->set_execution_mode(ExecutionModeOutputVertices, shaderConfig.options.numTessControlPoints);
			}
		}

		// Establish the MSL options for the compiler
		// This needs to be done in two steps...for CompilerMSL and its superclass.
		bool isRayTracingPipeline = shaderConfig.options.entryPointStage >= ExecutionModelRayGenerationKHR &&
			shaderConfig.options.entryPointStage <= ExecutionModelCallableKHR;
#if SPIRV_CROSS_MSL_RAY_TRACING_PIPELINE
		shaderConfig.options.mslOptions.ray_tracing_pipeline = isRayTracingPipeline;
#endif
		pMSLCompiler->set_msl_options(shaderConfig.options.mslOptions);
#if SPIRV_CROSS_MSL_RAY_TRACING_PIPELINE
		if (isRayTracingPipeline) {
			uint32_t contextKind = shaderConfig.options.mslOptions.ray_tracing_any_hit_ifb ? 3 :
				shaderConfig.options.mslOptions.ray_tracing_intersection_ifb ? 4 :
				shaderConfig.options.entryPointStage == ExecutionModelRayGenerationKHR ? 0 :
				shaderConfig.options.entryPointStage == ExecutionModelCallableKHR ? 2 : 1;
			pMSLCompiler->add_header_line("#define SPV_RAY_CONTEXT_KIND " + to_string(contextKind));
			pMSLCompiler->add_header_line(shaderConfig.options.enableRayTracingIFB
				? "#define SPV_RAY_IFB 1" : "#define SPV_RAY_IFB 0");
			pMSLCompiler->add_header_line(shaderConfig.options.enableRayTracingProceduralIFB
				? "#define SPV_RAY_PROCEDURAL_IFB 1" : "#define SPV_RAY_PROCEDURAL_IFB 0");
			pMSLCompiler->add_header_line(shaderConfig.options.mslOptions.ray_tracing_intersection_ifb
				? "#define SPV_RAY_PROCEDURAL_IFB_WRAPPER 1" : "#define SPV_RAY_PROCEDURAL_IFB_WRAPPER 0");
			if (shaderConfig.options.mslOptions.ray_tracing_intersection_ifb) {
				pMSLCompiler->add_header_line("#define SPV_RAY_FUNCTION_TABLE_BUFFER_INDEX " +
					to_string(shaderConfig.options.rayTracingFunctionTableBufferIndex));
				pMSLCompiler->add_header_line("#define SPV_RAY_INTERSECTION_TABLE_BUFFER_INDEX " +
					to_string(shaderConfig.options.rayTracingIntersectionTableBufferIndex));
				pMSLCompiler->add_header_line("#define SPV_RAY_CALLABLE_TABLE_BUFFER_INDEX " +
					to_string(shaderConfig.options.rayTracingCallableTableBufferIndex));
			}
			pMSLCompiler->add_header_line(getRayTracingRuntimeMSL());
		}
#endif

		auto scOpts = pMSLCompiler->get_common_options();
		scOpts.vertex.flip_vert_y = shaderConfig.options.shouldFlipVertexY;
		scOpts.vertex.fixup_clipspace = shaderConfig.options.shouldFixupClipSpace;
		pMSLCompiler->set_common_options(scOpts);

		// Add shader inputs and outputs
		for (auto& si : shaderConfig.shaderInputs) {
			pMSLCompiler->add_msl_shader_input(si.shaderVar);
		}

		for (auto& so : shaderConfig.shaderOutputs) {
			pMSLCompiler->add_msl_shader_output(so.shaderVar);
		}

		// Add resource bindings and hardcoded constexpr samplers
		for (auto& rb : shaderConfig.resourceBindings) {
			auto& rbb = rb.resourceBinding;
			if (rbb.stage == shaderConfig.options.entryPointStage) {
				pMSLCompiler->add_msl_resource_binding(rbb);
#if SPIRV_CROSS_MSL_RAY_TRACING_PIPELINE
				if (isRayTracingPipeline) {
					pMSLCompiler->set_argument_buffer_device_address_space(rbb.desc_set, true);
				}
#endif
				if (rb.requiresConstExprSampler) {
					pMSLCompiler->remap_constexpr_sampler_by_binding(rbb.desc_set, rbb.binding, rb.constExprSampler);
				}
			}
		}

		// Add any descriptor sets that are not using Metal argument buffers.
		// This only has an effect if SPIRVToMSLConversionConfiguration::options::mslOptions::argument_buffers is enabled.
		for (uint32_t dsIdx : shaderConfig.discreteDescriptorSets) {
			pMSLCompiler->add_discrete_descriptor_set(dsIdx);
		}

		// Add any dynamic buffer bindings.
		// This only has an applies if SPIRVToMSLConversionConfiguration::options::mslOptions::argument_buffers is enabled.
		if (shaderConfig.options.mslOptions.argument_buffers) {
			for (auto& db : shaderConfig.dynamicBufferDescriptors) {
				if (db.stage == shaderConfig.options.entryPointStage) {
					pMSLCompiler->add_dynamic_buffer(db.descriptorSet, db.binding, db.index);
				}
			}
		}
		conversionResult.msl = pMSLCompiler->compile();
#if SPIRV_CROSS_MSL_ACCELERATION_STRUCTURE_DESCRIPTOR_AS_ADDRESS
		if (pMSLCompiler->needs_acceleration_structure_address_table() &&
		    !isRayTracingPipeline) {
			conversionResult.msl.insert(0, getAccelerationStructureAddressMSL());
		}
#endif

        if (shouldLogMSL) { logSource(conversionResult.resultLog, conversionResult.msl, "MSL", "Converted"); }

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
	} catch (CompilerError& ex) {
		string errMsg("SPIR-V to MSL conversion error: ");
		errMsg += ex.what();
		logError(conversionResult.resultLog, errMsg.data());
        if (shouldLogMSL && pMSLCompiler) {
			auto partialMSL = pMSLCompiler->get_partial_source();
            logSource(conversionResult.resultLog, partialMSL, "MSL", "Partially converted");
        }
	}
#endif

	// Populate the shader conversion results with info from the compilation run,
	// and mark which vertex attributes and resource bindings are used by the shader
	populateEntryPoint(pMSLCompiler, shaderConfig.options, conversionResult.resultInfo.entryPoint);
	conversionResult.resultInfo.isRasterizationDisabled = pMSLCompiler && pMSLCompiler->get_is_rasterization_disabled();
	conversionResult.resultInfo.isPositionInvariant = pMSLCompiler && pMSLCompiler->is_position_invariant();
	conversionResult.resultInfo.needsSwizzleBuffer = pMSLCompiler && pMSLCompiler->needs_swizzle_buffer();
	conversionResult.resultInfo.needsOutputBuffer = pMSLCompiler && pMSLCompiler->needs_output_buffer();
	conversionResult.resultInfo.needsPatchOutputBuffer = pMSLCompiler && pMSLCompiler->needs_patch_output_buffer();
	conversionResult.resultInfo.needsBufferSizeBuffer = pMSLCompiler && pMSLCompiler->needs_buffer_size_buffer();
#if SPIRV_CROSS_MSL_ACCELERATION_STRUCTURE_DESCRIPTOR_AS_ADDRESS
	conversionResult.resultInfo.needsAccelerationStructureAddressTable =
		pMSLCompiler && pMSLCompiler->needs_acceleration_structure_address_table();
#else
	conversionResult.resultInfo.needsAccelerationStructureAddressTable = false;
#endif
	conversionResult.resultInfo.needsInputThreadgroupMem = pMSLCompiler && pMSLCompiler->needs_input_threadgroup_mem();
	conversionResult.resultInfo.needsDispatchBaseBuffer = pMSLCompiler && pMSLCompiler->needs_dispatch_base_buffer();
	conversionResult.resultInfo.needsViewRangeBuffer = pMSLCompiler && pMSLCompiler->needs_view_mask_buffer();
	conversionResult.resultInfo.needsDrawId = pMSLCompiler && pMSLCompiler->has_active_builtin(spv::BuiltInDrawIndex, spv::StorageClassInput);
	conversionResult.resultInfo.usesPhysicalStorageBufferAddressesCapability = usesPhysicalStorageBufferAddressesCapability(pMSLCompiler);
	populateSpecializationMacros(pMSLCompiler, conversionResult.resultInfo.specializationMacros);

	// When using Metal argument buffers, if the shader is provided with dynamic buffer offsets,
	// then it needs a buffer to hold these dynamic offsets.
	conversionResult.resultInfo.needsDynamicOffsetBuffer = false;
	if (shaderConfig.options.mslOptions.argument_buffers) {
		for (auto& db : shaderConfig.dynamicBufferDescriptors) {
			if (db.stage == shaderConfig.options.entryPointStage) {
				conversionResult.resultInfo.needsDynamicOffsetBuffer = true;
			}
		}
	}

	for (auto& ctxSI : shaderConfig.shaderInputs) {
		if (ctxSI.shaderVar.builtin != spv::BuiltInMax) {
			ctxSI.outIsUsedByShader = pMSLCompiler->has_active_builtin(ctxSI.shaderVar.builtin, spv::StorageClassInput);
		} else {
			ctxSI.outIsUsedByShader = pMSLCompiler->is_msl_shader_input_used(ctxSI.shaderVar.location);
		}
	}
	for (auto& ctxSO : shaderConfig.shaderOutputs) {
		if (ctxSO.shaderVar.builtin != spv::BuiltInMax) {
			ctxSO.outIsUsedByShader = pMSLCompiler->has_active_builtin(ctxSO.shaderVar.builtin, spv::StorageClassOutput);
		} else {
			ctxSO.outIsUsedByShader = pMSLCompiler->is_msl_shader_output_used(ctxSO.shaderVar.location);
		}
	}
	for (auto& ctxRB : shaderConfig.resourceBindings) {
		if (ctxRB.resourceBinding.stage == shaderConfig.options.entryPointStage) {
			ctxRB.outIsUsedByShader = pMSLCompiler->is_msl_resource_binding_used(ctxRB.resourceBinding.stage,
																				 ctxRB.resourceBinding.desc_set,
																				 ctxRB.resourceBinding.binding);
		}
	}

	delete pMSLCompiler;

    // To check GLSL conversion
    if (shouldLogGLSL) {
		CompilerGLSL* pGLSLCompiler = nullptr;

#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
		try {
#endif
			pGLSLCompiler = new CompilerGLSL(_spirv);
			auto options = pGLSLCompiler->get_common_options();
			options.vulkan_semantics = true;
			options.separate_shader_objects = true;
			pGLSLCompiler->set_common_options(options);
			string glsl = pGLSLCompiler->compile();
            logSource(conversionResult.resultLog, glsl, "GLSL", "Estimated original");
#ifndef SPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS
        } catch (CompilerError& ex) {
            string errMsg("Original GLSL extraction error: ");
            errMsg += ex.what();
            logMsg(conversionResult.resultLog, errMsg.data());
			if (pGLSLCompiler) {
				string glsl = pGLSLCompiler->get_partial_source();
				logSource(conversionResult.resultLog, glsl, "GLSL", "Partially converted");
			}
        }
#endif
		delete pGLSLCompiler;
	}

	return wasConverted;
}

// Appends the message text to the result log.
void SPIRVToMSLConverter::logMsg(string& log, const char* logMsg) {
	string trimMsg = trim(logMsg);
	if ( !trimMsg.empty() ) {
		log += trimMsg;
		log += "\n\n";
	}
}

// Appends the error text to the result log, and returns false to indicate an error.
bool SPIRVToMSLConverter::logError(string& log, const char* errMsg) {
	logMsg(log, errMsg);
	fprintf(stderr, "[mvk-error] %s\n", errMsg);
	return false;
}

// Appends the SPIR-V to the result log, indicating whether it is being converted or was converted.
void SPIRVToMSLConverter::logSPIRV(string& log, const char* opDesc) {

	log += opDesc;
	log += " SPIR-V:\n";
	mvk::logSPIRV(_spirv, log);
	log += "\nEnd SPIR-V\n\n";

	// Uncomment one or both of the following lines to get additional debugging and tracability capabilities.
	// The SPIR-V can be written in binary form to a file, and/or logged in human readable form to the console.
	// These can be helpful if errors occur during conversion of SPIR-V to MSL.
//	writeSPIRVToFile("spvout.spv", log);
//	printf("\n%s\n", log.c_str());
}

// Writes the SPIR-V code to a file. This can be useful for debugging
// when the SPRIR-V did not originally come from a known file
void SPIRVToMSLConverter::writeSPIRVToFile(string spvFilepath, string& log) {
	vector<char> fileContents;
	spirvToBytes(_spirv, fileContents);
	string errMsg;
	if (writeFile(spvFilepath, fileContents, errMsg)) {
		log += "Saved SPIR-V to file: " + absolutePath(spvFilepath) + "\n\n";
	} else {
		log += "Could not write SPIR-V file. " + errMsg + "\n\n";
	}
}

// Validates that the SPIR-V code will disassemble during logging.
bool SPIRVToMSLConverter::validateSPIRV() {
	if (_spirv.size() < 5) { return false; }
	if (_spirv[0] != MagicNumber) { return false; }
	if (_spirv[4] != 0) { return false; }
	return true;
}

// Appends the source to the result log, prepending with the operation.
void SPIRVToMSLConverter::logSource(string& log, string& src, const char* srcLang, const char* opDesc) {
    log += opDesc;
    log += " ";
    log += srcLang;
    log += ":\n";
    log += src;
    log += "\nEnd ";
    log += srcLang;
    log += "\n\n";
}

// Extracts the workgroup dimension from either the LocalSizeId, LocalSize, or WorkgroupSize Builtin.
// Although LocalSizeId is the modern mechanism, the Builtin takes precedence if it is present.
static void getWorkgroupSize(Compiler* pCompiler, SPIREntryPoint& spvEP, uint32_t& x, uint32_t& y, uint32_t& z) {
	auto& wgSz = spvEP.workgroup_size;
	if (spvEP.flags.get(ExecutionModeLocalSizeId) && !wgSz.constant) {
		x = wgSz.id_x ? pCompiler->get_constant(wgSz.id_x).scalar() : 0;
		y = wgSz.id_y ? pCompiler->get_constant(wgSz.id_y).scalar() : 0;
		z = wgSz.id_z ? pCompiler->get_constant(wgSz.id_z).scalar() : 0;
	} else {
		x = wgSz.x;
		y = wgSz.y;
		z = wgSz.z;
	}
}

void SPIRVToMSLConverter::populateWorkgroupDimension(SPIRVWorkgroupSizeDimension& wgDim,
													 uint32_t size,
													 SpecializationConstant& spvSpecConst) {
	wgDim.size = max(size, 1u);
	wgDim.isSpecialized = (uint32_t(spvSpecConst.id) != 0);
	wgDim.specializationID = spvSpecConst.constant_id;
}

// Populates the entry point with info extracted from the SPRI-V compiler.
void SPIRVToMSLConverter::populateEntryPoint(CompilerMSL* pMSLCompiler,
											 SPIRVToMSLConversionOptions& options,
											 SPIRVEntryPoint& entryPoint) {

	if ( !pMSLCompiler ) { return; }

	SPIREntryPoint spvEP;
	if (options.hasEntryPoint()) {
		spvEP = pMSLCompiler->get_entry_point(getMSLEntryPointName(options), options.entryPointStage);
	} else {
		const auto& entryPoints = pMSLCompiler->get_entry_points_and_stages();
		if ( !entryPoints.empty() ) {
			auto& ep = entryPoints[0];
			spvEP = pMSLCompiler->get_entry_point(ep.name, ep.execution_model);
		}
	}

	entryPoint.mtlFunctionName = spvEP.name;
	entryPoint.fpFastMathFlags = pMSLCompiler->get_fp_fast_math_flags(true);

	uint32_t x, y, z;
	getWorkgroupSize(pMSLCompiler, spvEP, x, y, z);

	SpecializationConstant widthSC, heightSC, depthSC;
	pMSLCompiler->get_work_group_size_specialization_constants(widthSC, heightSC, depthSC);

	auto& wgSize = entryPoint.workgroupSize;
	populateWorkgroupDimension(wgSize.width,  x, widthSC);
	populateWorkgroupDimension(wgSize.height, y, heightSC);
	populateWorkgroupDimension(wgSize.depth,  z, depthSC);
}

bool SPIRVToMSLConverter::usesPhysicalStorageBufferAddressesCapability(Compiler* pCompiler) {
	if (pCompiler) {
		auto& declaredCapabilities = pCompiler->get_declared_capabilities();
		for(auto dc: declaredCapabilities) {
			if (dc == CapabilityPhysicalStorageBufferAddresses) {
				return true;
			}
		}
	}
	for (size_t idx = 5; idx < _spirv.size();) {
		uint32_t wordCount = _spirv[idx] >> 16;
		if ((_spirv[idx] & 0xffffu) == OpConvertUToAccelerationStructureKHR) { return true; }
		if (!wordCount || idx + wordCount > _spirv.size()) { break; }
		idx += wordCount;
	}
	return false;
}

void SPIRVToMSLConverter::populateSpecializationMacros(CompilerMSL* pMSLCompiler,
													   map<uint32_t, MSLSpecializationMacroInfo>& specializationMacros)
{
	if (pMSLCompiler) {
		auto spec_consts = pMSLCompiler->get_specialization_constants();
		for (auto& c: spec_consts) {
			uint32_t id = c.constant_id;
			if (pMSLCompiler->specialization_constant_is_macro(id)) {
				const SPIRConstant& constant = pMSLCompiler->get_constant(c.id);
				const SPIRType& type = pMSLCompiler->get_type(constant.constant_type);
				MSLSpecializationMacroInfo info;

				switch (type.basetype) {
					case SPIRType::SByte:
					case SPIRType::Short:
					case SPIRType::Int:
					case SPIRType::Int64:
						info.isFloat = false;
						info.isSigned = true;
						break;
					case SPIRType::UByte:
					case SPIRType::UShort:
					case SPIRType::UInt:
					case SPIRType::UInt64:
					case SPIRType::Boolean:
						info.isFloat = false;
						info.isSigned = false;
						break;
					case SPIRType::Half:
					case SPIRType::Float:
					case SPIRType::Double:
						info.isFloat = true;
						info.isSigned = false;
						break;
					default:
						continue;  // Ignore unsupported types
				}
				info.name = pMSLCompiler->constant_value_macro_name(id);
				specializationMacros[id] = info;
			}
		}
	}
}
