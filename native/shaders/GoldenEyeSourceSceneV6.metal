#include <metal_stdlib>

using namespace metal;

// The fields in these structures are the fixed-width value-only V6 lowering
// contract.  The CPU uploads one source vertex buffer and one per-draw record
// through the Metal 4 argument table; no display-list pointer or host object is
// visible to the shader.
struct GoldenEyeSourceSceneV6Vertex {
    float4 position;
    float4 texcoord;
    float4 normal;
    float4 color;
};

struct GoldenEyeSourceSceneV6Draw {
    float4x4 transform;
    float4 primitiveColor;
    float4 environmentColor;
    uint4 cycle0Color;
    uint4 cycle0Alpha;
    uint4 cycle1Color;
    uint4 cycle1Alpha;
    uint4 selectors;
    float4 ambientColor;
    float4 directionalColor;
    float4 directionalDirection;
    float4 reflectionRight;
    float4 reflectionUp;
    float4x4 normalTransform;
    uint4 lightingInfo;
    uint4 textureInfo;
    uint4 textureLevel0;
    uint4 textureLevel1;
    uint4 textureLevel2;
    uint4 textureLevel3;
    uint4 textureLevel4;
    uint4 textureLevel5;
    uint4 textureLevel6;
    // x = source fog mode (1 = G_RM_FOG_SHADE_A geometry fog),
    // y/z = signed gSPFogPosition fm/fo bit patterns, w = RGBA8 fog color.
    uint4 fogInfo;
    // x = presentation treatment, y = profile, z = LOD bias, w = profile gain.
    float4 presentationInfo;
};

struct GoldenEyeSourceSceneV6Varyings {
    float4 position [[position]];
    float2 texcoord;
    float fogCoordinate [[center_no_perspective]];
    float4 color;
    float4 ambientColor;
    float4 normal;
    float4 primitiveColor;
    float4 environmentColor;
    uint4 cycle0Color [[flat]];
    uint4 cycle0Alpha [[flat]];
    uint4 cycle1Color [[flat]];
    uint4 cycle1Alpha [[flat]];
    uint4 selectors [[flat]];
    uint4 lightingInfo [[flat]];
    uint4 textureInfo [[flat]];
    uint4 textureLevel0 [[flat]];
    uint4 textureLevel1 [[flat]];
    uint4 textureLevel2 [[flat]];
    uint4 textureLevel3 [[flat]];
    uint4 textureLevel4 [[flat]];
    uint4 textureLevel5 [[flat]];
    uint4 textureLevel6 [[flat]];
    uint4 fogInfo [[flat]];
    float4 presentationInfo [[flat]];
};

// OtherMode.H bit 19 selects the source texture-perspective mode. Keep both
// interpolation contracts in the metallib and choose the entry point from
// the exact source pipeline key rather than silently approximating one mode.
struct GoldenEyeSourceSceneV6NoPerspectiveVaryings {
    float4 position [[position]];
    float2 texcoord [[center_no_perspective]];
    float fogCoordinate [[center_no_perspective]];
    float4 color;
    float4 ambientColor;
    float4 normal;
    float4 primitiveColor;
    float4 environmentColor;
    uint4 cycle0Color [[flat]];
    uint4 cycle0Alpha [[flat]];
    uint4 cycle1Color [[flat]];
    uint4 cycle1Alpha [[flat]];
    uint4 selectors [[flat]];
    uint4 lightingInfo [[flat]];
    uint4 textureInfo [[flat]];
    uint4 textureLevel0 [[flat]];
    uint4 textureLevel1 [[flat]];
    uint4 textureLevel2 [[flat]];
    uint4 textureLevel3 [[flat]];
    uint4 textureLevel4 [[flat]];
    uint4 textureLevel5 [[flat]];
    uint4 textureLevel6 [[flat]];
    uint4 fogInfo [[flat]];
    float4 presentationInfo [[flat]];
};

#define GOLDENEYE_SOURCE_SCENE_GEOMETRY_LIGHTING 0x00020000u
#define GOLDENEYE_SOURCE_SCENE_GEOMETRY_TEXTURE_GEN 0x00040000u
#define GOLDENEYE_SOURCE_SCENE_GEOMETRY_TEXTURE_GEN_LINEAR 0x00080000u
#define GOLDENEYE_SOURCE_SCENE_LIGHTING_FLAG (1u << 0)
#define GOLDENEYE_SOURCE_SCENE_TEXGEN_FLAG (1u << 1)
#define GOLDENEYE_SOURCE_SCENE_TEXGEN_LINEAR_FLAG (1u << 2)

static float3 goldeneye_source_scene_v6_normal(
    float4 sourceNormal,
    float4x4 normalTransform)
{
    // The fourth texture lane carries an optional source fog coordinate. It
    // is metadata, not a homogeneous normal component.
    const float3 transformed = (normalTransform * float4(sourceNormal.xyz, 0.0f)).xyz;
    const float lengthSquared = dot(transformed, transformed);
    if (!isfinite(lengthSquared) || lengthSquared <= 0.0000001f) {
        return float3(0.0f, 0.0f, 1.0f);
    }
    return normalize(transformed);
}

static float2 goldeneye_source_scene_v6_texgen(
    float3 normal,
    float4 reflectionRight,
    float4 reflectionUp)
{
    // guLookAtReflect writes the source right/up reflection vectors as signed
    // fractional bytes. The CPU expands those copied q7 values to unit
    // vectors; no screen identity is baked into this shader.
    const float3 right = normalize(reflectionRight.xyz);
    const float3 up = normalize(reflectionUp.xyz);
    const float2 projected = float2(dot(normal, right), dot(normal, up));
    // The regular reflection mode uses the source's centered [0,1] lookup
    // domain. Linear texgen is intentionally rejected by the CPU/provider
    // until its exact angular mapping is available.
    return projected * 0.5f + 0.5f;
}

