import Foundation

private let root = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first
        ?? "build/native/source-frontend-v6",
    isDirectory: true
)

private func require(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else {
        FileHandle.standardError.write(Data("goldeneye_file_mode_reference_capture_v6_smoke: FAIL \(message)\n".utf8))
        preconditionFailure(message)
    }
}

@main
struct GoldenEyeFileModeReferenceCaptureV6Smoke {
    static func main() throws {
        let catalog = try GoldenEyeSourceFrontendCatalog.load(preparedAssetRoot: root)
        let backgroundRecord = try catalog.record(kind: .background, name: "gunbarrel-background", family: "gunbarrel")
        let background = try GoldenEyeFileModeBackgroundContractV6(encoded: catalog.copyOut(.decoded, for: backgroundRecord))
        require(background.rowCount == 299 && background.sourceColumn(forCanvasColumn: 0) == 28 && background.sourceColumn(forCanvasColumn: 412) == nil, "File/Mode source background contract")
        let assets = try GoldenEyeSource2DAssetsV6(catalog: catalog)
        let lowerer = GoldenEyeSource2DLowererV6(assets: assets)
        let model = try GoldenEyeSourceModelV6.load(
            data: Data(contentsOf: root.appendingPathComponent("walletbond.gesm")),
            modelName: "walletbond"
        )
        let expectedWalletPayloads: Set<String> = [
            "FOLDERTEX.payload", "PAPERTEX.payload", "MI6.payload",
            "MI6_UL.payload", "MI6_UR.payload", "MI6_LL.payload", "MI6_LR.payload",
            "BROSNAN_UL.payload", "BROSNAN_UR.payload", "BROSNAN_LL.payload", "BROSNAN_LR.payload"
        ]
        let linkedWalletPayloads = Set(model.textures.compactMap { catalog.record(id: $0.payloadRecordID)?.name })
        require(expectedWalletPayloads.isSubset(of: linkedWalletPayloads), "Wallet cover/photo/MI6 source payload linkage")

        // Preserve the guarded Wallet source inventory and validate every
        // independently reachable SWITCH branch against its exact GESM route.
        let counts = model.header.counts
        require(counts.nodes == 90 && counts.scalars == 90 && counts.displayLists == 46, "Wallet graph counts")
        require(counts.commands == 982 && counts.vertices == 765 && counts.textures == 84, "Wallet command/texture counts")
        require(counts.mips == 186 && counts.tluts == 2, "Wallet mip/TLUT counts")
        let switchOpcode: UInt32 = 0x258d_b802
        let switches = model.nodes.filter { $0.opcodeHandle == switchOpcode }
        let report = try String(
            contentsOf: root.appendingPathComponent("source-frontend-v6-report.txt"),
            encoding: .utf8
        )
        require(report.contains("walletbond_switch_records=43"), "Wallet SwitchNodes[43] preparation evidence")
        require(switches.count == 42, "Wallet switch-node count")
        let defaults = Dictionary(uniqueKeysWithValues: switches.map { ($0.id, UInt32(0)) })
        let base = GESourceModelCompilerV6.compile(
            model, modelName: "walletbond", switchInputs: defaults
        )
        require(base.status == .complete && base.diagnostics.isEmpty, "Wallet default route")
        require(base.scene?.commands.count == 390, "Wallet default selected command count")
        let setup = try GoldenEyeSourceTextureSetupResolverV6.resolve(
            modelName: "walletbond",
            model: model,
            catalog: catalog,
            compiledCommands: base.scene!.commands
        )
        require(setup.setups.count == 41, "Wallet typed texture setup count")
        require(setup.aliases.count == 19, "Wallet typed texture alias count")
        require(setup.setups.contains { $0.palette != nil }, "Wallet TLUT setup identity")
        var branchRoutes = 0
        for node in switches {
            guard node.scalarStart < UInt32(model.scalars.count) else {
                preconditionFailure("Wallet switch " + String(node.id) + " has no scalar metadata")
            }
            let metadata = model.scalars[Int(node.scalarStart)].metadata
            require(metadata.count > 1 && metadata[1] > 0 && metadata[1] <= 32, "Wallet switch " + String(node.id) + " branch metadata")
            for selection in 0..<metadata[1] {
                var route = defaults
                route[node.id] = selection
                let compilation = GESourceModelCompilerV6.compile(
                    model, modelName: "walletbond", switchInputs: route
                )
                require(compilation.status == .complete, "Wallet switch " + String(node.id) + " route " + String(selection) + " status")
                require(compilation.diagnostics.isEmpty, "Wallet switch " + String(node.id) + " route " + String(selection) + " diagnostics")
                require(compilation.scene?.unsupportedCount == 0, "Wallet switch " + String(node.id) + " route " + String(selection) + " unsupported")
                require(compilation.scene?.commands.isEmpty == false, "Wallet switch " + String(node.id) + " route " + String(selection) + " empty")
                branchRoutes += 1
            }
        }

        // Build source 2D key states from the same copied semantic save used
        // by production.  No folder shape, label, or cursor is synthesized.
        let authority = try GoldenEyeFileModeAuthorityV6()
        let blank = try GoldenEyeSource2DFileModeViewV6(
            frame: authority.lastFrame,
            saveState: .blank
        )
        let blankFile = try lowerer.makeFileSelectFrame(nativeTick: 2, sourceTimer: 0, menu: blank)
        require(blankFile.textureRects.count == 4, "blank File Select icon/cursor packet")
        require(blank.visualInput.textRows.map(\.sourceText) == ["Copy\n", "Erase\n"], "File Select option labels")

        var completedFolders = (0..<4).map { GoldenEyeSaveFolder.created(folder: $0) }
        for index in completedFolders.indices {
            completedFolders[index].setStageTimeByte(index, value: 1)
        }
        let completed = GoldenEyeSaveState(folders: completedFolders, selectedFolder: 3)
        let completedView = try GoldenEyeSource2DFileModeViewV6(
            frame: authority.lastFrame,
            saveState: completed
        )
        let completedFile = try lowerer.makeFileSelectFrame(nativeTick: 4, sourceTimer: 1, menu: completedView)
        require(completedFile.textureRects.count == 4, "completed File Select icon/cursor packet")
        require(completedView.visualInput.textRows.contains { $0.kind == .folderDifficulty }, "difficulty progress text")
        require(completedView.visualInput.textRows.contains { $0.kind == .folderMission }, "mission progress text")

        var eraseAuthority = try GoldenEyeFileModeAuthorityV6(saveState: completed)
        var eraseTick: UInt64 = 0
        for _ in 0..<21 {
            eraseTick += 1
            _ = try eraseAuthority.step(.init(nativeTick: eraseTick, sequence: eraseTick, stickX: 75, stickY: 75, synthetic: true))
        }
        eraseTick += 1
        _ = try eraseAuthority.step(.init(nativeTick: eraseTick, sequence: eraseTick, pressed: UInt32(GE_FILE_MODE_V6_BUTTON_A), synthetic: true))
        // Return the cursor to wallet 0 while the erase option is armed.
        for index in 0..<46 {
            eraseTick += 1
            _ = try eraseAuthority.step(.init(nativeTick: eraseTick, sequence: eraseTick, stickX: -75, stickY: index < 20 ? -75 : 0, synthetic: true))
        }
        eraseTick += 1
        let eraseDialogAuthorityFrame = try eraseAuthority.step(.init(nativeTick: eraseTick, sequence: eraseTick, pressed: UInt32(GE_FILE_MODE_V6_BUTTON_A), synthetic: true))
        let eraseDialogView = try GoldenEyeSource2DFileModeViewV6(frame: eraseDialogAuthorityFrame, saveState: eraseAuthority.saveState)
        let eraseDialog = try lowerer.makeFileSelectFrame(nativeTick: eraseTick, sourceTimer: 2, menu: eraseDialogView)
        require(eraseDialog.fills.count == 2, "erase confirmation overlay")
        require(eraseDialogView.visualInput.textRows.contains { $0.kind == .eraseTitle } && eraseDialogView.visualInput.textRows.contains { $0.kind == .eraseCancel } && eraseDialogView.visualInput.textRows.contains { $0.kind == .eraseConfirm }, "erase confirmation text")

        var modeAuthority = try GoldenEyeFileModeAuthorityV6(saveState: completed)
        let modeAuthorityFrame = try modeAuthority.step(.init(nativeTick: 1, sequence: 1, pressed: UInt32(GE_FILE_MODE_V6_BUTTON_A), synthetic: true))
        let modeView = try GoldenEyeSource2DFileModeViewV6(frame: modeAuthorityFrame, saveState: modeAuthority.saveState)
        let mode = try lowerer.makeModeSelectFrame(nativeTick: 6, sourceTimer: 2, menu: modeView)
        require(mode.textureRects.count == 1, "Mode Select cursor packet")
        require(modeView.visualInput.textRows.contains { $0.sourceText == "PREVIOUS\n" && $0.vertical }, "Mode Select previous tab")
        require(modeView.visualInput.textRows.contains { $0.sourceText == "1.\n" }, "Mode Select row 1")
        require(modeView.visualInput.textRows.contains { $0.sourceText == "2.\n" && $0.colorRGBA == 0x707070FF }, "Mode Select controller-gated row color")
        require(mode.unsupportedVisibleCount == 0, "Mode Select unsupported visible work")
        var routeAuthority = try GoldenEyeFileModeAuthorityV6(saveState: completed)
        let routedMode = try routeAuthority.step(.init(nativeTick: 1, sequence: 1, pressed: UInt32(GE_FILE_MODE_V6_BUTTON_A), controllerCount: 2, synthetic: true))
        require(routedMode.state.screen == GE_FILE_MODE_V6_SCREEN_MODE_SELECT.rawValue, "File Select to Mode Select route")
        let routedView = try GoldenEyeSource2DFileModeViewV6(frame: routedMode, saveState: routeAuthority.saveState)
        let routedModeFrame = try lowerer.makeModeSelectFrame(nativeTick: 8, sourceTimer: 3, menu: routedView)
        require(routedModeFrame.textureRects.count == 1 && routedView.visualInput.textRows.contains { $0.kind == .previousTab && $0.vertical }, "routed Mode Select packet")

        // The source canvas and reference target are exact; Faithful HD is
        // checked through the same layout contract used by the renderer.
        let referenceLayout = GoldenEyeFidelityLayout(mode: .reference320x240, drawableWidth: 320, drawableHeight: 240)
        require(referenceLayout.sourceToOutputRect(.init(minX: 0, minY: 0, maxX: 440, maxY: 330)).maxX == 320, "Reference 320x240 width")
        require(referenceLayout.sourceToOutputRect(.init(minX: 0, minY: 0, maxX: 440, maxY: 330)).maxY == 240, "Reference 320x240 height")
        let hdLayout = GoldenEyeFidelityLayout(mode: .faithfulHD, drawableWidth: 1760, drawableHeight: 1320)
        require(hdLayout.sourceToOutputRect(.init(minX: 0, minY: 0, maxX: 440, maxY: 330)).maxX == 1760, "Faithful HD width")
        require(hdLayout.sourceToOutputRect(.init(minX: 0, minY: 0, maxX: 440, maxY: 330)).maxY == 1320, "Faithful HD height")

        print("wallet=nodes=90 switch-nodes=42 switch-records=43 commands=982 vertices=765 textures=84 mips=186 tluts=2")
        print("wallet=default-visible-commands=390 metadata-authorized-branch-routes=\(branchRoutes)")
        print("file=blank-textures=\(blankFile.textureRects.count) completed-glyphs=\(completedFile.glyphs.count)")
        print("file=erase-dialog=true")
        print("mode=rows=true previous-tab=true cursor=true")
        print("reference=320x240 faithful-hd=1760x1320 unsupported=0")
        print("capture=GPU deferred-until-Metal4-scene-composer")
        print("goldeneye_file_mode_reference_capture_v6_smoke: PASS")
    }
}
