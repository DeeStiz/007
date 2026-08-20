import Foundation

/// The source model's SwitchNodes[] order is part of the walletbond binary
/// contract.  These are the names used by WalletBond_SwitchNames in the
/// original frontend, paired with the GESM node id produced from Model.c.
/// Values in `switchInputs` are source visibility booleans (0/1), not
/// renderer guesses or texture/material selections.
public enum GoldenEyeWalletSwitchNameV6: UInt32, CaseIterable, Sendable {
    case tabs = 0
    case paper = 1
    case eyesOnly = 2
    case ohmss = 3
    case confidential = 4
    case confidential2 = 5
    case classified = 6
    case photoBond = 7
    case brosnan = 8
    case connery = 9
    case dalton = 10
    case moore = 11
    case photoBrief = 12
    case cover = 13
    case photoCover = 14
    case brosnanCover = 15
    case conneryCover = 16
    case daltonCover = 17
    case mooreCover = 18
    case slides = 19
    case pics = 20
    case gfxHit0Pics = 21
    case brief1 = 22
    case brief2 = 23
    case brief3 = 24
    case brief4 = 25
    case brief5 = 26
    case brief6 = 27
    case brief7 = 28
    case brief8 = 29
    case brief9 = 30
    case brief10 = 31
    case brief11 = 32
    case brief12 = 33
    case brief13 = 34
    case brief14 = 35
    case brief15 = 36
    case brief16 = 37
    case brief17 = 38
    case brief18 = 39
    case brief19 = 40
    case brief20 = 41
    case blank = 42

    public var sourceIndex: UInt32 { rawValue }

    /// The node ids are the declaration order in walletbond/Model.c.  They
    /// are deliberately explicit so a regenerated sidecar cannot silently
    /// move a visible branch to a different source switch.
    public var nodeID: UInt32 {
        Self.nodeIDs[Int(rawValue)]
    }

    public var isModelSwitch: Bool { self != .gfxHit0Pics }

    public var displayName: String {
        Self.names[Int(rawValue)]
    }

    fileprivate static let nodeIDs: [UInt32] = [
        3, 5, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31, 34,
        77, 79, 81, 83, 85, 87, 9, 11, 12, 36, 38, 40, 42,
        44, 46, 48, 50, 52, 54, 56, 58, 60, 62, 64, 66, 68,
        70, 72, 74, 7
    ]

    fileprivate static let names: [String] = [
        "SW_TABS", "SW_PAPER", "SW_EYESONLY", "SW_OHMSS",
        "SW_CONFIDENTIAL", "SW_CONFIDENTIAL2", "SW_CLASSIFIED",
        "SW_PHOTOBOND", "SW_BROSNAN", "SW_CONNERY", "SW_DALTON",
        "SW_MOORE", "SW_PHOTOBRIEF", "SW_COVER", "SW_PHOTOCOVER",
        "SW_BROSNANCOVER", "SW_CONNERYCOVER", "SW_DALTONCOVER",
        "SW_MOORECOVER", "SW_SLIDES", "SW_PICS", "GFXHIT0_PICS",
        "SW_BRIEF1", "SW_BRIEF2", "SW_BRIEF3", "SW_BRIEF4",
        "SW_BRIEF5", "SW_BRIEF6", "SW_BRIEF7", "SW_BRIEF8",
        "SW_BRIEF9", "SW_BRIEF10", "SW_BRIEF11", "SW_BRIEF12",
        "SW_BRIEF13", "SW_BRIEF14", "SW_BRIEF15", "SW_BRIEF16",
        "SW_BRIEF17", "SW_BRIEF18", "SW_BRIEF19", "SW_BRIEF20",
        "SW_BLANK"
    ]

    /// Number of source sibling branches below each switch.  The current
    /// GESM sidecar carries the first controlled child and the model graph
    /// carries the sibling chain; this table is a compact source manifest,
    /// while `validate(model:)` verifies it against that graph.
    fileprivate var sourceBranchCount: UInt32 {
        Self.branchCounts[Int(rawValue)]
    }

