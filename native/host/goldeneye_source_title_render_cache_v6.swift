#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

/// A title-scene cache entry owns only copied, immutable source values.  The
/// entry is deliberately separate from Metal resources and from the owner
/// thread's mutable frame mailbox: it may be looked up by a model/switch
/// route, then reframed with the current value-only matrices on the owner
/// thread.
struct GoldenEyeSourceTitleRenderCacheKeyV6: Hashable, Sendable {
    let modelName: String
    let modelPacketHash: UInt64
    let routeHash: UInt64
    let screen: UInt32
}

struct GoldenEyeSourceTitleRenderCacheEntryV6: @unchecked Sendable {
    let key: GoldenEyeSourceTitleRenderCacheKeyV6
    let scene: GESourceSceneV6
    let textureSetups: [GoldenEyeSourceTextureSetupV6]
    let topology: GoldenEyeGBISceneBuildResultV6
    /// State handles are stable across frames; this map tells the lighting
    /// sidecar which current source model-view resource each state consumes.
    let stateModelViewHandles: [UInt32: UInt32]
}

enum GoldenEyeSourceTitleRenderCacheError: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case missingMatrix(UInt32)
    case missingViewport(UInt32)
    case invalidTransform(UInt32)
    case invalidLightingState(UInt32)
    case invalidFrame

    var description: String {
        switch self {
        case .missingMatrix(let handle):
            return "title render cache matrix 0x\(String(handle, radix: 16)) is missing"
        case .missingViewport(let handle):
            return "title render cache viewport 0x\(String(handle, radix: 16)) is missing"
        case .invalidTransform(let handle):
            return "title render cache transform 0x\(String(handle, radix: 16)) is invalid"
        case .invalidLightingState(let handle):
            return "title render cache lighting state 0x\(String(handle, radix: 16)) has no model-view mapping"
        case .invalidFrame:
            return "title render cache frame context is invalid"
        }
    }
}

