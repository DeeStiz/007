import Foundation
import GoldenEyeNative
import GoldenEyeOriginalFrontend

@main
struct GoldenEyeOriginalPairedAuthorityV6Smoke {
    static func main() {
        do {
            try run()
            print("goldeneye_original_paired_authority_v6_smoke: PASS")
        } catch {
            fputs("goldeneye_original_paired_authority_v6_smoke: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        precondition(MemoryLayout<GEOriginalFrontendInputV6>.size == 56)
        precondition(MemoryLayout<GEOriginalFrontendEventV6>.size == 80)
        precondition(MemoryLayout<GEOriginalFrontendStateV6>.size == 104)
        precondition(MemoryLayout<GEOriginalFrontendFrameV6>.size == 104)

        var authority = try GoldenEyeOriginalPairedAuthorityV6()
        precondition(authority.originalState.native_tick == 0)
        precondition(authority.lastProjection.screen ==
                     UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL))
        precondition(!authority.lastFrame.originalExecuted)
        precondition(
            authority.lastFrame.authoritativeFrame.provenance == .nativeBootstrap
        )

        let oddResult = modelResultForSourceState(
            authority.nativeAuthority.state,
            nativeTick: 1
        )
        let odd = try authority.step(
            nativeTick: 1,
            fileModeControllerCount: 1,
            synthetic: false,
            fileModeHeld: 0,
            fileModePressed: 0,
            fileModeReleased: 0,
            fileModeStickX: 0,
            fileModeStickY: 0,
            modelResultModel: oddResult.model,
            modelResultOperation: oddResult.operation,
            modelResultFlags: oddResult.flags,
            modelResultValue0: oddResult.value0,
            modelResultValue1: oddResult.value1
        )
        precondition(!odd.originalExecuted)
        precondition(odd.originalEventCount == 0)
        precondition(odd.projection.nativeTick == 1)
        precondition(
            odd.authoritativeFrame.provenance == .native120Extension
        )
        precondition(odd.authoritativeFrame.nativeTick == odd.nativeFrame.nativeTick)

        let evenResult = modelResultForSourceState(
            authority.nativeAuthority.state,
            nativeTick: 2
        )
        let firstEven = try authority.step(
            nativeTick: 2,
            fileModeControllerCount: 1,
            synthetic: false,
            fileModeHeld: 0,
            fileModePressed: 0,
            fileModeReleased: 0,
            fileModeStickX: 0,
            fileModeStickY: 0,
            modelResultModel: evenResult.model,
            modelResultOperation: evenResult.operation,
            modelResultFlags: evenResult.flags,
            modelResultValue0: evenResult.value0,
            modelResultValue1: evenResult.value1
        )
        precondition(firstEven.originalExecuted)
        precondition(firstEven.originalEventCount == 0)
        precondition(firstEven.projection.referenceTick == 1)
        precondition(firstEven.projection.screen ==
                     UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL))
        precondition(authority.originalState.native_tick == 2)
        let originalEven = authority.originalFrame
        let authoritativeEven = firstEven.authoritativeFrame
        precondition(authoritativeEven.provenance == .originalCanonical)
        precondition(authoritativeEven.screen == UInt32(originalEven.screen))
        precondition(authoritativeEven.subphase == 0)
        precondition(authoritativeEven.nativeTick == UInt64(originalEven.native_tick))
        precondition(authoritativeEven.referenceTick == UInt64(originalEven.source_frame))
        precondition(authoritativeEven.sourceFrame == UInt32(originalEven.source_frame))
        precondition(authoritativeEven.sourceTimer == UInt32(originalEven.source_timer))
        precondition(authoritativeEven.transitionTimer == UInt32(originalEven.transition_timer))
        precondition(authoritativeEven.flags == UInt32(originalEven.flags))
        precondition(authoritativeEven.stateHash == UInt64(originalEven.state_hash))
        precondition(authoritativeEven.renderHash == UInt64(originalEven.render_hash))
        precondition(authoritativeEven.audioHash == UInt64(originalEven.audio_hash))
        precondition(
            authoritativeEven.unsupportedCount == UInt32(authority.originalState.unsupported_count)
        )

        var mutated = try GoldenEyeOriginalPairedAuthorityV6()
        let mutatedOddResult = modelResultForSourceState(
            mutated.nativeAuthority.state,
            nativeTick: 1
        )
        _ = try mutated.step(
            nativeTick: 1,
            fileModeControllerCount: 1,
            synthetic: false,
            fileModeHeld: 0,
            fileModePressed: 0,
            fileModeReleased: 0,
            fileModeStickX: 0,
            fileModeStickY: 0,
            modelResultModel: mutatedOddResult.model,
            modelResultOperation: mutatedOddResult.operation,
            modelResultFlags: mutatedOddResult.flags,
            modelResultValue0: mutatedOddResult.value0,
            modelResultValue1: mutatedOddResult.value1
        )
        mutated.mutateNativeProjectionForTesting(sourceTimer: 77)
        let mutatedEvenResult = modelResultForSourceState(
            mutated.nativeAuthority.state,
            nativeTick: 2
        )
        do {
            _ = try mutated.step(
                nativeTick: 2,
                fileModeControllerCount: 1,
                synthetic: false,
                fileModeHeld: 0,
                fileModePressed: 0,
                fileModeReleased: 0,
                fileModeStickX: 0,
                fileModeStickY: 0,
                modelResultModel: mutatedEvenResult.model,
                modelResultOperation: mutatedEvenResult.operation,
                modelResultFlags: mutatedEvenResult.flags,
                modelResultValue0: mutatedEvenResult.value0,
                modelResultValue1: mutatedEvenResult.value1
            )
            preconditionFailure("native projection mutation unexpectedly matched original")
        } catch let error as GoldenEyeOriginalPairedAuthorityV6Error {
            guard case let .projectionMismatch(_, field, _, _) = error,
                  field == "sourceTimer" else {
                preconditionFailure("unexpected native mutation error: \(error)")
            }
        }

        do {
            _ = try authority.step(nativeTick: 4)
            preconditionFailure("paired authority accepted a skipped odd/even pair")
        } catch let error as GoldenEyeOriginalPairedAuthorityV6Error {
            guard case let .invalidTick(expected, actual) = error,
                  expected == 3, actual == 4 else {
                preconditionFailure("unexpected skipped-tick error: \(error)")
            }
        }

        // The linked production target captures source constructors through
        // the value-only host hooks. Continue through the source-owned
        // Rareware/gunbarrel/GoldenEye render-coupled timing and a
        // source-permitted input route to File Select.
        var reachedNintendo = false
        var reachedGoldenEye = false
        var reachedFileSelect = false
        var capturedScreens: Set<UInt32> = []
        var productionFailure: GoldenEyeOriginalPairedAuthorityV6Error?
        var sawBloodAcknowledgement = false
        while authority.nativeAuthority.state.native_tick < 5_000 {
            let tick = UInt64(authority.nativeAuthority.state.native_tick) + 1
            do {
                let buttons: UInt32 = tick >= 3_423 && tick < 3_800
                    ? UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_ANY)
                    : UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_BUTTON_NONE)
                let result = modelResultForSourceState(
                    authority.nativeAuthority.state,
                    nativeTick: tick
                )
                if !sawBloodAcknowledgement,
                   authority.nativeAuthority.state.screen ==
                       UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL),
                   authority.nativeAuthority.state.gunbarrel_mode == 5,
                   tick & 1 == 0 {
                    print(
                        "paired_gunbarrel_blood_ack="
                            + "tick=\(tick) g_MenuTimer=\(authority.nativeAuthority.state.source_timer) "
                            + "gunbarrel_mode=\(authority.nativeAuthority.state.gunbarrel_mode) "
                            + "gunbarrel_counter=\(authority.nativeAuthority.state.gunbarrel_counter) "
                            + "modelResult=\(result.model)/\(result.operation)/0x\(String(result.flags, radix: 16))"
                    )
                    sawBloodAcknowledgement = true
                }
                let frame = try authority.step(
                    nativeTick: tick,
                    buttonsPressed: buttons,
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
                if frame.projection.screen ==
                    UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO) {
                    reachedNintendo = true
                    precondition(frame.originalExecuted == (tick & 1 == 0))
                    if tick & 1 == 0 {
                        precondition(frame.projection.sourceTimer ==
                                     authority.originalState.source_timer)
                    }
                }
                if tick & 1 == 0 {
                    let original = authority.originalFrame
                    let authoritative = frame.authoritativeFrame
                    precondition(authoritative.provenance == .originalCanonical)
                    precondition(authoritative.screen == UInt32(original.screen))
                    precondition(authoritative.sourceFrame == UInt32(original.source_frame))
                    precondition(authoritative.sourceTimer == UInt32(original.source_timer))
                    precondition(authoritative.transitionTimer == UInt32(original.transition_timer))
                    precondition(authoritative.stateHash == UInt64(original.state_hash))
                    precondition(authoritative.renderHash == UInt64(original.render_hash))
                    precondition(authoritative.audioHash == UInt64(original.audio_hash))
                } else {
                    precondition(
                        frame.authoritativeFrame.provenance == .native120Extension
                    )
                }
                if frame.projection.screen ==
                    UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE) {
                    reachedGoldenEye = true
                }
                if frame.projection.screen ==
                    UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT) {
                    reachedFileSelect = true
                }
                if frame.originalExecuted,
                   frame.projection.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO) ||
                   frame.projection.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE) ||
                   frame.projection.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL) ||
                   frame.projection.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE) ||
                   frame.projection.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT) {
                    precondition(frame.originalRenderEventCount > 0)
                    capturedScreens.insert(frame.projection.screen)
                }
            } catch let error as GoldenEyeOriginalPairedAuthorityV6Error {
                switch error {
                case .originalUnsupported, .sourceGap, .projectionMismatch:
                    productionFailure = error
                    break
                default:
                    throw error
                }
                if productionFailure != nil {
                    break
                }
            }
        }
        precondition(reachedNintendo)
        precondition(reachedGoldenEye)
        precondition(reachedFileSelect)
        precondition(sawBloodAcknowledgement)
        precondition(capturedScreens.contains(UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO)))
        precondition(capturedScreens.contains(UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE)))
        precondition(capturedScreens.contains(UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL)))
        precondition(capturedScreens.contains(UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE)))
        precondition(capturedScreens.contains(UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT)))
        precondition(productionFailure == nil)
        precondition(authority.nativeAuthority.state.screen ==
                     UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT))
        precondition(authority.originalState.screen ==
                     UInt32(GE_ORIGINAL_FRONTEND_V6_SCREEN_FILE_SELECT))

        // The production renderer currently returns an executed DRAW result
        // for a Gunbarrel frame.  Prove the source-owned blood acknowledgement
        // boundary explicitly: at mode 5 the C source requires a matching
        // BLOOD_TICK/BLOOD_COMPLETE result before it can enter mode 6 and
        // eventually route to GoldenEye.  This is an integration guard, not a
        // production fallback.
        try assertProductionDrawOnlyStopsAtBlood()
    }

    private static func assertProductionDrawOnlyStopsAtBlood() throws {
        var authority = try GoldenEyeOriginalPairedAuthorityV6()
        var observed = false
        while authority.nativeAuthority.state.native_tick < 5_000 {
            let tick = UInt64(authority.nativeAuthority.state.native_tick) + 1
            let result = modelResultForSourceState(
                authority.nativeAuthority.state,
                nativeTick: tick,
                acknowledgeBlood: false
            )
            do {
                _ = try authority.step(
                    nativeTick: tick,
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
            } catch let error as GoldenEyeOriginalPairedAuthorityV6Error {
                guard case let .nativeFlags(errorTick, errorScreen, errorFlags) = error,
                      errorTick == tick,
                      errorScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL),
                      authority.nativeAuthority.state.screen ==
                          UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL),
                      authority.nativeAuthority.state.gunbarrel_mode == 5 else {
                    throw error
                }
                print(
                    "production_draw_only_blood_handoff_gap="
                        + "tick=\(tick) g_MenuTimer=\(authority.nativeAuthority.state.source_timer) "
                        + "gunbarrel_mode=\(authority.nativeAuthority.state.gunbarrel_mode) "
                        + "gunbarrel_counter=\(authority.nativeAuthority.state.gunbarrel_counter) "
                        + "modelResult=\(result.model)/\(result.operation)/0x\(String(result.flags, radix: 16)) "
                        + "nativeFlags=0x\(String(errorFlags, radix: 16))"
                )
                observed = true
                break
            }
        }
        precondition(observed, "draw-only production handoff did not reach the blood acknowledgement boundary")
    }

    private static func modelResultForSourceState(
        _ state: GEFrontendRuntimeV6State,
        nativeTick: UInt64,
        acknowledgeBlood: Bool = true
    ) -> (model: UInt32, operation: UInt32, flags: UInt32, value0: UInt32, value1: UInt32) {
        let executed = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED)
        let bloodComplete = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_BLOOD_COMPLETE)
        if state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL),
           state.gunbarrel_mode == 5,
           nativeTick & 1 == 0 {
            if !acknowledgeBlood {
                return (
                    UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL),
                    UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW),
                    executed, 0, 0
                )
            }
            return (
                UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL),
                UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK),
                executed | bloodComplete, 0, 0
            )
        }
        if state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH),
           state.pending_reload != UInt32.max {
            let model: UInt32
            switch state.pending_reload {
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NINTENDOLOGO)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RAREWARELOGO)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE):
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
                    executed, 0, 0
                )
            }
        }
        let transitionLikely =
            (state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL) &&
                state.source_timer >= 240) ||
            (state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO) &&
                state.source_timer >= 500) ||
            (state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE) &&
                state.source_timer >= 180) ||
            (state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE) &&
                state.rareware_mode == 2) ||
            (state.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL) &&
                state.gunbarrel_mode == 9)
        if nativeTick & 1 == 0,
           state.screen != UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH),
           transitionLikely {
            let model: UInt32
            switch state.screen {
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NINTENDOLOGO)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RAREWARELOGO)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL):
                model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL)
            case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE):
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
                    UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_RELEASE),
                    executed, 0, 0
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
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL):
            model = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL)
        case UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE):
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
            executed, 0, 0
        )
    }
}
