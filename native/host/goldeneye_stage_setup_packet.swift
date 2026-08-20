import Foundation

/// A source-derived setup record with no pointer, path, ROM address, or
/// retained payload.  The bit fields intentionally remain in source order so
/// the packet can be compared without introducing host floating-point or
/// pointer semantics.
public struct GoldenEyeStageSetupVectorBits: Sendable, Equatable {
    public let x: UInt32
    public let y: UInt32
    public let z: UInt32
}

public struct GoldenEyeStageSetupBoundsBits: Sendable, Equatable {
    public let a: UInt32
    public let b: UInt32
    public let c: UInt32
    public let d: UInt32
    public let e: UInt32
    public let f: UInt32
}

public struct GoldenEyeStageSetupHeaderPacket: Sendable, Equatable {
    public let offsets: [UInt32]

    public var pathwaypointsOffset: UInt32 { offsets[0] }
    public var waypointGroupsOffset: UInt32 { offsets[1] }
    public var introOffset: UInt32 { offsets[2] }
    public var propDefinitionsOffset: UInt32 { offsets[3] }
    public var patrolPathsOffset: UInt32 { offsets[4] }
    public var aiListsOffset: UInt32 { offsets[5] }
    public var padsOffset: UInt32 { offsets[6] }
    public var boundPadsOffset: UInt32 { offsets[7] }
    public var padNamesOffset: UInt32 { offsets[8] }
    public var boundPadNamesOffset: UInt32 { offsets[9] }
}

public struct GoldenEyeStageSetupPadPacket: Sendable, Equatable {
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let position: GoldenEyeStageSetupVectorBits
    public let up: GoldenEyeStageSetupVectorBits
    public let look: GoldenEyeStageSetupVectorBits
    public let linkOffset: UInt32
    public let stanOffset: UInt32
}

public struct GoldenEyeStageSetupBoundPadPacket: Sendable, Equatable {
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let position: GoldenEyeStageSetupVectorBits
    public let up: GoldenEyeStageSetupVectorBits
    public let look: GoldenEyeStageSetupVectorBits
    public let linkOffset: UInt32
    public let stanOffset: UInt32
    public let bounds: GoldenEyeStageSetupBoundsBits
}

/// A bounded object/prop summary. `key0`/`key1` are the two source words after
/// the header (object/preset for generic props, chr/pad for guards). The
/// complete source record is never retained.
public struct GoldenEyeStageSetupObjectPacket: Sendable, Equatable {
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let type: UInt32
    public let scale8_8: UInt32
    public let state: UInt32
    public let key0: UInt32
    public let key1: UInt32
    public let flags1: UInt32
    public let flags2: UInt32
    public let recordBytes: UInt32
    /// Serialized ObjectRecord model matrix at +0x18. It is copied as raw
    /// IEEE-754 words; the existing setup packet hash remains unchanged and
    /// a later scene lowerer owns source quantization.
    public let matrixWords: [UInt32]
    /// For doors this is the serialized portal-number word at record + 0xf0;
    /// for tinted glass it is the serialized portal-number word at record +
    /// 0x8c. It is zero for other types.
    public let portalHint: UInt32
}

public struct GoldenEyeStageSetupIntroPacket: Sendable, Equatable {
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let type: UInt32
    public let wordCount: UInt32
    public let payloadHash: UInt64
}

public struct GoldenEyeStageSetupWaypointPacket: Sendable, Equatable {
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let padID: UInt32
    public let neighboursOffset: UInt32
    public let groupNumber: UInt32
    public let distance: UInt32
}

public struct GoldenEyeStageSetupWaygroupPacket: Sendable, Equatable {
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let neighboursOffset: UInt32
    public let waypointsOffset: UInt32
    public let distance: UInt32
}

public struct GoldenEyeStageSetupPatrolPathPacket: Sendable, Equatable {
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let waypointsOffset: UInt32
    public let pathID: UInt32
    public let isLoop: UInt32
    public let length: UInt32
}

public struct GoldenEyeStageSetupAIListPacket: Sendable, Equatable {
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let scriptOffset: UInt32
    public let identifier: UInt32
}

public struct GoldenEyeStageSetupPortalPacket: Sendable, Equatable {
    public let index: UInt32
    public let sourceRecordOffset: UInt32
    public let geometryOffset: UInt32
    public let connectedRoom1: UInt32
    public let connectedRoom2: UInt32
    public let controlBytes: UInt32
}

