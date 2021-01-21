/*
 * MVKWatermark.mm
 *
 * Copyright (c) 2015-2021 The Brenwill Workshop Ltd. (http://www.brenwill.com)
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


#include "MVKWatermark.h"
#include "MVKOSExtensions.h"
#include "MTLTextureDescriptor+MoltenVK.h"
#include "MVKEnvironment.h"


/** The structure to hold shader uniforms. */
typedef struct {
	float mvpMtx[16];
	MVKWatermarkColor color;
} MVKWatermarkUniforms;


#define kMVKWatermarkUniformBufferIndex				0
#define kMVKWatermarkVertexUniformBufferLength		(sizeof(MVKWatermarkUniforms))

#define kMVKWatermarkVertexContentBufferIndex		1
#define kMVKWatermarkVertexContentBufferLength		(sizeof(float) * 4 * 4)
#define kMVKWatermarkVertexIndexBufferLength		(sizeof(uint16_t) * 6)

#define kMVKWatermarkTextureIndex					0


#pragma mark -
#pragma mark MVKWatermark

void MVKWatermark::setPosition(MVKWatermarkPosition position) {
    if ( (position.x == _position.x) && (position.y == _position.y) ) { return; }
    _position = position;
    markUniformsDirty();
}

void MVKWatermark::setSize(MVKWatermarkSize size) {
    if ( (size.width == _size.width) && (size.height == _size.height) ) { return; }
    _size = size;
    markUniformsDirty();
}

void MVKWatermark::setOpacity(float opacity) {
    if (opacity == _color.a) { return; }
    _color.a = opacity;
    markUniformsDirty();
}

void MVKWatermark::markUniformsDirty() { _isUniformsDirty = true; }

void MVKWatermark::markRenderPipelineStateDirty() {
    [_mtlRenderPipelineState release];
    _mtlRenderPipelineState = nil;
}

id<MTLRenderPipelineState> MVKWatermark::mtlRenderPipelineState() {
    if ( !_mtlRenderPipelineState ) { _mtlRenderPipelineState = newRenderPipelineState(); }	// retained
    return _mtlRenderPipelineState;
}

id<MTLRenderPipelineState> MVKWatermark::newRenderPipelineState() {
    MTLRenderPipelineDescriptor* plDesc = [MTLRenderPipelineDescriptor new];	// temp retained
    plDesc.label = _mtlName;

    plDesc.vertexFunction = _mtlFunctionVertex;
    plDesc.fragmentFunction = _mtlFunctionFragment;

    plDesc.depthAttachmentPixelFormat = _mtlDepthFormat;
    plDesc.stencilAttachmentPixelFormat = _mtlStencilFormat;
    plDesc.sampleCount = _sampleCount;
    plDesc.rasterizationEnabled = true;

    MTLRenderPipelineColorAttachmentDescriptor* colorDesc = plDesc.colorAttachments[0];
    colorDesc.pixelFormat = _mtlColorFormat;
    colorDesc.writeMask = MTLColorWriteMaskAll;
    colorDesc.blendingEnabled = true;
    colorDesc.rgbBlendOperation = MTLBlendOperationAdd;
    colorDesc.alphaBlendOperation = MTLBlendOperationMax;
    colorDesc.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    colorDesc.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    colorDesc.sourceAlphaBlendFactor = MTLBlendFactorOne;
    colorDesc.destinationAlphaBlendFactor = MTLBlendFactorZero;

    MTLVertexDescriptor* vtxDesc = plDesc.vertexDescriptor;

    // Vertex attribute descriptors
    MTLVertexAttributeDescriptorArray* vaDescArray = vtxDesc.attributes;
    MTLVertexAttributeDescriptor* vaDesc;
    NSUInteger vtxStride = 0;

    // Vertex location
    vaDesc = vaDescArray[0];
    vaDesc.format = MTLVertexFormatFloat2;
    vaDesc.bufferIndex = kMVKWatermarkVertexContentBufferIndex;
    vaDesc.offset = vtxStride;
    vtxStride += sizeof(float) * 2;

    // Vertex texture coords
    vaDesc = vaDescArray[1];
    vaDesc.format = MTLVertexFormatFloat2;
    vaDesc.bufferIndex = kMVKWatermarkVertexContentBufferIndex;
    vaDesc.offset = vtxStride;
    vtxStride += sizeof(float) * 2;

    // Vertex attribute buffer.
    MTLVertexBufferLayoutDescriptorArray* vbDescArray = vtxDesc.layouts;
    MTLVertexBufferLayoutDescriptor* vbDesc = vbDescArray[kMVKWatermarkVertexContentBufferIndex];
    vbDesc.stepFunction = MTLVertexStepFunctionPerVertex;
    vbDesc.stepRate = 1;
    vbDesc.stride = vtxStride;

    NSError* err = nil;
    id<MTLRenderPipelineState> rps = [_mtlDevice newRenderPipelineStateWithDescriptor: plDesc error: &err];	// retained
    MVKAssert( !err, "Could not create watermark pipeline state (Error code %li)\n%s", (long)err.code, err.localizedDescription.UTF8String);
	[plDesc release];		// temp released
	return rps;
}


