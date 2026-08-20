import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

enum GoldenEyeRamRomCatalogError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingAssetRoot
    case invalidCatalogCount(UInt32)
    case missingAsset(String)
    case oversizedAsset(String)
    case parseFailure(String, UInt32)
    case catalogMismatch(String)

    var description: String {
        switch self {
        case .missingAssetRoot:
            return "GOLDENEYE_NATIVE_ASSET_ROOT is not set"
        case let .invalidCatalogCount(count):
            return "RAMROM catalog count is \(count), expected 14"
        case let .missingAsset(name):
            return "RAMROM asset is missing: \(name)"
        case let .oversizedAsset(name):
            return "RAMROM asset exceeds the fixed-width byte-count contract: \(name)"
        case let .parseFailure(name, status):
            return "RAMROM asset \(name) failed parsing with status \(status)"
        case let .catalogMismatch(name):
            return "RAMROM asset does not match its source-order catalog row: \(name)"
        }
    }
}

struct GoldenEyeRamRomDemoRoute: Sendable, Equatable {
    let catalogIndex: UInt8
    let demoID: UInt8
    let stageID: UInt32
    let variant: UInt32
    let controllerCount: UInt32
    let totalTime60: UInt32
    let declaredFileBytes: UInt32
    let assetFileBytes: UInt32
    let packetCount: UInt32
    let recordCount: UInt32
    let recordingHash: UInt64
    let rngHash: UInt64
    let assetName: String
}

/// Immutable result of validating every source RAMROM file against both the
/// parsed stream and the static source-order C catalog.  It intentionally does
/// not retain the file bytes; a future stage owner must reopen the guarded
/// external asset for the duration of its playback call.
struct GoldenEyeRamRomRouteCatalog: Sendable, Equatable {
    static let sourceAssetNames = [
        "ramrom_Dam_1.bin",
        "ramrom_Dam_2.bin",
        "ramrom_Facility_1.bin",
        "ramrom_Facility_2.bin",
        "ramrom_Facility_3.bin",
        "ramrom_Runway_1.bin",
        "ramrom_Runway_2.bin",
        "ramrom_BunkerI_1.bin",
        "ramrom_BunkerI_2.bin",
        "ramrom_Silo_1.bin",
        "ramrom_Silo_2.bin",
        "ramrom_Frigate_1.bin",
        "ramrom_Frigate_2.bin",
        "ramrom_Train.bin",
    ]

    let entries: [GoldenEyeRamRomDemoRoute]
    let catalogHash: UInt64
    let failure: String?

    var isComplete: Bool {
        failure == nil && entries.count == Self.sourceAssetNames.count
    }

    static func parsed(assetRoot: URL) throws -> Self {
        let catalogCount = ge_ramrom_v5_catalog_count()
        guard catalogCount == UInt32(sourceAssetNames.count) else {
            throw GoldenEyeRamRomCatalogError.invalidCatalogCount(catalogCount)
        }

        let ramromRoot = assetRoot.appendingPathComponent("ramrom", isDirectory: true)
        var entries: [GoldenEyeRamRomDemoRoute] = []
        entries.reserveCapacity(sourceAssetNames.count)

        for (index, name) in sourceAssetNames.enumerated() {
            let url = ramromRoot.appendingPathComponent(name, isDirectory: false)
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                throw GoldenEyeRamRomCatalogError.missingAsset(name)
            }
            guard data.count <= Int(UInt32.max) else {
                throw GoldenEyeRamRomCatalogError.oversizedAsset(name)
            }

            var catalog = GERamRomCatalogEntryV5()
            var header = GERamRomHeaderV5()
            var summary = GERamRomParseSummaryV5()
            let catalogStatus = ge_ramrom_v5_catalog_entry(UInt32(index), &catalog)
            let parseStatuses: (UInt32, UInt32) = data.withUnsafeBytes { rawBytes in
                guard let baseAddress = rawBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return (UInt32(GE_STATUS_INVALID_ARGUMENT), UInt32(GE_STATUS_INVALID_ARGUMENT))
                }
                let byteCount = UInt32(data.count)
                return (
                    UInt32(ge_ramrom_v5_read_header(baseAddress, byteCount, &header)),
                    UInt32(ge_ramrom_v5_parse(baseAddress, byteCount, &summary))
                )
            }
            guard catalogStatus == GE_STATUS_OK else {
                throw GoldenEyeRamRomCatalogError.parseFailure(name, UInt32(catalogStatus))
            }
            guard parseStatuses.0 == UInt32(GE_STATUS_OK) else {
                throw GoldenEyeRamRomCatalogError.parseFailure(name, parseStatuses.0)
            }
            guard parseStatuses.1 == UInt32(GE_STATUS_OK) else {
                throw GoldenEyeRamRomCatalogError.parseFailure(name, parseStatuses.1)
            }
            guard catalog.demo_id == UInt32(index + 1),
                  catalog.stage_id == header.stage_id,
                  catalog.controller_count == header.controller_count,
                  catalog.total_time_ms == header.total_time_ms,
                  catalog.declared_file_bytes == header.declared_file_bytes,
                  catalog.asset_file_bytes == UInt32(data.count),
                  catalog.recording_hash == summary.recording_hash,
                  summary.packet_count != 0,
                  summary.parsed_bytes == header.declared_file_bytes else {
                throw GoldenEyeRamRomCatalogError.catalogMismatch(name)
            }

