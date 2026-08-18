#include <metal_stdlib>
using namespace metal;

// These records intentionally mirror the Swift-side GPU staging records in
// metal_classic_textured_prop_renderer.swift.  They contain no host pointers
// or N64 addresses; all resource selection happens through the Metal 4
// argument table and a bounded per-draw material record.
struct GoldenEyeClassicTexturedPropVertex {
    float4 position;
    float2 texcoord;
    float4 color;
};

struct GoldenEyeClassicTexturedPropTransient {
    uint textureID;
    uint materialFlags;
    uint stateHashLow;
    uint stateHashHigh;
};

struct GoldenEyeClassicTexturedPropVaryings {
    float4 position [[position]];
    float2 texcoord;
    float4 color;
};

vertex GoldenEyeClassicTexturedPropVaryings goldeneye_classic_textured_prop_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device const GoldenEyeClassicTexturedPropVertex *vertices [[buffer(0)]],
    device const GoldenEyeClassicTexturedPropTransient *transient [[buffer(2)]])
{
    GoldenEyeClassicTexturedPropVaryings output;
    const GoldenEyeClassicTexturedPropVertex sourceVertex = vertices[vertexID];
    // Reading the record makes the draw's immutable material/state boundary
    // visible to GPU capture while leaving texture selection to the host's
    // argument-table update immediately before this draw.
    const GoldenEyeClassicTexturedPropTransient draw = transient[instanceID];
    output.position = sourceVertex.position;
    output.texcoord = sourceVertex.texcoord;
    output.color = sourceVertex.color;
    (void)draw;
    return output;
}

fragment float4 goldeneye_classic_textured_prop_fragment(
    GoldenEyeClassicTexturedPropVaryings input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]])
{
    // First textured-material target: explicit TEXEL0 * vertex shade.  This
    // is deliberately narrower than generic RDP combiner lowering and keeps
    // all texture bytes in the fixed-width C decoder/Metal resource path.
    const float4 texel = sourceTexture.sample(sourceSampler, input.texcoord);
    return floor(saturate(texel * input.color) * 255.0f + 0.5f) / 255.0f;
}
