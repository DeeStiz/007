import CryptoKit
import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Errors from the scheduler-independent prepared-payload service.  The
/// service owns decoded stage bytes only after a caller explicitly loads a
/// stage; it never opens the external ROM or accepts an N64 pointer/address.
public enum GoldenEyeStagePayloadStoreErrorV6: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case unknownStage(UInt32)
    case unknownResource(UInt32, GoldenEyeStageAssetKind)
    case invalidTransition(UInt32, String)
    case stageNotLoaded(UInt32)
    case invalidRange(UInt32, GoldenEyeStageAssetKind, UInt32, UInt32)
    case oversizedRead(UInt32)
    case decodedSizeMismatch(UInt32, GoldenEyeStageAssetKind, UInt32, UInt32)
    case digestMismatch(UInt32, GoldenEyeStageAssetKind, String, String)
    case activeStageRemains(UInt32)

    public var description: String {
        switch self {
        case let .unknownStage(stageID):
            return "stage payload store does not contain stage \(stageID)"
        case let .unknownResource(stageID, kind):
            return "stage payload store does not contain \(stageID)/\(kind.rawValue)"
        case let .invalidTransition(stageID, detail):
            return "stage payload store transition for \(stageID) rejected: \(detail)"
        case let .stageNotLoaded(stageID):
            return "stage \(stageID) payloads are not loaded"
        case let .invalidRange(stageID, kind, offset, count):
            return "stage payload range \(stageID)/\(kind.rawValue) offset=\(offset) count=\(count) is outside decoded bytes"
        case let .oversizedRead(count):
            return "stage payload read of \(count) bytes exceeds the bounded chunk size"
        case let .decodedSizeMismatch(stageID, kind, expected, actual):
            return "stage payload decoded size mismatch for \(stageID)/\(kind.rawValue): expected \(expected), got \(actual)"
        case let .digestMismatch(stageID, kind, expected, actual):
            return "stage payload decoded digest mismatch for \(stageID)/\(kind.rawValue): expected \(expected), got \(actual)"
        case let .activeStageRemains(stageID):
            return "stage payload store reset requires stage \(stageID) to be deactivated"
        }
    }
}

/// A deterministic copied read result.  The bytes are caller-owned after the
/// value is returned; no source pointer or ROM address crosses this boundary.
public struct GoldenEyeStagePayloadReadV6: Sendable, Equatable {
    public let stageID: UInt32
    public let kind: GoldenEyeStageAssetKind
    public let assetHandle: UInt32
    public let decodedOffset: UInt32
    public let bytes: Data
    public let decodedHash: String
}

/// A value-only snapshot of one prepared stage payload residency state.
public struct GoldenEyeStagePayloadSnapshotV6: Sendable, Equatable {
    public let stageID: UInt32
    public let stageName: String
    public let loaded: Bool
    public let active: Bool
    public let resourceCount: UInt32
    public let decodedBytes: UInt32
    public let decodedHash: String
    public let loadCount: UInt32
}

/// Scheduler-independent ownership for prepared stage payloads.
///
/// This is intentionally separate from ``GoldenEyeStageLifecycleV6``'s
/// metadata/arena contract: the lifecycle remains pointer-free, while this
/// service is the bounded owner for decoded bytes and range reads.  At most
/// one stage is active, and an active stage cannot be unloaded or reset.
public struct GoldenEyeStagePayloadStoreV6: Sendable {
    public static let defaultMaxReadBytes: UInt32 = 1 << 20

    private struct Entry: Sendable {
        let stage: GoldenEyeStageAssetStage
        var payloads: [GoldenEyeStageAssetKind: Data]
        var loadCount: UInt32
        var active: Bool
    }

    public let catalogHash: UInt64
    public let maxReadBytes: UInt32
    private var entries: [UInt32: Entry]

    public init(
        catalog: GoldenEyeStageAssetCatalog,
        maxReadBytes: UInt32 = Self.defaultMaxReadBytes
    ) throws {
        guard maxReadBytes > 0 else {
            throw GoldenEyeStagePayloadStoreErrorV6.oversizedRead(0)
        }
        self.catalogHash = catalog.catalogHash
        self.maxReadBytes = maxReadBytes
        self.entries = Dictionary(uniqueKeysWithValues: catalog.stages.map { stage in
            (
                stage.stageID,
                Entry(stage: stage, payloads: [:], loadCount: 0, active: false)
            )
        })
    }

