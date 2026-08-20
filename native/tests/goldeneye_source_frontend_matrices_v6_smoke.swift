import Foundation

private let legalHandle: UInt32 = 0xB015_CACD
private let nintendoHandle: UInt32 = 0x5730_A717
private let goldenEyeHandle: UInt32 = 0xE9B1_7506
private let walletHandle: UInt32 = 0x5C01_DCE9

private func input(
    screen: UInt32,
    nativeTick: UInt64,
    sourceTimer: UInt32,
    pairPhase: UInt32
) throws -> GoldenEyeSourceFrontendMatrixInputV6 {
    try GoldenEyeSourceFrontendMatrixInputV6(
        screen: screen,
        nativeTick: nativeTick,
        referenceTick: nativeTick / 2,
        sourceTimer: sourceTimer,
        pairPhase: pairPhase
    )
}

private func values(_ frame: GoldenEyeSourceFrontendMatrixFrameV6, handle: UInt32) -> [Int32] {
    guard let resource = frame.resources.matrices.first(where: { $0.handle == handle }) else {
        preconditionFailure("missing matrix handle 0x\(String(handle, radix: 16))")
    }
    return resource.values
}

private func expect(_ actual: [Int32], _ expected: [Int32], _ name: String) {
    precondition(actual == expected, "\(name): expected \(expected), got \(actual)")
}

