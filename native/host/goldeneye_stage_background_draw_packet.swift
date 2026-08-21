import Compression
import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

@available(macOS 26.0, *)
protocol GoldenEyeStageSourceEnvironmentFrameRendererV6: AnyObject {
    func submit(
        sourceEnvironmentPacket: GoldenEyeStageBackgroundDrawPacket,
        nativeTick: UInt64
    ) throws
}

/// Optional additive handoff for source GBI/RDP state. Consumers that do not
/// lower material state remain compatible with the environment-only seam.
@available(macOS 26.0, *)
protocol GoldenEyeStageSourceMaterialFrameRendererV6: AnyObject {
    /// True only after the verified stage IMAGE/TLUT sidecar has been loaded,
    /// uploaded, and committed to the shared resident Metal texture store.
    var stageTextureDependenciesReady: Bool { get }

    func submit(
        sourceEnvironmentPacket: GoldenEyeStageBackgroundDrawPacket,
        materialPacket: GoldenEyeStageSourceMaterialPacketV6,
        nativeTick: UInt64
    ) throws
}

/// Additive M27 stage-background draw packet.
///
/// The original M27 contract emits a deterministic diagnostic overlay from
/// room-table metadata and portal connectivity. The additive source
/// environment builder below now also lowers copied room triangles and portal
/// polygons from guarded background payloads; the legacy builder remains
/// unchanged for historical evidence. Every field crossing either seam is a
/// copied fixed-width value; no Data, pointer, ROM address, source path, Metal
/// object, or mutable source graph is stored.
public enum GoldenEyeStageBackgroundDrawPrimitive: UInt32, Sendable, Equatable {
    case roomMarker = 1
    case portalEdge = 2
    /// A copied source portal polygon. This is separate from the legacy
    /// room-marker/portal-edge diagnostics and is only emitted by the source
    /// environment builder below.
    case portalPolygon = 3
    /// A triangle decoded from a source room point table and primary GDL.
    case roomTriangle = 4
}

public enum GoldenEyeStageBackgroundDrawDiagnosticCode: UInt32, Sendable, Equatable {
    case unsupportedBackgroundDisplayLists = 1
    case unsupportedRoomGeometry = 2
    case unsupportedProps = 3
    case unsupportedCharacters = 4
    case unsupportedAI = 5
    case unsupportedEffects = 6
    case invalidRoomPosition = 7
    case invalidPortal = 8
    case projectionRejected = 9
}

public struct GoldenEyeStageBackgroundDrawDiagnostic: Sendable, Equatable {
    public let code: GoldenEyeStageBackgroundDrawDiagnosticCode
    public let stageID: UInt32
    public let sourceIndex: UInt32
    public let detail0: UInt32
    public let detail1: UInt32
    public let message: String

    public init(
        code: GoldenEyeStageBackgroundDrawDiagnosticCode,
        stageID: UInt32,
        sourceIndex: UInt32 = 0,
        detail0: UInt32 = 0,
        detail1: UInt32 = 0,
        message: String
    ) {
        self.code = code
        self.stageID = stageID
        self.sourceIndex = sourceIndex
        self.detail0 = detail0
        self.detail1 = detail1
        self.message = message
    }
}

/// A Metal-ready line vertex. Positions are signed Q16.16 clip coordinates;
/// the eventual MSL vertex function can divide by `clipWQ16` without any
/// source address or host pointer lookup.
public struct GoldenEyeStageBackgroundDrawVertex: Sendable, Equatable {
    public let clipXQ16: Int32
    public let clipYQ16: Int32
    public let clipZQ16: Int32
    public let clipWQ16: Int32
    public let colorRGBA8: UInt32
    public let roomIndex: UInt32
    public let flags: UInt32
    public let reserved: UInt32

    /// The source environment packet keeps its historical 32-byte vertex
    /// stride.  Source Vtx S/T values therefore occupy the reserved word as
    /// two signed S10.5 lanes (high 16 bits S, low 16 bits T).  Diagnostic
    /// marker vertices leave this word zero.  Keeping the lanes here avoids a
    /// second pointer-bearing or platform-specific vertex ABI while allowing
    /// the generic source-scene adapter to consume authored UVs.
    public var sourceTextureS10_5: Int32 {
        Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: reserved >> 16)))
    }

    public var sourceTextureT10_5: Int32 {
        Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: reserved)))
    }

    public var sourceTextureCoordinatesPresent: Bool {
        reserved != 0
    }

    public static func packedSourceTextureCoordinates(
        s10_5: Int32,
        t10_5: Int32
    ) -> UInt32 {
        UInt32(UInt16(bitPattern: Int16(clamping: s10_5))) << 16
            | UInt32(UInt16(bitPattern: Int16(clamping: t10_5)))
    }

    public init(
        clipXQ16: Int32,
        clipYQ16: Int32,
        clipZQ16: Int32,
        clipWQ16: Int32,
        colorRGBA8: UInt32,
        roomIndex: UInt32,
        flags: UInt32,
        reserved: UInt32 = 0
    ) {
        self.clipXQ16 = clipXQ16
        self.clipYQ16 = clipYQ16
        self.clipZQ16 = clipZQ16
        self.clipWQ16 = clipWQ16
        self.colorRGBA8 = colorRGBA8
        self.roomIndex = roomIndex
        self.flags = flags
        self.reserved = reserved
    }
}

public struct GoldenEyeStageBackgroundDrawCommand: Sendable, Equatable {
    public let primitive: GoldenEyeStageBackgroundDrawPrimitive
    public let vertexStart: UInt32
    public let vertexCount: UInt32
    public let sourceIndex: UInt32
    public let sourceRecordOffset: UInt32
    public let metadataHash: UInt64
    public let flags: UInt32
    public let reserved: UInt32

    public init(
        primitive: GoldenEyeStageBackgroundDrawPrimitive,
        vertexStart: UInt32,
        vertexCount: UInt32,
        sourceIndex: UInt32,
        sourceRecordOffset: UInt32,
        metadataHash: UInt64,
        flags: UInt32,
        reserved: UInt32 = 0
    ) {
        self.primitive = primitive
        self.vertexStart = vertexStart
        self.vertexCount = vertexCount
        self.sourceIndex = sourceIndex
        self.sourceRecordOffset = sourceRecordOffset
        self.metadataHash = metadataHash
        self.flags = flags
        self.reserved = reserved
    }
}

/// Immutable stage draw data. Arrays contain only copied value records and
/// are bounded by the source parser's room/portal limits. `unsupportedMask`
/// is intentionally non-zero for the current M27 slice so a caller cannot
/// mistake the diagnostic overlay for full stage rendering.
public struct GoldenEyeStageBackgroundDrawPacket: Sendable, Equatable {
    public static let abiVersion: UInt32 = 1
    public static let contractVersion: UInt32 = 27
    public static let headerBytes: UInt32 = 64

