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
    /// The exact signed 16-bit values emitted by ``gSPFogPosition`` in
    /// ``include/PR/gbi.h``.  The source RSP evaluates
    /// ``clamp(eyespaceZ * fm + fo, 0, 255)``; these are not the distance
    /// coefficients used by ``fogGetPropDistColor`` below.
    public let sourceFogMultiplier: Int32
    public let sourceFogOffset: Int32
    public let scaledFarFogDistanceQ16: Int32
    public let scaledDifferenceFogDistanceQ16: Int32
    public let farFogFactorQ16: Int32
    public let nearFogFactorQ16: Int32
    /// The generic V6 shader has a typed source-symmetric fog lane. This flag
    /// is true only when the stage camera's per-row viSetZRange and
    /// homogeneous coordinate provenance are both proven.
    public let exactMetalFactorBindingAvailable: Bool
    public let unsupportedReasonCode: UInt32
    public let packetHash: UInt64

    public var requiresRendererBinding: Bool {
        enabled && !exactMetalFactorBindingAvailable
    }

    /// Evaluate the exact source geometry fog equation for one copied
    /// clip-Z/clip-W coordinate.  The coordinate is signed Q16.16 and the
    /// result is the source RDP fog alpha in Q8 (0...255), normalized to the
    /// Q16.16 factor used by the value-only smoke/evidence contract.
    public func geometryFactor(
        at fogCoordinateQ16: Int32
    ) -> GoldenEyeStageFogFactorV6 {
        let product = Int64(fogCoordinateQ16) * Int64(sourceFogMultiplier)
        let sourceAlpha = product / 65_536 + Int64(sourceFogOffset)
        let alphaQ8 = min(Int64(255), max(Int64(0), sourceAlpha))
        let factorQ16 = (alphaQ8 * 65_536) / 255
        return GoldenEyeStageFogFactorV6(
            stageID: stageID,
            eyespaceZQ16: fogCoordinateQ16,
            factorQ16: Int32(factorQ16),
            sourceFogColorRGBA: sourceFogColorRGBA,
            sourcePacketHash: packetHash
        )
    }

    /// Retain the existing distance-space prop equation from
    /// fogGetPropDistColor(). Geometry binding uses ``geometryFactor(at:)``
    /// above and the independent clip-Z/clip-W register equation.
    public func factor(at eyespaceZQ16: Int32) -> GoldenEyeStageFogFactorV6 {
        let product = Int64(eyespaceZQ16) * Int64(farFogFactorQ16)
        let roundedProduct: Int64
        if product >= 0 {
            roundedProduct = (product + 32_768) >> 16
        } else {
            roundedProduct = (product - 32_768) >> 16
        }
        let unclamped = roundedProduct + Int64(nearFogFactorQ16)
        let clamped = min(Int64(65_536), max(Int64(0), unclamped))
        return GoldenEyeStageFogFactorV6(
            stageID: stageID,
            eyespaceZQ16: eyespaceZQ16,
            factorQ16: Int32(clamped),
            sourceFogColorRGBA: sourceFogColorRGBA,
            sourcePacketHash: packetHash
        )
    }
}

/// Typed source fog factor data ready for a future Metal vertex/fragment
/// binding.  The packet hash ties the factor back to the exact stage row; no
/// renderer may substitute a guessed neutral factor or color.
public struct GoldenEyeStageFogFactorV6: Sendable, Equatable {
    public let stageID: UInt32
    public let eyespaceZQ16: Int32
    public let factorQ16: Int32
    public let sourceFogColorRGBA: UInt32
    public let sourcePacketHash: UInt64