/// Rebuilds only the copied frame-local values around a compiled title
/// topology.  GESM traversal, C decoding, vertex/index expansion, resource
/// and draw records are never repeated on a cache hit.
enum GoldenEyeSourceTitleRenderCacheV6 {
    static func frameFlagsForTesting(
        presentable: Bool,
        unsupportedVisibleCount: UInt32,
        pairPhase: UInt32
    ) -> UInt32 {
        let visible = presentable && unsupportedVisibleCount == 0
        return (visible ? UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE) : 0)
            | (pairPhase == 0
                ? UInt32(GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR)
                : UInt32(GE_SOURCE_FRAME_V6_FLAG_INTERPOLATED))
    }

    static func makeKey(
        model: GoldenEyeSourceModelV6,
        modelName: String,
        screen: UInt32,
        switchInputs: [UInt32: UInt32],
        routeIdentity: UInt64 = 0
    ) -> GoldenEyeSourceTitleRenderCacheKeyV6 {
        var routeHash: UInt64 = 1_469_598_103_934_665_603
        routeHash ^= routeIdentity
        routeHash &*= 1_099_511_628_211
        for pair in switchInputs.sorted(by: { $0.key < $1.key }) {
            routeHash ^= UInt64(pair.key)
            routeHash &*= 1_099_511_628_211
            routeHash ^= UInt64(pair.value)
            routeHash &*= 1_099_511_628_211
        }
        if routeHash == 0 { routeHash = 1 }
        return GoldenEyeSourceTitleRenderCacheKeyV6(
            modelName: modelName,
            modelPacketHash: digestPrefix(model.header.packetHash),
            routeHash: routeHash,
            screen: screen
        )
    }

    static func makeEntry(
        key: GoldenEyeSourceTitleRenderCacheKeyV6,
        scene: GESourceSceneV6,
        textureSetups: [GoldenEyeSourceTextureSetupV6],
        result: GoldenEyeGBISceneBuildResultV6
    ) -> GoldenEyeSourceTitleRenderCacheEntryV6 {
        var transformByHandle: [UInt32: GESourceTransformV6] = [:]
        for transform in result.snapshot.transforms {
            transformByHandle[transform.handle] = transform
        }
        var stateModelViewHandles: [UInt32: UInt32] = [:]
        for draw in result.snapshot.drawCommands {
            guard stateModelViewHandles[draw.render_state_handle] == nil,
                  let transform = transformByHandle[draw.transform_handle],
                  transform.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_CLIP_COMPOSITE),
                  transform.parent_handle != 0 else { continue }
            stateModelViewHandles[draw.render_state_handle] = transform.parent_handle
        }
        return GoldenEyeSourceTitleRenderCacheEntryV6(
            key: key,
            scene: scene,
            textureSetups: textureSetups,
            topology: result,
            stateModelViewHandles: stateModelViewHandles
        )
    }

    static func reframe(
        _ entry: GoldenEyeSourceTitleRenderCacheEntryV6,
        model: GoldenEyeSourceModelV6,
        modelName: String,
        frame: GoldenEyeGBISceneFrameContextV6,
        matrices: [GoldenEyeGBIMatrixResourceV6],
        viewports: [GoldenEyeGBIViewportResourceV6]
    ) throws -> GoldenEyeGBISceneBuildResultV6 {
        guard frame.nativeTick > 0, frame.pairPhase <= 1 else {
            throw GoldenEyeSourceTitleRenderCacheError.invalidFrame
        }
        let matrixByHandle = Dictionary(uniqueKeysWithValues: matrices.map { ($0.handle, $0) })
        let matrixByLowHandle = Dictionary(
            matrices.map { ($0.handle & 0x00ff_ffff, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let viewportByHandle = Dictionary(uniqueKeysWithValues: viewports.map { ($0.handle, $0) })

        var transforms = entry.topology.snapshot.transforms
        for index in transforms.indices {
            let source = transforms[index]
            switch source.transform_kind {
            case UInt32(GE_SOURCE_TRANSFORM_V6_MODELVIEW),
                 UInt32(GE_SOURCE_TRANSFORM_V6_PROJECTION):
                let sourceHandle = source.handle & 0x00ff_ffff
                guard let matrix = matrixByLowHandle[sourceHandle] else {
                    throw GoldenEyeSourceTitleRenderCacheError.missingMatrix(sourceHandle)
                }
                var value = source
                setInt32Tuple(&value.matrix_q16, values: matrix.values)
                transforms[index] = value

            case UInt32(GE_SOURCE_TRANSFORM_V6_VIEWPORT):
                guard let viewport = viewportByHandle[source.viewport_id] else {
                    throw GoldenEyeSourceTitleRenderCacheError.missingViewport(source.viewport_id)
                }
                var value = source
                var matrix = Array(repeating: Int32(0), count: 16)
                matrix[0] = viewport.values[0]
                matrix[5] = viewport.values[1]
                matrix[10] = viewport.values[2]
                matrix[15] = viewport.values[3]
                matrix[12] = viewport.values[4]
                matrix[13] = viewport.values[5]
                matrix[14] = viewport.values[6]
                setInt32Tuple(&value.matrix_q16, values: matrix)
                transforms[index] = value

            case UInt32(GE_SOURCE_TRANSFORM_V6_CLIP_COMPOSITE):
                guard let modelView = matrixByHandle[source.parent_handle]
                        ?? matrixByLowHandle[source.parent_handle & 0x00ff_ffff],
                      let projection = matrixByHandle[source.source_node]
                        ?? matrixByLowHandle[source.source_node & 0x00ff_ffff],
                      let viewport = viewportByHandle[source.viewport_id]
                        ?? viewports.first(where: { ($0.handle & 0x00ff_ffff) == source.viewport_id }) else {
                    throw GoldenEyeSourceTitleRenderCacheError.invalidTransform(source.handle)
                }
                let inputs = try GoldenEyeSourceProjectionClipInputsV6(
                    modelViewHandle: source.parent_handle,
                    projectionHandle: source.source_node,
                    viewportHandle: source.viewport_id,
                    modelViewQ16: modelView.values,
                    projectionQ16: projection.values,
                    viewportQ16: viewport.values
                )
                transforms[index] = try GoldenEyeSourceProjectionBindingV6.makeTransform(
                    handle: source.handle,
                    inputs: inputs
                )

            default:
                // Future transform kinds remain immutable until their typed
                // source producer is added; silently changing them would
                // break the fail-closed renderer contract.
                break
            }
        }

        var renderStates = entry.topology.snapshot.renderStates
        if modelName == "rarewarelogo" {
            let bodyTexture = model.textures.last?.resourceHandle
            let fade = rarewareFade(sourceTimer: frame.sourceTimer ?? 0, pairPhase: frame.pairPhase)
            for index in renderStates.indices {
                var state = renderStates[index]
                let textureHandle = state.material_handle
                if textureHandle == bodyTexture {
                    let redBlue = (fade * 0xF0) / 0xFF
                    let green = (fade * 0xD0) / 0xFF
                    state.primitive_rgba = UInt32(redBlue) << 24
                        | UInt32(green) << 16 | UInt32(redBlue) << 8 | 0xFF
                } else {
                    state.primitive_rgba = UInt32(fade) << 24
                        | UInt32(fade) << 16 | UInt32(fade) << 8 | 0xFF
                }
                renderStates[index] = state
            }
        }

        var lighting: GoldenEyeSourceSceneLightingFrameContextV6?
        let geometryModes = entry.topology.geometryModesByState
        var modelViews: [UInt32: [Int32]] = [:]
        if entry.topology.snapshot.lightingFrameContext != nil {
            modelViews.reserveCapacity(geometryModes.count)
            for stateHandle in geometryModes.keys {
                guard let modelViewHandle = entry.stateModelViewHandles[stateHandle],
                      let matrix = matrixByHandle[modelViewHandle]
                        ?? matrixByLowHandle[modelViewHandle & 0x00ff_ffff] else {
                    throw GoldenEyeSourceTitleRenderCacheError.invalidLightingState(stateHandle)
                }
                modelViews[stateHandle] = matrix.values
            }
            lighting = try GoldenEyeSourceSceneLightingFrameContextV6(
                screen: frame.screen,
                nativeTick: frame.nativeTick,
                referenceTick: frame.referenceTick,
                sourceTimer: frame.sourceTimer ?? 0,
                pairPhase: frame.pairPhase,
                geometryModesByState: geometryModes,
                modelViewQ16ByState: modelViews
            )
        }

        let vertices = entry.topology.snapshot.vertices
        let indices = entry.topology.snapshot.indices
        let draws = entry.topology.snapshot.drawCommands
        let sceneHash = hashRecords(
            model: model,
            eventHash: entry.topology.eventHash,
            stateHash: entry.topology.stateHash,
            transforms: transforms,
            vertices: vertices,
            indices: indices,
            states: renderStates,
            draws: draws
        )
        let renderHash = hashDrawRecords(draws)
        let textureSetupHash = hashTextureSetups(entry.textureSetups)
        var frameHash = sceneHash
            ^ (renderHash &* 0x9e37_79b9_7f4a_7c15)
            ^ entry.topology.stateHash
            ^ textureSetupHash
        for value in [
            frame.nativeTick,
            frame.referenceTick,
            UInt64(frame.pairPhase),
            UInt64(frame.screen),
            UInt64(frame.subphase)
        ] {
            frameHash ^= value
            frameHash &*= 1_099_511_628_211
        }
        if frameHash == 0 { frameHash = 1 }

        var summary = entry.topology.snapshot.summary
        summary.flags = frameFlagsForTesting(
            presentable: entry.topology.presentable,
            unsupportedVisibleCount: entry.topology.unsupportedVisibleCount,
            pairPhase: frame.pairPhase
        )
        summary.screen = frame.screen
        summary.subphase = frame.subphase
        summary.native_tick = frame.nativeTick
        summary.reference_tick = frame.referenceTick
        summary.pair_phase = frame.pairPhase
        summary.viewport_width = frame.viewportWidth
        summary.viewport_height = frame.viewportHeight
        summary.logical_width = frame.logicalWidth
        summary.logical_height = frame.logicalHeight
        summary.unsupported_visible_count = entry.topology.unsupportedVisibleCount
        summary.scene_hash = sceneHash
        summary.render_hash = renderHash
        summary.state_hash = entry.topology.stateHash
        summary.frame_hash = frameHash

        let snapshot = try GoldenEyeSourceSceneSnapshotV6(
            reframing: entry.topology.snapshot,
            summary: summary,
            transforms: transforms,
            renderStates: renderStates,
            lightingFrameContext: lighting
        )

        return GoldenEyeGBISceneBuildResultV6(
            snapshot: snapshot,
            packetDialect: entry.topology.packetDialect,
            packetCommandCount: entry.topology.packetCommandCount,
            packetListCount: entry.topology.packetListCount,
            packetVertexCount: entry.topology.packetVertexCount,
            packetImageCount: entry.topology.packetImageCount,
            sourceCommandWordHash: entry.topology.sourceCommandWordHash,
            packetCommandWordHash: entry.topology.packetCommandWordHash,
            packetSourceCommandWordHash: entry.topology.packetSourceCommandWordHash,
            textureSetups: entry.textureSetups,
            vertexResourceTotal: entry.topology.vertexResourceTotal,
            vertexResourcePageCount: entry.topology.vertexResourcePageCount,
            vertexResourceManifestHash: entry.topology.vertexResourceManifestHash,
            projectionConsumption: entry.topology.projectionConsumption,
            decoderStatus: entry.topology.decoderStatus,
            decoderDraws: entry.topology.decoderDraws,
            stateWordEvidence: entry.topology.stateWordEvidence,
            decoderUnsupportedCount: entry.topology.decoderUnsupportedCount,
            unsupportedVisibleCount: entry.topology.unsupportedVisibleCount,
            unsupportedReasons: entry.topology.unsupportedReasons,
            presentable: snapshot.isPresentable,
            commandCount: entry.topology.commandCount,
            triangleCount: entry.topology.triangleCount,
            sourceTriangleSlotCount: entry.topology.sourceTriangleSlotCount,
            decoderStateCount: entry.topology.decoderStateCount,
            resourceCount: entry.topology.resourceCount,
            eventHash: entry.topology.eventHash,
            stateHash: entry.topology.stateHash,
            geometryModesByState: geometryModes,
            modelViewQ16ByState: modelViews,
            exactNodeTransformDrawCount: entry.topology.exactNodeTransformDrawCount,
            fallbackNodeTransformDrawCount: entry.topology.fallbackNodeTransformDrawCount,
            exactNodeTransformHandles: entry.topology.exactNodeTransformHandles
        )
    }

    private static func rarewareFade(sourceTimer: UInt32, pairPhase: UInt32) -> Int {
        let counter = Int64(sourceTimer)
        let fadeIn = min(max((counter * 255) / 70, 0), 255)
        let fadeOut = min(max(255 - ((counter * 255 - 40_800) / 70), 0), 255)
        let current = (fadeIn * fadeOut) / 255
        let next: Int64
        if pairPhase == 1, sourceTimer != UInt32.max {
            let n = Int64(sourceTimer &+ 1)
            let nextIn = min(max((n * 255) / 70, 0), 255)
            let nextOut = min(max(255 - ((n * 255 - 40_800) / 70), 0), 255)
            next = (nextIn * nextOut) / 255
        } else {
            next = current
        }
        let fadeQ16 = (current + next) * (pairPhase == 1 ? 32_768 : 65_536)
        return Int(min(max((fadeQ16 + 32_768) / 65_536, 0), 255))
    }

    private static func hashRecords(
        model: GoldenEyeSourceModelV6,
        eventHash: UInt64,
        stateHash: UInt64,
        transforms: [GESourceTransformV6],
        vertices: [GESourceVertexV6],
        indices: [GESourceIndexV6],
        states: [GESourceRenderStateV6],
        draws: [GESourceDrawCommandV6]
    ) -> UInt64 {
        var hash = UInt64(1_469_598_103_934_665_603)
        hash ^= digestPrefix(model.header.packetHash); hash &*= 1_099_511_628_211
        hash ^= eventHash; hash &*= 1_099_511_628_211
        hash ^= stateHash; hash &*= 1_099_511_628_211
        for value in transforms { hash = hashRecordBytes(hash, value) }
        for value in vertices { hash = hashRecordBytes(hash, value) }
        for value in indices { hash = hashRecordBytes(hash, value) }
        for value in states { hash = hashRecordBytes(hash, value) }
        for value in draws { hash = hashRecordBytes(hash, value) }
        return hash == 0 ? 1 : hash
    }

    private static func hashDrawRecords(_ draws: [GESourceDrawCommandV6]) -> UInt64 {
        var hash = UInt64(1_469_598_103_934_665_603)
        for draw in draws { hash = hashRecordBytes(hash, draw) }
        return hash == 0 ? 1 : hash
    }

    private static func hashTextureSetups(_ setups: [GoldenEyeSourceTextureSetupV6]) -> UInt64 {
        var hash = UInt64(1_469_598_103_934_665_603)
        for setup in setups.sorted(by: {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            if $0.resourceHandle != $1.resourceHandle { return $0.resourceHandle < $1.resourceHandle }
            return $0.tile < $1.tile
        }) {
            hash ^= setup.setupHash
            hash &*= 1_099_511_628_211
        }
        return setups.isEmpty ? 0 : (hash == 0 ? 1 : hash)
    }

    private static func hashRecordBytes<T>(_ seed: UInt64, _ value: T) -> UInt64 {
        var hash = seed
        withUnsafeBytes(of: value) { bytes in
            for byte in bytes { hash ^= UInt64(byte); hash &*= 1_099_511_628_211 }
        }
        return hash
    }

    private static func digestPrefix(_ digest: [UInt8]) -> UInt64 {
        digest.prefix(8).enumerated().reduce(UInt64(0)) {
            $0 | UInt64($1.element) << UInt64($1.offset * 8)
        }
    }

    private static func setInt32Tuple<T>(_ tuple: inout T, values: [Int32]) {
        withUnsafeMutableBytes(of: &tuple) { raw in
            let typed = raw.bindMemory(to: Int32.self)
            for index in values.indices where index < typed.count {
                typed[index] = values[index]
            }
        }
    }
}
