import Foundation

/// Source ``EnvironmentRecord`` fog state copied from ``src/game/bgfog.c``.
/// The record is deliberately independent of the generic scene ABI: it holds
/// only fixed-width values and the deterministic scalar equations needed by a
/// later per-fragment Metal fog binding.
public struct GoldenEyeStageFogParametersV6: Sendable, Equatable {
    public let stageID: UInt32
    public let enabled: Bool
    public let sourceBlendMultiplier: UInt32
    public let sourceFarFog: UInt32
    public let sourceNearFog: UInt32
    public let sourceVisibilityScaleQ16: Int32
    public let sourceDifferenceFromFarIntensityQ16: Int32
    public let sourceFarIntensityQ16: Int32
    public let sourceFogColorRGBA: UInt32
    public let sourceFogPositionDifference: UInt32
    public let sourceFogPositionFar: UInt32
    public let scaledFarFogDistanceQ16: Int32
    public let scaledDifferenceFogDistanceQ16: Int32
    public let farFogFactorQ16: Int32
    public let nearFogFactorQ16: Int32
    /// The source equations are complete, but the current generic Metal
    /// record has no typed per-fragment fog coordinate/position input.
    public let exactMetalFactorBindingAvailable: Bool
    public let unsupportedReasonCode: UInt32
    public let packetHash: UInt64

    public var requiresRendererBinding: Bool {
        enabled && !exactMetalFactorBindingAvailable
    }
}

public enum GoldenEyeStageFogLoweringError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedStage(UInt32)

    public var description: String {
        switch self {
        case let .unsupportedStage(stageID):
            return "no source fog-table evidence for stage \(stageID)"
        }
    }
}

public enum GoldenEyeStageFogLoweringV6 {
    /// ``src/game/bgfog.c`` uses this diagnostic until the generic shader
    /// receives the source G_FOG per-fragment coordinate contract.
    public static let missingMetalFactorBinding: UInt32 = 1

    public static func make(stageID: UInt32) throws -> GoldenEyeStageFogParametersV6 {
        guard let row = sourceRow(stageID: stageID) else {
            throw GoldenEyeStageFogLoweringError.unsupportedStage(stageID)
        }
        guard row.visibilityScale > 0 else {
            throw GoldenEyeStageFogLoweringError.unsupportedStage(stageID)
        }

        let visibilityQ16 = q16(row.visibilityScale)
        let difference = Double(row.differenceFromFarIntensity) / 1000.0
        let farIntensity = Double(row.farIntensity) / 1000.0
        let zNear = Double(row.blendMultiplier) / row.visibilityScale
        let zFar = Double(row.farFog) / row.visibilityScale
        let zSpan = zFar - zNear
        let scaledFar = zSpan * farIntensity + zNear
        let scaledDifference = zSpan * difference + zNear

        let factors: (far: Double, near: Double)
        if row.enabled, abs(farIntensity - difference) > 0.000_000_001,
           abs(zFar - zNear) > 0.000_000_001 {
            // Exact source algebra from fogLoadCurrentEnvironment() and
            // fogGetPropDistColor(): sp20/sp1C are the source's 128-based
            // fog-position terms, then the two distance coefficients are
            // divided by 255 before the per-depth alpha equation.
            let sp20 = 128.0 / (farIntensity - difference)
            let sp1C = (128.0 * (0.5 - difference)) /
                (farIntensity - difference)
            let farFactor = (zFar * -sp20 * (zNear + 1.0) /
                (zFar - zNear)) / 255.0
            let nearFactor = (sp20 * (zFar + 1.0) /
                (zFar - zNear) + sp1C) / 255.0
            factors = (far: farFactor, near: nearFactor)
        } else {
            factors = (far: 0, near: 0)
        }

        let fogColor = (UInt32(row.red) << 24) |
            (UInt32(row.green) << 16) |
            (UInt32(row.blue) << 8) | 0xff
        let exactMetalBinding = false
        var hash = Hash.offset
        for value in [
            UInt64(stageID), UInt64(row.enabled ? 1 : 0),
            UInt64(row.blendMultiplier), UInt64(row.farFog), UInt64(row.nearFog),
            UInt64(bitPattern: Int64(visibilityQ16)),
            UInt64(bitPattern: Int64(q16(difference))),
            UInt64(bitPattern: Int64(q16(farIntensity))), UInt64(fogColor),
            UInt64(row.differenceFromFarIntensity), UInt64(row.farIntensity),
            UInt64(bitPattern: Int64(q16(scaledFar))),
            UInt64(bitPattern: Int64(q16(scaledDifference))),
            UInt64(bitPattern: Int64(q16(factors.far))),
            UInt64(bitPattern: Int64(q16(factors.near))),
            UInt64(exactMetalBinding ? 1 : 0),
            UInt64(exactMetalBinding ? 0 : missingMetalFactorBinding),
        ] {
            hash = Hash.word(hash, value)
        }
        return GoldenEyeStageFogParametersV6(
            stageID: stageID,
            enabled: row.enabled,
            sourceBlendMultiplier: row.blendMultiplier,
            sourceFarFog: row.farFog,
            sourceNearFog: row.nearFog,
            sourceVisibilityScaleQ16: visibilityQ16,
            sourceDifferenceFromFarIntensityQ16: q16(difference),
            sourceFarIntensityQ16: q16(farIntensity),
            sourceFogColorRGBA: fogColor,
            sourceFogPositionDifference: row.differenceFromFarIntensity,
            sourceFogPositionFar: row.farIntensity,
            scaledFarFogDistanceQ16: q16(scaledFar),
            scaledDifferenceFogDistanceQ16: q16(scaledDifference),
            farFogFactorQ16: q16(factors.far),
            nearFogFactorQ16: q16(factors.near),
            exactMetalFactorBindingAvailable: exactMetalBinding,
            unsupportedReasonCode: exactMetalBinding ? 0 : missingMetalFactorBinding,
            packetHash: hash
        )
    }

