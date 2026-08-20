#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

/// The source-complete Nintendo title frame used by the Nintendo closure
/// lane.  It is intentionally separate from the Legal fixture: Nintendo is
/// a 42-node BSP graph with 23 display lists and a single I8 texture, so a
/// Legal-sized synthetic/root list cannot prove this screen.
@available(macOS 26.0, *)
struct GoldenEyeNintendoFrameV6: @unchecked Sendable {
    static let modelName = "nintendologo"
    static let sourceNodeCount = 42
    static let sourceDisplayListCount = 23
    static let sourceCommandCount: UInt32 = 821
    static let sourceVertexCount = 1_363
    static let sourceTriangleCount: UInt32 = 1_021
    static let sourceTextureCount = 1
    static let sourceOrderHash: UInt64 = 0x9cc6_2b91_3ce5_2e5b
    static let sourceSHA256 = "8e0e40946713203f1db3cda53167a86658aa2aa10eb00ae89d64aa52aedc35d9"
    static let renderedTriangleCount: UInt32 = 1_018

    /// The original gsSP4Triangles stream contains three zero-padded fourth
    /// slots.  They are retained in the source command manifest and counted
    /// in sourceTriangleCount, but the native GBI decoder correctly emits no
    /// draw for a (0,0,0) slot because all three indices name the same vertex.
    /// Packet offsets are byte offsets after the 24-command synthetic root
    /// prefix (23 DL calls plus one root ENDDL).
    static let suppressedDegeneratePrimitives: [(sourceCommandIndex: UInt32, packetByteOffset: UInt32, sourceLine: UInt32, semantic: String)] = [
        (740, 6_112, 2_937, "gsSP4Triangles(7,8,9,10,11,12,10,12,13,0,0,0)"),
        (766, 6_320, 2_963, "gsSP4Triangles(9,6,10,10,11,9,12,10,13,0,0,0)"),
        (784, 6_464, 2_981, "gsSP4Triangles(7,8,9,10,11,12,13,10,12,0,0,0)"),
    ]

    let source: GoldenEyeSourceFrontendFrameV6
    let model: GoldenEyeSourceModelV6
    let scene: GoldenEyeGBISceneBuildResultV6
    let matrixFrame: GoldenEyeSourceFrontendMatrixFrameV6
    let modelTextureHandles: [UInt32]
    let sourceOrderHash: UInt64
    let frameHash: UInt64

    enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case invalidRoot(String)
        case invalidSource(String)
        case invalidModel(String)
        case invalidGraph(String)
        case invalidScene(String)
        case invalidCadence(String)