    fileprivate static let branchCounts: [UInt32] = [
        1, 1, 1, 1, 1, 1, 1, 6, 1, 1, 1, 1, 22,
        2, 6, 1, 1, 1, 1, 2, 1, 0, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
    ]
}

public enum GoldenEyeWalletRouteV6: UInt32, Sendable {
    case fileSelect = 5
    case modeSelect = 6
}

/// A copied folder-progress summary.  It intentionally contains no save
/// pointer or renderer state; the File/Mode authority can construct it from
/// its immutable save projection before handing this packet to the visual
/// worker.
public struct GoldenEyeWalletFolderProgressV6: Sendable, Equatable {
    public let number: UInt32
    public let isReset: Bool
    public let hasCompletion: Bool
    public let highestStage: Int32
    public let highestDifficulty: Int32

    public init(
        number: UInt32,
        isReset: Bool,
        hasCompletion: Bool,
        highestStage: Int32 = -1,
        highestDifficulty: Int32 = -1
    ) {
        self.number = number
        self.isReset = isReset
        self.hasCompletion = hasCompletion
        self.highestStage = highestStage
        self.highestDifficulty = highestDifficulty
    }
}

public struct GoldenEyeWalletTextSegmentV6: Sendable, Equatable {
    public let sourceStringID: UInt32
    public let literal: String

    public init(sourceStringID: UInt32 = 0, literal: String = "") {
        self.sourceStringID = sourceStringID
        self.literal = literal
    }
}

public enum GoldenEyeWalletTextKindV6: UInt32, Sendable {
    case option = 1
    case folderDifficulty = 2
    case folderMission = 3
    case eraseTitle = 4
    case eraseCancel = 5
    case eraseConfirm = 6
    case modeNumber = 7
    case modeLabel = 8
    case previousTab = 9
}

/// One source text call or one source-built text row.  Mission rows retain
/// the exact source components (`Mission ` + chapter literal + `.` + part
/// literal) and their already-composed source text.  A renderer can measure
/// the complete row before placing it, preventing the component overlap that
/// occurs when each fragment is independently left-aligned.
public struct GoldenEyeWalletTextRowV6: Sendable, Equatable {
    public let kind: GoldenEyeWalletTextKindV6
    public let folder: UInt32
    public let anchorX: Int32
    public let anchorY: Int32
    public let centered: Bool
    public let vertical: Bool
    public let colorRGBA: UInt32
    public let fontID: UInt32
    public let segments: [GoldenEyeWalletTextSegmentV6]
    public let sourceText: String
    public let sequence: UInt64

    public init(
        kind: GoldenEyeWalletTextKindV6,
        folder: UInt32 = UInt32.max,
        anchorX: Int32,
        anchorY: Int32,
        centered: Bool,
        vertical: Bool = false,
        colorRGBA: UInt32 = 0xFFFF_FFFF,
        fontID: UInt32 = 0,
        segments: [GoldenEyeWalletTextSegmentV6],
        sourceText: String,
        sequence: UInt64
    ) {
        self.kind = kind
        self.folder = folder
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.centered = centered
        self.vertical = vertical
        self.colorRGBA = colorRGBA
        self.fontID = fontID
        self.segments = segments
        self.sourceText = sourceText
        self.sequence = sequence
    }
}

public struct GoldenEyeWalletSwitchSelectionV6: Sendable, Equatable {
    public let name: GoldenEyeWalletSwitchNameV6
    public let sourceIndex: UInt32
    public let nodeID: UInt32
    public let visible: Bool
    public let branchCount: UInt32

    public init(
        name: GoldenEyeWalletSwitchNameV6,
        visible: Bool,
        branchCount: UInt32? = nil
    ) {
        self.name = name
        self.sourceIndex = name.sourceIndex
        self.nodeID = name.nodeID
        self.visible = visible
        self.branchCount = branchCount ?? name.sourceBranchCount
    }
}

