#include <metal_stdlib>
using namespace metal;

// This record mirrors GoldenEyeMetalTitleRenderer.GPUUniforms.  It contains
// only fixed-width values copied from GoldenEyeTitleSnapshot and the supplied
// drawable dimensions; no ROM address, Gfx word, pointer, or Metal object
// crosses the native boundary.
struct GoldenEyeTitleUniforms {
    uint screen;
    uint subphase;
    uint selection;
    uint assetFlags;
    uint timer120;
    uint nativeTickLow;
    uint nativeTickHigh;
    uint reserved0;
    float viewportWidth;
    float viewportHeight;
    float logicalWidth;
    float logicalHeight;
    float titleXQ16;
    float titleRotationQ16;
    float titleScaleQ16;
    float alphaQ16;
    float titleLightQ8;
    float assetWidth;
    float assetHeight;
    float reserved1;
    float reserved2;
};

struct GoldenEyeTitleVaryings {
    float4 position [[position]];
};

struct GoldenEyeTitleGeometryVertex {
    float2 position;
    float4 color;
};

struct GoldenEyeTitleGeometryVaryings {
    float4 position [[position]];
    float4 color;
};

struct GoldenEyeTitleIconVertex {
    float2 position;
    float2 uv;
    float4 color;
};

struct GoldenEyeTitleIconVaryings {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex GoldenEyeTitleVaryings goldeneye_title_vertex(uint vertexID [[vertex_id]])
{
    // Fullscreen triangle; the logical canvas is reconstructed from the
    // fragment position so 4:3 coordinates remain stable on widescreen.
    constexpr float2 vertices[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    GoldenEyeTitleVaryings output;
    output.position = float4(vertices[vertexID], 0.0, 1.0);
    return output;
}

vertex GoldenEyeTitleGeometryVaryings goldeneye_title_geometry_vertex(
    uint vertexID [[vertex_id]],
    constant GoldenEyeTitleUniforms &uniforms [[buffer(0)]],
    device const GoldenEyeTitleGeometryVertex *vertices [[buffer(1)]])
{
    GoldenEyeTitleGeometryVaryings output;
    const GoldenEyeTitleGeometryVertex source = vertices[vertexID];
    // Geometry packets are authored in the canonical 440x330 UI space. Map
    // their clip coordinates through the same uniform letterbox used by the
    // fullscreen title pass so 4:3 remains exact on 16:9/ultrawide displays.
    float2 logical = float2(uniforms.logicalWidth, uniforms.logicalHeight);
    float2 viewport = float2(uniforms.viewportWidth, uniforms.viewportHeight);
    float scale = min(viewport.x / max(logical.x, 1.0), viewport.y / max(logical.y, 1.0));
    float2 origin = (viewport - logical * scale) * 0.5;
    float2 logicalPixel = float2(
        (source.position.x + 1.0) * 0.5 * logical.x,
        (1.0 - source.position.y) * 0.5 * logical.y
    );
    float2 viewportPixel = origin + logicalPixel * scale;
    float2 clip = float2(
        viewportPixel.x / max(viewport.x, 1.0) * 2.0 - 1.0,
        1.0 - viewportPixel.y / max(viewport.y, 1.0) * 2.0
    );
    output.position = float4(clip, 0.0, 1.0);
    output.color = source.color;
    return output;
}

fragment float4 goldeneye_title_geometry_fragment(
    GoldenEyeTitleGeometryVaryings input [[stage_in]])
{
    return floor(saturate(input.color) * 255.0f + 0.5f) / 255.0f;
}

// GETU is a corner-expanded source-material lane.  Positions are already
// normalized to the canonical logical canvas by the Swift loader; this
// shader only applies adaptive letterboxing and samples the resident GETT
// texture selected for the homogeneous triangle group.
struct GoldenEyeTitleUVVertex {
    float2 position;
    float2 uv;
    float4 color;
};

struct GoldenEyeTitleUVVaryings {
    float4 position [[position]];
    float2 uv;
    float4 color;
};

vertex GoldenEyeTitleUVVaryings goldeneye_title_uv_vertex(
    uint vertexID [[vertex_id]],
    constant GoldenEyeTitleUniforms &uniforms [[buffer(0)]],
    device const GoldenEyeTitleUVVertex *vertices [[buffer(1)]])
{
    GoldenEyeTitleUVVaryings output;
    const GoldenEyeTitleUVVertex source = vertices[vertexID];
    float2 logical = float2(uniforms.logicalWidth, uniforms.logicalHeight);
    float2 viewport = float2(uniforms.viewportWidth, uniforms.viewportHeight);
    float scale = min(viewport.x / max(logical.x, 1.0), viewport.y / max(logical.y, 1.0));
    float2 origin = (viewport - logical * scale) * 0.5;
    float2 viewportPixel = origin + source.position * scale;
    float2 clip = float2(
        viewportPixel.x / max(viewport.x, 1.0) * 2.0 - 1.0,
        1.0 - viewportPixel.y / max(viewport.y, 1.0) * 2.0
    );
    output.position = float4(clip, 0.0, 1.0);
    output.uv = clamp(source.uv, 0.0, 1.0);
    output.color = source.color;
    return output;
}

fragment float4 goldeneye_title_uv_fragment(
    GoldenEyeTitleUVVaryings input [[stage_in]],
    texture2d<float> preparedTitleTexture [[texture(0)]],
    sampler titleSampler [[sampler(0)]])
{
    const float4 texel = preparedTitleTexture.sample(titleSampler, input.uv);
    return floor(saturate(texel * input.color) * 255.0f + 0.5f) / 255.0f;
}

vertex GoldenEyeTitleIconVaryings goldeneye_title_icon_vertex(
    uint vertexID [[vertex_id]],
    constant GoldenEyeTitleUniforms &uniforms [[buffer(0)]],
    device const GoldenEyeTitleIconVertex *vertices [[buffer(1)]])
{
    GoldenEyeTitleIconVaryings output;
    const GoldenEyeTitleIconVertex source = vertices[vertexID];
    float2 logical = float2(uniforms.logicalWidth, uniforms.logicalHeight);
    float2 viewport = float2(uniforms.viewportWidth, uniforms.viewportHeight);
    float scale = min(viewport.x / max(logical.x, 1.0), viewport.y / max(logical.y, 1.0));
    float2 origin = (viewport - logical * scale) * 0.5;
    float2 logicalPixel = float2(
        (source.position.x + 1.0) * 0.5 * logical.x,
        (1.0 - source.position.y) * 0.5 * logical.y
    );
    float2 viewportPixel = origin + logicalPixel * scale;
    float2 clip = float2(
        viewportPixel.x / max(viewport.x, 1.0) * 2.0 - 1.0,
        1.0 - viewportPixel.y / max(viewport.y, 1.0) * 2.0
    );
    output.position = float4(clip, 0.0, 1.0);
    output.uv = source.uv;
    output.color = source.color;
    return output;
}

fragment float4 goldeneye_title_icon_fragment(
    GoldenEyeTitleIconVaryings input [[stage_in]],
    texture2d<float> iconTexture [[texture(0)]],
    sampler iconSampler [[sampler(0)]])
{
    const float4 texel = iconTexture.sample(iconSampler, input.uv);
    return floor(saturate(texel * input.color) * 255.0f + 0.5f) / 255.0f;
}

float roundedBox(float2 p, float2 center, float2 halfSize, float radius)
{
    float2 q = abs(p - center) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

float ring(float2 p, float2 center, float radius, float width)
{
    float distance = abs(length(p - center) - radius);
    return 1.0 - smoothstep(width * 0.45, width * 1.55, distance);
}

float line(float value, float start, float end, float width)
{
    return 1.0 - smoothstep(width, width + 1.0, abs(value - clamp(value, start, end)));
}

float blockLetter(float2 p, uint letter, float scale)
{
    // Compact 5x7 masks for the labels used by the frontend placeholder.
    // The masks intentionally communicate screen identity without pretending
    // to be the source font or a decoded model display list.
    constexpr ushort glyphs[26][7] = {
        {14,17,17,31,17,17,17}, {30,17,17,30,17,17,30}, {14,17,16,16,16,17,14},
        {30,17,17,17,17,17,30}, {31,16,16,30,16,16,31}, {31,16,16,30,16,16,16},
        {14,17,16,23,17,17,14}, {17,17,17,31,17,17,17}, {14,4,4,4,4,4,14},
        {7,2,2,2,18,18,12}, {17,18,20,24,20,18,17}, {16,16,16,16,16,16,31},
        {17,27,21,21,17,17,17}, {17,25,21,19,17,17,17}, {14,17,17,17,17,17,14},
        {30,17,17,30,16,16,16}, {14,17,17,17,21,18,13}, {30,17,17,30,20,18,17},
        {15,16,16,14,1,1,30}, {31,4,4,4,4,4,4}, {17,17,17,17,17,17,14},
        {17,17,17,17,17,10,4}, {17,17,17,21,21,21,10}, {17,17,10,4,10,17,17},
        {17,17,10,4,4,4,4}, {31,1,2,4,8,16,31}
    };
    if (letter >= 26) { return 0.0; }
    float2 cell = floor((p / scale) + float2(0.5));
    if (cell.x < 0.0 || cell.x > 4.0 || cell.y < 0.0 || cell.y > 6.0) {
        return 0.0;
    }
    ushort row = glyphs[letter][uint(cell.y)];
    return float((row >> uint(4 - cell.x)) & 1);
}

float labelGoldenEye(float2 p, float2 center, float scale, uint variant)
{
    // Render a small fixed label assembled from the masks above.  `variant`
    // selects one of the source-shaped frontend names while avoiding a text
    // resource dependency in this bounded visual lane.
    constexpr uint words[6][10] = {
        {11,4,6,0,11,0,0,0,0,0},       // LEGAL
        {13,8,13,19,4,13,3,14,0,0},    // NINTENDO
        {17,0,17,4,22,0,17,4,0,0},     // RAREWARE
        {6,14,11,3,4,13,4,24,4,0},     // GOLDENEYE
        {5,8,11,4,18,4,11,4,2,19},     // FILESELECT
        {12,14,3,4,18,4,11,4,2,19}      // MODESELECT
    };
    constexpr uint lengths[6] = {5, 8, 8, 9, 10, 10};
    uint word = min(variant, 5u);
    float glyphWidth = scale * 6.0;
    float2 local = p - center;
    float halfWordWidth = glyphWidth * float(lengths[word]) * 0.5;
    float wordX = local.x + halfWordWidth;
    if (wordX < 0.0 || wordX >= glyphWidth * float(lengths[word])) {
        return 0.0;
    }
    uint index = uint(floor(wordX / glyphWidth));
    float2 glyphPosition = float2(fmod(wordX, glyphWidth) - glyphWidth * 0.5, local.y);
    return blockLetter(glyphPosition, words[word][index], scale);
}

float4 samplePreparedTitleTexture(
    texture2d<float> texture,
    sampler samplerState,
    float2 p,
    float2 center,
    float2 halfExtent)
{
    float2 local = (p - center) / max(halfExtent, float2(1.0));
    if (abs(local.x) > 1.0 || abs(local.y) > 1.0) {
        return float4(0.0);
    }
    float2 uv = clamp(local * 0.5 + 0.5, 0.0, 1.0);
    return texture.sample(samplerState, uv);
}

fragment float4 goldeneye_title_fragment(
    GoldenEyeTitleVaryings input [[stage_in]],
    constant GoldenEyeTitleUniforms &uniforms [[buffer(0)]],
    texture2d<float> preparedBackground [[texture(0)]],
    sampler backgroundSampler [[sampler(0)]])
{
    float2 viewport = float2(uniforms.viewportWidth, uniforms.viewportHeight);
    float2 logical = float2(uniforms.logicalWidth, uniforms.logicalHeight);
    float scale = min(viewport.x / logical.x, viewport.y / logical.y);
    float2 origin = (viewport - logical * scale) * 0.5;
    float2 center = float2(220.0, 165.0);
    float2 p = (input.position.xy - origin) / max(scale, 0.0001);
    if (uniforms.screen == 1u) {
        // The source Nintendo model rotates around Y while its authored
        // scale grows toward 1.1. The bounded title pass uses the same
        // transform in logical 2D space until full model lighting/material
        // lowering is available.
        float angle = uniforms.titleRotationQ16;
        float modelScale = max(uniforms.titleScaleQ16, 0.0001f);
        float2 local = p - center;
        local.x = local.x * cos(angle) * modelScale;
        local.y = local.y * modelScale;
        p = center + local;
    }
    float2 uv = clamp(p / logical, 0.0, 1.0);

    float3 color = float3(0.006, 0.007, 0.010);
    float alpha = clamp(uniforms.alphaQ16, 0.0, 1.0);

    switch (uniforms.screen) {
    case 0u: { // Legal
        color = float3(0.004, 0.005, 0.008);
        float panel = 1.0 - smoothstep(1.0, 2.0, abs(roundedBox(p, center, float2(167, 113), 2)));
        float bars = line(p.y, 70, 75, 1) + line(p.y, 254, 259, 1);
        color += panel * float3(0.12) + bars * float3(0.70, 0.72, 0.76);
        if ((uniforms.assetFlags & 2u) == 0u) {
            float label = labelGoldenEye(p, float2(220, 135), 4.0, 0u);
            color += label * float3(0.88, 0.88, 0.90);
        }
        if ((uniforms.assetFlags & 16u) != 0u) {
            float4 texel = samplePreparedTitleTexture(
                preparedBackground, backgroundSampler, p, center, float2(116.0, 82.0));
            color = mix(color, texel.rgb, texel.a);
        }
        break;
    }
    case 1u: { // Nintendo
        color = float3(0.40, 0.008, 0.012);
        if ((uniforms.assetFlags & 2u) == 0u) {
            float oval = 1.0 - smoothstep(1.0, 3.0, abs(length((p - center) / float2(86, 48)) - 1.0) * 36.0);
            float logo = 1.0 - smoothstep(1.0, 2.0, abs(roundedBox(p, center, float2(64, 14), 7)));
            float light = clamp(uniforms.titleLightQ8, 0.0f, 1.0f);
            color = mix(color, float3(0.96, 0.96, 0.94) * light, oval * 0.5 + logo * 0.5);
            float label = labelGoldenEye(p, float2(220, 165), 5.0, 1u);
            color += label * float3(0.55, 0.02, 0.02);
        }
        if ((uniforms.assetFlags & 16u) != 0u) {
            float4 texel = samplePreparedTitleTexture(
                preparedBackground, backgroundSampler, p, center, float2(104.0, 76.0));
            color = mix(color, texel.rgb, texel.a);
        }
        break;
    }
    case 2u: { // Rareware
        color = mix(float3(0.006, 0.025, 0.10), float3(0.01, 0.20, 0.30), uv.y);
        if ((uniforms.assetFlags & 4u) != 0u) {
            float4 atlas = preparedBackground.sample(backgroundSampler, uv);
            color = mix(color, atlas.rgb, 0.58);
        }
        if ((uniforms.assetFlags & 2u) == 0u) {
            float logo = 1.0 - smoothstep(1.0, 2.5, length((p - center) / float2(92, 38)) - 1.0);
            float eye = ring(p, center, 29.0, 8.0) + ring(p, center, 8.0, 4.0);
            color += logo * float3(0.02, 0.62, 0.52) + eye * float3(0.85, 0.90, 0.65);
            float label = labelGoldenEye(p, float2(220, 165), 4.0, 2u);
            color += label * float3(0.78, 0.90, 0.75);
        }
        break;
    }
    case 3u: { // Gunbarrel / eye intro
        float backgroundY = clamp((p.y - 16.0) / max(uniforms.assetHeight, 1.0), 0.0, 1.0);
        float2 backgroundUV = float2(uv.x, backgroundY);
        float intensity = preparedBackground.sample(backgroundSampler, backgroundUV).r;
        float3 prepared = float3(intensity * 0.64, intensity * 0.68, intensity * 0.74);
        color = ((uniforms.assetFlags & 1u) != 0u) ? prepared : float3(0.035);
        float2 sightCenter = center + float2(uniforms.titleXQ16 * 0.06, 0.0);
        color += ring(p, sightCenter, 52.0, 2.0) * float3(0.82, 0.84, 0.86);
        color += ring(p, sightCenter, 14.0, 2.0) * float3(0.78, 0.80, 0.84);
        color += line(p.x, 0, logical.x, 1.0) * line(p.y, 164, 166, 1.0) * float3(0.75);
        float fade = 1.0 - smoothstep(0.0, 255.0, float(uniforms.timer120 & 255u));
        color *= mix(0.55, 1.0, fade);
        break;
    }
    case 4u: { // GoldenEye logo
        color = float3(0.008, 0.006, 0.002);
        if ((uniforms.assetFlags & 2u) == 0u) {
            float goldBar = 1.0 - smoothstep(1.0, 4.0, abs(roundedBox(p, center, float2(138, 26), 5)));
            float logo = 1.0 - smoothstep(1.0, 3.0, abs(roundedBox(p, center, float2(98, 9), 3)));
            color += goldBar * float3(0.52, 0.33, 0.06) + logo * float3(0.92, 0.68, 0.16);
            float label = labelGoldenEye(p, float2(220, 165), 5.0, 3u);
            color += label * float3(0.15, 0.08, 0.01);
        }
        if ((uniforms.assetFlags & 16u) != 0u) {
            float4 texel = samplePreparedTitleTexture(
                preparedBackground, backgroundSampler, p, center, float2(126.0, 78.0));
            color = mix(color, texel.rgb, texel.a);
        }
        break;
    }
    case 5u: // File select
    case 6u: { // Mode select
        color = mix(float3(0.008, 0.018, 0.040), float3(0.015, 0.040, 0.060), uv.y);
        uint count = uniforms.screen == 5u ? 4u : 2u;
        for (uint index = 0; index < 4u; ++index) {
            if (index >= count) { continue; }
            float x = 76.0 + float(index) * (uniforms.screen == 5u ? 96.0 : 144.0);
            float selected = index == uniforms.selection ? 1.0 : 0.0;
            float folder = 1.0 - smoothstep(1.0, 3.0, abs(roundedBox(p, float2(x, 168), float2(39, 51), 4)));
            color += folder * mix(float3(0.05, 0.10, 0.15), float3(0.52, 0.34, 0.08), selected);
            float tab = 1.0 - smoothstep(1.0, 2.0, abs(roundedBox(p, float2(x - 18, 116), float2(19, 8), 2)));
            color += tab * mix(float3(0.10, 0.20, 0.28), float3(0.74, 0.52, 0.12), selected);
        }
        float label = labelGoldenEye(p, float2(220, 70), 4.0, uniforms.screen == 5u ? 4u : 5u);
        color += label * float3(0.78, 0.82, 0.86);
        break;
    }
    case 7u: // Cast
        color = float3(0.006);
        color += (1.0 - smoothstep(1.0, 3.0, abs(roundedBox(p, center, float2(70, 100), 4)))) * float3(0.17);
        color += line(p.y, 235, 239, 1.0) * float3(0.50, 0.40, 0.10);
        break;
    default: // RAMROM attract
        color = mix(float3(0.005, 0.025, 0.010), float3(0.01, 0.08, 0.03), uv.y);
        color += line(p.y, 248, 252, 1.0) * float3(0.25, 0.70, 0.32);
        color += line(p.x, 80, 360, 1.0) * line(p.y, 118, 121, 1.0) * float3(0.35, 0.80, 0.42);
        break;
    }

    // Keep the letterbox outside the logical canvas black and quantize the
    // output to the BGRA8 target.  The quantization is diagnostic stability,
    // not a claim of source framebuffer identity.
    bool inside = p.x >= 0.0 && p.x <= logical.x && p.y >= 0.0 && p.y <= logical.y;
    float3 output = inside ? saturate(color) * alpha : float3(0.0);
    return floor(float4(output, 1.0) * 255.0 + 0.5) / 255.0;
}
