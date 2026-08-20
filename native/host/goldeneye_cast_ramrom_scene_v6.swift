import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Source-derived cast identity and RAMROM presentation contracts.
///
/// This file is intentionally additive.  The existing M27 room/portal line
/// renderer and the V5 RAMROM `STAGE_LOAD_UNSUPPORTED` event remain diagnostic
/// evidence; they are never used as a product scene.  These value-only Swift
/// records are the seam a complete source scene lowerer must satisfy before a
/// cast or attract frame can be presented.

public enum GoldenEyeCastSceneV6Error: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidSourceIndex(UInt16)
    case invalidAnimation(UInt32)
    case invalidPose(UInt32, UInt32)
    case unsupportedStage(UInt32, UInt32)
    case authorityMismatch(String)
    case playbackFailure(UInt8, UInt64, String)

    public var description: String {
        switch self {
        case let .invalidSourceIndex(index):
            return "cast source index \(index) is outside the source table"
        case let .invalidAnimation(animation):
            return "cast animation \(animation) is outside the source intro table"
        case let .invalidPose(count, expected):
            return "cast pose has \(count) joints, expected a bounded nonzero pose with at most \(expected)"
        case let .unsupportedStage(stageID, mask):
            return "stage \(stageID) has unsupported visible command mask 0x\(String(mask, radix: 16))"
        case let .authorityMismatch(detail):
            return "RAMROM authority mismatch: \(detail)"
        case let .playbackFailure(demoID, tick, detail):
            return "RAMROM demo \(demoID) failed at native tick \(tick): \(detail)"
        }
    }
}

public struct GoldenEyeCastJointPoseV6: Sendable, Equatable {
    public let jointIndex: UInt16
    public let parentIndex: UInt16
    public let rotationXQ16: Int32
    public let rotationYQ16: Int32
    public let rotationZQ16: Int32
    public let translationXQ16: Int32
    public let translationYQ16: Int32
    public let translationZQ16: Int32
    public let scaleQ16: Int32

    public init(
        jointIndex: UInt16,
        parentIndex: UInt16,
        rotationXQ16: Int32 = 0,
        rotationYQ16: Int32 = 0,
        rotationZQ16: Int32 = 0,
        translationXQ16: Int32 = 0,
        translationYQ16: Int32 = 0,
        translationZQ16: Int32 = 0,
        scaleQ16: Int32 = 65_536
    ) {
        self.jointIndex = jointIndex
        self.parentIndex = parentIndex
        self.rotationXQ16 = rotationXQ16
        self.rotationYQ16 = rotationYQ16
        self.rotationZQ16 = rotationZQ16
        self.translationXQ16 = translationXQ16
        self.translationYQ16 = translationYQ16
        self.translationZQ16 = translationZQ16
        self.scaleQ16 = scaleQ16
    }
}

public struct GoldenEyeCastPoseV6: Sendable, Equatable {
    public static let maxJoints = 256

    public let sourcePoseHash: UInt64
    public let joints: [GoldenEyeCastJointPoseV6]

    public init(sourcePoseHash: UInt64, joints: [GoldenEyeCastJointPoseV6]) throws {
        guard !joints.isEmpty, joints.count <= Self.maxJoints else {
            throw GoldenEyeCastSceneV6Error.invalidPose(
                UInt32(joints.count), UInt32(Self.maxJoints)
            )
        }
        self.sourcePoseHash = sourcePoseHash
        self.joints = joints
    }

    public var jointCount: UInt32 { UInt32(joints.count) }

    public var hash: UInt64 {
        var value = GoldenEyeCastSceneV6Hash.offsetBasis
        value = GoldenEyeCastSceneV6Hash.mix(value, sourcePoseHash)
        value = GoldenEyeCastSceneV6Hash.mix(value, UInt64(joints.count))
        for joint in joints {
            value = GoldenEyeCastSceneV6Hash.mix(value, UInt64(joint.jointIndex))
            value = GoldenEyeCastSceneV6Hash.mix(value, UInt64(joint.parentIndex))
            value = GoldenEyeCastSceneV6Hash.mix(value, UInt64(bitPattern: Int64(joint.rotationXQ16)))
            value = GoldenEyeCastSceneV6Hash.mix(value, UInt64(bitPattern: Int64(joint.rotationYQ16)))
            value = GoldenEyeCastSceneV6Hash.mix(value, UInt64(bitPattern: Int64(joint.rotationZQ16)))
            value = GoldenEyeCastSceneV6Hash.mix(value, UInt64(bitPattern: Int64(joint.translationXQ16)))
            value = GoldenEyeCastSceneV6Hash.mix(value, UInt64(bitPattern: Int64(joint.translationYQ16)))
            value = GoldenEyeCastSceneV6Hash.mix(value, UInt64(bitPattern: Int64(joint.translationZQ16)))
            value = GoldenEyeCastSceneV6Hash.mix(value, UInt64(bitPattern: Int64(joint.scaleQ16)))
        }
        return value
    }
}

