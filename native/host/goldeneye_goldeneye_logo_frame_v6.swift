#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

/// Immutable, source-ordered GoldenEye logo frame.
///
/// This is intentionally a screen-specific closure contract.  It keeps the
/// source route/timing evidence next to the complete GoldenEye model graph so
/// a generic title fixture cannot accidentally stand in for the 438-vertex,
/// two-material logo.  All source values are copied into the existing V6
/// value-only scene boundary before this record is returned.
@available(macOS 26.0, *)
struct GoldenEyeGoldenEyeLogoFrameV6: @unchecked Sendable {
    struct OmittedDegenerateTriangleV6: Sendable, Equatable {
        let sourceCommandIndex: UInt32
        let packetByteOffset: UInt32
        let tupleIndex: UInt32
        let sourceVertexA: UInt32
        let sourceVertexB: UInt32
        let sourceVertexC: UInt32

        var reason: String { "gsSP4Triangles zero sentinel (0,0,0)" }
    }

    static let modelName = "goldeneyelogo"
    static let sourceNodeCount = 3
    static let sourceDisplayListCount = 1
    static let sourceCommandCount: UInt32 = 162
    static let sourceVertexCount = 438
    static let sourceTextureCount = 2
    static let sourceMipCount = 7
    static let sourceTLUTCount = 0
    static let sourceTriangleCount: UInt32 = 339
    static let sourceTriangleSlotCount: UInt32 = 341
    static let sourcePacketSHA256 = "b73bb84432ad1cd2e821ccc339502a5900571643e0b956ca53d581a5abfee6c1"
    static let sourceHash = "c98da38e9b27fb6a5f02e1ff1dc28964384cd387e325af17b1804625b622a54c"
    static let sourceOrderHash: UInt64 = 0xbe5c_050b_adae_9682
    static let routeGoldenEyeNativeTick: UInt64 = 3_422

    let source: GoldenEyeSourceFrontendFrameV6
    let model: GoldenEyeSourceModelV6
    let scene: GoldenEyeGBISceneBuildResultV6
    let matrixFrame: GoldenEyeSourceFrontendMatrixFrameV6
    let modelTextureHandles: [UInt32]
    let materialTextureHandles: [UInt32]
    let textureSetups: [GoldenEyeSourceTextureSetupV6]
    let sourceCommandCount: UInt32
    let sourceVertexCount: UInt32
    let sourceMipCount: UInt32
    let omittedDegenerateTriangles: [OmittedDegenerateTriangleV6]
    let sourceOrderHash: UInt64
    let frameHash: UInt64

    enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case invalidRoot(String)
        case invalidRoute(String)
        case invalidModel(String)
        case invalidGraph(String)
        case invalidScene(String)
        case invalidMaterial(String)