@main
struct GoldenEyeSourceFrontendMatricesV6Smoke {
    static func main() throws {
        let viewportExpected: [Int32] = [
            220 << 16, 165 << 16, 65_536, 65_536,
            220 << 16, 165 << 16, 0, 65_536,
        ]

        let legal = try GoldenEyeSourceFrontendMatricesV6.make(
            input: input(screen: 0, nativeTick: 2, sourceTimer: 0, pairPhase: 0),
            modelMatrixHandle: legalHandle
        )
        precondition(legal.resources.viewports.count == 1)
        expect(legal.resources.viewports[0].values, viewportExpected, "440x330 viewport")
        precondition(legal.resources.matrices.first(where: { $0.handle == legalHandle })?.roleFlags == 1 << 0)
        precondition(legal.resources.matrices.count >= 3)
        precondition(legal.resources.matrices[2].roleFlags == 1 << 1)
        expect(
            values(legal, handle: legalHandle),
            [
                65_536, 0, 0, 0,
                0, 65_536, 0, 0,
                0, 0, 65_536, 0,
                0, 0, -262_144_000, 65_536,
            ],
            "Legal look-at"
        )
        precondition(legal.matrixHash == 14_557_527_943_632_421_433)
        precondition(legal.frameHash == 8_491_512_272_080_949_065)

        let nintendoEven0 = try GoldenEyeSourceFrontendMatricesV6.make(
            input: input(screen: 1, nativeTick: 2, sourceTimer: 0, pairPhase: 0),
            modelMatrixHandle: nintendoHandle
        )
        let nintendoOdd0 = try GoldenEyeSourceFrontendMatricesV6.make(
            input: input(screen: 1, nativeTick: 3, sourceTimer: 0, pairPhase: 1),
            modelMatrixHandle: nintendoHandle
        )
        let nintendoEven1 = try GoldenEyeSourceFrontendMatricesV6.make(
            input: input(screen: 1, nativeTick: 4, sourceTimer: 1, pairPhase: 0),
            modelMatrixHandle: nintendoHandle
        )
        let nintendoOdd1 = try GoldenEyeSourceFrontendMatricesV6.make(
            input: input(screen: 1, nativeTick: 5, sourceTimer: 1, pairPhase: 1),
            modelMatrixHandle: nintendoHandle
        )
        expect(
            values(nintendoEven0, handle: nintendoHandle),
            [
                229, 0, 1179, 0,
                0, 1201, 0, 0,
                -1179, 0, 229, 0,
                0, 0, -262_144_000, 65_536,
            ],
            "Nintendo even zero"
        )
        expect(
            values(nintendoOdd0, handle: nintendoHandle),
            [
                249, 0, 1224, 0,
                0, 1249, 0, 0,
                -1224, 0, 249, 0,
                0, 0, -262_144_000, 65_536,
            ],
            "Nintendo odd zero"
        )
        expect(
            values(nintendoEven1, handle: nintendoHandle),
            [
                269, 0, 1268, 0,
                0, 1297, 0, 0,
                -1268, 0, 269, 0,
                0, 0, -262_144_000, 65_536,
            ],
            "Nintendo even one"
        )
        expect(
            values(nintendoOdd1, handle: nintendoHandle),
            [
                291, 0, 1317, 0,
                0, 1349, 0, 0,
                -1317, 0, 291, 0,
                0, 0, -262_144_000, 65_536,
            ],
            "Nintendo odd one"
        )
        precondition(nintendoEven0.matrixHash == 16_129_196_459_737_930_212)
        precondition(nintendoOdd0.matrixHash == 11_168_903_349_565_104_398)
        precondition(nintendoEven1.matrixHash == 4_371_597_468_097_681_693)
        precondition(nintendoOdd1.matrixHash == 1_033_693_300_813_582_839)
        precondition(nintendoEven0.matrixHash != nintendoOdd0.matrixHash)
        precondition(nintendoEven1.matrixHash != nintendoOdd1.matrixHash)
        precondition(nintendoEven0.resources.viewports == nintendoOdd0.resources.viewports)

        let goldenEye = try GoldenEyeSourceFrontendMatricesV6.make(
            input: input(screen: 4, nativeTick: 2, sourceTimer: 0, pairPhase: 0),
            modelMatrixHandle: goldenEyeHandle
        )
        expect(
            values(goldenEye, handle: goldenEyeHandle),
            [
                78_643, 0, 0, 0,
                0, 78_643, 0, 0,
                0, 0, 78_643, 0,
                0, 0, -196_608_000, 65_536,
            ],
            "GoldenEye model scale"
        )
        precondition(goldenEye.reflectionRightQ7 == SIMD4<Int32>(127, 0, 0, 0))
        precondition(goldenEye.reflectionUpQ7 == SIMD4<Int32>(0, 127, 0, 0))
        expect(
            values(goldenEye, handle: goldenEye.reflectionMatrixHandle),
            [
                65_536, 0, 0, 0,
                0, 65_536, 0, 0,
                0, 0, 65_536, 0,
                0, 0, -262_144_000, 65_536,
            ],
            "GoldenEye reflection camera"
        )
        precondition(goldenEye.matrixHash == 8_151_358_590_723_254_394)

        let fileSelect = try GoldenEyeSourceFrontendMatricesV6.make(
            input: input(screen: 5, nativeTick: 2, sourceTimer: 0, pairPhase: 0),
            modelMatrixHandle: walletHandle
        )
        precondition(fileSelect.modelMatrixHandles.count == 4)
        precondition(fileSelect.visibleModelMatrixHandles.count == 4)
        expect(
            values(fileSelect, handle: walletHandle),
            [
                24_248, 0, 0, 0,
                0, 24_248, 0, 0,
                0, 0, 24_248, 0,
                -58_982_400, 52_428_800, -262_144_000, 65_536,
            ],
            "File Select wallet 1"
        )
        precondition(fileSelect.matrixHash == 15_911_625_537_206_804_428)

        let modeSelect = try GoldenEyeSourceFrontendMatricesV6.make(
            input: input(screen: 6, nativeTick: 2, sourceTimer: 0, pairPhase: 0),
            modelMatrixHandle: walletHandle
        )
        precondition(modeSelect.modelMatrixHandles == [walletHandle])
        precondition(modeSelect.visibleModelMatrixHandles == [walletHandle])
        precondition(modeSelect.resources.matrices.count == 4)
        expect(
            values(modeSelect, handle: walletHandle),
            [
                16_384, 0, 0, 0,
                0, 16_384, 0, 0,
                0, 0, 16_384, 0,
                0, -12_451_840, -45_875_200, 65_536,
            ],
            "Mode Select wallet"
        )
        precondition(modeSelect.matrixHash == 11_034_703_662_483_808_396)

        let modeFolderCheckpoints: [(UInt32, UInt64, [Int32])] = [
            (0, 11_034_703_662_483_808_396, [58_982_400, -64_880_640, -45_875_200]),
            (1, 13_488_826_016_981_907_988, [-117_964_800, -64_880_640, -45_875_200]),
            (2, 5_284_471_920_289_925_788, [117_964_800, 655_360, -45_875_200]),
            (3, 13_373_700_869_892_673_116, [-58_982_400, 655_360, -45_875_200]),
        ]
        for (folder, expectedHash, translation) in modeFolderCheckpoints {
            let selected = try GoldenEyeSourceFrontendMatricesV6.make(
                input: input(screen: 6, nativeTick: 2, sourceTimer: 0, pairPhase: 0),
                modelMatrixHandle: walletHandle,
                selectedFolder: folder
            )
            precondition(selected.matrixHash == expectedHash)
            precondition(selected.modelMatrixHandles == [walletHandle])
            precondition(selected.visibleModelMatrixHandles == [walletHandle])
            let camera = selected.resources.matrices[1].values
            precondition(Array(camera[12...14]) == translation)
        }

        do {
            _ = try GoldenEyeSourceFrontendMatricesV6.make(
                input: input(screen: 6, nativeTick: 2, sourceTimer: 0, pairPhase: 0),
                modelMatrixHandle: walletHandle,
                selectedFolder: 4
            )
            preconditionFailure("invalid selected folder must fail closed")
        } catch let error as GoldenEyeSourceFrontendMatricesV6Error {
            guard case .invalidSelection(4) = error else { throw error }
        }

        let rareware = try GoldenEyeSourceFrontendMatricesV6.make(
            input: input(screen: 2, nativeTick: 2, sourceTimer: 0, pairPhase: 0),
            modelMatrixHandle: 0xF300_0001
        )
        precondition(rareware.modelMatrixHandles == [0xF300_0001])
        precondition(rareware.visibleModelMatrixHandles == [0xF300_0001])
        precondition(rareware.projectionMatrixQ16[0] != 0)
        precondition(rareware.input.screen == 2)

        print("goldeneye_source_frontend_matrices_v6_smoke: PASS")
    }
}
