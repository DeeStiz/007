import Foundation

@available(macOS 26.0, *)
@main
struct GoldenEyeSourceTitleRenderCacheV6Smoke {
    static func main() throws {
        let root = URL(
            fileURLWithPath: CommandLine.arguments.dropFirst().first
                ?? "build/native/source-frontend-v6",
            isDirectory: true
        )
        let preparation = try GoldenEyeSourceProductPreparationV6.load(rootURL: root)
        let cachedRouteNames = ["legalpage", "nintendologo", "goldeneyelogo", "rarewarelogo", "walletbond"]
        let routeKeys = cachedRouteNames.map { name in
            GoldenEyeSourceTitleRenderCacheV6.makeKey(
                model: try! preparation.model(named: name),
                modelName: name,
                screen: name == "walletbond" ? 5 : 0,
                switchInputs: [:]
            )
        }
        precondition(Set(routeKeys.map(\.modelName)).count == cachedRouteNames.count)
        let walletModel = try preparation.model(named: "walletbond")
        let walletA = GoldenEyeSourceTitleRenderCacheV6.makeKey(
            model: walletModel, modelName: "walletbond", screen: 5,
            switchInputs: [0x100: 1, 0x101: 0]
        )
        let walletB = GoldenEyeSourceTitleRenderCacheV6.makeKey(
            model: walletModel, modelName: "walletbond", screen: 5,
            switchInputs: [0x100: 2, 0x101: 0]
        )
        precondition(walletA != walletB, "save/switch route changes must invalidate the cache key")
        let saveA = GoldenEyeSourceTitleRenderCacheV6.makeKey(
            model: walletModel, modelName: "walletbond", screen: 5,
            switchInputs: [:], routeIdentity: 0x1111
        )
        let saveB = GoldenEyeSourceTitleRenderCacheV6.makeKey(
            model: walletModel, modelName: "walletbond", screen: 5,
            switchInputs: [:], routeIdentity: 0x2222
        )
        precondition(saveA != saveB, "save semantic changes must invalidate the cache key")
        let odd = try GoldenEyeGoldenEyeLogoFrameV6.build(
            rootURL: root,
            nativeTick: GoldenEyeGoldenEyeLogoFrameV6.routeGoldenEyeNativeTick + 1
        )
        let even = try GoldenEyeGoldenEyeLogoFrameV6.build(
            rootURL: root,
            nativeTick: GoldenEyeGoldenEyeLogoFrameV6.routeGoldenEyeNativeTick + 2
        )
        let compiled = GESourceModelCompilerV6.compile(
            odd.model,
            modelName: GoldenEyeGoldenEyeLogoFrameV6.modelName
        )
        guard compiled.status == .complete,
              compiled.diagnostics.isEmpty,
              let sourceScene = compiled.scene else {
            throw SmokeError("source topology did not compile")
        }
        let key = GoldenEyeSourceTitleRenderCacheV6.makeKey(
            model: odd.model,
            modelName: GoldenEyeGoldenEyeLogoFrameV6.modelName,
            screen: even.source.screen,
            switchInputs: [:]
        )
        let entry = GoldenEyeSourceTitleRenderCacheV6.makeEntry(
            key: key,
            scene: sourceScene,
            textureSetups: odd.textureSetups,
            result: odd.scene
        )
        let frame = try GoldenEyeGBISceneFrameContextV6(
            nativeTick: even.source.nativeTick,
            referenceTick: even.source.referenceTick,
            sourceTimer: even.source.sourceTimer,
            pairPhase: even.source.nativeTick & 1 == 0 ? 0 : 1,
            screen: even.source.screen,
            subphase: even.source.subphase,
            viewportWidth: even.matrixFrame.resources.viewportWidth,
            viewportHeight: even.matrixFrame.resources.viewportHeight
        )
        let reframed = try GoldenEyeSourceTitleRenderCacheV6.reframe(
            entry,
            model: even.model,
            modelName: GoldenEyeGoldenEyeLogoFrameV6.modelName,
            frame: frame,
            matrices: even.matrixFrame.resources.matrices,
            viewports: even.matrixFrame.resources.viewports
        )
        let direct = even.scene
        precondition(reframed.snapshot.summary.scene_hash == direct.snapshot.summary.scene_hash)
        precondition(reframed.snapshot.summary.render_hash == direct.snapshot.summary.render_hash)
        precondition(reframed.snapshot.summary.state_hash == direct.snapshot.summary.state_hash)
        precondition(reframed.snapshot.summary.frame_hash == direct.snapshot.summary.frame_hash)
        precondition(reframed.snapshot.transformHashes == direct.snapshot.transformHashes)
        precondition(reframed.snapshot.vertexHashes == direct.snapshot.vertexHashes)
        precondition(reframed.snapshot.indexHashes == direct.snapshot.indexHashes)
        precondition(reframed.snapshot.renderStateHashes == direct.snapshot.renderStateHashes)
        precondition(reframed.snapshot.drawCommandHashes == direct.snapshot.drawCommandHashes)
        precondition(reframed.snapshot.lightingFrameContext == direct.snapshot.lightingFrameContext)
        precondition(reframed.snapshot.copiedRecordAggregateHash == direct.snapshot.copiedRecordAggregateHash)
        precondition(
            GoldenEyeSourceTitleRenderCacheV6.frameFlagsForTesting(
                presentable: true, unsupportedVisibleCount: 1, pairPhase: 1
            ) & UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE) == 0,
            "unsupported cached results must not advertise PRESENTABLE"
        )
        let invalidResult = invalidating(odd.scene)
        do {
            _ = try GoldenEyeSourceSceneComposerV6.combine([invalidResult], frame: frame)
            preconditionFailure("composer must reject an unsupported input result")
        } catch is GoldenEyeSourceSceneComposerV6Error {
            // Expected fail-closed negative path.
        }