    public static let unsupportedBackgroundDisplayLists: UInt32 = 1 << 0
    public static let unsupportedRoomGeometry: UInt32 = 1 << 1
    public static let unsupportedProps: UInt32 = 1 << 2
    public static let unsupportedCharacters: UInt32 = 1 << 3
    public static let unsupportedAI: UInt32 = 1 << 4
    public static let unsupportedEffects: UInt32 = 1 << 5

    public let abiVersion: UInt32
    public let headerBytes: UInt32
    public let contractVersion: UInt32
    public let stageID: UInt32
    public let roomCount: UInt32
    public let portalCount: UInt32
    public let commandCount: UInt32
    public let vertexCount: UInt32
    public let unsupportedMask: UInt32
    public let viewportFlags: UInt32
    public let sourceHash: UInt64
    public let scenePacketHash: UInt64
    public let packetHash: UInt64
    public let vertices: [GoldenEyeStageBackgroundDrawVertex]
    /// Additive source eye-space Z values parallel to `vertices`.  This is
    /// optional so the historical M27 marker packet retains its frozen hash
    /// and contract; source-environment packets populate it before the clip
    /// divide, where the exact fog equation still has the source depth.
    public let eyeSpaceZQ16: [Int32]?
    /// Optional source-symmetric fog coordinate (2 * Metal depth - 1 in
    /// Q16.16), parallel to `vertices`. It is computed before the generic
    /// snapshot discards clip-W and is separate from the historical
    /// UV/reserved word.
    public let fogCoordinateQ16: [Int32]?
    public let commands: [GoldenEyeStageBackgroundDrawCommand]
    public let diagnostics: [GoldenEyeStageBackgroundDrawDiagnostic]

    public var hasUnsupportedWork: Bool { unsupportedMask != 0 }

    fileprivate init(
        stageID: UInt32,
        roomCount: UInt32,
        portalCount: UInt32,
        viewportFlags: UInt32,
        sourceHash: UInt64,
        scenePacketHash: UInt64,
        unsupportedMask: UInt32,
        vertices: [GoldenEyeStageBackgroundDrawVertex],
        eyeSpaceZQ16: [Int32]? = nil,
        fogCoordinateQ16: [Int32]? = nil,
        commands: [GoldenEyeStageBackgroundDrawCommand],
        diagnostics: [GoldenEyeStageBackgroundDrawDiagnostic]
    ) {
        self.abiVersion = Self.abiVersion
        self.headerBytes = Self.headerBytes
        self.contractVersion = Self.contractVersion
        self.stageID = stageID
        self.roomCount = roomCount
        self.portalCount = portalCount
        self.commandCount = UInt32(commands.count)
        self.vertexCount = UInt32(vertices.count)
        self.unsupportedMask = unsupportedMask
        self.viewportFlags = viewportFlags
        self.sourceHash = sourceHash
        self.scenePacketHash = scenePacketHash
        self.vertices = vertices
        if let eyeSpaceZQ16 {
            precondition(eyeSpaceZQ16.count == vertices.count)
        }
        self.eyeSpaceZQ16 = eyeSpaceZQ16
        if let fogCoordinateQ16 {
            precondition(fogCoordinateQ16.count == vertices.count)
        }
        self.fogCoordinateQ16 = fogCoordinateQ16
        self.commands = commands
        self.diagnostics = diagnostics

        var hash = StageBackgroundDrawHash.offsetBasis
        hash = StageBackgroundDrawHash.append(hash, Self.abiVersion)
        hash = StageBackgroundDrawHash.append(hash, Self.headerBytes)
        hash = StageBackgroundDrawHash.append(hash, Self.contractVersion)
        hash = StageBackgroundDrawHash.append(hash, stageID)
        hash = StageBackgroundDrawHash.append(hash, roomCount)
        hash = StageBackgroundDrawHash.append(hash, portalCount)
        hash = StageBackgroundDrawHash.append(hash, UInt32(commands.count))
        hash = StageBackgroundDrawHash.append(hash, UInt32(vertices.count))
        hash = StageBackgroundDrawHash.append(hash, unsupportedMask)
        hash = StageBackgroundDrawHash.append(hash, viewportFlags)
        hash = StageBackgroundDrawHash.append(hash, sourceHash)
        hash = StageBackgroundDrawHash.append(hash, scenePacketHash)
        for vertex in vertices {
            hash = StageBackgroundDrawHash.append(hash, UInt32(bitPattern: vertex.clipXQ16))
            hash = StageBackgroundDrawHash.append(hash, UInt32(bitPattern: vertex.clipYQ16))
            hash = StageBackgroundDrawHash.append(hash, UInt32(bitPattern: vertex.clipZQ16))
            hash = StageBackgroundDrawHash.append(hash, UInt32(bitPattern: vertex.clipWQ16))
            hash = StageBackgroundDrawHash.append(hash, vertex.colorRGBA8)
            hash = StageBackgroundDrawHash.append(hash, vertex.roomIndex)
            hash = StageBackgroundDrawHash.append(hash, vertex.flags)
            hash = StageBackgroundDrawHash.append(hash, vertex.reserved)
        }
        if let eyeSpaceZQ16 {
            hash = StageBackgroundDrawHash.append(hash, UInt32(0x4559_455a))
            for value in eyeSpaceZQ16 {
                hash = StageBackgroundDrawHash.append(hash, UInt32(bitPattern: value))
            }
        }
        if let fogCoordinateQ16 {
            hash = StageBackgroundDrawHash.append(hash, UInt32(0x464f_4751))
            for value in fogCoordinateQ16 {
                hash = StageBackgroundDrawHash.append(hash, UInt32(bitPattern: value))
            }
        }
        for command in commands {
            hash = StageBackgroundDrawHash.append(hash, command.primitive.rawValue)
            hash = StageBackgroundDrawHash.append(hash, command.vertexStart)
            hash = StageBackgroundDrawHash.append(hash, command.vertexCount)
            hash = StageBackgroundDrawHash.append(hash, command.sourceIndex)
            hash = StageBackgroundDrawHash.append(hash, command.sourceRecordOffset)
            hash = StageBackgroundDrawHash.append(hash, command.metadataHash)
            hash = StageBackgroundDrawHash.append(hash, command.flags)
            hash = StageBackgroundDrawHash.append(hash, command.reserved)
        }
        for diagnostic in diagnostics {
            hash = StageBackgroundDrawHash.append(hash, diagnostic.code.rawValue)
            hash = StageBackgroundDrawHash.append(hash, diagnostic.stageID)
            hash = StageBackgroundDrawHash.append(hash, diagnostic.sourceIndex)
            hash = StageBackgroundDrawHash.append(hash, diagnostic.detail0)
            hash = StageBackgroundDrawHash.append(hash, diagnostic.detail1)
        }
        self.packetHash = hash
    }

