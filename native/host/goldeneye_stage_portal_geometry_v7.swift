import Foundation

/// One copied source background portal polygon. Coordinates are fixed Q16.16
/// values; room IDs and control bytes remain the source one-based/raw values.
public struct GoldenEyeStagePortalPointV7: Sendable, Equatable {
    public let xQ16: Int32
    public let yQ16: Int32
    public let zQ16: Int32
}

public struct GoldenEyeStagePortalGeometryV7: Sendable, Equatable {
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let geometryOffset: UInt32
    public let connectedRoom1: UInt32
    public let connectedRoom2: UInt32
    public let controlByte1: UInt8
    public let controlByte2: UInt8
    public let points: [GoldenEyeStagePortalPointV7]
    public let sourceHash: UInt64

    public var connectsRooms: Bool { connectedRoom1 != connectedRoom2 }

    public func connects(_ roomA: UInt32, _ roomB: UInt32) -> Bool {
        (connectedRoom1 == roomA && connectedRoom2 == roomB) ||
            (connectedRoom1 == roomB && connectedRoom2 == roomA)
    }
}

public struct GoldenEyeStagePortalGeometryCatalogV7: Sendable, Equatable {
    public let stageID: UInt32
    public let portals: [GoldenEyeStagePortalGeometryV7]
    public let sourceHash: UInt64
    public let aggregateHash: UInt64

    public var crossRoomPortalCount: Int {
        portals.reduce(into: 0) { if $1.connectsRooms { $0 += 1 } }
    }

    public func portalsBetween(roomA: UInt32, roomB: UInt32) -> [GoldenEyeStagePortalGeometryV7] {
        portals.filter { $0.connects(roomA, roomB) }
    }

    /// Return the first source portal whose polygon is crossed by the bounded
    /// segment. This mirrors the geometric portion of `bgGetPortalBetweenRooms`
    /// without inventing room IDs: callers still retain the raw connected-room
    /// pair and must decide whether the segment's endpoint rooms are valid.
    public func portalIntersectingSegment(
        startQ16: (Int32, Int32, Int32),
        endQ16: (Int32, Int32, Int32),
        roomA: UInt32? = nil,
        roomB: UInt32? = nil
    ) -> GoldenEyeStagePortalGeometryV7? {
        func vector(_ point: GoldenEyeStagePortalPointV7) -> (Double, Double, Double) {
            (Double(point.xQ16) / 65_536.0, Double(point.yQ16) / 65_536.0, Double(point.zQ16) / 65_536.0)
        }
        let start = (Double(startQ16.0) / 65_536.0, Double(startQ16.1) / 65_536.0, Double(startQ16.2) / 65_536.0)
        let end = (Double(endQ16.0) / 65_536.0, Double(endQ16.1) / 65_536.0, Double(endQ16.2) / 65_536.0)
        for portal in portals {
            if let roomA, let roomB, !portal.connects(roomA, roomB) { continue }
            guard portal.points.count >= 3 else { continue }
            let p0 = vector(portal.points[0]), p1 = vector(portal.points[1]), p2 = vector(portal.points[2])
            let a = (p1.0 - p0.0, p1.1 - p0.1, p1.2 - p0.2)
            let b = (p2.0 - p0.0, p2.1 - p0.1, p2.2 - p0.2)
            let normal = (
                a.1 * b.2 - a.2 * b.1,
                a.2 * b.0 - a.0 * b.2,
                a.0 * b.1 - a.1 * b.0
            )
            let length = sqrt(normal.0 * normal.0 + normal.1 * normal.1 + normal.2 * normal.2)
            guard length > 0.000001 else { continue }
            let n = (normal.0 / length, normal.1 / length, normal.2 / length)
            let d0 = (start.0 - p0.0) * n.0 + (start.1 - p0.1) * n.1 + (start.2 - p0.2) * n.2
            let d1 = (end.0 - p0.0) * n.0 + (end.1 - p0.1) * n.1 + (end.2 - p0.2) * n.2
            guard d0 == 0 || d1 == 0 || (d0 < 0) != (d1 < 0), abs(d0 - d1) > 0.000001 else { continue }
            let t = d0 / (d0 - d1)
            let hit = (start.0 + (end.0 - start.0) * t, start.1 + (end.1 - start.1) * t, start.2 + (end.2 - start.2) * t)
            let dominant = [abs(n.0), abs(n.1), abs(n.2)].enumerated().max { $0.element < $1.element }?.offset ?? 1
            var positive = true
            var negative = true
            for index in portal.points.indices {
                let nextIndex = (index + 1) % portal.points.count
                let a = vector(portal.points[index]), b = vector(portal.points[nextIndex])
                let cross: Double
                switch dominant {
                case 0: cross = (b.1 - a.1) * (hit.2 - a.2) - (b.2 - a.2) * (hit.1 - a.1)
                case 2: cross = (b.0 - a.0) * (hit.1 - a.1) - (b.1 - a.1) * (hit.0 - a.0)
                default: cross = (b.0 - a.0) * (hit.2 - a.2) - (b.2 - a.2) * (hit.0 - a.0)
                }
                positive = positive && cross >= -0.01
                negative = negative && cross <= 0.01
            }
            if positive || negative { return portal }
        }
        return nil
    }

