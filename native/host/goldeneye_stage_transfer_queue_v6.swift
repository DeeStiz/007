import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// A source-derived file-index row.  The row preserves the catalog's source
/// and decoded ranges, compression flag, handle, and digests without exposing
/// an N64 address or retaining a file pointer.
public struct GoldenEyeStageFileIndexEntryV6: Sendable, Equatable {
    public let stageID: UInt32
    public let stageName: String
    public let kind: GoldenEyeStageAssetKind
    public let resourceName: String
    public let assetHandle: UInt32
    public let sourceOffset: UInt32
    public let sourceBytes: UInt32
    public let decodedBytes: UInt32
    public let compressed1172: Bool
    public let sourceSHA256: String
    public let decodedSHA256: String
}

public enum GoldenEyeStageFileIndexErrorV6: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case duplicateResource(UInt32, GoldenEyeStageAssetKind)
    case missingResource(UInt32, GoldenEyeStageAssetKind)
    case sourceCatalogMismatch(String)

    public var description: String {
        switch self {
        case let .duplicateResource(stageID, kind):
            return "duplicate stage file-index resource \(stageID)/\(kind.rawValue)"
        case let .missingResource(stageID, kind):
            return "missing stage file-index resource \(stageID)/\(kind.rawValue)"
        case let .sourceCatalogMismatch(detail):
            return "stage file-index source catalog mismatch: \(detail)"
        }
    }
}

/// Deterministic metadata index for the prepared stage files.
///
/// This is deliberately a value-only replacement seam for the source file
/// table.  It does not open the external ROM, schedule N64 DMA, or imply that
/// any stage category is executable.
public struct GoldenEyeStageFileIndexV6: Sendable, Equatable {
    private static let offsetBasis: UInt64 = 14_695_981_039_346_656_037
    private static let prime: UInt64 = 1_099_511_628_211

    public let catalogHash: UInt64
    public let indexHash: UInt64
    public let entries: [GoldenEyeStageFileIndexEntryV6]

    public init(catalog: GoldenEyeStageAssetCatalog) throws {
        // Keep the Swift value catalog behind the same C source-order and
        // metadata contract used by RAMROM packet production.  The public
        // catalog initializer is intentionally value-only, so this check is
        // required even when the usual manifest loader already performed the
        // comparison; callers can otherwise construct a drifted catalog.
        let sourceOrderedResources = try Self.validateSourceCatalog(catalog: catalog)
        var rows: [GoldenEyeStageFileIndexEntryV6] = []
        rows.reserveCapacity(sourceOrderedResources.count)
        // The ordering here is deliberately the C packet/RAMROM order.  A
        // numeric stage-ID sort would silently change source traversal (the
        // catalog order is 33,34,35,9,20,26,25).
        for resource in sourceOrderedResources {
            rows.append(
                GoldenEyeStageFileIndexEntryV6(
                    stageID: resource.stageID,
                    stageName: resource.stageName,
                    kind: resource.kind,
                    resourceName: resource.resourceName,
                    assetHandle: resource.assetHandle,
                    sourceOffset: resource.sourceOffset,
                    sourceBytes: resource.sourceBytes,
                    decodedBytes: resource.decodedBytes,
                    compressed1172: resource.compressed1172,
                    sourceSHA256: resource.sourceSHA256,
                    decodedSHA256: resource.decodedSHA256
                )
            )
        }
        self.catalogHash = catalog.catalogHash
        self.entries = rows
        var hash = Self.offsetBasis
        for row in rows {
            hash = Self.mix(hash, UInt64(row.stageID))
            hash = Self.mix(hash, UInt64(Self.order(row.kind)))
            hash = Self.mix(hash, UInt64(row.assetHandle))
            hash = Self.mix(hash, UInt64(row.sourceOffset))
            hash = Self.mix(hash, UInt64(row.sourceBytes))
            hash = Self.mix(hash, UInt64(row.decodedBytes))
            hash = Self.mix(hash, row.compressed1172 ? 1 : 0)
            hash = Self.mix(hash, row.resourceName.utf8)
            hash = Self.mix(hash, row.sourceSHA256.utf8)
            hash = Self.mix(hash, row.decodedSHA256.utf8)
        }
        self.indexHash = hash
    }

