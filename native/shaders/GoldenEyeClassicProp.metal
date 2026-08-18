#include <metal_stdlib>
using namespace metal;

struct GoldenEyeClassicPropVertex {
    float4 position;
    float4 color;
};

struct GoldenEyeClassicPropTransient {
    float4 diagnosticTint;
    uint materialFlags;
    uint stateHashLow;
    uint stateHashHigh;
    uint reserved;
};

struct GoldenEyeClassicPropVaryings {
    float4 position [[position]];
    float4 color;
};

vertex GoldenEyeClassicPropVaryings goldeneye_classic_prop_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    device const GoldenEyeClassicPropVertex *vertices [[buffer(0)]],
    device const GoldenEyeClassicPropTransient *transient [[buffer(2)]])
{
    GoldenEyeClassicPropVaryings output;
    const GoldenEyeClassicPropVertex sourceVertex = vertices[vertexID];
    const GoldenEyeClassicPropTransient draw = transient[instanceID];
    output.position = sourceVertex.position;
    // The classic replay records texture/mode state, but this goal renders
    // through an explicit vertex-color diagnostic material.  Keeping the tint
    // in a GPU-address-bound transient record makes that boundary visible in
    // captures without claiming texture or combiner fidelity.
    output.color = sourceVertex.color * draw.diagnosticTint;
    return output;
}

fragment float4 goldeneye_classic_prop_fragment(GoldenEyeClassicPropVaryings input [[stage_in]])
{
    // Match the stable BGRA8 diagnostic output used by the first-frame lane.
    return floor(saturate(input.color) * 255.0f + 0.5f) / 255.0f;
}