    private struct SourceRow {
        let enabled: Bool
        let blendMultiplier: UInt32
        let farFog: UInt32
        let nearFog: UInt32
        let visibilityScale: Double
        let differenceFromFarIntensity: UInt32
        let farIntensity: UInt32
        let red: UInt32
        let green: UInt32
        let blue: UInt32
    }

    private static func sourceRow(stageID: UInt32) -> SourceRow? {
        switch stageID {
        // US fog_tables[]: src/game/bgfog.c, EnvironmentRecord rows.
        case 33: // LEVELID_DAM; level visibility 0.2 in src/game/bg.c
            return SourceRow(enabled: true, blendMultiplier: 5, farFog: 15_000, nearFog: 3_333, visibilityScale: 0.2, differenceFromFarIntensity: 0x3e3, farIntensity: 0x3e7, red: 0x10, green: 0x30, blue: 0x60)
        case 34: // LEVELID_FACILITY
            return SourceRow(enabled: true, blendMultiplier: 10, farFog: 5_000, nearFog: 0, visibilityScale: 1.0, differenceFromFarIntensity: 0x3de, farIntensity: 0x3e7, red: 0x10, green: 0x20, blue: 0x10)
        case 35: // LEVELID_RUNWAY
            return SourceRow(enabled: true, blendMultiplier: 10, farFog: 15_000, nearFog: 6_000, visibilityScale: 1.0, differenceFromFarIntensity: 0x3e4, farIntensity: 0x3e7, red: 0x10, green: 0x30, blue: 0x40)
        case 25: // LEVELID_TRAIN
            return SourceRow(enabled: true, blendMultiplier: 10, farFog: 1_500, nearFog: 0, visibilityScale: 1.0, differenceFromFarIntensity: 0x3e4, farIntensity: 0x3e7, red: 0x00, green: 0x00, blue: 0x08)
        // These stages select the source fogless fallback in fogLoadLevelEnvironment().
        case 9, 20, 26:
            return SourceRow(enabled: false, blendMultiplier: 15, farFog: 10_000, nearFog: 0, visibilityScale: 1.0, differenceFromFarIntensity: 0, farIntensity: 0, red: 0, green: 0, blue: 0)
        default:
            return nil
        }
    }

    private static func q16(_ value: Double) -> Int32 {
        Int32(clamping: Int64((value * 65_536.0).rounded(.toNearestOrAwayFromZero)))
    }

    private enum Hash {
        static let offset: UInt64 = 1_469_598_103_934_665_603
        static let prime: UInt64 = 1_099_511_628_211

        static func word(_ initial: UInt64, _ value: UInt64) -> UInt64 {
            var hash = initial
            for shift in stride(from: 0, to: 64, by: 8) {
                hash = (hash ^ ((value >> UInt64(shift)) & 0xff)) &* prime
            }
            return hash
        }
    }
}
