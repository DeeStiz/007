import Foundation

/// Explicit lifecycle states for the scheduler-independent stage foundation.
/// These states describe metadata/arena ownership only; they do not imply that
/// gameplay, Metal resources, or unsupported stage categories are executable.
public enum GoldenEyeStageLifecyclePhaseV6: UInt8, Sendable, Equatable {
    case unloaded = 0
    case loaded = 1
    case active = 2
}

public enum GoldenEyeStageLifecycleErrorV6: Error, Sendable, Equatable, CustomStringConvertible {
    case unknownStage(UInt32)
    case invalidTransition(UInt32, GoldenEyeStageLifecyclePhaseV6, GoldenEyeStageLifecyclePhaseV6)
    case activeStagesRemain([UInt32])
    case decodedArenaOverflow
    case stageViewCount(UInt32, Int)

    public var description: String {
        switch self {
        case let .unknownStage(stageID):
            return "stage lifecycle does not contain stage \(stageID)"
        case let .invalidTransition(stageID, from, to):
            return "stage \(stageID) cannot transition from \(from) to \(to)"
        case let .activeStagesRemain(stageIDs):
            return "stage lifecycle reset requires inactive stages: \(stageIDs)"
        case .decodedArenaOverflow:
            return "stage lifecycle decoded arena exceeds the fixed-width offset domain"
        case let .stageViewCount(stageID, count):
            return "stage \(stageID) has \(count) resource views; expected 3"
        }
    }
}

/// A copied, pointer-free lifecycle snapshot. Resource bytes remain owned by
/// the prepared asset root and are never retained by this value type.
public struct GoldenEyeStageLifecycleSnapshotV6: Sendable, Equatable {
    public let stageID: UInt32
    public let stageName: String
    public let phase: GoldenEyeStageLifecyclePhaseV6
    public let loadCount: UInt32
    public let resourceHandles: [UInt32]
    public let sourceBytes: UInt32
    public let decodedBytes: UInt32
    public let resourceViewHash: UInt64
    public let stateHash: UInt64
}

/// Bounded native platform-service lifecycle for prepared stage metadata.
///
/// This contract closes the safe M24 portion that can be represented without
/// an N64 scheduler: catalog/file-index identity, 1172-validated decoded
/// sizes, deterministic arena offsets, and load/activate/deactivate/unload
/// transitions. It intentionally does not retain payload bytes, create Metal
/// objects, run gameplay, or clear any M25–M27 unsupported diagnostics.
public struct GoldenEyeStageLifecycleV6: Sendable {
    private struct Entry: Sendable {
        let stageID: UInt32
        let stageName: String
        let views: [GoldenEyeStageResourceView]
        var phase: GoldenEyeStageLifecyclePhaseV6
        var loadCount: UInt32
    }

    private static let hashOffset: UInt64 = 14_695_981_039_346_656_037
    private static let hashPrime: UInt64 = 1_099_511_628_211

    public let catalogHash: UInt64
    public let decodedArenaBase: UInt32
    public let decodedArenaBytes: UInt32
    public let resourceViewHash: UInt64
    private var entries: [UInt32: Entry]

    public init(
        catalog: GoldenEyeStageAssetCatalog,
        decodedArenaBase: UInt32 = 4_096
    ) throws {
        let decodedTotal = catalog.stages.reduce(UInt64(0)) { total, stage in
            total + stage.resources.reduce(UInt64(0)) { bytes, resource in
                bytes + UInt64(resource.decodedBytes)
            }
        }
        guard decodedTotal <= UInt64(UInt32.max - decodedArenaBase) else {
            throw GoldenEyeStageLifecycleErrorV6.decodedArenaOverflow
        }

        let loader = GoldenEyeStageResourceLoader(catalog: catalog)
        let arenaBytes = UInt32(decodedTotal)
        let views = try loader.views(
            decodedArenaBase: decodedArenaBase,
            decodedArenaBytes: arenaBytes + decodedArenaBase
        )

        var built: [UInt32: Entry] = [:]
        built.reserveCapacity(catalog.stages.count)
        for stage in catalog.stages {
            let stageViews = views.filter { $0.stageID == stage.stageID }
            guard stageViews.count == GoldenEyeStageAssetKind.allCases.count else {
                throw GoldenEyeStageLifecycleErrorV6.stageViewCount(
                    stage.stageID,
                    stageViews.count
                )
            }
            built[stage.stageID] = Entry(
                stageID: stage.stageID,
                stageName: stage.stageName,
                views: stageViews,
                phase: .unloaded,
                loadCount: 0
            )
        }
        self.catalogHash = catalog.catalogHash
        self.decodedArenaBase = decodedArenaBase
        self.decodedArenaBytes = arenaBytes
        self.resourceViewHash = Self.hashViews(views)
        self.entries = built
    }

    public var stageIDs: [UInt32] {
        entries.keys.sorted()
    }

