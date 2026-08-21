import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Source head selection copied from bodiesReset/bodyChooseHead.  The
/// authority is intentionally separate from character animation and
/// SwitchNodes: a resolved head never makes a character presentable until the
/// remaining source animation/attachment records are supplied.
public struct GoldenEyeRamRomCharacterHeadSelectionV6: Sendable, Equatable {
    public let stageID: UInt32
    public let demoID: UInt8
    public let objectIndex: UInt32
    public let bodyID: UInt32
    public let bodyIsMale: Bool
    /// Index into the source gender-specific random_*_heads table.
    public let tableIndex: UInt32?
    /// The source HEAD_* value selected by bodyChooseHead, not a host array
    /// index or model handle.
    public let sourceHeadID: UInt32
    public let randomSeedBefore: UInt64
    public let randomSeedAfter: UInt64
    public let consumedRandom: Bool
    public let sourceHash: UInt64

    public init(
        stageID: UInt32,
        demoID: UInt8,
        objectIndex: UInt32,
        bodyID: UInt32,
        bodyIsMale: Bool,
        tableIndex: UInt32?,
        sourceHeadID: UInt32,
        randomSeedBefore: UInt64,
        randomSeedAfter: UInt64,
        consumedRandom: Bool,
        sourceHash: UInt64
    ) {
        self.stageID = stageID
        self.demoID = demoID
        self.objectIndex = objectIndex
        self.bodyID = bodyID
        self.bodyIsMale = bodyIsMale
        self.tableIndex = tableIndex
        self.sourceHeadID = sourceHeadID
        self.randomSeedBefore = randomSeedBefore
        self.randomSeedAfter = randomSeedAfter
        self.consumedRandom = consumedRandom
        self.sourceHash = sourceHash
    }
}

public struct GoldenEyeRamRomCharacterHeadSelectionAuthorityV6: Sendable {
    public enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case notReset
        case unknownBody(UInt32)
        case invalidExplicitHead(UInt32)

