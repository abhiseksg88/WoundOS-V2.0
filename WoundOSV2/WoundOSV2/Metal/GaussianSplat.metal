#include <metal_stdlib>
using namespace metal;

// Placeholder Gaussian Splatting shader — full implementation in Phase 5

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float opacity;
    float pointSize [[point_size]];
};

struct Uniforms {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float2 screenSize;
    uint splatCount;
};

struct SplatData {
    packed_float3 position;
    packed_float4 color;
    float opacity;
};

vertex VertexOut gaussianVertex(
    const device SplatData* splats [[buffer(0)]],
    constant Uniforms& uniforms [[buffer(1)]],
    uint vertexID [[vertex_id]]
) {
    VertexOut out;
    SplatData splat = splats[vertexID];

    float4 worldPos = float4(splat.position[0], splat.position[1], splat.position[2], 1.0);
    float4 viewPos = uniforms.viewMatrix * worldPos;
    out.position = uniforms.projectionMatrix * viewPos;
    out.color = float4(splat.color[0], splat.color[1], splat.color[2], splat.color[3]);
    out.opacity = splat.opacity;
    out.pointSize = max(1.0, 10.0 / (-viewPos.z));

    return out;
}

fragment float4 gaussianFragment(VertexOut in [[stage_in]]) {
    float2 center = float2(0.5, 0.5);
    float dist = length(in.position.xy - center);
    float alpha = in.opacity * exp(-dist * dist * 2.0);
    return float4(in.color.rgb, alpha);
}