/// The exact source `intro_char_table` body/head rows from front.c.  The
/// numeric values are the source BODIES/HEADS enum values, not host indices.
public struct GoldenEyeCastIdentityV6: Sendable, Equatable {
    public let sourceIndex: UInt16
    public let bodyID: UInt16
    public let headID: UInt32
    public let headSelection: UInt32
    public let text1SourceID: UInt32
    public let text2SourceID: UInt32
    public let text3SourceID: UInt32
    public let sourceFlag: UInt32

    public var hasRandomHead: Bool { headID == Self.headRandom }
    public var isGuest: Bool { sourceFlag == 0 && (26...29).contains(sourceIndex) }

    public static let headFixed: UInt32 = 0xffff_ffff
    public static let headRandom: UInt32 = 0xffff_ff9f

    fileprivate init(
        sourceIndex: UInt16,
        bodyID: UInt16,
        headID: UInt32,
        headSelection: UInt32,
        text1SourceID: UInt32,
        text2SourceID: UInt32,
        text3SourceID: UInt32,
        sourceFlag: UInt32
    ) {
        self.sourceIndex = sourceIndex
        self.bodyID = bodyID
        self.headID = headID
        self.headSelection = headSelection
        self.text1SourceID = text1SourceID
        self.text2SourceID = text2SourceID
        self.text3SourceID = text3SourceID
        self.sourceFlag = sourceFlag
    }
}

public struct GoldenEyeCastAnimationV6: Sendable, Equatable {
    public let sourceIndex: UInt16
    public let animationID: UInt32
    public let startFrameQ16: Int32
    public let playbackSpeedQ16: Int32
    public let cameraPreset: UInt32

    public var usesWeaponCamera: Bool { cameraPreset == 1 || cameraPreset == 2 }
}

public struct GoldenEyeCastWeaponV6: Sendable, Equatable {
    public let propID: UInt16
    public let cameraPreset: UInt32

    public var isPistol: Bool { cameraPreset == 1 }
    public var isRifle: Bool { cameraPreset == 2 }
}

public enum GoldenEyeCastSourceTableV6 {
    /// Source enum values from bondconstants.h.  Text identifiers use stable
    /// source-name hashes because the language table is an independent asset
    /// payload; no host pointer or string crosses the scene boundary.
    public static let identities: [GoldenEyeCastIdentityV6] = [
        row(0, 5, 78, 0, "LF", "THEACTORS", "LF", 1),
        row(1, 22, 74, 0, "STARRING", "007", "JAMESBOND", 0),
        row(2, 16, GoldenEyeCastIdentityV6.headFixed, 1, "STARRING", "NATALYASIMONOVA", "LF", 0),
        row(3, 9, GoldenEyeCastIdentityV6.headFixed, 1, "STARRING", "006", "ALECTREVELYAN", 0),
        row(4, 11, GoldenEyeCastIdentityV6.headFixed, 1, "ALSOFEATURING", "JANUSOPPERATIVE", "XENIAONPTOPP", 0),
        row(5, 7, GoldenEyeCastIdentityV6.headFixed, 1, "ALSOFEATURING", "GENERAL", "ARKADYOURUMOV", 0),
        row(6, 6, GoldenEyeCastIdentityV6.headFixed, 1, "ALSOFEATURING", "BORISGRISHENKO", "LF", 0),
        row(7, 10, GoldenEyeCastIdentityV6.headFixed, 1, "ALSOFEATURING", "EXKGBAGENT", "VELENTINZUKOVSKY", 0),
        row(8, 19, 69, 0, "ALSOFEATURING", "DEFENSEMINISTER", "DIMITRIMISHKIN", 0),
        row(9, 2, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "RUSSIANSOLDIER", "LF", 1),
        row(10, 3, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "RUSSIANINFANTRY", "LF", 1),
        row(11, 35, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "SCIENTIST", "LF", 1),
        row(12, 28, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "SCIENTIST", "LF", 1),
        row(13, 18, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "RUSSIANCOMMANDANT", "LF", 1),
        row(14, 17, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "JANUSMARINE", "LF", 1),
        row(15, 20, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "NAVALOFFICER", "LF", 1),
        row(16, 36, GoldenEyeCastIdentityV6.headFixed, 1, "LF", "HELICOPTERPILOT", "LF", 1),
        row(17, 1, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "STPETERSBURGGUARD", "LF", 1),
        row(18, 29, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "CIVILIAN", "LF", 1),
        row(19, 30, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "CIVILIAN", "LF", 1),
        row(20, 31, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "CIVILIAN", "LF", 1),
        row(21, 32, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "CIVILIAN", "LF", 1),
        row(22, 21, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "SIBERIANGUARD", "LF", 1),
        row(23, 38, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "ARCTICCOMMANDO", "LF", 1),
        row(24, 39, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "MOONRAKERELITE", "LF", 1),
        row(25, 40, GoldenEyeCastIdentityV6.headRandom, 2, "LF", "MOONRAKERELITE", "LF", 1),
        row(26, 14, GoldenEyeCastIdentityV6.headFixed, 1, "GUESTSTAR", "MAYDAY", "LF", 0),
        row(27, 13, GoldenEyeCastIdentityV6.headFixed, 1, "GUESTSTAR", "JAWS", "LF", 0),
        row(28, 15, GoldenEyeCastIdentityV6.headFixed, 1, "GUESTSTAR", "ODDJOB", "LF", 0),
        row(29, 12, GoldenEyeCastIdentityV6.headFixed, 1, "GUESTSTAR", "BERONSAMEDI", "LF", 0),
        row(30, 0xffff, 0, 0, "", "", "", 0),
        row(31, 0xffff, 0, 0, "", "", "", 0),
        row(32, 0xffff, 0, 0, "", "", "", 0),
        row(33, 0xffff, 0, 0, "", "", "", 0),
    ]