        public var description: String {
            switch self {
            case .notReset:
                return "source head selection requires bodiesReset seed boundary"
            case let .unknownBody(bodyID):
                return "source head selection body gender is unknown for body \(bodyID)"
            case let .invalidExplicitHead(headID):
                return "source head selection explicit head \(headID) is invalid"
            }
        }
    }

    /// Exact source arrays from src/game/chr.c.  The terminal -1 entries are
    /// excluded, so these counts are the source num_male_heads/female_heads.
    public static let maleHeadIDs: [UInt32] = [
        57, 54, 55, 62, 59, 56, 58, 53, 52, 51, 42, 43, 44, 45, 46, 47,
        48, 49, 50, 63, 64, 65, 66, 67, 68,
    ]
    public static let femaleHeadIDs: [UInt32] = [70, 71, 72, 73]

    /// Source list_of_bodies has 42 entries before its terminal -1. The
    /// values are not used for head selection; current_random_body is only
    /// the reset-boundary index until a source body-choice consumer exists.
    public static let sourceBodyCount: UInt32 = 42

    private static let maleBodyIDs: Set<UInt32> = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 15, 17, 18, 19, 20, 21,
        22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 41,
    ]

    private static let femaleBodyIDs: Set<UInt32> = [11, 14, 16, 26, 27, 28, 29, 40]

    public private(set) var sourceSeed: UInt64
    public private(set) var currentRandomMaleHead: UInt32 = 0
    public private(set) var currentRandomFemaleHead: UInt32 = 0
    public private(set) var currentRandomBody: UInt32 = 0
    public private(set) var didReset = false

    public init(sourceRandomSeed: UInt64) {
        self.sourceSeed = sourceRandomSeed
    }

    /// Exact non-Goldfinger bodiesReset boundary. It consumes three source
    /// random values in order: male-head base, female-head base, body base.
    public mutating func reset() {
        currentRandomMaleHead = Self.next(&sourceSeed) % UInt32(Self.maleHeadIDs.count)
        currentRandomFemaleHead = Self.next(&sourceSeed) % UInt32(Self.femaleHeadIDs.count)
        currentRandomBody = Self.next(&sourceSeed) % Self.sourceBodyCount
        didReset = true
    }

    public mutating func select(
        stageID: UInt32,
        demoID: UInt8,
        objectIndex: UInt32,
        bodyID: UInt32,
        explicitHeadID: UInt32? = nil
    ) throws -> GoldenEyeRamRomCharacterHeadSelectionV6 {
        guard didReset else { throw Error.notReset }
        guard let bodyIsMale = Self.bodyIsMale(bodyID) else {
            throw Error.unknownBody(bodyID)
        }
        let before = sourceSeed
        if let explicitHeadID {
            guard explicitHeadID != UInt32.max else {
                throw Error.invalidExplicitHead(explicitHeadID)
            }
            let tableIndex = (bodyIsMale ? Self.maleHeadIDs : Self.femaleHeadIDs)
                .firstIndex(of: explicitHeadID)
                .map(UInt32.init)
            return Self.selection(
                stageID: stageID, demoID: demoID, objectIndex: objectIndex,
                bodyID: bodyID, bodyIsMale: bodyIsMale, tableIndex: tableIndex,
                sourceHeadID: explicitHeadID, before: before, after: sourceSeed,
                consumedRandom: false
            )
        }

        let tableIndex: UInt32
        if bodyIsMale {
            let offset = Self.next(&sourceSeed) & 3
            tableIndex = (currentRandomMaleHead + offset) % UInt32(Self.maleHeadIDs.count)
        } else {
            // Source bodyChooseHead uses current_random_female_head directly;
            // it does not consume another random value for female bodies.
            tableIndex = currentRandomFemaleHead
        }
        let heads = bodyIsMale ? Self.maleHeadIDs : Self.femaleHeadIDs
        let sourceHeadID = heads[Int(tableIndex)]
        return Self.selection(
            stageID: stageID, demoID: demoID, objectIndex: objectIndex,
            bodyID: bodyID, bodyIsMale: bodyIsMale, tableIndex: tableIndex,
            sourceHeadID: sourceHeadID, before: before, after: sourceSeed,
            consumedRandom: bodyIsMale
        )
    }

    public static func bodyIsMale(_ bodyID: UInt32) -> Bool? {
        if maleBodyIDs.contains(bodyID) { return true }
        if femaleBodyIDs.contains(bodyID) { return false }
        return nil
    }

    private static func selection(
        stageID: UInt32,
        demoID: UInt8,
        objectIndex: UInt32,
        bodyID: UInt32,
        bodyIsMale: Bool,
        tableIndex: UInt32?,
        sourceHeadID: UInt32,
        before: UInt64,
        after: UInt64,
        consumedRandom: Bool
    ) -> GoldenEyeRamRomCharacterHeadSelectionV6 {
        var hash = offsetBasis
        for value in [
            UInt64(stageID), UInt64(demoID), UInt64(objectIndex), UInt64(bodyID),
            UInt64(bodyIsMale ? 1 : 0), UInt64(tableIndex ?? UInt32.max),
            UInt64(sourceHeadID), before, after, UInt64(consumedRandom ? 1 : 0),
        ] {
            hash = mix(hash, value)
        }
        return GoldenEyeRamRomCharacterHeadSelectionV6(
            stageID: stageID, demoID: demoID, objectIndex: objectIndex,
            bodyID: bodyID, bodyIsMale: bodyIsMale, tableIndex: tableIndex,
            sourceHeadID: sourceHeadID, randomSeedBefore: before,
            randomSeedAfter: after, consumedRandom: consumedRandom,
            sourceHash: hash
        )
    }

    private static func next(_ seed: inout UInt64) -> UInt32 {
        #if canImport(GoldenEyeNative)
        ge_ramrom_gameplay_v6_source_random_next(&seed)
        #else
        // Standalone value-only character fixtures do not link the C gameplay
        // owner. Product builds and the dedicated head-selection sanitizer
        // lane use the C symbol above; this branch preserves fixture parity
        // without inventing a second production authority.
        let value = seed
        let shifted = ((value & 1) << 32) | ((value >> 1) & 0x7fff_ffff)
        let mixed = shifted ^ (value << 12)
        let next = mixed ^ ((mixed >> 20) & 0xfff)
        seed = next
        return UInt32(truncatingIfNeeded: next)
        #endif
    }

    private static let offsetBasis: UInt64 = 1_469_598_103_934_665_603

    private static func mix(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 56, by: 8) {
            result = (result ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
        }
        return result == 0 ? 1 : result
    }
}