#pragma mark Rendering

void MVKWatermark::render(id<MTLTexture> mtlTexture, id<MTLCommandBuffer> mtlCommandBuffer, double frameInterval) {

    updateRenderState(mtlTexture);

    MTLRenderPassDescriptor* mtlRPDesc = getMTLRenderPassDescriptor();
    MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = mtlRPDesc.colorAttachments[0];
    mtlColorAttDesc.texture = mtlTexture;

    id<MTLRenderCommandEncoder> mtlRendEnc = [mtlCommandBuffer renderCommandEncoderWithDescriptor: mtlRPDesc];
    mtlRendEnc.label = _mtlRendEncName;
    render(mtlRendEnc, frameInterval);
    [mtlRendEnc endEncoding];
}

void MVKWatermark::updateRenderState(id<MTLTexture> mtlTexture) {

    MTLPixelFormat mtlColorFormat = mtlTexture.pixelFormat;
    if (_mtlColorFormat != mtlColorFormat) {
        _mtlColorFormat = mtlColorFormat;
        markRenderPipelineStateDirty();
    }

    MTLPixelFormat mtlDepthFormat = MTLPixelFormatInvalid;
    if (_mtlDepthFormat != mtlDepthFormat) {
        _mtlDepthFormat = mtlDepthFormat;
        markRenderPipelineStateDirty();
    }

    MTLPixelFormat mtlStencilFormat = MTLPixelFormatInvalid;
    if (_mtlStencilFormat != mtlStencilFormat) {
        _mtlStencilFormat = mtlStencilFormat;
        markRenderPipelineStateDirty();
    }

    NSUInteger sampleCount = mtlTexture.sampleCount;
    if (_sampleCount != sampleCount) {
        _sampleCount = sampleCount;
        markRenderPipelineStateDirty();
    }
}

void MVKWatermark::render(id<MTLRenderCommandEncoder> mtlEncoder, double frameInterval) {

    updateUniforms();

    [mtlEncoder pushDebugGroup: _mtlName];

    [mtlEncoder setRenderPipelineState: mtlRenderPipelineState()];
    [mtlEncoder setCullMode: MTLCullModeBack];
    [mtlEncoder setVertexBuffer: _mtlVertexContentBuffer offset: 0 atIndex: kMVKWatermarkVertexContentBufferIndex];
    [mtlEncoder setVertexBuffer: _mtlVertexUniformBuffer offset: 0 atIndex: kMVKWatermarkUniformBufferIndex];
    [mtlEncoder setFragmentTexture: _mtlTexture atIndex: kMVKWatermarkTextureIndex];
    [mtlEncoder setFragmentSamplerState: _mtlSamplerState atIndex: kMVKWatermarkTextureIndex];

    [mtlEncoder drawIndexedPrimitives: MTLPrimitiveTypeTriangle
                        indexCount: 6
                         indexType: MTLIndexTypeUInt16
                       indexBuffer: _mtlVertexIndexBuffer
                 indexBufferOffset: 0];
    
    [mtlEncoder popDebugGroup];
}

