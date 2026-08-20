import Foundation

@main
struct GoldenEyeStageTextureCatalogV6Smoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("usage: goldeneye_stage_texture_catalog_v6_smoke /absolute/stage-asset-root")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let catalog = try GoldenEyeStageTextureCatalogV6.load(stageAssetRoot: root)
        let setupDependencies = try GoldenEyeStageSetupDependencyCatalogV6.load(stageAssetRoot: root)
        precondition(setupDependencies.isReady)
        precondition(setupDependencies.propCount == 1_484)
        precondition(setupDependencies.characterCount == 299)
        let modelSidecars = try GoldenEyeStageModelSidecarCatalogV6.load(stageAssetRoot: root)
        precondition(modelSidecars.models.count == 179)
        precondition(modelSidecars.isComplete)
        precondition(catalog.textures.count == GoldenEyeStageTextureCatalogV6.expectedTextureCount)
        precondition(catalog.textures.filter { $0.palette != nil }.count == GoldenEyeStageTextureCatalogV6.expectedTLUTCount)

        let descriptors = catalog.uploadDescriptors()
        let plan = try GoldenEyeSourceTextureUploadPlanV6.make(descriptors: descriptors)
        precondition(plan.descriptors.count == 436)
        precondition(plan.levelRanges.count >= plan.descriptors.count)
        precondition(plan.paletteEvidence.count == 248)

        let stageCatalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: root)
        let scene = try GoldenEyeStageScenePacket.load(stageID: 33, catalog: stageCatalog)
        let placements = GoldenEyeStageModelPlacementCatalogV6.make(
            stageID: scene.stageID,
            setup: scene.setup,
            dependencies: setupDependencies,
            sidecars: modelSidecars
        )
        precondition(!placements.placements.isEmpty)
        precondition(placements.readyCount < placements.placements.count)
        if let firstReadyCandidate = placements.placements.first(where: { $0.modelIndex == 38 }) {
            print("placementProbe=modelIndex=38 name=\(firstReadyCandidate.modelName) sidecar=\(firstReadyCandidate.sidecarReady) matrix=\(firstReadyCandidate.matrixWords.count)")
        }
        guard let viewport = GoldenEyeProjectionV10.ViewportV10(
            drawableWidth: 440, drawableHeight: 330
        ), let projection = GoldenEyeProjectionV10.PacketV10(
            viewport: viewport,
            modelView: .identity,
            projection: .identity
        ) else {
            fatalError("could not construct canonical projection")
        }
        let packet = try GoldenEyeStageSourceEnvironmentDrawPacketBuilderV6.make(
            scene: scene, viewport: viewport, projection: projection
        )
        let material = try GoldenEyeStageSourceMaterialLowererV6.make(scene: scene)
        let snapshot = try GoldenEyeStageSourceSceneSnapshotAdapterV6.make(
            packet: packet,
            nativeTick: 2,
            materialPacket: material,
            stageTextureCatalog: catalog
        )
        precondition(!snapshot.resources.isEmpty)
        precondition(snapshot.resources.contains { $0.resource_kind == UInt32(GE_SOURCE_RESOURCE_V6_TEXTURE) })
        precondition(snapshot.drawCommands.contains { $0.resource_handle != 0 })
        let resources = snapshot.resourceByHandle
        for draw in snapshot.drawCommands where draw.resource_handle != 0 {
            precondition(resources[draw.resource_handle] != nil)
            precondition(draw.resource_handle & 0xFF00_0000 == GoldenEyeStageTextureCatalogV6.textureHandlePrefix)
            if let texture = catalog.textures.first(where: {
                $0.resourceHandle == draw.resource_handle
            }), texture.palette != nil {
                let paletteHandle = GoldenEyeStageTextureCatalogV6
                    .paletteResourceHandle(textureID: texture.textureID)
                precondition(paletteHandle & 0xFF00_0000 == 0xA900_0000)
                precondition(resources[paletteHandle]?.resource_kind ==
                             UInt32(GE_SOURCE_RESOURCE_V6_PALETTE))
            }
        }
        precondition(snapshot.summary.unsupported_visible_count > 0)
        print(
                "goldeneye_stage_texture_catalog_v6_smoke: PASS "
                + "textures=\(catalog.textures.count) tluts=\(catalog.textures.filter { $0.palette != nil }.count) bindings=\(catalog.bindingCount) bindingHash=\(catalog.bindingValidationHash) "
                + "levels=\(plan.levelRanges.count) resources=\(snapshot.resources.count) "
                + "boundDraws=\(snapshot.drawCommands.filter { $0.resource_handle != 0 }.count) "
                + "gpuRepresentable=\(catalog.isGPURepresentable ? 1 : 0) "
                + "unrepresentableMips=\(catalog.unrepresentableMipTextureCount) "
                + "unclassifiedVisibility=\(catalog.unclassifiedVisibilityTextureCount) "
                + "placements=\(placements.placements.count) placementReady=\(placements.readyCount) "
                + "placementSidecars=\(placements.placements.filter { $0.sidecarReady }.count) "
                + "unsupported=\(snapshot.summary.unsupported_visible_count)"
        )
    }
}