vertex GoldenEyeSourceSceneV6Varyings goldeneye_source_scene_v6_vertex(
    uint vertexID [[vertex_id]],
    device const GoldenEyeSourceSceneV6Vertex *vertices [[buffer(0)]],
    constant GoldenEyeSourceSceneV6Draw &draw [[buffer(1)]])
{
    const GoldenEyeSourceSceneV6Vertex sourceVertex = vertices[vertexID];
    const uint lightingFlags = draw.lightingInfo.y;
    const bool lightingEnabled = (lightingFlags & GOLDENEYE_SOURCE_SCENE_LIGHTING_FLAG) != 0u;
    const bool texgenEnabled = (lightingFlags & GOLDENEYE_SOURCE_SCENE_TEXGEN_FLAG) != 0u;
    const float3 normal = goldeneye_source_scene_v6_normal(
        sourceVertex.normal,
        draw.normalTransform
    );
    float4 shade = sourceVertex.color;
    if (lightingEnabled) {
        const float3 rawLightDirection = draw.directionalDirection.xyz;
        const float lightLengthSquared = dot(rawLightDirection, rawLightDirection);
        const float3 lightDirection = lightLengthSquared > 0.0000001f
            ? normalize(rawLightDirection) : float3(0.0f);
        const float diffuse = lightLengthSquared > 0.0000001f
            ? max(dot(normal, lightDirection), 0.0f) : 0.0f;
        shade = float4(
            saturate(draw.ambientColor.rgb + draw.directionalColor.rgb * diffuse),
            sourceVertex.color.a
        );
    }
    float2 texcoord = sourceVertex.texcoord.xy;
    if (texgenEnabled) {
        texcoord = goldeneye_source_scene_v6_texgen(
            normal,
            draw.reflectionRight,
            draw.reflectionUp
        );
    }
    GoldenEyeSourceSceneV6Varyings output;
    output.position = draw.transform * sourceVertex.position;
    output.texcoord = texcoord;
    output.fogCoordinate = sourceVertex.texcoord.w;
    output.color = shade;
    output.ambientColor = draw.ambientColor;
    output.normal = float4(normal, 0.0f);
    output.primitiveColor = draw.primitiveColor;
    output.environmentColor = draw.environmentColor;
    output.cycle0Color = draw.cycle0Color;
    output.cycle0Alpha = draw.cycle0Alpha;
    output.cycle1Color = draw.cycle1Color;
    output.cycle1Alpha = draw.cycle1Alpha;
    output.selectors = draw.selectors;
    output.lightingInfo = draw.lightingInfo;
    output.textureInfo = draw.textureInfo;
    output.textureLevel0 = draw.textureLevel0;
    output.textureLevel1 = draw.textureLevel1;
    output.textureLevel2 = draw.textureLevel2;
    output.textureLevel3 = draw.textureLevel3;
    output.textureLevel4 = draw.textureLevel4;
    output.textureLevel5 = draw.textureLevel5;
    output.textureLevel6 = draw.textureLevel6;
    output.fogInfo = draw.fogInfo;
    output.presentationInfo = draw.presentationInfo;
    return output;
}

vertex GoldenEyeSourceSceneV6NoPerspectiveVaryings goldeneye_source_scene_v6_vertex_no_perspective(
    uint vertexID [[vertex_id]],
    device const GoldenEyeSourceSceneV6Vertex *vertices [[buffer(0)]],
    constant GoldenEyeSourceSceneV6Draw &draw [[buffer(1)]])
{
    const GoldenEyeSourceSceneV6Vertex sourceVertex = vertices[vertexID];
    const uint lightingFlags = draw.lightingInfo.y;
    const bool lightingEnabled = (lightingFlags & GOLDENEYE_SOURCE_SCENE_LIGHTING_FLAG) != 0u;
    const bool texgenEnabled = (lightingFlags & GOLDENEYE_SOURCE_SCENE_TEXGEN_FLAG) != 0u;
    const float3 normal = goldeneye_source_scene_v6_normal(
        sourceVertex.normal,
        draw.normalTransform
    );
    float4 shade = sourceVertex.color;
    if (lightingEnabled) {
        const float3 rawLightDirection = draw.directionalDirection.xyz;
        const float lightLengthSquared = dot(rawLightDirection, rawLightDirection);
        const float3 lightDirection = lightLengthSquared > 0.0000001f
            ? normalize(rawLightDirection) : float3(0.0f);
        const float diffuse = lightLengthSquared > 0.0000001f
            ? max(dot(normal, lightDirection), 0.0f) : 0.0f;
        shade = float4(
            saturate(draw.ambientColor.rgb + draw.directionalColor.rgb * diffuse),
            sourceVertex.color.a
        );
    }
    float2 texcoord = sourceVertex.texcoord.xy;
    if (texgenEnabled) {
        texcoord = goldeneye_source_scene_v6_texgen(
            normal,
            draw.reflectionRight,
            draw.reflectionUp
        );
    }
    GoldenEyeSourceSceneV6NoPerspectiveVaryings output;
    output.position = draw.transform * sourceVertex.position;
    output.texcoord = texcoord;
    output.fogCoordinate = sourceVertex.texcoord.w;
    output.color = shade;
    output.ambientColor = draw.ambientColor;
    // The copied source clip-Z/clip-W fog coordinate travels in the existing
    // fourth texture lane; the historical 64-byte GPU vertex stride remains
    // unchanged.
    output.normal = float4(normal, 0.0f);
    output.primitiveColor = draw.primitiveColor;
    output.environmentColor = draw.environmentColor;
    output.cycle0Color = draw.cycle0Color;
    output.cycle0Alpha = draw.cycle0Alpha;
    output.cycle1Color = draw.cycle1Color;
    output.cycle1Alpha = draw.cycle1Alpha;
    output.selectors = draw.selectors;
    output.lightingInfo = draw.lightingInfo;
    output.textureInfo = draw.textureInfo;
    output.textureLevel0 = draw.textureLevel0;
    output.textureLevel1 = draw.textureLevel1;
    output.textureLevel2 = draw.textureLevel2;
    output.textureLevel3 = draw.textureLevel3;
    output.textureLevel4 = draw.textureLevel4;
    output.textureLevel5 = draw.textureLevel5;
    output.textureLevel6 = draw.textureLevel6;
    output.fogInfo = draw.fogInfo;
    output.presentationInfo = draw.presentationInfo;
    return output;
}

static bool goldeneye_source_scene_v6_supported_rgb(uint selector)
{
    return selector == 0u || selector == 1u || selector == 2u ||
        selector == 3u ||
        selector == 4u || selector == 5u || selector == 6u || selector == 7u ||
        selector == 9u ||
        selector == 15u;
}

static bool goldeneye_source_scene_v6_supported_alpha(uint selector)
{
    return selector == 0u || selector == 1u || selector == 2u ||
        selector == 3u ||
        selector == 4u || selector == 5u || selector == 6u || selector == 7u ||
        selector == 9u ||
        selector == 15u;
}

