#include <metal_stdlib>
using namespace metal;

// This shader is deliberately limited to the one captured ModelType-4
// combiner used by Pammo_crate1Z.  The source setup is
//
//   FC26A004 1F1093FF
//
// (TRILERP followed by MODULATEIA2).  The V3 fixture contains one decoded
// mip per texture, so TEXEL1 is explicitly aliased to TEXEL0 and the LOD
// fraction is fixed at zero.  This preserves the bounded source expression
// without claiming generic RDP/TMEM/mipmap parity.
struct GoldenEyeClassicCombinerPropVertex {
    float4 position;
    float2 texcoord;
    float4 color;
};

struct GoldenEyeClassicCombinerPropTransient {
    uint textureID;
    uint materialFlags;
    uint sourceCommandOffset;
    uint combinerKey;
    uint renderModeKey;
    uint otherModeH;
    uint otherModeL;
    uint combineW0;
    uint combineW1;
    uint combinerFlags;
    uint renderModeFlags;
    uint stateHashLow;
    uint stateHashHigh;
    uint reserved0;
    uint reserved1;
    uint reserved2;
    uint alphaCompare;
    uint alphaPolicy;
    uint alphaThresholdQ8;
    uint fogEnabled;
    uint fogColorRGBA8;
    uint fogAlphaQ8;
    uint coverageFlags;
};

struct GoldenEyeClassicCombinerPropVaryings {
    float4 position [[position]];
    float2 texcoord;
    float4 color;
    uint textureID [[flat]];
    uint sourceCommandOffset [[flat]];
    uint combinerKey [[flat]];
    uint renderModeKey [[flat]];
    uint otherModeH [[flat]];
    uint otherModeL [[flat]];
    uint combineW0 [[flat]];
    uint combineW1 [[flat]];
    uint combinerFlags [[flat]];
    uint renderModeFlags [[flat]];
    uint alphaCompare [[flat]];
    uint alphaPolicy [[flat]];
    uint alphaThresholdQ8 [[flat]];
    uint fogEnabled [[flat]];
    uint fogColorRGBA8 [[flat]];
    uint fogAlphaQ8 [[flat]];
    uint coverageFlags [[flat]];
};

vertex GoldenEyeClassicCombinerPropVaryings goldeneye_classic_combiner_prop_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device const GoldenEyeClassicCombinerPropVertex *vertices [[buffer(0)]],
    device const GoldenEyeClassicCombinerPropTransient *transient [[buffer(2)]])
{
    GoldenEyeClassicCombinerPropVaryings output;
    const GoldenEyeClassicCombinerPropVertex sourceVertex = vertices[vertexID];
    const GoldenEyeClassicCombinerPropTransient draw = transient[instanceID];

    output.position = sourceVertex.position;
    output.texcoord = sourceVertex.texcoord;
    output.color = sourceVertex.color;
    output.textureID = draw.textureID;
    output.sourceCommandOffset = draw.sourceCommandOffset;
    output.combinerKey = draw.combinerKey;
    output.renderModeKey = draw.renderModeKey;
    output.otherModeH = draw.otherModeH;
    output.otherModeL = draw.otherModeL;
    output.combineW0 = draw.combineW0;
    output.combineW1 = draw.combineW1;
    output.combinerFlags = draw.combinerFlags;
    output.renderModeFlags = draw.renderModeFlags;
    output.alphaCompare = draw.alphaCompare;
    output.alphaPolicy = draw.alphaPolicy;
    output.alphaThresholdQ8 = draw.alphaThresholdQ8;
    output.fogEnabled = draw.fogEnabled;
    output.fogColorRGBA8 = draw.fogColorRGBA8;
    output.fogAlphaQ8 = draw.fogAlphaQ8;
    output.coverageFlags = draw.coverageFlags;
    return output;
}

fragment float4 goldeneye_classic_combiner_prop_fragment(
    GoldenEyeClassicCombinerPropVaryings input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]])
{
    constexpr uint expectedCombineW0 = 0xFC26A004u;
    constexpr uint expectedCombineW1 = 0x1F1093FFu;

    // The CPU lowering rejects unsupported words before encoding.  Keep an
    // explicit magenta diagnostic for a corrupted GPU record instead of
    // silently falling back to the old vertex-color material.
    if (input.combineW0 != expectedCombineW0 || input.combineW1 != expectedCombineW1) {
        return float4(1.0f, 0.0f, 1.0f, 1.0f);
    }

    // Source TRILERP cycle:
    //   (TEXEL1 - TEXEL0) * LOD_FRACTION + TEXEL0
    // The one-texture fixture has no TEXEL1 resource or mip fraction, so the
    // alias and zero fraction are intentional, explicit lowering decisions.
    const float4 texel0 = sourceTexture.sample(sourceSampler, input.texcoord);
    const float4 texel1 = texel0;
    constexpr float lodFraction = 0.0f;
    const float4 combined = (texel1 - texel0) * lodFraction + texel0;

    // Source MODULATEIA2 cycle:
    //   COMBINED * SHADE for both color and alpha.
    float4 result = combined * input.color;

    // M9 raster policy: alpha compare and source fog are explicit copied
    // values, rather than silently discarded V4 deferred flags. Dither uses a
    // deterministic 4x4 threshold; threshold mode uses the source-shaped Q8
    // cutoff emitted by the C sidecar.
    if (input.alphaCompare == 1u) {
        if (result.a * 255.0f < float(input.alphaThresholdQ8)) {
            discard_fragment();
        }
    } else if (input.alphaCompare == 3u) {
        constexpr float bayer[4][4] = {
            {0.0f, 8.0f, 2.0f, 10.0f},
            {12.0f, 4.0f, 14.0f, 6.0f},
            {3.0f, 11.0f, 1.0f, 9.0f},
            {15.0f, 7.0f, 13.0f, 5.0f}
        };
        uint2 pixel = uint2(input.position.xy);
        float threshold = (bayer[pixel.y & 3u][pixel.x & 3u] + 0.5f) / 16.0f;
        if (result.a < threshold) {
            discard_fragment();
        }
    }
    if (input.fogEnabled != 0u) {
        float3 fog = float3(
            float((input.fogColorRGBA8 >> 24) & 0xffu),
            float((input.fogColorRGBA8 >> 16) & 0xffu),
            float(input.fogColorRGBA8 & 0xffu)
        ) / 255.0f;
        float fogFactor = float(input.fogAlphaQ8) / 255.0f;
        result.rgb = mix(result.rgb, fog, clamp(fogFactor, 0.0f, 1.0f));
    }

    // Keep the lowered render-mode and key fields observable in a GPU frame.
    const uint stateObservation = input.combinerKey ^ input.renderModeKey ^
        input.otherModeH ^ input.otherModeL ^ input.combinerFlags ^
        input.renderModeFlags ^ input.sourceCommandOffset ^ input.textureID;
    if (stateObservation == 0xFFFFFFFFu) {
        return float4(0.0f, 0.0f, 0.0f, 1.0f);
    }

    return floor(saturate(result) * 255.0f + 0.5f) / 255.0f;
}