public struct GoldenEyeWalletVisualInputPacketV6: Sendable, Equatable {
    public let route: GoldenEyeWalletRouteV6
    public let selectedFolder: UInt32
    public let selectedBond: UInt32
    public let modeSelection: UInt32
    public let controllerCount: UInt32
    public let eraseConfirmation: Bool
    public let eraseChoice: UInt32
    public let switchInputs: [UInt32: UInt32]
    public let switchSelections: [GoldenEyeWalletSwitchSelectionV6]
    public let textRows: [GoldenEyeWalletTextRowV6]
    public let semanticHash: UInt64

    public var visibleSwitchNames: [GoldenEyeWalletSwitchNameV6] {
        switchSelections.filter(\.visible).map(\.name)
    }
}

public enum GoldenEyeWalletSwitchTextResolverV6Error: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidFolder(UInt32)
    case invalidBond(UInt32)
    case invalidStage(Int32)
    case invalidDifficulty(Int32)
    case malformedWalletModel(String)

    public var description: String {
        switch self {
        case let .invalidFolder(value): return "Wallet folder " + String(value) + " is outside 0...3"
        case let .invalidBond(value): return "Wallet Bond " + String(value) + " is outside 0...3"
        case let .invalidStage(value): return "Wallet stage " + String(value) + " is outside 0...19"
        case let .invalidDifficulty(value): return "Wallet difficulty " + String(value) + " is outside 0...3"
        case let .malformedWalletModel(value): return "Wallet model source contract: " + value
        }
    }
}

/// Source-faithful WalletBond switch visibility and File/Mode text producer.
/// The resolver is deliberately independent of the renderer and SaveStore:
/// it emits only copied source values that another worker may lower.
public enum GoldenEyeWalletSwitchTextResolverV6 {
    public static let walletModelCounts = (nodes: 90, scalars: 90, displayLists: 46, commands: 982, vertices: 765, textures: 84, mips: 186, tluts: 2)
    public static let switchOpcode: UInt32 = 0x258D_B802
    public static let collisionOpcode: UInt32 = 0x7471_23D2
    public static let sourceCanvasFolderCenters: [Int32] = [76, 172, 268, 364]

    /// Resolve a source route from copied File/Mode state and folder progress.
    /// The US source build does not define ALL_BONDS, so select_load_bond_picture
    /// always enables the Brosnan and Brosnan-cover switches, matching front.c.
    public static func resolve(
        route: GoldenEyeWalletRouteV6,
        folders: [GoldenEyeWalletFolderProgressV6] = [],
        selectedFolder: UInt32 = 0,
        selectedBond: UInt32 = 0,
        modeSelection: UInt32 = 0,
        controllerCount: UInt32 = 1,
        eraseConfirmation: Bool = false,
        eraseChoice: UInt32 = 1
    ) throws -> GoldenEyeWalletVisualInputPacketV6 {
        guard selectedFolder < 4 else { throw GoldenEyeWalletSwitchTextResolverV6Error.invalidFolder(selectedFolder) }
        guard selectedBond < 4 else { throw GoldenEyeWalletSwitchTextResolverV6Error.invalidBond(selectedBond) }
        guard modeSelection < 2 else { throw GoldenEyeWalletSwitchTextResolverV6Error.invalidDifficulty(Int32(modeSelection)) }
        guard eraseChoice < 2 else { throw GoldenEyeWalletSwitchTextResolverV6Error.invalidDifficulty(Int32(eraseChoice)) }

        let normalizedFolders = try normalizeFolders(folders)
        let active = activeSwitches(for: route)
        let selections = GoldenEyeWalletSwitchNameV6.allCases.map { name in
            GoldenEyeWalletSwitchSelectionV6(name: name, visible: active.contains(name))
        }
        let inputs = Dictionary(uniqueKeysWithValues: selections
            .filter(\.name.isModelSwitch)
            .map { ($0.nodeID, $0.visible ? UInt32(1) : UInt32(0)) })
        let textRows: [GoldenEyeWalletTextRowV6]
        switch route {
        case .fileSelect:
            textRows = fileTextRows(
                folders: normalizedFolders,
                eraseConfirmation: eraseConfirmation,
                selectedFolder: selectedFolder,
                eraseChoice: eraseChoice
            )
        case .modeSelect:
            textRows = modeTextRows(
                modeSelection: modeSelection,
                controllerCount: controllerCount
            )
        }
        let hash = semanticHash(
            route: route,
            selectedFolder: selectedFolder,
            selectedBond: selectedBond,
            modeSelection: modeSelection,
            controllerCount: controllerCount,
            eraseConfirmation: eraseConfirmation,
            eraseChoice: eraseChoice,
            selections: selections,
            textRows: textRows
        )
        return GoldenEyeWalletVisualInputPacketV6(
            route: route,
            selectedFolder: selectedFolder,
            selectedBond: selectedBond,
            modeSelection: modeSelection,
            controllerCount: controllerCount,
            eraseConfirmation: eraseConfirmation,
            eraseChoice: eraseChoice,
            switchInputs: inputs,
            switchSelections: selections,
            textRows: textRows,
            semanticHash: hash
        )
    }

