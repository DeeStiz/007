import Foundation

/// The first native stage-owner seam for the attract recordings.  This is a
/// deliberately bounded gameplay-independent core: it owns source setup
/// identity, fixed-point player/camera state, pad lookup, room/portal graph
/// traversal, and source-record summaries.  It does not execute AI scripts,
/// weapons, effects, collision, or renderer commands.
///
/// Every public value is copied fixed-width data.  In particular, setup
/// offsets remain offsets and never become host pointers.
public struct GoldenEyeStageFixedVector3: Sendable, Equatable {
    public let x: Int64
    public let y: Int64
    public let z: Int64

    public init(x: Int64, y: Int64, z: Int64) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct GoldenEyeStagePadLookup: Sendable, Equatable {
    public let isBound: Bool
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let position: GoldenEyeStageFixedVector3
    public let look: GoldenEyeStageFixedVector3
    public let up: GoldenEyeStageFixedVector3
    public let stanOffset: UInt32
    public let linkOffset: UInt32
}

public struct GoldenEyeStagePlayerState: Sendable, Equatable {
    public let position: GoldenEyeStageFixedVector3
    public let currentPad: GoldenEyeStagePadLookup?
    public let currentRoom: UInt32
    public let lastPortal: UInt32?
}

public struct GoldenEyeStageCameraState: Sendable, Equatable {
    public let position: GoldenEyeStageFixedVector3
    public let forward: GoldenEyeStageFixedVector3
    public let up: GoldenEyeStageFixedVector3
}

public struct GoldenEyeStageDoorSummary: Sendable, Equatable {
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let presetID: UInt32
    public let padID: UInt32
    public let state: UInt32
    public let flags1: UInt32
    public let flags2: UInt32
    public let portalHint: UInt32
}

public struct GoldenEyeStageGuardSummary: Sendable, Equatable {
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let characterID: UInt32
    public let padID: UInt32
    public let state: UInt32
    public let flags1: UInt32
    public let flags2: UInt32
}

public struct GoldenEyeStageObjectiveSummary: Sendable, Equatable {
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let type: UInt32
    public let key0: UInt32
    public let key1: UInt32
    public let state: UInt32
}

public struct GoldenEyeStageGameplaySummary: Sendable, Equatable {
    public let objectCount: UInt32
    public let doorCount: UInt32
    public let guardCount: UInt32
    public let objectiveCount: UInt32
    public let tintedGlassCount: UInt32
    public let padCount: UInt32
    public let boundPadCount: UInt32
    public let waypointCount: UInt32
    public let patrolPathCount: UInt32
    public let aiListCount: UInt32
    public let roomCount: UInt32
    public let portalCount: UInt32
    public let sourceHash: UInt64
    public let packetHash: UInt64
    public let summaryHash: UInt64
}

public enum GoldenEyeStageGameplayDiagnosticCode: UInt32, Sendable, Equatable {
    case unsupportedEffects = 1
    case unsupportedAI = 2
    case unsupportedWeapons = 3
    case unsupportedCollision = 4
    case invalidPortal = 5
    case portalNotConnected = 6
    case invalidPadLink = 7
    case realInputAbort = 8
    case restoreApplied = 9
}

public struct GoldenEyeStageGameplayDiagnostic: Sendable, Equatable {
    public let code: GoldenEyeStageGameplayDiagnosticCode
    public let stageID: UInt32
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let detail0: UInt32
    public let detail1: UInt32
    public let message: String
}

/// Input consumed by the stage owner.  `portalIndex`, `nextPadSourceOffset`,
/// and `abortRequested` are owner-side seams, not claims that the source
/// controller packet contains those fields.  They let a future collision/
/// input adapter make an explicit bounded decision without storing a pointer.
public struct GoldenEyeStageGameplayInput: Sendable, Equatable {
    public let stickX: Int16
    public let stickY: Int16
    public let pressedButtons: UInt32
    public let heldButtons: UInt32
    public let focused: Bool
    public let sourceMask: UInt32
    public let portalIndex: UInt32?
    public let nextPadSourceOffset: UInt32?
    public let abortRequested: Bool