    /// Rebuilds only the copied geometry for a camera-owned clip pass.  The
    /// source room/portal provenance and unsupported-work declaration remain
    /// unchanged; the packet hash is recomputed over the replacement values.
    /// This is intentionally an in-module value transformation so the
    /// gameplay camera adapter never needs a pointer or source address.
    func replacingGeometry(
        vertices: [GoldenEyeStageBackgroundDrawVertex],
        commands: [GoldenEyeStageBackgroundDrawCommand],
        eyeSpaceZQ16: [Int32]? = nil,
        fogCoordinateQ16: [Int32]? = nil
    ) -> Self {
        Self(
            stageID: stageID,
            roomCount: roomCount,
            portalCount: portalCount,
            viewportFlags: viewportFlags,
            sourceHash: sourceHash,
            scenePacketHash: scenePacketHash,
            unsupportedMask: unsupportedMask,
            vertices: vertices,
            eyeSpaceZQ16: eyeSpaceZQ16,
            fogCoordinateQ16: fogCoordinateQ16,
            commands: commands,
            diagnostics: diagnostics
        )
    }
}

public enum GoldenEyeStageBackgroundDrawPacketError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidCapacity
    case invalidViewport
    case invalidProjection
    case viewportMismatch
    case roomLimitExceeded(UInt32)
    case portalLimitExceeded(UInt32)
    case vertexLimitExceeded
    case commandLimitExceeded

    public var description: String {
        switch self {
        case .invalidCapacity: return "stage background draw capacity is invalid"
        case .invalidViewport: return "stage background draw viewport is invalid"
        case .invalidProjection: return "stage background draw projection packet is invalid"
        case .viewportMismatch: return "stage background draw viewport does not match projection"
        case let .roomLimitExceeded(count): return "stage background room count " + String(count) + " exceeds bounded capacity"
        case let .portalLimitExceeded(count): return "stage background portal count " + String(count) + " exceeds bounded capacity"
        case .vertexLimitExceeded: return "stage background vertex count exceeds bounded capacity"
        case .commandLimitExceeded: return "stage background command count exceeds bounded capacity"
        }
    }
}

public struct GoldenEyeStageBackgroundDrawOptions: Sendable, Equatable {
    public let roomMarkerHalfExtentQ16: Int32
    public let maxRooms: UInt32
    public let maxPortals: UInt32
    public let maxVertices: UInt32
    public let maxCommands: UInt32

    public init(
        roomMarkerHalfExtentQ16: Int32 = 1_024,
        maxRooms: UInt32 = 4_096,
        maxPortals: UInt32 = 16_384,
        // Full source room display lists exceed the historical diagnostic
        // overlay's 65k vertex bound (Facility/Silo are the largest).  Keep
        // the bound finite but size it for the seven guarded RAMROM scenes.
        maxVertices: UInt32 = 1_000_000,
        maxCommands: UInt32 = 200_000
    ) {
        self.roomMarkerHalfExtentQ16 = roomMarkerHalfExtentQ16
        self.maxRooms = maxRooms
        self.maxPortals = maxPortals
        self.maxVertices = maxVertices
        self.maxCommands = maxCommands
    }
}