    public func entry(
        stageID: UInt32,
        kind: GoldenEyeStageAssetKind
    ) -> GoldenEyeStageFileIndexEntryV6? {
        entries.first { $0.stageID == stageID && $0.kind == kind }
    }

    private static func order(_ kind: GoldenEyeStageAssetKind) -> UInt32 {
        switch kind {
        case .background: return 1
        case .stan: return 2
        case .setup: return 3
        }
    }

    private static func mix(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        (hash ^ value) &* prime
    }

    private static func mix<S: Sequence>(_ hash: UInt64, _ bytes: S) -> UInt64
    where S.Element == UInt8 {
        bytes.reduce(hash) { partial, byte in
            mix(partial, UInt64(byte))
        }
    }

    private static func validateSourceCatalog(
        catalog: GoldenEyeStageAssetCatalog
    ) throws -> [GoldenEyeStageAssetResource] {
        let cStageCount = ge_stage_v5_catalog_count()
        guard cStageCount == UInt32(catalog.stages.count) else {
            throw GoldenEyeStageFileIndexErrorV6.sourceCatalogMismatch(
                "stage count swift=\(catalog.stages.count) c=\(cStageCount)"
            )
        }
        let cPacketCount = ge_stage_v5_resource_packet_count()
        guard cPacketCount == UInt32(GoldenEyeStageAssetCatalog.expectedResourceCount) else {
            throw GoldenEyeStageFileIndexErrorV6.sourceCatalogMismatch(
                "C packet count=\(cPacketCount) expected=\(GoldenEyeStageAssetCatalog.expectedResourceCount)"
            )
        }

        var stageIDs: Set<UInt32> = []
        var resourcesByKey: [String: [GoldenEyeStageAssetResource]] = [:]
        var allResources: [GoldenEyeStageAssetResource] = []
        allResources.reserveCapacity(cPacketCount == 0 ? 0 : Int(cPacketCount))
        for stage in catalog.stages {
            guard stageIDs.insert(stage.stageID).inserted else {
                throw GoldenEyeStageFileIndexErrorV6.sourceCatalogMismatch(
                    "duplicate stage id \(stage.stageID)"
                )
            }
            var seenKinds: Set<GoldenEyeStageAssetKind> = []
            for resource in stage.resources {
                guard seenKinds.insert(resource.kind).inserted else {
                    throw GoldenEyeStageFileIndexErrorV6.duplicateResource(
                        stage.stageID,
                        resource.kind
                    )
                }
                guard resource.stageID == stage.stageID else {
                    throw GoldenEyeStageFileIndexErrorV6.sourceCatalogMismatch(
                        "stage \(stage.stageID) resource \(resource.resourceName) carries stage id \(resource.stageID)"
                    )
                }
                let key = Self.key(stageID: resource.stageID, kind: resource.kind)
                resourcesByKey[key, default: []].append(resource)
                allResources.append(resource)
            }
            for kind in GoldenEyeStageAssetKind.allCases {
                guard seenKinds.contains(kind) else {
                    throw GoldenEyeStageFileIndexErrorV6.missingResource(stage.stageID, kind)
                }
            }
        }
        guard allResources.count == Int(cPacketCount) else {
            throw GoldenEyeStageFileIndexErrorV6.sourceCatalogMismatch(
                "Swift resource count=\(allResources.count) C packet count=\(cPacketCount)"
            )
        }

        var rows: [GoldenEyeStageAssetResource] = []
        rows.reserveCapacity(Int(cPacketCount))
        for packetIndex in 0..<cPacketCount {
            var packet = GEStageResourcePacketV5()
            let packetStatus = UInt32(ge_stage_v5_resource_packet(packetIndex, &packet))
            guard packetStatus == UInt32(GE_STATUS_OK) else {
                throw GoldenEyeStageFileIndexErrorV6.sourceCatalogMismatch(
                    "C packet \(packetIndex) status=\(packetStatus)"
                )
            }
            guard packet.packet_index == packetIndex else {
                throw GoldenEyeStageFileIndexErrorV6.sourceCatalogMismatch(
                    "C packet index \(packetIndex) reports \(packet.packet_index)"
                )
            }
            guard let kind = GoldenEyeStageAssetKind.allCases.first(where: {
                Self.cKind($0) == packet.resource_kind
            }) else {
                throw GoldenEyeStageFileIndexErrorV6.sourceCatalogMismatch(
                    "packet \(packetIndex) has unknown resource kind \(packet.resource_kind)"
                )
            }

            var cStage = GEStageCatalogEntryV5()
            let stageStatus = UInt32(ge_stage_v5_find_stage(packet.stage_id, &cStage))
            guard stageStatus == UInt32(GE_STATUS_OK) else {
                throw GoldenEyeStageFileIndexErrorV6.sourceCatalogMismatch(
                    "packet \(packetIndex) stage \(packet.stage_id) lookup status=\(stageStatus)"
                )
            }
            let cStageName = Self.cString(
                cStage.stage_name,
                capacity: Int(GE_STAGE_V5_STAGE_NAME_BYTES)
            )
            guard let swiftStage = catalog.stages.first(where: { $0.stageID == packet.stage_id }) else {
                throw GoldenEyeStageFileIndexErrorV6.sourceCatalogMismatch(
                    "packet \(packetIndex) stage \(packet.stage_id) is absent from Swift catalog"
                )
            }
            guard swiftStage.stageName == cStageName,
                  swiftStage.demoMask == cStage.demo_mask else {
                throw GoldenEyeStageFileIndexErrorV6.sourceCatalogMismatch(
                    "stage \(packet.stage_id) Swift identity differs from C source"
                )
            }

            let key = Self.key(stageID: packet.stage_id, kind: kind)
            guard let candidates = resourcesByKey[key], candidates.count == 1,
                  let resource = candidates.first else {
                throw GoldenEyeStageFileIndexErrorV6.sourceCatalogMismatch(
                    "packet \(packetIndex) has no unique Swift row for \(packet.stage_id)/\(kind.rawValue)"
                )
            }
            let cResourceName = Self.cString(
                packet.resource_name,
                capacity: Int(GE_STAGE_V5_RESOURCE_NAME_BYTES)
            )
            let cCompression = packet.compression
            guard resource.stageID == packet.stage_id,
                  resource.stageName == cStageName,
                  resource.kind == kind,
                  resource.resourceName == cResourceName,
                  resource.assetHandle == packet.asset_handle,
                  cCompression == UInt32(GE_STAGE_V5_COMPRESSION_NONE) ||
                    cCompression == UInt32(GE_STAGE_V5_COMPRESSION_1172),
                  resource.compressed1172 ==
                    (cCompression == UInt32(GE_STAGE_V5_COMPRESSION_1172)),
                  resource.sourceOffset == packet.source_offset,
                  resource.sourceBytes == packet.source_bytes,
                  resource.decodedBytes == packet.decoded_bytes else {
                throw GoldenEyeStageFileIndexErrorV6.sourceCatalogMismatch(
                    "packet \(packetIndex) metadata differs for \(packet.stage_id)/\(kind.rawValue)"
                )
            }
            rows.append(resource)
        }
        return rows
    }