static float3 goldeneye_source_scene_v6_rgb_source(
    uint selector,
    float4 combined,
    float4 texel0,
    float4 texel1,
    float4 primitive,
    float4 shade,
    float4 environment,
    float lodFraction)
{
    switch (selector) {
    case 0u: return combined.rgb;       // COMBINED
    case 1u: return texel0.rgb;         // TEXEL0
    case 2u: return texel1.rgb;         // TEXEL1 (source mip/tile level)
    case 3u: return primitive.rgb;      // PRIMITIVE
    case 4u: return shade.rgb;          // SHADE
    case 5u: return environment.rgb;    // ENVIRONMENT
    case 6u: return float3(1.0f);       // ONE
    case 7u: return float3(0.0f);        // normalized ZERO
    case 9u: return float3(lodFraction); // source LOD_FRACTION
    case 15u: return float3(combined.a); // COMBINED_ALPHA
    default: return float3(0.0f);       // CPU rejects before encoding
    }
}

static float goldeneye_source_scene_v6_alpha_source(
    uint selector,
    float4 combined,
    float4 texel0,
    float4 texel1,
    float4 primitive,
    float4 shade,
    float4 environment,
    float lodFraction)
{
    switch (selector) {
    case 0u: return combined.a;          // COMBINED
    case 1u: return texel0.a;            // TEXEL0
    case 2u: return texel1.a;             // TEXEL1
    case 3u: return primitive.a;         // PRIMITIVE
    case 4u: return shade.a;             // SHADE
    case 5u: return environment.a;       // ENVIRONMENT
    case 6u: return 1.0f;                // ONE
    case 7u: return 0.0f;                // ZERO
    case 9u: return lodFraction;         // source LOD_FRACTION
    case 15u: return combined.a;         // COMBINED_ALPHA
    default: return 0.0f;                // CPU rejects before encoding
    }
}

static float4 goldeneye_source_scene_v6_cycle(
    uint4 colorSelectors,
    uint4 alphaSelectors,
    float4 combined,
    float4 texel0,
    float4 texel1,
    float4 primitive,
    float4 shade,
    float4 environment,
    float lodFraction)
{
    if (!goldeneye_source_scene_v6_supported_rgb(colorSelectors.x) ||
        !goldeneye_source_scene_v6_supported_rgb(colorSelectors.y) ||
        !goldeneye_source_scene_v6_supported_rgb(colorSelectors.z) ||
        !goldeneye_source_scene_v6_supported_rgb(colorSelectors.w) ||
        !goldeneye_source_scene_v6_supported_alpha(alphaSelectors.x) ||
        !goldeneye_source_scene_v6_supported_alpha(alphaSelectors.y) ||
        !goldeneye_source_scene_v6_supported_alpha(alphaSelectors.z) ||
        !goldeneye_source_scene_v6_supported_alpha(alphaSelectors.w)) {
        discard_fragment();
    }
    float3 colorA = goldeneye_source_scene_v6_rgb_source(
        colorSelectors.x, combined, texel0, texel1, primitive, shade, environment, lodFraction);
    float3 colorB = goldeneye_source_scene_v6_rgb_source(
        colorSelectors.y, combined, texel0, texel1, primitive, shade, environment, lodFraction);
    float3 colorC = goldeneye_source_scene_v6_rgb_source(
        colorSelectors.z, combined, texel0, texel1, primitive, shade, environment, lodFraction);
    float3 colorD = goldeneye_source_scene_v6_rgb_source(
        colorSelectors.w, combined, texel0, texel1, primitive, shade, environment, lodFraction);
    float alphaA = goldeneye_source_scene_v6_alpha_source(
        alphaSelectors.x, combined, texel0, texel1, primitive, shade, environment, lodFraction);
    float alphaB = goldeneye_source_scene_v6_alpha_source(
        alphaSelectors.y, combined, texel0, texel1, primitive, shade, environment, lodFraction);
    float alphaC = goldeneye_source_scene_v6_alpha_source(
        alphaSelectors.z, combined, texel0, texel1, primitive, shade, environment, lodFraction);
    float alphaD = goldeneye_source_scene_v6_alpha_source(
        alphaSelectors.w, combined, texel0, texel1, primitive, shade, environment, lodFraction);
    return float4(
        (colorA - colorB) * colorC + colorD,
        (alphaA - alphaB) * alphaC + alphaD
    );
}

static bool goldeneye_source_scene_v6_uses_texture(
    uint4 cycle0Color,
    uint4 cycle0Alpha,
    uint4 cycle1Color,
    uint4 cycle1Alpha)
{
    return cycle0Color.x == 1u || cycle0Color.y == 1u ||
        cycle0Color.z == 1u || cycle0Color.w == 1u ||
        cycle0Alpha.x == 1u || cycle0Alpha.y == 1u ||
        cycle0Alpha.z == 1u || cycle0Alpha.w == 1u ||
        cycle1Color.x == 1u || cycle1Color.y == 1u ||
        cycle1Color.z == 1u || cycle1Color.w == 1u ||
        cycle1Alpha.x == 1u || cycle1Alpha.y == 1u ||
        cycle1Alpha.z == 1u || cycle1Alpha.w == 1u ||
        cycle0Color.x == 2u || cycle0Color.y == 2u ||
        cycle0Color.z == 2u || cycle0Color.w == 2u ||
        cycle0Alpha.x == 2u || cycle0Alpha.y == 2u ||
        cycle0Alpha.z == 2u || cycle0Alpha.w == 2u ||
        cycle1Color.x == 2u || cycle1Color.y == 2u ||
        cycle1Color.z == 2u || cycle1Color.w == 2u ||
        cycle1Alpha.x == 2u || cycle1Alpha.y == 2u ||
        cycle1Alpha.z == 2u || cycle1Alpha.w == 2u ||
        cycle0Color.x == 9u || cycle0Color.y == 9u ||
        cycle0Color.z == 9u || cycle0Color.w == 9u ||
        cycle0Alpha.x == 9u || cycle0Alpha.y == 9u ||
        cycle0Alpha.z == 9u || cycle0Alpha.w == 9u ||
        cycle1Color.x == 9u || cycle1Color.y == 9u ||
        cycle1Color.z == 9u || cycle1Color.w == 9u ||
        cycle1Alpha.x == 9u || cycle1Alpha.y == 9u ||
        cycle1Alpha.z == 9u || cycle1Alpha.w == 9u;
}