    public init(
        stickX: Int16 = 0,
        stickY: Int16 = 0,
        pressedButtons: UInt32 = 0,
        heldButtons: UInt32 = 0,
        focused: Bool = true,
        sourceMask: UInt32 = 0,
        portalIndex: UInt32? = nil,
        nextPadSourceOffset: UInt32? = nil,
        abortRequested: Bool = false
    ) {
        self.stickX = stickX
        self.stickY = stickY
        self.pressedButtons = pressedButtons
        self.heldButtons = heldButtons
        self.focused = focused
        self.sourceMask = sourceMask
        self.portalIndex = portalIndex
        self.nextPadSourceOffset = nextPadSourceOffset
        self.abortRequested = abortRequested
    }
}

public struct GoldenEyeStageGameplayRestoreSnapshot: Sendable, Equatable {
    public let stageID: UInt32
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let pairPhase: UInt32
    public let frameIndex: UInt64
    public let player: GoldenEyeStagePlayerState
    public let camera: GoldenEyeStageCameraState
    public let sourceHash: UInt64
    public let packetHash: UInt64
    public let stateHash: UInt64
}

public struct GoldenEyeStageGameplayFrame: Sendable, Equatable {
    public let stageID: UInt32
    public let stageName: String
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let pairPhase: UInt32
    public let frameIndex: UInt64
    public let player: GoldenEyeStagePlayerState
    public let camera: GoldenEyeStageCameraState
    public let summary: GoldenEyeStageGameplaySummary
    public let stateHash: UInt64
    public let diagnostics: [GoldenEyeStageGameplayDiagnostic]
    public let isActive: Bool
    public let isAborted: Bool
}

public enum GoldenEyeStageGameplayRuntimeError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidTick(UInt64, UInt64)
    case invalidPortal(UInt32)
    case portalNotConnected(UInt32, UInt32)
    case invalidPadLink(UInt32)
    case runtimeInactive
    case snapshotMismatch(UInt32, UInt32)

    public var description: String {
        switch self {
        case let .invalidTick(expected, actual):
            return "stage runtime requires sequential native tick " + String(expected) + ", got " + String(actual)
        case let .invalidPortal(index):
            return "stage runtime portal index " + String(index) + " is outside the source packet"
        case let .portalNotConnected(index, room):
            return "stage runtime portal " + String(index) + " is not connected to room " + String(room)
        case let .invalidPadLink(offset):
            return "stage runtime pad link 0x\(String(offset, radix: 16)) is not a copied source pad"
        case .runtimeInactive:
            return "stage runtime is inactive"
        case let .snapshotMismatch(expected, actual):
            return "stage restore snapshot stage " + String(actual) + " does not match " + String(expected)
        }
    }
}

/// A single-owner, deterministic stage seam.  It intentionally uses a class
/// only so the owner can retain one mutable instance; callers must keep all
/// mutating calls on the engine-owner thread.
public final class GoldenEyeStageGameplayRuntime: @unchecked Sendable {
    public static let realInputAbortMask: UInt32 = 1 << 10

    public let stageID: UInt32
    public let stageName: String
    public let sourceHash: UInt64
    public let packetHash: UInt64
    public let demoMask: UInt32
    public let summary: GoldenEyeStageGameplaySummary
    public let doors: [GoldenEyeStageDoorSummary]
    public let guards: [GoldenEyeStageGuardSummary]
    public let objectives: [GoldenEyeStageObjectiveSummary]

    private let packet: GoldenEyeStageScenePacket
    private let allPads: [GoldenEyeStagePadLookup]
    private var playerState: GoldenEyeStagePlayerState
    private var cameraState: GoldenEyeStageCameraState
    private var nativeTick: UInt64 = 0
    private var frameIndex: UInt64 = 0
    private var expectedTick: UInt64 = 0
    private var initialized = false
    private var active = true
    private var aborted = false
    private var restoreSnapshot: GoldenEyeStageGameplayRestoreSnapshot?
    private var diagnostics: [GoldenEyeStageGameplayDiagnostic] = []
    private var diagnosticKeys: Set<UInt64> = []