    private static func cKind(_ kind: GoldenEyeStageAssetKind) -> UInt32 {
        switch kind {
        case .background: return UInt32(GE_STAGE_V5_RESOURCE_BACKGROUND)
        case .stan: return UInt32(GE_STAGE_V5_RESOURCE_STAN)
        case .setup: return UInt32(GE_STAGE_V5_RESOURCE_SETUP)
        }
    }

    private static func key(stageID: UInt32, kind: GoldenEyeStageAssetKind) -> String {
        "\(stageID):\(kind.rawValue)"
    }

    private static func cString<T>(_ tuple: T, capacity: Int) -> String {
        var value = tuple
        return withUnsafePointer(to: &value) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { cStringPointer in
                String(cString: cStringPointer)
            }
        }
    }
}

public struct GoldenEyeStageTransferRequestV6: Sendable, Equatable {
    public let requestID: UInt64
    public let stageID: UInt32
    public let kind: GoldenEyeStageAssetKind
    public let decodedOffset: UInt32
    public let byteCount: UInt32
}

public struct GoldenEyeStageTransferCompletionV6: Sendable, Equatable {
    public let request: GoldenEyeStageTransferRequestV6
    public let bytes: Data
    public let decodedSHA256: String
}

public struct GoldenEyeStageTransferSnapshotV6: Sendable, Equatable {
    public let activeStageID: UInt32?
    public let pendingCount: UInt32
    public let completedCount: UInt32
    public let transferHash: UInt64
}

