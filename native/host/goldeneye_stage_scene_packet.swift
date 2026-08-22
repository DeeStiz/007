import CryptoKit
import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// A bounded, value-only room summary copied from the source background
/// parser. The offsets remain file-local integers; no segmented address is
/// ever turned into a host pointer.
public struct GoldenEyeStageRoomPacket: Sendable, Equatable {
    public let roomIndex: UInt32
    public let sourceRecordOffset: UInt32
    public let pointOffset: UInt32
    public let pointBytes: UInt32
    public let primaryOffset: UInt32
    public let primaryBytes: UInt32
    public let secondaryOffset: UInt32
    public let secondaryBytes: UInt32
    public let positionBits: (UInt32, UInt32, UInt32)
    public let flags: UInt32
    public let metadataHash: UInt64

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.roomIndex == rhs.roomIndex &&
            lhs.sourceRecordOffset == rhs.sourceRecordOffset &&
            lhs.pointOffset == rhs.pointOffset && lhs.pointBytes == rhs.pointBytes &&
            lhs.primaryOffset == rhs.primaryOffset && lhs.primaryBytes == rhs.primaryBytes &&
            lhs.secondaryOffset == rhs.secondaryOffset && lhs.secondaryBytes == rhs.secondaryBytes &&
            lhs.positionBits.0 == rhs.positionBits.0 &&
            lhs.positionBits.1 == rhs.positionBits.1 &&
            lhs.positionBits.2 == rhs.positionBits.2 &&
            lhs.flags == rhs.flags && lhs.metadataHash == rhs.metadataHash
    }
}

public struct GoldenEyeStageBackgroundPacket: Sendable, Equatable {
    public let sourceBytes: UInt32
    public let roomTableOffset: UInt32
    public let roomCount: UInt32
    public let sentinelRecordOffset: UInt32
    public let firstPayloadOffset: UInt32
    public let flags: UInt32
    public let sourceHash: UInt64
    public let roomTableHash: UInt64
    public let metadataHash: UInt64
}

public struct GoldenEyeStageSceneResource: Sendable, Equatable {
    public let kind: GoldenEyeStageAssetKind
    public let resourceName: String
    public let assetHandle: UInt32
    public let decodedBytes: UInt32
    public let decodedSHA256: String
    public let payloadHash: UInt64
    /// The decoded bytes are an owned, bounded copy. This is the only scene
    /// payload retained by the packet and it contains no ROM path/address.
    public let payload: Data
}

public struct GoldenEyeStageScenePacket: Sendable, Equatable {
    public let stageID: UInt32
    public let stageName: String
    public let demoMask: UInt32
    public let resources: [GoldenEyeStageSceneResource]
    public let background: GoldenEyeStageBackgroundPacket
    public let rooms: [GoldenEyeStageRoomPacket]
    public let setup: GoldenEyeStageSetupPacket
    public let packetHash: UInt64

    public var isRenderablePayloadReady: Bool {
        !resources.isEmpty && resources.allSatisfy { $0.payload.count == Int($0.decodedBytes) }
    }

    public enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case invalidCapacity
        case unknownStage(UInt32)
        case catalogLookup(UInt32)
        case missingResource(String)
        case resourceSize(String, Int, Int)
        case digestMismatch(String)
        case backgroundParse(UInt32, UInt32, String)
        case roomCapacity(Int)
        case roomCopy(UInt32, UInt32, UInt32, UInt32)
        case transfer(String)