/** Updates the shader uniforms structure from the properties of this instance. */
void MVKWatermark::updateUniforms() {
    if ( !_isUniformsDirty ) { return; }

    MVKWatermarkUniforms* pUniforms = (MVKWatermarkUniforms*)_mtlVertexUniformBuffer.contents;

    // Populate the MVP matrix uniform
    // The matrix is specified in clip-space coordinates (-1.0 < v < 1.0 for each axis).
    float* mvpMtx = (float*)&(pUniforms->mvpMtx);
    mvpMtx[0] = _size.width;
    mvpMtx[1] = 0.0;
    mvpMtx[2] = 0.0;
    mvpMtx[3] = 0.0;

    mvpMtx[4] = 0.0;
    mvpMtx[5] = _size.height;
    mvpMtx[6] = 0.0;
    mvpMtx[7] = 0.0;

    mvpMtx[8] = 0.0;
    mvpMtx[9] = 0.0;
    mvpMtx[10] = 1.0;
    mvpMtx[11] = 0.0;

    mvpMtx[12] = _position.x;
    mvpMtx[13] = _position.y;
    mvpMtx[14] = 0.0;
    mvpMtx[15] = 1.0;

    // Populate the opacity uniform
    pUniforms->color = _color;
    
    _isUniformsDirty = false;
}

// Returns a MTLRenderPassDescriptor that can be used to render this watermark.
MTLRenderPassDescriptor* MVKWatermark::getMTLRenderPassDescriptor() {
    if ( !_mtlRenderPassDescriptor ) {
        _mtlRenderPassDescriptor = [[MTLRenderPassDescriptor renderPassDescriptor] retain];		// retained
        MTLRenderPassColorAttachmentDescriptor* mtlColorAttDesc = _mtlRenderPassDescriptor.colorAttachments[0];
        mtlColorAttDesc.loadAction = MTLLoadActionLoad;
        mtlColorAttDesc.storeAction = MTLStoreActionStore;
    }
    return _mtlRenderPassDescriptor;
}


#pragma mark Instance creation

MVKWatermark::MVKWatermark(id<MTLDevice> mtlDevice,
                           unsigned char* textureContent,
                           uint32_t textureWidth,
                           uint32_t textureHeight,
                           MTLPixelFormat textureFormat,
                           NSUInteger textureBytesPerRow,
                           const char* mslSourceCode) : _position(0, 0), _size(1, 1), _color(1, 1, 1, 0.25) {
    _mtlColorFormat = MTLPixelFormatInvalid;
    _mtlDepthFormat = MTLPixelFormatInvalid;
    _mtlStencilFormat = MTLPixelFormatInvalid;
    _sampleCount = 1;
    _mtlName = [@"License Watermark" retain];                           // retained
    _mtlRendEncName = [@"License Watermark RenderEncoder" retain];      // retained
    _isUniformsDirty = true;

    _mtlDevice = [mtlDevice retain];    // retained
    initTexture(textureContent, textureWidth, textureHeight, textureFormat, textureBytesPerRow);
    initShaders(mslSourceCode);
    initBuffers();
    _mtlRenderPipelineState = nil;
    _mtlRenderPassDescriptor = nil;
}

// Initialize the texture to use for rendering the watermark
void MVKWatermark::initTexture(unsigned char* textureContent,
                               uint32_t textureWidth,
                               uint32_t textureHeight,
                               MTLPixelFormat textureFormat,
                               NSUInteger textureBytesPerRow) {

    MTLTextureDescriptor* texDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat: textureFormat
                                                                                       width: textureWidth
                                                                                      height: textureHeight
                                                                                   mipmapped: NO];
    texDesc.usageMVK = MTLTextureUsageShaderRead;
#if MVK_IOS
    texDesc.storageModeMVK = MTLStorageModeShared;
#endif
#if MVK_MACOS
    texDesc.storageModeMVK = MTLStorageModeManaged;
#endif

    _mtlTexture = [_mtlDevice newTextureWithDescriptor: texDesc];		// retained
    [_mtlTexture replaceRegion: MTLRegionMake2D(0, 0, textureWidth, textureHeight)
                   mipmapLevel: 0
                         slice: 0
                     withBytes: textureContent
                   bytesPerRow: textureBytesPerRow
                 bytesPerImage: 0];

    MTLSamplerDescriptor* sampDesc = [MTLSamplerDescriptor new];				// temp retained
    sampDesc.minFilter = MTLSamplerMinMagFilterLinear;
    _mtlSamplerState = [_mtlDevice newSamplerStateWithDescriptor: sampDesc];	// retained
	[sampDesc release];															// temp released
}