public enum GoldenEyeStageTransferQueueErrorV6: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case invalidCapacity
    case invalidChunkSize
    case queueFull(UInt32)
    case noActiveStage
    case activeStageMismatch(UInt32, UInt32)
    case duplicateRequest(UInt64)
    case unknownRequest(UInt64)
    case pendingRequests(UInt32)
    case invalidRange(UInt32, GoldenEyeStageAssetKind, UInt32, UInt32)
    case transferFailed(UInt64, String)

    public var description: String {
        switch self {
        case .invalidCapacity: return "stage transfer queue capacity must be positive"
        case .invalidChunkSize: return "stage transfer chunk size must be positive"
        case let .queueFull(count): return "stage transfer queue is full at \(count) requests"
        case .noActiveStage: return "stage transfer requires an active stage"
        case let .activeStageMismatch(expected, actual):
            return "stage transfer active stage mismatch expected=\(expected) actual=\(actual)"
        case let .duplicateRequest(requestID): return "stage transfer request \(requestID) is already known"
        case let .unknownRequest(requestID): return "stage transfer request \(requestID) is unknown"
        case let .pendingRequests(count): return "stage transfer has \(count) pending requests"
        case let .invalidRange(stageID, kind, offset, count):
            return "stage transfer range \(stageID)/\(kind.rawValue) offset=\(offset) count=\(count) is outside decoded bytes"
        case let .transferFailed(requestID, detail):
            return "stage transfer request \(requestID) failed: \(detail)"
        }
    }
}

/// A bounded, synchronous transfer queue over the prepared payload store.
///
/// Submit/complete gives the native owner a deterministic DMA-shaped contract
/// while keeping the implementation honest: reads are copied from the active
/// decoded payload into caller-visible values, no N64 scheduler is emulated,
/// and stage replacement/reset is rejected while work is outstanding.
public struct GoldenEyeStageTransferQueueV6: Sendable {
    private static let offsetBasis: UInt64 = 14_695_981_039_346_656_037
    private static let prime: UInt64 = 1_099_511_628_211

    public let fileIndex: GoldenEyeStageFileIndexV6
    public let maxPending: UInt32
    public let maxChunkBytes: UInt32
    private var store: GoldenEyeStagePayloadStoreV6
    private var pending: [UInt64: GoldenEyeStageTransferRequestV6] = [:]
    private var completed: Set<UInt64> = []
    private var nextRequestID: UInt64 = 1
    private var transferHash = Self.offsetBasis

    public init(
        catalog: GoldenEyeStageAssetCatalog,
        maxPending: UInt32 = 8,
        maxChunkBytes: UInt32 = 1 << 20
    ) throws {
        guard maxPending > 0 else { throw GoldenEyeStageTransferQueueErrorV6.invalidCapacity }
        guard maxChunkBytes > 0 else { throw GoldenEyeStageTransferQueueErrorV6.invalidChunkSize }
        self.fileIndex = try GoldenEyeStageFileIndexV6(catalog: catalog)
        self.maxPending = maxPending
        self.maxChunkBytes = maxChunkBytes
        self.store = try GoldenEyeStagePayloadStoreV6(
            catalog: catalog,
            maxReadBytes: maxChunkBytes
        )
    }

    public var snapshot: GoldenEyeStageTransferSnapshotV6 {
        GoldenEyeStageTransferSnapshotV6(
            activeStageID: store.activeStageID,
            pendingCount: UInt32(clamping: pending.count),
            completedCount: UInt32(clamping: completed.count),
            transferHash: transferHash
        )
    }

    @discardableResult
    public mutating func activate(stageID: UInt32) throws -> GoldenEyeStagePayloadSnapshotV6 {
        guard pending.isEmpty else {
            throw GoldenEyeStageTransferQueueErrorV6.pendingRequests(UInt32(pending.count))
        }
        return try store.activate(stageID: stageID)
    }

    public mutating func deactivate(stageID: UInt32) throws {
        guard pending.isEmpty else {
            throw GoldenEyeStageTransferQueueErrorV6.pendingRequests(UInt32(pending.count))
        }
        _ = try store.deactivate(stageID: stageID)
    }

    public mutating func unload(stageID: UInt32) throws {
        guard pending.isEmpty else {
            throw GoldenEyeStageTransferQueueErrorV6.pendingRequests(UInt32(pending.count))
        }
        _ = try store.unload(stageID: stageID)
    }