        var directDurations: [Double] = []
        var cachedDurations: [Double] = []
        for offset in 0..<20 {
            let tick = odd.source.nativeTick &+ UInt64(offset * 2)
            let context = try GoldenEyeGBISceneFrameContextV6(
                nativeTick: tick,
                referenceTick: tick >> 1,
                sourceTimer: 0,
                pairPhase: 0,
                screen: odd.source.screen,
                subphase: odd.source.subphase,
                viewportWidth: odd.matrixFrame.resources.viewportWidth,
                viewportHeight: odd.matrixFrame.resources.viewportHeight
            )
            let directStart = DispatchTime.now().uptimeNanoseconds
            _ = try GoldenEyeGBISceneBuilderV6.build(
                model: odd.model,
                modelName: GoldenEyeGoldenEyeLogoFrameV6.modelName,
                matrices: odd.matrixFrame.resources.matrices,
                viewports: odd.matrixFrame.resources.viewports,
                matrixRoles: try odd.matrixFrame.resources.matrices.map {
                    try GoldenEyeSourceMatrixRoleSidecarV6(handle: $0.handle, roleFlags: $0.roleFlags)
                },
                frame: context,
                textureSetups: odd.textureSetups
            )
            directDurations.append(Double(DispatchTime.now().uptimeNanoseconds - directStart) / 1_000_000.0)
            let cachedStart = DispatchTime.now().uptimeNanoseconds
            _ = try GoldenEyeSourceTitleRenderCacheV6.reframe(
                entry,
                model: odd.model,
                modelName: GoldenEyeGoldenEyeLogoFrameV6.modelName,
                frame: context,
                matrices: odd.matrixFrame.resources.matrices,
                viewports: odd.matrixFrame.resources.viewports
            )
            cachedDurations.append(Double(DispatchTime.now().uptimeNanoseconds - cachedStart) / 1_000_000.0)
        }
        let directP95 = percentile(directDurations, 0.95)
        let cachedP95 = percentile(cachedDurations, 0.95)
        if ProcessInfo.processInfo.environment["GE_CACHE_PERF_CHECK"] == "1" {
            precondition(cachedP95 < 8.33, "cached scene-build p95 must remain below one 120 Hz tick")
        }
        let directText = String(format: "%.3f", directP95)
        let cachedText = String(format: "%.3f", cachedP95)
        print("goldeneye-source-title-render-cache-v6: topology=\(entry.topology.snapshot.vertices.count)/\(entry.topology.snapshot.indices.count)/\(entry.topology.snapshot.drawCommands.count) frameHash=\(reframed.snapshot.summary.frame_hash) directP95Ms=\(directText) cachedP95Ms=\(cachedText) PASS")
    }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))
        return sorted[index]
    }

    private static func invalidating(
        _ result: GoldenEyeGBISceneBuildResultV6
    ) -> GoldenEyeGBISceneBuildResultV6 {
        GoldenEyeGBISceneBuildResultV6(
            snapshot: result.snapshot,
            packetDialect: result.packetDialect,
            packetCommandCount: result.packetCommandCount,
            packetListCount: result.packetListCount,
            packetVertexCount: result.packetVertexCount,
            packetImageCount: result.packetImageCount,
            sourceCommandWordHash: result.sourceCommandWordHash,
            packetCommandWordHash: result.packetCommandWordHash,
            packetSourceCommandWordHash: result.packetSourceCommandWordHash,
            textureSetups: result.textureSetups,
            vertexResourceTotal: result.vertexResourceTotal,
            vertexResourcePageCount: result.vertexResourcePageCount,
            vertexResourceManifestHash: result.vertexResourceManifestHash,
            projectionConsumption: result.projectionConsumption,
            decoderStatus: result.decoderStatus,
            decoderDraws: result.decoderDraws,
            stateWordEvidence: result.stateWordEvidence,
            decoderUnsupportedCount: result.decoderUnsupportedCount,
            unsupportedVisibleCount: 1,
            unsupportedReasons: ["negative smoke"],
            presentable: false,
            commandCount: result.commandCount,
            triangleCount: result.triangleCount,
            sourceTriangleSlotCount: result.sourceTriangleSlotCount,
            decoderStateCount: result.decoderStateCount,
            resourceCount: result.resourceCount,
            eventHash: result.eventHash,
            stateHash: result.stateHash,
            geometryModesByState: result.geometryModesByState,
            modelViewQ16ByState: result.modelViewQ16ByState,
            exactNodeTransformDrawCount: result.exactNodeTransformDrawCount,
            fallbackNodeTransformDrawCount: result.fallbackNodeTransformDrawCount,
            exactNodeTransformHandles: result.exactNodeTransformHandles
        )
    }

    private struct SmokeError: Error, CustomStringConvertible {
        let message: String
        init(_ message: String) { self.message = message }
        var description: String { message }
    }
}
