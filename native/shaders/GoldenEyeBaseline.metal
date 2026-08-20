#include <metal_stdlib>
using namespace metal;

struct GoldenEyeBaselineVertex {
    float2 position;
    float4 color;
};

struct GoldenEyeBaselineVaryings {
    float4 position [[position]];
    float4 color;
};

vertex GoldenEyeBaselineVaryings goldeneye_baseline_vertex(
    uint vertexID [[vertex_id]],
    device const GoldenEyeBaselineVertex *vertices [[buffer(0)]])
{
    GoldenEyeBaselineVaryings output;
    output.position = float4(vertices[vertexID].position, 0.0, 1.0);
    output.color = vertices[vertexID].color;
    return output;
}

fragment float4 goldeneye_baseline_fragment(GoldenEyeBaselineVaryings input [[stage_in]])
{
    // Quantize the fixture output before the shared BGRA8 target. This keeps
    // consecutive window captures byte-stable instead of allowing compositor
    // color-management dithering to move an interpolated channel by one code.
    return floor(saturate(input.color) * 255.0f + 0.5f) / 255.0f;
}