static bool goldeneye_source_scene_v6_uses_lod_fraction(
    uint4 cycle0Color,
    uint4 cycle0Alpha,
    uint4 cycle1Color,
    uint4 cycle1Alpha)
{
    return cycle0Color.x == 9u || cycle0Color.y == 9u ||
        cycle0Color.z == 9u || cycle0Color.w == 9u ||
        cycle0Alpha.x == 9u || cycle0Alpha.y == 9u ||
        cycle0Alpha.z == 9u || cycle0Alpha.w == 9u ||
        cycle1Color.x == 9u || cycle1Color.y == 9u ||
        cycle1Color.z == 9u || cycle1Color.w == 9u ||
        cycle1Alpha.x == 9u || cycle1Alpha.y == 9u ||
        cycle1Alpha.z == 9u || cycle1Alpha.w == 9u;
}

static bool goldeneye_source_scene_v6_uses_texel1(
    uint4 cycle0Color,
    uint4 cycle0Alpha,
    uint4 cycle1Color,
    uint4 cycle1Alpha)
{
    return cycle0Color.x == 2u || cycle0Color.y == 2u ||
        cycle0Color.z == 2u || cycle0Color.w == 2u ||
        cycle0Alpha.x == 2u || cycle0Alpha.y == 2u ||
        cycle0Alpha.z == 2u || cycle0Alpha.w == 2u ||
        cycle1Color.x == 2u || cycle1Color.y == 2u ||
        cycle1Color.z == 2u || cycle1Color.w == 2u ||
        cycle1Alpha.x == 2u || cycle1Alpha.y == 2u ||
        cycle1Alpha.z == 2u || cycle1Alpha.w == 2u;
}

// Source textures are uploaded as a 2D-array whose first authored slices are
// level 0...N. The fixed-width per-draw metadata carries exact dimensions for
// every authored level, including source chains whose tail is not the result of
// Metal's implicit floor-halving rule. Every slice is sampled at physical
// level zero; no sentinel texels or extra native mip allocations are used.
static uint goldeneye_source_scene_v6_level_count(
    uint4 textureInfo)
{
    return min(textureInfo.x, 7u);
}

static float source_address(float value, uint mode)
{
    if (mode == 1u) return fract(value);
    if (mode == 2u) {
        const float whole = floor(value);
        const float fraction = value - whole;
        return (fmod(whole, 2.0f) == 0.0f) ? fraction : 1.0f - fraction;
    }
    return clamp(value, 0.0f, 1.0f);
}

static uint4 goldeneye_source_scene_v6_level_dimensions(
    uint mipLevel,
    uint4 level0,
    uint4 level1,
    uint4 level2,
    uint4 level3,
    uint4 level4,
    uint4 level5,
    uint4 level6)
{
    switch (min(mipLevel, 6u)) {
    case 0u: return level0;
    case 1u: return level1;
    case 2u: return level2;
    case 3u: return level3;
    case 4u: return level4;
    case 5u: return level5;
    default: return level6;
    }
}

static float2 goldeneye_source_scene_v6_level_coord(
    texture2d_array<float> sourceTexture,
    float2 sourceCoord,
    uint mipLevel,
    uint4 textureInfo,
    uint4 textureLevel0,
    uint4 textureLevel1,
    uint4 textureLevel2,
    uint4 textureLevel3,
    uint4 textureLevel4,
    uint4 textureLevel5,
    uint4 textureLevel6)
{
    const uint selectedLevel = min(mipLevel, goldeneye_source_scene_v6_level_count(textureInfo) - 1u);
    const uint4 level = goldeneye_source_scene_v6_level_dimensions(
        selectedLevel, textureLevel0, textureLevel1, textureLevel2, textureLevel3,
        textureLevel4, textureLevel5, textureLevel6);
    const float2 levelDimensions = float2(
        float(level.x), float(level.y)
    );
    const float2 addressedCoord = float2(
        source_address(sourceCoord.x, textureInfo.z),
        source_address(sourceCoord.y, textureInfo.w)
    );
    return addressedCoord * levelDimensions / float2(
        float(sourceTexture.get_width(0)),
        float(sourceTexture.get_height(0))
    );
}

static float4 goldeneye_source_scene_v6_sample_level(
    texture2d_array<float> sourceTexture,
    sampler sourceSampler,
    float2 sourceCoord,
    uint mipLevel,
    uint4 textureInfo,
    uint4 textureLevel0,
    uint4 textureLevel1,
    uint4 textureLevel2,
    uint4 textureLevel3,
    uint4 textureLevel4,
    uint4 textureLevel5,
    uint4 textureLevel6)
{
    const uint levelCount = goldeneye_source_scene_v6_level_count(textureInfo);
    if (levelCount == 0u) discard_fragment();
    const uint selectedLevel = min(mipLevel, levelCount - 1u);
    const float2 levelCoord = goldeneye_source_scene_v6_level_coord(
        sourceTexture, sourceCoord, selectedLevel, textureInfo,
        textureLevel0, textureLevel1, textureLevel2, textureLevel3,
        textureLevel4, textureLevel5, textureLevel6);
    return sourceTexture.sample(
        sourceSampler,
        levelCoord,
        selectedLevel,
        level(0.0f)
    );
}