    /// Validate the immutable GESM wallet graph against the source SwitchNodes
    /// order.  This catches stale sidecars before their switchInputs reach a
    /// visual worker; it does not retain the model or any file path.
    static func validate(model: GoldenEyeSourceModelV6) throws {
        let counts = model.header.counts
        guard counts.nodes == walletModelCounts.nodes,
              counts.scalars == walletModelCounts.scalars,
              counts.displayLists == walletModelCounts.displayLists,
              counts.commands == walletModelCounts.commands,
              counts.vertices == walletModelCounts.vertices,
              counts.textures == walletModelCounts.textures,
              counts.mips == walletModelCounts.mips,
              counts.tluts == walletModelCounts.tluts else {
            throw GoldenEyeWalletSwitchTextResolverV6Error.malformedWalletModel("inventory counts")
        }
        for name in GoldenEyeWalletSwitchNameV6.allCases {
            guard let node = model.node(id: name.nodeID) else {
                throw GoldenEyeWalletSwitchTextResolverV6Error.malformedWalletModel("missing (name.displayName) node (name.nodeID)")
            }
            let expectedOpcode = name == .gfxHit0Pics ? collisionOpcode : switchOpcode
            guard node.opcodeHandle == expectedOpcode else {
                throw GoldenEyeWalletSwitchTextResolverV6Error.malformedWalletModel("(name.displayName) opcode")
            }
            guard branchCount(model: model, node: node) == name.sourceBranchCount else {
                throw GoldenEyeWalletSwitchTextResolverV6Error.malformedWalletModel("(name.displayName) branch count")
            }
        }
    }

    private static func normalizeFolders(_ folders: [GoldenEyeWalletFolderProgressV6]) throws -> [GoldenEyeWalletFolderProgressV6] {
        var result = (0..<4).map { GoldenEyeWalletFolderProgressV6(number: UInt32($0), isReset: true, hasCompletion: false) }
        for folder in folders {
            guard folder.number < 4 else { throw GoldenEyeWalletSwitchTextResolverV6Error.invalidFolder(folder.number) }
            if folder.highestStage < -1 || folder.highestStage > 19 {
                throw GoldenEyeWalletSwitchTextResolverV6Error.invalidStage(folder.highestStage)
            }
            if folder.highestDifficulty < -1 || folder.highestDifficulty > 3 {
                throw GoldenEyeWalletSwitchTextResolverV6Error.invalidDifficulty(folder.highestDifficulty)
            }
            result[Int(folder.number)] = folder
        }
        return result
    }

    private static func activeSwitches(for route: GoldenEyeWalletRouteV6) -> Set<GoldenEyeWalletSwitchNameV6> {
        var result: Set<GoldenEyeWalletSwitchNameV6> = [.brosnan, .brosnanCover]
        switch route {
        case .fileSelect:
            // init_menu05_fileselect/interface_menu05_fileselect after
            // disable_all_switches: SW_COVER and SW_PHOTOCOVER only.
            result.formUnion([.cover, .photoCover])
        case .modeSelect:
            // interface_menu06_modesel after disable_all_switches.
            result.formUnion([.tabs, .paper, .ohmss, .photoBond, .eyesOnly])
        }
        return result
    }

