import Foundation

enum GoldenEyeTitleHash {
    static func fnv1a(_ words: [UInt64]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for word in words {
            var value = word.littleEndian
            withUnsafeBytes(of: &value) { bytes in
                for byte in bytes {
                    hash ^= UInt64(byte)
                    hash &*= 0x100000001b3
                }
            }
        }
        return hash
    }
}

@available(macOS 27.0, *)
@main
struct GoldenEyeCastRamRomSceneV6Smoke {
    private struct RunResult: Equatable {
        let demoID: UInt8
        let stageID: UInt32
        let samples: UInt32
        let anchors: UInt32
        let terminalTick: UInt64
        let recordingHash: UInt64
        let rngHash: UInt64
        let aggregate: UInt64
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 || CommandLine.arguments.count == 3 else {
            fatalError("usage: goldeneye_cast_ramrom_scene_v6_smoke /absolute/boot-asset-root [/absolute/stage-asset-root]")
        }
        try checkSourceTables()
        try checkCastFrameContract()

        let assetRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let catalog = try GoldenEyeRamRomRouteCatalog.parsed(assetRoot: assetRoot)
        precondition(catalog.isComplete && catalog.entries.count == 14)
        var stageCoverageByID: [UInt32: GoldenEyeRamRomStageCoverageV6] = [:]
        var materialStageCoverageByID: [UInt32: GoldenEyeRamRomStageCoverageV6] = [:]
        var environmentPacketByStage: [UInt32: GoldenEyeStageBackgroundDrawPacket] = [:]
        if CommandLine.arguments.count == 3 {
            let stageRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
            let stageCatalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: stageRoot)
            let packets = try GoldenEyeStageScenePacket.loadAll(catalog: stageCatalog)
            precondition(packets.count == 7)
            guard let viewport = GoldenEyeProjectionV10.ViewportV10(
                drawableWidth: 440, drawableHeight: 330
            ), let projection = GoldenEyeProjectionV10.PacketV10(
                viewport: viewport, modelView: .identity, projection: .identity
            ) else {
                fatalError("could not construct canonical stage projection")
            }
            for packet in packets {
                let coverage = GoldenEyeRamRomStageCoverageV6.from(packet: packet)
                precondition(!coverage.isRenderable)
                stageCoverageByID[packet.stageID] = coverage
                let environmentPacket = try GoldenEyeStageSourceEnvironmentDrawPacketBuilderV6.make(
                    scene: packet, viewport: viewport, projection: projection
                )
                let materialPacket = try GoldenEyeStageSourceMaterialLowererV6.make(scene: packet)
                let materialCoverage = GoldenEyeRamRomStageCoverageV6.from(
                    packet: packet,
                    environmentPacket: environmentPacket,
                    materialPacket: materialPacket
                )
                precondition(materialCoverage.unsupportedVisibleCommandMask != 0)
                precondition(materialCoverage.unsupportedVisibleCommandCount <= 7)
                materialStageCoverageByID[packet.stageID] = materialCoverage
                print(
                    "materialCoverageStage=\(packet.stageID) mask=\(materialCoverage.unsupportedVisibleCommandMask) "
                        + "count=\(materialCoverage.unsupportedVisibleCommandCount)"
                )
                environmentPacketByStage[packet.stageID] = environmentPacket
            }
        }
        let manifest = GoldenEyeRamRomUnsupportedManifestV6.make(
            routes: catalog.entries,
            coverageByStage: stageCoverageByID,
            environmentByStage: environmentPacketByStage
        )
        precondition(manifest.entries.count == 14)
        precondition(!manifest.isComplete)
        let materialManifest = GoldenEyeRamRomUnsupportedManifestV6.make(
            routes: catalog.entries,
            coverageByStage: materialStageCoverageByID,
            environmentByStage: environmentPacketByStage
        )
        precondition(materialManifest.entries.count == 14)
        // The source environment lowerer may now prove room/background
        // geometry, so those two bits are intentionally allowed to clear.
        // Cast/RAMROM remains fail-closed until the dynamic model/effect
        // categories are lowered for every visible route row.
        let requiredDynamicUnsupportedMask =
            GoldenEyeRamRomStageCoverageV6.unsupportedProps |
            GoldenEyeRamRomStageCoverageV6.unsupportedCharacters |
            GoldenEyeRamRomStageCoverageV6.unsupportedEffects |
            GoldenEyeRamRomStageCoverageV6.unsupportedHUD
        precondition(materialManifest.entries.allSatisfy {
            $0.unsupportedVisibleCommandMask & requiredDynamicUnsupportedMask ==
                requiredDynamicUnsupportedMask &&
                $0.unsupportedVisibleCommandCount >=
                    UInt32(requiredDynamicUnsupportedMask.nonzeroBitCount)
        })