    /// Source `intro_animation_table`.  Animation IDs are the enum values in
    /// bondconstants.h; Q16 values preserve the authored float parameters.
    public static let animations: [GoldenEyeCastAnimationV6] = [
        .init(sourceIndex: 0, animationID: 63, startFrameQ16: 6_422_528, playbackSpeedQ16: 65_536, cameraPreset: 0),
        .init(sourceIndex: 1, animationID: 66, startFrameQ16: 1_376_256, playbackSpeedQ16: 65_536, cameraPreset: 1),
        .init(sourceIndex: 2, animationID: 67, startFrameQ16: 1_703_936, playbackSpeedQ16: 65_536, cameraPreset: 1),
        .init(sourceIndex: 3, animationID: 72, startFrameQ16: 0, playbackSpeedQ16: 65_536, cameraPreset: 1),
        .init(sourceIndex: 4, animationID: 76, startFrameQ16: 0, playbackSpeedQ16: 65_536, cameraPreset: 1),
        .init(sourceIndex: 5, animationID: 89, startFrameQ16: 0, playbackSpeedQ16: 59_638, cameraPreset: 1),
        .init(sourceIndex: 6, animationID: 98, startFrameQ16: 2_031_104, playbackSpeedQ16: 65_536, cameraPreset: 1),
        .init(sourceIndex: 7, animationID: 99, startFrameQ16: 0, playbackSpeedQ16: 65_536, cameraPreset: 1),
        .init(sourceIndex: 8, animationID: 100, startFrameQ16: 0, playbackSpeedQ16: 65_536, cameraPreset: 1),
        .init(sourceIndex: 9, animationID: 102, startFrameQ16: 0, playbackSpeedQ16: 65_536, cameraPreset: 1),
        .init(sourceIndex: 10, animationID: 103, startFrameQ16: 0, playbackSpeedQ16: 65_536, cameraPreset: 1),
        .init(sourceIndex: 11, animationID: 153, startFrameQ16: 16_252_928, playbackSpeedQ16: 65_536, cameraPreset: 0),
        .init(sourceIndex: 12, animationID: 163, startFrameQ16: 9_830_400, playbackSpeedQ16: 65_536, cameraPreset: 0),
        .init(sourceIndex: 13, animationID: 70, startFrameQ16: 0, playbackSpeedQ16: 58_982, cameraPreset: 1),
        .init(sourceIndex: 14, animationID: 74, startFrameQ16: 0, playbackSpeedQ16: 58_982, cameraPreset: 1),
        .init(sourceIndex: 15, animationID: 80, startFrameQ16: 0, playbackSpeedQ16: 58_982, cameraPreset: 1),
        .init(sourceIndex: 16, animationID: 97, startFrameQ16: 3_342_336, playbackSpeedQ16: 65_536, cameraPreset: 1),
        .init(sourceIndex: 17, animationID: 150, startFrameQ16: 0, playbackSpeedQ16: 58_982, cameraPreset: 1),
        .init(sourceIndex: 18, animationID: 151, startFrameQ16: 0, playbackSpeedQ16: 58_982, cameraPreset: 1),
        .init(sourceIndex: 19, animationID: 152, startFrameQ16: 2_424_832, playbackSpeedQ16: 65_536, cameraPreset: 2),
        .init(sourceIndex: 20, animationID: 161, startFrameQ16: 19_660_800, playbackSpeedQ16: 65_536, cameraPreset: 2),
        .init(sourceIndex: 21, animationID: 160, startFrameQ16: 7_864_320, playbackSpeedQ16: 65_536, cameraPreset: 2),
    ]