static float4 goldeneye_source_scene_v6_fragment_body(
    float4 color,
    float4 ambientColor,
    float4 normal,
    float fogCoordinate,
    float4 primitiveColor,
    float4 environmentColor,
    uint4 cycle0Color,
    uint4 cycle0Alpha,
    uint4 cycle1Color,
    uint4 cycle1Alpha,
    uint4 selectors,
    uint4 lightingInfo,
    uint4 fogInfo,
    float4 presentationInfo,
    float4 texel0,
    float4 texel1,
    float lodFraction)
{
    // This is the first real source-material lowering.  The CPU validates the
    // selectors and raw render words before encoding; the shader still guards
    // the copied selectors so a corrupted GPU record discards rather than
    // silently rendering an approximation.
    // lightingInfo carries the copied raw geometry mode and normalized
    // binding flags. A missing LIGHTING/TEXTURE_GEN binding must discard
    // rather than silently becoming an unlit approximation.
    const uint rawGeometryMode = lightingInfo.x;
    const uint lightingFlags = lightingInfo.y;
    if ((rawGeometryMode & GOLDENEYE_SOURCE_SCENE_GEOMETRY_LIGHTING) != 0u &&
        (lightingFlags & GOLDENEYE_SOURCE_SCENE_LIGHTING_FLAG) == 0u) {
        discard_fragment();
    }
    if ((rawGeometryMode & GOLDENEYE_SOURCE_SCENE_GEOMETRY_TEXTURE_GEN) != 0u &&
        (lightingFlags & GOLDENEYE_SOURCE_SCENE_TEXGEN_FLAG) == 0u) {
        discard_fragment();
    }
    if ((rawGeometryMode & GOLDENEYE_SOURCE_SCENE_GEOMETRY_TEXTURE_GEN_LINEAR) != 0u &&
        (lightingFlags & GOLDENEYE_SOURCE_SCENE_TEXGEN_LINEAR_FLAG) == 0u) {
        discard_fragment();
    }
    if ((lightingFlags & GOLDENEYE_SOURCE_SCENE_TEXGEN_LINEAR_FLAG) != 0u) {
        discard_fragment();
    }
    // selectors.z is the copied source-texture availability bit. A no-texture
    // PSO passes zero texels and must discard if a corrupted record selects
    // either TEXEL0 or TEXEL1 rather than silently rendering black.
    bool needsTexture = goldeneye_source_scene_v6_uses_texture(
        cycle0Color, cycle0Alpha, cycle1Color, cycle1Alpha);
    if (needsTexture && selectors.z == 0u) {
        discard_fragment();
    }
    float fogAlpha = 0.0f;
    float3 fogColor = float3(0.0f);
    if (fogInfo.x == 1u) {
        const int fogMultiplier = as_type<int>(fogInfo.y);
        const int fogOffset = as_type<int>(fogInfo.z);
        const float fogValue = fogCoordinate * float(fogMultiplier) + float(fogOffset);
        if (!isfinite(fogValue)) discard_fragment();
        fogAlpha = clamp(fogValue, 0.0f, 255.0f) / 255.0f;
        fogColor = float3(
            float((fogInfo.w >> 24) & 0xffu),
            float((fogInfo.w >> 16) & 0xffu),
            float((fogInfo.w >> 8) & 0xffu)
        ) / 255.0f;
    } else if (fogInfo.x != 0u) {
        // No other source fog blender is represented by this shader. Keep the
        // CPU/provider fail-closed contract meaningful if a malformed record
        // reaches the GPU.
        discard_fragment();
    }

    // G_FOG writes the computed alpha into the source shade register before
    // the combiner runs. Preserve that input as well as the later
    // G_RM_FOG_SHADE_A color blend.
    const float4 shade = fogInfo.x == 1u
        ? float4(color.rgb, fogAlpha)
        : color;
    const float4 primitive = primitiveColor;
    const float4 environment = environmentColor;
    float4 combined = float4(0.0f);
    combined = goldeneye_source_scene_v6_cycle(
        cycle0Color,
        cycle0Alpha,
        combined,
        texel0,
        texel1,
        primitive,
        shade,
        environment,
        lodFraction
    );
    if (selectors.y == 2u) {
        combined = goldeneye_source_scene_v6_cycle(
            cycle1Color,
            cycle1Alpha,
            combined,
            texel0,
            texel1,
            primitive,
            shade,
            environment,
            lodFraction
        );
    } else if (selectors.y != 1u) {
        discard_fragment();
    }

    float4 result = combined;

    // Normal is copied after the source normal transform. Reject non-finite
    // values rather than dropping the field silently if a malformed GPU
    // record reaches the shader.
    if (!all(isfinite(normal))) {
        discard_fragment();
    }

    // Alpha compare is a source render-state selector.  The source threshold
    // is represented by the source's alpha mode until the generic RDP alpha
    // lowerer supplies its exact threshold words.
    if (selectors.x == 1u && result.a < 0.5f) {
        discard_fragment();
    }

    // bg.c patches room render modes to G_RM_FOG_SHADE_A when
    // fogSetRenderFogColor() has enabled G_FOG. The source blender then
    // mixes the copied fog color over the source pixel using the RSP fog
    // alpha. `fogCoordinate` is the copied clip-Z/clip-W coordinate; the
    // signed fm/fo pair is the exact gSPFogPosition register payload.
    if (fogInfo.x == 1u) {
        result.rgb = mix(result.rgb, fogColor, fogAlpha);
    }

    if (presentationInfo.x > 0.5f) {
        const uint profile = uint(presentationInfo.y + 0.5f);
        if (profile == 1u) {
            // Nintendo is an I8 reflectance texture under a source ambient
            // fade. Lift the low silver toe while multiplying the authored
            // ambient back in so the fade still reaches black at its source
            // boundary.
            const float authoredAmbient = max(ambientColor.r, 0.0001f);
            float3 base = clamp(result.rgb / authoredAmbient, 0.0f, 1.0f);
            base = mix(base, pow(max(base, float3(0.0f)), float3(0.72f)), 0.70f);
            base = max(base, float3(0.12f));
            result.rgb = base * authoredAmbient;
        } else if (profile == 2u) {
            // Rareware's source fade is RGB brightness, not model alpha. A
            // bounded max-channel curve improves HD visibility without
            // changing hue, alpha, or the source black endpoint.
            const float maximum = max(max(result.r, result.g), result.b);
            if (maximum > 0.0001f) {
                result.rgb *= pow(maximum, presentationInfo.w) / maximum;
            }
        } else if (profile == 3u) {
            // Cast HD lift preserves white highlights and black while raising
            // the low-mid texture values that otherwise read as translucency.
            const float gain = max(presentationInfo.w, 1.0f);
            result.rgb = (gain * result.rgb) /
                (1.0f + (gain - 1.0f) * result.rgb);
        }
        if ((selectors.w & (1u << 0)) != 0u) {
            result.a = 1.0f;
        }
    } else if ((selectors.w & (1u << 0)) != 0u) {
        // Opaque source draws never carry material alpha into the drawable;
        // coverage/alpha belongs to the explicitly typed raster state.
        result.a = 1.0f;
    }

    return saturate(result);
}