/// Builds a bounded diagnostic overlay from source room/portal records. The
/// projection is caller-owned value data and is checked before any command is
/// emitted. Source room display lists, models, and effects intentionally do
/// not enter this path.
public enum GoldenEyeStageBackgroundDrawPacketBuilder {
    public static func make(
        scene: GoldenEyeStageScenePacket,
        viewport: GoldenEyeProjectionV10.ViewportV10,
        projection: GoldenEyeProjectionV10.PacketV10,
        options: GoldenEyeStageBackgroundDrawOptions = GoldenEyeStageBackgroundDrawOptions()
    ) throws -> GoldenEyeStageBackgroundDrawPacket {
        guard options.roomMarkerHalfExtentQ16 > 0,
              options.maxRooms > 0,
              options.maxPortals > 0,
              options.maxVertices > 0,
              options.maxCommands > 0 else {
            throw GoldenEyeStageBackgroundDrawPacketError.invalidCapacity
        }
        guard projection.isValid else {
            throw GoldenEyeStageBackgroundDrawPacketError.invalidProjection
        }
        guard projection.viewport == viewport else {
            throw GoldenEyeStageBackgroundDrawPacketError.viewportMismatch
        }
        guard scene.rooms.count <= Int(options.maxRooms) else {
            throw GoldenEyeStageBackgroundDrawPacketError.roomLimitExceeded(UInt32(scene.rooms.count))
        }
        guard scene.setup.portals.count <= Int(options.maxPortals) else {
            throw GoldenEyeStageBackgroundDrawPacketError.portalLimitExceeded(UInt32(scene.setup.portals.count))
        }

        var vertices: [GoldenEyeStageBackgroundDrawVertex] = []
        var commands: [GoldenEyeStageBackgroundDrawCommand] = []
        var diagnostics: [GoldenEyeStageBackgroundDrawDiagnostic] = []
        vertices.reserveCapacity(scene.rooms.count * 8 + scene.setup.portals.count * 2)
        commands.reserveCapacity(scene.rooms.count + scene.setup.portals.count)

        let guardCount = scene.setup.objects.reduce(into: 0) { count, object in
            if object.type == 9 { count += 1 }
        }
        let objectiveCount = scene.setup.objects.reduce(into: 0) { count, object in
            if (23...34).contains(object.type) { count += 1 }
        }
        let propCount = scene.setup.objects.count - guardCount - objectiveCount
        var unsupportedMask =
            GoldenEyeStageBackgroundDrawPacket.unsupportedBackgroundDisplayLists |
            GoldenEyeStageBackgroundDrawPacket.unsupportedRoomGeometry |
            GoldenEyeStageBackgroundDrawPacket.unsupportedProps |
            GoldenEyeStageBackgroundDrawPacket.unsupportedCharacters |
            GoldenEyeStageBackgroundDrawPacket.unsupportedAI |
            GoldenEyeStageBackgroundDrawPacket.unsupportedEffects

        diagnostics.append(.init(
            code: .unsupportedBackgroundDisplayLists,
            stageID: scene.stageID,
            detail0: scene.background.sourceBytes,
            detail1: scene.background.roomCount,
            message: "source background display lists remain outside the M27 bounded lowering"
        ))
        diagnostics.append(.init(
            code: .unsupportedRoomGeometry,
            stageID: scene.stageID,
            detail0: UInt32(scene.rooms.count),
            detail1: scene.background.firstPayloadOffset,
            message: "room payload offsets are retained as metadata; room triangles are not lowered"
        ))
        diagnostics.append(.init(
            code: .unsupportedProps,
            stageID: scene.stageID,
            detail0: UInt32(max(propCount, 0)),
            message: "setup props are not submitted by the background draw packet"
        ))
        diagnostics.append(.init(
            code: .unsupportedCharacters,
            stageID: scene.stageID,
            detail0: UInt32(guardCount),
            message: "character/guard models are not submitted by the background draw packet"
        ))
        diagnostics.append(.init(
            code: .unsupportedAI,
            stageID: scene.stageID,
            detail0: UInt32(scene.setup.aiLists.count),
            message: "AI lists are source metadata only and never become draw commands"
        ))
        diagnostics.append(.init(
            code: .unsupportedEffects,
            stageID: scene.stageID,
            detail0: 0,
            message: "stage effects are not represented in the copied background/setup packets"
        ))

        var projectedRooms: [UInt32: GoldenEyeProjectionV10.ClipVertexV10] = [:]
        projectedRooms.reserveCapacity(scene.rooms.count)
        for room in scene.rooms {
            guard let point = pointQ16(from: room.positionBits) else {
                diagnostics.append(.init(
                    code: .invalidRoomPosition,
                    stageID: scene.stageID,
                    sourceIndex: room.roomIndex,
                    detail0: room.positionBits.0,
                    detail1: room.positionBits.1,
                    message: "room position words are not finite bounded IEEE-754 values"
                ))
                continue
            }
            let projected = projection.transform(point)
            guard projected.clipWQ16 > 0 else {
                diagnostics.append(.init(
                    code: .invalidRoomPosition,
                    stageID: scene.stageID,
                    sourceIndex: room.roomIndex,
                    detail0: UInt32(bitPattern: projected.clipWQ16),
                    message: "room center is behind the supplied projection"
                ))
                continue
            }
            projectedRooms[room.roomIndex] = projected

            let color = roomColor(flags: room.flags)
            let xDelta = clipDelta(centerWQ16: projected.clipWQ16, halfExtentQ16: options.roomMarkerHalfExtentQ16)
            let yDelta = xDelta
            let start = UInt32(vertices.count)
            vertices.append(contentsOf: [
                vertex(projected, x: -xDelta, y: 0, z: 0, color: color, roomIndex: room.roomIndex),
                vertex(projected, x: xDelta, y: 0, z: 0, color: color, roomIndex: room.roomIndex),
                vertex(projected, x: 0, y: -yDelta, z: 0, color: color, roomIndex: room.roomIndex),
                vertex(projected, x: 0, y: yDelta, z: 0, color: color, roomIndex: room.roomIndex),
                // The Z-arm makes the packet useful for captures that render
                // the diagnostic overlay against a different camera basis.
                vertex(projected, x: 0, y: 0, z: -xDelta, color: color, roomIndex: room.roomIndex),
                vertex(projected, x: 0, y: 0, z: xDelta, color: color, roomIndex: room.roomIndex),
            ])
            commands.append(.init(
                primitive: .roomMarker,
                vertexStart: start,
                vertexCount: 6,
                sourceIndex: room.roomIndex,
                sourceRecordOffset: room.sourceRecordOffset,
                metadataHash: room.metadataHash,
                flags: room.flags
            ))
        }

        for (portalIndex, portal) in scene.setup.portals.enumerated() {
            guard let first = projectedRooms[portal.connectedRoom1],
                  let second = projectedRooms[portal.connectedRoom2] else {
                diagnostics.append(.init(
                    code: .invalidPortal,
                    stageID: scene.stageID,
                    sourceIndex: UInt32(portalIndex),
                    detail0: portal.connectedRoom1,
                    detail1: portal.connectedRoom2,
                    message: "portal endpoints do not resolve to projected copied rooms"
                ))
                continue
            }
            let start = UInt32(vertices.count)
            let color: UInt32 = 0xF0C060A0
            vertices.append(vertex(first, x: 0, y: 0, z: 0, color: color, roomIndex: portal.connectedRoom1))
            vertices.append(vertex(second, x: 0, y: 0, z: 0, color: color, roomIndex: portal.connectedRoom2))
            commands.append(.init(
                primitive: .portalEdge,
                vertexStart: start,
                vertexCount: 2,
                sourceIndex: UInt32(portalIndex),
                sourceRecordOffset: portal.sourceRecordOffset,
                metadataHash: scene.setup.packetHash,
                flags: portal.controlBytes
            ))
        }

        guard vertices.count <= Int(options.maxVertices) else {
            throw GoldenEyeStageBackgroundDrawPacketError.vertexLimitExceeded
        }
        guard commands.count <= Int(options.maxCommands) else {
            throw GoldenEyeStageBackgroundDrawPacketError.commandLimitExceeded
        }
        if diagnostics.contains(where: { $0.code == .invalidRoomPosition || $0.code == .invalidPortal }) {
            unsupportedMask |= GoldenEyeStageBackgroundDrawPacket.unsupportedRoomGeometry
        }

        return GoldenEyeStageBackgroundDrawPacket(
            stageID: scene.stageID,
            roomCount: UInt32(scene.rooms.count),
            portalCount: UInt32(scene.setup.portals.count),
            viewportFlags: viewport.flags,
            sourceHash: scene.background.sourceHash,
            scenePacketHash: scene.packetHash,
            unsupportedMask: unsupportedMask,
            vertices: vertices,
            commands: commands,
            diagnostics: diagnostics
        )
    }

    private static func pointQ16(
        from bits: (UInt32, UInt32, UInt32)
    ) -> GoldenEyeProjectionV10.PointQ16? {
        guard let x = boundedQ16(Float(bitPattern: bits.0)),
              let y = boundedQ16(Float(bitPattern: bits.1)),
              let z = boundedQ16(Float(bitPattern: bits.2)) else {
            return nil
        }
        return .init(x: x, y: y, z: z)
    }

    private static func boundedQ16(_ value: Float) -> Int32? {
        guard value.isFinite, abs(value) <= 32_000 else { return nil }
        let scaled = Double(value) * Double(GoldenEyeProjectionV10.q16One)
        guard scaled >= Double(Int32.min), scaled <= Double(Int32.max) else { return nil }
        return Int32(scaled.rounded(.toNearestOrAwayFromZero))
    }

    private static func clipDelta(centerWQ16: Int32, halfExtentQ16: Int32) -> Int32 {
        let numerator = Int64(centerWQ16) * Int64(halfExtentQ16)
        let value = numerator / GoldenEyeProjectionV10.q16One
        return Int32(clamping: value)
    }

    private static func vertex(
        _ center: GoldenEyeProjectionV10.ClipVertexV10,
        x: Int32,
        y: Int32,
        z: Int32,
        color: UInt32,
        roomIndex: UInt32
    ) -> GoldenEyeStageBackgroundDrawVertex {
        .init(
            clipXQ16: Int32(clamping: Int64(center.clipXQ16) + Int64(x)),
            clipYQ16: Int32(clamping: Int64(center.clipYQ16) + Int64(y)),
            clipZQ16: Int32(clamping: Int64(center.clipZQ16) + Int64(z)),
            clipWQ16: center.clipWQ16,
            colorRGBA8: color,
            roomIndex: roomIndex,
            flags: center.clipFlags
        )
    }

    private static func roomColor(flags: UInt32) -> UInt32 {
        if flags & UInt32(GE_STAGE_V5_BG_ROOM_FLAG_PRIMARY) != 0 { return 0x48B8FFFF }
        if flags & UInt32(GE_STAGE_V5_BG_ROOM_FLAG_SECONDARY) != 0 { return 0xF4B74CFF }
        if flags & UInt32(GE_STAGE_V5_BG_ROOM_FLAG_POINT) != 0 { return 0x60E0C0FF }
        return 0xD0D0D0FF
    }
}