    public static let rifleWeapons: [GoldenEyeCastWeaponV6] = [
        .init(propID: 184, cameraPreset: 2), .init(propID: 188, cameraPreset: 2),
        .init(propID: 197, cameraPreset: 2), .init(propID: 207, cameraPreset: 2),
        .init(propID: 185, cameraPreset: 2), .init(propID: 210, cameraPreset: 2),
    ]

    public static let pistolWeapons: [GoldenEyeCastWeaponV6] = [
        .init(propID: 191, cameraPreset: 1), .init(propID: 204, cameraPreset: 1),
        .init(propID: 193, cameraPreset: 1), .init(propID: 195, cameraPreset: 1),
        .init(propID: 195, cameraPreset: 1), .init(propID: 205, cameraPreset: 1),
        .init(propID: 205, cameraPreset: 1), .init(propID: 190, cameraPreset: 1),
        .init(propID: 187, cameraPreset: 1), .init(propID: 208, cameraPreset: 1),
    ]

    public static func identity(sourceIndex: UInt16) throws -> GoldenEyeCastIdentityV6 {
        guard Int(sourceIndex) < identities.count else {
            throw GoldenEyeCastSceneV6Error.invalidSourceIndex(sourceIndex)
        }
        let value = identities[Int(sourceIndex)]
        guard value.bodyID != 0xffff else {
            throw GoldenEyeCastSceneV6Error.invalidSourceIndex(sourceIndex)
        }
        return value
    }

    public static func animation(sourceIndex: UInt16) throws -> GoldenEyeCastAnimationV6 {
        guard Int(sourceIndex) < animations.count else {
            throw GoldenEyeCastSceneV6Error.invalidAnimation(UInt32(sourceIndex))
        }
        return animations[Int(sourceIndex)]
    }

    private static func row(
        _ index: UInt16, _ body: UInt16, _ head: UInt32, _ selection: UInt32,
        _ text1: String, _ text2: String, _ text3: String, _ flag: UInt32
    ) -> GoldenEyeCastIdentityV6 {
        GoldenEyeCastIdentityV6(
            sourceIndex: index, bodyID: body, headID: head,
            headSelection: selection, text1SourceID: sourceHash(text1),
            text2SourceID: sourceHash(text2), text3SourceID: sourceHash(text3),
            sourceFlag: flag
        )
    }

    private static func sourceHash(_ value: String) -> UInt32 {
        value.utf8.reduce(UInt32(2_166_136_261)) { hash, byte in
            (hash ^ UInt32(byte)) &* 16_777_619
        }
    }
}

public struct GoldenEyeCastSceneFrameV6: Sendable, Equatable {
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let pairPhase: UInt32
    public let sourceIndex: UInt16
    public let bodyID: UInt16
    public let headID: UInt32
    public let weaponPropID: UInt16
    public let animationID: UInt32
    public let sourceFrameQ16: Int32
    public let fadeQ16: Int32
    public let cameraDistanceQ16: Int32
    public let cameraAngleQ16: Int32
    public let cameraHeightQ16: Int32
    public let poseHash: UInt64
    public let jointCount: UInt32
    public let unsupportedVisibleCommandCount: UInt32
    public let stateHash: UInt64
    public let renderHash: UInt64

    public var isRenderable: Bool {
        unsupportedVisibleCommandCount == 0 && poseHash != 0 && jointCount != 0
    }
}

