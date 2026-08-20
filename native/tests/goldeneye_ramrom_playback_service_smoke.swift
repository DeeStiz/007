import Foundation

@main
struct GoldenEyeRamRomPlaybackServiceSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("usage: goldeneye_ramrom_playback_service_smoke /absolute/boot-asset-root")
        }
        let assetRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let catalog = try GoldenEyeRamRomRouteCatalog.parsed(assetRoot: assetRoot)
        guard let route = catalog.entries.first else {
            preconditionFailure("catalog must contain Dam 1")
        }
        let request = GoldenEyeRamRomLaunchRequest(
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

        try checkAlignmentAndDiagnostic(assetRoot: assetRoot, request: request)
        try checkRealInputAbort(assetRoot: assetRoot, request: request)
        try checkCompleteRestore(assetRoot: assetRoot, request: request)
        print("goldeneye_ramrom_playback_service_smoke: PASS")
    }

    private static func makeService(assetRoot: URL) -> GoldenEyeRamRomPlaybackService {
        GoldenEyeRamRomPlaybackService(assetRoot: assetRoot)
    }

    private static func checkAlignmentAndDiagnostic(
        assetRoot: URL,
        request: GoldenEyeRamRomLaunchRequest
    ) throws {
        let service = makeService(assetRoot: assetRoot)
        let begin = try service.begin(request: request, atNativeTick: 10)
        precondition(begin.kind == .stageLoadUnsupported)
        precondition(begin.diagnosticCode == UInt32(GE_RAMROM_PLAYBACK_DIAGNOSTIC_STAGE_UNSUPPORTED))
        precondition(service.stageLoadDiagnostic()?.kind == .stageLoadUnsupported)
        let beforeStart = try service.step(nativeTick: 10, input: GoldenEyeRamRomServiceInput())
        let oddBeforeStart = try service.step(nativeTick: 11, input: GoldenEyeRamRomServiceInput())
        precondition(beforeStart == nil)
        precondition(oddBeforeStart == nil)
        let first = try service.step(nativeTick: 12, input: GoldenEyeRamRomServiceInput())
        precondition(first?.kind == .sample)
        precondition(first?.nativeTick == 12)
        precondition(first?.referenceTick == 0)
        precondition(first?.pairPhase == 0)
        let odd = try service.step(nativeTick: 13, input: GoldenEyeRamRomServiceInput())
        precondition(odd?.kind == GoldenEyeRamRomPlaybackEventKind.none)
        precondition(odd?.pairPhase == 1)
    }

    private static func checkRealInputAbort(
        assetRoot: URL,
        request: GoldenEyeRamRomLaunchRequest
    ) throws {
        let service = makeService(assetRoot: assetRoot)
        _ = try service.begin(request: request, atNativeTick: 20)
        let input = GoldenEyeRamRomServiceInput(
            pressedButtons: 1 << 10,
            sourceMask: UInt32(GE_RAMROM_PLAYBACK_INPUT_CONTROLLER)
        )
        let fade = try service.step(nativeTick: 22, input: input)
        precondition(fade?.kind == .fadeToTitle)
        precondition(fade?.isRealInputAbort == true)
        let returned = try service.step(nativeTick: 23, input: GoldenEyeRamRomServiceInput())
        precondition(returned?.kind == .returnToTitle)
        precondition(service.isActive == false)
        precondition(service.takeRestoreSnapshot() != nil)
    }

    private static func checkCompleteRestore(
        assetRoot: URL,
        request: GoldenEyeRamRomLaunchRequest
    ) throws {
        let service = makeService(assetRoot: assetRoot)
        _ = try service.begin(request: request, atNativeTick: 0)
        var sawFade = false
        var sawReturn = false
        var sampleCount: UInt32 = 0
        for tick in UInt64(0)..<UInt64(5_000) {
            guard let event = try service.step(
                nativeTick: tick,
                input: GoldenEyeRamRomServiceInput()
            ) else { continue }
            if event.kind == .sample { sampleCount += 1 }
            if event.kind == .fadeToTitle { sawFade = true }
            if event.kind == .returnToTitle {
                sawReturn = true
                break
            }
        }
        precondition(sawFade && sawReturn)
        precondition(sampleCount == request.recordCount)
        guard let restore = service.takeRestoreSnapshot() else {
            preconditionFailure("completed RAMROM must expose restore snapshot")
        }
        precondition(restore.demoID == UInt32(request.demoID))
        precondition(restore.stageID == request.stageID)
        precondition(restore.saveData.count == Int(GE_RAMROM_V5_SAVE_BYTES))
        precondition(restore.saveHash != 0)
        precondition(service.isActive == false)
    }
}
