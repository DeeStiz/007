#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

/// A source-scene batch key.  This is deliberately a value-only description
/// of every piece of state which can affect a triangle draw.  Metal object
/// identity is not used as a shortcut: the source/pipeline/texture hashes and
/// the fixed-width state fields must all agree before two source commands can
/// share one indexed draw.
struct GoldenEyeSourceSceneBatchingKeyV6: Hashable {
    let commandKind: UInt32
    let flags: UInt32
    let transformHandle: UInt32
    let resourceHandle: UInt32
    let renderStateHandle: UInt32
    let instanceCount: UInt32
    let textHandle: UInt32
    let scissorX: Int64
    let scissorY: Int64
    let scissorWidth: Int64
    let scissorHeight: Int64
    let sourceRenderStateHash: UInt64
    let pipelineKeyHash: UInt64
    let samplerKeyHash: UInt64
    let textureBindingHash: UInt64
    let uniformHash: UInt64
    let cullKey: UInt32
    let depthKey: UInt64
    let blendKey: UInt64
}

/// One command plus its immutable source manifest entry.  The source command
/// remains present in this array even when the Metal encoder coalesces it with
/// an adjacent command.  This makes the batching optimization auditable and
/// prevents a lower draw count from hiding source-order or source-hash drift.
struct GoldenEyeSourceSceneBatchingInputV6 {
    let command: GESourceDrawCommandV6
    let commandHash: UInt64
    let key: GoldenEyeSourceSceneBatchingKeyV6
}

struct GoldenEyeSourceSceneBatchManifestEntryV6: Equatable {
    let sourceIndex: Int
    let drawHandle: UInt32
    let commandHash: UInt64
    let renderStateHandle: UInt32
    let sourceRenderStateHash: UInt64
    let pipelineKeyHash: UInt64
    let firstVertex: UInt32
    let vertexCount: UInt32
    let sortKey: UInt32
    let depthQ16: Int32
    let firstIndex: UInt32
    let indexCount: UInt32
}

struct GoldenEyeSourceSceneBatchV6: Equatable {
    let sourceStart: Int
    let sourceCount: Int
    let firstIndex: UInt32
    let indexCount: UInt32
    let instanceCount: UInt32
    let pipelineKeyHash: UInt64

    var sourceEnd: Int { sourceStart + sourceCount }
}

enum GoldenEyeSourceSceneBatchingV6Error: Error, CustomStringConvertible, Equatable {
    case commandCountMismatch(expected: Int, actual: Int)
    case commandHashCountMismatch(expected: Int, actual: Int)
    case unsupportedCommand(UInt32, sourceIndex: Int)
    case zeroIndexCount(Int)
    case zeroInstanceCount(Int)
    case indexRangeOverflow(Int)
    case indexRangeOutOfBounds(Int, end: UInt64, capacity: Int)
    case indexCountOverflow(Int)
    case batchCountExceeded(Int)

    var description: String {
        switch self {
        case .commandCountMismatch(let expected, let actual):
            return "V6 batching command count mismatch expected=\(expected) actual=\(actual)"
        case .commandHashCountMismatch(let expected, let actual):
            return "V6 batching command-hash count mismatch expected=\(expected) actual=\(actual)"
        case .unsupportedCommand(let kind, let sourceIndex):
            return "V6 batching unsupported command kind \(kind) at source index \(sourceIndex)"
        case .zeroIndexCount(let sourceIndex):
            return "V6 batching zero index count at source index \(sourceIndex)"
        case .zeroInstanceCount(let sourceIndex):
            return "V6 batching zero instance count at source index \(sourceIndex)"
        case .indexRangeOverflow(let sourceIndex):
            return "V6 batching index range overflow at source index \(sourceIndex)"
        case .indexRangeOutOfBounds(let sourceIndex, let end, let capacity):
            return "V6 batching index range out of bounds at source index \(sourceIndex): end=\(end) capacity=\(capacity)"
        case .indexCountOverflow(let sourceIndex):
            return "V6 batching Metal index count overflow at source index \(sourceIndex)"
        case .batchCountExceeded(let count):
            return "V6 batching batch capacity exceeded: \(count)"
        }
    }
}

