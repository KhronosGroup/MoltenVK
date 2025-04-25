/*
 * MVKWatermark.h
 *
 * Copyright (c) 2015-2025 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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

#pragma once


#include "MVKBaseObject.h"
#include <string>

#import <Metal/Metal.h>


typedef struct MVKWatermarkPosition {
    float x;
    float y;
    MVKWatermarkPosition(float xVal, float yVal) : x(xVal), y(yVal) {}
} MVKWatermarkPosition;

typedef struct MVKWatermarkSize {
    float width;
    float height;
    MVKWatermarkSize(float w, float h) : width(w), height(h) {}
} MVKWatermarkSize;

typedef struct MVKWatermarkColor {
    float r;
    float g;
    float b;
    float a;
    MVKWatermarkColor(float red, float green, float blue, float alpha) : r(red), g(green), b(blue), a(alpha) {}
} MVKWatermarkColor;


#pragma mark -
#pragma mark MVKWatermark

/**
 * A 2D watermark for display as an overlay on the rendered scene.
 *
 * This class uses Metal directly.
 */
class MVKWatermark : public MVKBaseObject {

public:


	/** Returns the Vulkan API opaque object controlling this object. */
	MVKVulkanAPIObject* getVulkanAPIObject() override { return nullptr; };

    /** Sets the clip-space position (0.0 - 1.0) of this watermark. */
    void setPosition(MVKWatermarkPosition position);

    /** Sets the clip-space size (0.0 - 1.0) of this watermark. */
    void setSize(MVKWatermarkSize size);

    /** Sets the opacity (0.0 - 1.0) of this watermark. */
    void setOpacity(float opacity);

    /** Update the render state prior to rendering to the specified texture. */
    virtual void updateRenderState(id<MTLTexture> mtlTexture);

    /** Render to the specified Metal encoder. */
    virtual void render(id<MTLRenderCommandEncoder> mtlEncoder, double frameInterval);

    /** 
     * Convenience function that calls updateRenderState() to update the render state to 
     * match the specified texture, creates a Metal encoder from the specified Metal 
     * command buffer, and calls render(encoder, interval) to render to the texture.
     */
    void render(id<MTLTexture> mtlTexture, id<MTLCommandBuffer> mtlCommandBuffer, double frameInterval);

    MVKWatermark(id<MTLDevice> mtlDevice,
                 unsigned char* textureContent,
                 uint32_t textureWidth,
                 uint32_t textureHeight,
                 MTLPixelFormat textureFormat,
                 NSUInteger textureBytesPerRow,
                 const char* mtlShaderSource);

    virtual ~MVKWatermark();

protected:
    void initTexture(unsigned char* textureContent,
                     uint32_t textureWidth,
                     uint32_t textureHeight,
                     MTLPixelFormat textureFormat,
                     NSUInteger textureBytesPerRow);
    void initShaders(const char* mslSourceCode);
    void initBuffers();
    void updateUniforms();
    void markUniformsDirty();
    void markRenderPipelineStateDirty();
    id<MTLRenderPipelineState> mtlRenderPipelineState();
    id<MTLRenderPipelineState> newRenderPipelineState();
    MTLRenderPassDescriptor* getMTLRenderPassDescriptor();

    NSString* _mtlName;
    NSString* _mtlRendEncName;
    MVKWatermarkPosition _position;
    MVKWatermarkSize _size;
    MVKWatermarkColor _color;
    id<MTLDevice> _mtlDevice;
    id<MTLTexture> _mtlTexture;
    id<MTLSamplerState> _mtlSamplerState;
    id <MTLFunction> _mtlFunctionVertex;
    id <MTLFunction> _mtlFunctionFragment;
    id<MTLRenderPipelineState> _mtlRenderPipelineState;
    id<MTLBuffer> _mtlVertexContentBuffer;
    id<MTLBuffer> _mtlVertexIndexBuffer;
    id<MTLBuffer> _mtlVertexUniformBuffer;
    MTLRenderPassDescriptor* _mtlRenderPassDescriptor;
    MTLPixelFormat _mtlColorFormat;
    MTLPixelFormat _mtlDepthFormat;
    MTLPixelFormat _mtlStencilFormat;
    NSUInteger _sampleCount;
    bool _isUniformsDirty;
};


#pragma mark -
#pragma mark MVKWatermarkRandom

typedef enum {
    kMVKWatermarkPositionModeBounce,
    kMVKWatermarkPositionModeTeleport,
} MVKWatermarkPositionMode;

/**
 * A 2D watermark displayed in a random location in the rendered scene, and then moves
 * either by smoothly bouncing around the screen or by teleporting. The mode of movement
 * is selected randomly during initialization.
 */
class MVKWatermarkRandom : public MVKWatermark {

public:

    /** Update the render state prior to rendering to the specified texture. */
    void updateRenderState(id<MTLTexture> mtlTexture) override;

    /** Render to the specified Metal encoder. */
    void render(id<MTLRenderCommandEncoder> mtlEncoder, double frameInterval) override;

    MVKWatermarkRandom(id<MTLDevice> mtlDevice,
                       unsigned char* textureContent,
                       uint32_t textureWidth,
                       uint32_t textureHeight,
                       MTLPixelFormat textureFormat,
                       NSUInteger textureBytesPerRow,
                       const char* mtlShaderSource);

protected:
    float _minOpacity;
    float _maxOpacity;
    float _opacityVelocity;
    float _scale;
    float _maxPosition;
    MVKWatermarkPosition _positionVelocity;
    MVKWatermarkPositionMode _positionMode;
};

