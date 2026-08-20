#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import CryptoKit
import Foundation

struct GoldenEyeLegalTextPlacementV6: Sendable, Equatable {
    let textID: UInt32
    let x: Int32
    let y: Int32
    let flags: UInt32
    let sequence: UInt64
}

struct GoldenEyeLegalTextPacketV6: Sendable, Equatable {
    let sourceEvents: [GoldenEyeLegalTextPlacementV6]
    let glyphs: [GoldenEyeSource2DGlyphV6]
    let sourceEventHash: UInt64
    let glyphPacketHash: UInt64
}

/// A complete, immutable Legal source frame.  This is deliberately a
/// value-only handoff: the source event batch, model scene, material order,
/// and Zurich glyph packet remain independently inspectable by the renderer
/// and by the headless manifest test.
@available(macOS 26.0, *)
struct GoldenEyeLegalFrameV6: @unchecked Sendable {
    let source: GoldenEyeSourceFrontendFrameV6
    let scene: GoldenEyeGBISceneBuildResultV6
    let text: GoldenEyeLegalTextPacketV6
    let modelTextureHandles: [UInt32]
    let materialTextureHandles: [UInt32]
    let sourceCommandCount: UInt32
    let sourceTriangleCount: UInt32
    let viewport: GoldenEyeGBIViewportResourceV6
    let matrix: GoldenEyeGBIMatrixResourceV6
    let sourceMatrices: [GoldenEyeGBIMatrixResourceV6]
    let projectionConsumption: GoldenEyeGBIProjectionConsumptionEvidenceV6
    let logicalWidth: UInt32
    let logicalHeight: UInt32
    let frameHash: UInt64

    static let legalTextIDs: [UInt32] = Array(7...18)
    static let legalTextX: [Int32] = [220, 34, 226, 226, 226, 226, 227, 219, 60, 60, 99, 80]
    static let legalTextY: [Int32] = [30, 83, 84, 97, 110, 122, 134, 211, 169, 201, 266, 280]
    static let legalModelPacketSHA256 = "da42f17da9654a83a7c0a7ab3fd3233cc6892434c07cd593227932fb2e545f22"
    static let sourceCommandCount: UInt32 = 58
    static let sourceTriangleCount: UInt32 = 12
    private static let sourceFontFlag: UInt32 = 1 << 0
    private static let centeredTextFlag: UInt32 = 1 << 1

    enum Error: Swift.Error, CustomStringConvertible, Sendable, Equatable {
        case invalidSource(String)
        case invalidModel(String)
        case invalidScene(String)
        case invalidText(String)
        case invalidMaterial(String)
        case invalidMatrix(String)

        var description: String {
            switch self {
            case .invalidSource(let value): return "Legal source frame invalid: " + value
            case .invalidModel(let value): return "Legal source model invalid: " + value
            case .invalidScene(let value): return "Legal source scene invalid: " + value
            case .invalidText(let value): return "Legal source text invalid: " + value
            case .invalidMaterial(let value): return "Legal source material order invalid: " + value
            case .invalidMatrix(let value): return "Legal source matrix invalid: " + value
            }
        }
    }