public enum GoldenEyeCastSceneFrameBuilderV6 {
    /// Builds a frame only when the caller supplies a complete copied pose.
    /// A missing model/attachment/texture lowerer is represented by an
    /// unsupported count, never by a procedural character.
    public static func make(
        nativeTick: UInt64,
        sourceIndex: UInt16,
        animation: GoldenEyeCastAnimationV6,
        identity: GoldenEyeCastIdentityV6,
        weapon: GoldenEyeCastWeaponV6?,
        pose: GoldenEyeCastPoseV6?,
        sourceFrameQ16: Int32,
        fadeQ16: Int32,
        cameraDistanceQ16: Int32,
        cameraAngleQ16: Int32,
        cameraHeightQ16: Int32,
        unsupportedVisibleCommandCount: UInt32
    ) throws -> GoldenEyeCastSceneFrameV6 {
        guard sourceIndex == identity.sourceIndex else {
            throw GoldenEyeCastSceneV6Error.authorityMismatch("identity/source index differs")
        }
        let checkedPose = pose
        let poseHash = checkedPose?.hash ?? 0
        let jointCount = checkedPose?.jointCount ?? 0
        let renderHash = GoldenEyeCastSceneV6Hash.frame(
            nativeTick: nativeTick, sourceIndex: sourceIndex,
            bodyID: identity.bodyID, headID: identity.headID,
            weaponID: weapon?.propID ?? UInt16.max,
            animationID: animation.animationID, sourceFrameQ16: sourceFrameQ16,
            fadeQ16: fadeQ16, poseHash: poseHash,
            unsupported: unsupportedVisibleCommandCount
        )
        var stateHash = renderHash
        stateHash = GoldenEyeCastSceneV6Hash.mix(stateHash, cameraDistanceQ16)
        stateHash = GoldenEyeCastSceneV6Hash.mix(stateHash, cameraAngleQ16)
        stateHash = GoldenEyeCastSceneV6Hash.mix(stateHash, cameraHeightQ16)
        return GoldenEyeCastSceneFrameV6(
            nativeTick: nativeTick, referenceTick: nativeTick >> 1,
            pairPhase: UInt32(nativeTick & 1), sourceIndex: sourceIndex,
            bodyID: identity.bodyID, headID: identity.headID,
            weaponPropID: weapon?.propID ?? UInt16.max,
            animationID: animation.animationID, sourceFrameQ16: sourceFrameQ16,
            fadeQ16: fadeQ16, cameraDistanceQ16: cameraDistanceQ16,
            cameraAngleQ16: cameraAngleQ16, cameraHeightQ16: cameraHeightQ16,
            poseHash: poseHash, jointCount: jointCount,
            unsupportedVisibleCommandCount: unsupportedVisibleCommandCount,
            stateHash: stateHash, renderHash: renderHash
        )
    }
}

public enum GoldenEyeCastSceneInterpolatorV6 {
    public static func interpolate(
        previous: GoldenEyeCastSceneFrameV6,
        current: GoldenEyeCastSceneFrameV6,
        nativeTick: UInt64
    ) -> GoldenEyeCastSceneFrameV6 {
        guard previous.sourceIndex == current.sourceIndex,
              previous.pairPhase == 0, current.pairPhase == 0 else {
            return current
        }
        let midpoint = { (a: Int32, b: Int32) -> Int32 in
            Int32((Int64(a) + Int64(b)) / 2)
        }
        let renderHash = GoldenEyeCastSceneV6Hash.frame(
            nativeTick: nativeTick, sourceIndex: current.sourceIndex,
            bodyID: current.bodyID, headID: current.headID,
            weaponID: current.weaponPropID, animationID: current.animationID,
            sourceFrameQ16: midpoint(previous.sourceFrameQ16, current.sourceFrameQ16),
            fadeQ16: midpoint(previous.fadeQ16, current.fadeQ16),
            poseHash: current.poseHash, unsupported: current.unsupportedVisibleCommandCount
        )
        return GoldenEyeCastSceneFrameV6(
            nativeTick: nativeTick, referenceTick: nativeTick >> 1,
            pairPhase: UInt32(nativeTick & 1), sourceIndex: current.sourceIndex,
            bodyID: current.bodyID, headID: current.headID,
            weaponPropID: current.weaponPropID, animationID: current.animationID,
            sourceFrameQ16: midpoint(previous.sourceFrameQ16, current.sourceFrameQ16),
            fadeQ16: midpoint(previous.fadeQ16, current.fadeQ16),
            cameraDistanceQ16: midpoint(previous.cameraDistanceQ16, current.cameraDistanceQ16),
            cameraAngleQ16: midpoint(previous.cameraAngleQ16, current.cameraAngleQ16),
            cameraHeightQ16: midpoint(previous.cameraHeightQ16, current.cameraHeightQ16),
            poseHash: current.poseHash, jointCount: current.jointCount,
            unsupportedVisibleCommandCount: current.unsupportedVisibleCommandCount,
            stateHash: current.stateHash, renderHash: renderHash
        )
    }
}

public struct GoldenEyeRamRomStageCoverageV6: Sendable, Equatable {
    public static let unsupportedBackground: UInt32 = 1 << 0
    public static let unsupportedRooms: UInt32 = 1 << 1
    public static let unsupportedProps: UInt32 = 1 << 2
    public static let unsupportedCharacters: UInt32 = 1 << 3
    public static let unsupportedEffects: UInt32 = 1 << 4
    public static let unsupportedHUD: UInt32 = 1 << 5
    public static let unsupportedTextures: UInt32 = 1 << 6

    public let stageID: UInt32
    public let sourceHash: UInt64
    public let packetHash: UInt64
    public let roomCount: UInt32
    public let resourceCount: UInt32
    public let unsupportedVisibleCommandMask: UInt32
    public let unsupportedVisibleCommandCount: UInt32