    public var stageIDs: [UInt32] { entries.keys.sorted() }

    public var activeStageID: UInt32? {
        entries.values.first(where: { $0.active })?.stage.stageID
    }

    public func snapshot(stageID: UInt32) throws -> GoldenEyeStagePayloadSnapshotV6 {
        guard let entry = entries[stageID] else {
            throw GoldenEyeStagePayloadStoreErrorV6.unknownStage(stageID)
        }
        let decodedBytes = entry.payloads.values.reduce(UInt32(0)) {
            $0 &+ UInt32(clamping: $1.count)
        }
        let decodedHash = Self.hashPayloads(entry.payloads, stage: entry.stage)
        return GoldenEyeStagePayloadSnapshotV6(
            stageID: stageID,
            stageName: entry.stage.stageName,
            loaded: !entry.payloads.isEmpty,
            active: entry.active,
            resourceCount: UInt32(entry.payloads.count),
            decodedBytes: decodedBytes,
            decodedHash: decodedHash,
            loadCount: entry.loadCount
        )
    }

    public func isLoaded(stageID: UInt32) throws -> Bool {
        try snapshot(stageID: stageID).loaded
    }

    @discardableResult
    public mutating func load(stageID: UInt32) throws -> GoldenEyeStagePayloadSnapshotV6 {
        guard var entry = entries[stageID] else {
            throw GoldenEyeStagePayloadStoreErrorV6.unknownStage(stageID)
        }
        guard entry.payloads.isEmpty else {
            throw GoldenEyeStagePayloadStoreErrorV6.invalidTransition(
                stageID,
                "stage is already loaded"
            )
        }

        var payloads: [GoldenEyeStageAssetKind: Data] = [:]
        payloads.reserveCapacity(entry.stage.resources.count)
        for resource in entry.stage.resources {
            let data: Data
            do {
                data = try Data(contentsOf: resource.decodedURL, options: [.mappedIfSafe])
            } catch {
                throw GoldenEyeStagePayloadStoreErrorV6.invalidTransition(
                    stageID,
                    "decoded payload could not be opened for \(resource.kind.rawValue): \(error)"
                )
            }
            let expected = Int(resource.decodedBytes)
            guard data.count == expected else {
                throw GoldenEyeStagePayloadStoreErrorV6.decodedSizeMismatch(
                    stageID,
                    resource.kind,
                    resource.decodedBytes,
                    UInt32(clamping: data.count)
                )
            }
            let actual = Self.sha256(data)
            guard actual == resource.decodedSHA256 else {
                throw GoldenEyeStagePayloadStoreErrorV6.digestMismatch(
                    stageID,
                    resource.kind,
                    resource.decodedSHA256,
                    actual
                )
            }
            payloads[resource.kind] = data
        }
        guard payloads.count == GoldenEyeStageAssetKind.allCases.count else {
            throw GoldenEyeStagePayloadStoreErrorV6.invalidTransition(
                stageID,
                "decoded resource count is \(payloads.count), expected \(GoldenEyeStageAssetKind.allCases.count)"
            )
        }
        entry.payloads = payloads
        entry.loadCount = entry.loadCount == UInt32.max ? UInt32.max : entry.loadCount + 1
        entries[stageID] = entry
        return try snapshot(stageID: stageID)
    }

    @discardableResult
    public mutating func activate(stageID: UInt32) throws -> GoldenEyeStagePayloadSnapshotV6 {
        guard entries[stageID] != nil else {
            throw GoldenEyeStagePayloadStoreErrorV6.unknownStage(stageID)
        }
        if let activeStageID, activeStageID != stageID {
            throw GoldenEyeStagePayloadStoreErrorV6.invalidTransition(
                stageID,
                "stage \(activeStageID) is active; deactivate it before replacement"
            )
        }
        if try !isLoaded(stageID: stageID) {
            _ = try load(stageID: stageID)
        }
        guard var entry = entries[stageID] else {
            throw GoldenEyeStagePayloadStoreErrorV6.unknownStage(stageID)
        }
        entry.active = true
        entries[stageID] = entry
        return try snapshot(stageID: stageID)
    }