    public init(packet: GoldenEyeStageScenePacket) {
        self.packet = packet
        stageID = packet.stageID
        stageName = packet.stageName
        sourceHash = packet.setup.sourceHash
        packetHash = packet.packetHash
        demoMask = packet.demoMask

        let standardPads = packet.setup.pads.map {
            Self.lookup(isBound: false, index: $0.index, sourceOffset: $0.sourceRecordOffset,
                        position: $0.position, up: $0.up, look: $0.look,
                        linkOffset: $0.linkOffset, stanOffset: $0.stanOffset)
        }
        let boundedPads = packet.setup.boundPads.map {
            Self.lookup(isBound: true, index: $0.index, sourceOffset: $0.sourceRecordOffset,
                        position: $0.position, up: $0.up, look: $0.look,
                        linkOffset: $0.linkOffset, stanOffset: $0.stanOffset)
        }
        allPads = standardPads + boundedPads

        doors = packet.setup.objects.compactMap { object in
            guard object.type == 1 else { return nil }
            return GoldenEyeStageDoorSummary(
                index: object.index, sourceRecordOffset: object.sourceRecordOffset,
                presetID: object.key0, padID: object.key1, state: object.state,
                flags1: object.flags1, flags2: object.flags2, portalHint: object.portalHint
            )
        }
        guards = packet.setup.objects.compactMap { object in
            guard object.type == 9 else { return nil }
            return GoldenEyeStageGuardSummary(
                index: object.index, sourceRecordOffset: object.sourceRecordOffset,
                characterID: object.key0, padID: object.key1, state: object.state,
                flags1: object.flags1, flags2: object.flags2
            )
        }
        objectives = packet.setup.objects.compactMap { object in
            // PROPDEF_OBJECTIVE_START through PROPDEF_OBJECTIVE_COPY_ITEM are
            // source enum values 23...34.  The copied type/key/state words are
            // retained, while objective execution remains outside this seam.
            guard (23...34).contains(object.type) else { return nil }
            return GoldenEyeStageObjectiveSummary(
                index: object.index, sourceRecordOffset: object.sourceRecordOffset,
                type: object.type, key0: object.key0, key1: object.key1, state: object.state
            )
        }

        let summaryHash = Self.makeSummaryHash(packet: packet, pads: allPads,
                                                doors: doors, guards: guards,
                                                objectives: objectives)
        summary = GoldenEyeStageGameplaySummary(
            objectCount: UInt32(packet.setup.objects.count),
            doorCount: UInt32(doors.count),
            guardCount: UInt32(guards.count),
            objectiveCount: UInt32(objectives.count),
            tintedGlassCount: packet.setup.tintedGlassCount,
            padCount: UInt32(packet.setup.pads.count),
            boundPadCount: UInt32(packet.setup.boundPads.count),
            waypointCount: UInt32(packet.setup.waypoints.count),
            patrolPathCount: UInt32(packet.setup.patrolPaths.count),
            aiListCount: UInt32(packet.setup.aiLists.count),
            roomCount: UInt32(packet.rooms.count),
            portalCount: UInt32(packet.setup.portals.count),
            sourceHash: packet.setup.sourceHash,
            packetHash: packet.packetHash,
            summaryHash: summaryHash
        )

        let spawn = allPads.first ?? GoldenEyeStagePadLookup(
            isBound: false, index: 0, sourceRecordOffset: 0,
            position: GoldenEyeStageFixedVector3(x: 0, y: 0, z: 0),
            look: GoldenEyeStageFixedVector3(x: 0, y: 0, z: -65_536),
            up: GoldenEyeStageFixedVector3(x: 0, y: 65_536, z: 0),
            stanOffset: 0, linkOffset: 0
        )
        playerState = GoldenEyeStagePlayerState(
            position: spawn.position, currentPad: spawn,
            currentRoom: Self.initialRoom(packet: packet), lastPortal: nil
        )
        cameraState = GoldenEyeStageCameraState(
            position: spawn.position, forward: spawn.look, up: spawn.up
        )
        appendInitialDiagnostics()
    }

    public var currentFrame: GoldenEyeStageGameplayFrame {
        makeFrame()
    }

    public var isActive: Bool { active }
    public var isAborted: Bool { aborted }
    public var currentPlayer: GoldenEyeStagePlayerState { playerState }
    public var currentCamera: GoldenEyeStageCameraState { cameraState }
    public var currentNativeTick: UInt64 { nativeTick }
    public var currentReferenceTick: UInt64 { nativeTick >> 1 }
    public var currentPairPhase: UInt32 { UInt32(nativeTick & 1) }