    public mutating func reset() throws {
        guard pending.isEmpty else {
            throw GoldenEyeStageTransferQueueErrorV6.pendingRequests(UInt32(pending.count))
        }
        try store.reset()
    }

    @discardableResult
    public mutating func submit(
        stageID: UInt32,
        kind: GoldenEyeStageAssetKind,
        decodedOffset: UInt32,
        byteCount: UInt32
    ) throws -> GoldenEyeStageTransferRequestV6 {
        guard byteCount > 0 else {
            throw GoldenEyeStageTransferQueueErrorV6.invalidChunkSize
        }
        guard byteCount <= maxChunkBytes else {
            throw GoldenEyeStageTransferQueueErrorV6.invalidChunkSize
        }
        guard let active = store.activeStageID else {
            throw GoldenEyeStageTransferQueueErrorV6.noActiveStage
        }
        guard active == stageID else {
            throw GoldenEyeStageTransferQueueErrorV6.activeStageMismatch(stageID, active)
        }
        guard pending.count < Int(maxPending) else {
            throw GoldenEyeStageTransferQueueErrorV6.queueFull(UInt32(pending.count))
        }
        guard let entry = fileIndex.entry(stageID: stageID, kind: kind) else {
            throw GoldenEyeStageFileIndexErrorV6.missingResource(stageID, kind)
        }
        guard decodedOffset <= entry.decodedBytes,
              byteCount <= entry.decodedBytes - decodedOffset else {
            throw GoldenEyeStageTransferQueueErrorV6.invalidRange(
                stageID,
                kind,
                decodedOffset,
                byteCount
            )
        }
        let requestID = nextRequestID
        nextRequestID = nextRequestID == UInt64.max ? 1 : nextRequestID + 1
        guard pending[requestID] == nil, completed.contains(requestID) == false else {
            throw GoldenEyeStageTransferQueueErrorV6.duplicateRequest(requestID)
        }
        let request = GoldenEyeStageTransferRequestV6(
            requestID: requestID,
            stageID: stageID,
            kind: kind,
            decodedOffset: decodedOffset,
            byteCount: byteCount
        )
        pending[requestID] = request
        transferHash = Self.mix(transferHash, requestID)
        transferHash = Self.mix(transferHash, UInt64(stageID))
        transferHash = Self.mix(transferHash, UInt64(Self.order(kind)))
        transferHash = Self.mix(transferHash, UInt64(decodedOffset))
        transferHash = Self.mix(transferHash, UInt64(byteCount))
        return request
    }

    public mutating func complete(
        requestID: UInt64
    ) throws -> GoldenEyeStageTransferCompletionV6 {
        guard let request = pending[requestID] else {
            if completed.contains(requestID) {
                throw GoldenEyeStageTransferQueueErrorV6.duplicateRequest(requestID)
            }
            throw GoldenEyeStageTransferQueueErrorV6.unknownRequest(requestID)
        }
        do {
            let read = try store.read(
                stageID: request.stageID,
                kind: request.kind,
                offset: request.decodedOffset,
                count: request.byteCount
            )
            pending.removeValue(forKey: requestID)
            completed.insert(requestID)
            for byte in read.bytes {
                transferHash = Self.mix(transferHash, UInt64(byte))
            }
            return GoldenEyeStageTransferCompletionV6(
                request: request,
                bytes: read.bytes,
                decodedSHA256: read.decodedHash
            )
        } catch {
            throw GoldenEyeStageTransferQueueErrorV6.transferFailed(
                requestID,
                String(describing: error)
            )
        }
    }

    public mutating func drain(
        maximumCompletions: UInt32 = UInt32.max
    ) throws -> [GoldenEyeStageTransferCompletionV6] {
        let ids = pending.keys.sorted().prefix(Int(maximumCompletions))
        var output: [GoldenEyeStageTransferCompletionV6] = []
        output.reserveCapacity(ids.count)
        for requestID in ids {
            output.append(try complete(requestID: requestID))
        }
        return output
    }

    private static func order(_ kind: GoldenEyeStageAssetKind) -> UInt32 {
        switch kind {
        case .background: return 1
        case .stan: return 2
        case .setup: return 3
        }
    }

    private static func mix(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        (hash ^ value) &* prime
    }
}