// Initialize the shader functions for rendering the watermark
void MVKWatermark::initShaders(const char* mslSourceCode) {
    NSError* err = nil;
	NSString* nsSrc = [[NSString alloc] initWithUTF8String: mslSourceCode];	// temp retained
	id<MTLLibrary> mtlLib = [_mtlDevice newLibraryWithSource: nsSrc
													 options: nil
													   error: &err];		// temp retained
	MVKAssert( !err, "Could not compile watermark shaders (Error code %li):\n%s", (long)err.code, err.localizedDescription.UTF8String);

    _mtlFunctionVertex = [mtlLib newFunctionWithName: @"watermarkVertex"];          // retained
    _mtlFunctionFragment = [mtlLib newFunctionWithName: @"watermarkFragment"];      // retained

	[nsSrc release];	// temp released
	[mtlLib release];	// temp released
}

// Initialize the vertex buffers to use for rendering the watermark
void MVKWatermark::initBuffers() {
    _mtlVertexUniformBuffer = [_mtlDevice newBufferWithLength: kMVKWatermarkVertexUniformBufferLength
                                                     options: MTLResourceOptionCPUCacheModeDefault];	// retained

    _mtlVertexContentBuffer = [_mtlDevice newBufferWithLength: kMVKWatermarkVertexContentBufferLength
                                                     options: MTLResourceOptionCPUCacheModeDefault];	// retained

    float* vtxContents = (float*)_mtlVertexContentBuffer.contents;
    uint32_t idx = 0;

    // Bottom left
    vtxContents[idx++] = -1.0;		// Location X
    vtxContents[idx++] = -1.0;		// Location Y
    vtxContents[idx++] =  0.0;		// TexCoord X
    vtxContents[idx++] =  1.0;		// TexCoord Y

    // Bottom right
    vtxContents[idx++] =  1.0;		// Location X
    vtxContents[idx++] = -1.0;		// Location Y
    vtxContents[idx++] =  1.0;		// TexCoord X
    vtxContents[idx++] =  1.0;		// TexCoord Y

    // Top left
    vtxContents[idx++] = -1.0;		// Location X
    vtxContents[idx++] =  1.0;		// Location Y
    vtxContents[idx++] =  0.0;		// TexCoord X
    vtxContents[idx++] =  0.0;		// TexCoord Y

    // Top right
    vtxContents[idx++] =  1.0;		// Location X
    vtxContents[idx++] =  1.0;		// Location Y
    vtxContents[idx++] =  1.0;		// TexCoord X
    vtxContents[idx++] =  0.0;		// TexCoord Y

    _mtlVertexIndexBuffer = [_mtlDevice newBufferWithLength: kMVKWatermarkVertexIndexBufferLength
                                                   options: MTLResourceOptionCPUCacheModeDefault];	// retained
    uint16_t* vtxIndices = (uint16_t*)_mtlVertexIndexBuffer.contents;
    idx = 0;
    vtxIndices[idx++] = 0;		// First face
    vtxIndices[idx++] = 2;
    vtxIndices[idx++] = 3;
    
    vtxIndices[idx++] = 3;		// Second face
    vtxIndices[idx++] = 1;
    vtxIndices[idx++] = 0;
}

MVKWatermark::~MVKWatermark() {
    [_mtlName release];
    [_mtlRendEncName release];
    [_mtlDevice release];
    [_mtlTexture release];
    [_mtlSamplerState release];
    [_mtlFunctionVertex release];
    [_mtlFunctionFragment release];
    [_mtlRenderPipelineState release];
    [_mtlVertexContentBuffer release];
    [_mtlVertexIndexBuffer release];
    [_mtlVertexUniformBuffer release];
    [_mtlRenderPassDescriptor release];
}


#pragma mark -
#pragma mark MVKWatermarkRandom

static inline uint32_t randomUInt() { return arc4random(); }
static inline uint32_t randomUIntBelow(uint32_t max) { return randomUInt() % max; }
static inline float randomFloat() { return (float)randomUInt() / (float)(1LL << 32); }
static inline double randomFloatBetween(float min, float max) { return min + (randomFloat() * (max - min)); }