    public var isIdle: Bool {
        entries.values.allSatisfy { $0.phase == .unloaded }
    }

    public func snapshot(stageID: UInt32) throws -> GoldenEyeStageLifecycleSnapshotV6 {
        guard let entry = entries[stageID] else {
            throw GoldenEyeStageLifecycleErrorV6.unknownStage(stageID)
        }
        return Self.snapshot(for: entry)
    }

    public func resourceViews(stageID: UInt32) throws -> [GoldenEyeStageResourceView] {
        guard let entry = entries[stageID] else {
            throw GoldenEyeStageLifecycleErrorV6.unknownStage(stageID)
        }
        guard entry.phase != .unloaded else {
            throw GoldenEyeStageLifecycleErrorV6.invalidTransition(
                stageID,
                entry.phase,
                .loaded
            )
        }
        return entry.views
    }

    @discardableResult
    public mutating func load(stageID: UInt32) throws -> GoldenEyeStageLifecycleSnapshotV6 {
        try transition(stageID: stageID, from: .unloaded, to: .loaded)
    }

    @discardableResult
    public mutating func activate(stageID: UInt32) throws -> GoldenEyeStageLifecycleSnapshotV6 {
        try transition(stageID: stageID, from: .loaded, to: .active)
    }

    @discardableResult
    public mutating func deactivate(stageID: UInt32) throws -> GoldenEyeStageLifecycleSnapshotV6 {
        try transition(stageID: stageID, from: .active, to: .loaded)
    }

    @discardableResult
    public mutating func unload(stageID: UInt32) throws -> GoldenEyeStageLifecycleSnapshotV6 {
        try transition(stageID: stageID, from: .loaded, to: .unloaded)
    }

    public mutating func reset() throws {
        let active = entries.values
            .filter { $0.phase == .active }
            .map(\.stageID)
            .sorted()
        guard active.isEmpty else {
            throw GoldenEyeStageLifecycleErrorV6.activeStagesRemain(active)
        }
        for stageID in entries.keys {
            entries[stageID]?.phase = .unloaded
        }
    }

    private mutating func transition(
        stageID: UInt32,
        from expected: GoldenEyeStageLifecyclePhaseV6,
        to next: GoldenEyeStageLifecyclePhaseV6
    ) throws -> GoldenEyeStageLifecycleSnapshotV6 {
        guard var entry = entries[stageID] else {
            throw GoldenEyeStageLifecycleErrorV6.unknownStage(stageID)
        }
        guard entry.phase == expected else {
            throw GoldenEyeStageLifecycleErrorV6.invalidTransition(
                stageID,
                entry.phase,
                next
            )
        }
        entry.phase = next
        if next == .loaded && expected == .unloaded {
            entry.loadCount = entry.loadCount == UInt32.max
                ? UInt32.max
                : entry.loadCount + 1
        }
        entries[stageID] = entry
        return Self.snapshot(for: entry)
    }

    private static func snapshot(for entry: Entry) -> GoldenEyeStageLifecycleSnapshotV6 {
        let sourceBytes = entry.views.reduce(UInt32(0)) { partial, view in
            partial &+ view.sourceBytes
        }
        let decodedBytes = entry.views.reduce(UInt32(0)) { partial, view in
            partial &+ view.decodedBytes
        }
        let viewHash = hashViews(entry.views)
        var stateHash = viewHash
        stateHash = mix(stateHash, UInt64(entry.stageID))
        stateHash = mix(stateHash, UInt64(entry.phase.rawValue))
        stateHash = mix(stateHash, UInt64(entry.loadCount))
        return GoldenEyeStageLifecycleSnapshotV6(
            stageID: entry.stageID,
            stageName: entry.stageName,
            phase: entry.phase,
            loadCount: entry.loadCount,
            resourceHandles: entry.views.map(\.assetHandle),
            sourceBytes: sourceBytes,
            decodedBytes: decodedBytes,
            resourceViewHash: viewHash,
            stateHash: stateHash
        )
    }

    private static func hashViews(_ views: [GoldenEyeStageResourceView]) -> UInt64 {
        views.reduce(Self.hashOffset) { hash, view in
            var value = hash
            value = mix(value, UInt64(view.packetIndex))
            value = mix(value, UInt64(view.stageID))
            value = mix(value, UInt64(view.assetHandle))
            value = mix(value, UInt64(view.decodedBaseOffset))
            value = mix(value, UInt64(view.decodedBytes))
            value = mix(value, UInt64(view.sourceOffset))
            value = mix(value, UInt64(view.sourceBytes))
            value = mix(value, view.metadataHash)
            return value
        }
    }

    private static func mix(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        var result = hash
        var word = value
        for _ in 0..<8 {
            result ^= word & 0xff
            result &*= Self.hashPrime
            word >>= 8
        }
        return result
    }
}
