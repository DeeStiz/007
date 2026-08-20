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
                precondition(value.requiresRendererBinding)
                precondition(value.unsupportedReasonCode ==
                             GoldenEyeStageFogLoweringV6.missingMetalFactorBinding)
            } else {
                precondition(!value.requiresRendererBinding)
                precondition(value.unsupportedReasonCode ==
                             GoldenEyeStageFogLoweringV6.missingMetalFactorBinding)
            }
            aggregate ^= value.packetHash &* 1_099_511_628_211
        }
        print(
            "goldeneye_stage_fog_lowering_v6_smoke: PASS stages=7 " +
            "enabled=4 aggregate=\(aggregate)"
        )
    }
}