        var description: String {
            switch self {
            case .invalidRoot(let value): return "GoldenEye logo root invalid: \(value)"
            case .invalidRoute(let value): return "GoldenEye logo route invalid: \(value)"
            case .invalidModel(let value): return "GoldenEye logo model invalid: \(value)"
            case .invalidGraph(let value): return "GoldenEye logo graph invalid: \(value)"
            case .invalidScene(let value): return "GoldenEye logo scene invalid: \(value)"
            case .invalidMaterial(let value): return "GoldenEye logo material invalid: \(value)"
            }
        }
    }

    /// Builds the first visible paired frame after the source gunbarrel
    /// transition.  The following even anchor is available through
    /// ``build(rootURL:nativeTick:)`` with `routeGoldenEyeNativeTick + 2`.
    static func build(
        rootURL: URL,
        nativeTick: UInt64 = routeGoldenEyeNativeTick + 1
    ) throws -> Self {
        guard nativeTick == routeGoldenEyeNativeTick + 1 ||
                nativeTick == routeGoldenEyeNativeTick + 2 else {
            throw Error.invalidRoute(
                "GoldenEye closure accepts paired ticks \(routeGoldenEyeNativeTick + 1) and \(routeGoldenEyeNativeTick + 2), got \(nativeTick)"
            )
        }

        let preparation: GoldenEyeSourceProductPreparationV6
        do {
            preparation = try GoldenEyeSourceProductPreparationV6.load(rootURL: rootURL)
        } catch {
            throw Error.invalidRoot(String(describing: error))
        }
        let model: GoldenEyeSourceModelV6
        do {
            model = try preparation.model(named: modelName)
        } catch {
            throw Error.invalidModel(String(describing: error))
        }
        try validateModel(model)

        let source = try makeSourceFrame(nativeTick: nativeTick)
        try validateSource(source, nativeTick: nativeTick)

        let matrixFrame: GoldenEyeSourceFrontendMatrixFrameV6
        do {
            matrixFrame = try GoldenEyeSourceFrontendMatricesV6.make(
                frame: source,
                model: model,
                modelName: modelName,
                viewportWidth: 440,
                viewportHeight: 330
            )
        } catch {
            throw Error.invalidGraph("matrix provider: \(error)")
        }
        let roles: [GoldenEyeSourceMatrixRoleSidecarV6]
        do {
            roles = try matrixFrame.resources.matrices.map {
                try GoldenEyeSourceMatrixRoleSidecarV6(
                    handle: $0.handle,
                    roleFlags: $0.roleFlags
                )
            }
        } catch {
            throw Error.invalidGraph("matrix roles: \(error)")
        }

        let compiled = GESourceModelCompilerV6.compile(model, modelName: modelName)
        guard compiled.status == .complete,
              compiled.diagnostics.isEmpty,
              let sourceScene = compiled.scene else {
            throw Error.invalidGraph("compiler diagnostics=\(compiled.diagnostics)")
        }
        guard sourceScene.visibleNodeIDs == Array(0..<UInt32(sourceNodeCount)),
              sourceScene.displayLists.map(\.id) == [0],
              sourceScene.commands.count == Int(sourceCommandCount) else {
            throw Error.invalidGraph(
                "visible=\(sourceScene.visibleNodeIDs) lists=\(sourceScene.displayLists.map(\.id)) commands=\(sourceScene.commands.count)"
            )
        }
        let textureSetups: [GoldenEyeSourceTextureSetupV6]
        do {
            textureSetups = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                modelName: modelName,
                model: model,
                catalog: preparation.catalog,
                compiledCommands: sourceScene.commands
            ).setups
        } catch {
            throw Error.invalidMaterial("texture setup resolver: \(error)")
        }

        let frameContext: GoldenEyeGBISceneFrameContextV6
        do {
            frameContext = try GoldenEyeGBISceneFrameContextV6(
                nativeTick: source.nativeTick,
                referenceTick: source.referenceTick,
                sourceTimer: source.sourceTimer,
                pairPhase: UInt32(source.nativeTick & 1),
                screen: source.screen,
                subphase: source.subphase,
                viewportWidth: matrixFrame.resources.viewportWidth,
                viewportHeight: matrixFrame.resources.viewportHeight
            )
        } catch {
            throw Error.invalidScene("frame context: \(error)")
        }
        let scene: GoldenEyeGBISceneBuildResultV6
        do {
            scene = try GoldenEyeGBISceneBuilderV6.build(
                model: model,
                modelName: modelName,
                matrices: matrixFrame.resources.matrices,
                viewports: matrixFrame.resources.viewports,
                matrixRoles: roles,
                frame: frameContext,
                textureSetups: textureSetups
            )
        } catch {
            throw Error.invalidScene("GBI builder: \(error)")
        }
        try validateScene(scene, model: model, sourceScene: sourceScene)
        try validateGoldenEyeCombiner(scene)
        let omittedDegenerateTriangles = try classifyOmittedDegenerateTriangles(
            model: model,
            sourceScene: sourceScene,
            scene: scene
        )

        let modelTextureHandles = model.textures.map(\.resourceHandle)
        let materialTextureHandles = scene.snapshot.drawCommands.map(\.resource_handle)
        guard modelTextureHandles.count == sourceTextureCount,
              Set(modelTextureHandles).count == sourceTextureCount,
              Set(materialTextureHandles).isSubset(of: Set(modelTextureHandles)),
              Set(materialTextureHandles) == Set(modelTextureHandles) else {
            throw Error.invalidMaterial(
                "model=\(modelTextureHandles) draws=\(materialTextureHandles)"
            )
        }
        let frameHash = hashFrame(
            source: source,
            scene: scene,
            matrixFrame: matrixFrame,
            materialTextureHandles: materialTextureHandles
        )
        return Self(
            source: source,
            model: model,
            scene: scene,
            matrixFrame: matrixFrame,
            modelTextureHandles: modelTextureHandles,
            materialTextureHandles: materialTextureHandles,
            textureSetups: textureSetups,
            sourceCommandCount: sourceCommandCount,
            sourceVertexCount: UInt32(model.vertices.count),
            sourceMipCount: UInt32(model.mips.count),
            omittedDegenerateTriangles: omittedDegenerateTriangles,
            sourceOrderHash: sourceOrderHash,
            frameHash: frameHash
        )
    }

    private static func validateModel(_ model: GoldenEyeSourceModelV6) throws {
        let counts = model.header.counts
        guard counts.nodes == sourceNodeCount,
              counts.displayLists == sourceDisplayListCount,
              counts.commands == Int(sourceCommandCount),
              counts.vertices == sourceVertexCount,
              counts.textures == sourceTextureCount,
              counts.mips == sourceMipCount,
              counts.tluts == sourceTLUTCount else {
            throw Error.invalidModel("counts=\(counts)")
        }
        let expectedSourceHash = stride(from: 0, to: sourceHash.count, by: 2).compactMap {
            UInt8(sourceHash.dropFirst($0).prefix(2), radix: 16)
        }
        let expectedPacketHash = stride(from: 0, to: sourcePacketSHA256.count, by: 2).compactMap {
            UInt8(sourcePacketSHA256.dropFirst($0).prefix(2), radix: 16)
        }
        guard model.header.sourceHash == expectedSourceHash,
              model.header.packetHash == expectedPacketHash else {
            throw Error.invalidModel("source/packet digest mismatch")
        }
        guard model.nodes.map(\.id) == Array(0..<UInt32(sourceNodeCount)),
              model.displayLists.map(\.id) == [0],
              model.textures.map(\.index) == [0, 1],
              model.mips.map(\.level).contains(0) else {
            throw Error.invalidModel("source ordering")
        }
        guard model.mips.count == sourceMipCount,
              model.mips.allSatisfy({ $0.resourceHandle != 0 && $0.payloadRecordID != 0 }) else {
            throw Error.invalidModel("mip provenance")
        }
    }

    private static func makeSourceFrame(
        nativeTick: UInt64
    ) throws -> GoldenEyeSourceFrontendFrameV6 {
        var authority: GoldenEyeSourceFrontendAuthorityV6
        do {
            authority = try GoldenEyeSourceFrontendAuthorityV6()
        } catch {
            throw Error.invalidRoute("authority init: \(error)")
        }
        var source: GoldenEyeSourceFrontendFrameV6?
        source = nil
        for tick in UInt64(1)...nativeTick {
            let timeline: GoldenEyeSourceFrontendTimelineV6
            do {
                timeline = try GoldenEyeSourceFrontendTimelineV6(nativeTick: tick)
            } catch {
                throw Error.invalidRoute("timeline \(tick): \(error)")
            }
            // The source gunbarrel callback owns the transition through the
            // 3,414 switch anchor.  Once the source has entered GoldenEye,
            // acknowledge its draw request with the exact model/operation;
            // this keeps the visible logo frame free of a synthetic result.
            let model: UInt32
            let operation: UInt32
            let flags: UInt32
            if tick >= routeGoldenEyeNativeTick + 1 {
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GOLDENEYELOGO)
                operation = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW)
                flags = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED)
            } else {
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL)
                operation = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK)
                flags = UInt32(
                    GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_BLOOD_COMPLETE |
                        GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED
                )
            }
            do {
                source = try authority.step(
                    timeline,
                    controllerCount: 1,
                    clockTimer: 1,
                    focused: true,
                    controllerConnected: true,
                    synthetic: true,
                    modelResultModel: model,
                    modelResultOperation: operation,
                    modelResultFlags: flags
                )
            } catch {
                throw Error.invalidRoute("tick \(tick): \(error)")
            }
        }
        guard let source else { throw Error.invalidRoute("missing terminal source frame") }
        return source
    }

    private static func validateSource(
        _ source: GoldenEyeSourceFrontendFrameV6,
        nativeTick: UInt64
    ) throws {
        guard source.nativeTick == nativeTick,
              source.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE),
              source.modelEvents.contains(where: {
                  $0.model == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GOLDENEYELOGO) &&
                  $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW) &&
                  $0.resultFlags & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED) != 0
              }),
              source.renderEvents.contains(where: {
                  $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CLEAR_BLACK)
              }),
              source.diagnosticEvents.isEmpty else {
            throw Error.invalidRoute(
                "screen=\(source.screen) model=\(source.modelEvents) diagnostics=\(source.diagnosticEvents.count)"
            )
        }
    }

    private static func validateScene(
        _ scene: GoldenEyeGBISceneBuildResultV6,
        model: GoldenEyeSourceModelV6,
        sourceScene: GESourceSceneV6
    ) throws {
        guard scene.packetCommandCount == sourceCommandCount + 2,
              scene.packetListCount == UInt32(sourceDisplayListCount + 1),
              scene.packetVertexCount == UInt32(sourceVertexCount),
              scene.packetImageCount == UInt32(sourceTextureCount),
              scene.commandCount == sourceCommandCount + 2,
              scene.decoderUnsupportedCount == 0,
              scene.sourceTriangleSlotCount == sourceTriangleSlotCount,
              scene.triangleCount == sourceTriangleCount,
              scene.snapshot.vertices.count == Int(scene.triangleCount * 3),
              scene.snapshot.summary.unsupported_visible_count == 0,
              scene.unsupportedVisibleCount == 0,
              scene.projectionConsumption.isComplete,
              scene.projectionConsumption.consumedDrawCount == scene.projectionConsumption.requiredDrawCount,
              scene.sourceCommandWordHash != 0,
              scene.packetSourceCommandWordHash != 0,
              sourceScene.commands.count == Int(sourceCommandCount),
              model.vertices.count == sourceVertexCount else {
            throw Error.invalidScene(
                "packet=\(scene.packetCommandCount)/\(scene.packetListCount) images=\(scene.packetImageCount) commands=\(scene.commandCount) triangles=\(scene.triangleCount)/\(scene.sourceTriangleSlotCount) vertices=\(scene.snapshot.vertices.count) unsupported=\(scene.unsupportedVisibleCount) reasons=\(scene.unsupportedReasons.prefix(4))"
            )
        }
    }

    private static func validateGoldenEyeCombiner(
        _ scene: GoldenEyeGBISceneBuildResultV6
    ) throws {
        let expectedCycle0: [UInt32] = [
            UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL1),
            UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0),
            UInt32(GE_SOURCE_COMBINER_V6_KEY_LOD_FRACTION),
            UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0),
        ]
        let expectedCycle1: [UInt32] = [
            UInt32(GE_SOURCE_COMBINER_V6_KEY_COMBINED),
            UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO),
            UInt32(GE_SOURCE_COMBINER_V6_KEY_SHADE),
            UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO),
        ]
        guard scene.snapshot.renderStates.count == 2 else {
            throw Error.invalidMaterial("expected exactly two GoldenEye material states")
        }
        for state in scene.snapshot.renderStates {
            let cycle0Color = [
                state.cycle0_color_a, state.cycle0_color_b,
                state.cycle0_color_c, state.cycle0_color_d,
            ]
            let cycle1Color = [
                state.cycle1_color_a, state.cycle1_color_b,
                state.cycle1_color_c, state.cycle1_color_d,
            ]
            let cycle0Alpha = [
                state.cycle0_alpha_a, state.cycle0_alpha_b,
                state.cycle0_alpha_c, state.cycle0_alpha_d,
            ]
            let cycle1Alpha = [
                state.cycle1_alpha_a, state.cycle1_alpha_b,
                state.cycle1_alpha_c, state.cycle1_alpha_d,
            ]
            guard cycle0Color == expectedCycle0,
                  cycle1Color == expectedCycle1,
                  cycle0Alpha == expectedCycle0,
                  cycle1Alpha == expectedCycle1 else {
                throw Error.invalidMaterial(
                    "state 0x\(String(state.state_handle, radix: 16)) combiner c0=\(cycle0Color)/\(cycle0Alpha) c1=\(cycle1Color)/\(cycle1Alpha)"
                )
            }
        }
    }

    private static func classifyOmittedDegenerateTriangles(
        model: GoldenEyeSourceModelV6,
        sourceScene: GESourceSceneV6,
        scene: GoldenEyeGBISceneBuildResultV6
    ) throws -> [OmittedDegenerateTriangleV6] {
        var omitted: [OmittedDegenerateTriangleV6] = []
        for commandIndex in sourceScene.commands.indices {
            let command = sourceScene.commands[commandIndex]
            guard command.macro == "gsSP4Triangles" else { continue }
            let modelIndex = model.commands.firstIndex {
                $0.displayListID == command.displayListID && $0.ordinal == command.ordinal
            }
            guard let modelIndex else {
                throw Error.invalidScene("triangle command \(commandIndex) has no source row")
            }
            guard let encoded = GESourceModelCompilerV6.encodedWords(
                model: model,
                commandIndex: modelIndex
            ) else {
                throw Error.invalidScene("gsSP4Triangles source word \(modelIndex)")
            }
            let z = [
                encoded.word0 & 0xf,
                (encoded.word0 >> 4) & 0xf,
                (encoded.word0 >> 8) & 0xf,
                (encoded.word0 >> 12) & 0xf,
            ]
            let x = [
                encoded.word1 & 0xf,
                (encoded.word1 >> 8) & 0xf,
                (encoded.word1 >> 16) & 0xf,
                (encoded.word1 >> 24) & 0xf,
            ]
            let y = [
                (encoded.word1 >> 4) & 0xf,
                (encoded.word1 >> 12) & 0xf,
                (encoded.word1 >> 20) & 0xf,
                (encoded.word1 >> 28) & 0xf,
            ]
            for tupleIndex in 0..<4 {
                guard x[tupleIndex] == 0, y[tupleIndex] == 0, z[tupleIndex] == 0 else {
                    continue
                }
                let packetCommandIndex = UInt32(2 + commandIndex)
                let candidate = OmittedDegenerateTriangleV6(
                    sourceCommandIndex: UInt32(modelIndex),
                    packetByteOffset: packetCommandIndex * UInt32(MemoryLayout<GEGBISourceCommandV6>.size),
                    tupleIndex: UInt32(tupleIndex),
                    sourceVertexA: x[tupleIndex],
                    sourceVertexB: y[tupleIndex],
                    sourceVertexC: z[tupleIndex]
                )
                omitted.append(candidate)
            }
        }
        guard omitted.map(\.packetByteOffset) == [0x290, 0x400],
              omitted.map(\.sourceCommandIndex) == [80, 126],
              omitted.allSatisfy({
                  $0.sourceVertexA == 0 && $0.sourceVertexB == 0 && $0.sourceVertexC == 0
              }),
              omitted.allSatisfy({ candidate in
                  scene.decoderDraws.filter {
                      $0.source_command_offset == candidate.packetByteOffset
                  }.count == 3
              }),
              scene.sourceTriangleSlotCount == scene.triangleCount + UInt32(omitted.count) else {
            throw Error.invalidScene(
                "degenerate omission classification offsets=\(omitted.map { String(format: "0x%03x", $0.packetByteOffset) })"
            )
        }
        return omitted
    }

    private static func hashFrame(
        source: GoldenEyeSourceFrontendFrameV6,
        scene: GoldenEyeGBISceneBuildResultV6,
        matrixFrame: GoldenEyeSourceFrontendMatrixFrameV6,
        materialTextureHandles: [UInt32]
    ) -> UInt64 {
        var hash = source.summary.stateHash ^ source.summary.renderHash
        hash ^= source.summary.audioEventHash &* 0x9e37_79b9_7f4a_7c15
        hash ^= scene.snapshot.copiedRecordAggregateHash
        hash ^= matrixFrame.frameHash
        hash ^= sourceOrderHash
        for value in [source.nativeTick, source.referenceTick, source.nativeTick & 1, scene.packetCommandWordHash] {
            hash = (hash ^ value) &* 1_099_511_628_211
        }
        for handle in materialTextureHandles {
            hash = (hash ^ UInt64(handle)) &* 1_099_511_628_211
        }
        return hash == 0 ? 1 : hash
    }
}
