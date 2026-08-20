import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

@main
struct GoldenEyeSourceFrontendAuthorityV6Smoke {
    static func main() {
        do {
            try run()
            print("goldeneye_source_frontend_authority_v6_smoke: PASS")
        } catch {
            fputs("goldeneye_source_frontend_authority_v6_smoke: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        precondition(MemoryLayout<GEFrontendRuntimeV6Input>.size == 80)
        precondition(MemoryLayout<GEFrontendRuntimeV6State>.size == 112)
        precondition(MemoryLayout<GEFrontendRuntimeV6Snapshot>.size == 184)
        precondition(MemoryLayout<GEFrontendRuntimeV6EventBatch>.size == 14_952)
        precondition(MemoryLayout<GEFrontendRuntimeV6Frame>.size == 15_152)
        var authority = try GoldenEyeSourceFrontendAuthorityV6()
        precondition(authority.lastFrame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL))
        precondition(authority.state.native_tick == 0)
        precondition(authority.lastFrame.unsupportedCount == 0)
        precondition(authority.lastFrame.diagnosticEvents.isEmpty)
        precondition(authority.lastFrame.summary.screenEvents ==
                     UInt32(authority.lastFrame.screenEvents.count))
        precondition(authority.lastFrame.summary.modelEvents ==
                     UInt32(authority.lastFrame.modelEvents.count))
        precondition(authority.lastFrame.summary.audioEvents ==
                     UInt32(authority.lastFrame.audioEvents.count))
        precondition(authority.lastFrame.summary.saveEvents ==
                     UInt32(authority.lastFrame.saveEvents.count))
        precondition(authority.lastFrame.audioEvents.contains {
            $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_STOP_MUSIC) &&
            $0.assetID == 0
        })
        precondition(authority.lastFrame.saveEvents.contains {
            $0.operation == 1 && $0.folder == UInt32.max
        })

        let tick1 = try GoldenEyeSourceFrontendTimelineV6(nativeTick: 1)
        let first = try authority.step(tick1)
        precondition(first.nativeTick == 1)
        precondition(first.sourceTimer == 0)
        precondition(first.modelEvents.count > 0)
        precondition(first.diagnosticEvents.isEmpty)
        precondition(first.modelEvents.contains {
            $0.model == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE) &&
            $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW) &&
            $0.resultFlags == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_NONE)
        })
        precondition(first.renderEvents.first?.operation ==
                     UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_FRAME_BEGIN))
        precondition(first.screenHash != 0)
        precondition(first.modelHash != 0)
        precondition(first.renderEventHash != 0)
        precondition(first.diagnosticHash != 0)

        let tick2 = try GoldenEyeSourceFrontendTimelineV6(nativeTick: 2)
        let second = try authority.step(
            tick2,
            modelResultModel: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE),
            modelResultOperation: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW),
            modelResultFlags: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED)
        )
        precondition(second.nativeTick == 2)
        precondition(second.referenceTick == 1)
        precondition(second.sourceTimer == 1)
        precondition(second.diagnosticEvents.isEmpty)
        precondition(second.unsupportedCount == 0)
        precondition(second.modelEvents.contains {
            $0.model == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_LEGALPAGE) &&
            $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_DRAW) &&
            $0.resultFlags == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED)
        })

        do {
            let skipped = try GoldenEyeSourceFrontendTimelineV6(nativeTick: 4)
            _ = try authority.step(skipped)
            preconditionFailure("out-of-order timeline was accepted")
        } catch let error as GoldenEyeSourceFrontendAuthorityV6Error {
            guard case .timelineOutOfOrder(expected: 3, actual: 4) = error else {
                preconditionFailure("unexpected timeline error: \(error)")
            }
        }

        var route = try GoldenEyeSourceFrontendAuthorityV6()
        let checkpoints: [UInt64: UInt32] = [
            482: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH),
            490: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO),
            1_492: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH),
            1_500: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE),
            2_080: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH),
            2_088: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL),
            3_414: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_SWITCH),
            3_422: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE)
        ]
        let expectedHashes: [UInt64: (UInt64, UInt64, UInt64, UInt64, UInt64)] = [
            482: (12_148_411_076_173_669_584, 8_993_193_564_978_864_323,
                  1_469_598_103_934_665_603, 15_168_420_778_098_252_373,
                  16_452_672_044_474_766_681),
            490: (17_197_748_433_994_636_776, 1_539_429_964_335_137_430,
                  6_418_139_492_873_329_037, 4_339_580_779_072_900_167,
                  14_248_640_562_281_692_134),
            1_492: (3_211_041_422_698_025_979, 3_388_390_801_265_945_923,
                    1_469_598_103_934_665_603, 9_130_697_064_002_292_971,
                    12_078_952_769_377_972_224),
            1_500: (7_164_807_020_729_162_208, 7_191_874_429_797_370_364,
                    4_096_621_968_161_550_010, 16_441_844_686_733_458_069,
                    12_429_629_656_934_165_744),
            2_080: (13_127_586_111_353_531_099, 1_469_598_103_934_665_603,
                    1_469_598_103_934_665_603, 6_549_056_298_776_763_641,
                    1_469_598_103_934_665_603),
            2_088: (1_388_088_631_140_964_831, 518_861_022_813_054_600,
                    6_101_314_762_243_868_957, 18_079_995_050_108_269_164,
                    17_232_617_065_479_170_018),
            3_414: (8_423_579_721_212_471_147, 4_135_293_261_568_208_526,
                    1_469_598_103_934_665_603, 11_736_805_842_578_029_847,
                    2_168_490_003_780_996_348),
            3_422: (1_742_107_397_966_388_705, 15_952_112_473_578_439_006,
                    1_469_598_103_934_665_603, 9_806_366_698_405_544_775,
                    851_804_230_807_133_558)
        ]
        for tick in UInt64(1)...UInt64(3_422) {
            let timeline = try GoldenEyeSourceFrontendTimelineV6(nativeTick: tick)
            let frame = try route.step(
                timeline,
                modelResultModel: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_GUNBARREL),
                modelResultOperation: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK),
                modelResultFlags: UInt32(
                    GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_BLOOD_COMPLETE |
                        GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED
                )
            )
            if let expectedScreen = checkpoints[tick] {
                precondition(frame.screen == expectedScreen)
                precondition(frame.screenHash != 0)
                precondition(frame.renderEventHash != 0)
                precondition(frame.diagnosticHash != 0)
                if let expected = expectedHashes[tick] {
                    precondition(frame.screenHash == expected.0)
                    precondition(frame.modelHash == expected.1)
                    precondition(frame.audioEventHash == expected.2)
                    precondition(frame.renderEventHash == expected.3)
                    precondition(frame.diagnosticHash == expected.4)
                }
            }
            if tick == 482 {
                precondition(frame.screenEvents.contains {
                    $0.event == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_EVENT_TRANSITION) &&
                        $0.targetScreen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO) &&
                        $0.sourceTimer == 241
                })
            }
            if tick == 490 {
                precondition(frame.audioEvents.contains {
                    $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_PLAY_MUSIC) &&
                        $0.assetID == 44
                })
            }
            if tick == 1_500 {
                precondition(frame.audioEvents.contains {
                    $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_PLAY_SFX) &&
                        $0.assetID == 258
                })
            }
            if tick == 2_088 {
                precondition(frame.audioEvents.contains {
                    $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_PLAY_MUSIC) &&
                        $0.assetID == 2
                })
            }
        }
        precondition(route.lastFrame.screen == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE))

        for tick in UInt64(1)...UInt64(8) {
            var cState = GEFrontendRuntimeV6State()
            var cFrame = GEFrontendRuntimeV6Frame()
            guard ge_frontend_runtime_v6_init(&cState, &cFrame) == GE_STATUS_OK else {
                throw GoldenEyeSourceFrontendAuthorityV6Error.cStatus(1)
            }
            cState.native_tick = tick - 1
            cState.pending_direct = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO)

            var input = GEFrontendRuntimeV6Input()
            input.header.abi_version = GE_NATIVE_ABI_VERSION
            input.header.struct_size = UInt32(MemoryLayout<GEFrontendRuntimeV6Input>.size)
            input.record_version = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RECORD_VERSION)
            input.flags = UInt32(
                GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_FOCUSED |
                    GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_CONTROLLER_CONNECTED |
                    GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_SYNTHETIC
            )
            if tick & 1 == 0 {
                input.flags |= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_INPUT_FLAG_SOURCE_ANCHOR)
            }
            input.controller_count = 1
            input.clock_timer = 1
            input.native_tick = tick
            input.sequence = tick
            guard ge_frontend_runtime_v6_step(&cState, &input, &cFrame) == GE_STATUS_OK else {
                throw GoldenEyeSourceFrontendAuthorityV6Error.cStatus(2)
            }
            let frame = GoldenEyeSourceFrontendFrameV6(cFrame)
            guard let audio = frame.audioEvents.first(where: {
                $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_AUDIO_OP_PLAY_MUSIC)
            }) else {
                preconditionFailure("missing direct Nintendo audio cue at tick \(tick)")
            }
            precondition(audio.assetID == 44)
            precondition(audio.sourceSample == (tick * 735) / 4)
            if tick & 1 == 1 {
                precondition(audio.sourceSample == (tick * 735) / 4)
            }
        }
    }
}
