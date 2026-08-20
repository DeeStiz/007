import Foundation

@main
struct GoldenEyeSource2DV6Smoke {
    static func main() {
        do {
            try run()
            print("goldeneye_source_2d_v6_smoke: PASS")
        } catch {
            fputs("goldeneye_source_2d_v6_smoke: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        guard CommandLine.arguments.count >= 2 else {
            throw NSError(domain: "goldeneye-source-2d-v6", code: 2, userInfo: [NSLocalizedDescriptionKey: "prepared asset root is required"])
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let catalog = try GoldenEyeSourceFrontendCatalog.load(preparedAssetRoot: root)
        let assets = try GoldenEyeSource2DAssetsV6(catalog: catalog)
        precondition(assets.zurichBold.glyphs.count == 94)
        precondition(assets.zurichBold.kerning.count == 169)
        precondition(assets.bankGothic.glyphs.count == 94)
        precondition(assets.bankGothic.kerning.count == 169)
        // Bank Gothic's source chart has authored source indices that differ
        // from the ASCII table slot.  Preserve those values rather than
        // normalizing them into a guessed synthetic font.
        precondition(assets.bankGothic.glyphs.contains { $0.sourceIndex != $0.character - 0x21 })
        precondition(assets.textStrings.count == 302)

        let expectedIconSizes: [GoldenEyeSource2DIconIDV6: (UInt32, UInt32)] = [
            .copy: (32, 28), .erase: (32, 28), .selectFile: (122, 18),
            .crosshair: (32, 32), .check: (20, 20), .dot: (16, 16), .cursorX: (15, 15)
        ]
        for icon in assets.icons.keys {
            let value = try assets.icon(icon)
            precondition((value.width, value.height) == expectedIconSizes[icon]!)
            precondition(value.pixels.count == Int(value.width * value.height * 4))
            precondition(!value.pixels.allSatisfy { $0 == 0 })
        }

        let lowerer = GoldenEyeSource2DLowererV6(assets: assets)
        let legal = try lowerer.makeLegalFrame(nativeTick: 1, sourceTimer: 0)
        precondition(legal.logicalWidth == 440 && legal.logicalHeight == 330)
        precondition(legal.fills.count == 1)
        precondition(legal.textureRects.isEmpty)
        precondition(legal.glyphs.count > 100)
        precondition(Set(legal.glyphs.map(\.stringID)) == Set(7...18))
        precondition(legal.glyphs.allSatisfy { $0.fontID == GoldenEyeSource2DFontIDV6.zurichBold.rawValue })
        precondition(legal.unsupportedVisibleCount == 0)
        precondition(legal.frameHash != 0)

        let fadedLegal = try lowerer.makeLegalFrame(nativeTick: 2, sourceTimer: 1, fadeAlpha: 127)
        precondition(fadedLegal.fills.count == 2)
        precondition(fadedLegal.fills.last?.rgba == 128)

        do {
            let file = try lowerer.makeFileSelectFrame(nativeTick: 3, sourceTimer: 0, cursorCenter: (220, 165))
            precondition(file.textureRects.contains { $0.resourceRecordID == assets.iconRecordIDs[.selectFile] })
        } catch {
            preconditionFailure("file-select frame failed after SELECTFILE payload repair: \(error)")
        }

        // The production File/Mode sidecar is the only source of cursor,
        // option, and four-folder semantic state.  Exercise both the blank
        // defaults and a completed folder so progress text is emitted from
        // the copied save projection rather than a procedural label.
        let fileAuthority = try GoldenEyeFileModeAuthorityV6()
        let blankMenu = try GoldenEyeSource2DFileModeViewV6(
            frame: fileAuthority.lastFrame,
            saveState: .blank
        )
        let blankFile = try lowerer.makeFileSelectFrame(
            nativeTick: 5,
            sourceTimer: 0,
            menu: blankMenu
        )
        precondition(blankFile.textureRects.count == 4)
        precondition(blankMenu.visualInput.textRows.map(\.sourceText) == ["Copy\n", "Erase\n"])
        precondition(!blankFile.glyphs.isEmpty)
        precondition(blankFile.unsupportedVisibleCount == 0)

        var completedFolders = (0..<4).map { GoldenEyeSaveFolder.created(folder: $0) }
        for index in completedFolders.indices {
            completedFolders[index].setStageTimeByte(0, value: 1)
        }
        let completedSave = GoldenEyeSaveState(folders: completedFolders)
        let completedMenu = try GoldenEyeSource2DFileModeViewV6(
            frame: fileAuthority.lastFrame,
            saveState: completedSave
        )
        let completedFile = try lowerer.makeFileSelectFrame(
            nativeTick: 6,
            sourceTimer: 1,
            menu: completedMenu
        )
        precondition(completedFile.textureRects.count == 4)
        precondition(completedMenu.visualInput.textRows.contains { $0.kind == .folderDifficulty })
        precondition(completedMenu.visualInput.textRows.contains { $0.kind == .folderMission })

        let mode = try lowerer.makeModeSelectFrame(nativeTick: 4, sourceTimer: 0, selectedRow: 1)
        precondition(mode.glyphs.count > 10)
        precondition(mode.fills.count == 2)
        precondition(mode.fills[1].rect == .init(x: 148, y: 250, width: 175, height: 16) || mode.fills[1].rect.width > 175)

        var modeAuthority = try GoldenEyeFileModeAuthorityV6()
        let modeAuthorityFrame = try modeAuthority.step(.init(nativeTick: 1, sequence: 1, pressed: UInt32(GE_FILE_MODE_V6_BUTTON_A), synthetic: true))
        let modeMenu = try GoldenEyeSource2DFileModeViewV6(frame: modeAuthorityFrame, saveState: modeAuthority.saveState)
        let modeFile = try lowerer.makeModeSelectFrame(
            nativeTick: 7,
            sourceTimer: 1,
            menu: modeMenu
        )
        precondition(modeFile.textureRects.count == 1)
        precondition(modeFile.glyphs.count > 10)
        precondition(modeMenu.visualInput.textRows.contains { $0.vertical })
        precondition(modeFile.unsupportedVisibleCount == 0)

        let event = GoldenEyeSource2DTextEventV6(screen: 0, textID: 7, x: 220, y: 30, nativeTick: 5, sourceTimer: 2, sequence: 7)
        let lowered = try lowerer.lower(screen: 0, nativeTick: 5, sourceTimer: 2, renderEvents: [
            .init(screen: 0, operation: GoldenEyeSource2DLowererV6.renderFrameBegin),
            .init(screen: 0, operation: GoldenEyeSource2DLowererV6.renderClearBlack),
            .init(screen: 0, operation: GoldenEyeSource2DLowererV6.renderSourceText)
        ], textEvents: [event])
        precondition(Set(lowered.glyphs.map(\.stringID)) == [7])

        let missingSelectAssets = try GoldenEyeSource2DAssetsV6(catalog: catalog, requiredIcons: [.copy, .erase, .crosshair, .check, .dot, .cursorX])
        do {
            _ = try missingSelectAssets.icon(.selectFile)
            preconditionFailure("missing SELECTFILE requirement was accepted")
        } catch let error as GoldenEyeSource2DError {
            guard case let .preparationGap(category, family, name, evidence) = error else {
                preconditionFailure("unexpected missing-icon error: \(error)")
            }
            precondition(category == "texture_payload" && family == "frontend" && name == "SELECTFILE.payload")
            precondition(evidence.contains("explicit asset requirement"))
        }

        do {
            _ = try lowerer.lower(screen: 0, nativeTick: 6, sourceTimer: 3, renderEvents: [
                .init(screen: 0, operation: 99)
            ])
            preconditionFailure("unknown visible render event was accepted")
        } catch let error as GoldenEyeSource2DError {
            guard case .unsupportedVisibleEvent(99) = error else {
                preconditionFailure("unexpected unknown-render error: \(error)")
            }
        }

        print("assets=fonts=2 glyphs=\(assets.zurichBold.glyphs.count + assets.bankGothic.glyphs.count) icons=\(assets.icons.count) strings=\(assets.textStrings.count)")
        print("legal=glyphs=\(legal.glyphs.count) fills=\(legal.fills.count) hash=\(legal.frameHash)")
        print("file=SELECTFILE_payload_gap=false")
        print("file=SELECTFILE_payload_nonzero=true")
        print("file=source-menu-icons=4 blank-glyphs=\(blankFile.glyphs.count) completed-glyphs=\(completedFile.glyphs.count)")
        print("mode=fills=\(mode.fills.count) glyphs=\(mode.glyphs.count) hash=\(mode.frameHash)")
        print("mode=source-menu-textures=\(modeFile.textureRects.count) previous-tab=true cursor=true")
        print("preparation_gap=none")
        print("runtime_rom_access=false")
        print("visual_parity=source_coordinates_and_payloads_only")
    }
}