        var first: [UInt8: RunResult] = [:]
        var second: [UInt8: RunResult] = [:]
        for pass in 0..<2 {
            for route in catalog.entries {
                let result = try run(
                    route: route, assetRoot: assetRoot,
                    stageCoverage: stageCoverageByID[route.stageID],
                    environmentPacket: environmentPacketByStage[route.stageID]
                )
                if pass == 0 {
                    first[route.demoID] = result
                } else {
                    second[route.demoID] = result
                    precondition(first[route.demoID] == result,
                                 "demo (route.demoID) authority trace changed on repeat")
                }
            }
        }
        precondition(first.count == 14 && second.count == 14)
        var aggregate = GoldenEyeCastSceneV6Hash.offsetBasis
        for result in first.values.sorted(by: { $0.demoID < $1.demoID }) {
            for word in [
                UInt64(result.demoID), UInt64(result.stageID), UInt64(result.samples),
                UInt64(result.anchors), result.terminalTick, result.recordingHash,
                result.rngHash, result.aggregate,
            ] {
                aggregate = GoldenEyeCastSceneV6Hash.mix(aggregate, word)
            }
        }
        print(
            "goldeneye_cast_ramrom_scene_v6_smoke: PASS castIdentity=30 " +
                "animations=22 demos=14 runs=28 manifest=14 stageVisual=FAIL_CLOSED aggregate=\(aggregate)"
        )
    }

    private static func checkSourceTables() throws {
        precondition(GoldenEyeCastSourceTableV6.identities.count == 34)
        precondition(GoldenEyeCastSourceTableV6.animations.count == 22)
        let bond = try GoldenEyeCastSourceTableV6.identity(sourceIndex: 1)
        precondition(bond.bodyID == 22 && bond.headID == 74)
        let natalya = try GoldenEyeCastSourceTableV6.identity(sourceIndex: 2)
        precondition(natalya.bodyID == 16 && natalya.headID == GoldenEyeCastIdentityV6.headFixed && natalya.headSelection == 1)
        let soldier = try GoldenEyeCastSourceTableV6.identity(sourceIndex: 9)
        precondition(soldier.bodyID == 2 && soldier.hasRandomHead)
        let mayday = try GoldenEyeCastSourceTableV6.identity(sourceIndex: 26)
        precondition(mayday.bodyID == 14 && mayday.headID == GoldenEyeCastIdentityV6.headFixed)
        let firstAnimation = try GoldenEyeCastSourceTableV6.animation(sourceIndex: 0)
        precondition(firstAnimation.animationID == 63 && firstAnimation.startFrameQ16 == 6_422_528)
        precondition(GoldenEyeCastSourceTableV6.animations.map(\.animationID) == [
            63, 66, 67, 72, 76, 89, 98, 99, 100, 102, 103, 153,
            163, 70, 74, 80, 97, 150, 151, 152, 161, 160,
        ])
        precondition(GoldenEyeCastSourceTableV6.rifleWeapons.count == 6)
        precondition(GoldenEyeCastSourceTableV6.pistolWeapons.count == 10)
        do {
            _ = try GoldenEyeCastSourceTableV6.identity(sourceIndex: 30)
            preconditionFailure("source sentinel must not become a cast identity")
        } catch GoldenEyeCastSceneV6Error.invalidSourceIndex(30) {
            // The route sidecar's 34-slot history includes the source table
            // sentinel at 30; fail closed until the route is corrected.
        }
    }

    private static func checkCastFrameContract() throws {
        let preparedIdentity = try GoldenEyeCastSourceTableV6.identity(sourceIndex: 1)
        let preparedAnimation = try GoldenEyeCastSourceTableV6.animation(sourceIndex: 1)
        let preparedRequest = try GoldenEyeCastSourceSceneRequestV6(
            identity: preparedIdentity,
            animation: preparedAnimation,
            weapon: GoldenEyeCastSourceTableV6.pistolWeapons[0],
            nativeTick: 2,
            sourceTimer: 30,
            sourceFrameQ16: 30 * 65_536,
            fadeQ16: 65_536
        )
        precondition(preparedRequest.identity.sourceIndex == 1)
        precondition(preparedRequest.animation.animationID == 66)
        precondition(preparedRequest.weapon?.isPistol == true)

        let identity = try GoldenEyeCastSourceTableV6.identity(sourceIndex: 1)
        let animation = try GoldenEyeCastSourceTableV6.animation(sourceIndex: 1)
        let pose = try GoldenEyeCastPoseV6(
            sourcePoseHash: 0x11_22_33_44,
            joints: [GoldenEyeCastJointPoseV6(jointIndex: 0, parentIndex: UInt16.max)]
        )
        let weapon = GoldenEyeCastSourceTableV6.pistolWeapons[0]
        let previous = try GoldenEyeCastSceneFrameBuilderV6.make(
            nativeTick: 10, sourceIndex: 1, animation: animation, identity: identity,
            weapon: weapon, pose: pose, sourceFrameQ16: 0, fadeQ16: 65_536,
            cameraDistanceQ16: 70 * 65_536, cameraAngleQ16: 0,
            cameraHeightQ16: 0, unsupportedVisibleCommandCount: 0
        )
        let current = try GoldenEyeCastSceneFrameBuilderV6.make(
            nativeTick: 12, sourceIndex: 1, animation: animation, identity: identity,
            weapon: weapon, pose: pose, sourceFrameQ16: 65_536, fadeQ16: 65_536,
            cameraDistanceQ16: 80 * 65_536, cameraAngleQ16: 65_536,
            cameraHeightQ16: 65_536, unsupportedVisibleCommandCount: 0
        )
        let odd = GoldenEyeCastSceneInterpolatorV6.interpolate(
            previous: previous, current: current, nativeTick: 11
        )
        precondition(previous.isRenderable && current.isRenderable && odd.isRenderable)
        precondition(odd.pairPhase == 1 && odd.sourceFrameQ16 == 32_768)
        precondition(odd.cameraDistanceQ16 == 75 * 65_536)

        let missingPose = try GoldenEyeCastSceneFrameBuilderV6.make(
            nativeTick: 10, sourceIndex: 1, animation: animation, identity: identity,
            weapon: weapon, pose: nil, sourceFrameQ16: 0, fadeQ16: 65_536,
            cameraDistanceQ16: 0, cameraAngleQ16: 0, cameraHeightQ16: 0,
            unsupportedVisibleCommandCount: 1
        )
        precondition(!missingPose.isRenderable)
        let stage = GoldenEyeRamRomStageCoverageV6(
            stageID: 33, sourceHash: 1, packetHash: 2, roomCount: 1,
            resourceCount: 3,
            unsupportedVisibleCommandMask: GoldenEyeRamRomStageCoverageV6.unsupportedRooms,
            unsupportedVisibleCommandCount: 1
        )
        precondition(!stage.isRenderable)
    }

    private static func makeRequest(_ route: GoldenEyeRamRomDemoRoute) -> GoldenEyeRamRomLaunchRequest {
        GoldenEyeRamRomLaunchRequest(
            catalogIndex: route.catalogIndex, demoID: route.demoID, stageID: route.stageID,
            variant: route.variant, controllerCount: route.controllerCount,
            totalTime60: route.totalTime60, packetCount: route.packetCount,
            recordCount: route.recordCount, recordingHash: route.recordingHash,
            rngHash: route.rngHash, assetName: route.assetName
        )
    }

    private static func run(
        route: GoldenEyeRamRomDemoRoute,
        assetRoot: URL,
        stageCoverage suppliedCoverage: GoldenEyeRamRomStageCoverageV6?,
        environmentPacket suppliedEnvironmentPacket: GoldenEyeStageBackgroundDrawPacket?
    ) throws -> RunResult {
        let service = GoldenEyeRamRomPlaybackService(assetRoot: assetRoot)
        let authority = GoldenEyeRamRomAuthorityV6(service: service)
        let coverage = suppliedCoverage ?? GoldenEyeRamRomStageCoverageV6(
            stageID: route.stageID, sourceHash: 1, packetHash: 2,
            roomCount: 1, resourceCount: 3,
            unsupportedVisibleCommandMask: GoldenEyeRamRomStageCoverageV6.unsupportedBackground |
                GoldenEyeRamRomStageCoverageV6.unsupportedRooms |
                GoldenEyeRamRomStageCoverageV6.unsupportedProps |
                GoldenEyeRamRomStageCoverageV6.unsupportedCharacters |
                GoldenEyeRamRomStageCoverageV6.unsupportedEffects |
                GoldenEyeRamRomStageCoverageV6.unsupportedHUD,
            unsupportedVisibleCommandCount: 6
        )
        let begin = try authority.begin(
            request: makeRequest(route), atNativeTick: 0, stageCoverage: coverage,
            environmentPacket: suppliedEnvironmentPacket
        )
        precondition(begin.eventKind == GoldenEyeRamRomPlaybackEventKind.stageLoadUnsupported)
        precondition(!begin.isRenderable)
        if let suppliedEnvironmentPacket {
            precondition(begin.environmentPacketHash == suppliedEnvironmentPacket.packetHash)
            precondition(begin.environmentCommandCount == UInt32(suppliedEnvironmentPacket.commands.count))
            precondition(begin.hasEnvironmentGeometry)
        }

        var samples: UInt32 = 0
        var anchors: UInt32 = 0
        var terminalTick: UInt64 = 0
        var sawFade = false
        var sawReturn = false
        var aggregate = GoldenEyeCastSceneV6Hash.offsetBasis
        let limit = UInt64(route.recordCount) * 2 + 16
        for tick in UInt64(0)..<limit {
            guard let frame = try authority.step(
                nativeTick: tick, input: GoldenEyeRamRomServiceInput()
            ) else { continue }
            aggregate = GoldenEyeCastSceneV6Hash.mix(aggregate, frame.authorityStateHash)
            aggregate = GoldenEyeCastSceneV6Hash.mix(aggregate, frame.sampleHash)
            if frame.pairPhase == 1, let anchor = authority.currentAnchor {
                precondition(frame.authorityStateHash == anchor.authorityStateHash)
                precondition(frame.packetIndex == anchor.packetIndex)
                precondition(frame.sourceFrame == anchor.sourceFrame)
                precondition(!frame.isSourceAnchor)
            }
            if frame.isSourceAnchor { anchors += 1 }
            if frame.eventKind == .sample {
                samples += 1
                precondition(frame.pairPhase == 0)
                precondition(frame.recordingHash == route.recordingHash)
                precondition(frame.rngHash == route.rngHash)
            }
            if frame.eventKind == .fadeToTitle { sawFade = true }
            if frame.eventKind == .returnToTitle {
                sawReturn = true
                terminalTick = tick
                break
            }
        }
        precondition(sawFade && sawReturn)
        precondition(samples == route.recordCount)
        precondition(anchors >= route.recordCount)
        precondition(!service.isActive)
        precondition(service.takeRestoreSnapshot() != nil)
        return RunResult(
            demoID: route.demoID, stageID: route.stageID, samples: samples,
            anchors: anchors, terminalTick: terminalTick,
            recordingHash: route.recordingHash, rngHash: route.rngHash,
            aggregate: aggregate
        )
    }
}