    public var isFullyFogged: Bool { factorQ16 == 65_536 }
    public var isVisible: Bool { factorQ16 < 65_536 }
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
            // fogGetPropDistColor(): sp20/sp1C use the source's 256-based
            // fog-position terms (sp20's 0.5 - 0 term is 128), then the two
            // distance coefficients are divided by 255 before the per-depth
            // alpha equation.
            let sp20 = 128.0 / (farIntensity - difference)
            let sp1C = (256.0 * (0.5 - difference)) /
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
        let fogDenominator = Int64(row.farIntensity) - Int64(row.differenceFromFarIntensity)
        // This is the integer arithmetic in gSPFogPosition(), not the
        // distance-space prop equation above.  Keep the values in the source
        // signed 16-bit fog register domain so truncation/overflow can never
        // silently alter the command payload. Fogless fallback rows never
        // emit G_FOG and therefore carry a deterministic zero pair.
        let sourceFogMultiplier64: Int64
        let sourceFogOffset64: Int64
        if row.enabled {
            guard fogDenominator > 0 else {
                throw GoldenEyeStageFogLoweringError.unsupportedStage(stageID)
            }
            sourceFogMultiplier64 = 128_000 / fogDenominator
            sourceFogOffset64 = ((500 - Int64(row.differenceFromFarIntensity)) * 256) /
                fogDenominator
            guard sourceFogMultiplier64 >= Int64(Int16.min),
                  sourceFogMultiplier64 <= Int64(Int16.max),
                  sourceFogOffset64 >= Int64(Int16.min),
                  sourceFogOffset64 <= Int64(Int16.max) else {
                throw GoldenEyeStageFogLoweringError.unsupportedStage(stageID)
            }
        } else {
            sourceFogMultiplier64 = 0
            sourceFogOffset64 = 0
        }
        let sourceFogMultiplier = Int32(sourceFogMultiplier64)
        let sourceFogOffset = Int32(sourceFogOffset64)
        // The stage camera derives the source per-row clip range and the
        // packet/clipper preserves and recomputes homogeneous clip-Z/clip-W
        // before the renderer boundary. The shader admits only the exact
        // G_FOG geometry tuple, so enabled rows with this provenance marker
        // have a complete typed binding.
        let exactMetalBinding = row.enabled && row.exactCoordinateProvenance &&
            sourceFogMultiplier64 == Int64(sourceFogMultiplier) &&
            sourceFogOffset64 == Int64(sourceFogOffset)
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
            UInt64(bitPattern: Int64(sourceFogMultiplier)),
            UInt64(bitPattern: Int64(sourceFogOffset)),
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
            sourceFogMultiplier: sourceFogMultiplier,
            sourceFogOffset: sourceFogOffset,
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
        /// Set only when the caller has proven the stage camera's per-row
        /// viSetZRange and homogeneous fog coordinate provenance.
        let exactCoordinateProvenance: Bool
    }

    private static func sourceRow(stageID: UInt32) -> SourceRow? {
        switch stageID {
        // US fog_tables[]: src/game/bgfog.c, EnvironmentRecord rows.
        case 33: // LEVELID_DAM; level visibility 0.2 in src/game/bg.c
            return SourceRow(enabled: true, blendMultiplier: 5, farFog: 15_000, nearFog: 3_333, visibilityScale: 0.2, differenceFromFarIntensity: 0x3e3, farIntensity: 0x3e8, red: 0x10, green: 0x30, blue: 0x60, exactCoordinateProvenance: true)
        case 34: // LEVELID_FACILITY
            return SourceRow(enabled: true, blendMultiplier: 10, farFog: 5_000, nearFog: 0, visibilityScale: 1.0, differenceFromFarIntensity: 0x3de, farIntensity: 0x3e8, red: 0x10, green: 0x20, blue: 0x10, exactCoordinateProvenance: true)
        case 35: // LEVELID_RUNWAY
            return SourceRow(enabled: true, blendMultiplier: 10, farFog: 15_000, nearFog: 6_000, visibilityScale: 1.0, differenceFromFarIntensity: 0x3e4, farIntensity: 0x3e8, red: 0x10, green: 0x30, blue: 0x40, exactCoordinateProvenance: true)
        case 25: // LEVELID_TRAIN
            return SourceRow(enabled: true, blendMultiplier: 10, farFog: 1_500, nearFog: 0, visibilityScale: 1.0, differenceFromFarIntensity: 0x3e4, farIntensity: 0x3e8, red: 0x00, green: 0x00, blue: 0x08, exactCoordinateProvenance: true)
        // These stages select the source fogless fallback in fogLoadLevelEnvironment().
        case 9, 20, 26:
            return SourceRow(enabled: false, blendMultiplier: 15, farFog: 10_000, nearFog: 0, visibilityScale: 1.0, differenceFromFarIntensity: 0, farIntensity: 0, red: 0, green: 0, blue: 0, exactCoordinateProvenance: false)
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
