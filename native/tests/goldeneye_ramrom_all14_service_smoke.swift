import Foundation

@available(macOS 27.0, *)
@main
struct GoldenEyeRamRomAll14ServiceSmoke {
    private struct RunResult: Equatable {
        let demoID: UInt32
        let stageID: UInt32
        let packetCount: UInt32
        let recordCount: UInt32
        let sampleCount: UInt32
        let terminalTick: UInt64
        let recordingHash: UInt64
        let rngHash: UInt64
        let finalStateHash: UInt64
        let restoreRegisterHash: UInt64
        let restoreSaveHash: UInt64
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("usage: goldeneye_ramrom_all14_service_smoke /absolute/boot-asset-root")
        }
        let assetRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let catalog = try GoldenEyeRamRomRouteCatalog.parsed(assetRoot: assetRoot)
        precondition(catalog.isComplete)
        precondition(catalog.entries.count == GoldenEyeRamRomRouteCatalog.sourceAssetNames.count)

        var firstResults: [UInt8: RunResult] = [:]
        var secondResults: [UInt8: RunResult] = [:]
        for pass in 0..<2 {
            for route in catalog.entries {
                let result = try runToTitle(assetRoot: assetRoot, route: route)
                if pass == 0 {
                    firstResults[route.demoID] = result
                } else {
                    precondition(secondResults[route.demoID] == nil)
                    secondResults[route.demoID] = result
                    precondition(firstResults[route.demoID] == result)
                }
            }
        }
        precondition(firstResults.count == 14)
        precondition(secondResults.count == 14)

        var abortCount = 0
        for route in catalog.entries {
            try runAbortAndRestore(assetRoot: assetRoot, route: route)
            abortCount += 1
        }

        var aggregate = UInt64(1469598103934665603)
        for result in firstResults.values.sorted(by: { $0.demoID < $1.demoID }) {
            let words: [UInt64] = [
                UInt64(result.demoID), UInt64(result.stageID), UInt64(result.packetCount),
                UInt64(result.recordCount), UInt64(result.sampleCount),
                result.terminalTick, result.recordingHash, result.rngHash,
                result.finalStateHash, result.restoreRegisterHash,
                result.restoreSaveHash,
            ]
            for word in words {
                aggregate = mix(aggregate, word)
            }
        }
        print(
            "goldeneye_ramrom_all14_service_smoke: PASS demos=14 runs=28 " +
                "abort_restore=\(abortCount) aggregate=\(aggregate)"
        )
    }

    private static func mix(_ hash: UInt64, _ word: UInt64) -> UInt64 {
        var next = hash
        for shift in stride(from: 0, to: 64, by: 8) {
            next = (next ^ ((word >> UInt64(shift)) & 0xff)) &* 1099511628211
        }
        return next
    }

    private static func request(for route: GoldenEyeRamRomDemoRoute) -> GoldenEyeRamRomLaunchRequest {
        GoldenEyeRamRomLaunchRequest(
            catalogIndex: route.catalogIndex,
            demoID: route.demoID,
            stageID: route.stageID,
            variant: route.variant,
            controllerCount: route.controllerCount,
            totalTime60: route.totalTime60,
            packetCount: route.packetCount,
            recordCount: route.recordCount,
            recordingHash: route.recordingHash,
            rngHash: route.rngHash,
            assetName: route.assetName
        )
    }

    private static func runToTitle(
        assetRoot: URL,
        route: GoldenEyeRamRomDemoRoute
    ) throws -> RunResult {
        let service = GoldenEyeRamRomPlaybackService(assetRoot: assetRoot)
        let launch = request(for: route)
        let begin = try service.begin(request: launch, atNativeTick: 0)
        precondition(begin.kind == .stageLoadUnsupported)
        precondition(begin.diagnosticCode == UInt32(GE_RAMROM_PLAYBACK_DIAGNOSTIC_STAGE_UNSUPPORTED))
        precondition(service.stageLoadDiagnostic()?.kind == .stageLoadUnsupported)

        var sampleCount: UInt32 = 0
        var terminalTick: UInt64 = 0
        var sawFade = false
        var sawReturn = false
        let maximumTick = UInt64(route.recordCount) * 2 + 16
        for tick in UInt64(0)..<maximumTick {
            guard let event = try service.step(
                nativeTick: tick,
                input: GoldenEyeRamRomServiceInput()
            ) else { continue }
            precondition(event.demoID == UInt32(route.demoID))
            precondition(event.stageID == route.stageID)
            precondition(event.recordingHash == route.recordingHash)
            precondition(event.rngHash == route.rngHash)
            if event.kind == .sample { sampleCount += 1 }
            if event.kind == .fadeToTitle { sawFade = true }
            if event.kind == .returnToTitle {
                sawReturn = true
                terminalTick = tick
                break
            }
        }
        precondition(sawFade && sawReturn)
        precondition(sampleCount == route.recordCount)
        precondition(service.isActive == false)
        guard let restore = service.takeRestoreSnapshot() else {
            preconditionFailure("RAMROM service did not provide restore snapshot")
        }
        precondition(restore.demoID == UInt32(route.demoID))
        precondition(restore.stageID == route.stageID)
        precondition(restore.saveHash != 0)
        precondition(restore.registerHash != 0)
        precondition(restore.saveData.count == Int(GE_RAMROM_V5_SAVE_BYTES))

        return RunResult(
            demoID: UInt32(route.demoID),
            stageID: route.stageID,
            packetCount: route.packetCount,
            recordCount: route.recordCount,
            sampleCount: sampleCount,
            terminalTick: terminalTick,
            recordingHash: route.recordingHash,
            rngHash: route.rngHash,
            finalStateHash: service.lastEvent?.stateHash ?? 0,
            restoreRegisterHash: restore.registerHash,
            restoreSaveHash: restore.saveHash
        )
    }

    private static func runAbortAndRestore(
        assetRoot: URL,
        route: GoldenEyeRamRomDemoRoute
    ) throws {
        let service = GoldenEyeRamRomPlaybackService(assetRoot: assetRoot)
        let launch = request(for: route)
        _ = try service.begin(request: launch, atNativeTick: 10)
        let beforeStart = try service.step(
            nativeTick: 10,
            input: GoldenEyeRamRomServiceInput()
        )
        precondition(beforeStart == nil)
        let onOddTick = try service.step(
            nativeTick: 11,
            input: GoldenEyeRamRomServiceInput()
        )
        precondition(onOddTick == nil)
        let fade = try service.step(
            nativeTick: 12,
            input: GoldenEyeRamRomServiceInput(
                pressedButtons: 1 << 10,
                sourceMask: UInt32(GE_RAMROM_PLAYBACK_INPUT_CONTROLLER)
            )
        )
        precondition(fade?.isFadeToTitle == true)
        precondition(fade?.isRealInputAbort == true)
        let returned = try service.step(
            nativeTick: 13,
            input: GoldenEyeRamRomServiceInput()
        )
        precondition(returned?.isReturnToTitle == true)
        precondition(service.isActive == false)
        guard let restore = service.takeRestoreSnapshot() else {
            preconditionFailure("aborted RAMROM service did not provide restore snapshot")
        }
        precondition(restore.demoID == UInt32(route.demoID))
        precondition(restore.stageID == route.stageID)
        precondition(restore.saveHash != 0)
        precondition(restore.registerHash != 0)
    }
}
