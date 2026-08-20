import Foundation

@main
struct GoldenEyeStageModelSceneComposerV6Smoke {
    static func main() throws {
        guard CommandLine.arguments.count == 3 || CommandLine.arguments.count == 4 else {
            fatalError("usage: goldeneye_stage_model_scene_composer_v6_smoke /absolute/stage-root /absolute/visible-root [stage-id]")
        }
        let stageRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let visibleRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let stageID = CommandLine.arguments.count == 4
            ? UInt32(CommandLine.arguments[3]) ?? 33
            : 33
        let stageCatalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: stageRoot)
        let scene = try GoldenEyeStageScenePacket.load(stageID: stageID, catalog: stageCatalog)
        let textures = try GoldenEyeStageTextureCatalogV6.load(stageAssetRoot: stageRoot)
        let setupDependencies = try GoldenEyeStageSetupDependencyCatalogV6.load(stageAssetRoot: stageRoot)
        let sidecars = try GoldenEyeStageModelSidecarCatalogV6.load(stageAssetRoot: stageRoot)
        let visible = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(rootURL: visibleRoot)
        precondition(textures.isGPURepresentable)
        precondition(textures.allBindingsPrepared)
        precondition(textures.bindingCount == 3_575)

        let aliases = GoldenEyeStageModelSceneCompositionV6.textureDescriptors(
            models: sidecars.models,
            sidecars: sidecars,
            stageTextures: textures
        )
        precondition(!aliases.isEmpty)
        let aliasPlan = try GoldenEyeSourceTextureUploadPlanV6.make(descriptors: aliases)
        precondition(aliasPlan.descriptors.count == aliases.count)
        precondition(aliasPlan.levelRanges.count >= aliasPlan.descriptors.count)

        guard let viewport = GoldenEyeProjectionV10.ViewportV10(
            drawableWidth: 440, drawableHeight: 330
        ), let projection = GoldenEyeProjectionV10.PacketV10(
            viewport: viewport,
            modelView: .identity,
            projection: .identity
        ) else {
            fatalError("canonical stage projection fixture could not be constructed")
        }
        let environment = try GoldenEyeStageSourceEnvironmentDrawPacketBuilderV6.make(
            scene: scene,
            viewport: viewport,
            projection: projection
        )
        let material = try GoldenEyeStageSourceMaterialLowererV6.make(scene: scene)
        let placements = GoldenEyeStageModelPlacementCatalogV6.make(
            stageID: scene.stageID,
            setup: scene.setup,
            dependencies: setupDependencies,
            sidecars: sidecars,
            visibleDependencies: visible
        )
        precondition(placements.placements.count > 0)
        let propCount = placements.placements.filter { $0.kind == "prop" }.count
        let propReady = placements.placements.filter { $0.kind == "prop" && $0.isRenderable }.count
        let characterCount = placements.placements.filter { $0.kind == "character" }.count
        let characterReady = placements.placements.filter { $0.kind == "character" && $0.isRenderable }.count
        print("placementKinds=prop:\(propCount)/\(propReady),character:\(characterCount)/\(characterReady)")

        // The source matrix provider is used only to supply an explicit
        // projection/viewport fixture. The composer replaces one model-view
        // handle with each placement's copied setup matrix; it never infers a
        // stage camera from an identity fallback in the production seam.
        let candidate = placements.placements.first { placement in
            guard placement.kind == "prop", let model = sidecars.models[placement.modelName] else { return false }
            let compilation = GESourceModelCompilerV6.compile(model, modelName: placement.modelName)
            guard let scene = compilation.scene else { return false }
            return scene.commands.contains {
                guard $0.macro == "gsSPMatrix", let first = $0.arguments.first else { return false }
                switch first {
                case .handle(_, let value): return value != 0
                case .integer(let value): return value > 0
                default: return false
                }
            }
        }
        let frameResources: GoldenEyeSourceProductFrameResourcesV6?
        if let candidate,
           let model = sidecars.models[candidate.modelName],
           let compiled = GESourceModelCompilerV6.compile(model, modelName: candidate.modelName).scene,
           let firstMatrix = compiled.commands.first(where: { $0.macro == "gsSPMatrix" })?.arguments.first,
           let matrixHandle = matrixHandle(firstMatrix) {
            let input = try GoldenEyeSourceFrontendMatrixInputV6(
                screen: GoldenEyeSourceFrontendMatricesV6.screenLegal,
                nativeTick: 2, referenceTick: 1, sourceTimer: 0, pairPhase: 0
            )
            frameResources = try GoldenEyeSourceFrontendMatricesV6.make(
                input: input,
                modelMatrixHandle: matrixHandle,
                viewportWidth: 440,
                viewportHeight: 330
            ).resources
        } else {
            frameResources = nil
        }

        let result = try GoldenEyeStageModelSceneCompositionV6.make(
            stageScene: scene,
            environmentPacket: environment,
            materialPacket: material,
            sidecars: sidecars,
            setupDependencies: setupDependencies,
            stageTextures: textures,
            frameResources: frameResources,
            nativeTick: 2,
            demoID: 0,
            visibleDependencies: visible
        )
        precondition(result.placementCount == UInt32(placements.placements.count))
        precondition(propCount == propReady)
        precondition(result.drawablePlacementCount == UInt32(propCount))
        precondition(result.unsupportedMask == 0x38)
        precondition(result.snapshot.summary.unsupported_visible_count > 0)
        precondition(!result.isPresentable)
        precondition(result.categoryPackets.count == 16)
        precondition(result.categoryPackets.contains { $0.category == "hud" })
        print(
            "goldeneye_stage_model_scene_composer_v6_smoke: PASS stage=\(stageID) "
                + "textures=\(textures.textures.count) bindings=\(textures.bindingCount) aliases=\(aliases.count) "
                + "placements=\(result.placementCount) drawable=\(result.drawablePlacementCount) "
                + "unsupportedPlacements=\(result.unsupportedPlacementCount) unsupportedMask=0x\(String(result.unsupportedMask, radix: 16)) categories=\(result.categoryPackets.count) "
                + "sceneDraws=\(result.snapshot.drawCommands.count) presentable=\(result.isPresentable ? 1 : 0) "
                + "contiguousBatches=\(result.contiguousBatchCount) largestBatch=\(result.largestContiguousBatch) "
                + "compositionHash=\(result.compositionHash) failureCount=\(result.failureReasons.count) "
                + "failureSample=\(result.failureReasons.prefix(8).joined(separator: ";"))"
        )
    }

    private static func matrixHandle(_ value: GoldenEyeSourceModelV6.TokenValue) -> UInt32? {
        switch value {
        case .handle(_, let value): return value == 0 ? nil : value
        case .integer(let value): return value > 0 ? UInt32(value) : nil
        default: return nil
        }
    }
}