    public init(stageID: UInt32, sourceHash: UInt64, packetHash: UInt64,
                roomCount: UInt32, resourceCount: UInt32,
                unsupportedVisibleCommandMask: UInt32,
                unsupportedVisibleCommandCount: UInt32) {
        self.stageID = stageID
        self.sourceHash = sourceHash
        self.packetHash = packetHash
        self.roomCount = roomCount
        self.resourceCount = resourceCount
        self.unsupportedVisibleCommandMask = unsupportedVisibleCommandMask
        self.unsupportedVisibleCommandCount = unsupportedVisibleCommandCount
    }

    public var isRenderable: Bool {
        unsupportedVisibleCommandMask == 0 && unsupportedVisibleCommandCount == 0
    }

    public static func from(packet: GoldenEyeStageScenePacket) -> Self {
        from(packet: packet, environmentPacket: nil, materialPacket: nil)
    }

    static func from(
        packet: GoldenEyeStageScenePacket,
        environmentPacket: GoldenEyeStageBackgroundDrawPacket?,
        materialPacket: GoldenEyeStageSourceMaterialPacketV6?,
        stageTexturesReady: Bool = false
    ) -> Self {
        // Keep the immutable category evidence honest. Environment bits are
        // cleared only when the source packet itself proves that category;
        // setup props, characters, effects, and HUD remain explicit until
        // their source draw lowerers exist.
        var mask = Self.unsupportedProps | Self.unsupportedCharacters |
            Self.unsupportedEffects | Self.unsupportedHUD
        if environmentPacket == nil ||
            (environmentPacket!.unsupportedMask & GoldenEyeStageBackgroundDrawPacket.unsupportedBackgroundDisplayLists) != 0 {
            mask |= Self.unsupportedBackground
        }
        if environmentPacket == nil ||
            (environmentPacket!.unsupportedMask & GoldenEyeStageBackgroundDrawPacket.unsupportedRoomGeometry) != 0 {
            mask |= Self.unsupportedRooms
        }
        if !stageTexturesReady && (materialPacket?.unsupportedTextureBindingCount ?? 0 > 0) {
            mask |= Self.unsupportedTextures
        }
        let unsupportedCount = UInt32(mask.nonzeroBitCount)
        return Self(
            stageID: packet.stageID, sourceHash: packet.setup.sourceHash,
            packetHash: packet.packetHash, roomCount: UInt32(packet.rooms.count),
            resourceCount: UInt32(packet.resources.count),
            unsupportedVisibleCommandMask: mask,
            unsupportedVisibleCommandCount: unsupportedCount
        )
    }
}

/// Per-recording source-scene coverage. A shared stage packet is not enough
/// evidence for an attract recording: variants can reach different props,
/// characters, effects, and HUD branches. The manifest keeps one immutable
/// row for every recording and never collapses unsupported work into a
/// stage-wide success bit.
struct GoldenEyeRamRomDemoCoverageV6: Sendable, Equatable {
    let demoID: UInt8
    let stageID: UInt32
    let variant: UInt32
    let assetName: String
    let unsupportedVisibleCommandMask: UInt32
    let unsupportedVisibleCommandCount: UInt32
    let sourceHash: UInt64
    let packetHash: UInt64
    let environmentPacketHash: UInt64
    let environmentCommandCount: UInt32
    let environmentVertexCount: UInt32

    var isRenderable: Bool {
        unsupportedVisibleCommandMask == 0 && unsupportedVisibleCommandCount == 0
    }
}

struct GoldenEyeRamRomUnsupportedManifestV6: Sendable, Equatable {
    let entries: [GoldenEyeRamRomDemoCoverageV6]
    let aggregateHash: UInt64

    var isComplete: Bool {
        entries.count == GoldenEyeRamRomRouteCatalog.sourceAssetNames.count &&
            entries.allSatisfy(\.isRenderable)
    }

    static func make(
        routes: [GoldenEyeRamRomDemoRoute],
        coverageByStage: [UInt32: GoldenEyeRamRomStageCoverageV6],
        environmentByStage: [UInt32: GoldenEyeStageBackgroundDrawPacket] = [:]
    ) -> Self {
        let entries = routes.map { route in
            let coverage = coverageByStage[route.stageID]
            return GoldenEyeRamRomDemoCoverageV6(
                demoID: route.demoID, stageID: route.stageID, variant: route.variant,
                assetName: route.assetName,
                unsupportedVisibleCommandMask: coverage?.unsupportedVisibleCommandMask ?? UInt32.max,
                unsupportedVisibleCommandCount: coverage?.unsupportedVisibleCommandCount ?? UInt32.max,
                sourceHash: coverage?.sourceHash ?? 0,
                packetHash: coverage?.packetHash ?? 0,
                environmentPacketHash: environmentByStage[route.stageID]?.packetHash ?? 0,
                environmentCommandCount: UInt32(environmentByStage[route.stageID]?.commands.count ?? 0),
                environmentVertexCount: UInt32(environmentByStage[route.stageID]?.vertices.count ?? 0)
            )
        }
        var hash = GoldenEyeCastSceneV6Hash.offsetBasis
        for entry in entries {
            for word in [
                UInt64(entry.demoID), UInt64(entry.stageID), UInt64(entry.variant),
                UInt64(entry.unsupportedVisibleCommandMask),
                UInt64(entry.unsupportedVisibleCommandCount), entry.sourceHash,
                entry.packetHash, entry.environmentPacketHash,
                UInt64(entry.environmentCommandCount), UInt64(entry.environmentVertexCount),
            ] {
                hash = GoldenEyeCastSceneV6Hash.mix(hash, word)
            }
            for byte in entry.assetName.utf8 {
                hash = GoldenEyeCastSceneV6Hash.mix(hash, UInt64(byte))
            }
        }
        return Self(entries: entries, aggregateHash: hash)
    }
}

