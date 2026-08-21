import Foundation

@main
struct GoldenEyeRamRomCharacterSceneV6Smoke {
    static func main() throws {
        guard CommandLine.arguments.count >= 3 else {
            fatalError("usage: smoke stage-root visible-dependency-root")
        }
        let stageRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let visibleRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let visible = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(rootURL: visibleRoot)
        let dependencies = try GoldenEyeStageSetupDependencyCatalogV6.load(stageAssetRoot: stageRoot)
        let sidecars = try GoldenEyeStageModelSidecarCatalogV6.load(stageAssetRoot: stageRoot)
        precondition(visible.isComplete)
        precondition(dependencies.isReady)

        var setups: [UInt32: (name: String, packet: GoldenEyeStageSetupPacket)] = [:]
        for route in uniqueRoutes() {
            let setupURL = try setupURL(root: stageRoot, stageName: route.stageName)
            let packet = try GoldenEyeStageSetupPacket.load(
                stageID: route.stageID,
                setupData: Data(contentsOf: setupURL, options: [.mappedIfSafe])
            )
            precondition(packet.stageID == route.stageID)
            precondition(!packet.objects.isEmpty)
            setups[route.stageID] = (route.stageName, packet)
        }

        let frames = try GoldenEyeRamRomCharacterSceneAdapterV6.makeAll(
            setupsByStage: setups,
            dependencies: dependencies,
            visibleDependencies: visible,
            sidecars: sidecars,
            nativeTick: 2
        )
        precondition(frames.count == 14)
        precondition(Set(frames.map(\.stageID)).count == 7)
        precondition(frames.allSatisfy { !$0.characters.isEmpty })
        precondition(frames.allSatisfy { $0.staticPlacementCount == UInt32($0.characters.count) })
        precondition(frames.allSatisfy { $0.characters.allSatisfy { !$0.headCandidates.isEmpty } })
        precondition(frames.allSatisfy { $0.pairPhase == 0 && $0.referenceTick == 1 })
        precondition(frames.allSatisfy { $0.animationReadyCount == 0 })
        precondition(frames.allSatisfy { !$0.isPresentable })

        for frame in frames {
            print(
                "character-demo=\(frame.demoID) stage=\(frame.stageID) " +
                    "variant=\(frame.variant) " +
                    "guards=\(frame.characters.count) static=\(frame.staticPlacementCount) " +
                    "sidecars=\(frame.bodySidecarReadyCount) heads=\(frame.resolvedHeadCount) " +
                    "animation=\(frame.animationReadyCount) attachments=\(frame.attachmentReadyCount) " +
                    "unsupported=\(frame.unsupportedVisibleCommandCount) " +
                    "missing=\(frame.missingFields.joined(separator: ","))"
            )
        }

        try fixtureGuards()
        print(
            "goldeneye_ramrom_character_scene_v6_smoke: PASS demos=\(frames.count) " +
                "stages=\(Set(frames.map(\.stageID)).count) visibleDependencies=\(visible.dependencies.count) " +
                "sidecars=\(sidecars.models.count) failClosedAnimation=1"
        )
    }

    private static func uniqueRoutes() -> [GoldenEyeRamRomCharacterSceneAdapterV6.DemoRoute] {
        var result: [GoldenEyeRamRomCharacterSceneAdapterV6.DemoRoute] = []
        var seen = Set<UInt32>()
        for route in GoldenEyeRamRomCharacterSceneAdapterV6.sourceRoutes where seen.insert(route.stageID).inserted {
            result.append(route)
        }
        return result
    }

    private static func setupURL(root: URL, stageName: String) throws -> URL {
        let prefix = stageName.replacingOccurrences(of: " ", with: "_") + "__setup__"
        let urls = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("setup", isDirectory: true),
            includingPropertiesForKeys: nil
        ).filter {
            $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "bin"
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let url = urls.first else { fatalError("missing decoded setup for \(stageName)") }
        return url
    }

