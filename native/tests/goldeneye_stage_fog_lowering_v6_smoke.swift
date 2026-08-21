import Foundation

@main
struct GoldenEyeStageFogLoweringV6Smoke {
    static func main() throws {
        let expectedEnabled: Set<UInt32> = [25, 33, 34, 35]
        let allStages: [UInt32] = [9, 20, 25, 26, 33, 34, 35]
        var aggregate: UInt64 = 1_469_598_103_934_665_603
        for stageID in allStages {
            let value = try GoldenEyeStageFogLoweringV6.make(stageID: stageID)
            let repeated = try GoldenEyeStageFogLoweringV6.make(stageID: stageID)
            precondition(value == repeated)
            precondition(value.packetHash != 0)
            precondition(value.enabled == expectedEnabled.contains(stageID))
            if value.enabled {
                precondition(value.sourceFogPositionFar > value.sourceFogPositionDifference)
                precondition(value.sourceFogColorRGBA & 0xff == 0xff)
                precondition(!value.requiresRendererBinding)
                precondition(value.exactMetalFactorBindingAvailable)
                precondition(value.unsupportedReasonCode == 0)

                let expectedFogRegister: (Int32, Int32)
                switch stageID {
                case 33: expectedFogRegister = (25_600, -25_344)
                case 34: expectedFogRegister = (12_800, -12_544)
                case 35, 25: expectedFogRegister = (32_000, -31_744)
                default: fatalError("unexpected enabled stage")
                }
                precondition(value.sourceFogMultiplier == expectedFogRegister.0)
                precondition(value.sourceFogOffset == expectedFogRegister.1)
                let expectedPropFactors: (Int32, Int32)
                switch stageID {
                case 33: expectedPropFactors = (-171_118_850, 68_075)
                case 34: expectedPropFactors = (-36_258_669, 73_045)
                case 35: expectedPropFactors = (-90_525_731, 71_828)
                case 25: expectedPropFactors = (-91_072_531, 126_508)
                default: fatalError("unexpected enabled stage")
                }
                precondition(value.farFogFactorQ16 == expectedPropFactors.0)
                precondition(value.nearFogFactorQ16 == expectedPropFactors.1)

                // Exercise the additive source-coordinate contract without
                // substituting the prop-distance equation.  At NDC z=0 the
                // rows are clear; at NDC z=1 they are fully fogged.
                for fogCoordinateQ16 in [Int32(-65_536), 0, 65_536] {
                    let factor = value.geometryFactor(at: fogCoordinateQ16)
                    let sourceAlpha = Int64(fogCoordinateQ16) *
                        Int64(value.sourceFogMultiplier) / 65_536 +
                        Int64(value.sourceFogOffset)
                    let expectedAlpha = min(255, max(0, sourceAlpha))
                    let expected = expectedAlpha * 65_536 / 255
                    precondition(factor.stageID == stageID)
                    precondition(factor.eyespaceZQ16 == fogCoordinateQ16)
                    precondition(factor.factorQ16 == Int32(expected))
                    precondition(factor.sourceFogColorRGBA == value.sourceFogColorRGBA)
                    precondition(factor.sourcePacketHash == value.packetHash)
                }
            } else {
                precondition(!value.requiresRendererBinding)
                precondition(!value.exactMetalFactorBindingAvailable)
                precondition(value.unsupportedReasonCode ==
                             GoldenEyeStageFogLoweringV6.missingMetalFactorBinding)
                precondition(value.sourceFogMultiplier == 0)
                precondition(value.sourceFogOffset == 0)
                precondition(value.factor(at: 0).factorQ16 == 0)
            }
            aggregate ^= value.packetHash &* 1_099_511_628_211
        }
        print(
            "goldeneye_stage_fog_lowering_v6_smoke: PASS stages=7 " +
            "enabled=4 aggregate=\(aggregate)"
        )
    }
}