    private static func fileTextRows(
        folders: [GoldenEyeWalletFolderProgressV6],
        eraseConfirmation: Bool,
        selectedFolder: UInt32,
        eraseChoice: UInt32
    ) -> [GoldenEyeWalletTextRowV6] {
        var rows: [GoldenEyeWalletTextRowV6] = []
        for folder in folders where !folder.isReset && folder.hasCompletion && folder.highestStage >= 0 {
            let center = sourceCanvasFolderCenters[Int(folder.number)]
            let difficulty = max(0, min(3, folder.highestDifficulty))
            let difficultyID = UInt32(19 + difficulty)
            rows.append(.init(
                kind: .folderDifficulty,
                folder: folder.number,
                anchorX: center,
                anchorY: 133,
                centered: true,
                colorRGBA: 0xEBD8_79FF,
                fontID: 1,
                segments: [.init(sourceStringID: difficultyID), .init(literal: "\n")],
                sourceText: difficultyText(id: difficultyID),
                sequence: 100 + UInt64(folder.number)
            ))
            if difficulty != 3 {
                let mission = missionText(for: folder.highestStage)
                rows.append(.init(
                    kind: .folderMission,
                    folder: folder.number,
                    anchorX: center,
                    anchorY: 145,
                    centered: true,
                    colorRGBA: 0xEBD8_79FF,
                    fontID: 1,
                    segments: [
                        .init(sourceStringID: 26),
                        .init(literal: mission.chapter),
                        .init(literal: "."),
                        .init(literal: mission.part),
                        .init(literal: "\n")
                    ],
                    sourceText: "Mission " + mission.chapter + "." + mission.part + "\n",
                    sequence: 200 + UInt64(folder.number)
                ))
            }
        }

        rows.append(.init(
            kind: .option, anchorX: 247, anchorY: 278, centered: false,
            fontID: 1, segments: [.init(sourceStringID: 27)],
            sourceText: "Copy\n", sequence: 10
        ))
        rows.append(.init(
            kind: .option, anchorX: 357, anchorY: 278, centered: false,
            fontID: 1, segments: [.init(sourceStringID: 28)],
            sourceText: "Erase\n", sequence: 11
        ))

        if eraseConfirmation {
            let folder = min(selectedFolder, 3)
            let center = sourceCanvasFolderCenters[Int(folder)]
            rows.append(.init(
                kind: .eraseTitle, folder: folder, anchorX: center - 47, anchorY: 136,
                centered: false, colorRGBA: 0xEBD8_79FF, fontID: 1,
                segments: [.init(sourceStringID: 23)], sourceText: "Erase file?\n", sequence: 300
            ))
            rows.append(.init(
                kind: .eraseCancel, folder: folder, anchorX: center - 47, anchorY: 154,
                centered: false, colorRGBA: eraseChoice == 1 ? 0xFFFF_FFFF : 0xEBD8_79FF,
                fontID: 1, segments: [.init(sourceStringID: 24)], sourceText: "cancel\n", sequence: 301
            ))
            rows.append(.init(
                kind: .eraseConfirm, folder: folder, anchorX: center - 1, anchorY: 154,
                centered: false, colorRGBA: eraseChoice == 0 ? 0xFFFF_FFFF : 0xEBD8_79FF,
                fontID: 1, segments: [.init(sourceStringID: 25)], sourceText: "confirm\n", sequence: 302
            ))
        }
        return rows
    }

