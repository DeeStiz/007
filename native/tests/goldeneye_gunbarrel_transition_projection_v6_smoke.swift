import Foundation
import GoldenEyeNative
import GoldenEyeOriginalFrontend

private let screenGunbarrel = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL)
private let screenGoldenEye = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE)
private let screenSwitch = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH)

private func modelResultForSourceState(
    _ state: GEFrontendRuntimeV6State,
    nativeTick: UInt64
) -> (model: UInt32, operation: UInt32, flags: UInt32, value0: UInt32, value1: UInt32) {
    let executed = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED)
    let bloodComplete = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_BLOOD_COMPLETE)
    if state.screen == screenGunbarrel,
       state.gunbarrel_mode == 5,
       nativeTick & 1 == 0 {
        return (
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL),
            UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK),
            executed | bloodComplete,
            0,
            0
        )
    }
    if state.screen == screenSwitch,
       state.pending_reload != UInt32.max {
        let model: UInt32
        switch state.pending_reload {
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO):
            model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NINTENDOLOGO)
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE):
            model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RAREWARELOGO)
        case screenGunbarrel:
            model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL)
        case screenGoldenEye:
            model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GOLDENEYELOGO)
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT),
             UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT):
            model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_WALLETBOND)
        default:
            model = 0
        }
        if model != 0 {
            return (
                model,
                UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW),
                executed,
                0,
                0
            )
        }
    }

    let model: UInt32
    switch state.screen {
    case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL):
        model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE)
    case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO):
        model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NINTENDOLOGO)
    case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE):
        model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RAREWARELOGO)
    case screenGunbarrel:
        model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL)
    case screenGoldenEye:
        model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GOLDENEYELOGO)
    case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT),
         UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT):
        model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_WALLETBOND)
    default:
        model = 0
    }
    guard model != 0 else { return (0, 0, 0, 0, 0) }
    return (
        model,
        UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW),
        executed,
        0,
        0
    )
}

private func expectedMode2Anchors() -> Int {
    // title.c: g_TitleX starts at -30, increments by 6, and changes mode
    // once it is strictly greater than 1390.
    var x = -30 * 65_536
    var count = 0
    while x <= 1_390 * 65_536 {
        x += 6 * 65_536
        count += 1
    }
    return count
}

private func expectedMode3Anchors() -> Int {
    // title.c's NTSC XDEC3 is 5.8183274.  The fixed-point source seam uses
    // the audited Q16 value 381310 and exits when X <= -80.
    var x = 1_276 * 65_536
    let decrement = 381_310
    var count = 0
    while x > -80 * 65_536 {
        x -= decrement
        count += 1
    }
    return count
}

