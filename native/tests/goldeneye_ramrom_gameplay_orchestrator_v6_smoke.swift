import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

@main
struct GoldenEyeRamRomGameplayOrchestratorV6Smoke {
    private struct Result: Equatable {
        let demoID: UInt32
        let samples: UInt32
        let stateHash: UInt64
        let playerHash: UInt64
        let cameraHash: UInt64
        let readinessMissing: [String]
        let positionChanged: Bool
        let aggregate: UInt64
    }

    private struct Prepared {
        let request: GoldenEyeRamRomLaunchRequest
        let recording: Data
        let pages: GoldenEyeRamRomPlayerCameraPagesV6
    }

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("usage: goldeneye_ramrom_gameplay_orchestrator_v6_smoke boot-root visible-root")
        }
        let bootRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let visibleRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let catalog = try GoldenEyeRamRomRouteCatalog.parsed(assetRoot: bootRoot)
        precondition(catalog.isComplete)
        let stageRootValue = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_STAGE_ASSET_ROOT"]
            ?? "build/native/stage-assets"
        let stageRoot = URL(fileURLWithPath: stageRootValue, isDirectory: true)
        let stageCatalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: stageRoot)
        let packets = try GoldenEyeStageScenePacket.loadAll(catalog: stageCatalog)
        let dependencies = try GoldenEyeStageSetupDependencyCatalogV6.load(stageAssetRoot: stageRoot)
        let sidecars = try GoldenEyeStageModelSidecarCatalogV6.load(stageAssetRoot: stageRoot)
        let visibleDependencies = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(rootURL: visibleRoot)
        let prepared = try catalog.entries.map { entry -> Prepared in
            let request = GoldenEyeRamRomLaunchRequest(
                catalogIndex: entry.catalogIndex, demoID: entry.demoID,
                stageID: entry.stageID, variant: entry.variant,
                controllerCount: entry.controllerCount, totalTime60: entry.totalTime60,
                packetCount: entry.packetCount, recordCount: entry.recordCount,
                recordingHash: entry.recordingHash, rngHash: entry.rngHash,
                assetName: entry.assetName
            )
            guard let packet = packets.first(where: { $0.stageID == entry.stageID }) else {
                throw GoldenEyeRamRomGameplayOrchestratorErrorV6.sourceNotReady(["stage_\(entry.stageID)"])
            }
            let sourcePages = try GoldenEyeRamRomGameplaySourcePagesV6.make(
                stagePacket: packet, dependencies: dependencies, sidecars: sidecars,
                visibleDependencies: visibleDependencies,
                slotNumber: sourceSlot(stageID: entry.stageID)
            )
            let recording = try Data(contentsOf: bootRoot.appendingPathComponent("ramrom", isDirectory: true)
                .appendingPathComponent(entry.assetName, isDirectory: false), options: [.mappedIfSafe])
            var header = GERamRomHeaderV5()
            let headerStatus = recording.withUnsafeBytes { raw -> UInt32 in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return UInt32(GE_STATUS_INVALID_ARGUMENT)
                }
                return ge_ramrom_v5_read_header(base, UInt32(recording.count), &header)
            }
            guard headerStatus == UInt32(GE_STATUS_OK) else {
                throw GoldenEyeRamRomGameplayOrchestratorErrorV6.cStatus(headerStatus, "header")
            }
            let style = withUnsafeBytes(of: header.controller_styles) {
                Array($0.bindMemory(to: UInt32.self)).first ?? 0
            }
            let options = try GoldenEyeRamRomSourceOptionStateV6(
                controlStyle: style, invertLook: 0, sourceHash: 0x4f5054494f4e5f55,
                provenance: ["RAMROM header controller_styles[0]", "src/game/options.c:104 default look option"]
            )
            let pages = try GoldenEyeRamRomPlayerCameraPageBuilderV6.make(
                stagePacket: packet, sourcePages: sourcePages, ramromHeader: header,
                optionState: options, demoID: UInt32(entry.demoID)
            )
            return Prepared(request: request, recording: recording, pages: pages)
        }
        let preparedByDemo = Dictionary(uniqueKeysWithValues: prepared.map { ($0.request.demoID, $0) })
        var first: [UInt32: Result] = [:]
        var second: [UInt32: Result] = [:]
        for pass in 0..<2 {
            for entry in catalog.entries {
                guard let prepared = preparedByDemo[entry.demoID] else { fatalError("missing prepared route") }
                let request = prepared.request
                let orchestrator = try GoldenEyeRamRomGameplayOrchestratorV6(
                    request: request, recording: prepared.recording, pages: prepared.pages,
                    atNativeTick: 0
                )
                var aggregate = UInt64(1_469_598_103_934_665_603)
                var finalFrame: GoldenEyeRamRomGameplayFrameV6?
                var initialPosition: GoldenEyeRamRomQ16Vector3V6?
                let tickCount = entry.demoID == 1
                    ? UInt64(entry.recordCount) * 2
                    : min(UInt64(entry.recordCount) * 2, 8)
                for tick in UInt64(0)..<max(2, tickCount) {
                    let frame = try orchestrator.step(nativeTick: tick)
                    finalFrame = frame
                    if initialPosition == nil {
                        initialPosition = frame.playerCamera.stageState.playerPositionQ16
                    }
                    aggregate = mix(aggregate, [
                        tick, frame.stateHash, frame.gameplaySnapshot.state_hash,
                        frame.playerCamera.playerHash, frame.playerCamera.cameraHash,
                        frame.playerCamera.roomHash, UInt64(frame.readiness.missingFields.count),
                    ])
                    if tick == 0 {
                        precondition(frame.readiness.playerCameraReady)
                        precondition(frame.readiness.gameplayReady)
                        precondition(frame.readiness.missingFields.contains("guard_door_authoritative_pages"))
                        precondition(frame.readiness.missingFields.contains("weapon_effect_authoritative_pages"))
                    }
                }
                guard let frame = finalFrame else { fatalError("orchestrator produced no frame") }
                let positionChanged = initialPosition != frame.playerCamera.stageState.playerPositionQ16
                if entry.demoID == 1 {
                    precondition(positionChanged, "Dam1 player/camera position did not move")
                }
                let result = Result(
                    demoID: UInt32(entry.demoID), samples: UInt32(tickCount / 2),
                    stateHash: frame.gameplaySnapshot.state_hash,
                    playerHash: frame.playerCamera.playerHash,
                    cameraHash: frame.playerCamera.cameraHash,
                    readinessMissing: frame.readiness.missingFields,
                    positionChanged: positionChanged,
                    aggregate: aggregate
                )
                if pass == 0 {
                    first[result.demoID] = result
                } else {
                    precondition(second[result.demoID] == nil)
                    second[result.demoID] = result
                }
            }
        }

        let dam = try require(first[1])
        let damPrepared = try require(preparedByDemo[1])
        let damRequest = damPrepared.request
        let restoreOwner = try GoldenEyeRamRomGameplayOrchestratorV6(
            request: damRequest, recording: damPrepared.recording,
            pages: damPrepared.pages, atNativeTick: 0
        )
        _ = try restoreOwner.step(nativeTick: 0)
        _ = try restoreOwner.step(nativeTick: 1)
        guard let restoreSnapshot = restoreOwner.takeRestoreSnapshot() else {
            fatalError("restore snapshot missing")
        }
        precondition(!restoreOwner.isActive)
        try restoreOwner.restore(restoreSnapshot)
        precondition(restoreOwner.isActive)
        let restored = try restoreOwner.step(nativeTick: restoreSnapshot.nativeTick + 1)
        precondition(restored.nativeTick == restoreSnapshot.nativeTick + 1)
        precondition(restored.playerCamera.stageState.stageID == damRequest.stageID)
        let environmentOwner = try GoldenEyeRamRomGameplayOrchestratorV6.fromEnvironment(
            request: damRequest, atNativeTick: 0
        )
        let environmentFrame = try environmentOwner.step(nativeTick: 0)
        precondition(environmentFrame.readiness.playerCameraReady)
        precondition(environmentFrame.readiness.gameplayReady)
        precondition(environmentFrame.readiness.missingFields.contains { $0.hasPrefix("guard_ai_") })
        precondition(environmentFrame.readiness.missingFields.contains {
            $0.hasPrefix("guard_pose_decoder.") ||
                $0.hasPrefix("guard_animationtable_payload.") ||
                $0 == "guard_animation_source_commands"
        })

        let aggregate = first.values.sorted { $0.demoID < $1.demoID }.reduce(UInt64(1_469_598_103_934_665_603)) {
            mix($0, [$1.stateHash, $1.playerHash, $1.cameraHash,
                     $1.positionChanged ? 1 : 0, $1.aggregate])
        }
        print(
                "goldeneye_ramrom_gameplay_orchestrator_v6_smoke: PASS demos=14 runs=28 " +
                "aggregate=\(aggregate) dam1State=\(dam.stateHash) " +
                "dam1Player=\(dam.playerHash) dam1Camera=\(dam.cameraHash) " +
                "dam1Moved=\(dam.positionChanged ? 1 : 0) restore=1"
        )
        _ = visibleRoot
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "gameplay-orchestrator-v6", code: 1) }
        return value
    }

    private static func sourceSlot(stageID: UInt32) -> UInt32 {
        switch stageID {
        case 9, 25: return 0
        default: return 1
        }
    }

    private static func mix(_ initial: UInt64, _ values: [UInt64]) -> UInt64 {
        values.reduce(initial) { hash, value in
            var result = hash
            for shift in stride(from: 0, to: 64, by: 8) {
                result = (result ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
            }
            return result
        }
    }
}
