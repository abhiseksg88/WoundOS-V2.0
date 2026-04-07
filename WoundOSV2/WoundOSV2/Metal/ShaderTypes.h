#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

typedef struct {
    simd_float3 position;
    simd_float4 color;
    float opacity;
    simd_float3x3 covariance;
} GaussianSplat;

typedef struct {
    simd_float4x4 projectionMatrix;
    simd_float4x4 viewMatrix;
    simd_float2 screenSize;
    uint32_t splatCount;
} GaussianUniforms;

#endif /* ShaderTypes_h */
