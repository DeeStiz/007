#include <metal_stdlib>

using namespace metal;

// This shader consumes GoldenEyeStageBackgroundDrawVertex values emitted by
// the additive M27 packet. It draws diagnostic room/portal lines only; source
// room display-list triangles, props, characters, AI, and effects are not
// represented here.
struct GoldenEyeStageBackgroundDrawVertex {
    int clipXQ16;
    int clipYQ16;
    int clipZQ16;
    int clipWQ16;
    uint colorRGBA8;
    uint roomIndex;
    uint flags;
    uint reserved;
};

struct GoldenEyeStageBackgroundVaryings {
    float4 position [[position]];
    float4 color;
};

static float4 decodeRGBA8(uint packed) {
    return float4(
        float((packed >> 24) & 0xffu) / 255.0,
        float((packed >> 16) & 0xffu) / 255.0,
        float((packed >> 8) & 0xffu) / 255.0,
        float(packed & 0xffu) / 255.0
    );
}

vertex GoldenEyeStageBackgroundVaryings goldeneye_stage_background_vertex(
    const device GoldenEyeStageBackgroundDrawVertex *vertices [[buffer(0)]],
    uint vertexID [[vertex_id]])
{
    GoldenEyeStageBackgroundDrawVertex sourceVertex = vertices[vertexID];
    float reciprocalW = 1.0 / max(abs(float(sourceVertex.clipWQ16)) / 65536.0, 0.0000152587890625);
    GoldenEyeStageBackgroundVaryings output;
    output.position = float4(
        (float(sourceVertex.clipXQ16) / 65536.0) * reciprocalW,
        (float(sourceVertex.clipYQ16) / 65536.0) * reciprocalW,
        (float(sourceVertex.clipZQ16) / 65536.0) * reciprocalW,
        1.0
    );
    output.color = decodeRGBA8(sourceVertex.colorRGBA8);
    return output;
}

fragment float4 goldeneye_stage_background_fragment(
    GoldenEyeStageBackgroundVaryings input [[stage_in]])
{
    return input.color;
}
