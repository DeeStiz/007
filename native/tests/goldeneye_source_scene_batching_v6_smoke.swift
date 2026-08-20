#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

private func setHeader(_ header: inout GEAbiHeaderV1, size: Int) {
    header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
    header.struct_size = UInt32(size)
}

private func command(
    drawHandle: UInt32,
    firstIndex: UInt32,
    indexCount: UInt32,
    instanceCount: UInt32 = 1,
    renderStateHandle: UInt32 = 7
) -> GESourceDrawCommandV6 {
    var value = GESourceDrawCommandV6()
    setHeader(&value.header, size: MemoryLayout<GESourceDrawCommandV6>.size)
    value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
    value.command_kind = UInt32(GE_SOURCE_DRAW_V6_TRIANGLES)
    value.flags = UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE)
    value.draw_handle = drawHandle
    value.transform_handle = 11
    value.resource_handle = 13
    value.render_state_handle = renderStateHandle
    value.first_vertex = 0
    value.vertex_count = 3
    value.first_index = firstIndex
    value.index_count = indexCount
    value.instance_count = instanceCount
    // These source ordering fields are intentionally unique per command. They
    // remain in the CPU manifest but do not affect the GPU draw because source
    // order is already preserved by the contiguous index range.
    value.sort_key = drawHandle * 3
    value.depth_q16 = Int32(truncatingIfNeeded: drawHandle)
    value.scissor_width = 320
    value.scissor_height = 240
    value.draw_hash = UInt64(drawHandle) * 0x1_0000_0001
    return value
}

private func key(
    pipeline: UInt64,
    transform: UInt32 = 11,
    texture: UInt64 = 13,
    scissorX: Int64 = 0,
    instanceCount: UInt32 = 1
) -> GoldenEyeSourceSceneBatchingKeyV6 {
    GoldenEyeSourceSceneBatchingKeyV6(
        commandKind: UInt32(GE_SOURCE_DRAW_V6_TRIANGLES),
        flags: UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE),
        transformHandle: transform,
        resourceHandle: 13,
        renderStateHandle: 7,
        instanceCount: instanceCount,
        textHandle: 0,
        scissorX: scissorX,
        scissorY: 0,
        scissorWidth: 320,
        scissorHeight: 240,
        sourceRenderStateHash: pipeline,
        pipelineKeyHash: pipeline,
        samplerKeyHash: pipeline ^ 0x55,
        textureBindingHash: texture,
        uniformHash: pipeline ^ 0xaa,
        cullKey: 1,
        depthKey: pipeline ^ 0x101,
        blendKey: pipeline ^ 0x202
    )
}

private func input(
    _ command: GESourceDrawCommandV6,
    commandHash: UInt64,
    key: GoldenEyeSourceSceneBatchingKeyV6
) -> GoldenEyeSourceSceneBatchingInputV6 {
    GoldenEyeSourceSceneBatchingInputV6(command: command, commandHash: commandHash, key: key)
}

private func expectsError(_ body: () throws -> Void) {
    do {
        try body()
        preconditionFailure("expected source-scene batching error")
    } catch {
        // The exact error is asserted by the focused checks below where it is
        // useful; all other malformed-input checks only require fail-closed.
    }
}