fragment float4 goldeneye_source_scene_v6_fragment_array(
    GoldenEyeSourceSceneV6Varyings input [[stage_in]],
    texture2d_array<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]])
{
    float4 texel0 = goldeneye_source_scene_v6_sample_level(
        sourceTexture, sourceSampler, input.texcoord, 0u,
        input.textureInfo, input.textureLevel0, input.textureLevel1,
        input.textureLevel2, input.textureLevel3, input.textureLevel4,
        input.textureLevel5, input.textureLevel6);
    float4 texel1 = texel0;
    float lodFraction = 0.0f;
    if (goldeneye_source_scene_v6_uses_lod_fraction(
            input.cycle0Color, input.cycle0Alpha,
            input.cycle1Color, input.cycle1Alpha)) {
        const float2 baseSize = float2(
            float(input.textureLevel0.x), float(input.textureLevel0.y)
        );
        const float2 dx = dfdx(input.texcoord * baseSize);
        const float2 dy = dfdy(input.texcoord * baseSize);
        const float rhoSquared = max(dot(dx, dx), dot(dy, dy));
        const float rawLOD = 0.5f * log2(max(rhoSquared, 0.000001f))
            + input.presentationInfo.z;
        const float maxLOD = max(
            0.0f,
            float(goldeneye_source_scene_v6_level_count(input.textureInfo) - 1u)
        );
        const float lod = clamp(rawLOD, 0.0f, maxLOD);
        const float lod0 = floor(lod);
        lodFraction = fract(lod);
        texel0 = goldeneye_source_scene_v6_sample_level(
            sourceTexture, sourceSampler, input.texcoord, uint(lod0),
            input.textureInfo, input.textureLevel0, input.textureLevel1,
            input.textureLevel2, input.textureLevel3, input.textureLevel4,
            input.textureLevel5, input.textureLevel6);
        texel1 = goldeneye_source_scene_v6_sample_level(
            sourceTexture, sourceSampler, input.texcoord,
            uint(min(lod0 + 1.0f, maxLOD)), input.textureInfo,
            input.textureLevel0, input.textureLevel1, input.textureLevel2,
            input.textureLevel3, input.textureLevel4, input.textureLevel5,
            input.textureLevel6);
        // Keep the two authored mip samples distinct.  The copied RDP
        // combiner owns the LOD_FRACTION equation; pre-mixing here would add
        // an extra cross-level filter to Rareware's
        // (TEXEL0-TEXEL0)*LOD_FRACTION+TEXEL0 tuple and visibly blur the logo.
    } else if (goldeneye_source_scene_v6_uses_texel1(
            input.cycle0Color, input.cycle0Alpha,
            input.cycle1Color, input.cycle1Alpha) &&
               goldeneye_source_scene_v6_level_count(input.textureInfo) > 1u) {
        // A typed setup with maxLOD==0 may still select TEXEL1 for a
        // single-level source material.  The N64 tile state aliases that
        // request to level zero; never sample an unresident level one.
        const uint maxLOD = goldeneye_source_scene_v6_level_count(input.textureInfo) - 1u;
        texel1 = goldeneye_source_scene_v6_sample_level(
            sourceTexture, sourceSampler, input.texcoord, min(1u, maxLOD),
            input.textureInfo, input.textureLevel0, input.textureLevel1,
            input.textureLevel2, input.textureLevel3, input.textureLevel4,
            input.textureLevel5, input.textureLevel6);
    }
    return goldeneye_source_scene_v6_fragment_body(
        input.color, input.ambientColor, input.normal, input.fogCoordinate, input.primitiveColor,
        input.environmentColor, input.cycle0Color, input.cycle0Alpha,
        input.cycle1Color, input.cycle1Alpha, input.selectors,
        input.lightingInfo, input.fogInfo, input.presentationInfo,
        texel0, texel1, lodFraction);
}

fragment float4 goldeneye_source_scene_v6_fragment_array_no_perspective(
    GoldenEyeSourceSceneV6NoPerspectiveVaryings input [[stage_in]],
    texture2d_array<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]])
{
    float4 texel0 = goldeneye_source_scene_v6_sample_level(
        sourceTexture, sourceSampler, input.texcoord, 0u,
        input.textureInfo, input.textureLevel0, input.textureLevel1,
        input.textureLevel2, input.textureLevel3, input.textureLevel4,
        input.textureLevel5, input.textureLevel6);
    float4 texel1 = texel0;
    float lodFraction = 0.0f;
    if (goldeneye_source_scene_v6_uses_lod_fraction(
            input.cycle0Color, input.cycle0Alpha,
            input.cycle1Color, input.cycle1Alpha)) {
        const float2 baseSize = float2(
            float(input.textureLevel0.x), float(input.textureLevel0.y)
        );
        const float2 dx = dfdx(input.texcoord * baseSize);
        const float2 dy = dfdy(input.texcoord * baseSize);
        const float rhoSquared = max(dot(dx, dx), dot(dy, dy));
        const float rawLOD = 0.5f * log2(max(rhoSquared, 0.000001f))
            + input.presentationInfo.z;
        const float maxLOD = max(
            0.0f,
            float(goldeneye_source_scene_v6_level_count(input.textureInfo) - 1u)
        );
        const float lod = clamp(rawLOD, 0.0f, maxLOD);
        const float lod0 = floor(lod);
        lodFraction = fract(lod);
        texel0 = goldeneye_source_scene_v6_sample_level(
            sourceTexture, sourceSampler, input.texcoord, uint(lod0),
            input.textureInfo, input.textureLevel0, input.textureLevel1,
            input.textureLevel2, input.textureLevel3, input.textureLevel4,
            input.textureLevel5, input.textureLevel6);
        texel1 = goldeneye_source_scene_v6_sample_level(
            sourceTexture, sourceSampler, input.texcoord,
            uint(min(lod0 + 1.0f, maxLOD)), input.textureInfo,
            input.textureLevel0, input.textureLevel1, input.textureLevel2,
            input.textureLevel3, input.textureLevel4, input.textureLevel5,
            input.textureLevel6);
        // The combiner, rather than this sampler helper, performs the one
        // source-authorized LOD interpolation.
    } else if (goldeneye_source_scene_v6_uses_texel1(
            input.cycle0Color, input.cycle0Alpha,
            input.cycle1Color, input.cycle1Alpha) &&
               goldeneye_source_scene_v6_level_count(input.textureInfo) > 1u) {
        const uint maxLOD = goldeneye_source_scene_v6_level_count(input.textureInfo) - 1u;
        texel1 = goldeneye_source_scene_v6_sample_level(
            sourceTexture, sourceSampler, input.texcoord, min(1u, maxLOD),
            input.textureInfo, input.textureLevel0, input.textureLevel1,
            input.textureLevel2, input.textureLevel3, input.textureLevel4,
            input.textureLevel5, input.textureLevel6);
    }
    return goldeneye_source_scene_v6_fragment_body(
        input.color, input.ambientColor, input.normal, input.fogCoordinate, input.primitiveColor,
        input.environmentColor, input.cycle0Color, input.cycle0Alpha,
        input.cycle1Color, input.cycle1Alpha, input.selectors,
        input.lightingInfo, input.fogInfo, input.presentationInfo,
        texel0, texel1, lodFraction);
}