struct GoldenEyeRamRomAuthorityFrameV6: Sendable, Equatable {
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let pairPhase: UInt32
    public let demoID: UInt32
    public let stageID: UInt32
    public let packetIndex: UInt32
    public let packetCount: UInt32
    public let sourceFrame: UInt32
    public let speedframes: UInt32
    public let sampleHash: UInt64
    public let authorityStateHash: UInt64
    public let recordingHash: UInt64
    public let rngHash: UInt64
    public let stageCoverage: GoldenEyeRamRomStageCoverageV6?
    public let environmentPacketHash: UInt64
    public let environmentCommandCount: UInt32
    public let environmentVertexCount: UInt32
    public let eventKind: GoldenEyeRamRomPlaybackEventKind
    public let eventFlags: UInt32
    public let diagnosticCode: UInt32
    public let isSourceAnchor: Bool

    public var isRenderable: Bool {
        stageCoverage?.isRenderable == true
    }

    var hasEnvironmentGeometry: Bool {
        environmentCommandCount > 0 && environmentVertexCount > 0
    }

    var isFadeToTitle: Bool { eventKind == .fadeToTitle }
    var isReturnToTitle: Bool { eventKind == .returnToTitle }
    var isRealInputAbort: Bool {
        (eventFlags & UInt32(GE_RAMROM_PLAYBACK_EVENT_FLAG_ABORTED_INPUT)) != 0
    }
}

/// A source-anchor owner around the existing V5 C playback service.  C still
/// owns packet decoding, checksums, speedframes, RNG checkpoints and exact
/// 60 Hz recording consumption.  This adapter owns only copied presentation
/// snapshots and never calls the diagnostic stage-line renderer.
@available(macOS 27.0, *)
final class GoldenEyeRamRomAuthorityV6: @unchecked Sendable {
    let service: GoldenEyeRamRomPlaybackService
    private(set) var request: GoldenEyeRamRomLaunchRequest?
    private(set) var stageCoverage: GoldenEyeRamRomStageCoverageV6?
    private(set) var environmentPacket: GoldenEyeStageBackgroundDrawPacket?
    private(set) var previousAnchor: GoldenEyeRamRomAuthorityFrameV6?
    private(set) var currentAnchor: GoldenEyeRamRomAuthorityFrameV6?
    private(set) var lastError: String?

    init(service: GoldenEyeRamRomPlaybackService) {
        self.service = service
    }

    var isActive: Bool { service.isActive }

    @discardableResult
    func begin(
        request: GoldenEyeRamRomLaunchRequest,
        atNativeTick nativeTick: UInt64,
        stageCoverage: GoldenEyeRamRomStageCoverageV6?,
        environmentPacket: GoldenEyeStageBackgroundDrawPacket? = nil
    ) throws -> GoldenEyeRamRomAuthorityFrameV6 {
        let event = try service.begin(request: request, atNativeTick: nativeTick)
        self.request = request
        self.stageCoverage = stageCoverage
        self.environmentPacket = environmentPacket
        let frame = makeFrame(event: event, nativeTick: nativeTick, sourceAnchor: true)
        previousAnchor = nil
        currentAnchor = frame
        lastError = nil
        return frame
    }

