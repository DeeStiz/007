import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Copied, renderer-facing File/Mode state.  The source authority remains the
/// owner of cursor transitions and save mutations; this record only derives
/// the immutable visual inputs required by the 2D packet.
public struct GoldenEyeSource2DFileModeViewV6: Sendable, Equatable {
    public struct Folder: Sendable, Equatable {
        public let number: UInt32
        public let isReset: Bool
        public let hasCompletion: Bool
        public let highestStage: Int32
        public let highestDifficulty: Int32
        public let selectedBond: UInt32

        public var isUsable: Bool { !isReset && number < 4 && selectedBond < 4 }

        fileprivate init(number: UInt32, save: GoldenEyeSaveFolder) {
            self.number = number
            isReset = save.isReset
            selectedBond = UInt32(save.selectedBond)
            var highestStage: Int32 = -1
            var highestDifficulty: Int32 = -1
            // fileGetHighestStageDifficultyCompletedForFolder scans 007 down
            // to Agent, then Egypt down to Dam.  The packed 10-bit stage
            // times are decoded with the same MSB-first bit ordering used by
            // fileGetSaveStageDifficultyTime in src/game/file2.c.
            for difficulty in stride(from: 3, through: 0, by: -1) {
                for stage in stride(from: 19, through: 0, by: -1) {
                    if Self.stageTime(save: save, stage: stage, difficulty: difficulty) != 0 {
                        highestStage = Int32(stage)
                        highestDifficulty = Int32(difficulty)
                        break
                    }
                }
                if highestStage >= 0 { break }
            }
            self.highestStage = highestStage
            self.highestDifficulty = highestDifficulty
            hasCompletion = highestStage >= 0
        }

        private static func stageTime(
            save: GoldenEyeSaveFolder,
            stage: Int,
            difficulty: Int
        ) -> UInt32 {
            let bitOffset = (difficulty * 20 + stage) * 10
            let bytes = save.stageTimeBytes()
            guard bitOffset >= 0, bitOffset + 10 <= bytes.count * 8 else { return 0 }
            var result: UInt32 = 0
            for bit in 0..<10 {
                let absolute = bitOffset + bit
                let byte = bytes[absolute >> 3]
                let shift = 7 - (absolute & 7)
                result = (result << 1) | UInt32((byte >> shift) & 1)
            }
            // Difficulty 007 is represented by the source flag or by all
            // 00-Agent stages being complete.  The latter is checked here so
            // the visual packet agrees with fileIs007ModeUnlocked().
            if difficulty == 3 {
                let explicit = save.flag007 & 1 != 0
                let all00 = (0..<20).allSatisfy {
                    stageTime(save: save, stage: $0, difficulty: 2) != 0
                }
                return explicit || all00 ? 0x3ff : 0
            }
            return result
        }
    }

    public let frame: GoldenEyeFileModeFrameV6
    public let folders: [Folder]
    public let visualInput: GoldenEyeWalletVisualInputPacketV6

    public init(
        frame: GoldenEyeFileModeFrameV6,
        saveState: GoldenEyeSaveState
    ) throws {
        guard saveState.folders.count == 4 else {
            throw GoldenEyeSource2DError.malformedPayload("File/Mode folder count")
        }
        self.frame = frame
        self.folders = saveState.folders.enumerated().map {
            Folder(number: UInt32($0.offset), save: $0.element)
        }
        let progress = folders.map {
            GoldenEyeWalletFolderProgressV6(
                number: $0.number,
                isReset: $0.isReset,
                hasCompletion: $0.hasCompletion,
                highestStage: $0.highestStage,
                highestDifficulty: $0.highestDifficulty
            )
        }
        let route: GoldenEyeWalletRouteV6 = frame.state.screen == GE_FILE_MODE_V6_SCREEN_MODE_SELECT.rawValue
            ? .modeSelect
            : .fileSelect
        visualInput = try GoldenEyeWalletSwitchTextResolverV6.resolve(
            route: route,
            folders: progress,
            selectedFolder: frame.state.selectedFolder,
            selectedBond: UInt32(saveState.selectedBond),
            modeSelection: frame.state.modeSelection,
            controllerCount: frame.state.controllerCount,
            eraseConfirmation: frame.state.flags & GE_FILE_MODE_V6_STATE_FLAG_ERASE_CONFIRM != 0,
            eraseChoice: frame.state.eraseChoice
        )
    }
}

