import Foundation

/// Portable source-AI decoder for the bounded setup AI lists.  The command
/// lengths are generated from `src/aicommands.def` / `src/aicommands2.h` with
/// GE's one-byte AI command envelope.  This module only copies command bytes
/// and extracts source weapon-give records; it does not execute an unported AI
/// branch or invent a target/path state.
struct GoldenEyeRamRomGuardAISourceV6: Sendable, Equatable {
    /// Canonical checked-in global list rows. These rows are source
    /// semantics, not prepared payloads; a page may only clear its global-AI
    /// requirement after a guarded copy of the corresponding row is added.
    static let canonicalGlobalSourceRows: [UInt32: String] = [
        2: "src/game/chraidata.c:88:m_StandardGuard",
        5: "src/game/chraidata.c:260:m_SimpleGuardDeaf",
        9: "src/game/chraidata.c:471:m_SimpleGuardAlarmRaiser",
    ]

    static func canonicalGlobalSourceRow(for listID: UInt32) -> String? {
        canonicalGlobalSourceRows[listID]
    }

    struct WeaponChoice: Sendable, Equatable {
        let propID: UInt32
        let itemID: UInt32
        let propFlags: UInt32
        let label: UInt32
        let sourceOffset: UInt32
    }

    struct AnimationChoice: Sendable, Equatable {
        let animationID: UInt32
        let tableOffset: UInt32
        let startFrame: Int32
        let endFrame: Int32
        let flags: UInt32
        let interpolation60: UInt32
        let sourceOffset: UInt32
    }

    struct Analysis: Sendable, Equatable {
        let listID: UInt32
        let sourceOffset: UInt32
        let commandCount: UInt32
        let sourceHash: UInt64
        let ended: Bool
        let weaponChoices: [WeaponChoice]
        let animationChoices: [AnimationChoice]
        let runtimeOpcodes: [UInt32]
        let malformed: String?

        var initialStateReady: Bool { ended && malformed == nil }
    }

    private static let commandLengths: [UInt8] = [
        2, 2, 2, 1, 1, 4, 3, 1, 1, 1, 9, 2, 1, 1, 2, 2,
        2, 2, 2, 2, 6, 6, 6, 6, 4, 4, 2, 5, 3, 1, 3, 3,
        2, 1, 1, 2, 4, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 2,
        3, 3, 2, 1, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        3, 2, 2, 2, 4, 2, 2, 3, 3, 3, 3, 4, 4, 7, 7, 5,
        5, 4, 6, 6, 5, 4, 3, 3, 4, 3, 3, 3, 3, 3, 2, 2,
        2, 2, 2, 2, 3, 4, 2, 2, 4, 3, 3, 3, 4, 3, 3, 3,
        3, 3, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 4, 4, 3, 3,
        3, 2, 2, 2, 3, 2, 2, 2, 2, 3, 2, 3, 2, 2, 2, 3,
        3, 2, 2, 2, 2, 2, 3, 3, 3, 4, 5, 5, 6, 5, 5, 6,
        6, 6, 7, 6, 6, 7, 6, 6, 7, 2, 3, 3, 4, 0, 1, 1,
        1, 1, 2, 5, 5, 1, 1, 3, 1, 1, 2, 4, 4, 12, 11, 9,
        8, 5, 3, 3, 4, 5, 6, 6, 6, 2, 5, 2, 5, 5, 2, 2,
        4, 2, 1, 1, 3, 6, 4, 2, 1, 5, 1, 1, 2, 1, 1, 2,
        3, 3, 4, 2, 2, 3, 5, 2, 2, 1, 1, 2, 1, 1, 13, 1,
        2, 2, 3, 2, 4, 2, 1, 3, 3, 1, 1, 1, 2,
    ]