        public var description: String {
            switch self {
            case .invalidCapacity: return "scene packet capacity is invalid"
            case let .unknownStage(id): return "unknown stage \(id)"
            case let .catalogLookup(id): return "C stage catalog lookup failed for \(id)"
            case let .missingResource(name): return "missing stage resource \(name)"
            case let .resourceSize(name, actual, expected): return "resource \(name) size \(actual) != \(expected)"
            case let .digestMismatch(name): return "decoded digest mismatch for \(name)"
            case let .backgroundParse(id, status, message): return "background parse failed for \(id) status=\(status) \(message)"
            case let .roomCapacity(count): return "room count \(count) exceeds bounded capacity"
            case let .roomCopy(id, status, copied, expected): return "room copy failed for \(id) status=\(status) copied=\(copied)/\(expected)"
            case let .transfer(detail): return "stage transfer-backed scene load failed: \(detail)"
            }
        }
    }

    public static func load(
        stageID: UInt32,
        catalog: GoldenEyeStageAssetCatalog,
        maxResourceBytes: Int = 64 * 1024 * 1024
    ) throws -> Self {
        guard maxResourceBytes > 0 else { throw Error.invalidCapacity }
        guard let stage = catalog.stages.first(where: { $0.stageID == stageID }) else {
            throw Error.unknownStage(stageID)
        }
        var resourceData: [GoldenEyeStageAssetKind: Data] = [:]
        resourceData.reserveCapacity(stage.resources.count)
        for resource in stage.resources.sorted(by: { $0.kind.rawValue < $1.kind.rawValue }) {
            let data: Data
            do {
                data = try Data(contentsOf: resource.decodedURL, options: [.mappedIfSafe])
            } catch {
                throw Error.missingResource(resource.resourceName)
            }
            resourceData[resource.kind] = data
        }
        return try load(
            stageID: stageID,
            catalog: catalog,
            resourceData: resourceData,
            maxResourceBytes: maxResourceBytes
        )
    }

    /// Transfer-backed scene loading for the production owner. Each resource
    /// is copied through the bounded M24 queue before the existing C
    /// background/setup parsers consume it. The queue is deliberately passed
    /// inout so request IDs, source-order completion, and transfer hashes are
    /// retained by the owner without introducing an asynchronous scheduler.
    public static func load(
        stageID: UInt32,
        catalog: GoldenEyeStageAssetCatalog,
        transferQueue: inout GoldenEyeStageTransferQueueV6,
        maxResourceBytes: Int = 64 * 1024 * 1024
    ) throws -> Self {
        guard maxResourceBytes > 0 else { throw Error.invalidCapacity }
        guard catalog.stages.contains(where: { $0.stageID == stageID }) else {
            throw Error.unknownStage(stageID)
        }
        let resources = catalog.stages
            .first(where: { $0.stageID == stageID })?.resources
            .sorted(by: { $0.kind.rawValue < $1.kind.rawValue }) ?? []
        guard resources.count == GoldenEyeStageAssetKind.allCases.count else {
            throw Error.transfer("stage \(stageID) does not expose all three resources")
        }
        var resourceData: [GoldenEyeStageAssetKind: Data] = [:]
        resourceData.reserveCapacity(resources.count)
        for resource in resources {
            guard resource.decodedBytes <= UInt32(clamping: maxResourceBytes) else {
                throw Error.resourceSize(
                    resource.resourceName,
                    Int(resource.decodedBytes),
                    maxResourceBytes
                )
            }
            let totalBytes = Int(resource.decodedBytes)
            let chunkBytes = Int(transferQueue.maxChunkBytes)
            guard chunkBytes > 0 else {
                throw Error.transfer("transfer queue chunk size is zero")
            }
            var offset = 0
            var data = Data()
            data.reserveCapacity(totalBytes)
            while offset < totalBytes {
                let count = min(chunkBytes, totalBytes - offset)
                do {
                    let request = try transferQueue.submit(
                        stageID: stageID,
                        kind: resource.kind,
                        decodedOffset: UInt32(offset),
                        byteCount: UInt32(count)
                    )
                    let completion = try transferQueue.complete(requestID: request.requestID)
                    guard completion.request == request,
                          completion.bytes.count == count,
                          completion.decodedSHA256 == resource.decodedSHA256 else {
                        throw Error.transfer(
                            "request \(request.requestID) metadata/digest mismatch for \(stageID)/\(resource.kind.rawValue)"
                        )
                    }
                    data.append(completion.bytes)
                    offset += count
                } catch let error as Error {
                    throw error
                } catch {
                    throw Error.transfer(
                        "request for \(stageID)/\(resource.kind.rawValue) offset \(offset) failed: \(error)"
                    )
                }
            }
            resourceData[resource.kind] = data
        }
        return try load(
            stageID: stageID,
            catalog: catalog,
            resourceData: resourceData,
            maxResourceBytes: maxResourceBytes
        )
    }

    /// Loads every stage through the queue in the C file-index order. Only one
    /// stage is active at a time; each stage is released after its packet is
    /// parsed, and the caller may explicitly reactivate the selected stage.
    public static func loadAll(
        catalog: GoldenEyeStageAssetCatalog,
        transferQueue: inout GoldenEyeStageTransferQueueV6,
        maxResourceBytes: Int = 64 * 1024 * 1024
    ) throws -> [Self] {
        var orderedStageIDs: [UInt32] = []
        var seen: Set<UInt32> = []
        for entry in transferQueue.fileIndex.entries where seen.insert(entry.stageID).inserted {
            orderedStageIDs.append(entry.stageID)
        }
        guard orderedStageIDs.count == catalog.stages.count else {
            throw Error.transfer(
                "C source-order stage count \(orderedStageIDs.count) != Swift catalog \(catalog.stages.count)"
            )
        }
        var packets: [Self] = []
        packets.reserveCapacity(orderedStageIDs.count)
        for stageID in orderedStageIDs {
            _ = try transferQueue.activate(stageID: stageID)
            do {
                let packet = try load(
                    stageID: stageID,
                    catalog: catalog,
                    transferQueue: &transferQueue,
                    maxResourceBytes: maxResourceBytes
                )
                try transferQueue.deactivate(stageID: stageID)
                try transferQueue.unload(stageID: stageID)
                packets.append(packet)
            } catch {
                _ = try? transferQueue.deactivate(stageID: stageID)
                _ = try? transferQueue.unload(stageID: stageID)
                throw error
            }
        }
        return packets
    }

    private static func load(
        stageID: UInt32,
        catalog: GoldenEyeStageAssetCatalog,
        resourceData: [GoldenEyeStageAssetKind: Data],
        maxResourceBytes: Int
    ) throws -> Self {
        guard maxResourceBytes > 0 else { throw Error.invalidCapacity }
        guard let stage = catalog.stages.first(where: { $0.stageID == stageID }) else {
            throw Error.unknownStage(stageID)
        }
        var cEntry = GEStageCatalogEntryV5()
        guard UInt32(ge_stage_v5_find_stage(stageID, &cEntry)) == UInt32(GE_STATUS_OK) else {
            throw Error.catalogLookup(stageID)
        }

        var sceneResources: [GoldenEyeStageSceneResource] = []
        sceneResources.reserveCapacity(stage.resources.count)
        for resource in stage.resources.sorted(by: { $0.kind.rawValue < $1.kind.rawValue }) {
            guard let data = resourceData[resource.kind] else {
                throw Error.missingResource(resource.resourceName)
            }
            guard data.count == Int(resource.decodedBytes), data.count <= maxResourceBytes else {
                throw Error.resourceSize(resource.resourceName, data.count, Int(resource.decodedBytes))
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == resource.decodedSHA256 else {
                throw Error.digestMismatch(resource.resourceName)
            }
            sceneResources.append(
                GoldenEyeStageSceneResource(
                    kind: resource.kind,
                    resourceName: resource.resourceName,
                    assetHandle: resource.assetHandle,
                    decodedBytes: resource.decodedBytes,
                    decodedSHA256: digest,
                    payloadHash: fnv(data),
                    payload: data
                )
            )
        }

        guard let backgroundData = sceneResources.first(where: { $0.kind == .background }),
              let setupData = sceneResources.first(where: { $0.kind == .setup }) else {
            throw Error.missingResource("background")
        }
        var cResource = cEntry.background
        var cBackground = GEStageBackgroundV5()
        var diagnostic = GEStageDiagnosticV5()
        let parseStatus = backgroundData.payload.withUnsafeBytes { bytes -> UInt32 in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return UInt32(GE_STATUS_INVALID_ARGUMENT)
            }
            return UInt32(ge_stage_v5_parse_background(
                &cResource, base, UInt32(backgroundData.payload.count), &cBackground, &diagnostic
            ))
        }
        guard parseStatus == UInt32(GE_STATUS_OK) else {
            throw Error.backgroundParse(stageID, parseStatus, Self.cString(diagnostic.message))
        }

        let roomCount = Int(cBackground.room_count)
        guard roomCount <= Int(GE_STAGE_V5_BG_MAX_ROOMS) else {
            throw Error.roomCapacity(roomCount)
        }
        var cRooms = [GEStageBackgroundRoomV5](
            repeating: GEStageBackgroundRoomV5(), count: max(roomCount, 1)
        )
        var copied: UInt32 = 0
        let copyStatus = backgroundData.payload.withUnsafeBytes { bytes -> UInt32 in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return UInt32(GE_STATUS_INVALID_ARGUMENT)
            }
            return UInt32(cRooms.withUnsafeMutableBufferPointer { roomBuffer in
                ge_stage_v5_copy_background_rooms(
                    &cResource, base, UInt32(backgroundData.payload.count), 0,
                    UInt32(roomBuffer.count), roomBuffer.baseAddress, &copied,
                    &cBackground, &diagnostic
                )
            })
        }
        guard copyStatus == UInt32(GE_STATUS_OK), copied == cBackground.room_count else {
            throw Error.roomCopy(stageID, copyStatus, copied, cBackground.room_count)
        }

        let rooms = cRooms.prefix(Int(copied)).map { room in
            GoldenEyeStageRoomPacket(
                roomIndex: room.room_index,
                sourceRecordOffset: room.source_record_offset,
                pointOffset: room.point_offset,
                pointBytes: room.point_bytes,
                primaryOffset: room.primary_offset,
                primaryBytes: room.primary_bytes,
                secondaryOffset: room.secondary_offset,
                secondaryBytes: room.secondary_bytes,
                positionBits: (room.position_x_bits, room.position_y_bits, room.position_z_bits),
                flags: room.flags,
                metadataHash: room.metadata_hash
            )
        }
        let background = GoldenEyeStageBackgroundPacket(
            sourceBytes: cBackground.source_bytes,
            roomTableOffset: cBackground.room_table_offset,
            roomCount: cBackground.room_count,
            sentinelRecordOffset: cBackground.sentinel_record_offset,
            firstPayloadOffset: cBackground.first_payload_offset,
            flags: cBackground.flags,
            sourceHash: cBackground.source_hash,
            roomTableHash: cBackground.room_table_hash,
            metadataHash: cBackground.metadata_hash
        )
        let setup = try GoldenEyeStageSetupPacket.load(
            stageID: stageID,
            setupData: setupData.payload,
            backgroundData: backgroundData.payload
        )
        var hash = fnvWord(UInt64(stageID))
        hash = fnvWord(UInt64(stage.demoMask), into: hash)
        for resource in sceneResources {
            hash = fnvWord(UInt64(resource.assetHandle), into: hash)
            hash = fnvWord(resource.payloadHash, into: hash)
        }
        hash = fnvWord(background.metadataHash, into: hash)
        hash = fnvWord(setup.packetHash, into: hash)
        for room in rooms {
            hash = fnvWord(room.metadataHash, into: hash)
        }
        return Self(
            stageID: stage.stageID,
            stageName: stage.stageName,
            demoMask: stage.demoMask,
            resources: sceneResources,
            background: background,
            rooms: rooms,
            setup: setup,
            packetHash: hash
        )
    }

    public static func loadAll(catalog: GoldenEyeStageAssetCatalog) throws -> [Self] {
        try catalog.stages.map { try load(stageID: $0.stageID, catalog: catalog) }
    }

    private static func fnv(_ data: Data) -> UInt64 {
        data.reduce(UInt64(1469598103934665603)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1099511628211
        }
    }

    private static func fnvWord(_ value: UInt64, into initial: UInt64 = 1469598103934665603) -> UInt64 {
        var hash = initial
        for shift in stride(from: 0, to: 64, by: 8) {
            hash = (hash ^ ((value >> UInt64(shift)) & 0xff)) &* 1099511628211
        }
        return hash
    }

    private static func cString<T>(_ tuple: T) -> String {
        var value = tuple
        return withUnsafePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 96) { cStringPointer in
                String(cString: cStringPointer)
            }
        }
    }
}
