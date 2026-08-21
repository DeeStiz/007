import Foundation

@main
struct GoldenEyeRamRomCharacterHeadSelectionV6Smoke {
    static func main() throws {
        let seed: UInt64 = 0xAB8D_9F77_8128_0783
        var expected = seed
        let expectedMale = oracleNext(&expected) % 25
        let expectedFemale = oracleNext(&expected) % 4
        let expectedBody = oracleNext(&expected) % 42

        var authority = GoldenEyeRamRomCharacterHeadSelectionAuthorityV6(
            sourceRandomSeed: seed
        )
        do {
            _ = try authority.select(
                stageID: 33, demoID: 1, objectIndex: 1, bodyID: 0
            )
            fatalError("head selection accepted a pre-bodiesReset boundary")
        } catch let error as GoldenEyeRamRomCharacterHeadSelectionAuthorityV6.Error {
            precondition(error == .notReset)
        }
        authority.reset()
        precondition(authority.currentRandomMaleHead == expectedMale)
        precondition(authority.currentRandomFemaleHead == expectedFemale)
        precondition(authority.currentRandomBody == expectedBody)
        precondition(authority.sourceSeed == expected)

        let maleRandomBefore = expected
        let maleOffset = oracleNext(&expected) & 3
        let maleTableIndex = (expectedMale + maleOffset) % 25
        let male = try authority.select(
            stageID: 33, demoID: 1, objectIndex: 100, bodyID: 0
        )
        precondition(male.bodyIsMale)
        precondition(male.tableIndex == maleTableIndex)
        precondition(
            male.sourceHeadID ==
                GoldenEyeRamRomCharacterHeadSelectionAuthorityV6.maleHeadIDs[Int(maleTableIndex)]
        )
        precondition(male.randomSeedBefore == maleRandomBefore)
        precondition(male.randomSeedAfter == expected)
        precondition(male.consumedRandom)

        let femaleBefore = expected
        let female = try authority.select(
            stageID: 33, demoID: 1, objectIndex: 101, bodyID: 11
        )
        precondition(!female.bodyIsMale)
        precondition(female.tableIndex == expectedFemale)
        precondition(
            female.sourceHeadID ==
                GoldenEyeRamRomCharacterHeadSelectionAuthorityV6.femaleHeadIDs[Int(expectedFemale)]
        )
        precondition(female.randomSeedBefore == femaleBefore)
        precondition(female.randomSeedAfter == femaleBefore)
        precondition(!female.consumedRandom)

        let explicitBefore = authority.sourceSeed
        let explicit = try authority.select(
            stageID: 33, demoID: 1, objectIndex: 102, bodyID: 0,
            explicitHeadID: 57
        )
        precondition(explicit.sourceHeadID == 57)
        precondition(explicit.tableIndex == 0)
        precondition(!explicit.consumedRandom)
        precondition(explicit.randomSeedBefore == explicitBefore)
        precondition(explicit.randomSeedAfter == explicitBefore)

        var repeated = GoldenEyeRamRomCharacterHeadSelectionAuthorityV6(
            sourceRandomSeed: seed
        )
        repeated.reset()
        let repeatedMale = try repeated.select(
            stageID: 33, demoID: 1, objectIndex: 100, bodyID: 0
        )
        precondition(repeatedMale == male)
        precondition(male.sourceHash != 0)
        precondition(
            GoldenEyeRamRomCharacterHeadSelectionAuthorityV6.bodyIsMale(11) == false
        )
        precondition(
            GoldenEyeRamRomCharacterHeadSelectionAuthorityV6.bodyIsMale(999) == nil
        )
        do {
            _ = try authority.select(
                stageID: 33, demoID: 1, objectIndex: 103, bodyID: 999
            )
            fatalError("unknown body gender was accepted")
        } catch let error as GoldenEyeRamRomCharacterHeadSelectionAuthorityV6.Error {
            precondition(error == .unknownBody(999))
        }
        print(
            "goldeneye_ramrom_character_head_selection_v6_smoke: PASS " +
                "bodiesReset=1 maleHeads=25 femaleHeads=4 " +
                "maleConsumed=1 femaleConsumed=0 explicitConsumed=0 deterministic=1"
        )
    }

    private static func oracleNext(_ seed: inout UInt64) -> UInt32 {
        let value = seed
        let shifted = ((value & 1) << 32) | ((value >> 1) & 0x7fff_ffff)
        let mixed = shifted ^ (value << 12)
        let next = mixed ^ ((mixed >> 20) & 0xfff)
        seed = next
        return UInt32(truncatingIfNeeded: next)
    }
}