/// First real source-environment slice for M27/M28. The background linker
/// stores room point/GDL payloads and portal visibility metadata in the
/// guarded background stream. This builder copies and triangulates both
/// source primary/secondary room display lists into the existing value-only
/// Metal vertex contract. Portals remain visibility/clipping inputs and are
/// deliberately not emitted as diagnostic tinted geometry.
public enum GoldenEyeStageSourceEnvironmentDrawPacketBuilderV6 {
    /// Reconcile the explicit environment-only capture scope with the
    /// source-room contract.  Props/characters/AI/effects can be omitted from
    /// a scoped capture only after both room/background bits have been proven
    /// clear by the producer.  Keeping this as a pure value operation makes
    /// malformed-mask coverage independent of a particular decoded stage
    /// payload and, importantly, prevents an unknown visible room opcode from
    /// being hidden by the scope bit clear.
    static func environmentOnlyCaptureUnsupportedMask(
        _ unsupportedMask: UInt32
    ) -> UInt32 {
        let roomAndBackgroundMask =
            GoldenEyeStageBackgroundDrawPacket.unsupportedBackgroundDisplayLists |
            GoldenEyeStageBackgroundDrawPacket.unsupportedRoomGeometry
        guard unsupportedMask & roomAndBackgroundMask == 0 else {
            return unsupportedMask
        }
        let omittedCategoryMask =
            GoldenEyeStageBackgroundDrawPacket.unsupportedProps |
            GoldenEyeStageBackgroundDrawPacket.unsupportedCharacters |
            GoldenEyeStageBackgroundDrawPacket.unsupportedAI |
            GoldenEyeStageBackgroundDrawPacket.unsupportedEffects
        return unsupportedMask & ~omittedCategoryMask
    }

