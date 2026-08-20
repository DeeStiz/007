import Foundation

@available(macOS 27.0, *)
@main
struct GoldenEyeStageGameplayRuntimeSmoke {
    private struct StageSpec {
        let id: UInt32
        let name: String
    }

    private static let stageSpecs: [StageSpec] = [
        StageSpec(id: 33, name: "Dam"),
        StageSpec(id: 34, name: "Facility"),
        StageSpec(id: 35, name: "Runway"),
        StageSpec(id: 9, name: "Bunker_I"),
        StageSpec(id: 20, name: "Silo"),
        StageSpec(id: 26, name: "Frigate"),
        StageSpec(id: 25, name: "Train"),
    ]

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(
                domain: "stage-gameplay-runtime", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "stage and boot asset roots required"]
            )
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let bootRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: root)
        let packets = try GoldenEyeStageScenePacket.loadAll(catalog: catalog)
        precondition(packets.count == stageSpecs.count)
        for spec in stageSpecs {
            guard let packet = packets.first(where: { $0.stageID == spec.id }) else {
                preconditionFailure("missing scene packet for \(spec.name)")
            }
            try checkStage(packet: packet)
        }
        try checkOneRamRomTrace(root: bootRoot, packets: packets)
        print(
            "goldeneye_stage_gameplay_runtime_smoke: PASS stages=7 " +
                "trace=1 diagnostics=effects,ai,weapons,collision"
        )
    }

    private static func checkStage(packet: GoldenEyeStageScenePacket) throws {
        let first = GoldenEyeStageGameplayRuntime(packet: packet)
        let second = GoldenEyeStageGameplayRuntime(packet: packet)
        precondition(first.summary.sourceHash == packet.setup.sourceHash)
        precondition(first.summary.packetHash == packet.packetHash)
        precondition(first.summary.objectCount == UInt32(packet.setup.objects.count))
        precondition(first.summary.roomCount == UInt32(packet.rooms.count))
        precondition(first.currentPlayer.currentPad != nil || packet.setup.pads.isEmpty)
        let diagnosticCodes = Set(first.currentFrame.diagnostics.map(\.code))
        precondition(diagnosticCodes.contains(.unsupportedEffects))
        precondition(diagnosticCodes.contains(.unsupportedAI))
        precondition(diagnosticCodes.contains(.unsupportedWeapons))
        precondition(diagnosticCodes.contains(.unsupportedCollision))

        let initialRoom = first.currentPlayer.currentRoom
        let portal = packet.setup.portals.first {
            $0.connectedRoom1 == initialRoom || $0.connectedRoom2 == initialRoom
        }
        var movedThroughPortal = false
        for tick in UInt64(0)..<UInt64(24) {
            let portalIndex: UInt32? = tick == 0 ? portal?.index : nil
            let input = GoldenEyeStageGameplayInput(
                stickX: Int16((Int(tick) % 3 - 1) * 24),
                stickY: Int16((Int(tick) % 5 - 2) * 16),
                portalIndex: portalIndex
            )
            let lhs = try first.step(nativeTick: tick, input: input)
            let rhs = try second.step(nativeTick: tick, input: input)
            precondition(lhs == rhs)
            if portalIndex != nil { movedThroughPortal = lhs.player.lastPortal != nil }
            precondition(lhs.referenceTick == tick >> 1)
            precondition(lhs.pairPhase == UInt32(tick & 1))
            precondition(lhs.frameIndex == (tick >> 1) + 1)
            precondition(lhs.stateHash != 0)
        }
        if portal != nil { precondition(movedThroughPortal, "source portal was not traversed") }
        if let nearest = first.nearestPad(to: first.currentPlayer.position) {
            precondition(nearest.sourceRecordOffset != 0 || packet.setup.pads.first?.sourceRecordOffset == 0)
        }

        // Real-input abort captures a value-only restore snapshot and does not
        // silently turn into a successful gameplay claim.
        let abortTick: UInt64 = 24
        let aborted = try first.step(
            nativeTick: abortTick,
            input: GoldenEyeStageGameplayInput(
                pressedButtons: GoldenEyeStageGameplayRuntime.realInputAbortMask,
                sourceMask: 1
            )
        )
        precondition(aborted.isAborted && !aborted.isActive)
        guard let restore = first.takeRestoreSnapshot() else {
            preconditionFailure("real-input abort did not capture restore snapshot")
        }
        precondition(restore.stageID == packet.stageID)
        try first.restore(restore)
        precondition(first.currentFrame.isActive && !first.currentFrame.isAborted)
        let restored = try first.step(nativeTick: abortTick + 1)
        precondition(restored.isActive && !restored.isAborted)
    }

    private static func checkOneRamRomTrace(
        root: URL,
        packets: [GoldenEyeStageScenePacket]
    ) throws {
        let routeCatalog = try GoldenEyeRamRomRouteCatalog.parsed(assetRoot: root)
        guard let route = routeCatalog.entries.first else {
            preconditionFailure("RAMROM catalog has no first source route")
        }
        guard let packet = packets.first(where: { $0.stageID == route.stageID }) else {
            preconditionFailure("RAMROM route stage \(route.stageID) has no scene packet")
        }
        let runtime = GoldenEyeStageGameplayRuntime(packet: packet)
        let service = GoldenEyeRamRomPlaybackService(assetRoot: root)
        let request = GoldenEyeRamRomLaunchRequest(
            catalogIndex: route.catalogIndex, demoID: route.demoID,
            stageID: route.stageID, variant: route.variant,
            controllerCount: route.controllerCount, totalTime60: route.totalTime60,
            packetCount: route.packetCount, recordCount: route.recordCount,
            recordingHash: route.recordingHash, rngHash: route.rngHash,
            assetName: route.assetName
        )
        let begin = try service.begin(request: request, atNativeTick: 0)
        precondition(begin.kind == .stageLoadUnsupported)
        precondition(runtime.currentFrame.summary.sourceHash == packet.setup.sourceHash)

        var sampleCount: UInt32 = 0
        var sawFade = false
        var sawReturn = false
        var aggregate = GoldenEyeStageGameplayRuntimeHash.offsetBasis
        let limit = UInt64(route.recordCount) * 2 + 16
        for tick in UInt64(0)..<limit {
            let frame = try runtime.step(nativeTick: tick)
            aggregate = GoldenEyeStageGameplayRuntimeHash.mix(aggregate, frame.stateHash)
            if let event = try service.step(nativeTick: tick, input: GoldenEyeRamRomServiceInput()) {
                precondition(event.demoID == UInt32(route.demoID))
                precondition(event.stageID == route.stageID)
                precondition(event.recordingHash == route.recordingHash)
                precondition(event.rngHash == route.rngHash)
                if event.kind == .sample { sampleCount += 1 }
                if event.kind == .fadeToTitle { sawFade = true }
                if event.kind == .returnToTitle { sawReturn = true; break }
            }
        }
        precondition(sampleCount == route.recordCount)
        precondition(sawFade && sawReturn)
        precondition(!runtime.isAborted)
        precondition(aggregate != 0)
        precondition(service.isActive == false)
        precondition(service.takeRestoreSnapshot() != nil)
        print(
            "trace demo=\(route.demoID) stage=\(route.stageID) samples=\(sampleCount) " +
                "aggregate=\(aggregate) gameplay=bounded unsupported=effects,ai,weapons"
        )
    }
}

enum GoldenEyeStageGameplayRuntimeHash {
    static let offsetBasis: UInt64 = 1469598103934665603
    static let prime: UInt64 = 1099511628211

    static func mix(_ initial: UInt64, _ word: UInt64) -> UInt64 {
        var hash = initial
        for shift in stride(from: 0, to: 64, by: 8) {
            hash = (hash ^ ((word >> UInt64(shift)) & 0xff)) &* prime
        }
        return hash
    }
}
