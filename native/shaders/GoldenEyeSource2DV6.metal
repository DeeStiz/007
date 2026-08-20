#include <metal_stdlib>

using namespace metal;

// The 2D source frame is deliberately a value-only packet.  The host uploads
// these vertices through a shared frame buffer and binds that buffer through
// the Metal 4 argument table; no source pointer, display-list word, or
// Metal object is visible to this shader.
struct GoldenEyeSource2DV6Vertex {
    float2 position;
    float2 uv;
    float4 color;
};

struct GoldenEyeSource2DV6Uniforms {
    float2 outputSize;
    float2 origin;
    float scale;
    float logicalWidth;
    float logicalHeight;
    uint reserved0;
    uint reserved1;
};

struct GoldenEyeSource2DV6Varyings {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

static float2 sourceToClip(
    float2 source,
    constant GoldenEyeSource2DV6Uniforms &uniforms
)
{
    const float2 output = uniforms.origin + source * uniforms.scale;
    const float2 safeSize = max(uniforms.outputSize, float2(1.0f));
    return float2(
        output.x / safeSize.x * 2.0f - 1.0f,
        1.0f - output.y / safeSize.y * 2.0f
    );
}

static GoldenEyeSource2DV6Varyings source2dVertex(
    uint vertexID [[vertex_id]],
    constant GoldenEyeSource2DV6Uniforms &uniforms [[buffer(1)]],
    device const GoldenEyeSource2DV6Vertex *vertices [[buffer(0)]]
)
{
    const GoldenEyeSource2DV6Vertex source = vertices[vertexID];
    GoldenEyeSource2DV6Varyings output;
    output.position = float4(sourceToClip(source.position, uniforms), 0.0f, 1.0f);
    output.uv = source.uv;
    output.color = source.color;
    return output;
}

vertex GoldenEyeSource2DV6Varyings goldeneye_source_2d_v6_fill_vertex(
    uint vertexID [[vertex_id]],
    constant GoldenEyeSource2DV6Uniforms &uniforms [[buffer(1)]],
    device const GoldenEyeSource2DV6Vertex *vertices [[buffer(0)]]
)
{
    return source2dVertex(vertexID, uniforms, vertices);
}

fragment float4 goldeneye_source_2d_v6_fill_fragment(
    GoldenEyeSource2DV6Varyings input [[stage_in]]
)
{
    return floor(saturate(input.color) * 255.0f + 0.5f) / 255.0f;
}

vertex GoldenEyeSource2DV6Varyings goldeneye_source_2d_v6_texture_vertex(
    uint vertexID [[vertex_id]],
    constant GoldenEyeSource2DV6Uniforms &uniforms [[buffer(1)]],
    device const GoldenEyeSource2DV6Vertex *vertices [[buffer(0)]]
)
{
    return source2dVertex(vertexID, uniforms, vertices);
}

fragment float4 goldeneye_source_2d_v6_texture_fragment(
    GoldenEyeSource2DV6Varyings input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]]
)
{
    const float4 texel = sourceTexture.sample(sourceSampler, input.uv);
    return floor(saturate(texel * input.color) * 255.0f + 0.5f) / 255.0f;
}

vertex GoldenEyeSource2DV6Varyings goldeneye_source_2d_v6_glyph_vertex(
    uint vertexID [[vertex_id]],
    constant GoldenEyeSource2DV6Uniforms &uniforms [[buffer(1)]],
    device const GoldenEyeSource2DV6Vertex *vertices [[buffer(0)]]
)
{
    return source2dVertex(vertexID, uniforms, vertices);
}

fragment float4 goldeneye_source_2d_v6_glyph_fragment(
    GoldenEyeSource2DV6Varyings input [[stage_in]],
    texture2d<float> fontAtlas [[texture(0)]],
    sampler fontSampler [[sampler(0)]]
)
{
    // Zurich and Bank Gothic are source I8 glyph atlases.  The sampled red
    // channel is the authored coverage; RGB remains the source glyph color.
    const float coverage = fontAtlas.sample(fontSampler, input.uv).r;
    return floor(saturate(float4(input.color.rgb, input.color.a * coverage)) * 255.0f + 0.5f) / 255.0f;
}