    /// Build tick one, the first native half-step.  Legal has no autonomous
    /// timer advance at this point, but the source still emits its complete
    /// model/text/render batch, making this a stable visible-frame fixture.
    static func build(rootURL: URL, nativeTick: UInt64 = 1) throws -> GoldenEyeLegalFrameV6 {
        guard nativeTick == 1 else {
            throw Error.invalidSource("the canonical Legal fixture starts at native tick one")
        }

        let preparation: GoldenEyeSourceProductPreparationV6
        do {
            preparation = try GoldenEyeSourceProductPreparationV6.load(rootURL: rootURL)
        } catch {
            throw Error.invalidModel("source preparation: " + String(describing: error))
        }
        let model: GoldenEyeSourceModelV6
        do {
            model = try preparation.model(named: "legalpage")
        } catch {
            throw Error.invalidModel(String(describing: error))
        }
        let packetHash = model.header.packetHash.map { String(format: "%02x", $0) }.joined()
        guard packetHash == legalModelPacketSHA256 else {
            throw Error.invalidModel("packet SHA-256 " + packetHash)
        }
        guard model.header.counts.commands == Int(sourceCommandCount),
              model.header.counts.vertices == 24,
              model.header.counts.textures == 5,
              model.header.counts.mips == 5,
              model.header.counts.tluts == 0 else {
            throw Error.invalidModel("counts " + String(describing: model.header.counts))
        }

        var authority: GoldenEyeSourceFrontendAuthorityV6
        do {
            authority = try GoldenEyeSourceFrontendAuthorityV6()
        } catch {
            throw Error.invalidSource("authority init: " + String(describing: error))
        }
        let source: GoldenEyeSourceFrontendFrameV6
        do {
            source = try authority.step(
                try GoldenEyeSourceFrontendTimelineV6(nativeTick: nativeTick),
                controllerCount: 1,
                clockTimer: 1,
                focused: true,
                controllerConnected: true,
                synthetic: true,
                modelResultModel: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE),
                modelResultOperation: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW),
                modelResultFlags: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED)
            )
        } catch {
            throw Error.invalidSource("authority step: " + String(describing: error))
        }
        try validateSource(source)

        let matrixProvider: GoldenEyeSourceFrontendMatrixProviderV6
        let frameResources: GoldenEyeSourceProductFrameResourcesV6
        do {
            matrixProvider = try GoldenEyeSourceFrontendMatrixProviderV6(
                preparation: preparation,
                viewportWidth: 440,
                viewportHeight: 330
            )
            frameResources = try matrixProvider.frameResources(for: source)
        } catch {
            throw Error.invalidMatrix("shared source matrix provider: " + String(describing: error))
        }
        guard frameResources.viewportWidth == 440,
              frameResources.viewportHeight == 330,
              frameResources.viewports.count == 1,
              frameResources.matrices.contains(where: {
                  $0.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.modelView != 0
              }),
              frameResources.matrices.contains(where: {
                  $0.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.projection != 0
              }) else {
            throw Error.invalidMatrix("shared provider did not return complete Legal roles")
        }
        guard let matrix = frameResources.matrices.first(where: {
            $0.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.modelView != 0
        }), let viewport = frameResources.viewports.first else {
            throw Error.invalidMatrix("shared provider model/viewport role")
        }
        let sourceMatrices = frameResources.matrices
        let matrixRoles = try sourceMatrices.map {
            try GoldenEyeSourceMatrixRoleSidecarV6(handle: $0.handle, roleFlags: $0.roleFlags)
        }

        let sourceCompilation = GESourceModelCompilerV6.compile(
            model,
            modelName: "legalpage"
        )
        guard sourceCompilation.status == .complete,
              sourceCompilation.diagnostics.isEmpty,
              let sourceScene = sourceCompilation.scene else {
            throw Error.invalidScene(
                "Legal texture setup source traversal: \(sourceCompilation.diagnostics)"
            )
        }
        let textureSetups: [GoldenEyeSourceTextureSetupV6]
        do {
            textureSetups = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                modelName: "legalpage",
                model: model,
                catalog: preparation.catalog,
                compiledCommands: sourceScene.commands
            ).setups
        } catch {
            throw Error.invalidScene("Legal texture setup resolver: \(error)")
        }
        guard !textureSetups.isEmpty else {
            throw Error.invalidScene("Legal texture setup resolver returned no setups")
        }

        let scene: GoldenEyeGBISceneBuildResultV6
        do {
            scene = try GoldenEyeGBISceneBuilderV6.build(
                model: model,
                modelName: "legalpage",
                matrices: frameResources.matrices,
                viewports: frameResources.viewports,
                matrixRoles: matrixRoles,
                frame: try GoldenEyeGBISceneFrameContextV6(
                    nativeTick: source.nativeTick,
                    referenceTick: source.referenceTick,
                    sourceTimer: source.sourceTimer,
                    pairPhase: UInt32(source.nativeTick & 1),
                    screen: source.screen,
                    subphase: source.subphase,
                    viewportWidth: frameResources.viewportWidth,
                    viewportHeight: frameResources.viewportHeight
                ),
                textureSetups: textureSetups
            )
        } catch {
            throw Error.invalidScene(String(describing: error))
        }
        guard scene.presentable,
              scene.unsupportedVisibleCount == 0,
              scene.decoderUnsupportedCount == 0,
              // The bounded packet adds one synthetic root call and one root
              // ENDDL around the 46 source display-list words.  The source
              // command count remains the model's exact 46-word count.
              scene.packetCommandCount == sourceCommandCount + 2,
              scene.triangleCount == sourceTriangleCount,
              scene.snapshot.vertices.count == Int(sourceTriangleCount * 3),
              scene.projectionConsumption.isComplete,
              scene.projectionConsumption.consumedDrawCount == scene.projectionConsumption.requiredDrawCount else {
            throw Error.invalidScene(
                "presentable=" + String(scene.presentable)
                    + " unsupported=" + String(scene.unsupportedVisibleCount)
                    + " decoderUnsupported=" + String(scene.decoderUnsupportedCount)
                    + " packetCommands=" + String(scene.packetCommandCount)
                    + " triangles=" + String(scene.triangleCount)
                    + " vertices=" + String(scene.snapshot.vertices.count)
                    + " projectionComplete=" + String(scene.projectionConsumption.isComplete)
                    + " reasons=" + String(describing: scene.unsupportedReasons.prefix(4))
            )
        }

        let modelTextureHandles = model.textures.map(\.resourceHandle)
        guard modelTextureHandles.count == 5,
              Set(modelTextureHandles).count == 5 else {
            throw Error.invalidMaterial("the five legal texture handles are not unique")
        }
        let materialTextureHandles = scene.snapshot.drawCommands.map(\.resource_handle)
        guard materialTextureHandles.first == 0 else {
            throw Error.invalidMaterial("the first source primitive material changed order")
        }
        let texturedMaterialHandles = Set(materialTextureHandles.dropFirst())
        guard texturedMaterialHandles.count == 5,
              Set(modelTextureHandles) == texturedMaterialHandles else {
            throw Error.invalidMaterial(
                "draw material handles " + String(describing: materialTextureHandles)
                    + " do not preserve all five textured source material changes"
            )
        }

        let assets: GoldenEyeSource2DAssetsV6
        do {
            assets = try GoldenEyeSource2DAssetsV6(catalog: preparation.catalog, requiredIcons: [])
        } catch {
            throw Error.invalidText("2D asset preparation: " + String(describing: error))
        }
        let lowerer = GoldenEyeSource2DLowererV6(assets: assets)
        let textFrame: GoldenEyeSource2DFrameV6
        do {
            // `validateSource` below proves these are the source event values.
            // The lowerer’s no-event form uses the same source placements and
            // keeps the canonical centered first line while the event-aware
            // API is being closed over in the renderer.
            textFrame = try lowerer.makeLegalFrame(
                nativeTick: source.nativeTick,
                sourceTimer: source.sourceTimer,
                textEvents: []
            )
        } catch {
            throw Error.invalidText("Zurich lowering: " + String(describing: error))
        }
        guard textFrame.unsupportedVisibleCount == 0,
              Set(textFrame.glyphs.map(\.stringID)) == Set(legalTextIDs),
              textFrame.glyphs.count > 100 else {
            throw Error.invalidText(
                "glyphs=" + String(textFrame.glyphs.count)
                    + " unsupported=" + String(textFrame.unsupportedVisibleCount)
            )
        }
        let placements = source.textEvents.map {
            GoldenEyeLegalTextPlacementV6(
                textID: $0.textID, x: $0.x, y: $0.y, flags: $0.flags, sequence: $0.sequence
            )
        }
        let text = GoldenEyeLegalTextPacketV6(
            sourceEvents: placements,
            glyphs: textFrame.glyphs,
            sourceEventHash: hashSourceText(placements),
            glyphPacketHash: hashGlyphs(textFrame.glyphs)
        )
        let frameHash = hashFrame(
            source: source,
            scene: scene,
            text: text,
            modelTextureHandles: modelTextureHandles,
            materialTextureHandles: materialTextureHandles
        )
        return GoldenEyeLegalFrameV6(
            source: source,
            scene: scene,
            text: text,
            modelTextureHandles: modelTextureHandles,
            materialTextureHandles: materialTextureHandles,
            sourceCommandCount: sourceCommandCount,
            sourceTriangleCount: sourceTriangleCount,
            viewport: viewport,
            matrix: matrix,
            sourceMatrices: sourceMatrices,
            projectionConsumption: scene.projectionConsumption,
            logicalWidth: 440,
            logicalHeight: 330,
            frameHash: frameHash
        )
    }

    private static func validateSource(_ source: GoldenEyeSourceFrontendFrameV6) throws {
        guard source.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL),
              source.summary.unsupportedCount == 0,
              source.modelEvents.count == 1,
              source.modelEvents[0].model == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE),
              source.modelEvents[0].operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW),
              source.modelEvents[0].resultFlags & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED) != 0 else {
            throw Error.invalidSource("Legal model event is absent or unsupported")
        }
        let expectedRender: [UInt32] = [
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_FRAME_BEGIN),
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CLEAR_BLACK),
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_SOURCE_TEXT),
        ]
        guard source.renderEvents.map(\.operation) == expectedRender,
              source.textEvents.count == legalTextIDs.count else {
            throw Error.invalidSource(
                "render order \(source.renderEvents.map { $0.operation }), text count \(source.textEvents.count)"
            )
        }
        for index in source.textEvents.indices {
            let event = source.textEvents[index]
            guard event.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL),
                  event.textID == legalTextIDs[index],
                  event.x == legalTextX[index],
                  event.y == legalTextY[index],
                  event.flags & sourceFontFlag != 0,
                  index != 0 || event.flags & centeredTextFlag != 0 else {
                throw Error.invalidSource("text event " + String(index) + " does not match front.c ordering")
            }
        }
    }

    private static func hashSourceText(_ values: [GoldenEyeLegalTextPlacementV6]) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for value in values {
            hash = (hash ^ UInt64(value.textID)) &* 1_099_511_628_211
            hash = (hash ^ UInt64(bitPattern: Int64(value.x))) &* 1_099_511_628_211
            hash = (hash ^ UInt64(bitPattern: Int64(value.y))) &* 1_099_511_628_211
            hash = (hash ^ UInt64(value.flags)) &* 1_099_511_628_211
            hash = (hash ^ value.sequence) &* 1_099_511_628_211
        }
        return hash
    }

    private static func hashGlyphs(_ values: [GoldenEyeSource2DGlyphV6]) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for value in values {
            for part in [
                UInt64(value.fontID), UInt64(value.fontRecordID), UInt64(value.glyphIndex),
                UInt64(value.character), UInt64(bitPattern: Int64(value.x)),
                UInt64(bitPattern: Int64(value.y)), UInt64(value.width), UInt64(value.height),
                UInt64(value.stringID), value.sequence,
            ] {
                hash = (hash ^ part) &* 1_099_511_628_211
            }
        }
        return hash
    }

    private static func hashFrame(
        source: GoldenEyeSourceFrontendFrameV6,
        scene: GoldenEyeGBISceneBuildResultV6,
        text: GoldenEyeLegalTextPacketV6,
        modelTextureHandles: [UInt32],
        materialTextureHandles: [UInt32]
    ) -> UInt64 {
        var hash = source.summary.stateHash ^ source.summary.renderHash
        hash ^= source.summary.textHash &* 0x9e37_79b9_7f4a_7c15
        hash ^= scene.snapshot.copiedRecordAggregateHash
        hash ^= text.sourceEventHash &* 0x517c_c1b7_2722_0a95
        hash ^= text.glyphPacketHash
        for handle in modelTextureHandles + materialTextureHandles { hash = (hash ^ UInt64(handle)) &* 1_099_511_628_211 }
        return hash == 0 ? 1 : hash
    }
}