public struct GoldenEyeStageSetupSectionPacket: Sendable, Equatable {
    public let index: UInt32
    public let sourceOffset: UInt32
    public let sourceBytes: UInt32
    public let recordCount: UInt32
    public let metadataHash: UInt64
}

public struct GoldenEyeStageSetupPacket: Sendable, Equatable {
    public let stageID: UInt32
    public let sourceBytes: UInt32
    public let sourceHash: UInt64
    public let header: GoldenEyeStageSetupHeaderPacket
    public let sections: [GoldenEyeStageSetupSectionPacket]
    public let pads: [GoldenEyeStageSetupPadPacket]
    public let boundPads: [GoldenEyeStageSetupBoundPadPacket]
    public let objects: [GoldenEyeStageSetupObjectPacket]
    public let intros: [GoldenEyeStageSetupIntroPacket]
    public let waypoints: [GoldenEyeStageSetupWaypointPacket]
    public let waygroups: [GoldenEyeStageSetupWaygroupPacket]
    public let patrolPaths: [GoldenEyeStageSetupPatrolPathPacket]
    public let aiLists: [GoldenEyeStageSetupAIListPacket]
    public let padNameCount: UInt32
    public let boundPadNameCount: UInt32
    public let portalTableSegmentedOffset: UInt32
    public let portalTableOffset: UInt32
    public let portals: [GoldenEyeStageSetupPortalPacket]
    public let packetHash: UInt64

    public var doorCount: UInt32 {
        UInt32(objects.reduce(into: 0) { if $1.type == 1 { $0 += 1 } })
    }

    public var tintedGlassCount: UInt32 {
        UInt32(objects.reduce(into: 0) { if $1.type == 47 { $0 += 1 } })
    }

    public var portalHintCount: UInt32 {
        UInt32(objects.reduce(into: 0) { if $1.portalHint != 0 { $0 += 1 } })
    }

    public enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case invalidCapacity
        case emptyPayload
        case truncated(UInt32, UInt32, UInt32)
        case invalidHeader(UInt32, UInt32)
        case invalidOffset(UInt32, UInt32)
        case invalidSection(UInt32, UInt32, UInt32)
        case missingSentinel(UInt32)
        case capacityExceeded(UInt32, UInt32)
        case unsupportedObjectType(UInt32, UInt32)
        case unsupportedIntroType(UInt32, UInt32)
        case malformedPortalHeader(UInt32)
        case malformedPortalOffset(UInt32, UInt32)
        case missingPortalSentinel