    private static func modeTextRows(modeSelection: UInt32, controllerCount: UInt32) -> [GoldenEyeWalletTextRowV6] {
        let disabled = controllerCount < 2
        let color: UInt32 = disabled ? 0x7070_70FF : 0xFFFF_FFFF
        return [
            .init(kind: .modeNumber, anchorX: 150, anchorY: 220, centered: false, colorRGBA: 0xFFFF_FFFF, fontID: 1,
                  segments: [.init(literal: "1.\n")], sourceText: "1.\n", sequence: 10),
            .init(kind: .modeLabel, anchorX: 170, anchorY: 220, centered: false, colorRGBA: 0xFFFF_FFFF, fontID: 1,
                  segments: [.init(sourceStringID: 29)], sourceText: "SELECT MISSION\n", sequence: 11),
            .init(kind: .modeNumber, anchorX: 150, anchorY: 252, centered: false, colorRGBA: color, fontID: 1,
                  segments: [.init(literal: "2.\n")], sourceText: "2.\n", sequence: 12),
            .init(kind: .modeLabel, anchorX: 170, anchorY: 252, centered: false, colorRGBA: color, fontID: 1,
                  segments: [.init(sourceStringID: 30)], sourceText: "MULTIPLAYER\n", sequence: 13),
            .init(kind: .previousTab, anchorX: 398, anchorY: 236, centered: false, vertical: true,
                  fontID: 2, segments: [.init(sourceStringID: 6)], sourceText: "PREVIOUS\n", sequence: 30)
        ]
    }

    private static func difficultyText(id: UInt32) -> String {
        switch id {
        case 19: return "Agent\n"
        case 20: return "Secret Agent\n"
        case 21: return "00 Agent\n"
        default: return "007\n"
        }
    }

    private static func missionText(for stage: Int32) -> (chapter: String, part: String) {
        let values: [(String, String)] = [
            ("1", "i"), ("1", "ii"), ("1", "iii"), ("2", "i"), ("2", "ii"),
            ("3", "i"), ("4", "i"), ("5", "i"), ("5", "ii"), ("6", "i"),
            ("6", "ii"), ("6", "iii"), ("6", "iv"), ("6", "v"), ("7", "i"),
            ("7", "ii"), ("7", "iii"), ("7", "iv"), ("8", "i"), ("9", "i")
        ]
        let index = Int(stage)
        return values.indices.contains(index) ? values[index] : ("?", "?")
    }

    private static func branchCount(model: GoldenEyeSourceModelV6, node: GoldenEyeSourceModelV6.Node) -> UInt32 {
        var current = node.child
        var seen = Set<UInt32>()
        var count: UInt32 = 0
        while current != GoldenEyeSourceModelV6.nullHandle,
              !seen.contains(current),
              let child = model.node(id: current) {
            seen.insert(current)
            count += 1
            current = child.next
        }
        return count
    }

    private static func semanticHash(
        route: GoldenEyeWalletRouteV6,
        selectedFolder: UInt32,
        selectedBond: UInt32,
        modeSelection: UInt32,
        controllerCount: UInt32,
        eraseConfirmation: Bool,
        eraseChoice: UInt32,
        selections: [GoldenEyeWalletSwitchSelectionV6],
        textRows: [GoldenEyeWalletTextRowV6]
    ) -> UInt64 {
        var bytes = Data()
        func append(_ value: UInt64) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { bytes.append(contentsOf: $0) }
        }
        append(UInt64(route.rawValue)); append(UInt64(selectedFolder)); append(UInt64(selectedBond))
        append(UInt64(modeSelection)); append(UInt64(controllerCount)); append(eraseConfirmation ? 1 : 0); append(UInt64(eraseChoice))
        for selection in selections { append(UInt64(selection.nodeID)); append(selection.visible ? 1 : 0); append(UInt64(selection.branchCount)) }
        for row in textRows {
            append(UInt64(row.kind.rawValue)); append(UInt64(row.folder)); append(UInt64(bitPattern: Int64(row.anchorX))); append(UInt64(bitPattern: Int64(row.anchorY)))
            append(row.centered ? 1 : 0); append(row.vertical ? 1 : 0); append(UInt64(row.colorRGBA)); append(UInt64(row.fontID)); append(row.sequence)
            bytes.append(contentsOf: row.sourceText.utf8); bytes.append(0)
        }
        var hash: UInt64 = 14695981039346656037
        for byte in bytes { hash ^= UInt64(byte); hash &*= 1099511628211 }
        return hash
    }
}
