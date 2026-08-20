import Foundation

@main
struct GoldenEyeRamRomCharacterOwnerExportV6Smoke {
    static func main() throws {
        let setup = syntheticSetup()
        let visible = GoldenEyeRamRomVisibleDependencyCatalogV6(
            rootURL: URL(fileURLWithPath: "/tmp"), dependencies: [], categoryNames: []
        )
        let dependencies = GoldenEyeStageSetupDependencyCatalogV6(
            rootURL: URL(fileURLWithPath: "/tmp"), manifestURL: URL(fileURLWithPath: "/tmp"), dependencies: []
        )
        let sidecars = GoldenEyeStageModelSidecarCatalogV6(
            rootURL: URL(fileURLWithPath: "/tmp"), models: [:], sidecarCount: 0,
            expectedModelCount: 0, status: "PASS", payloads: [:]
        )

        let anchor = owner(tick: 2, sourceAnchor: true, interpolated: false)
        try GoldenEyeRamRomCharacterOwnerExportV6Adapter.validate(anchor, expectedNativeTick: 2)
        let anchorState = try GoldenEyeRamRomCharacterOwnerExportV6Adapter.animationState(
            from: anchor, expectedNativeTick: 2
        )
        precondition(anchorState.sourceAnchor && !anchorState.interpolated)
        let anchorFrame = try GoldenEyeRamRomCharacterSceneAdapterV6.makeWithOwnerExports(
            stageID: 33, stageName: "Dam", demoID: 1, nativeTick: 2,
            setup: setup, dependencies: dependencies,
            visibleDependencies: visible, sidecars: sidecars,
            ownerExports: [anchor]
        )
        precondition(anchorFrame.animationReadyCount == 1)
        precondition(anchorFrame.characters.first?.renderContext?.primaryType4ZMode == 0xC411_2078)
        precondition(anchorFrame.characters.first?.placementProvenance == .ownerWorldTransform)
        precondition(anchorFrame.characters.first?.placementMatrixQ16 == identity())

        let midpoint = owner(tick: 3, sourceAnchor: false, interpolated: true)
        try GoldenEyeRamRomCharacterOwnerExportV6Adapter.validate(midpoint, expectedNativeTick: 3)
        let midpointFrame = try GoldenEyeRamRomCharacterSceneAdapterV6.makeWithOwnerExports(
            stageID: 33, stageName: "Dam", demoID: 1, nativeTick: 3,
            setup: setup, dependencies: dependencies,
            visibleDependencies: visible, sidecars: sidecars,
            ownerExports: [midpoint]
        )
        precondition(midpointFrame.pairPhase == 1)

        let invalid = owner(tick: 3, sourceAnchor: true, interpolated: false)
        do {
            try GoldenEyeRamRomCharacterOwnerExportV6Adapter.validate(invalid)
            fatalError("odd source-anchor owner export was accepted")
        } catch let error as GoldenEyeRamRomCharacterOwnerExportV6Error {
            guard case .invalid = error else { throw error }
        }
        precondition(GoldenEyeRamRomCharacterOwnerExportV6Adapter.requiredAuthorityFields.count == 28)
        precondition(GoldenEyeRamRomCharacterOwnerExportV6Adapter.currentV5MissingAuthority.count == 3)
        print("goldeneye_ramrom_character_owner_export_v6_smoke: PASS anchor=1 midpoint=1 strictCadence=1 missingFields=28")
    }

    private static func owner(
        tick: UInt64,
        sourceAnchor: Bool,
        interpolated: Bool
    ) -> GoldenEyeRamRomCharacterOwnerExportV6 {
        let attachment = GoldenEyeRamRomCharacterAttachmentV6(
            kind: .weapon, switchIndex: 3, parentJoint: 0,
            modelName: "chrwppk", transformQ16: identity(), sourceMatrixHandle: 0x1001
        )
        let joint = GoldenEyeRamRomCharacterJointPoseV6(
            jointID: 0, parentJointID: UInt32.max,
            translationQ16: (0, 0, 0), rotationQ16: (0, 0, 0, 65_536),
            scaleQ16: (65_536, 65_536, 65_536)
        )
        let context = GoldenEyeRamRomCharacterRenderContextV6(
            propType: 9, renderFlags: 1, zBufferMode: 1,
            environmentRGBA: 0x1020_30ff, fogRGBA: 0x4050_60ff,
            rawOtherModeH: 0x0010_0000, rawOtherModeL: 0,
            rawRenderMode: 0xC411_2078,
            primaryType4ZMode: 0xC411_2078,
            secondaryType4ZMode: 0xC410_49D8,
            sourceEventHash: 0x1234
        )
        return GoldenEyeRamRomCharacterOwnerExportV6(
            nativeTick: tick, referenceTick: tick >> 1,
            pairPhase: UInt32(tick & 1), sourceAnchor: sourceAnchor,
            interpolated: interpolated, continuousPoseDeclared: true,
            demoID: 1, stageID: 33, objectIndex: 0,
            characterID: 1, bodyModelIndex: 1, headTableIndex: nil,
            rngCheckpoint: 0, padID: 0, worldTransformQ16: identity(),
            animationID: 66, animationFrameQ16: 65_536,
            animationMergeQ16: 65_536, animationFlipFlags: 0,
            rootMotionQ16: (0, 0, 0), poseHash: 0x77,
            joints: [joint], attachments: [attachment],
            visibilityState: 1, deathState: 0, actionState: 1,
            renderContext: context, sourceEventHash: context.sourceEventHash
        )
    }

    private static func identity() -> [Int32] {
        (0..<16).map { $0 % 5 == 0 ? 65_536 : 0 }
    }

    private static func syntheticSetup() -> GoldenEyeStageSetupPacket {
        let bits: (Float) -> UInt32 = { $0.bitPattern }
        return GoldenEyeStageSetupPacket(
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
    }
}