        public var description: String {
            switch self {
            case .invalidCapacity: return "setup packet capacity is invalid"
            case .emptyPayload: return "setup packet payload is empty"
            case let .truncated(offset, needed, available):
                return "setup packet truncated at 0x\(String(offset, radix: 16)): need \(needed), have \(available)"
            case let .invalidHeader(index, value):
                return "setup header word \(index) is invalid: 0x\(String(value, radix: 16))"
            case let .invalidOffset(offset, byteCount):
                return "setup offset 0x\(String(offset, radix: 16)) is outside \(byteCount) bytes"
            case let .invalidSection(start, end, byteCount):
                return "setup section [0x\(String(start, radix: 16)), 0x\(String(end, radix: 16))) is invalid for \(byteCount) bytes"
            case let .missingSentinel(section):
                return "setup section \(section) has no bounded sentinel"
            case let .capacityExceeded(section, limit):
                return "setup section \(section) exceeds bounded record limit \(limit)"
            case let .unsupportedObjectType(type, offset):
                return "setup object type \(type) at 0x\(String(offset, radix: 16)) has no bounded size"
            case let .unsupportedIntroType(type, offset):
                return "setup intro type \(type) at 0x\(String(offset, radix: 16)) has no bounded size"
            case let .malformedPortalHeader(status):
                return "background portal header is malformed (status \(status))"
            case let .malformedPortalOffset(segmented, byteCount):
                return "background portal offset 0x\(String(segmented, radix: 16)) is outside \(byteCount) bytes"
            case .missingPortalSentinel: return "background portal table has no bounded sentinel"
            }
        }
    }

    private static let fnvOffset: UInt64 = 1469598103934665603
    private static let fnvPrime: UInt64 = 1099511628211
    private static let maxRecords: UInt32 = 16_384
    private static let maxPortals: UInt32 = 16_384

    /// Parse the source setup stream and, optionally, its background portal
    /// table. All offsets are copied as uint32 values and validated against the
    /// borrowed Data; no pointer or address escapes this function.
    public static func load(
        stageID: UInt32,
        setupData: Data,
        backgroundData: Data? = nil,
        maxBytes: Int = 64 * 1024 * 1024
    ) throws -> Self {
        guard maxBytes > 0 else { throw Error.invalidCapacity }
        guard !setupData.isEmpty else { throw Error.emptyPayload }
        guard setupData.count <= maxBytes else {
            throw Error.invalidCapacity
        }
        if let backgroundData, backgroundData.count > maxBytes {
            throw Error.invalidCapacity
        }
        let sourceHash = hashBytes(setupData)
        let rawOffsets = try (0..<10).map { index in
            try readWord(setupData, offset: index * 4)
        }
        for (index, offset) in rawOffsets.enumerated() {
            guard offset == 0 || (offset >= 40 && offset < setupData.count) else {
                throw Error.invalidHeader(UInt32(index), offset)
            }
            guard offset == 0 || (offset & 3) == 0 else {
                throw Error.invalidHeader(UInt32(index), offset)
            }
        }
        let header = GoldenEyeStageSetupHeaderPacket(offsets: rawOffsets)

        let padsEnd = try sectionEnd(start: rawOffsets[6], offsets: rawOffsets, byteCount: setupData.count)
        let boundPadsEnd = try sectionEnd(start: rawOffsets[7], offsets: rawOffsets, byteCount: setupData.count)
        let objectEnd = try sectionEnd(start: rawOffsets[3], offsets: rawOffsets, byteCount: setupData.count)
        let introEnd = try sectionEnd(start: rawOffsets[2], offsets: rawOffsets, byteCount: setupData.count)
        let waypointEnd = try sectionEnd(start: rawOffsets[0], offsets: rawOffsets, byteCount: setupData.count)
        let groupEnd = try sectionEnd(start: rawOffsets[1], offsets: rawOffsets, byteCount: setupData.count)
        let pathEnd = try sectionEnd(start: rawOffsets[4], offsets: rawOffsets, byteCount: setupData.count)
        let aiEnd = try sectionEnd(start: rawOffsets[5], offsets: rawOffsets, byteCount: setupData.count)
        let padNamesEnd = try sectionEnd(start: rawOffsets[8], offsets: rawOffsets, byteCount: setupData.count)
        let boundNamesEnd = try sectionEnd(start: rawOffsets[9], offsets: rawOffsets, byteCount: setupData.count)

        let pads = try parsePads(setupData, start: rawOffsets[6], end: padsEnd)
        let boundPads = try parseBoundPads(setupData, start: rawOffsets[7], end: boundPadsEnd)
        let objects = try parseObjects(setupData, start: rawOffsets[3], end: objectEnd)
        let intros = try parseIntros(setupData, start: rawOffsets[2], end: introEnd)
        let waypoints = try parseWaypoints(setupData, start: rawOffsets[0], end: waypointEnd)
        let waygroups = try parseWaygroups(setupData, start: rawOffsets[1], end: groupEnd)
        let patrolPaths = try parsePatrolPaths(setupData, start: rawOffsets[4], end: pathEnd)
        let aiLists = try parseAILists(setupData, start: rawOffsets[5], end: aiEnd)
        let padNameCount = try parseNameCount(setupData, start: rawOffsets[8], end: padNamesEnd)
        let boundPadNameCount = try parseNameCount(setupData, start: rawOffsets[9], end: boundNamesEnd)

        let portalResult: PortalResult
        if let backgroundData {
            portalResult = try parsePortals(backgroundData)
        } else {
            portalResult = PortalResult(segmentedOffset: 0, localOffset: 0, portals: [])
        }

        var sections: [GoldenEyeStageSetupSectionPacket] = []
        sections.reserveCapacity(10)
        let sectionValues: [(UInt32, UInt32, UInt32)] = [
            (0, rawOffsets[0], UInt32(waypoints.count)),
            (1, rawOffsets[1], UInt32(waygroups.count)),
            (2, rawOffsets[2], UInt32(intros.count)),
            (3, rawOffsets[3], UInt32(objects.count)),
            (4, rawOffsets[4], UInt32(patrolPaths.count)),
            (5, rawOffsets[5], UInt32(aiLists.count)),
            (6, rawOffsets[6], UInt32(pads.count)),
            (7, rawOffsets[7], UInt32(boundPads.count)),
            (8, rawOffsets[8], padNameCount),
            (9, rawOffsets[9], boundPadNameCount),
        ]
        for (index, (kind, start, count)) in sectionValues.enumerated() where start != 0 {
            let end = try sectionEnd(start: start, offsets: rawOffsets, byteCount: setupData.count)
            let metadataHash = hashWords(
                [kind, start, UInt32(end - Int(start)), count]
            )
            sections.append(
                GoldenEyeStageSetupSectionPacket(
                    index: UInt32(index),
                    sourceOffset: start,
                    sourceBytes: UInt32(end - Int(start)),
                    recordCount: count,
                    metadataHash: metadataHash
                )
            )
        }

        var packetHash = hashWords([
            UInt64(stageID), UInt64(setupData.count), sourceHash,
        ])
        packetHash = hashWords(rawOffsets, into: packetHash)
        packetHash = hashWords([
            UInt32(pads.count), UInt32(boundPads.count), UInt32(objects.count),
            UInt32(intros.count), UInt32(waypoints.count), UInt32(waygroups.count),
            UInt32(patrolPaths.count), UInt32(aiLists.count), padNameCount,
            boundPadNameCount, UInt32(portalResult.portals.count),
            portalResult.segmentedOffset, portalResult.localOffset,
        ], into: packetHash)
        for section in sections {
            packetHash = hashWords([
                UInt64(section.index), UInt64(section.sourceOffset),
                UInt64(section.sourceBytes), UInt64(section.recordCount),
                section.metadataHash,
            ], into: packetHash)
        }
        for pad in pads {
            packetHash = hashWords([
                UInt64(pad.index), UInt64(pad.sourceRecordOffset),
                UInt64(pad.position.x), UInt64(pad.position.y), UInt64(pad.position.z),
                UInt64(pad.up.x), UInt64(pad.up.y), UInt64(pad.up.z),
                UInt64(pad.look.x), UInt64(pad.look.y), UInt64(pad.look.z),
                UInt64(pad.linkOffset), UInt64(pad.stanOffset),
            ], into: packetHash)
        }
        for pad in boundPads {
            packetHash = hashWords([
                UInt64(pad.index), UInt64(pad.sourceRecordOffset),
                UInt64(pad.position.x), UInt64(pad.position.y), UInt64(pad.position.z),
                UInt64(pad.up.x), UInt64(pad.up.y), UInt64(pad.up.z),
                UInt64(pad.look.x), UInt64(pad.look.y), UInt64(pad.look.z),
                UInt64(pad.linkOffset), UInt64(pad.stanOffset),
                UInt64(pad.bounds.a), UInt64(pad.bounds.b), UInt64(pad.bounds.c),
                UInt64(pad.bounds.d), UInt64(pad.bounds.e), UInt64(pad.bounds.f),
            ], into: packetHash)
        }
        for object in objects {
            packetHash = hashWords([
                UInt64(object.index), UInt64(object.sourceRecordOffset),
                UInt64(object.type), UInt64(object.scale8_8), UInt64(object.state),
                UInt64(object.key0), UInt64(object.key1), UInt64(object.flags1),
                UInt64(object.flags2), UInt64(object.recordBytes),
                UInt64(object.portalHint),
            ], into: packetHash)
        }
        for intro in intros {
            packetHash = hashWords([
                UInt64(intro.index), UInt64(intro.sourceRecordOffset),
                UInt64(intro.type), UInt64(intro.wordCount), intro.payloadHash,
            ], into: packetHash)
        }
        for waypoint in waypoints {
            packetHash = hashWords([
                UInt64(waypoint.index), UInt64(waypoint.sourceRecordOffset),
                UInt64(waypoint.padID), UInt64(waypoint.neighboursOffset),
                UInt64(waypoint.groupNumber), UInt64(waypoint.distance),
            ], into: packetHash)
        }
        for group in waygroups {
            packetHash = hashWords([
                UInt64(group.index), UInt64(group.sourceRecordOffset),
                UInt64(group.neighboursOffset), UInt64(group.waypointsOffset),
                UInt64(group.distance),
            ], into: packetHash)
        }
        for path in patrolPaths {
            packetHash = hashWords([
                UInt64(path.index), UInt64(path.sourceRecordOffset),
                UInt64(path.waypointsOffset), UInt64(path.pathID),
                UInt64(path.isLoop), UInt64(path.length),
            ], into: packetHash)
        }
        for list in aiLists {
            packetHash = hashWords([
                UInt64(list.index), UInt64(list.sourceRecordOffset),
                UInt64(list.scriptOffset), UInt64(list.identifier),
            ], into: packetHash)
        }
        for portal in portalResult.portals {
            packetHash = hashWords([
                UInt64(portal.index), UInt64(portal.sourceRecordOffset),
                UInt64(portal.geometryOffset), UInt64(portal.connectedRoom1),
                UInt64(portal.connectedRoom2), UInt64(portal.controlBytes),
            ], into: packetHash)
        }

        return Self(
            stageID: stageID,
            sourceBytes: UInt32(setupData.count),
            sourceHash: sourceHash,
            header: header,
            sections: sections,
            pads: pads,
            boundPads: boundPads,
            objects: objects,
            intros: intros,
            waypoints: waypoints,
            waygroups: waygroups,
            patrolPaths: patrolPaths,
            aiLists: aiLists,
            padNameCount: padNameCount,
            boundPadNameCount: boundPadNameCount,
            portalTableSegmentedOffset: portalResult.segmentedOffset,
            portalTableOffset: portalResult.localOffset,
            portals: portalResult.portals,
            packetHash: packetHash
        )
    }

    private static func sectionEnd(
        start: UInt32,
        offsets: [UInt32],
        byteCount: Int
    ) throws -> Int {
        guard start != 0 else { return 0 }
        guard start < UInt32(byteCount) else {
            throw Error.invalidOffset(start, UInt32(byteCount))
        }
        let end = offsets.filter { $0 > start }.min().map(Int.init) ?? byteCount
        guard end > Int(start), end <= byteCount else {
            throw Error.invalidSection(start, UInt32(end), UInt32(byteCount))
        }
        return end
    }

    private static func parsePads(
        _ data: Data,
        start: UInt32,
        end: Int
    ) throws -> [GoldenEyeStageSetupPadPacket] {
        guard start != 0 else { return [] }
        let recordBytes = 44
        var result: [GoldenEyeStageSetupPadPacket] = []
        var offset = Int(start)
        while offset + recordBytes <= end {
            let words = try readWords(data, offset: offset, count: recordBytes / 4)
            if words.allSatisfy({ $0 == 0 }) {
                return result
            }
            guard result.count < Int(maxRecords) else {
                throw Error.capacityExceeded(6, maxRecords)
            }
            let vector = GoldenEyeStageSetupVectorBits(x: words[0], y: words[1], z: words[2])
            let up = GoldenEyeStageSetupVectorBits(x: words[3], y: words[4], z: words[5])
            let look = GoldenEyeStageSetupVectorBits(x: words[6], y: words[7], z: words[8])
            result.append(
                GoldenEyeStageSetupPadPacket(
                    index: UInt32(result.count),
                    sourceRecordOffset: UInt32(offset),
                    position: vector,
                    up: up,
                    look: look,
                    linkOffset: words[9],
                    stanOffset: words[10]
                )
            )
            offset += recordBytes
        }
        throw Error.missingSentinel(6)
    }

    private static func parseBoundPads(
        _ data: Data,
        start: UInt32,
        end: Int
    ) throws -> [GoldenEyeStageSetupBoundPadPacket] {
        guard start != 0 else { return [] }
        let recordBytes = 68
        var result: [GoldenEyeStageSetupBoundPadPacket] = []
        var offset = Int(start)
        while offset + recordBytes <= end {
            let words = try readWords(data, offset: offset, count: recordBytes / 4)
            if words.allSatisfy({ $0 == 0 }) {
                return result
            }
            guard result.count < Int(maxRecords) else {
                throw Error.capacityExceeded(7, maxRecords)
            }
            result.append(
                GoldenEyeStageSetupBoundPadPacket(
                    index: UInt32(result.count),
                    sourceRecordOffset: UInt32(offset),
                    position: GoldenEyeStageSetupVectorBits(x: words[0], y: words[1], z: words[2]),
                    up: GoldenEyeStageSetupVectorBits(x: words[3], y: words[4], z: words[5]),
                    look: GoldenEyeStageSetupVectorBits(x: words[6], y: words[7], z: words[8]),
                    linkOffset: words[9],
                    stanOffset: words[10],
                    bounds: GoldenEyeStageSetupBoundsBits(
                        a: words[11], b: words[12], c: words[13],
                        d: words[14], e: words[15], f: words[16]
                    )
                )
            )
            offset += recordBytes
        }
        throw Error.missingSentinel(7)
    }

    private static func parseObjects(
        _ data: Data,
        start: UInt32,
        end: Int
    ) throws -> [GoldenEyeStageSetupObjectPacket] {
        guard start != 0 else { return [] }
        var result: [GoldenEyeStageSetupObjectPacket] = []
        var offset = Int(start)
        while offset + 4 <= end {
            let first = try readWord(data, offset: offset)
            let type = first & 0xff
            let sizeWords: Int
            switch type {
            case 0: sizeWords = 1
            case 1: sizeWords = 64
            case 2: sizeWords = 2
            case 3: sizeWords = 32
            case 4: sizeWords = 33
            case 5: sizeWords = 32
            case 6: sizeWords = 59
            case 7: sizeWords = 33
            case 8: sizeWords = 34
            case 9: sizeWords = 7
            case 10: sizeWords = 64
            case 11: sizeWords = 149
            case 12: sizeWords = 32
            case 13: sizeWords = 54
            case 14: sizeWords = 3
            case 15, 16: sizeWords = 1
            case 17: sizeWords = 32
            case 18: sizeWords = 3
            case 19: sizeWords = 4
            case 20: sizeWords = 45
            case 21: sizeWords = 34
            case 22: sizeWords = 4
            case 23: sizeWords = 4
            case 24: sizeWords = 1
            case 25, 26, 27, 28, 29: sizeWords = 2
            case 30: sizeWords = 4
            case 31: sizeWords = 1
            case 32, 34: sizeWords = 4
            case 33: sizeWords = 5
            case 35: sizeWords = 4
            case 36: sizeWords = 32
            case 37: sizeWords = 10
            case 38: sizeWords = 4
            case 39: sizeWords = 44
            case 40: sizeWords = 45
            case 41, 43, 44: sizeWords = 1
            case 42: sizeWords = 32
            case 45: sizeWords = 56
            case 46: sizeWords = 7
            case 47: sizeWords = 37
            case 48:
                return result
            default:
                throw Error.unsupportedObjectType(type, UInt32(offset))
            }
            let recordBytes = sizeWords * 4
            guard offset + recordBytes <= end else {
                throw Error.truncated(UInt32(offset), UInt32(recordBytes), UInt32(end - offset))
            }
            let second = sizeWords > 1 ? try readWord(data, offset: offset + 4) : 0
            let flags1 = sizeWords > 2 ? try readWord(data, offset: offset + 8) : 0
            let flags2 = sizeWords > 3 ? try readWord(data, offset: offset + 12) : 0
            let matrixWords: [UInt32]
            if sizeWords * 4 >= 0x58 {
                matrixWords = try (0..<16).map { try readWord(data, offset: offset + 0x18 + $0 * 4) }
            } else {
                matrixWords = []
            }
            var portalHint: UInt32 = 0
            if type == 1 {
                portalHint = try readWord(data, offset: offset + 60 * 4)
            } else if type == 47 {
                portalHint = try readWord(data, offset: offset + 35 * 4)
            }
            result.append(
                GoldenEyeStageSetupObjectPacket(
                    index: UInt32(result.count),
                    sourceRecordOffset: UInt32(offset),
                    type: type,
                    scale8_8: first >> 16,
                    state: (first >> 8) & 0xff,
                    key0: second >> 16,
                    key1: second & 0xffff,
                    flags1: flags1,
                    flags2: flags2,
                    recordBytes: UInt32(recordBytes),
                    matrixWords: matrixWords,
                    portalHint: portalHint
                )
            )
            guard result.count < Int(maxRecords) else {
                throw Error.capacityExceeded(3, maxRecords)
            }
            offset += recordBytes
        }
        throw Error.missingSentinel(3)
    }

    private static func parseIntros(
        _ data: Data,
        start: UInt32,
        end: Int
    ) throws -> [GoldenEyeStageSetupIntroPacket] {
        guard start != 0 else { return [] }
        var result: [GoldenEyeStageSetupIntroPacket] = []
        var offset = Int(start)
        while offset + 4 <= end {
            let first = try readWord(data, offset: offset)
            let type = first & 0xff
            let wordCount: Int
            switch type {
            case 0: wordCount = 3
            case 1, 2: wordCount = 4
            case 3: wordCount = 8
            case 4, 5: wordCount = 2
            case 6: wordCount = 10
            case 7: wordCount = 3
            case 8, 9: wordCount = 1
            default: throw Error.unsupportedIntroType(type, UInt32(offset))
            }
            let byteCount = wordCount * 4
            guard offset + byteCount <= end else {
                throw Error.truncated(UInt32(offset), UInt32(byteCount), UInt32(end - offset))
            }
            if type == 9 { return result }
            let payload = data.subdata(in: offset..<(offset + byteCount))
            result.append(
                GoldenEyeStageSetupIntroPacket(
                    index: UInt32(result.count),
                    sourceRecordOffset: UInt32(offset),
                    type: type,
                    wordCount: UInt32(wordCount),
                    payloadHash: hashBytes(payload)
                )
            )
            guard result.count < Int(maxRecords) else {
                throw Error.capacityExceeded(2, maxRecords)
            }
            offset += byteCount
        }
        throw Error.missingSentinel(2)
    }

    private static func parseWaypoints(
        _ data: Data,
        start: UInt32,
        end: Int
    ) throws -> [GoldenEyeStageSetupWaypointPacket] {
        guard start != 0 else { return [] }
        var result: [GoldenEyeStageSetupWaypointPacket] = []
        var offset = Int(start)
        while offset + 16 <= end {
            let words = try readWords(data, offset: offset, count: 4)
            if words[0] == UInt32.max { return result }
            result.append(
                GoldenEyeStageSetupWaypointPacket(
                    index: UInt32(result.count), sourceRecordOffset: UInt32(offset),
                    padID: words[0], neighboursOffset: words[1],
                    groupNumber: words[2], distance: words[3]
                )
            )
            guard result.count < Int(maxRecords) else {
                throw Error.capacityExceeded(0, maxRecords)
            }
            offset += 16
        }
        throw Error.missingSentinel(0)
    }

    private static func parseWaygroups(
        _ data: Data,
        start: UInt32,
        end: Int
    ) throws -> [GoldenEyeStageSetupWaygroupPacket] {
        guard start != 0 else { return [] }
        var result: [GoldenEyeStageSetupWaygroupPacket] = []
        var offset = Int(start)
        while offset + 12 <= end {
            let words = try readWords(data, offset: offset, count: 3)
            if words.allSatisfy({ $0 == 0 }) { return result }
            result.append(
                GoldenEyeStageSetupWaygroupPacket(
                    index: UInt32(result.count), sourceRecordOffset: UInt32(offset),
                    neighboursOffset: words[0], waypointsOffset: words[1], distance: words[2]
                )
            )
            guard result.count < Int(maxRecords) else {
                throw Error.capacityExceeded(1, maxRecords)
            }
            offset += 12
        }
        throw Error.missingSentinel(1)
    }

    private static func parsePatrolPaths(
        _ data: Data,
        start: UInt32,
        end: Int
    ) throws -> [GoldenEyeStageSetupPatrolPathPacket] {
        guard start != 0 else { return [] }
        var result: [GoldenEyeStageSetupPatrolPathPacket] = []
        var offset = Int(start)
        while offset + 8 <= end {
            let pointer = try readWord(data, offset: offset)
            let packed = try readWord(data, offset: offset + 4)
            if pointer == 0 && packed == 0 { return result }
            result.append(
                GoldenEyeStageSetupPatrolPathPacket(
                    index: UInt32(result.count), sourceRecordOffset: UInt32(offset),
                    waypointsOffset: pointer,
                    pathID: (packed >> 24) & 0xff,
                    isLoop: (packed >> 16) & 0xff,
                    length: packed & 0xffff
                )
            )
            guard result.count < Int(maxRecords) else {
                throw Error.capacityExceeded(4, maxRecords)
            }
            offset += 8
        }
        throw Error.missingSentinel(4)
    }

    private static func parseAILists(
        _ data: Data,
        start: UInt32,
        end: Int
    ) throws -> [GoldenEyeStageSetupAIListPacket] {
        guard start != 0 else { return [] }
        var result: [GoldenEyeStageSetupAIListPacket] = []
        var offset = Int(start)
        while offset + 8 <= end {
            let script = try readWord(data, offset: offset)
            let identifier = try readWord(data, offset: offset + 4)
            if script == 0 && identifier == 0 { return result }
            result.append(
                GoldenEyeStageSetupAIListPacket(
                    index: UInt32(result.count), sourceRecordOffset: UInt32(offset),
                    scriptOffset: script, identifier: identifier
                )
            )
            guard result.count < Int(maxRecords) else {
                throw Error.capacityExceeded(5, maxRecords)
            }
            offset += 8
        }
        throw Error.missingSentinel(5)
    }

    private static func parseNameCount(
        _ data: Data,
        start: UInt32,
        end: Int
    ) throws -> UInt32 {
        guard start != 0 else { return 0 }
        var offset = Int(start)
        var count: UInt32 = 0
        while offset + 4 <= end {
            let value = try readWord(data, offset: offset)
            // Null pointers are encoded as either zero or 0xffffffff by the
            // source linker/toolchain. Both forms terminate the name array;
            // later filler words are deliberately not interpreted.
            if value == 0 || value == UInt32.max { return count }
            count += 1
            guard count < maxRecords else { throw Error.capacityExceeded(8, maxRecords) }
            offset += 4
        }
        throw Error.missingSentinel(8)
    }

    private struct PortalResult {
        let segmentedOffset: UInt32
        let localOffset: UInt32
        let portals: [GoldenEyeStageSetupPortalPacket]
    }

    private static func parsePortals(_ data: Data) throws -> PortalResult {
        guard data.count >= 20 else {
            throw Error.malformedPortalHeader(UInt32(data.count))
        }
        let header = try readWords(data, offset: 0, count: 5)
        guard header[0] == 0, header[4] == 0 else {
            throw Error.malformedPortalHeader(header[0] != 0 ? header[0] : header[4])
        }
        let segmented = header[2]
        guard segmented != 0,
              (segmented & 0xff00_0000) == 0x0f00_0000 else {
            throw Error.malformedPortalHeader(segmented)
        }
        let local = segmented & 0x00ff_ffff
        guard (local & 3) == 0, local < UInt32(data.count) else {
            throw Error.malformedPortalOffset(segmented, UInt32(data.count))
        }
        var result: [GoldenEyeStageSetupPortalPacket] = []
        var offset = Int(local)
        while offset + 8 <= data.count {
            let geometrySegmented = try readWord(data, offset: offset)
            let room1 = UInt32(data[offset + 4])
            let room2 = UInt32(data[offset + 5])
            let control = UInt32(data[offset + 6]) << 8 | UInt32(data[offset + 7])
            if geometrySegmented == 0 && room1 == 0 && room2 == 0 && control == 0 {
                return PortalResult(
                    segmentedOffset: segmented,
                    localOffset: local,
                    portals: result
                )
            }
            guard (geometrySegmented & 0xff00_0000) == 0x0f00_0000 else {
                throw Error.malformedPortalOffset(geometrySegmented, UInt32(data.count))
            }
            let geometry = geometrySegmented & 0x00ff_ffff
            guard geometry < UInt32(data.count) else {
                throw Error.malformedPortalOffset(geometrySegmented, UInt32(data.count))
            }
            result.append(
                GoldenEyeStageSetupPortalPacket(
                    index: UInt32(result.count), sourceRecordOffset: UInt32(offset),
                    geometryOffset: geometry,
                    connectedRoom1: room1, connectedRoom2: room2,
                    controlBytes: control
                )
            )
            guard result.count < Int(maxPortals) else {
                throw Error.capacityExceeded(10, maxPortals)
            }
            offset += 8
        }
        throw Error.missingPortalSentinel
    }

    private static func readWord(_ data: Data, offset: Int) throws -> UInt32 {
        guard offset >= 0, offset <= data.count, data.count - offset >= 4 else {
            throw Error.truncated(UInt32(max(0, offset)), 4, UInt32(max(0, data.count - max(0, offset))))
        }
        return UInt32(data[offset]) << 24 |
            UInt32(data[offset + 1]) << 16 |
            UInt32(data[offset + 2]) << 8 |
            UInt32(data[offset + 3])
    }

    private static func readWords(_ data: Data, offset: Int, count: Int) throws -> [UInt32] {
        guard count >= 0 else { throw Error.invalidCapacity }
        var words: [UInt32] = []
        words.reserveCapacity(count)
        for index in 0..<count {
            words.append(try readWord(data, offset: offset + index * 4))
        }
        return words
    }

    private static func hashBytes(_ data: Data, into initial: UInt64 = fnvOffset) -> UInt64 {
        data.reduce(initial) { hash, byte in
            (hash ^ UInt64(byte)) &* fnvPrime
        }
    }

    private static func hashWords(_ words: [UInt64], into initial: UInt64 = fnvOffset) -> UInt64 {
        words.reduce(initial) { partial, word in
            var hash = partial
            for shift in stride(from: 0, to: 64, by: 8) {
                hash = (hash ^ ((word >> UInt64(shift)) & 0xff)) &* fnvPrime
            }
            return hash
        }
    }

    private static func hashWords(_ words: [UInt32], into initial: UInt64 = fnvOffset) -> UInt64 {
        hashWords(words.map(UInt64.init), into: initial)
    }
}