    public static func make(
        scene: GoldenEyeStageScenePacket,
        viewport: GoldenEyeProjectionV10.ViewportV10,
        projection: GoldenEyeProjectionV10.PacketV10,
        options: GoldenEyeStageBackgroundDrawOptions = GoldenEyeStageBackgroundDrawOptions(),
        environmentOnlyCapture: Bool = false,
        visibleRoomIndices: Set<UInt32>? = nil,
        roomCoordinateScale: Double = 1.0,
        roomOrigin: GoldenEyeProjectionV10.PointQ16? = nil
    ) throws -> GoldenEyeStageBackgroundDrawPacket {
        guard roomCoordinateScale.isFinite, roomCoordinateScale > 0,
              roomCoordinateScale <= 64 else {
            throw GoldenEyeStageSourceEnvironmentDrawPacketError.invalidCoordinateScale
        }
        guard projection.isValid, projection.viewport == viewport else {
            throw GoldenEyeStageBackgroundDrawPacketError.viewportMismatch
        }
        guard scene.setup.portals.count <= Int(options.maxPortals) else {
            throw GoldenEyeStageBackgroundDrawPacketError.portalLimitExceeded(
                UInt32(scene.setup.portals.count)
            )
        }
        guard let background = scene.resources.first(where: { $0.kind == .background }) else {
            throw GoldenEyeStageSourceEnvironmentDrawPacketError.missingBackground
        }

        var vertices: [GoldenEyeStageBackgroundDrawVertex] = []
        var eyeSpaceZQ16: [Int32] = []
        var fogCoordinateQ16: [Int32] = []
        var commands: [GoldenEyeStageBackgroundDrawCommand] = []
        var diagnostics: [GoldenEyeStageBackgroundDrawDiagnostic] = []
        vertices.reserveCapacity(scene.setup.portals.count * 18)
        commands.reserveCapacity(scene.setup.portals.count)

        var unsupportedMask =
            GoldenEyeStageBackgroundDrawPacket.unsupportedBackgroundDisplayLists |
            GoldenEyeStageBackgroundDrawPacket.unsupportedRoomGeometry |
            GoldenEyeStageBackgroundDrawPacket.unsupportedProps |
            GoldenEyeStageBackgroundDrawPacket.unsupportedCharacters |
            GoldenEyeStageBackgroundDrawPacket.unsupportedAI |
            GoldenEyeStageBackgroundDrawPacket.unsupportedEffects
        diagnostics.append(.init(
            code: .unsupportedBackgroundDisplayLists,
            stageID: scene.stageID,
            detail0: scene.background.sourceBytes,
            detail1: scene.background.roomCount,
            message: "room display-list triangles remain outside the source-environment slice"
        ))
        diagnostics.append(.init(
            code: .unsupportedRoomGeometry,
            stageID: scene.stageID,
            detail0: UInt32(scene.rooms.count),
            detail1: scene.background.firstPayloadOffset,
            message: "only copied source portal polygons are lowered; room mappings remain pending"
        ))
        diagnostics.append(.init(
            code: .unsupportedProps,
            stageID: scene.stageID,
            detail0: UInt32(scene.setup.objects.count),
            message: "setup props remain outside the source-environment slice"
        ))
        diagnostics.append(.init(
            code: .unsupportedCharacters,
            stageID: scene.stageID,
            detail0: UInt32(scene.setup.objects.filter { $0.type == 9 }.count),
            message: "character/guard models remain outside the source-environment slice"
        ))
        diagnostics.append(.init(
            code: .unsupportedAI,
            stageID: scene.stageID,
            detail0: UInt32(scene.setup.aiLists.count),
            message: "AI state is not a source draw command in this slice"
        ))
        diagnostics.append(.init(
            code: .unsupportedEffects,
            stageID: scene.stageID,
            message: "stage effects remain outside the source-environment slice"
        ))

        // A room table may contain a valid room with no display-list payload,
        // and a visible room can have both primary and secondary GDLs.  Count
        // only rooms that actually carry a stream; comparing against the raw
        // room-table count made every stage look unsupported even when every
        // visible stream decoded successfully.
        var roomsWithDisplayLists = 0
        var loweredRoomCount = 0
        var loweredRoomTriangleCount = 0
        var unsupportedRoomCommandCount = 0
        for room in scene.rooms where visibleRoomIndices == nil ||
            visibleRoomIndices?.contains(room.roomIndex) == true {
            guard room.pointBytes > 0 else { continue }
            let candidateStreams: [(offset: UInt32, bytes: UInt32)] = [
                (offset: room.primaryOffset, bytes: room.primaryBytes),
                (offset: room.secondaryOffset, bytes: room.secondaryBytes),
            ]
            var seenStreamOffsets: Set<UInt32> = []
            let streams = candidateStreams.filter {
                $0.bytes > 0 && seenStreamOffsets.insert($0.offset).inserted
                    && hasRoomPayloadMarker(
                    background.payload,
                    offset: Int($0.offset),
                    byteCount: Int($0.bytes)
                )
            }
            guard !streams.isEmpty else { continue }
            roomsWithDisplayLists += 1
            var roomFailed = false
            do {
                let pointData = try inflateRoomPayload(
                    background.payload,
                    offset: Int(room.pointOffset),
                    byteCount: Int(room.pointBytes)
                )
                guard pointData.count >= 16, pointData.count % 16 == 0 else {
                    roomFailed = true
                    continue
                }
                let pointCount = pointData.count / 16
                guard let roomPosition = pointQ16(from: room.positionBits) else {
                    continue
                }
                var roomTriangleCount = 0
                for stream in streams {
                    let displayList = try inflateRoomPayload(
                        background.payload,
                        offset: Int(stream.offset),
                        byteCount: Int(stream.bytes)
                    )
                    var vertexBase = 0
                    var offset = 0
                    while offset + 8 <= displayList.count {
                        let word0 = try readBE32(displayList, at: offset)
                        let word1 = try readBE32(displayList, at: offset + 4)
                        let opcode = UInt8(truncatingIfNeeded: word0 >> 24)
                        switch opcode {
                        case 0x04: // F3DEX G_VTX; address is a source-local byte offset.
                            let localByteOffset = Int(word1 & 0x00ff_ffff)
                            guard localByteOffset >= 0, localByteOffset % 16 == 0,
                                  localByteOffset / 16 < pointCount else {
                                throw GoldenEyeStageSourceEnvironmentDrawPacketError.malformedRoomCommand(
                                    room.roomIndex, UInt32(offset)
                                )
                            }
                            // GoldenEye's compact triangle microcode carries
                            // the loaded vertex-window offset in the low
                            // address nibble.  The source bg.c consumer
                            // subtracts that nibble from each *10 triangle
                            // index; retain the equivalent rebased base here
                            // so room batches spanning a window do not fail
                            // closed as out-of-range geometry.
                            vertexBase = localByteOffset / 16 - Int(word1 & 0x0f)
                        case 0xb1: // GE's TRI4 extension occupies the G_TRI2 opcode.
                            // gbi_extension.h packs four 4-bit vertex lanes:
                            // x/y in word1 and z in word0.  The source bg.c
                            // consumer applies the loaded-window vtxoff to
                            // every lane; treating this as stock G_TRI2
                            // (byte lanes / 10) silently drops most room
                            // surfaces and rejects valid batches.
                            let triangles: [[Int]] = [
                                [
                                    Int(word1 & 0x0f),
                                    Int((word1 >> 4) & 0x0f),
                                    Int(word0 & 0x0f),
                                ],
                                [
                                    Int((word1 >> 8) & 0x0f),
                                    Int((word1 >> 12) & 0x0f),
                                    Int((word0 >> 4) & 0x0f),
                                ],
                                [
                                    Int((word1 >> 16) & 0x0f),
                                    Int((word1 >> 20) & 0x0f),
                                    Int((word0 >> 8) & 0x0f),
                                ],
                                [
                                    Int((word1 >> 24) & 0x0f),
                                    Int((word1 >> 28) & 0x0f),
                                    Int((word0 >> 12) & 0x0f),
                                ],
                            ]
                            for triangle in triangles {
                                let sourceIndices = triangle.map { vertexBase + $0 }
                                guard sourceIndices.allSatisfy({ $0 >= 0 && $0 < pointCount }) else {
                                    throw GoldenEyeStageSourceEnvironmentDrawPacketError.malformedRoomCommand(
                                        room.roomIndex, UInt32(offset)
                                    )
                                }
                                let start = UInt32(vertices.count)
                                for sourceIndex in sourceIndices {
                                    let lowered = try roomVertex(
                                        pointData,
                                        index: sourceIndex,
                                        roomPosition: roomPosition,
                                        roomCoordinateScale: roomCoordinateScale,
                                        roomOrigin: roomOrigin,
                                        projection: projection,
                                        roomIndex: room.roomIndex
                                    )
                                    vertices.append(lowered.vertex)
                                    eyeSpaceZQ16.append(lowered.eyeSpaceZQ16)
                                    fogCoordinateQ16.append(lowered.fogCoordinateQ16)
                                }
                                commands.append(.init(
                                    primitive: .roomTriangle,
                                    vertexStart: start,
                                    vertexCount: 3,
                                    sourceIndex: room.roomIndex,
                                    sourceRecordOffset: room.sourceRecordOffset,
                                    metadataHash: room.metadataHash,
                                    flags: room.flags
                                ))
                                roomTriangleCount += 1
                            }
                        case 0xbf: // GoldenEye's compact G_TRI1 uses vertex * 10.
                            let sourceIndices = [
                                vertexBase + Int((word1 >> 16) & 0xff) / 10,
                                vertexBase + Int((word1 >> 8) & 0xff) / 10,
                                vertexBase + Int(word1 & 0xff) / 10,
                            ]
                            guard sourceIndices.allSatisfy({ $0 >= 0 && $0 < pointCount }) else {
                                throw GoldenEyeStageSourceEnvironmentDrawPacketError.malformedRoomCommand(
                                    room.roomIndex, UInt32(offset)
                                )
                            }
                            let start = UInt32(vertices.count)
                            for sourceIndex in sourceIndices {
                                let lowered = try roomVertex(
                                    pointData,
                                    index: sourceIndex,
                                    roomPosition: roomPosition,
                                    roomCoordinateScale: roomCoordinateScale,
                                    roomOrigin: roomOrigin,
                                    projection: projection,
                                    roomIndex: room.roomIndex
                                )
                                vertices.append(lowered.vertex)
                                eyeSpaceZQ16.append(lowered.eyeSpaceZQ16)
                                fogCoordinateQ16.append(lowered.fogCoordinateQ16)
                            }
                            commands.append(.init(
                                primitive: .roomTriangle,
                                vertexStart: start,
                                vertexCount: 3,
                                sourceIndex: room.roomIndex,
                                sourceRecordOffset: room.sourceRecordOffset,
                                metadataHash: room.metadataHash,
                                flags: room.flags
                            ))
                            roomTriangleCount += 1
                        case 0xba, 0xb9, 0xbb, 0xfd,
                             0xf0, 0xf3, 0xf4, 0xb6, 0xb7,
                             0xfc, 0xfa, 0xf9, 0xfb, 0xf5, 0xf2,
                             0xc0, 0xe7:
                            // Source state is lowered by the paired
                            // material packet; it is represented in this
                            // environment pass without emitting geometry.
                            break
                        case 0xb8, 0xdf: // G_ENDDL variants.
                            offset = displayList.count
                            continue
                        default:
                            // State-only source commands are consumed by the
                            // material lowerer. Any other opcode is retained
                            // as a visible-command gap instead of being
                            // silently treated as a no-op.
                            unsupportedRoomCommandCount += 1
                        }
                        offset += 8
                    }
                }
                if !roomFailed {
                    loweredRoomCount += 1
                    loweredRoomTriangleCount += roomTriangleCount
                }
            } catch {
                roomFailed = true
                // Keep the room unsupported and preserve the exact source
                // offset in diagnostics; one malformed room must not turn
                // into a guessed triangle strip.
                diagnostics.append(.init(
                    code: .invalidPortal,
                    stageID: scene.stageID,
                    sourceIndex: room.roomIndex,
                    detail0: room.primaryOffset,
                    detail1: room.primaryBytes,
                    message: "room primary GDL was not lowered: \(error)"
                ))
            }
        }
        if roomsWithDisplayLists == loweredRoomCount &&
            loweredRoomTriangleCount > 0 && unsupportedRoomCommandCount == 0 {
            unsupportedMask &= ~GoldenEyeStageBackgroundDrawPacket.unsupportedBackgroundDisplayLists
            unsupportedMask &= ~GoldenEyeStageBackgroundDrawPacket.unsupportedRoomGeometry
            diagnostics.removeAll {
                $0.code == .unsupportedRoomGeometry ||
                $0.code == .unsupportedBackgroundDisplayLists
            }
        } else if unsupportedRoomCommandCount > 0 {
            diagnostics.append(.init(
                code: .unsupportedRoomGeometry,
                stageID: scene.stageID,
                detail0: UInt32(unsupportedRoomCommandCount),
                message: "room GDL contains unsupported visible command opcodes"
            ))
        }

        guard vertices.count <= Int(options.maxVertices) else {
            throw GoldenEyeStageBackgroundDrawPacketError.vertexLimitExceeded
        }
        guard commands.count <= Int(options.maxCommands) else {
            throw GoldenEyeStageBackgroundDrawPacketError.commandLimitExceeded
        }
        guard !commands.isEmpty else {
            throw GoldenEyeStageSourceEnvironmentDrawPacketError.noRoomGeometry
        }

        if environmentOnlyCapture {
            // This explicit capture mode exercises only the room-source
            // producer represented by this packet. Props/characters/AI/
            // effects are outside the capture's declared visible workload.
            // Never clear their bits while a room/background bit remains set:
            // a malformed or unknown visible room command must remain
            // fail-closed instead of becoming a presentable mask=0 packet.
            let roomAndBackgroundMask =
                GoldenEyeStageBackgroundDrawPacket.unsupportedBackgroundDisplayLists |
                GoldenEyeStageBackgroundDrawPacket.unsupportedRoomGeometry
            if unsupportedMask & roomAndBackgroundMask == 0 {
                unsupportedMask = environmentOnlyCaptureUnsupportedMask(unsupportedMask)
                diagnostics.removeAll { diagnostic in
                    switch diagnostic.code {
                    case .unsupportedProps, .unsupportedCharacters,
                         .unsupportedAI, .unsupportedEffects:
                        return true
                    default:
                        return false
                    }
                }
            }
        }

        return GoldenEyeStageBackgroundDrawPacket(
            stageID: scene.stageID,
            roomCount: UInt32(scene.rooms.count),
            portalCount: UInt32(scene.setup.portals.count),
            viewportFlags: viewport.flags,
            sourceHash: scene.background.sourceHash,
            scenePacketHash: scene.packetHash,
            unsupportedMask: unsupportedMask,
            vertices: vertices,
            eyeSpaceZQ16: eyeSpaceZQ16,
            fogCoordinateQ16: fogCoordinateQ16,
            commands: commands,
            diagnostics: diagnostics
        )
    }