    public enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case malformedHeader(UInt32)
        case malformedGeometry(UInt32, UInt32, String)
        case invalidPointCount(UInt32, UInt32)
        case invalidPoint(UInt32, UInt32)
        case duplicatePortal(UInt32)

        public var description: String {
            switch self {
            case let .malformedHeader(stage): return "stage \(stage) portal geometry payload header is malformed"
            case let .malformedGeometry(portal, offset, detail):
                return "portal \(portal) geometry at 0x\(String(offset, radix: 16)) is malformed: \(detail)"
            case let .invalidPointCount(portal, count): return "portal \(portal) has invalid point count \(count)"
            case let .invalidPoint(portal, point): return "portal \(portal) point \(point) is not finite"
            case let .duplicatePortal(portal): return "portal \(portal) appears more than once"
            }
        }
    }

    /// Parse the exact `bg_portal_entry` layout from `src/game/bg.h`: one
    /// byte point count, three padding bytes, then packed big-endian float32
    /// `coord3d` points. Connectivity/control metadata comes from setup.
    public static func make(
        stageID: UInt32,
        setup: GoldenEyeStageSetupPacket,
        backgroundData: Data,
        maxPointsPerPortal: Int = 32
    ) throws -> Self {
        guard setup.stageID == stageID, maxPointsPerPortal >= 3, maxPointsPerPortal <= 255 else {
            throw Error.malformedHeader(stageID)
        }
        var portals: [GoldenEyeStagePortalGeometryV7] = []
        portals.reserveCapacity(setup.portals.count)
        var seen = Set<UInt32>()
        var aggregate = fnvWord(UInt64(stageID))
        for portal in setup.portals {
            guard seen.insert(portal.index).inserted else { throw Error.duplicatePortal(portal.index) }
            let offset = Int(portal.geometryOffset)
            guard offset >= 0, offset + 4 <= backgroundData.count else {
                throw Error.malformedGeometry(portal.index, portal.geometryOffset, "header bounds")
            }
            let count = Int(backgroundData[offset])
            guard count >= 3, count <= maxPointsPerPortal else {
                throw Error.invalidPointCount(portal.index, UInt32(count))
            }
            let byteCount = 4 + count * 12
            guard offset <= backgroundData.count - byteCount else {
                throw Error.malformedGeometry(portal.index, portal.geometryOffset, "point bounds")
            }
            var points: [GoldenEyeStagePortalPointV7] = []
            points.reserveCapacity(count)
            var hash = fnvWord(UInt64(portal.index))
            hash = fnvWord(UInt64(portal.sourceRecordOffset), into: hash)
            hash = fnvWord(UInt64(portal.geometryOffset), into: hash)
            hash = fnvWord(UInt64(portal.connectedRoom1), into: hash)
            hash = fnvWord(UInt64(portal.connectedRoom2), into: hash)
            hash = fnvWord(UInt64(portal.controlBytes), into: hash)
            hash = fnvWord(UInt64(count), into: hash)
            for pointIndex in 0..<count {
                let pointOffset = offset + 4 + pointIndex * 12
                let values = [
                    Float(bitPattern: readBE32(backgroundData, pointOffset)),
                    Float(bitPattern: readBE32(backgroundData, pointOffset + 4)),
                    Float(bitPattern: readBE32(backgroundData, pointOffset + 8)),
                ]
                guard values.allSatisfy({ $0.isFinite }) else {
                    throw Error.invalidPoint(portal.index, UInt32(pointIndex))
                }
                let q16 = values.map { Int32(clamping: Int64((Double($0) * 65_536.0).rounded(.toNearestOrAwayFromZero))) }
                let point = GoldenEyeStagePortalPointV7(xQ16: q16[0], yQ16: q16[1], zQ16: q16[2])
                points.append(point)
                hash = fnvWord(UInt64(bitPattern: Int64(point.xQ16)), into: hash)
                hash = fnvWord(UInt64(bitPattern: Int64(point.yQ16)), into: hash)
                hash = fnvWord(UInt64(bitPattern: Int64(point.zQ16)), into: hash)
            }
            let geometry = GoldenEyeStagePortalGeometryV7(
                index: portal.index, sourceRecordOffset: portal.sourceRecordOffset,
                geometryOffset: portal.geometryOffset, connectedRoom1: portal.connectedRoom1,
                connectedRoom2: portal.connectedRoom2,
                controlByte1: UInt8((portal.controlBytes >> 8) & 0xff),
                controlByte2: UInt8(portal.controlBytes & 0xff), points: points,
                sourceHash: hash
            )
            portals.append(geometry)
            aggregate = fnvWord(hash, into: aggregate)
        }
        return Self(stageID: stageID, portals: portals, sourceHash: fnvData(backgroundData), aggregateHash: aggregate)
    }

    private static func readBE32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 |
            UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }

    private static func fnvData(_ data: Data) -> UInt64 {
        data.reduce(UInt64(1_469_598_103_934_665_603)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    private static func fnvWord(_ value: UInt64, into initial: UInt64 = 1_469_598_103_934_665_603) -> UInt64 {
        stride(from: 0, to: 64, by: 8).reduce(initial) { hash, shift in
            (hash ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
        }
    }
}

/// Bounded source STAN floor catalog used only for source room sampling. It
/// deliberately keeps raw one-byte STAN room IDs; background room-index
/// normalization belongs at the camera/render boundary, not this setup-door
/// contract.
public struct GoldenEyeStageStanRoomCatalogV7: Sendable, Equatable {
    private struct Tile: Sendable, Equatable {
        let room: UInt32
        let points: [(Int32, Int32, Int32)]
        let sourceOffset: UInt32

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.room == rhs.room && lhs.points.map { [$0.0, $0.1, $0.2] } == rhs.points.map { [$0.0, $0.1, $0.2] } &&
                lhs.sourceOffset == rhs.sourceOffset
        }
    }

    private let tiles: [Tile]
    public let sourceHash: UInt64

    public static func make(data: Data, sourceHash: UInt64) throws -> Self {
        guard data.count >= 8 else { throw GoldenEyeStagePortalGeometryCatalogV7.Error.malformedHeader(0) }
        let first = Int(readBE32(data, 4))
        guard first >= 0, first < data.count else {
            throw GoldenEyeStagePortalGeometryCatalogV7.Error.malformedHeader(UInt32(data.count))
        }
        let sizes = [0x20, 0x20, 0x20, 0x20, 0x28, 0x30, 0x38, 0x40, 0x48, 0x50, 0x58, 0]
        var offset = first
        var tiles: [Tile] = []
        while offset + 8 <= data.count {
            let idRoom = readBE32(data, offset)
            if idRoom == 0 { break }
            let tail = readBE16(data, offset + 6)
            let count = Int((tail >> 12) & 0xf)
            guard count >= 3, count < sizes.count, sizes[count] != 0,
                  offset <= data.count - sizes[count] else {
                throw GoldenEyeStagePortalGeometryCatalogV7.Error.malformedGeometry(
                    UInt32.max, UInt32(offset), "STAN tile bounds"
                )
            }
            var points: [(Int32, Int32, Int32)] = []
            for index in 0..<count {
                let pointOffset = offset + 8 + index * 8
                let x = Int32(Int16(bitPattern: readBE16(data, pointOffset)))
                let y = Int32(Int16(bitPattern: readBE16(data, pointOffset + 2)))
                let z = Int32(Int16(bitPattern: readBE16(data, pointOffset + 4)))
                points.append((x, y, z))
            }
            tiles.append(Tile(room: idRoom & 0xff, points: points, sourceOffset: UInt32(offset)))
            offset += sizes[count]
            guard tiles.count <= 1_000_000 else {
                throw GoldenEyeStagePortalGeometryCatalogV7.Error.malformedHeader(UInt32(tiles.count))
            }
        }
        guard !tiles.isEmpty else { throw GoldenEyeStagePortalGeometryCatalogV7.Error.malformedHeader(0) }
        return Self(tiles: tiles, sourceHash: sourceHash)
    }

    public func room(forPositionQ16 position: (Int32, Int32, Int32), toleranceQ16: Int32 = 65_536) -> UInt32? {
        let x = Double(position.0) / 65_536.0
        let y = Double(position.1) / 65_536.0
        let z = Double(position.2) / 65_536.0
        let tolerance = Double(toleranceQ16) / 65_536.0
        var selected: (room: UInt32, floor: Double)?
        for tile in tiles {
            guard Self.inside(tile.points, x: x, z: z), let floor = Self.planeY(tile.points, x: x, z: z),
                  floor <= y + tolerance, selected == nil || floor > selected!.floor else { continue }
            selected = (tile.room, floor)
        }
        return selected?.room
    }

    private static func inside(_ points: [(Int32, Int32, Int32)], x: Double, z: Double) -> Bool {
        var positive = true
        var negative = true
        for index in points.indices {
            let next = (index + 1) % points.count
            let ax = Double(points[index].0), az = Double(points[index].2)
            let bx = Double(points[next].0), bz = Double(points[next].2)
            let cross = (bx - ax) * (z - az) - (bz - az) * (x - ax)
            positive = positive && cross >= -0.001
            negative = negative && cross <= 0.001
        }
        return positive || negative
    }

    private static func planeY(_ points: [(Int32, Int32, Int32)], x: Double, z: Double) -> Double? {
        guard points.count >= 3 else { return nil }
        let a = points[0], b = points[1], c = points[2]
        let ux = Double(b.0 - a.0), uy = Double(b.1 - a.1), uz = Double(b.2 - a.2)
        let vx = Double(c.0 - a.0), vy = Double(c.1 - a.1), vz = Double(c.2 - a.2)
        let normalY = uz * vx - ux * vz
        guard abs(normalY) > 0.000001 else { return nil }
        let normalX = uy * vz - uz * vy
        let normalZ = ux * vy - uy * vx
        return Double(a.1) - (normalX * (x - Double(a.0)) + normalZ * (z - Double(a.2))) / normalY
    }

    private static func readBE16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func readBE32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 |
            UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }
}