// Ordinary embedded/power-of-two textures retain the original single 2D
// allocation and hardware mip sampling path. This keeps their established
// source-frame hashes unchanged; only source-authored non-floor chains use the
// array entry points above.
fragment float4 goldeneye_source_scene_v6_fragment(
    GoldenEyeSourceSceneV6Varyings input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]])
{
    float4 texel0 = sourceTexture.sample(sourceSampler, input.texcoord);
    float4 texel1 = texel0;
    float lodFraction = 0.0f;
    if (goldeneye_source_scene_v6_uses_lod_fraction(
            input.cycle0Color, input.cycle0Alpha,
            input.cycle1Color, input.cycle1Alpha)) {
        const float2 baseSize = float2(
            float(sourceTexture.get_width(0)),
            float(sourceTexture.get_height(0))
        );
        const float2 dx = dfdx(input.texcoord * baseSize);
        const float2 dy = dfdy(input.texcoord * baseSize);
        const float rhoSquared = max(dot(dx, dx), dot(dy, dy));
        const float rawLOD = 0.5f * log2(max(rhoSquared, 0.000001f))
            + input.presentationInfo.z;
        const float maxLOD = max(0.0f, float(sourceTexture.get_num_mip_levels() - 1));
        const float lod = clamp(rawLOD, 0.0f, maxLOD);
        const float lod0 = floor(lod);
        lodFraction = fract(lod);
        texel0 = sourceTexture.sample(sourceSampler, input.texcoord, level(lod0));
        texel1 = sourceTexture.sample(
            sourceSampler,
            input.texcoord,
            level(min(lod0 + 1.0f, maxLOD))
        );
        // Keep adjacent source levels available to the copied combiner.  Do
        // not pre-mix them here; otherwise a source PASS/LOD tuple is filtered
        // twice before it reaches the RDP equation.
    } else if (goldeneye_source_scene_v6_uses_texel1(
            input.cycle0Color, input.cycle0Alpha,
            input.cycle1Color, input.cycle1Alpha) &&
               sourceTexture.get_num_mip_levels() > 1) {
        const float maxLOD = max(0.0f, float(sourceTexture.get_num_mip_levels() - 1));
        texel1 = sourceTexture.sample(
            sourceSampler,
            input.texcoord,
            level(min(1.0f, maxLOD))
        );
    }
    return goldeneye_source_scene_v6_fragment_body(
        input.color, input.ambientColor, input.normal, input.fogCoordinate, input.primitiveColor,
        input.environmentColor, input.cycle0Color, input.cycle0Alpha,
        input.cycle1Color, input.cycle1Alpha, input.selectors,
        input.lightingInfo, input.fogInfo, input.presentationInfo,
        texel0, texel1, lodFraction);
}