    private static func inflateRoomPayload(
        _ data: Data,
        offset: Int,
        byteCount: Int
    ) throws -> Data {
        var payloadOffset = offset
        var payloadByteCount = byteCount
        // The final room row in several source background linkers points at
        // the four-byte zero padding immediately before the next section's
        // 1172 stream.  Preserve the bounded source range but normalize this
        // linker padding before handing bytes to Compression.
        if offset >= 0, byteCount >= 6, offset <= data.count,
           byteCount <= data.count - offset,
           data[offset] == 0, data[offset + 1] == 0,
           data[offset + 2] == 0, data[offset + 3] == 0,
           data[offset + 4] == 0x11, data[offset + 5] == 0x72 {
            payloadOffset += 4
            payloadByteCount -= 4
        }
        guard payloadOffset >= 0, payloadByteCount >= 2,
              payloadOffset <= data.count,
              payloadByteCount <= data.count - payloadOffset,
              data[payloadOffset] == 0x11,
              data[payloadOffset + 1] == 0x72 else {
            throw GoldenEyeStageSourceEnvironmentDrawPacketError.roomInflateFailure(
                UInt32(max(offset, 0)), UInt32(max(byteCount, 0))
            )
        }
        let input = data.subdata(in: (payloadOffset + 2)..<(payloadOffset + payloadByteCount))
        var capacity = max(16 * 1024, payloadByteCount * 32)
        while capacity <= 16 * 1024 * 1024 {
            var output = Data(count: capacity)
            let produced = output.withUnsafeMutableBytes { outputBytes -> Int in
                input.withUnsafeBytes { inputBytes -> Int in
                    guard let outputBase = outputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                          let inputBase = inputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return 0
                    }
                    return compression_decode_buffer(
                        outputBase, outputBytes.count, inputBase, inputBytes.count,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            if produced > 0, produced < capacity {
                output.removeSubrange(produced..<output.count)
                return output
            }
            capacity *= 2
        }
        throw GoldenEyeStageSourceEnvironmentDrawPacketError.roomInflateFailure(
            UInt32(max(offset, 0)), UInt32(max(byteCount, 0))
        )
    }

    private static func hasRoomPayloadMarker(
        _ data: Data,
        offset: Int,
        byteCount: Int
    ) -> Bool {
        guard offset >= 0, byteCount >= 2,
              offset <= data.count, byteCount <= data.count - offset else {
            return false
        }
        if data[offset] == 0x11, data[offset + 1] == 0x72 {
            return true
        }
        return byteCount >= 6
            && data[offset] == 0 && data[offset + 1] == 0
            && data[offset + 2] == 0 && data[offset + 3] == 0
            && data[offset + 4] == 0x11 && data[offset + 5] == 0x72
    }

    private static func pointQ16(
        from bits: (UInt32, UInt32, UInt32)
    ) -> GoldenEyeProjectionV10.PointQ16? {
        func convert(_ bits: UInt32) -> Int32? {
            let value = Float(bitPattern: bits)
            guard value.isFinite, abs(value) <= 32_000 else { return nil }
            let scaled = Double(value) * Double(GoldenEyeProjectionV10.q16One)
            guard scaled >= Double(Int32.min), scaled <= Double(Int32.max) else { return nil }
            return Int32(scaled.rounded(.toNearestOrAwayFromZero))
        }
        guard let x = convert(bits.0), let y = convert(bits.1), let z = convert(bits.2) else {
            return nil
        }
        return .init(x: x, y: y, z: z)
    }

    private static func roomVertex(
        _ data: Data,
        index: Int,
        roomPosition: GoldenEyeProjectionV10.PointQ16,
        roomCoordinateScale: Double,
        roomOrigin: GoldenEyeProjectionV10.PointQ16?,
        projection: GoldenEyeProjectionV10.PacketV10,
        roomIndex: UInt32
    ) throws -> (
        vertex: GoldenEyeStageBackgroundDrawVertex,
        eyeSpaceZQ16: Int32,
        fogCoordinateQ16: Int32
    ) {
        let offset = index * 16
        guard offset >= 0, offset <= data.count, data.count - offset >= 16 else {
            throw GoldenEyeStageSourceEnvironmentDrawPacketError.malformedRoomCommand(
                roomIndex, UInt32(max(offset, 0))
            )
        }
        func signed16(_ offset: Int) throws -> Int32 {
            let word = try readBE16(data, at: offset)
            return Int32(
                Int64(Int16(bitPattern: word)) * GoldenEyeProjectionV10.q16One
            )
        }
        func scaled(_ value: Int64) -> Int32 {
            Int32(clamping: Int64((Double(value) * roomCoordinateScale).rounded(
                .toNearestOrAwayFromZero
            )))
        }
        let origin = roomOrigin ?? .init(x: 0, y: 0, z: 0)
        let point = GoldenEyeProjectionV10.PointQ16(
            x: scaled(Int64(roomPosition.x) + Int64(try signed16(offset)) - Int64(origin.x)),
            y: scaled(Int64(roomPosition.y) + Int64(try signed16(offset + 2)) - Int64(origin.y)),
            z: scaled(Int64(roomPosition.z) + Int64(try signed16(offset + 4)) - Int64(origin.z))
        )
        let eyeSpace = projection.modelView.applying(to: point)
        let clip = projection.transform(point)
        guard clip.clipWQ16 != 0 else {
            throw GoldenEyeStageSourceEnvironmentDrawPacketError.pointBehindCamera(
                roomIndex, UInt32(index)
            )
        }
        let fogProduct = Int64(clip.clipZQ16) * Int64(GoldenEyeProjectionV10.q16One)
        let metalDepth = fogProduct / Int64(clip.clipWQ16)
        // The Metal projection stores depth in [0,1]. Source gSPFogPosition
        // consumes the symmetric clip-Z coordinate in [-1,1], so preserve
        // that source domain separately from the GPU position.z payload.
        let fogCoordinate = Int32(clamping: metalDepth * 2 - Int64(GoldenEyeProjectionV10.q16One))
        let color = (UInt32(data[offset + 12]) << 24) |
            (UInt32(data[offset + 13]) << 16) |
            (UInt32(data[offset + 14]) << 8) |
            UInt32(data[offset + 15])
        let sourceS10_5 = Int32(Int16(bitPattern: try readBE16(data, at: offset + 8)))
        let sourceT10_5 = Int32(Int16(bitPattern: try readBE16(data, at: offset + 10)))
        return (
            vertex: vertex(
                clip,
                color: color,
                sourceIndex: roomIndex,
                reserved: GoldenEyeStageBackgroundDrawVertex.packedSourceTextureCoordinates(
                    s10_5: sourceS10_5,
                    t10_5: sourceT10_5
                )
            ),
            eyeSpaceZQ16: eyeSpace.z,
            fogCoordinateQ16: fogCoordinate
        )
    }

    private static func readBE16(_ data: Data, at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset <= data.count, data.count - offset >= 2 else {
            throw GoldenEyeStageSourceEnvironmentDrawPacketError.malformedGeometry(
                UInt32.max, UInt32(max(offset, 0))
            )
        }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func readBE32(_ data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= data.count, data.count - offset >= 4 else {
            throw GoldenEyeStageSourceEnvironmentDrawPacketError.malformedGeometry(
                UInt32.max, UInt32(max(offset, 0))
            )
        }
        return UInt32(data[offset]) << 24 |
            UInt32(data[offset + 1]) << 16 |
            UInt32(data[offset + 2]) << 8 |
            UInt32(data[offset + 3])
    }

    private static func vertex(
        _ point: GoldenEyeProjectionV10.ClipVertexV10,
        color: UInt32,
        sourceIndex: UInt32,
        reserved: UInt32 = 0
    ) -> GoldenEyeStageBackgroundDrawVertex {
        .init(
            clipXQ16: point.clipXQ16,
            clipYQ16: point.clipYQ16,
            clipZQ16: point.clipZQ16,
            clipWQ16: point.clipWQ16,
            colorRGBA8: color,
            roomIndex: sourceIndex,
            flags: point.clipFlags,
            reserved: reserved
        )
    }

}

public enum GoldenEyeStageSourceEnvironmentDrawPacketError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingBackground
    case malformedGeometry(UInt32, UInt32)
    case invalidPointCount(UInt32, UInt32)
    case invalidPointValue(UInt32)
    case pointBehindCamera(UInt32, UInt32)
    case noPortalGeometry
    case noRoomGeometry
    case noRoomGeometryAfterClip(UInt32, UInt32, String)
    case invalidCoordinateScale
    case malformedRoomCommand(UInt32, UInt32)
    case roomInflateFailure(UInt32, UInt32)
    case missingFogCoordinate(UInt32)

    public var description: String {
        switch self {
        case .missingBackground: return "source environment packet is missing background payload"
        case let .malformedGeometry(portal, offset): return "portal \(portal) geometry is malformed at 0x\(String(offset, radix: 16))"
        case let .invalidPointCount(portal, count): return "portal \(portal) has invalid point count \(count)"
        case let .invalidPointValue(bits): return "portal point contains invalid float bits 0x\(String(bits, radix: 16))"
        case let .pointBehindCamera(portal, point): return "portal \(portal) point \(point) is behind the supplied projection"
        case .noPortalGeometry: return "source environment packet contains no portal triangles"
        case .noRoomGeometry: return "source environment packet contains no lowered room triangles"
        case let .noRoomGeometryAfterClip(input, output, details):
            return "source environment clip rejected all room triangles (input=\(input), output=\(output), \(details))"
        case .invalidCoordinateScale: return "source environment room coordinate scale is invalid"
        case let .malformedRoomCommand(room, offset): return "room \(room) source GDL command is malformed at 0x\(String(offset, radix: 16))"
        case let .roomInflateFailure(offset, bytes): return "room compressed payload at 0x\(String(offset, radix: 16)) failed inflate for \(bytes) bytes"
        case let .missingFogCoordinate(room):
            return "room \(room) clipped geometry is missing a parallel fog coordinate"
        }
    }
}

private enum StageBackgroundDrawHash {
    static let offsetBasis: UInt64 = 1_469_598_103_934_665_603
    static let prime: UInt64 = 1_099_511_628_211

    static func append(_ hash: UInt64, _ word: UInt32) -> UInt64 {
        var value = hash
        for shift in stride(from: 0, to: 32, by: 8) {
            value = (value ^ UInt64((word >> UInt32(shift)) & 0xff)) &* prime
        }
        return value
    }

    static func append(_ hash: UInt64, _ word: UInt64) -> UInt64 {
        var value = hash
        for shift in stride(from: 0, to: 64, by: 8) {
            value = (value ^ ((word >> UInt64(shift)) & 0xff)) &* prime
        }
        return value
    }
}