    private static func fixtureGuards() throws {
        let attachment = GoldenEyeRamRomCharacterAttachmentV6(
            kind: .weapon, switchIndex: 3, parentJoint: 9,
            modelName: "chrwppk", transformQ16: Array(repeating: 0, count: 16),
            sourceMatrixHandle: 0x1234
        )
        let state = GoldenEyeRamRomCharacterAnimationStateV6(
            animationID: 66, sourceFrameQ16: 0, poseHash: 1,
            sourceAnchor: true, interpolated: false, continuousPoseDeclared: true,
            headTableIndex: 42, joints: [
                GoldenEyeRamRomCharacterJointPoseV6(
                    jointID: 0, parentJointID: UInt32.max,
                    translationQ16: (0, 0, 0), rotationQ16: (0, 0, 0, 65_536),
                    scaleQ16: (65_536, 65_536, 65_536)
                )
            ], attachments: [attachment],
            renderContext: GoldenEyeRamRomCharacterRenderContextV6(
                propType: 9, renderFlags: 0, zBufferMode: 1,
                environmentRGBA: 0, fogRGBA: 0,
                rawOtherModeH: 0x0010_0000, rawOtherModeL: 0,
                rawRenderMode: 0xC411_2078,
                primaryType4ZMode: 0xC411_2078,
                secondaryType4ZMode: 0xC410_49D8,
                sourceEventHash: 1
            )
        )
        precondition(state.poseHash == 1 && state.attachments.count == 1)

        let bits: (Float) -> UInt32 = { $0.bitPattern }
        let setup = GoldenEyeStageSetupPacket(
            stageID: 33, sourceBytes: 128, sourceHash: 1,
            header: GoldenEyeStageSetupHeaderPacket(offsets: Array(repeating: 0, count: 10)),
            sections: [],
            pads: [GoldenEyeStageSetupPadPacket(
                index: 0, sourceRecordOffset: 0,
                position: GoldenEyeStageSetupVectorBits(x: bits(1), y: bits(2), z: bits(3)),
                up: GoldenEyeStageSetupVectorBits(x: bits(0), y: bits(1), z: bits(0)),
                look: GoldenEyeStageSetupVectorBits(x: bits(0), y: bits(0), z: bits(1)),
                linkOffset: 0, stanOffset: 0
            )],
            boundPads: [],
            objects: [GoldenEyeStageSetupObjectPacket(
                index: 0, sourceRecordOffset: 0, type: 9, scale8_8: 0,
                state: 0, key0: 1, key1: 0, flags1: 0, flags2: 0,
                recordBytes: 28, matrixWords: [], portalHint: 0
            )],
            intros: [], waypoints: [], waygroups: [], patrolPaths: [], aiLists: [],
            padNameCount: 0, boundPadNameCount: 0, portalTableSegmentedOffset: 0,
            portalTableOffset: 0, portals: [], packetHash: 2
        )
        let emptyVisible = GoldenEyeRamRomVisibleDependencyCatalogV6(
            rootURL: URL(fileURLWithPath: "/tmp"), dependencies: [], categoryNames: []
        )
        let emptyDependencies = GoldenEyeStageSetupDependencyCatalogV6(
            rootURL: URL(fileURLWithPath: "/tmp"), manifestURL: URL(fileURLWithPath: "/tmp"), dependencies: []
        )
        let emptySidecars = GoldenEyeStageModelSidecarCatalogV6(
            rootURL: URL(fileURLWithPath: "/tmp"), models: [:], sidecarCount: 0,
            expectedModelCount: 0, status: "PASS", payloads: [:]
        )
        let anchorFrame = try GoldenEyeRamRomCharacterSceneAdapterV6.make(
            stageID: 33, stageName: "Dam", demoID: 1, nativeTick: 2,
            setup: setup, dependencies: emptyDependencies,
            visibleDependencies: emptyVisible, sidecars: emptySidecars,
            animationStates: [0: state]
        )
        precondition(anchorFrame.staticPlacementCount == 1)
        precondition(anchorFrame.animationReadyCount == 1)
        precondition(anchorFrame.attachmentReadyCount == 1)

        var headAuthority = GoldenEyeRamRomCharacterHeadSelectionAuthorityV6(
            sourceRandomSeed: 0xAB8D_9F77_8128_0783
        )
        headAuthority.reset()
        let selectedHead = try headAuthority.select(
            stageID: 33, demoID: 1, objectIndex: 0, bodyID: 1,
            explicitHeadID: 57
        )
        let selectedVisible = GoldenEyeRamRomVisibleDependencyCatalogV6(
            rootURL: URL(fileURLWithPath: "/tmp"),
            dependencies: [
                GoldenEyeRamRomVisibleDependencyCatalogV6.Dependency(
                    category: "heads", symbol: "chr_57_head",
                    dependencyKind: "heads", modelIndex: 57,
                    demoIDs: [1], stages: ["Dam"]
                ),
            ],
            categoryNames: ["heads"]
        )
        let selectedFrame = try GoldenEyeRamRomCharacterSceneAdapterV6.make(
            stageID: 33, stageName: "Dam", demoID: 1, nativeTick: 2,
            setup: setup, dependencies: emptyDependencies,
            visibleDependencies: selectedVisible, sidecars: emptySidecars,
            headSelections: [0: selectedHead]
        )
        precondition(selectedFrame.characters[0].headResolution == .sourceSelected)
        precondition(selectedFrame.characters[0].headTableIndex == 57)
        precondition(selectedFrame.characters[0].headSelection == selectedHead)
        precondition(
            !selectedFrame.characters[0].missingFields.contains("head_selection.table_index")
        )
        precondition(!selectedFrame.isPresentable)

        var midpointState = state
        midpointState = GoldenEyeRamRomCharacterAnimationStateV6(
            animationID: state.animationID, sourceFrameQ16: state.sourceFrameQ16,
            poseHash: state.poseHash, sourceAnchor: false, interpolated: true,
            continuousPoseDeclared: true, headTableIndex: state.headTableIndex,
            joints: state.joints, attachments: state.attachments,
            renderContext: state.renderContext
        )
        let midpointFrame = try GoldenEyeRamRomCharacterSceneAdapterV6.make(
            stageID: 33, stageName: "Dam", demoID: 1, nativeTick: 3,
            setup: setup, dependencies: emptyDependencies,
            visibleDependencies: emptyVisible, sidecars: emptySidecars,
            animationStates: [0: midpointState]
        )
        precondition(midpointFrame.pairPhase == 1)
        do {
            _ = try GoldenEyeRamRomCharacterSceneAdapterV6.make(
                stageID: 33, stageName: "Dam", demoID: 1, nativeTick: 3,
                setup: setup, dependencies: emptyDependencies,
                visibleDependencies: emptyVisible, sidecars: emptySidecars,
                animationStates: [0: state]
            )
            fatalError("source-anchor state was accepted on an odd native tick")
        } catch let error as GoldenEyeRamRomCharacterSceneV6Error {
            if case .invalidAnimationState = error {
                // Expected fail-closed cadence guard.
            } else {
                throw error
            }
        }
    }
}