        var description: String {
            switch self {
            case .invalidRoot(let value): return "Nintendo frame root invalid: \(value)"
            case .invalidSource(let value): return "Nintendo source frame invalid: \(value)"
            case .invalidModel(let value): return "Nintendo source model invalid: \(value)"
            case .invalidGraph(let value): return "Nintendo source graph invalid: \(value)"
            case .invalidScene(let value): return "Nintendo source scene invalid: \(value)"
            case .invalidCadence(let value): return "Nintendo cadence invalid: \(value)"
            }
        }
    }

    /// Build one complete Nintendo frame by replaying the source frontend
    /// from tick one.  Replaying from the initialized source state ensures
    /// the source-local timer and transition route are not guessed from the
    /// global reference tick.  `nativeTick` may be either an even source
    /// anchor or the odd paired render extension immediately after it.
    static func build(
        rootURL: URL,
        nativeTick: UInt64 = 590
    ) throws -> GoldenEyeNintendoFrameV6 {
        guard nativeTick > 0 else { throw Error.invalidCadence("tick starts at one") }
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

        var authority: GoldenEyeSourceFrontendAuthorityV6
        do {
            authority = try GoldenEyeSourceFrontendAuthorityV6()
        } catch {
            throw Error.invalidSource("authority init: \(error)")
        }

        var source: GoldenEyeSourceFrontendFrameV6?
        source = nil
        for tick in UInt64(1)...nativeTick {
            let frame: GoldenEyeSourceFrontendFrameV6
            do {
                frame = try authority.step(
                    try GoldenEyeSourceFrontendTimelineV6(nativeTick: tick),
                    controllerCount: 1,
                    clockTimer: 1,
                    focused: true,
                    controllerConnected: true,
                    synthetic: true,
                    modelResultModel: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NINTENDOLOGO),
                    modelResultOperation: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW),
                    modelResultFlags: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED)
                )
            } catch {
                throw Error.invalidSource("tick \(tick): \(error)")
            }
            source = frame
        }
        guard let source else { throw Error.invalidSource("missing terminal frame") }
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
        let matrixRoles: [GoldenEyeSourceMatrixRoleSidecarV6]
        do {
            matrixRoles = try matrixFrame.resources.matrices.map {
                try GoldenEyeSourceMatrixRoleSidecarV6(
                    handle: $0.handle,
                    roleFlags: $0.roleFlags
                )
            }
        } catch {
            throw Error.invalidGraph("matrix roles: \(error)")
        }

        let compiled = GESourceModelCompilerV6.compile(model, modelName: modelName)
        guard compiled.status == .complete, compiled.diagnostics.isEmpty,
              let sourceScene = compiled.scene else {
            throw Error.invalidGraph("compiler diagnostics=\(compiled.diagnostics)")
        }
        guard sourceScene.visibleNodeIDs == Array(0..<UInt32(sourceNodeCount)) else {
            throw Error.invalidGraph(
                "BSP traversal order=\(sourceScene.visibleNodeIDs)"
            )
        }
        guard sourceScene.displayLists.map(\.id) == Array(0..<UInt32(sourceDisplayListCount)) else {
            throw Error.invalidGraph(
                "display-list traversal order=\(sourceScene.displayLists.map(\.id))"
            )
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
                matrixRoles: matrixRoles,
                frame: frameContext
            )
        } catch {
            throw Error.invalidScene("GBI builder: \(error)")
        }
        try validateScene(scene, model: model, sourceScene: sourceScene)

        let modelTextureHandles = model.textures.map(\.resourceHandle)
        var frameHash = source.summary.stateHash ^ source.summary.renderHash
        frameHash ^= source.summary.audioEventHash &* 0x9e37_79b9_7f4a_7c15
        frameHash ^= scene.snapshot.copiedRecordAggregateHash
        frameHash ^= sourceScene.semanticHash
        for value in [source.nativeTick, source.referenceTick, source.nativeTick & 1, scene.packetCommandWordHash] {
            frameHash = (frameHash ^ value) &* 1_099_511_628_211
        }
        if frameHash == 0 { frameHash = 1 }
        return Self(
            source: source,
            model: model,
            scene: scene,
            matrixFrame: matrixFrame,
            modelTextureHandles: modelTextureHandles,
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
              counts.mips == 1,
              counts.tluts == 0 else {
            throw Error.invalidModel("counts=\(counts)")
        }
        for primitive in suppressedDegeneratePrimitives {
            let index = Int(primitive.sourceCommandIndex)
            guard index < model.commands.count,
                  model.commands[index].semantic == primitive.semantic,
                  let words = GESourceModelCompilerV6.encodedWords(model: model, commandIndex: index),
                  words.macro == "gsSP4Triangles",
                  words.arguments.suffix(3) == [0, 0, 0] else {
                throw Error.invalidModel(
                    "zero-padded primitive manifest mismatch at command \(primitive.sourceCommandIndex)"
                )
            }
        }
        let expectedSourceHash = stride(from: 0, to: sourceSHA256.count, by: 2).compactMap {
            UInt8(sourceSHA256.dropFirst($0).prefix(2), radix: 16)
        }
        guard model.header.sourceHash == expectedSourceHash else {
            throw Error.invalidModel("source SHA-256 mismatch")
        }
        guard model.textures.count == 1,
              model.textures[0].depth == 1,
              model.textures[0].width == 32,
              model.textures[0].height == 32,
              model.textures[0].mipCount == 1,
              model.textures[0].tlutIndex == GoldenEyeSourceModelV6.nullHandle else {
            throw Error.invalidModel("Nintendo must expose one 32x32 I8 texture without TLUT")
        }
        guard model.displayLists.map(\.id) == Array(0..<UInt32(sourceDisplayListCount)) else {
            throw Error.invalidModel("display-list ids are not source ordered")
        }
        guard model.nodes.map(\.id) == Array(0..<UInt32(sourceNodeCount)) else {
            throw Error.invalidModel("node ids are not source ordered")
        }
    }

    private static func validateSource(
        _ source: GoldenEyeSourceFrontendFrameV6,
        nativeTick: UInt64
    ) throws {
        guard source.nativeTick == nativeTick,
              source.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO),
              source.summary.unsupportedCount == 0,
              source.modelEvents.contains(where: {
                  $0.model == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NINTENDOLOGO) &&
                  $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW) &&
                  $0.resultFlags & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED) != 0
              }),
              source.renderEvents.contains(where: {
                  $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CLEAR_BLACK)
              }) else {
            throw Error.invalidSource(
                "screen=\(source.screen) modelEvents=\(source.modelEvents.count) renderEvents=\(source.renderEvents.map(\.operation))"
            )
        }
        let expectedPairPhase = nativeTick & 1
        guard source.nativeTick & 1 == expectedPairPhase else {
            throw Error.invalidCadence("pair phase")
        }
        let continuous = source.renderEvents.filter {
            $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CONTINUOUS_STATE)
                && ($0.flags & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_FLAG_Q16_VALUES)) != 0
        }
        let expectedContinuous: [UInt32] = nativeTick & 1 == 0 ? [] : [
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_CONTINUOUS_NINTENDO_ROTATION_SCALE),
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_CONTINUOUS_NINTENDO_AMBIENT)
        ]
        guard continuous.map(\.subphase) == expectedContinuous else {
            throw Error.invalidCadence(
                "Nintendo continuous packet count=\(continuous.count) subphases=\(continuous.map(\.subphase)) operations=\(source.renderEvents.map(\.operation)) flags=\(source.renderEvents.map(\.flags))"
            )
        }
    }

    private static func validateScene(
        _ scene: GoldenEyeGBISceneBuildResultV6,
        model: GoldenEyeSourceModelV6,
        sourceScene: GESourceSceneV6
    ) throws {
        // The synthetic root emits one DL call per source display list and
        // one root ENDDL before the 821 source words.
        let expectedPacketCommands = sourceCommandCount + UInt32(sourceDisplayListCount) + 1
        let suppressedOffsets = Set(
            suppressedDegeneratePrimitives.map(\.packetByteOffset)
        )
        let drawCountByOffset = scene.decoderDraws.reduce(into: [UInt32: Int]()) { counts, draw in
            counts[draw.source_command_offset, default: 0] += 1
        }
        guard scene.presentable,
              scene.unsupportedVisibleCount == 0,
              scene.decoderUnsupportedCount == 0,
              scene.packetCommandCount == expectedPacketCommands,
              scene.packetListCount == UInt32(sourceDisplayListCount + 1),
              scene.packetVertexCount == UInt32(sourceVertexCount),
              scene.packetImageCount == 1,
              scene.commandCount == expectedPacketCommands,
              scene.sourceTriangleSlotCount == sourceTriangleCount,
              scene.triangleCount == renderedTriangleCount,
              scene.decoderDraws.count == Int(renderedTriangleCount),
              scene.snapshot.vertices.count == Int(renderedTriangleCount * 3),
              scene.snapshot.drawCommands.count > 0,
              scene.snapshot.resources.count == 2,
              scene.snapshot.summary.unsupported_visible_count == 0,
              scene.projectionConsumption.isComplete,
              scene.projectionConsumption.consumedDrawCount == scene.projectionConsumption.requiredDrawCount,
              scene.sourceCommandWordHash != 0,
              scene.packetSourceCommandWordHash != 0,
              suppressedOffsets.allSatisfy({ drawCountByOffset[$0] == 3 }) else {
            throw Error.invalidScene(
                "presentable=\(scene.presentable) decoderUnsupported=\(scene.decoderUnsupportedCount) packet=\(scene.packetCommandCount)/\(scene.packetListCount) image=\(scene.packetImageCount) command=\(scene.commandCount)/\(expectedPacketCommands) source=\(sourceScene.commands.count) slots=\(scene.sourceTriangleSlotCount) triangles=\(scene.triangleCount) draws=\(scene.decoderDraws.count) vertices=\(scene.snapshot.vertices.count) resources=\(scene.snapshot.resources.count) summaryUnsupported=\(scene.snapshot.summary.unsupported_visible_count) proj=\(scene.projectionConsumption.consumedDrawCount)/\(scene.projectionConsumption.requiredDrawCount) projComplete=\(scene.projectionConsumption.isComplete) sourceHash=\(scene.sourceCommandWordHash) packetSourceHash=\(scene.packetSourceCommandWordHash) suppressedCounts=\(suppressedDegeneratePrimitives.map { drawCountByOffset[$0.packetByteOffset] ?? 0 }) unsupported=\(scene.unsupportedVisibleCount)"
            )
        }
        guard scene.sourceTriangleSlotCount - scene.triangleCount == UInt32(suppressedDegeneratePrimitives.count) else {
            throw Error.invalidScene("unexpected source/decoded triangle gap")
        }
        guard sourceScene.commands.count == Int(sourceCommandCount),
              sourceScene.visibleNodeIDs == Array(0..<UInt32(sourceNodeCount)),
              sourceScene.displayLists.count == sourceDisplayListCount,
              model.textures.count == 1 else {
            throw Error.invalidGraph("source scene counts/order changed")
        }
    }
}