    /// Advances exactly one native tick. Continuous fixed-point movement and
    /// pad/camera lookup run on both phases. Source-anchor counters and any
    /// future autonomous logic are intentionally confined to even ticks.
    @discardableResult
    public func step(
        nativeTick requestedTick: UInt64,
        input: GoldenEyeStageGameplayInput = GoldenEyeStageGameplayInput()
    ) throws -> GoldenEyeStageGameplayFrame {
        guard active else { throw GoldenEyeStageGameplayRuntimeError.runtimeInactive }
        guard requestedTick == expectedTick else {
            throw GoldenEyeStageGameplayRuntimeError.invalidTick(expectedTick, requestedTick)
        }
        if !initialized {
            initialized = true
        }
        nativeTick = requestedTick

        if input.abortRequested && input.focused && input.sourceMask != 0 {
            captureRestoreAndAbort(code: .realInputAbort, detail0: input.pressedButtons)
        } else if input.focused && input.sourceMask != 0 &&
                    (input.pressedButtons & Self.realInputAbortMask) != 0 {
            captureRestoreAndAbort(code: .realInputAbort, detail0: input.pressedButtons)
        }

        if active {
            applyContinuousInput(input)
            if let portalIndex = input.portalIndex {
                try traversePortal(index: portalIndex)
            }
            if let nextPadSourceOffset = input.nextPadSourceOffset {
                try moveToPad(sourceRecordOffset: nextPadSourceOffset)
            }
            // Autonomous source branches, AI, effects, and weapon behavior do
            // not run here. Their explicit diagnostics remain visible in every
            // frame and no parity claim is made for them.
            if requestedTick & 1 == 0 {
                frameIndex &+= 1
            }
        }
        expectedTick &+= 1
        return makeFrame()
    }

    /// Resolves a copied source pad record by its original file-local offset.
    @discardableResult
    public func moveToPad(sourceRecordOffset: UInt32) throws -> GoldenEyeStagePadLookup {
        guard let pad = allPads.first(where: { $0.sourceRecordOffset == sourceRecordOffset }) else {
            appendDiagnostic(.invalidPadLink, detail0: sourceRecordOffset, detail1: 0,
                             message: "source pad link is not present in the bounded setup packet")
            throw GoldenEyeStageGameplayRuntimeError.invalidPadLink(sourceRecordOffset)
        }
        setPad(pad)
        return pad
    }

    /// Follows a source setup `linkOffset` when the copied record resolves.
    @discardableResult
    public func followCurrentPadLink() throws -> GoldenEyeStagePadLookup? {
        guard let pad = playerState.currentPad, pad.linkOffset != 0 else { return nil }
        return try moveToPad(sourceRecordOffset: pad.linkOffset)
    }

    /// Traverses one source background portal. Geometry/occlusion is not
    /// executed; only the copied room connectivity is used.
    @discardableResult
    public func traversePortal(index: UInt32) throws -> UInt32 {
        guard index < UInt32(packet.setup.portals.count) else {
            appendDiagnostic(.invalidPortal, detail0: index, detail1: 0,
                             message: "portal index is outside the source setup packet")
            throw GoldenEyeStageGameplayRuntimeError.invalidPortal(index)
        }
        let portal = packet.setup.portals[Int(index)]
        let room = playerState.currentRoom
        let next: UInt32
        if room == portal.connectedRoom1 {
            next = portal.connectedRoom2
        } else if room == portal.connectedRoom2 {
            next = portal.connectedRoom1
        } else {
            appendDiagnostic(.portalNotConnected, detail0: index, detail1: room,
                             message: "portal is not connected to the current copied room")
            throw GoldenEyeStageGameplayRuntimeError.portalNotConnected(index, room)
        }
        guard next < UInt32(packet.rooms.count) else {
            appendDiagnostic(.invalidPortal, detail0: index, detail1: next,
                             message: "portal points outside the copied source room table")
            throw GoldenEyeStageGameplayRuntimeError.portalNotConnected(index, room)
        }
        playerState = GoldenEyeStagePlayerState(
            position: playerState.position, currentPad: playerState.currentPad,
            currentRoom: next, lastPortal: index
        )
        return next
    }

