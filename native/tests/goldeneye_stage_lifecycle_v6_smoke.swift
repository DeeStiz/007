import Foundation

@main
struct GoldenEyeStageLifecycleV6Smoke {
    static func main() throws {
        let rootPath = CommandLine.arguments.dropFirst().first
            ?? ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_STAGE_ASSET_ROOT"]
            ?? "build/native/stage-assets-image-decoder-v6"
        let catalog = try GoldenEyeStageAssetCatalog.load(
            stageAssetRoot: URL(fileURLWithPath: rootPath, isDirectory: true)
        )
        var lifecycle = try GoldenEyeStageLifecycleV6(catalog: catalog)
        let expectedStageIDs: [UInt32] = [33, 34, 35, 9, 20, 26, 25]
        precondition(lifecycle.stageIDs == expectedStageIDs.sorted())
        precondition(lifecycle.isIdle)
        precondition(lifecycle.catalogHash == catalog.catalogHash)
        precondition(lifecycle.decodedArenaBytes > 0)
        precondition(lifecycle.resourceViewHash != 0)

        let cold = try lifecycle.snapshot(stageID: expectedStageIDs[0])
        precondition(cold.phase == .unloaded)
        precondition(cold.loadCount == 0)
        precondition(cold.resourceHandles.count == 3)

        let loaded = try lifecycle.load(stageID: expectedStageIDs[0])
        precondition(loaded.phase == .loaded)
        precondition(loaded.loadCount == 1)
        precondition(loaded.sourceBytes > 0)
        precondition(loaded.decodedBytes > 0)
        let loadedViews = try lifecycle.resourceViews(stageID: expectedStageIDs[0])
        precondition(loadedViews.count == 3)

        do {
            _ = try lifecycle.load(stageID: expectedStageIDs[0])
            preconditionFailure("double stage load unexpectedly accepted")
        } catch GoldenEyeStageLifecycleErrorV6.invalidTransition {
        }

        let active = try lifecycle.activate(stageID: expectedStageIDs[0])
        precondition(active.phase == .active)
        do {
            try lifecycle.reset()
            preconditionFailure("active stage reset unexpectedly accepted")
        } catch GoldenEyeStageLifecycleErrorV6.activeStagesRemain(let stageIDs) {
            precondition(stageIDs == [expectedStageIDs[0]])
        }
        do {
            _ = try lifecycle.unload(stageID: expectedStageIDs[0])
            preconditionFailure("active stage unload unexpectedly accepted")
        } catch GoldenEyeStageLifecycleErrorV6.invalidTransition {
        }

        let deactivated = try lifecycle.deactivate(stageID: expectedStageIDs[0])
        precondition(deactivated.phase == .loaded)
        let unloaded = try lifecycle.unload(stageID: expectedStageIDs[0])
        precondition(unloaded.phase == .unloaded)
        precondition(lifecycle.isIdle)

        var replay = try GoldenEyeStageLifecycleV6(catalog: catalog)
        for stageID in expectedStageIDs {
            _ = try replay.load(stageID: stageID)
            _ = try replay.activate(stageID: stageID)
            _ = try replay.deactivate(stageID: stageID)
            _ = try replay.unload(stageID: stageID)
        }
        precondition(replay.isIdle)
        let replaySnapshot = try replay.snapshot(stageID: expectedStageIDs[0])
        precondition(replaySnapshot.stateHash == unloaded.stateHash)
        precondition(replay.resourceViewHash == lifecycle.resourceViewHash)

        do {
            _ = try lifecycle.snapshot(stageID: 0)
            preconditionFailure("unknown stage unexpectedly accepted")
        } catch GoldenEyeStageLifecycleErrorV6.unknownStage(let stageID) {
            precondition(stageID == 0)
        }

        print(
            "goldeneye_stage_lifecycle_v6_smoke: PASS "
                + "stages=\(lifecycle.stageIDs.count) "
                + "arenaBytes=\(lifecycle.decodedArenaBytes) "
                + "viewHash=\(lifecycle.resourceViewHash) "
                + "stateHash=\(unloaded.stateHash) "
                + "reset=failClosed"
        )
    }
}