    @discardableResult
    public mutating func deactivate(stageID: UInt32) throws -> GoldenEyeStagePayloadSnapshotV6 {
        guard var entry = entries[stageID] else {
            throw GoldenEyeStagePayloadStoreErrorV6.unknownStage(stageID)
        }
        guard entry.active else {
            throw GoldenEyeStagePayloadStoreErrorV6.invalidTransition(
                stageID,
                "stage is not active"
            )
        }
        entry.active = false
        entries[stageID] = entry
        return try snapshot(stageID: stageID)
    }

    @discardableResult
    public mutating func unload(stageID: UInt32) throws -> GoldenEyeStagePayloadSnapshotV6 {
        guard var entry = entries[stageID] else {
            throw GoldenEyeStagePayloadStoreErrorV6.unknownStage(stageID)
        }
        guard !entry.active else {
            throw GoldenEyeStagePayloadStoreErrorV6.invalidTransition(
                stageID,
                "active stage cannot be unloaded"
            )
        }
        guard !entry.payloads.isEmpty else {
            throw GoldenEyeStagePayloadStoreErrorV6.invalidTransition(
                stageID,
                "stage is not loaded"
            )
        }
        entry.payloads.removeAll(keepingCapacity: false)
        entries[stageID] = entry
        return try snapshot(stageID: stageID)
    }

    public mutating func reset() throws {
        if let activeStageID {
            throw GoldenEyeStagePayloadStoreErrorV6.activeStageRemains(activeStageID)
        }
        let loadedStageIDs = entries.values
            .filter { !$0.payloads.isEmpty }
            .map { $0.stage.stageID }
            .sorted()
        for stageID in loadedStageIDs {
            _ = try unload(stageID: stageID)
        }
    }

    public func read(
        stageID: UInt32,
        kind: GoldenEyeStageAssetKind,
        offset: UInt32,
        count: UInt32
    ) throws -> GoldenEyeStagePayloadReadV6 {
        guard count <= maxReadBytes else {
            throw GoldenEyeStagePayloadStoreErrorV6.oversizedRead(count)
        }
        guard let entry = entries[stageID] else {
            throw GoldenEyeStagePayloadStoreErrorV6.unknownStage(stageID)
        }
        guard !entry.payloads.isEmpty else {
            throw GoldenEyeStagePayloadStoreErrorV6.stageNotLoaded(stageID)
        }
        guard entry.active else {
            throw GoldenEyeStagePayloadStoreErrorV6.invalidTransition(
                stageID,
                "stage payloads are loaded but not active"
            )
        }
        guard let data = entry.payloads[kind] else {
            throw GoldenEyeStagePayloadStoreErrorV6.unknownResource(stageID, kind)
        }
        guard offset <= UInt32(clamping: data.count),
              count <= UInt32(clamping: data.count) - offset else {
            throw GoldenEyeStagePayloadStoreErrorV6.invalidRange(stageID, kind, offset, count)
        }
        let start = Int(offset)
        let end = start + Int(count)
        let resource = entry.stage.resources.first { $0.kind == kind }
        return GoldenEyeStagePayloadReadV6(
            stageID: stageID,
            kind: kind,
            assetHandle: resource?.assetHandle ?? 0,
            decodedOffset: offset,
            bytes: data.subdata(in: start..<end),
            decodedHash: Self.sha256(data)
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func hashPayloads(
        _ payloads: [GoldenEyeStageAssetKind: Data],
        stage: GoldenEyeStageAssetStage
    ) -> String {
        var data = Data()
        for resource in stage.resources.sorted(by: { $0.kind.canonicalOrder < $1.kind.canonicalOrder }) {
            data.append(contentsOf: resource.kind.rawValue.utf8)
            data.append(payloads[resource.kind] ?? Data())
        }
        return sha256(data)
    }
}

private extension GoldenEyeStageAssetKind {
    var canonicalOrder: UInt32 {
        switch self {
        case .background: return UInt32(GE_STAGE_V5_RESOURCE_BACKGROUND)
        case .stan: return UInt32(GE_STAGE_V5_RESOURCE_STAN)
        case .setup: return UInt32(GE_STAGE_V5_RESOURCE_SETUP)
        }
    }
}