            entries.append(
                GoldenEyeRamRomDemoRoute(
                    catalogIndex: UInt8(index),
                    demoID: UInt8(catalog.demo_id),
                    stageID: catalog.stage_id,
                    variant: catalog.variant,
                    controllerCount: catalog.controller_count,
                    totalTime60: catalog.total_time_ms,
                    declaredFileBytes: catalog.declared_file_bytes,
                    assetFileBytes: catalog.asset_file_bytes,
                    packetCount: summary.packet_count,
                    recordCount: summary.record_count,
                    recordingHash: summary.recording_hash,
                    rngHash: summary.rng_hash,
                    assetName: name
                )
            )
        }

        let hashWords = entries.flatMap { entry in
            [
                UInt64(entry.catalogIndex), UInt64(entry.demoID), UInt64(entry.stageID),
                UInt64(entry.variant), UInt64(entry.controllerCount),
                UInt64(entry.totalTime60), UInt64(entry.packetCount),
                UInt64(entry.recordCount), entry.recordingHash, entry.rngHash,
            ]
        }
        return Self(
            entries: entries,
            catalogHash: GoldenEyeCastRouteHash.fnv1a(hashWords),
            failure: nil
        )
    }

    static func fromEnvironment() -> Self {
        guard let value = ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_ASSET_ROOT"],
              !value.isEmpty else {
            return Self(entries: [], catalogHash: 0, failure: GoldenEyeRamRomCatalogError.missingAssetRoot.description)
        }
        do {
            return try parsed(assetRoot: URL(fileURLWithPath: value, isDirectory: true))
        } catch {
            return Self(entries: [], catalogHash: 0, failure: String(describing: error))
        }
    }
}

struct GoldenEyeCastProgress: OptionSet, Sendable, Equatable {
    let rawValue: UInt8

    static let aztecSecretOr00 = Self(rawValue: 1 << 0)
    static let egypt00 = Self(rawValue: 1 << 1)
}

enum GoldenEyeCastMode: UInt8, Sendable, Equatable {
    case normalAttract = 0
    case extendedCredits = 1
}

enum GoldenEyeCastUnlockGate: UInt8, Sendable, Equatable {
    case none = 0
    case aztecRequired = 1
    case aztecOrRare = 2
    case egyptOrRare = 3
}

struct GoldenEyeCastRouteEntry: Sendable, Equatable {
    let sourceIndex: UInt16
    let extendedOnly: Bool
    let gate: GoldenEyeCastUnlockGate
}

enum GoldenEyeAttractRouteAction: Sendable, Equatable {
    case showCast(UInt16)
    case launchDemo(GoldenEyeRamRomLaunchRequest)
    case missionSelect
    case catalogUnavailable(String)
}

enum GoldenEyeRamRomExitReason: UInt8, Sendable, Equatable {
    case completed = 1
    case realInputAbort = 2
    case failed = 3
}

struct GoldenEyeRamRomLaunchRequest: Sendable, Equatable {
    let catalogIndex: UInt8
    let demoID: UInt8
    let stageID: UInt32
    let variant: UInt32
    let controllerCount: UInt32
    let totalTime60: UInt32
    let packetCount: UInt32
    let recordCount: UInt32
    let recordingHash: UInt64
    let rngHash: UInt64
    let assetName: String
}

/// Exact host port of the source 64-bit random step in `src/random.s`.  The
/// route accepts an explicit seed so independent source-anchor smokes remain
/// repeatable.  Full cast model/animation random consumption belongs to M23;
/// this seam only consumes words for the source eligibility and demo-selection
/// branches that it owns.
private struct GoldenEyeSourceRandom: Sendable, Equatable {
    private(set) var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt32 {
        let rotate = (state << 63) >> 31 | (state << 31) >> 32
        let shifted = (state << 44) >> 32
        var nextState = rotate ^ shifted
        nextState ^= (nextState >> 20) & 0x0fff
        state = nextState
        // The assembly's dsll32/dsra32 return sequence sign-extends this low
        // word in a 64-bit register; callers consume it as the original u32.
        return UInt32(truncatingIfNeeded: nextState)
    }
}