fragment float4 goldeneye_source_scene_v6_fragment_no_perspective(
    GoldenEyeSourceSceneV6NoPerspectiveVaryings input [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler sourceSampler [[sampler(0)]])
{
    float4 texel0 = sourceTexture.sample(sourceSampler, input.texcoord);
    float4 texel1 = texel0;
    float lodFraction = 0.0f;
    if (goldeneye_source_scene_v6_uses_lod_fraction(
            input.cycle0Color, input.cycle0Alpha,
            input.cycle1Color, input.cycle1Alpha)) {
        const float2 baseSize = float2(
            float(sourceTexture.get_width(0)),
            float(sourceTexture.get_height(0))
        );
        const float2 dx = dfdx(input.texcoord * baseSize);
        const float2 dy = dfdy(input.texcoord * baseSize);
        const float rhoSquared = max(dot(dx, dx), dot(dy, dy));
        const float rawLOD = 0.5f * log2(max(rhoSquared, 0.000001f))
            + input.presentationInfo.z;
        const float maxLOD = max(0.0f, float(sourceTexture.get_num_mip_levels() - 1));
        const float lod = clamp(rawLOD, 0.0f, maxLOD);
        const float lod0 = floor(lod);
        lodFraction = fract(lod);
        texel0 = sourceTexture.sample(sourceSampler, input.texcoord, level(lod0));
        texel1 = sourceTexture.sample(
            sourceSampler,
            input.texcoord,
            level(min(lod0 + 1.0f, maxLOD))
        );
        // LOD_FRACTION is consumed by the source combiner, not by this
        // sampler helper.
    } else if (goldeneye_source_scene_v6_uses_texel1(
            input.cycle0Color, input.cycle0Alpha,
            input.cycle1Color, input.cycle1Alpha) &&
               sourceTexture.get_num_mip_levels() > 1) {
        const float maxLOD = max(0.0f, float(sourceTexture.get_num_mip_levels() - 1));
        texel1 = sourceTexture.sample(
            sourceSampler,
            input.texcoord,
            level(min(1.0f, maxLOD))
        );
    }
    return goldeneye_source_scene_v6_fragment_body(
        input.color, input.ambientColor, input.normal, input.fogCoordinate, input.primitiveColor,
        input.environmentColor, input.cycle0Color, input.cycle0Alpha,
        input.cycle1Color, input.cycle1Alpha, input.selectors,
        input.lightingInfo, input.fogInfo, input.presentationInfo,
        texel0, texel1, lodFraction);
}

fragment float4 goldeneye_source_scene_v6_fragment_no_texture(
    GoldenEyeSourceSceneV6Varyings input [[stage_in]])
{
    return goldeneye_source_scene_v6_fragment_body(
        input.color, input.ambientColor, input.normal, input.fogCoordinate, input.primitiveColor,
        input.environmentColor, input.cycle0Color, input.cycle0Alpha,
        input.cycle1Color, input.cycle1Alpha, input.selectors,
        input.lightingInfo,
        input.fogInfo,
        input.presentationInfo,
        float4(0.0f), float4(0.0f), 0.0f);
}

fragment float4 goldeneye_source_scene_v6_fragment_no_texture_no_perspective(
    GoldenEyeSourceSceneV6NoPerspectiveVaryings input [[stage_in]])
{
    return goldeneye_source_scene_v6_fragment_body(
        input.color, input.ambientColor, input.normal, input.fogCoordinate, input.primitiveColor,
        input.environmentColor, input.cycle0Color, input.cycle0Alpha,
        input.cycle1Color, input.cycle1Alpha, input.selectors,
        input.lightingInfo,
        input.fogInfo,
        input.presentationInfo,
        float4(0.0f), float4(0.0f), 0.0f);
}

// Source-owned Gunbarrel non-model passes. The CPU supplies the exact
// 440x299 I8 background and 96x80 decoded blood payload; these functions only
// perform the source row/gradient/offset and compositing math.
struct GoldenEyeGunbarrelPassVertex {
    float2 position;
    float2 uv;
    float4 color;
};

struct GoldenEyeGunbarrelPassUniforms {
    uint kind;
    uint mode;
    int titleXQ16;
    uint fadeAlphaQ8;
    uint bloodFrame;
    uint reserved0;
    float4 reserved1;
};

struct GoldenEyeGunbarrelPassVaryings {
    float4 position [[position]];
    float2 sourcePosition;
    float2 uv;
    float4 color;
};

vertex GoldenEyeGunbarrelPassVaryings goldeneye_gunbarrel_pass_vertex(
    uint vertexID [[vertex_id]],
    device const GoldenEyeGunbarrelPassVertex *vertices [[buffer(0)]],
    constant GoldenEyeGunbarrelPassUniforms &uniforms [[buffer(1)]])
{
    const GoldenEyeGunbarrelPassVertex source = vertices[vertexID];
    // The hole is rasterized procedurally from the logical fullscreen quad.
    // Keeping this source-position domain intact lets the fragment stage clip
    // the 64-unit sight disk explicitly; the old overlapping gSPVertex
    // windows could otherwise escape as a viewport-sized triangle on Metal.
    const float2 sourcePosition = source.position;
    const float2 ndc = float2(
        sourcePosition.x / 440.0f * 2.0f - 1.0f,
        1.0f - sourcePosition.y / 330.0f * 2.0f
    );
    GoldenEyeGunbarrelPassVaryings output;
    output.position = float4(ndc, 0.0f, 1.0f);
    output.sourcePosition = sourcePosition;
    output.uv = source.uv;
    output.color = source.color;
    return output;
}

fragment float4 goldeneye_gunbarrel_pass_fragment(
    GoldenEyeGunbarrelPassVaryings input [[stage_in]],
    constant GoldenEyeGunbarrelPassUniforms &uniforms [[buffer(1)]],
    texture2d<float> payload [[texture(0)]],
    sampler payloadSampler [[sampler(0)]])
{
    if (uniforms.kind == 0u) { // source 440x299 I8 rows + vertical gradient
        // Once the sight reaches its settled phase the source backdrop is
        // presentation-aligned to the same centered logical viewport as the
        // model. Modes 2/3 retain the authored right-to-left travel.
        const float xOffset = (uniforms.mode >= 4u && uniforms.mode <= 7u)
            ? 0.0f
            : float(uniforms.titleXQ16) / 65536.0f * (440.0f / 1280.0f);
        const float sourceX = input.sourcePosition.x - xOffset;
        if (sourceX < 0.0f || sourceX >= 440.0f) {
            return float4(0.0f);
        }
        const float2 uv = float2((sourceX + 0.5f) / 440.0f, input.uv.y);
        const float intensity = payload.sample(payloadSampler, uv).r;
        const float gradient = saturate(input.uv.y);
        return float4(intensity * float3(gradient), 1.0f);
    }
    if (uniforms.kind == 1u) { // source circular sight/hole geometry
        const bool dotSweep = uniforms.mode == 2u;
        const bool settledCenter = uniforms.mode >= 4u && uniforms.mode <= 7u;
        // `g_TitleX` and the authored +768 backdrop offset are in the
        // source 1280-wide orthographic space. Convert the complete
        // translation before entering the 440x330 presentation space.
        const float sourceCenterX = settledCenter
            ? 640.0f
            : (dotSweep ? 0.0f : 768.0f)
                + float(uniforms.titleXQ16) / 65536.0f;
        const float centerX = sourceCenterX * (440.0f / 1280.0f);
        const float centerY = (dotSweep ? 482.0f : (settledCenter ? 480.0f : 442.0f))
            / 960.0f * 330.0f;
        const float radiusX = 64.0f
            * (dotSweep ? 1.0f : 2.7f) / (1280.0f / 440.0f);
        const float radiusY = 64.0f
            * (dotSweep ? 1.0f : 2.57f) / (960.0f / 330.0f);
        const float2 delta = float2(
            (input.sourcePosition.x - centerX) / radiusX,
            (input.sourcePosition.y - centerY) / radiusY
        );
        const float distance = length(delta);
        const float edgeWidth = max(fwidth(distance), 0.0001f);
        if (distance > 1.0f + edgeWidth) {
            discard_fragment();
            // MSL's discard is a side effect rather than a control-flow
            // terminator on every compiler path. Return transparent as well
            // so a conservative backend cannot paint the fullscreen quad
            // black over the authored backdrop.
            return float4(0.0f);
        }
        if (dotSweep) {
            // title.c switches to G_CC_PRIMITIVE/G_RM_AA_OPA_SURF for the
            // sweep.  The generated vertex shade ramp belongs to the later
            // settled sight and must not make the dots look translucent or
            // gradient-filled.  Keep only analytic edge coverage here; the
            // interior is the authored opaque 0xE6 primitive colour.
            const float coverage = clamp(
                (1.0f + edgeWidth - distance) / (2.0f * edgeWidth),
                0.0f,
                1.0f
            );
            return float4(float3(230.0f / 255.0f), coverage);
        }
        // title3.c uses 143 - cos(angle) * -111 with the perimeter's
        // y-coordinate equal to -cos(angle) * 64. This is the exact linear
        // top-to-bottom gradient in the clipped disk.
        const float brightness = clamp(
            (143.0f - 111.0f * delta.y) / 255.0f,
            0.0f,
            1.0f
        );
        return float4(float3(brightness), 1.0f);
    }
    if (uniforms.kind == 2u) { // source I4 blood frame, prim 0x96/0xb4
        const float intensity = payload.sample(payloadSampler, input.uv).r;
        return float4(float3(0.5882353f, 0.0f, 0.0f), intensity * (180.0f / 255.0f));
    }
    if (uniforms.kind == 3u) { // source sub_GAME_7F01CA18 red wash
        const float alpha = float(uniforms.fadeAlphaQ8) / 255.0f;
        return float4(float3(150.0f / 255.0f, 0.0f, 0.0f), alpha);
    }
    if (uniforms.kind == 4u) { // source mode-7 black fade rectangle
        return float4(float3(0.0f), float(uniforms.fadeAlphaQ8) / 255.0f);
    }
    if (uniforms.kind == 5u) { // source mode-8 opaque clear-black rectangle
        return float4(float3(0.0f), 1.0f);
    }
    return float4(0.0f);
}