    /// Returns the nearest copied setup pad using integer squared distance.
    public func nearestPad(to position: GoldenEyeStageFixedVector3) -> GoldenEyeStagePadLookup? {
        guard !allPads.isEmpty else { return nil }
        return allPads.min { lhs, rhs in
            Self.distanceSquared(lhs.position, position) < Self.distanceSquared(rhs.position, position)
        }
    }

    /// Copies the pre-abort state, then stops the stage owner. The snapshot is
    /// available exactly once through `takeRestoreSnapshot`.
    public func takeRestoreSnapshot() -> GoldenEyeStageGameplayRestoreSnapshot? {
        defer { restoreSnapshot = nil }
        return restoreSnapshot
    }

    /// Restores a previously captured snapshot. This is an owner-side seam;
    /// no save/RAMROM bytes are retained or synthesized here.
    public func restore(_ snapshot: GoldenEyeStageGameplayRestoreSnapshot) throws {
        guard snapshot.stageID == stageID else {
            throw GoldenEyeStageGameplayRuntimeError.snapshotMismatch(stageID, snapshot.stageID)
        }
        playerState = snapshot.player
        cameraState = snapshot.camera
        nativeTick = snapshot.nativeTick
        expectedTick = nativeTick &+ 1
        frameIndex = snapshot.frameIndex
        active = true
        aborted = false
        restoreSnapshot = nil
        appendDiagnostic(.restoreApplied, detail0: UInt32(nativeTick & 0xffff_ffff), detail1: 0,
                         message: "stage owner restored its copied player/camera snapshot")
    }

    private func applyContinuousInput(_ input: GoldenEyeStageGameplayInput) {
        // Q16.16, one source-neutral bounded owner step. This is intentionally
        // not presented as source collision/physics; collision remains an
        // explicit unsupported diagnostic.
        let scale: Int64 = 512
        let dx = Int64(input.stickX) * scale / 80
        let dz = -Int64(input.stickY) * scale / 80
        let nextPosition = GoldenEyeStageFixedVector3(
            x: Self.saturatingAdd(playerState.position.x, dx),
            y: playerState.position.y,
            z: Self.saturatingAdd(playerState.position.z, dz)
        )
        let nearest = nearestPad(to: nextPosition) ?? playerState.currentPad
        playerState = GoldenEyeStagePlayerState(
            position: nextPosition, currentPad: nearest,
            currentRoom: playerState.currentRoom, lastPortal: playerState.lastPortal
        )
        if let nearest {
            cameraState = GoldenEyeStageCameraState(
                position: nextPosition, forward: nearest.look, up: nearest.up
            )
        } else {
            cameraState = GoldenEyeStageCameraState(
                position: nextPosition, forward: cameraState.forward, up: cameraState.up
            )
        }
    }

    private func setPad(_ pad: GoldenEyeStagePadLookup) {
        playerState = GoldenEyeStagePlayerState(
            position: pad.position, currentPad: pad,
            currentRoom: playerState.currentRoom, lastPortal: playerState.lastPortal
        )
        cameraState = GoldenEyeStageCameraState(
            position: pad.position, forward: pad.look, up: pad.up
        )
    }

    private func captureRestoreAndAbort(
        code: GoldenEyeStageGameplayDiagnosticCode,
        detail0: UInt32
    ) {
        guard active else { return }
        restoreSnapshot = GoldenEyeStageGameplayRestoreSnapshot(
            stageID: stageID, nativeTick: nativeTick,
            referenceTick: nativeTick >> 1, pairPhase: UInt32(nativeTick & 1),
            frameIndex: frameIndex, player: playerState, camera: cameraState,
            sourceHash: sourceHash, packetHash: packetHash, stateHash: stateHash()
        )
        active = false
        aborted = true
        appendDiagnostic(code, detail0: detail0, detail1: 0,
                         message: "real input requested a bounded stage abort; restore snapshot captured")
    }