    /// Steps the exact V5 owner timeline.  Odd ticks are presentation-only:
    /// they must not advance packet index, source frame, RNG, or authority
    /// hashes.  The returned frame is a declared interpolated snapshot, not a
    /// second gameplay step.
    @discardableResult
    func step(
        nativeTick: UInt64,
        input: GoldenEyeRamRomServiceInput
    ) throws -> GoldenEyeRamRomAuthorityFrameV6? {
        guard let request else { return nil }
        guard let event = try service.step(nativeTick: nativeTick, input: input) else {
            return nil
        }
        let sourceAnchor = event.kind == .sample || event.isFadeToTitle || event.isReturnToTitle
        let eventFrame = makeFrame(event: event, nativeTick: nativeTick, sourceAnchor: sourceAnchor)
        if sourceAnchor, event.kind == .sample {
            guard event.demoID == UInt32(request.demoID),
                  event.stageID == request.stageID,
                  event.recordingHash == request.recordingHash,
                  event.rngHash == request.rngHash else {
                let detail = "demo/stage/recording/RNG identity differs from the guarded request"
                lastError = detail
                throw GoldenEyeCastSceneV6Error.authorityMismatch(detail)
            }
            previousAnchor = currentAnchor
            currentAnchor = eventFrame
        }
        if nativeTick & 1 == 1, let currentAnchor {
            // RAMROM gameplay has exact 60 Hz authority. There is no source
            // pose in V5, so interpolation is represented by the paired
            // snapshot identity and does not consume another packet.
            return GoldenEyeRamRomAuthorityFrameV6(
                nativeTick: nativeTick, referenceTick: nativeTick >> 1,
                pairPhase: 1, demoID: currentAnchor.demoID,
                stageID: currentAnchor.stageID,
                packetIndex: currentAnchor.packetIndex,
                packetCount: currentAnchor.packetCount,
                sourceFrame: currentAnchor.sourceFrame,
                speedframes: currentAnchor.speedframes,
                sampleHash: currentAnchor.sampleHash,
                authorityStateHash: currentAnchor.authorityStateHash,
                recordingHash: currentAnchor.recordingHash,
                rngHash: currentAnchor.rngHash,
                stageCoverage: self.stageCoverage,
                environmentPacketHash: currentAnchor.environmentPacketHash,
                environmentCommandCount: currentAnchor.environmentCommandCount,
                environmentVertexCount: currentAnchor.environmentVertexCount,
                eventKind: eventFrame.eventKind,
                eventFlags: eventFrame.eventFlags,
                diagnosticCode: eventFrame.diagnosticCode,
                isSourceAnchor: false
            )
        }
        return eventFrame
    }

    func stopAfterFailure() -> GoldenEyeRamRomRestoreSnapshot? {
        service.stopAfterFailure()
    }

    private func makeFrame(
        event: GoldenEyeRamRomPlaybackEvent,
        nativeTick: UInt64,
        sourceAnchor: Bool
    ) -> GoldenEyeRamRomAuthorityFrameV6 {
        GoldenEyeRamRomAuthorityFrameV6(
            nativeTick: nativeTick, referenceTick: event.referenceTick,
            pairPhase: event.pairPhase, demoID: event.demoID,
            stageID: event.stageID, packetIndex: event.packetIndex,
            packetCount: event.packetCount, sourceFrame: event.sourceFrame,
            speedframes: event.speedframes, sampleHash: event.sampleHash,
            authorityStateHash: event.stateHash,
            recordingHash: event.recordingHash, rngHash: event.rngHash,
            stageCoverage: stageCoverage,
            environmentPacketHash: environmentPacket?.packetHash ?? 0,
            environmentCommandCount: UInt32(environmentPacket?.commands.count ?? 0),
            environmentVertexCount: UInt32(environmentPacket?.vertices.count ?? 0),
            eventKind: event.kind,
            eventFlags: event.flags, diagnosticCode: event.diagnosticCode,
            isSourceAnchor: sourceAnchor
        )
    }
}

public enum GoldenEyeCastSceneV6Hash {
    public static let offsetBasis: UInt64 = 1_469_598_103_934_665_603
    public static let prime: UInt64 = 1_099_511_628_211

    public static func mix(_ initial: UInt64, _ word: UInt64) -> UInt64 {
        var hash = initial
        for shift in stride(from: 0, to: 64, by: 8) {
            hash = (hash ^ ((word >> UInt64(shift)) & 0xff)) &* prime
        }
        return hash
    }

    public static func mix(_ initial: UInt64, _ word: Int32) -> UInt64 {
        mix(initial, UInt64(bitPattern: Int64(word)))
    }

    public static func frame(
        nativeTick: UInt64, sourceIndex: UInt16, bodyID: UInt16,
        headID: UInt32, weaponID: UInt16, animationID: UInt32,
        sourceFrameQ16: Int32, fadeQ16: Int32, poseHash: UInt64,
        unsupported: UInt32
    ) -> UInt64 {
        var hash = offsetBasis
        for value in [nativeTick, UInt64(sourceIndex), UInt64(bodyID), UInt64(headID),
                     UInt64(weaponID), UInt64(animationID), poseHash,
                     UInt64(unsupported)] {
            hash = mix(hash, value)
        }
        hash = mix(hash, sourceFrameQ16)
        hash = mix(hash, fadeQ16)
        return hash
    }
}