    /// Commands which only alter the source AI PC/initial action state. Any
    /// other opcode is retained as exact evidence until its runtime branch is
    /// ported; it is never silently treated as a no-op.
    private static let initialOnlyOpcodes: Set<UInt32> = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
    ]

    private static let animationTableOffsets: [UInt32: UInt32] = [
        1: 0x144, 2: 0x214, 89: 0x777c, 90: 0x77d4,
        98: 0x7aa8, 99: 0x7c4c, 100: 0x7d04, 101: 0x7dd8,
        102: 0x7f0c, 103: 0x7fb4, 104: 0x8080, 105: 0x8164,
        106: 0x8194, 107: 0x8204, 172: 0xd5e4, 173: 0xd668,
        174: 0xd6f8, 175: 0xd728,
    ]

    static func analyze(
        setupData: Data,
        aiLists: [GoldenEyeStageSetupAIListPacket],
        listID: UInt32,
        sourceLimit: Int = 64 * 1024
    ) -> Analysis {
        guard let list = aiLists.first(where: { $0.identifier == listID }) else {
            return Analysis(
                listID: listID, sourceOffset: 0, commandCount: 0, sourceHash: 0,
                ended: false, weaponChoices: [], animationChoices: [], runtimeOpcodes: [],
                malformed: "src/game/chrai.c:773 global/local AI list " + String(listID) + " is not in setup"
            )
        }
        let start = Int(list.scriptOffset)
        guard start >= 0, start < setupData.count else {
            return Analysis(
                listID: listID, sourceOffset: list.scriptOffset, commandCount: 0, sourceHash: 0,
                ended: false, weaponChoices: [], animationChoices: [], runtimeOpcodes: [],
                malformed: "src/game/chrai.c:773 AI script offset " + String(list.scriptOffset) + " is outside setup"
            )
        }
        let scriptLimit: Int
        if sourceLimit > 0 {
            let (candidate, overflow) = start.addingReportingOverflow(sourceLimit)
            scriptLimit = overflow ? setupData.count : min(setupData.count, candidate)
        } else {
            scriptLimit = setupData.count
        }
        var hash: UInt64 = 1_469_598_103_934_665_603
        var offset = start
        var commands: UInt32 = 0
        var ended = false
        var weapons: [WeaponChoice] = []
        var animations: [AnimationChoice] = []
        var runtime: [UInt32] = []
        while offset < scriptLimit && commands < 16_384 {
            let opcode = UInt32(setupData[offset])
            guard opcode < UInt32(commandLengths.count) else {
                return malformed(listID, list.scriptOffset, commands, hash, offset, opcode, "opcode")
            }
            let length: Int
            if opcode == 0xad {
                // debug_log is the one variable-length source AI command.
                // bondaicommands.h bounds it at 0x32 bytes and requires a
                // NUL terminator; preserve the complete bounded record in
                // the source hash instead of treating it as an unknown op.
                let end = min(scriptLimit, offset + 0x32)
                guard offset + 1 < end,
                      let terminator = setupData[(offset + 1)..<end].firstIndex(of: 0) else {
                    return malformed(listID, list.scriptOffset, commands, hash, offset, opcode, "debug_log terminator")
                }
                length = terminator - offset + 1
            } else {
                length = Int(commandLengths[Int(opcode)])
            }
            guard length > 0, offset + length <= scriptLimit else {
                return malformed(listID, list.scriptOffset, commands, hash, offset, opcode, "length")
            }
            for byte in setupData[offset..<(offset + length)] {
                hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
            }
            if opcode == 4 {
                ended = true
                break
            }
            if !initialOnlyOpcodes.contains(opcode) { runtime.append(opcode) }
            if opcode == 191 && length >= 9 {
                let prop = UInt32(setupData[offset + 1]) << 8 | UInt32(setupData[offset + 2])
                let item = UInt32(setupData[offset + 3])
                let flags = UInt32(setupData[offset + 4]) << 24 |
                    UInt32(setupData[offset + 5]) << 16 |
                    UInt32(setupData[offset + 6]) << 8 | UInt32(setupData[offset + 7])
                weapons.append(WeaponChoice(
                    propID: prop, itemID: item, propFlags: flags,
                    label: UInt32(setupData[offset + 8]), sourceOffset: UInt32(offset)
                ))
            }
            if opcode == 10 && length >= 9 {
                let animationID = UInt32(setupData[offset + 1]) << 8 | UInt32(setupData[offset + 2])
                let startRaw = UInt16(setupData[offset + 3]) << 8 | UInt16(setupData[offset + 4])
                let endRaw = UInt16(setupData[offset + 5]) << 8 | UInt16(setupData[offset + 6])
                animations.append(AnimationChoice(
                    animationID: animationID,
                    tableOffset: animationTableOffsets[animationID] ?? UInt32.max,
                    startFrame: Int32(Int16(bitPattern: startRaw)),
                    endFrame: Int32(Int16(bitPattern: endRaw)),
                    flags: UInt32(setupData[offset + 7]),
                    interpolation60: UInt32(setupData[offset + 8]),
                    sourceOffset: UInt32(offset)
                ))
            }
            commands += 1
            offset += length
        }
        if !ended {
            return Analysis(
                listID: listID, sourceOffset: list.scriptOffset, commandCount: commands,
                sourceHash: hash, ended: false, weaponChoices: weapons, animationChoices: animations,
                runtimeOpcodes: Array(Set(runtime)).sorted(),
                malformed: "src/game/chrai.c:773 AI list " + String(listID) + " has no AI_EndList opcode"
            )
        }
        return Analysis(
            listID: listID, sourceOffset: list.scriptOffset, commandCount: commands,
            sourceHash: hash, ended: true, weaponChoices: weapons, animationChoices: animations,
            runtimeOpcodes: Array(Set(runtime)).sorted(), malformed: nil
        )
    }

    private static func malformed(
        _ listID: UInt32, _ sourceOffset: UInt32, _ commands: UInt32,
        _ hash: UInt64, _ offset: Int, _ opcode: UInt32, _ reason: String
    ) -> Analysis {
        Analysis(
            listID: listID, sourceOffset: sourceOffset, commandCount: commands,
            sourceHash: hash, ended: false, weaponChoices: [], animationChoices: [], runtimeOpcodes: [opcode],
            malformed: "src/game/chrai.c:156-770 AI list " + String(listID) +
                " offset " + String(offset) + " opcode 0x" + String(opcode, radix: 16) + " " + reason
        )
    }
}