/// A deterministic, fail-closed contiguous batch plan for one source frame.
/// The plan only merges commands whose index ranges are adjacent and whose
/// complete render/visibility key is equal.  It never reorders commands,
/// rewrites source indices, or merges across a state boundary.
struct GoldenEyeSourceSceneBatchingPlanV6 {
    let sourceCommandCount: Int
    let metalDrawCount: Int
    let manifest: [GoldenEyeSourceSceneBatchManifestEntryV6]
    let batches: [GoldenEyeSourceSceneBatchV6]
    let sourceManifestHash: UInt64
    let batchManifestHash: UInt64

    static let hashOffset: UInt64 = 1_469_598_103_934_665_603
    static let hashPrime: UInt64 = 1_099_511_628_211

    init(
        inputs: [GoldenEyeSourceSceneBatchingInputV6],
        sourceTriangleCount: Int,
        maxBatchCount: Int = 65_536
    ) throws {
        guard sourceTriangleCount >= 0,
              maxBatchCount > 0 else {
            throw GoldenEyeSourceSceneBatchingV6Error.indexRangeOutOfBounds(
                0,
                end: 0,
                capacity: sourceTriangleCount
            )
        }

        var manifest: [GoldenEyeSourceSceneBatchManifestEntryV6] = []
        manifest.reserveCapacity(inputs.count)
        var batches: [GoldenEyeSourceSceneBatchV6] = []
        batches.reserveCapacity(min(inputs.count, maxBatchCount))

        var sourceHash = Self.hashOffset
        var batchHash = Self.hashOffset

        for (sourceIndex, input) in inputs.enumerated() {
            let command = input.command
            guard command.command_kind == UInt32(GE_SOURCE_DRAW_V6_TRIANGLES) else {
                throw GoldenEyeSourceSceneBatchingV6Error.unsupportedCommand(
                    command.command_kind,
                    sourceIndex: sourceIndex
                )
            }
            guard command.index_count > 0 else {
                throw GoldenEyeSourceSceneBatchingV6Error.zeroIndexCount(sourceIndex)
            }
            guard command.instance_count > 0 else {
                throw GoldenEyeSourceSceneBatchingV6Error.zeroInstanceCount(sourceIndex)
            }

            let end = UInt64(command.first_index) + UInt64(command.index_count)
            guard end >= UInt64(command.first_index) else {
                throw GoldenEyeSourceSceneBatchingV6Error.indexRangeOverflow(sourceIndex)
            }
            guard end <= UInt64(sourceTriangleCount) else {
                throw GoldenEyeSourceSceneBatchingV6Error.indexRangeOutOfBounds(
                    sourceIndex,
                    end: end,
                    capacity: sourceTriangleCount
                )
            }
            // The source command range is measured in triangle records. The
            // renderer expands each record to three UInt32 vertices when it
            // calls drawIndexedPrimitives. Reject a count that cannot be
            // represented by that Metal indexCount argument after merging.
            guard UInt64(command.index_count) <= UInt64(UInt32.max / 3) else {
                throw GoldenEyeSourceSceneBatchingV6Error.indexCountOverflow(sourceIndex)
            }

            let entry = GoldenEyeSourceSceneBatchManifestEntryV6(
                sourceIndex: sourceIndex,
                drawHandle: command.draw_handle,
                commandHash: input.commandHash,
                renderStateHandle: command.render_state_handle,
                sourceRenderStateHash: input.key.sourceRenderStateHash,
                pipelineKeyHash: input.key.pipelineKeyHash,
                firstVertex: command.first_vertex,
                vertexCount: command.vertex_count,
                sortKey: command.sort_key,
                depthQ16: command.depth_q16,
                firstIndex: command.first_index,
                indexCount: command.index_count
            )
            manifest.append(entry)
            sourceHash = Self.mix(sourceHash, UInt64(sourceIndex))
            sourceHash = Self.mix(sourceHash, UInt64(command.draw_handle))
            sourceHash = Self.mix(sourceHash, input.commandHash)
            sourceHash = Self.mix(sourceHash, UInt64(command.render_state_handle))
            sourceHash = Self.mix(sourceHash, input.key.sourceRenderStateHash)
            sourceHash = Self.mix(sourceHash, input.key.pipelineKeyHash)
            sourceHash = Self.mix(sourceHash, UInt64(command.first_vertex))
            sourceHash = Self.mix(sourceHash, UInt64(command.vertex_count))
            sourceHash = Self.mix(sourceHash, UInt64(command.sort_key))
            sourceHash = Self.mix(sourceHash, UInt64(bitPattern: Int64(command.depth_q16)))
            sourceHash = Self.mix(sourceHash, UInt64(command.first_index))
            sourceHash = Self.mix(sourceHash, UInt64(command.index_count))

            if let previousIndex = batches.indices.last {
                let previous = batches[previousIndex]
                let previousInput = inputs[previous.sourceEnd - 1]
                let previousEnd = UInt64(previous.firstIndex) + UInt64(previous.indexCount)
                let mergedCount = UInt64(previous.indexCount) + UInt64(command.index_count)
                let canMerge = previousInput.key == input.key
                    && previous.instanceCount == command.instance_count
                    && previousEnd == UInt64(command.first_index)
                    && mergedCount <= UInt64(UInt32.max / 3)
                if canMerge {
                    batches[previousIndex] = GoldenEyeSourceSceneBatchV6(
                        sourceStart: previous.sourceStart,
                        sourceCount: previous.sourceCount + 1,
                        firstIndex: previous.firstIndex,
                        indexCount: UInt32(mergedCount),
                        instanceCount: previous.instanceCount,
                        pipelineKeyHash: previous.pipelineKeyHash
                    )
                    continue
                }
            }

            guard batches.count < maxBatchCount else {
                throw GoldenEyeSourceSceneBatchingV6Error.batchCountExceeded(maxBatchCount)
            }
            let batch = GoldenEyeSourceSceneBatchV6(
                sourceStart: sourceIndex,
                sourceCount: 1,
                firstIndex: command.first_index,
                indexCount: command.index_count,
                instanceCount: command.instance_count,
                pipelineKeyHash: input.key.pipelineKeyHash
            )
            batches.append(batch)
        }

        // Recompute the batch hash from final spans so a merge cannot leave a
        // stale hash from an intermediate singleton.  This also makes the
        // value independent of whether a caller inspects the plan while it is
        // being built.
        batchHash = Self.hashOffset
        for batch in batches {
            batchHash = Self.mix(batchHash, UInt64(batch.sourceStart))
            batchHash = Self.mix(batchHash, UInt64(batch.sourceCount))
            batchHash = Self.mix(batchHash, UInt64(batch.firstIndex))
            batchHash = Self.mix(batchHash, UInt64(batch.indexCount))
            batchHash = Self.mix(batchHash, UInt64(batch.instanceCount))
            batchHash = Self.mix(batchHash, batch.pipelineKeyHash)
        }

        guard manifest.count == inputs.count,
              batches.reduce(0, { $0 + $1.sourceCount }) == inputs.count else {
            throw GoldenEyeSourceSceneBatchingV6Error.commandCountMismatch(
                expected: inputs.count,
                actual: manifest.count
            )
        }
        self.sourceCommandCount = inputs.count
        self.metalDrawCount = batches.count
        self.manifest = manifest
        self.batches = batches
        self.sourceManifestHash = sourceHash
        self.batchManifestHash = batchHash
    }

    private static func mix(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 56, by: 8) {
            result = (result ^ ((value >> UInt64(shift)) & 0xff)) &* hashPrime
        }
        return result
    }
}