/// Source menu text and cursor lowering.  This extension keeps the base
/// Legal/Nintendo packet independent of SaveStore while allowing the product
/// path to carry the exact four-folder semantic projection.
public extension GoldenEyeSource2DLowererV6 {
    /// The folder/menu background is source work that must run before wallet
    /// geometry. Its texture rect intentionally extends left by 28 source
    /// units, leaving the authored black right border on the 440-unit canvas.
    func makeFileModeBackgroundFrame(
        nativeTick: UInt64,
        sourceTimer: UInt32
    ) -> GoldenEyeSource2DFrameV6 {
        let clip = GoldenEyeSource2DScissorV6()
        var rows: [GoldenEyeSource2DTextureRectV6] = []
        rows.reserveCapacity(Int(GoldenEyeFileModeBackgroundContractV6.height))
        // title2.c passes S=(-xOffset)<<5 for a negative canvas offset.  The
        // prepared resource retains the complete 440-column source image, so
        // express that same starting texel as a normalized U range instead
        // of sampling the discarded left 28 columns a second time.
        let sourceU0 = UInt32(
            (Int(-GoldenEyeFileModeBackgroundContractV6.xOffset) * 65_536)
                / Int(GoldenEyeFileModeBackgroundContractV6.width)
        )
        for row in 0..<Int(GoldenEyeFileModeBackgroundContractV6.height) {
            // Preserve title2.c's one-row texture-rectangle ordering. The
            // texel-center V keeps a row sample exact when the complete
            // source image is represented as one persistent texture.
            let v = UInt32(
                (row * 65_536 + 32_768)
                    / Int(GoldenEyeFileModeBackgroundContractV6.height)
            )
            rows.append(.init(
                resourceRecordID: assets.fileModeBackground.sourceRecordID,
                rect: .init(x: GoldenEyeFileModeBackgroundContractV6.xOffset,
                             y: GoldenEyeFileModeBackgroundContractV6.yOrigin + Int32(row),
                             width: UInt32(GoldenEyeFileModeBackgroundContractV6.width),
                             height: 1),
                scissor: clip,
                u0Q16: sourceU0, v0Q16: v, u1Q16: 65_536, v1Q16: v,
                tintRGBA: 0xFFFF_FFFF,
                flags: 0,
                sequence: UInt64(row)
            ))
        }
        return makeFrame(
            screen: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT),
            nativeTick: nativeTick,
            sourceTimer: sourceTimer,
            scissor: clip,
            fills: [],
            textureRects: rows,
            glyphs: [],
            unsupported: 0
        )
    }

    func makeFileSelectFrame(
        nativeTick: UInt64,
        sourceTimer: UInt32,
        menu: GoldenEyeSource2DFileModeViewV6,
        fadeAlpha: UInt8 = 255
    ) throws -> GoldenEyeSource2DFrameV6 {
        let clip = GoldenEyeSource2DScissorV6()
        var fills: [GoldenEyeSource2DFillV6] = [
            .init(rect: .sourceCanvas, scissor: clip, rgba: 0x000000FF, flags: 0, sequence: 0)
        ]
        var textures: [GoldenEyeSource2DTextureRectV6] = []
        // The source constructor centers these exact payloads at (110,285),
        // (225,285), and (335,285).
        try appendIcon(.selectFile, rect: .init(x: 49, y: 276, width: 122, height: 18), scissor: clip, sequence: 10, into: &textures)
        try appendIcon(.copy, rect: .init(x: 209, y: 271, width: 32, height: 28), scissor: clip, sequence: 11, into: &textures)
        try appendIcon(.erase, rect: .init(x: 319, y: 271, width: 32, height: 28), scissor: clip, sequence: 12, into: &textures)

        var glyphs: [GoldenEyeSource2DGlyphV6] = []
        for row in menu.visualInput.textRows {
            try appendResolvedTextRow(row, scissor: clip, into: &glyphs)
        }

        let state = menu.frame.state
        let cursor = SIMD2<Int32>(
            Int32((state.cursorXQ16 + 32_768) / 65_536),
            Int32((state.cursorYQ16 + 32_768) / 65_536)
        )
        let cursorIcon: GoldenEyeSource2DIconIDV6 = switch state.fileOption {
        case GE_FILE_MODE_V6_OPTION_COPY.rawValue: .copy
        case GE_FILE_MODE_V6_OPTION_ERASE.rawValue: .erase
        default: .crosshair
        }
        let cursorPixels = try assets.icon(cursorIcon)
        let cursorWidth = cursorPixels.width
        let cursorHeight = cursorPixels.height
        textures.append(.init(
            resourceRecordID: cursorPixels.sourceRecordID,
            rect: .init(x: cursor.x - Int32(cursorWidth / 2), y: cursor.y - Int32(cursorHeight / 2), width: cursorWidth, height: cursorHeight),
            scissor: clip, u0Q16: 0, v0Q16: 0, u1Q16: 65_536, v1Q16: 65_536,
            tintRGBA: 0xFFFFFFDC, flags: 1, sequence: 300
        ))

        if state.flags & GE_FILE_MODE_V6_STATE_FLAG_ERASE_CONFIRM != 0 {
            let folder = min(state.selectedFolder, 3)
            let center = GoldenEyeWalletSwitchTextResolverV6.sourceCanvasFolderCenters[Int(folder)]
            fills.append(.init(
                rect: .init(x: center - 49, y: 132, width: 99, height: 42),
                scissor: clip, rgba: 0xFFFFFF32, flags: 2, sequence: 301
            ))
        }
        if fadeAlpha < 255 {
            fills.append(.init(rect: .sourceCanvas, scissor: clip, rgba: UInt32(255 - fadeAlpha), flags: 1, sequence: nativeTick))
        }
        return makeFrame(screen: 5, nativeTick: nativeTick, sourceTimer: sourceTimer, scissor: clip, fills: fills, textureRects: textures, glyphs: glyphs, unsupported: 0)
    }

    func makeModeSelectFrame(
        nativeTick: UInt64,
        sourceTimer: UInt32,
        menu: GoldenEyeSource2DFileModeViewV6,
        fadeAlpha: UInt8 = 255
    ) throws -> GoldenEyeSource2DFrameV6 {
        let clip = GoldenEyeSource2DScissorV6()
        var fills: [GoldenEyeSource2DFillV6] = [
            .init(rect: .sourceCanvas, scissor: clip, rgba: 0x000000FF, flags: 0, sequence: 0)
        ]
        var glyphs: [GoldenEyeSource2DGlyphV6] = []
        let selected = min(menu.visualInput.modeSelection, 1)
        for (index, row) in menu.visualInput.textRows.enumerated() {
            if row.kind == .modeLabel, UInt32(index / 2) == selected {
                let text = try measureLiteral(row.sourceText.replacingOccurrences(of: "\n", with: ""), fontID: .zurichBold)
                fills.append(.init(rect: .init(x: 148, y: row.anchorY - 2, width: UInt32(max(175, Int(text.width) + 175)), height: 16), scissor: clip, rgba: 0x00000032, flags: 2, sequence: UInt64(index + 1)))
            }
            try appendResolvedTextRow(row, scissor: clip, into: &glyphs)
        }
        let cursorY: Int32 = selected == 0 ? 226 : 258
        let cursor = try assets.icon(.crosshair)
        fills.reserveCapacity(fills.count + 1)
        var textures: [GoldenEyeSource2DTextureRectV6] = []
        textures.append(.init(resourceRecordID: cursor.sourceRecordID, rect: .init(x: 110, y: cursorY - 16, width: 32, height: 32), scissor: clip, u0Q16: 0, v0Q16: 0, u1Q16: 65_536, v1Q16: 65_536, tintRGBA: 0xFFFFFFDC, flags: 1, sequence: 40))
        if fadeAlpha < 255 { fills.append(.init(rect: .sourceCanvas, scissor: clip, rgba: UInt32(255 - fadeAlpha), flags: 1, sequence: nativeTick)) }
        return makeFrame(screen: 6, nativeTick: nativeTick, sourceTimer: sourceTimer, scissor: clip, fills: fills, textureRects: textures, glyphs: glyphs, unsupported: 0)
    }

    private func appendResolvedTextRow(
        _ row: GoldenEyeWalletTextRowV6,
        scissor: GoldenEyeSource2DScissorV6,
        into output: inout [GoldenEyeSource2DGlyphV6]
    ) throws {
        guard let font = GoldenEyeSource2DFontIDV6(rawValue: row.fontID) else {
            throw GoldenEyeSource2DError.malformedPayload("wallet text font")
        }
        let text = row.sourceText.replacingOccurrences(of: "\n", with: "")
        guard !text.isEmpty else { return }
        let measured = try measureLiteral(text, fontID: font)
        let x = row.centered ? row.anchorX - measured.width / 2 : row.anchorX
        if row.vertical {
            try appendVerticalLiteral(text, fontID: font, x: row.anchorX, y: row.anchorY, color: row.colorRGBA, scissor: scissor, sequence: row.sequence, into: &output)
        } else {
            try appendLiteral(text, fontID: font, anchorX: x, anchorY: row.anchorY, color: row.colorRGBA, scissor: scissor, sequence: row.sequence, into: &output)
        }
    }

    private func appendVerticalLiteral(
        _ text: String,
        fontID: GoldenEyeSource2DFontIDV6,
        x: Int32,
        y: Int32,
        color: UInt32,
        scissor: GoldenEyeSource2DScissorV6,
        sequence: UInt64,
        into output: inout [GoldenEyeSource2DGlyphV6]
    ) throws {
        let font = assets.font(fontID)
        var cursorY = y
        for (index, byte) in text.utf8.enumerated() {
            guard let glyph = font.glyph(forASCII: byte), let glyphIndex = font.glyphs.firstIndex(of: glyph) else {
                throw GoldenEyeSource2DError.invalidSourceEvent("vertical wallet text byte " + String(byte))
            }
            output.append(.init(fontID: font.id, fontRecordID: font.sourceRecordID, glyphIndex: UInt32(glyphIndex), character: UInt32(byte), x: x, y: cursorY, width: UInt32(glyph.height), height: UInt32(glyph.width), baseline: glyph.baseline, scissor: scissor, rgba: color, stringID: 0x8000_0000 | UInt32(sequence & 0x7fff), flags: 2, sequence: sequence + UInt64(index)))
            cursorY += max(8, glyph.width)
        }
    }

    private func appendVerticalText(
        id: UInt32,
        fontID: GoldenEyeSource2DFontIDV6,
        x: Int32,
        y: Int32,
        color: UInt32,
        scissor: GoldenEyeSource2DScissorV6,
        sequence: UInt64,
        into output: inout [GoldenEyeSource2DGlyphV6]
    ) throws {
        let text = try assets.text(id: id)
        let font = assets.font(fontID)
        var cursorY = y
        for (index, byte) in text.utf8.enumerated() where byte != 0x0a {
            guard let glyph = font.glyph(forASCII: byte), let glyphIndex = font.glyphs.firstIndex(of: glyph) else {
                throw GoldenEyeSource2DError.invalidSourceEvent("vertical text " + String(id) + " byte " + String(byte))
            }
            output.append(.init(fontID: font.id, fontRecordID: font.sourceRecordID, glyphIndex: UInt32(glyphIndex), character: UInt32(byte), x: x, y: cursorY + glyph.baseline, width: UInt32(glyph.width), height: UInt32(glyph.height), baseline: glyph.baseline, scissor: scissor, rgba: color, stringID: id, flags: 2, sequence: sequence + UInt64(index)))
            cursorY += max(8, glyph.width)
        }
    }

    private func appendLiteral(
        _ text: String,
        fontID: GoldenEyeSource2DFontIDV6,
        anchorX: Int32,
        anchorY: Int32,
        color: UInt32,
        scissor: GoldenEyeSource2DScissorV6,
        sequence: UInt64,
        into output: inout [GoldenEyeSource2DGlyphV6]
    ) throws {
        let font = assets.font(fontID)
        var x = anchorX
        var previous = font.glyph(forASCII: Character("H").asciiValue ?? 0x48)
        for (index, byte) in text.utf8.enumerated() {
            if byte == 0x20 {
                x += 5
                previous = font.glyph(forASCII: Character("H").asciiValue ?? 0x48)
                continue
            }
            guard let glyph = font.glyph(forASCII: byte), let glyphIndex = font.glyphs.firstIndex(of: glyph) else {
                throw GoldenEyeSource2DError.invalidSourceEvent("literal byte " + String(byte))
            }
            if let previous { x -= font.kerningValue(previous: previous, current: glyph) - 1 }
            output.append(.init(fontID: font.id, fontRecordID: font.sourceRecordID, glyphIndex: UInt32(glyphIndex), character: UInt32(byte), x: x, y: anchorY + glyph.baseline, width: UInt32(glyph.width), height: UInt32(glyph.height), baseline: glyph.baseline, scissor: scissor, rgba: color, stringID: 0x8000_0000 | UInt32(sequence & 0x7fff), flags: 1, sequence: sequence + UInt64(index)))
            x += glyph.width
            previous = glyph
        }
    }

    private func measureLiteral(_ text: String, fontID: GoldenEyeSource2DFontIDV6) throws -> (width: Int32, height: Int32) {
        let font = assets.font(fontID)
        var width: Int32 = 0
        var previous = font.glyph(forASCII: Character("H").asciiValue ?? 0x48)
        var height: Int32 = 0
        for byte in text.utf8 {
            if byte == 0x20 {
                width += 5
                previous = font.glyph(forASCII: Character("H").asciiValue ?? 0x48)
                continue
            }
            guard let glyph = font.glyph(forASCII: byte) else { throw GoldenEyeSource2DError.invalidSourceEvent("literal byte " + String(byte)) }
            if let previous { width += glyph.width - (font.kerningValue(previous: previous, current: glyph) - 1) }
            else { width += glyph.width }
            height = max(height, glyph.height)
            previous = glyph
        }
        return (width, height)
    }

    private func missionText(for stage: Int) -> (chapter: UInt32, part: UInt32) {
        // IDs are the exact LtitleE.gecat rows used by mission_folder_setup_entries.
        let map: [(UInt32, UInt32)] = [
            (120, 121), (120, 122), (120, 123), (124, 125), (124, 126),
            (127, 128), (130, 131), (132, 133), (132, 135), (132, 137),
            (132, 138), (132, 139), (140, 141), (140, 142), (140, 144),
            (140, 146), (148, 149), (151, 152), (0, 0), (0, 0)
        ]
        let value = map.indices.contains(stage) ? map[stage] : (0, 0)
        return value == (0, 0) ? (120, 121) : value
    }
}