@main
struct GoldenEyeGunbarrelTransitionProjectionV6Smoke {
    static func main() {
        do {
            let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                ?? "build/native/gunbarrel-transition-projection-v6/trace.tsv")
            try run(to: output)
            print("goldeneye_gunbarrel_transition_projection_v6_smoke: PASS")
        } catch {
            fputs("goldeneye_gunbarrel_transition_projection_v6_smoke: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run(to output: URL) throws {
        precondition(expectedMode2Anchors() == 237)
        precondition(expectedMode3Anchors() == 234)

        var authority = try GoldenEyeOriginalPairedAuthorityV6()
        var lines = [
            "tick\tscreen\tpending\tsourceTimer\tnativeMode\toriginalMode\tnativeCounter\toriginalCounter\tprovenance\tprojectionStateHash"
        ]
        var previousKey: String?
        var firstGunbarrelTick: UInt64?
        var firstGoldenEyeTick: UInt64?
        var observedModes = Set<UInt32>()
        var observedScreens = Set<UInt32>()
        var modeFirstTick: [UInt32: UInt64] = [:]
        var modeLastTick: [UInt32: UInt64] = [:]

        while authority.nativeAuthority.state.native_tick < 6_000 {
            let nativeTick = UInt64(authority.nativeAuthority.state.native_tick) + 1
            let result = modelResultForSourceState(
                authority.nativeAuthority.state,
                nativeTick: nativeTick
            )
            let frame = try authority.step(
                nativeTick: nativeTick,
                buttonsPressed: 0,
                controllerCount: 1,
                fileModeControllerCount: 1,
                synthetic: false,
                fileModeHeld: 0,
                fileModePressed: 0,
                fileModeReleased: 0,
                fileModeStickX: 0,
                fileModeStickY: 0,
                modelResultModel: result.model,
                modelResultOperation: result.operation,
                modelResultFlags: result.flags,
                modelResultValue0: result.value0,
                modelResultValue1: result.value1
            )
            let state = authority.nativeAuthority.state
            observedScreens.insert(UInt32(state.screen))
            if UInt32(state.screen) == screenGunbarrel {
                firstGunbarrelTick = firstGunbarrelTick ?? nativeTick
                observedModes.insert(state.gunbarrel_mode)
                modeFirstTick[state.gunbarrel_mode] = modeFirstTick[state.gunbarrel_mode] ?? nativeTick
                modeLastTick[state.gunbarrel_mode] = nativeTick
            }
            if UInt32(state.screen) == screenGoldenEye {
                firstGoldenEyeTick = firstGoldenEyeTick ?? nativeTick
            }

            if nativeTick & 1 == 0 {
                let original = authority.originalFrame
                precondition(UInt32(original.screen) == UInt32(state.screen))
                precondition(UInt32(original.pending_screen) == UInt32(state.pending_reload))
                precondition(UInt32(original.source_timer) == UInt32(state.source_timer))
                if UInt32(state.screen) == screenGunbarrel {
                    precondition(UInt32(original.gunbarrel_mode) == UInt32(state.gunbarrel_mode))
                    precondition(UInt32(original.gunbarrel_counter) == UInt32(state.gunbarrel_counter))
                }
            }

            let key = [
                UInt32(state.screen),
                UInt32(state.pending_reload),
                UInt32(state.gunbarrel_mode)
            ].map(String.init).joined(separator: ":")
            if key != previousKey {
                lines.append([
                    String(nativeTick),
                    String(state.screen),
                    String(state.pending_reload),
                    String(state.source_timer),
                    String(state.gunbarrel_mode),
                    String(authority.originalFrame.gunbarrel_mode),
                    String(state.gunbarrel_counter),
                    String(authority.originalFrame.gunbarrel_counter),
                    frame.authoritativeFrame.provenance.rawValue,
                    String(frame.projection.stateHash)
                ].joined(separator: "\t"))
                previousKey = key
            }
            if firstGoldenEyeTick != nil {
                break
            }
        }

        guard let firstGunbarrelTick, let firstGoldenEyeTick,
              firstGoldenEyeTick > firstGunbarrelTick,
              observedModes.contains(2), observedModes.contains(3),
              observedModes.contains(4), observedModes.contains(5),
              observedModes.contains(6), observedModes.contains(7),
              observedModes.contains(8), observedModes.contains(9),
              observedScreens.contains(screenGunbarrel),
              observedScreens.contains(screenGoldenEye) else {
            throw NSError(domain: "GunbarrelTransitionProjection", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "source authority did not complete Gunbarrel mode 2..9"
            ])
        }

        let summary = [
            "firstGunbarrelTick=\(firstGunbarrelTick)",
            "firstGoldenEyeTick=\(firstGoldenEyeTick)",
            "observedModes=\(observedModes.sorted().map(String.init).joined(separator: ","))",
            "expectedMode2Anchors=\(expectedMode2Anchors())",
            "expectedMode3Anchors=\(expectedMode3Anchors())",
            "projection=every-even-anchor-exact",
            "handoff=source-authority-complete"
        ].joined(separator: "\n") + "\n"
        let trace = lines.joined(separator: "\n") + "\n\n" + summary
        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(trace.utf8).write(to: output, options: .atomic)
        print(summary, terminator: "")
    }
}