/// Owner-thread value state for the source cast-to-demo route.  Rendering may
/// observe its current indices, but only the title owner advances it.
struct GoldenEyeAttractRoute: Sendable, Equatable {
    private static let castEntries: [GoldenEyeCastRouteEntry] = {
        var values: [GoldenEyeCastRouteEntry] = []
        values.reserveCapacity(34)
        for index in 0..<34 {
            let extendedOnly = index == 0 || (9...29).contains(index)
            let gate: GoldenEyeCastUnlockGate
            switch index {
            case 28, 29: gate = .aztecRequired
            case 30, 31: gate = .aztecOrRare
            case 32, 33: gate = .egyptOrRare
            default: gate = .none
            }
            values.append(
                GoldenEyeCastRouteEntry(
                    sourceIndex: UInt16(index),
                    extendedOnly: extendedOnly,
                    gate: gate
                )
            )
        }
        return values
    }()

    let catalog: GoldenEyeRamRomRouteCatalog
    private var random: GoldenEyeSourceRandom
    private(set) var progress: GoldenEyeCastProgress
    private(set) var castMode: GoldenEyeCastMode?
    private(set) var castSourceIndex: UInt16?
    private(set) var selectedDemo: GoldenEyeRamRomDemoRoute?
    private(set) var exitReason: GoldenEyeRamRomExitReason?
    private var explicitDemoIndex: UInt8?
    private var launchRequestPending = false

    init(
        catalog: GoldenEyeRamRomRouteCatalog,
        randomSeed: UInt64,
        progress: GoldenEyeCastProgress = []
    ) {
        self.catalog = catalog
        self.random = GoldenEyeSourceRandom(seed: randomSeed)
        self.progress = progress
    }

    mutating func setProgress(_ progress: GoldenEyeCastProgress) {
        self.progress = progress
    }

    @discardableResult
    mutating func beginCast(_ mode: GoldenEyeCastMode) -> UInt16 {
        castMode = mode
        castSourceIndex = mode == .normalAttract ? 1 : 0
        selectedDemo = nil
        exitReason = nil
        launchRequestPending = false
        return castSourceIndex!
    }

    mutating func requestDemo(catalogIndex: UInt8?) -> Bool {
        if let catalogIndex, Int(catalogIndex) >= catalog.entries.count {
            return false
        }
        explicitDemoIndex = catalogIndex
        return true
    }

    mutating func advanceCast() -> GoldenEyeAttractRouteAction {
        guard let mode = castMode, let current = castSourceIndex else {
            return .catalogUnavailable("cast route was not initialized")
        }
        var candidate = Int(current) + 1
        while candidate < Self.castEntries.count {
            let entry = Self.castEntries[candidate]
            candidate += 1
            if mode == .normalAttract && entry.extendedOnly { continue }
            if !isEligible(entry) { continue }
            castSourceIndex = entry.sourceIndex
            return .showCast(entry.sourceIndex)
        }

        castSourceIndex = 0
        if mode == .extendedCredits {
            return .missionSelect
        }
        guard catalog.isComplete else {
            return .catalogUnavailable(catalog.failure ?? "RAMROM catalog is incomplete")
        }
        let index: Int
        if let explicitDemoIndex {
            index = Int(explicitDemoIndex)
            self.explicitDemoIndex = nil
        } else {
            index = Int(random.next() % UInt32(catalog.entries.count))
        }
        let demo = catalog.entries[index]
        selectedDemo = demo
        exitReason = nil
        launchRequestPending = true
        return .launchDemo(Self.launchRequest(for: demo))
    }

    mutating func takeLaunchRequest() -> GoldenEyeRamRomLaunchRequest? {
        guard launchRequestPending, let selectedDemo else { return nil }
        launchRequestPending = false
        return Self.launchRequest(for: selectedDemo)
    }

    mutating func finishDemo(_ reason: GoldenEyeRamRomExitReason) -> Bool {
        guard selectedDemo != nil else { return false }
        exitReason = reason
        launchRequestPending = false
        selectedDemo = nil
        castMode = nil
        castSourceIndex = nil
        return true
    }

    private mutating func isEligible(_ entry: GoldenEyeCastRouteEntry) -> Bool {
        switch entry.gate {
        case .none:
            return true
        case .aztecRequired:
            return progress.contains(.aztecSecretOr00)
        case .aztecOrRare:
            return progress.contains(.aztecSecretOr00) || random.next() % 10_000 == 0
        case .egyptOrRare:
            return progress.contains(.egypt00) || random.next() % 10_000 == 0
        }
    }

    private static func launchRequest(for demo: GoldenEyeRamRomDemoRoute) -> GoldenEyeRamRomLaunchRequest {
        GoldenEyeRamRomLaunchRequest(
            catalogIndex: demo.catalogIndex,
            demoID: demo.demoID,
            stageID: demo.stageID,
            variant: demo.variant,
            controllerCount: demo.controllerCount,
            totalTime60: demo.totalTime60,
            packetCount: demo.packetCount,
            recordCount: demo.recordCount,
            recordingHash: demo.recordingHash,
            rngHash: demo.rngHash,
            assetName: demo.assetName
        )
    }
}
