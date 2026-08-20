import Foundation

private let root = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first
        ?? "build/native/source-frontend-v6",
    isDirectory: true
)

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("goldeneye_wallet_switch_text_v6_smoke: FAIL " + message + "\n", stderr)
        exit(1)
    }
}

@main
struct GoldenEyeWalletSwitchTextV6Smoke {
    static func main() throws {
        let model = try GoldenEyeSourceModelV6.load(
            data: Data(contentsOf: root.appendingPathComponent("walletbond.gesm")),
            modelName: "walletbond"
        )
        try GoldenEyeWalletSwitchTextResolverV6.validate(model: model)

        let blank = try GoldenEyeWalletSwitchTextResolverV6.resolve(
            route: .fileSelect,
            folders: (0..<4).map {
                GoldenEyeWalletFolderProgressV6(number: UInt32($0), isReset: true, hasCompletion: false)
            }
        )
        let expectedFileSwitches: Set<GoldenEyeWalletSwitchNameV6> = [
            .brosnan, .brosnanCover, .cover, .photoCover
        ]
        require(Set(blank.visibleSwitchNames) == expectedFileSwitches, "blank File Select switch visibility")
        require(blank.textRows.map(\.sourceText) == ["Copy\n", "Erase\n"], "blank File Select source text")
        require(blank.switchInputs.count == 42, "all model switches have copied values")

        let partial = try GoldenEyeWalletSwitchTextResolverV6.resolve(
            route: .fileSelect,
            folders: [
                GoldenEyeWalletFolderProgressV6(number: 0, isReset: false, hasCompletion: true, highestStage: 2, highestDifficulty: 1)
            ],
            selectedFolder: 0
        )
        let partialRows = partial.textRows.filter { $0.folder == 0 }
        require(partialRows.count == 2, "partial folder has difficulty and mission rows")
        require(partialRows[0].sourceText == "Secret Agent\n", "partial difficulty source text")
        require(partialRows[1].sourceText == "Mission 1.iii\n", "source-built mission text")
        require(partialRows[1].segments.map(\.literal) == ["", "1", ".", "iii", "\n"], "mission components remain ordered")
        require(partialRows[1].centered && partialRows[1].anchorX == 76, "mission row is centered as one measured string")

        let full = try GoldenEyeWalletSwitchTextResolverV6.resolve(
            route: .fileSelect,
            folders: (0..<4).map {
                GoldenEyeWalletFolderProgressV6(number: UInt32($0), isReset: false, hasCompletion: true, highestStage: 19, highestDifficulty: 3)
            },
            selectedFolder: 3,
            selectedBond: 3
        )
        require(full.textRows.filter { $0.kind == .folderDifficulty }.count == 4, "full save difficulty rows")
        require(full.textRows.filter { $0.kind == .folderMission }.isEmpty, "007 source route omits mission row")
        require(full.visibleSwitchNames == blank.visibleSwitchNames, "US source always uses Brosnan wallet art")

        let cancelDialog = try GoldenEyeWalletSwitchTextResolverV6.resolve(
            route: .fileSelect,
            folders: [GoldenEyeWalletFolderProgressV6(number: 2, isReset: false, hasCompletion: true, highestStage: 0, highestDifficulty: 0)],
            selectedFolder: 2,
            eraseConfirmation: true,
            eraseChoice: 1
        )
        let dialog = cancelDialog.textRows.filter {
            $0.kind == .eraseTitle || $0.kind == .eraseCancel || $0.kind == .eraseConfirm
        }
        require(dialog.count == 3, "erase dialog rows")
        require(dialog[1].sourceText == "cancel\n" && dialog[2].sourceText == "confirm\n", "erase dialog source text")
        require(dialog[1].colorRGBA == 0xFFFF_FFFF && dialog[2].colorRGBA == 0xEBD8_79FF, "Cancel is source default")

        let solo = try GoldenEyeWalletSwitchTextResolverV6.resolve(
            route: .modeSelect,
            selectedFolder: 0,
            modeSelection: 0,
            controllerCount: 1
        )
        let expectedModeSwitches: Set<GoldenEyeWalletSwitchNameV6> = [
            .tabs, .paper, .ohmss, .photoBond, .eyesOnly, .brosnan, .brosnanCover
        ]
        require(Set(solo.visibleSwitchNames) == expectedModeSwitches, "solo Mode Select switch visibility")
        require(solo.textRows.count == 5, "solo Mode Select text rows")
        require(solo.textRows[3].colorRGBA == 0x7070_70FF, "solo multiplayer row is controller-gated")
        require(solo.textRows[4].vertical && solo.textRows[4].sourceText == "PREVIOUS\n", "previous tab text")

        let multiplayer = try GoldenEyeWalletSwitchTextResolverV6.resolve(
            route: .modeSelect,
            selectedFolder: 0,
            modeSelection: 1,
            controllerCount: 2
        )
        require(multiplayer.textRows[3].colorRGBA == 0xFFFF_FFFF, "multiplayer row enabled with two controllers")
        require(multiplayer.semanticHash != solo.semanticHash, "route state participates in deterministic hash")

        do {
            _ = try GoldenEyeWalletSwitchTextResolverV6.resolve(route: .fileSelect, selectedFolder: 4)
            require(false, "invalid folder must fail closed")
        } catch GoldenEyeWalletSwitchTextResolverV6Error.invalidFolder(4) {
            // expected
        }
        do {
            _ = try GoldenEyeWalletSwitchTextResolverV6.resolve(
                route: .fileSelect,
                folders: [GoldenEyeWalletFolderProgressV6(number: 0, isReset: false, hasCompletion: true, highestStage: 20, highestDifficulty: 0)]
            )
            require(false, "invalid stage must fail closed")
        } catch GoldenEyeWalletSwitchTextResolverV6Error.invalidStage(20) {
            // expected
        }

        print("wallet-switches=42 source-order=43 branch-manifest=PASS")
        print("file=blank partial full copy-erase-text=PASS")
        print("mode=solo multiplayer controller-gate=PASS")
        print("semantic-hash=\(String(multiplayer.semanticHash))")
        print("goldeneye_wallet_switch_text_v6_smoke: PASS")
    }
}