    private func appendInitialDiagnostics() {
        appendDiagnostic(.unsupportedEffects, detail0: summary.tintedGlassCount,
                         detail1: summary.objectCount,
                         message: "stage effects/explosions/particles are not executed by this core")
        appendDiagnostic(.unsupportedAI, detail0: summary.guardCount,
                         detail1: summary.aiListCount,
                         message: "source guard records and AI lists are summarized but AI scripts are not executed")
        appendDiagnostic(.unsupportedWeapons, detail0: summary.objectCount,
                         detail1: summary.objectiveCount,
                         message: "weapon/projectile behavior is not executed by this core")
        appendDiagnostic(.unsupportedCollision, detail0: summary.roomCount,
                         detail1: summary.portalCount,
                         message: "Stan collision and portal geometry are not executed; room connectivity remains available")
    }

    private func appendDiagnostic(
        _ code: GoldenEyeStageGameplayDiagnosticCode,
        detail0: UInt32,
        detail1: UInt32,
        message: String
    ) {
        let key = (UInt64(code.rawValue) << 32) ^ UInt64(detail0)
        guard diagnosticKeys.insert(key).inserted else { return }
        diagnostics.append(
            GoldenEyeStageGameplayDiagnostic(
                code: code, stageID: stageID, nativeTick: nativeTick,
                referenceTick: nativeTick >> 1, detail0: detail0,
                detail1: detail1, message: message
            )
        )
    }

    private func makeFrame() -> GoldenEyeStageGameplayFrame {
        GoldenEyeStageGameplayFrame(
            stageID: stageID, stageName: stageName, nativeTick: nativeTick,
            referenceTick: nativeTick >> 1, pairPhase: UInt32(nativeTick & 1),
            frameIndex: frameIndex, player: playerState, camera: cameraState,
            summary: summary, stateHash: stateHash(), diagnostics: diagnostics,
            isActive: active, isAborted: aborted
        )
    }

    private func stateHash() -> UInt64 {
        var hash = Self.offsetBasis
        let words: [UInt64] = [
            UInt64(stageID), sourceHash, packetHash, nativeTick, frameIndex,
            UInt64(playerState.currentRoom), UInt64(playerState.lastPortal ?? UInt32.max),
            UInt64(bitPattern: playerState.position.x), UInt64(bitPattern: playerState.position.y),
            UInt64(bitPattern: playerState.position.z), UInt64(bitPattern: cameraState.forward.x),
            UInt64(bitPattern: cameraState.forward.y), UInt64(bitPattern: cameraState.forward.z),
            UInt64(active ? 1 : 0), UInt64(aborted ? 1 : 0), summary.summaryHash,
        ]
        for word in words { hash = Self.mixWord(hash, word) }
        return hash
    }

    private static let offsetBasis: UInt64 = 1469598103934665603
    private static let prime: UInt64 = 1099511628211

    private static func mixWord(_ initial: UInt64, _ word: UInt64) -> UInt64 {
        var hash = initial
        for shift in stride(from: 0, to: 64, by: 8) {
            hash = (hash ^ ((word >> UInt64(shift)) & 0xff)) &* prime
        }
        return hash
    }

    private static func lookup(
        isBound: Bool,
        index: UInt32,
        sourceOffset: UInt32,
        position: GoldenEyeStageSetupVectorBits,
        up: GoldenEyeStageSetupVectorBits,
        look: GoldenEyeStageSetupVectorBits,
        linkOffset: UInt32,
        stanOffset: UInt32
    ) -> GoldenEyeStagePadLookup {
        GoldenEyeStagePadLookup(
            isBound: isBound, index: index, sourceRecordOffset: sourceOffset,
            position: GoldenEyeStageFixedVector3(
                x: fixedFromFloatBits(position.x), y: fixedFromFloatBits(position.y),
                z: fixedFromFloatBits(position.z)
            ),
            look: GoldenEyeStageFixedVector3(
                x: fixedFromFloatBits(look.x), y: fixedFromFloatBits(look.y),
                z: fixedFromFloatBits(look.z)
            ),
            up: GoldenEyeStageFixedVector3(
                x: fixedFromFloatBits(up.x), y: fixedFromFloatBits(up.y),
                z: fixedFromFloatBits(up.z)
            ),
            stanOffset: stanOffset, linkOffset: linkOffset
        )
    }