@main
struct GoldenEyeSourceSceneBatchingV6Smoke {
    static func main() throws {
        let same = key(pipeline: 0x1111)

        let inputs = [
            input(command(drawHandle: 41, firstIndex: 0, indexCount: 1), commandHash: 0xa1, key: same),
            input(command(drawHandle: 42, firstIndex: 1, indexCount: 2), commandHash: 0xa2, key: same),
            input(command(drawHandle: 43, firstIndex: 3, indexCount: 1), commandHash: 0xa3, key: same)
        ]
        let merged = try GoldenEyeSourceSceneBatchingPlanV6(
            inputs: inputs,
            sourceTriangleCount: 4
        )
        precondition(merged.sourceCommandCount == 3)
        precondition(merged.metalDrawCount == 1)
        precondition(merged.batches == [
            GoldenEyeSourceSceneBatchV6(
                sourceStart: 0,
                sourceCount: 3,
                firstIndex: 0,
                indexCount: 4,
                instanceCount: 1,
                pipelineKeyHash: same.pipelineKeyHash
            )
        ])
        precondition(merged.manifest.map(\.sourceIndex) == [0, 1, 2])
        precondition(merged.manifest.map(\.commandHash) == [0xa1, 0xa2, 0xa3])
        precondition(merged.manifest.map(\.sortKey) == [123, 126, 129])
        precondition(merged.manifest.map(\.depthQ16) == [41, 42, 43])
        precondition(merged.sourceCommandCount > merged.metalDrawCount)
        precondition(merged.sourceManifestHash != 0)
        precondition(merged.batchManifestHash != 0)

        let changedTransform = [
            input(command(drawHandle: 41, firstIndex: 0, indexCount: 1), commandHash: 0xa1, key: same),
            input(command(drawHandle: 42, firstIndex: 1, indexCount: 1), commandHash: 0xa2, key: key(pipeline: 0x1111, transform: 12)),
            input(command(drawHandle: 43, firstIndex: 2, indexCount: 1), commandHash: 0xa3, key: same)
        ]
        let transformPlan = try GoldenEyeSourceSceneBatchingPlanV6(
            inputs: changedTransform,
            sourceTriangleCount: 3
        )
        precondition(transformPlan.metalDrawCount == 3)
        precondition(transformPlan.sourceCommandCount == 3)

        let changedScissor = [
            input(command(drawHandle: 41, firstIndex: 0, indexCount: 1), commandHash: 0xa1, key: same),
            input(command(drawHandle: 42, firstIndex: 1, indexCount: 1), commandHash: 0xa2, key: key(pipeline: 0x1111, scissorX: 1)),
            input(command(drawHandle: 43, firstIndex: 2, indexCount: 1), commandHash: 0xa3, key: same)
        ]
        let scissorPlan = try GoldenEyeSourceSceneBatchingPlanV6(
            inputs: changedScissor,
            sourceTriangleCount: 3
        )
        precondition(scissorPlan.metalDrawCount == 3)

        let nonContiguous = [
            input(command(drawHandle: 41, firstIndex: 0, indexCount: 1), commandHash: 0xa1, key: same),
            input(command(drawHandle: 42, firstIndex: 2, indexCount: 1), commandHash: 0xa2, key: same)
        ]
        let nonContiguousPlan = try GoldenEyeSourceSceneBatchingPlanV6(
            inputs: nonContiguous,
            sourceTriangleCount: 3
        )
        precondition(nonContiguousPlan.metalDrawCount == 2)

        let changedInstance = [
            input(command(drawHandle: 41, firstIndex: 0, indexCount: 1), commandHash: 0xa1, key: same),
            input(command(drawHandle: 42, firstIndex: 1, indexCount: 1, instanceCount: 2), commandHash: 0xa2, key: key(pipeline: 0x1111, instanceCount: 2))
        ]
        let instancePlan = try GoldenEyeSourceSceneBatchingPlanV6(
            inputs: changedInstance,
            sourceTriangleCount: 2
        )
        precondition(instancePlan.metalDrawCount == 2)

        expectsError {
            _ = try GoldenEyeSourceSceneBatchingPlanV6(
                inputs: [input(command(drawHandle: 41, firstIndex: 3, indexCount: 2), commandHash: 1, key: same)],
                sourceTriangleCount: 4
            )
        }
        // The capacity is source triangles, not the flattened UInt32 count.
        // This near-end range would incorrectly pass a 3x-expanded capacity.
        expectsError {
            _ = try GoldenEyeSourceSceneBatchingPlanV6(
                inputs: [input(command(drawHandle: 41, firstIndex: 1, indexCount: 2), commandHash: 1, key: same)],
                sourceTriangleCount: 2
            )
        }
        expectsError {
            _ = try GoldenEyeSourceSceneBatchingPlanV6(
                inputs: [input(command(drawHandle: 41, firstIndex: 0, indexCount: 0), commandHash: 1, key: same)],
                sourceTriangleCount: 0
            )
        }
        var unsupported = command(drawHandle: 44, firstIndex: 0, indexCount: 1)
        unsupported.command_kind = UInt32(GE_SOURCE_DRAW_V6_FILL_RECT)
        expectsError {
            _ = try GoldenEyeSourceSceneBatchingPlanV6(
                inputs: [input(unsupported, commandHash: 1, key: same)],
                sourceTriangleCount: 1
            )
        }

        print("goldeneye_source_scene_batching_v6_smoke: PASS source=3 metal=1 manifest=\(merged.sourceManifestHash) batch=\(merged.batchManifestHash)")
    }
}