void MVKWatermarkRandom::updateRenderState(id<MTLTexture> mtlTexture) {

    MVKWatermark::updateRenderState(mtlTexture);

    // Calculate the size of the watermark as a portion of the size of the framebuffer.
    // The watermark is displayed in clip-space coordinates, with the coordinate origin
    // at the center of the framebuffer, and positive coordinates to the right and up
    // and negative coordinates to the left and down.
    float sideLen = _scale;
    double renderAspect = (double)mtlTexture.width / (double)mtlTexture.height;
    sideLen = MIN(sideLen, sideLen * renderAspect);
    setSize(MVKWatermarkSize(sideLen / renderAspect, sideLen));
}

void MVKWatermarkRandom::render(id<MTLRenderCommandEncoder> mtlEncoder, double frameInterval) {

    // Determine the opacity
    float opacity = _color.a + (_opacityVelocity * frameInterval);
    BOOL isFadedOut = (opacity < _minOpacity);
    if (opacity < _minOpacity) {
        opacity = _minOpacity;
        _opacityVelocity = ABS(_opacityVelocity);
    }
    if (opacity > _maxOpacity) {
        opacity = _maxOpacity;
        _opacityVelocity = -ABS(_opacityVelocity);
    }
    setOpacity(opacity);

    // Determine the position in clip-space coordinates.
    MVKWatermarkPosition newPos = _position;
    switch (_positionMode) {
        case kMVKWatermarkPositionModeTeleport: {
            if (isFadedOut) {
                // Move to a new position somewhere on the screen before fading back in
                newPos.x = randomFloatBetween(-_maxPosition, _maxPosition);
                newPos.y = randomFloatBetween(-_maxPosition, _maxPosition);
            }
            break;
        }
        case kMVKWatermarkPositionModeBounce: {
            // Bounce around the screen, always staying with the screen bounds
            newPos.x = _position.x + (_positionVelocity.x * frameInterval);
            newPos.y = _position.y + (_positionVelocity.y * frameInterval);

            if (newPos.x < -_maxPosition) {
                newPos.x = -_maxPosition;
                _positionVelocity.x = ABS(_positionVelocity.x);
            }
            if (newPos.x > _maxPosition) {
                newPos.x = _maxPosition;
                _positionVelocity.x = -ABS(_positionVelocity.x);
            }
            if (newPos.y < -_maxPosition) {
                newPos.y = -_maxPosition;
                _positionVelocity.y = ABS(_positionVelocity.y);
            }
            if (newPos.y > _maxPosition) {
                newPos.y = _maxPosition;
                _positionVelocity.y = -ABS(_positionVelocity.y);
            }
            break;
        }
    }
    setPosition(newPos);

    MVKWatermark::render(mtlEncoder, frameInterval);
}

MVKWatermarkRandom::MVKWatermarkRandom(id<MTLDevice> mtlDevice,
                                       unsigned char* textureContent,
                                       uint32_t textureWidth,
                                       uint32_t textureHeight,
                                       MTLPixelFormat textureFormat,
                                       NSUInteger textureBytesPerRow,
                                       const char* mslSourceCode) : MVKWatermark(mtlDevice,
                                                                                 textureContent,
                                                                                 textureWidth,
                                                                                 textureHeight,
                                                                                 textureFormat,
                                                                                 textureBytesPerRow,
                                                                                 mslSourceCode), _positionVelocity(0, 0) {
    // Randomly select a position movement mode, but favour bounce mode
    _positionMode = ( (randomUIntBelow(3) == kMVKWatermarkPositionModeTeleport)
                     ? kMVKWatermarkPositionModeTeleport
                     : kMVKWatermarkPositionModeBounce);
    switch (_positionMode) {
        case kMVKWatermarkPositionModeBounce:
            _minOpacity = 0.25;
            _maxOpacity = 0.75;
            break;
        case kMVKWatermarkPositionModeTeleport:
            _minOpacity = 0.0;
            _maxOpacity = 0.75;
            break;
    }
    _opacityVelocity = (_maxOpacity - _minOpacity) / 2.5;
    setOpacity(_minOpacity);

    _scale = 0.2;
    _maxPosition = 1.0 - _scale;
    _positionVelocity = MVKWatermarkPosition(_maxPosition / 3.0, _maxPosition / 4.0);
    setPosition(MVKWatermarkPosition(randomFloatBetween(-_maxPosition, _maxPosition),
                                     randomFloatBetween(-_maxPosition, _maxPosition)));
}