    private static func fixedFromFloatBits(_ bits: UInt32) -> Int64 {
        let sign = (bits & 0x8000_0000) != 0 ? -1 : 1
        let exponent = Int((bits >> 23) & 0xff)
        let fraction = bits & 0x007f_ffff
        if exponent == 0xff { return sign < 0 ? Int64.min / 4 : Int64.max / 4 }
        if exponent == 0 && fraction == 0 { return 0 }
        let mantissa: Int64 = exponent == 0
            ? Int64(fraction)
            : Int64(0x0080_0000 | fraction)
        let unbiased = exponent == 0 ? -126 : exponent - 127
        // Float has 23 fraction bits and the destination has 16.
        let shift = unbiased - 7
        var magnitude: Int64
        if shift >= 0 {
            magnitude = mantissa > (Int64.max >> min(shift, 62))
                ? Int64.max : mantissa << min(shift, 62)
        } else {
            let right = min(-shift, 62)
            magnitude = mantissa >> right
        }
        return sign < 0 ? -magnitude : magnitude
    }

    private static func distanceSquared(
        _ lhs: GoldenEyeStageFixedVector3,
        _ rhs: GoldenEyeStageFixedVector3
    ) -> UInt64 {
        let dx = lhs.x &- rhs.x
        let dy = lhs.y &- rhs.y
        let dz = lhs.z &- rhs.z
        func square(_ value: Int64) -> UInt64 {
            let magnitude = value == Int64.min ? UInt64(Int64.max) : UInt64(abs(value))
            if magnitude == 0 { return 0 }
            if magnitude > UInt64.max / magnitude { return UInt64.max }
            return magnitude * magnitude
        }
        return square(dx) &+ square(dy) &+ square(dz)
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        if rhs > 0 && lhs > Int64.max - rhs { return Int64.max }
        if rhs < 0 && lhs < Int64.min - rhs { return Int64.min }
        return lhs + rhs
    }

    private static func initialRoom(packet: GoldenEyeStageScenePacket) -> UInt32 {
        guard !packet.rooms.isEmpty else { return 0 }
        return packet.rooms[0].roomIndex
    }

    private static func makeSummaryHash(
        packet: GoldenEyeStageScenePacket,
        pads: [GoldenEyeStagePadLookup],
        doors: [GoldenEyeStageDoorSummary],
        guards: [GoldenEyeStageGuardSummary],
        objectives: [GoldenEyeStageObjectiveSummary]
    ) -> UInt64 {
        var hash = offsetBasis
        hash = mixWord(hash, UInt64(packet.stageID))
        hash = mixWord(hash, packet.setup.sourceHash)
        hash = mixWord(hash, packet.packetHash)
        hash = mixWord(hash, UInt64(packet.rooms.count))
        hash = mixWord(hash, UInt64(packet.setup.portals.count))
        for pad in pads {
            for word in [UInt64(pad.isBound ? 1 : 0), UInt64(pad.index),
                         UInt64(pad.sourceRecordOffset), UInt64(bitPattern: pad.position.x),
                         UInt64(bitPattern: pad.position.y), UInt64(bitPattern: pad.position.z),
                         UInt64(pad.linkOffset), UInt64(pad.stanOffset)] {
                hash = mixWord(hash, word)
            }
        }
        for door in doors {
            for word in [UInt64(door.index), UInt64(door.sourceRecordOffset),
                         UInt64(door.presetID), UInt64(door.padID), UInt64(door.state),
                         UInt64(door.flags1), UInt64(door.flags2), UInt64(door.portalHint)] {
                hash = mixWord(hash, word)
            }
        }
        for guardRecord in guards {
            for word in [UInt64(guardRecord.index), UInt64(guardRecord.sourceRecordOffset),
                         UInt64(guardRecord.characterID), UInt64(guardRecord.padID), UInt64(guardRecord.state),
                         UInt64(guardRecord.flags1), UInt64(guardRecord.flags2)] {
                hash = mixWord(hash, word)
            }
        }
        for objective in objectives {
            for word in [UInt64(objective.index), UInt64(objective.sourceRecordOffset),
                         UInt64(objective.type), UInt64(objective.key0),
                         UInt64(objective.key1), UInt64(objective.state)] {
                hash = mixWord(hash, word)
            }
        }
        return hash
    }
}
