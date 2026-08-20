import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Converts the bounded stage-environment packet into the existing source
/// scene contract. This is intentionally a partial environment frame: the
/// packet contains only decoded room triangles and portal polygons, while the
/// per-stage unsupported mask remains outside the snapshot so the source
/// renderer can present the proven subset without pretending props, material
/// textures, characters, effects, or HUD are complete.
enum GoldenEyeStageSourceSceneSnapshotAdapterV6 {
    enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case capacity
        case malformedCommand(UInt32)
        case invalidCoordinate(UInt32)

        var description: String {
            switch self {
            case .capacity: return "stage source scene snapshot exceeds bounded capacity"
            case let .malformedCommand(index): return "stage source scene command \(index) is malformed"
            case let .invalidCoordinate(index): return "stage source scene vertex \(index) has invalid clip coordinates"
            }
        }
    }

    static func make(
        packet: GoldenEyeStageBackgroundDrawPacket,
        nativeTick: UInt64,
        materialPacket: GoldenEyeStageSourceMaterialPacketV6? = nil,
        stageTextureCatalog: GoldenEyeStageTextureCatalogV6? = nil
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        guard nativeTick > 0,
              packet.vertices.count <= 1_000_000,
              packet.commands.count <= 1_000_000 else {
            throw Error.capacity
        }

        var vertices: [GESourceVertexV6] = []
        vertices.reserveCapacity(packet.vertices.count)
        for (index, source) in packet.vertices.enumerated() {
            let w = Double(source.clipWQ16)
            guard w != 0, w.isFinite else { throw Error.invalidCoordinate(UInt32(index)) }
            let x = Double(source.clipXQ16) / w * 65_536.0
            let y = Double(source.clipYQ16) / w * 65_536.0
            let z = Double(source.clipZQ16) / w * 65_536.0
            guard x.isFinite, y.isFinite, z.isFinite,
                  x >= Double(Int32.min), x <= Double(Int32.max),
                  y >= Double(Int32.min), y <= Double(Int32.max),
                  z >= Double(Int32.min), z <= Double(Int32.max) else {
                throw Error.invalidCoordinate(UInt32(index))
            }
            var value = GESourceVertexV6()
            setHeader(&value.header, size: MemoryLayout<GESourceVertexV6>.size)
            value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
            value.handle = 0xA500_0000 | UInt32(index + 1)
            value.flags = UInt32(GE_SOURCE_VERTEX_V6_FLAG_SOURCE_QUANTIZED)
            value.position_q16.0 = Int32(x.rounded(.toNearestOrAwayFromZero))
            value.position_q16.1 = Int32(y.rounded(.toNearestOrAwayFromZero))
            value.position_q16.2 = Int32(z.rounded(.toNearestOrAwayFromZero))
            // Background Vtx records carry authored S/T in signed S10.5
            // lanes.  The generic source-scene ABI uses Q16.16, so widen by
            // eleven bits without passing through Float.  Marker/portal
            // vertices have a zero reserved word and retain the neutral UV.
            value.texcoord_q16.0 = source.sourceTextureCoordinatesPresent
                ? Int32(clamping: Int64(source.sourceTextureS10_5) * 2_048)
                : 0
            value.texcoord_q16.1 = source.sourceTextureCoordinatesPresent
                ? Int32(clamping: Int64(source.sourceTextureT10_5) * 2_048)
                : 0
            value.normal_q16.2 = 65_536
            value.color_rgba = source.colorRGBA8
            value.source_index = source.roomIndex
            vertices.append(value)
        }

        var indices: [GESourceIndexV6] = []
        var draws: [GESourceDrawCommandV6] = []
        indices.reserveCapacity(packet.commands.count)
        draws.reserveCapacity(packet.commands.count)
        var renderStates: [GESourceRenderStateV6] = [defaultRenderState()]
        var materialStateHandles: [UInt32: UInt32] = [:]
        var uniqueMaterialHandles: [UInt64: UInt32] = [:]
        let resolvedTextureIDs = Set(
            materialPacket?.states.compactMap { $0.resolvedTextureID } ?? []
        )
        let stageTextureResources: [GESourceResourceV6]
        if let stageTextureCatalog, !resolvedTextureIDs.isEmpty {
            stageTextureResources = try stageTextureCatalog.resources(for: resolvedTextureIDs)
        } else {
            stageTextureResources = []
        }
        let stageTextureHandles = Dictionary(
            uniqueKeysWithValues: resolvedTextureIDs.map { id in
                (id, GoldenEyeStageTextureCatalogV6.resourceHandle(textureID: id))
            }
        )
        if let materialPacket {
            renderStates.reserveCapacity(min(materialPacket.states.count + 1, 2_048))
            for material in materialPacket.states {
                if let existing = uniqueMaterialHandles[material.stateHash] {
                    materialStateHandles[material.stateIndex] = existing
                    continue
                }
                guard renderStates.count < 2_048 else { break }
                let handle = 0xB700_0000 | UInt32(renderStates.count)
                uniqueMaterialHandles[material.stateHash] = handle
                materialStateHandles[material.stateIndex] = handle
                renderStates.append(materialRenderState(material, handle: handle))
            }
        }
        var roomTriangleOrdinalsByRoom: [UInt32: Int] = [:]
        var materialStateIndicesByRoom: [UInt32: [UInt32]] = [:]
        if let materialPacket {
            let roomByState = Dictionary(
                uniqueKeysWithValues: materialPacket.states.map { ($0.stateIndex, $0.roomIndex) }
            )
            for stateIndex in materialPacket.drawStateIndices {
                if let roomIndex = roomByState[stateIndex] {
                    materialStateIndicesByRoom[roomIndex, default: []].append(stateIndex)
                }
            }
        }
        for (commandIndex, command) in packet.commands.enumerated() {
            guard command.vertexCount == 3,
                  Int(command.vertexStart) + 3 <= vertices.count else {
                throw Error.malformedCommand(UInt32(commandIndex))
            }
            var index = GESourceIndexV6()
            setHeader(&index.header, size: MemoryLayout<GESourceIndexV6>.size)
            index.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
            index.handle = 0xA600_0000 | UInt32(commandIndex + 1)
            index.flags = UInt32(GE_SOURCE_INDEX_V6_FLAG_SOURCE_ORDERED)
            index.vertex0 = command.vertexStart
            index.vertex1 = command.vertexStart + 1
            index.vertex2 = command.vertexStart + 2
            index.source_index = command.sourceIndex
            indices.append(index)

            var draw = GESourceDrawCommandV6()
            setHeader(&draw.header, size: MemoryLayout<GESourceDrawCommandV6>.size)
            draw.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
            draw.command_kind = UInt32(GE_SOURCE_DRAW_V6_TRIANGLES)
            draw.flags = UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE)
                | UInt32(GE_SOURCE_DRAW_V6_FLAG_SOURCE_ORDERED)
            draw.draw_handle = 0xA300_0000 | UInt32(commandIndex + 1)
            draw.transform_handle = 0
            draw.resource_handle = 0
            if command.primitive == .roomTriangle,
               let materialPacket {
                let roomIndex = command.sourceIndex
                let ordinal: Int
                if command.reserved & 0x8000_0000 != 0 {
                    ordinal = Int(command.reserved & 0x7fff_ffff)
                } else {
                    ordinal = roomTriangleOrdinalsByRoom[roomIndex, default: 0]
                    roomTriangleOrdinalsByRoom[roomIndex] = ordinal + 1
                }
                let stateIndex = materialStateIndicesByRoom[roomIndex]?[safe: ordinal]
                guard let stateIndex else {
                    throw Error.malformedCommand(UInt32(commandIndex))
                }
                draw.render_state_handle = materialStateHandles[stateIndex] ?? 1
                if stageTextureCatalog != nil,
                   let material = materialPacket.states.first(where: { $0.stateIndex == stateIndex }),
                   let textureID = material.resolvedTextureID {
                    draw.resource_handle = stageTextureHandles[textureID] ?? 0

                    // The stage packet stores authored S10.5 in the compact
                    // vertex reserved word.  Normalize against the bound
                    // source base dimensions here, at the same value-only
                    // seam where the resource handle is selected.  This
                    // keeps interpolation and sampler addressing in the
                    // generic source-scene Metal path source-derived without
                    // introducing a second stage-only shader ABI.
                    if let stageTexture = stageTextureCatalog?.texture(textureID: textureID),
                       let baseLevel = stageTexture.levels.first,
                       baseLevel.width > 0, baseLevel.height > 0 {
                        let start = Int(command.vertexStart)
                        let end = start + 3
                        if start >= 0, end <= vertices.count {
                            for vertexIndex in start..<end {
                                var vertex = vertices[vertexIndex]
                                vertex.texcoord_q16.0 = Int32(
                                    clamping: Int64(vertex.texcoord_q16.0) /
                                        Int64(baseLevel.width)
                                )
                                vertex.texcoord_q16.1 = Int32(
                                    clamping: Int64(vertex.texcoord_q16.1) /
                                        Int64(baseLevel.height)
                                )
                                vertices[vertexIndex] = vertex
                            }
                        }
                    }
                }
            } else {
                draw.render_state_handle = 1
            }
            draw.first_vertex = command.vertexStart
            draw.vertex_count = 3
            draw.first_index = UInt32(commandIndex)
            draw.index_count = 1
            draw.instance_count = 1
            draw.sort_key = command.sourceIndex
            draw.scissor_width = 440
            draw.scissor_height = 330
            draw.draw_hash = command.metadataHash ^ UInt64(commandIndex)
            draws.append(draw)
        }

        // Preserve every source triangle/index record, but submit contiguous
        // triangles as one generic source-scene draw whenever their authored
        // room display-list boundary, material state, texture handle, and
        // raster flags are identical.  This keeps source triangle manifests
        // lossless (`index_count`) while preventing one Metal draw per
        // triangle (`draw_count`) for the large RAMROM room lists.
        if draws.count > 1 {
            var batched: [GESourceDrawCommandV6] = []
            var batchedSourceCommands: [GoldenEyeStageBackgroundDrawCommand] = []
            batched.reserveCapacity(draws.count)
            batchedSourceCommands.reserveCapacity(draws.count)
            for index in draws.indices {
                let command = packet.commands[index]
                let draw = draws[index]
                if let lastIndex = batched.indices.last,
                   let priorCommand = batchedSourceCommands[safe: lastIndex],
                   command.primitive == .roomTriangle,
                   priorCommand.primitive == .roomTriangle,
                   command.sourceRecordOffset == priorCommand.sourceRecordOffset,
                   command.sourceIndex == priorCommand.sourceIndex,
                   command.flags == priorCommand.flags,
                   batched[lastIndex].render_state_handle == draw.render_state_handle,
                   batched[lastIndex].resource_handle == draw.resource_handle,
                   batched[lastIndex].first_vertex + batched[lastIndex].vertex_count == draw.first_vertex,
                   batched[lastIndex].first_index + batched[lastIndex].index_count == draw.first_index {
                    batched[lastIndex].vertex_count &+= draw.vertex_count
                    batched[lastIndex].index_count &+= draw.index_count
                    batched[lastIndex].draw_hash ^= draw.draw_hash &* 0x9e37_79b9_7f4a_7c15
                } else {
                    batched.append(draw)
                    batchedSourceCommands.append(command)
                }
            }
            draws = batched
        }

        var summary = GESourceFrameSummaryV6()
        setHeader(&summary.header, size: MemoryLayout<GESourceFrameSummaryV6>.size)
        summary.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        let texturePending: Bool
        if let materialPacket, materialPacket.textureStateCommandCount > 0 {
            texturePending = stageTextureCatalog?.isGPURepresentable != true
                || resolvedTextureIDs.isEmpty
                || !resolvedTextureIDs.allSatisfy { stageTextureCatalog?.texture(textureID: $0) != nil }
        } else {
            texturePending = false
        }
        let unsupportedVisibleCount = UInt32(packet.unsupportedMask.nonzeroBitCount)
            &+ (texturePending ? 1 : 0)
            &+ ((materialPacket?.unsupportedCommandCount ?? 0) > 0 ? 1 : 0)
        let cadenceFlags = nativeTick & 1 == 0
            ? UInt32(GE_SOURCE_FRAME_V6_FLAG_SOURCE_ANCHOR)
            : UInt32(GE_SOURCE_FRAME_V6_FLAG_INTERPOLATED)
        summary.flags = cadenceFlags
            | (unsupportedVisibleCount == 0
                ? UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE) : 0)
        summary.screen = UInt32(GE_SOURCE_FRAME_V6_SCREEN_RAMROM)
        summary.subphase = packet.stageID
        summary.native_tick = nativeTick
        summary.reference_tick = nativeTick >> 1
        summary.pair_phase = UInt32(nativeTick & 1)
        summary.viewport_width = 440
        summary.viewport_height = 330
        summary.logical_width = 440
        summary.logical_height = 330
        summary.vertex_count = UInt32(vertices.count)
        summary.index_count = UInt32(indices.count)
        summary.draw_count = UInt32(draws.count)
        summary.render_state_count = UInt32(renderStates.count)
        summary.resource_count = UInt32(stageTextureResources.count)
        summary.unsupported_visible_count = unsupportedVisibleCount
        let packetHash = materialPacket.map { packet.packetHash ^ $0.packetHash } ?? packet.packetHash
        summary.scene_hash = packetHash == 0 ? 1 : packetHash
        summary.render_hash = packetHash ^ 0x9e37_79b9_7f4a_7c15
        summary.state_hash = packetHash ^ 0xd1b5_4a32_d192_ed03
        summary.audio_hash = 1
        summary.frame_hash = packetHash ^ nativeTick

        let identity = Array(repeating: Int32(0), count: 16).enumerated().map {
            $0.offset % 5 == 0 ? Int32(65_536) : 0
        }
        let lighting = try GoldenEyeSourceSceneLightingFrameContextV6(
            screen: summary.screen,
            nativeTick: nativeTick,
            referenceTick: nativeTick >> 1,
            sourceTimer: 0,
            pairPhase: UInt32(nativeTick & 1),
            geometryModesByState: Dictionary(
                uniqueKeysWithValues: renderStates.map { ($0.state_handle, UInt32(0)) }
            ),
            modelViewQ16ByState: Dictionary(
                uniqueKeysWithValues: renderStates.map { ($0.state_handle, identity) }
            )
        )
        return try GoldenEyeSourceSceneSnapshotV6(
            summary: summary,
            resources: stageTextureResources,
            transforms: [],
            animationPoses: [],
            vertices: vertices,
            indices: indices,
            renderStates: renderStates,
            drawCommands: draws,
            textEvents: [],
            audioEvents: [],
            diagnostics: [],
            lightingFrameContext: lighting
        )
    }

    private static func setHeader(_ header: inout GEAbiHeaderV1, size: Int) {
        header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        header.struct_size = UInt32(size)
    }

    private struct StageCombinerV6 {
        let cycleCount: UInt32
        let values: [UInt32]
    }

    /// Field-aware decode of the source FC combiner tuple.  Raw selector
    /// values are width-dependent (A/B=4 bits, C=5 bits, D=3 bits); literal
    /// zero in a D field is not COMBINED.  Keeping this decoder beside the
    /// stage adapter ensures room materials use the same normalized selector
    /// contract as title/model scenes.
    private static func decodeStageCombiner(
        _ w0: UInt32,
        _ w1: UInt32,
        cycleCount: UInt32
    ) -> StageCombinerV6? {
        guard w0 >> 24 == 0xfc else { return nil }
        let combined = UInt32(GE_SOURCE_COMBINER_V6_KEY_COMBINED)
        let texel0 = UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0)
        let texel1 = UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL1)
        let primitive = UInt32(GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE)
        let shade = UInt32(GE_SOURCE_COMBINER_V6_KEY_SHADE)
        let environment = UInt32(GE_SOURCE_COMBINER_V6_KEY_ENVIRONMENT)
        let one = UInt32(GE_SOURCE_COMBINER_V6_KEY_ONE)
        let zero = UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO)
        let lod = UInt32(GE_SOURCE_COMBINER_V6_KEY_LOD_FRACTION)
        let primitiveLOD = UInt32(GE_SOURCE_COMBINER_V6_KEY_PRIMITIVE_LOD_FRACTION)
        let k4 = UInt32(GE_SOURCE_COMBINER_V6_KEY_K4)
        let k5 = UInt32(GE_SOURCE_COMBINER_V6_KEY_K5)
        let center = UInt32(GE_SOURCE_COMBINER_V6_KEY_CENTER)
        let combinedAlpha = UInt32(GE_SOURCE_COMBINER_V6_KEY_COMBINED_ALPHA)

        func colorA(_ raw: UInt32) -> UInt32? {
            switch raw {
            case 0: return combined
            case 1: return texel0
            case 2: return texel1
            case 3: return primitive
            case 4: return shade
            case 5: return environment
            case 6: return one
            case 7: return k4
            case 8: return texel0
            case 9: return texel1
            case 10: return primitive
            case 11: return shade
            case 12: return environment
            case 13: return lod
            case 14: return primitiveLOD
            case 15: return zero
            default: return nil
            }
        }
        func colorB(_ raw: UInt32) -> UInt32? {
            raw == 0 || raw == 15 ? zero : colorA(raw)
        }
        func colorC(_ raw: UInt32) -> UInt32? {
            switch raw {
            case 0: return combined
            case 1: return texel0
            case 2: return texel1
            case 3: return primitive
            case 4: return shade
            case 5: return environment
            case 6: return center
            case 7: return combinedAlpha
            case 8: return texel0
            case 9: return texel1
            case 10: return primitive
            case 11: return shade
            case 12: return environment
            case 13: return lod
            case 14: return primitiveLOD
            case 15: return k5
            case 31: return zero
            default: return nil
            }
        }
        func colorD(_ raw: UInt32) -> UInt32? {
            switch raw {
            case 0, 7: return zero
            case 1: return texel0
            case 2: return texel1
            case 3: return primitive
            case 4: return shade
            case 5: return environment
            case 6: return one
            default: return nil
            }
        }
        func alphaA(_ raw: UInt32) -> UInt32? {
            switch raw {
            case 0: return combined
            case 1: return texel0
            case 2: return texel1
            case 3: return primitive
            case 4: return shade
            case 5: return environment
            case 6: return one
            case 7: return zero
            default: return nil
            }
        }
        func alphaB(_ raw: UInt32) -> UInt32? {
            raw == 0 || raw == 7 ? zero : alphaA(raw)
        }
        func alphaD(_ raw: UInt32) -> UInt32? {
            raw == 0 || raw == 7 ? zero : alphaA(raw)
        }
        func alphaC(_ raw: UInt32) -> UInt32? {
            switch raw {
            case 0: return lod
            case 1: return texel0
            case 2: return texel1
            case 3: return primitive
            case 4: return shade
            case 5: return environment
            case 6: return one
            case 7: return zero
            default: return nil
            }
        }

        let rawC0: [UInt32] = [
            (w0 >> 20) & 0xf, (w1 >> 28) & 0xf,
            (w0 >> 15) & 0x1f, (w1 >> 15) & 7,
        ]
        let rawA0: [UInt32] = [
            (w0 >> 12) & 7, (w1 >> 12) & 7,
            (w0 >> 9) & 7, (w1 >> 9) & 7,
        ]
        let rawC1: [UInt32] = [
            (w0 >> 5) & 0xf, (w1 >> 24) & 0xf,
            w0 & 0x1f, (w1 >> 6) & 7,
        ]
        let rawA1: [UInt32] = [
            (w1 >> 21) & 7, (w1 >> 3) & 7,
            (w1 >> 18) & 7, w1 & 7,
        ]
        guard let c0a = colorA(rawC0[0]), let c0b = colorB(rawC0[1]),
              let c0c = colorC(rawC0[2]), let c0d = colorD(rawC0[3]),
              let c0aa = alphaA(rawA0[0]), let c0ab = alphaB(rawA0[1]),
              let c0ac = alphaC(rawA0[2]), let c0ad = alphaD(rawA0[3]),
              let c1a = colorA(rawC1[0]), let c1b = colorB(rawC1[1]),
              let c1c = colorC(rawC1[2]), let c1d = colorD(rawC1[3]),
              let c1aa = alphaA(rawA1[0]), let c1ab = alphaB(rawA1[1]),
              let c1ac = alphaC(rawA1[2]), let c1ad = alphaD(rawA1[3]) else {
            return nil
        }
        let inactive = Array(repeating: zero, count: 8)
        let first = [c0a, c0b, c0c, c0d, c0aa, c0ab, c0ac, c0ad]
        let second = cycleCount == 1
            ? inactive
            : [c1a, c1b, c1c, c1d, c1aa, c1ab, c1ac, c1ad]
        return StageCombinerV6(cycleCount: cycleCount, values: first + second)
    }

    private static func packedBlender(_ mode: UInt32, high: UInt32, low: UInt32) -> UInt32 {
        ((mode >> high) & 3) | (((mode >> low) & 3) << 2)
    }

    private static func defaultRenderState() -> GESourceRenderStateV6 {
        var value = GESourceRenderStateV6()
        setHeader(&value.header, size: MemoryLayout<GESourceRenderStateV6>.size)
        value.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        value.state_handle = 1
        value.flags = 0
        value.material_handle = 1
        value.combiner_cycle_count = 1
        // Normalized source combiner selectors: SHADE=4, ZERO=7, ONE=6.
        value.cycle0_color_a = 4
        value.cycle0_color_b = 7
        value.cycle0_color_c = 6
        value.cycle0_color_d = 7
        value.cycle0_alpha_a = 4
        value.cycle0_alpha_b = 7
        value.cycle0_alpha_c = 6
        value.cycle0_alpha_d = 7
        value.cycle1_color_a = 7
        value.cycle1_color_b = 7
        value.cycle1_color_c = 7
        value.cycle1_color_d = 7
        value.cycle1_alpha_a = 7
        value.cycle1_alpha_b = 7
        value.cycle1_alpha_c = 7
        value.cycle1_alpha_d = 7
        value.primitive_rgba = 0xffff_ffff
        value.environment_rgba = 0
        value.depth_mode = UInt32(GE_SOURCE_DEPTH_V6_DISABLED)
        value.alpha_mode = UInt32(GE_SOURCE_ALPHA_V6_DISABLED)
        value.coverage_mode = UInt32(GE_SOURCE_COVERAGE_V6_CLAMP)
        value.cull_mode = UInt32(GE_SOURCE_CULL_V6_NONE)
        value.filter_mode = UInt32(GE_SOURCE_FILTER_V6_POINT)
        value.wrap_s = UInt32(GE_SOURCE_WRAP_V6_CLAMP)
        value.wrap_t = UInt32(GE_SOURCE_WRAP_V6_CLAMP)
        value.raw_othermode_l = 0x0c08_0000
        value.raw_render_mode = 0x0c08_0000
        value.raw_blender_a = 0
        value.raw_blender_b = 3
        value.raw_blender_c = 0
        value.raw_blender_d = 2
        return value
    }

    private static func materialRenderState(
        _ source: GoldenEyeStageSourceMaterialStateV6,
        handle: UInt32
    ) -> GESourceRenderStateV6 {
        var value = defaultRenderState()
        value.state_handle = handle
        value.material_handle = handle
        value.primitive_rgba = source.primitiveColor == 0
            ? 0xffff_ffff : source.primitiveColor
        value.environment_rgba = source.environmentColor
        value.blend_rgba = source.blendColor
        value.fog_rgba = source.fogColor

        // Source detail mode is retained in the material sidecar. The
        // generic stage shader has no separate detail texture input, so clear
        // only the typed detail bits at this boundary; point/bilinear,
        // perspective, cycle, and LOD fields remain source-authored.
        let rawH = source.otherModeHigh & ~(UInt32(3) << 17)
        let rawL = source.otherModeLow
        let cycleType = (rawH >> 20) & 3
        let cycleCount = cycleType == 1 ? UInt32(2) : UInt32(1)
        if let combiner = decodeStageCombiner(
            source.combineWord0,
            source.combineWord1,
            cycleCount: cycleCount
        ) {
            value.combiner_cycle_count = combiner.cycleCount
            var c = combiner.values
            // Some source one-cycle room tuples retain the literal
            // LOD_FRACTION selector while OtherMode disables texture LOD.
            // The source RDP resolves that scalar to zero; normalize only at
            // the Metal selector boundary while retaining the raw FC/H words
            // in the material sidecar for provenance.
            if ((rawH >> 16) & 1) == 0 || cycleCount != 2 {
                let lodSelector = UInt32(GE_SOURCE_COMBINER_V6_KEY_LOD_FRACTION)
                for index in c.indices where c[index] == lodSelector {
                    c[index] = UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO)
                }
            }
            value.cycle0_color_a = c[0]; value.cycle0_color_b = c[1]
            value.cycle0_color_c = c[2]; value.cycle0_color_d = c[3]
            value.cycle0_alpha_a = c[4]; value.cycle0_alpha_b = c[5]
            value.cycle0_alpha_c = c[6]; value.cycle0_alpha_d = c[7]
            value.cycle1_color_a = c[8]; value.cycle1_color_b = c[9]
            value.cycle1_color_c = c[10]; value.cycle1_color_d = c[11]
            value.cycle1_alpha_a = c[12]; value.cycle1_alpha_b = c[13]
            value.cycle1_alpha_c = c[14]; value.cycle1_alpha_d = c[15]
        } else if source.resolvedTextureID != nil {
            // A source material without an FC command is uncommon but the
            // texture-only fallback remains typed and deterministic.
            value.cycle0_color_a = UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0)
            value.cycle0_color_b = UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO)
            value.cycle0_color_c = UInt32(GE_SOURCE_COMBINER_V6_KEY_ONE)
            value.cycle0_color_d = UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO)
            value.cycle0_alpha_a = UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0)
            value.cycle0_alpha_b = UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO)
            value.cycle0_alpha_c = UInt32(GE_SOURCE_COMBINER_V6_KEY_ONE)
            value.cycle0_alpha_d = UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO)
        }

        let rawRenderMode = rawL & 0xffff_fff8
        let zCompare = ((rawRenderMode >> 4) & 1) != 0
        let zUpdate = ((rawRenderMode >> 5) & 1) != 0
        let coverageDestination = (rawRenderMode >> 8) & 3
        let alphaMode = rawL & 3
        value.depth_mode = zCompare
            ? UInt32(GE_SOURCE_DEPTH_V6_LEQUAL)
            : (zUpdate ? UInt32(GE_SOURCE_DEPTH_V6_ALWAYS) : UInt32(GE_SOURCE_DEPTH_V6_DISABLED))
        value.alpha_mode = alphaMode
        value.coverage_mode = coverageDestination
        value.cull_mode = cullMode(for: source.geometryMode)
        value.filter_mode = filterMode(for: rawH)
        value.raw_othermode_h = rawH
        value.raw_othermode_l = rawL
        value.raw_render_mode = rawRenderMode
        value.raw_blender_a = packedBlender(rawRenderMode, high: 30, low: 28)
        value.raw_blender_b = packedBlender(rawRenderMode, high: 26, low: 24)
        value.raw_blender_c = packedBlender(rawRenderMode, high: 22, low: 20)
        value.raw_blender_d = packedBlender(rawRenderMode, high: 18, low: 16)
        value.flags = 0
        if zCompare { value.flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_TEST) }
        if zUpdate { value.flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_DEPTH_WRITE) }
        if alphaMode != UInt32(GE_SOURCE_ALPHA_V6_DISABLED) {
            value.flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_ALPHA_COMPARE)
        }
        if coverageDestination != 0 {
            value.flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_COVERAGE)
        }
        if coverageDestination == UInt32(GE_SOURCE_COVERAGE_V6_SAVE) {
            value.flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_COVERAGE_SAVE)
        }
        if source.geometryMode & 0x0001_0000 != 0 {
            value.flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_FOG)
        }
        if ((rawRenderMode >> 3) & 1) != 0 {
            value.flags |= UInt32(GE_SOURCE_RENDER_STATE_V6_FLAG_ANTIALIAS)
        }
        return value
    }

    private static func cullMode(for geometryMode: UInt32) -> UInt32 {
        let front = geometryMode & 0x0000_1000 != 0
        let back = geometryMode & 0x0000_2000 != 0
        switch (front, back) {
        case (true, true):
            // The source can transiently carry CULL_BOTH while switching
            // room lists. Metal exposes one-sided culling; the visibility
            // owner removes such a room when both faces are truly disabled.
            // Keep this packet renderable for source-room capture rather than
            // manufacturing a second pass or silently dropping the list.
            return UInt32(GE_SOURCE_CULL_V6_NONE)
        case (true, false): return UInt32(GE_SOURCE_CULL_V6_FRONT)
        case (false, true): return UInt32(GE_SOURCE_CULL_V6_BACK)
        default: return UInt32(GE_SOURCE_CULL_V6_NONE)
        }
    }

    private static func filterMode(for rawH: UInt32) -> UInt32 {
        switch (rawH >> 12) & 3 {
        case 2, 3: return UInt32(GE_SOURCE_FILTER_V6_BILINEAR)
        default: return UInt32(GE_SOURCE_FILTER_V6_POINT)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
