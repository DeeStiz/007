import CryptoKit
import Foundation

public enum GoldenEyeSourceTextureSetupV6Error: Error, Sendable, Equatable, CustomStringConvertible {
    case emptyCommands
    case invalidCommand(UInt32, String)
    case missingState(UInt32, String)
    case missingTexture(UInt32, String)
    case unknownAlias(UInt32)
    case invalidAddressMode(UInt32)
    case invalidTextureType(UInt32)
    case invalidLevel(UInt32, UInt32)
    case invalidTile(UInt32, String)
    case invalidBounds(UInt32, String)
    case sourceMismatch(UInt32, String)
    case payloadMismatch(UInt32, String)
    case duplicateSetup(UInt32, UInt32)
    case aliasCapacity

    public var description: String {
        switch self {
        case .emptyCommands: return "source texture setup command stream is empty"
        case let .invalidCommand(index, detail): return "invalid source texture command \(index): \(detail)"
        case let .missingState(index, state): return "source texture command \(index) is missing state: \(state)"
        case let .missingTexture(handle, detail): return "source texture \(handle) is missing: \(detail)"
        case let .unknownAlias(alias): return "source texture alias \(alias) is unknown"
        case let .invalidAddressMode(mode): return "source texture address mode \(mode) is invalid"
        case let .invalidTextureType(type): return "source texture type \(type) is invalid"
        case let .invalidLevel(handle, level): return "source texture \(handle) level \(level) is invalid"
        case let .invalidTile(tile, detail): return "source texture tile \(tile) is invalid: \(detail)"
        case let .invalidBounds(tile, detail): return "source texture tile \(tile) bounds are invalid: \(detail)"
        case let .sourceMismatch(id, detail): return "source texture source mismatch for record \(id): \(detail)"
        case let .payloadMismatch(id, detail): return "source texture payload mismatch for record \(id): \(detail)"
        case let .duplicateSetup(handle, tile): return "duplicate source texture setup for \(handle)/tile \(tile)"
        case .aliasCapacity: return "source texture alias table is exhausted"
        }
    }
}

public enum GoldenEyeSourceTextureAddressModeV6: UInt32, Sendable, Equatable {
    case wrap = 0
    case mirror = 1
    case clamp = 2
}

public enum GoldenEyeSourceTextureLoadKindV6: UInt32, Sendable, Equatable {
    case payload = 0
    case block = 1
    case tile = 2
    case tlut = 3
}

public enum GoldenEyeSourceTextureSetupKindV6: UInt32, Sendable, Equatable {
    case standardTile = 0
    case customGSetTex = 1
}

/// A copied command suitable for passing from the source compiler to the
/// setup resolver. It contains no Gfx pointer or segmented address.
public struct GoldenEyeSourceTextureSetupCommandV6: Sendable, Equatable {
    public let sequence: UInt32
    public let displayListID: UInt32
    public let ordinal: UInt32
    public let macro: String
    public let arguments: [UInt32]
    public let word0: UInt32
    public let word1: UInt32
    public let sourceHash: UInt64

    public init(
        sequence: UInt32,
        displayListID: UInt32,
        ordinal: UInt32,
        macro: String,
        arguments: [UInt32],
        word0: UInt32,
        word1: UInt32,
        sourceHash: UInt64 = 0
    ) {
        self.sequence = sequence
        self.displayListID = displayListID
        self.ordinal = ordinal
        self.macro = macro
        self.arguments = arguments
        self.word0 = word0
        self.word1 = word1
        self.sourceHash = sourceHash
    }

    init(sequence: UInt32, compiled: GESourceCompiledCommandV6) {
        self.init(
            sequence: sequence,
            displayListID: compiled.displayListID,
            ordinal: compiled.ordinal,
            macro: compiled.macro,
            arguments: compiled.arguments.map(Self.compact),
            word0: compiled.word0,
            word1: compiled.word1
        )
    }

    private static func compact(_ value: GoldenEyeSourceModelV6.TokenValue) -> UInt32 {
        switch value {
        case let .integer(value): return UInt32(truncatingIfNeeded: value)
        case let .constant(_, value): return value
        case let .handle(_, value): return value
        case .null: return GoldenEyeSourceModelV6.nullHandle
        case let .boolean(value): return value ? 1 : 0
        }
    }
}

public struct GoldenEyeSourceTextureTileBoundsV6: Sendable, Equatable {
    public let ulsQ2: UInt32
    public let ultQ2: UInt32
    public let lrsQ2: UInt32
    public let lrtQ2: UInt32
    public let width: UInt32
    public let height: UInt32
    public let derivedFromPayloadDimensions: Bool
}

public struct GoldenEyeSourceTextureTileStateV6: Sendable, Equatable {
    public let tile: UInt32
    public let format: UInt32?
    public let size: UInt32?
    public let line: UInt32?
    public let tmem: UInt32?
    public let palette: UInt32?
    public let addressS: GoldenEyeSourceTextureAddressModeV6
    public let addressT: GoldenEyeSourceTextureAddressModeV6
    public let maskS: UInt32
    public let maskT: UInt32
    public let shiftS: UInt32
    public let shiftT: UInt32
    public let bounds: GoldenEyeSourceTextureTileBoundsV6
    public let derivedFromCustomCommand: Bool
}

public struct GoldenEyeSourceTextureLoadEvidenceV6: Sendable, Equatable {
    public let kind: GoldenEyeSourceTextureLoadKindV6
    public let tile: UInt32
    public let imageHandle: UInt32
    public let payloadRecordID: UInt32
    public let level: UInt32
    public let ulsQ2: UInt32
    public let ultQ2: UInt32
    public let lrsQ2: UInt32
    public let lrtQ2: UInt32
    public let dxt: UInt32?
    public let sourceOffset: UInt32
    public let rawByteCount: UInt32
    public let decodedByteCount: UInt32
}

public struct GoldenEyeSourceTextureSetupLevelV6: Sendable, Equatable {
    public let level: UInt32
    public let width: UInt32
    public let height: UInt32
    public let payloadRecordID: UInt32
    public let sourceOffset: UInt32
    public let sourceRowHandle: UInt32
    public let rawByteCount: UInt32
    public let decodedByteCount: UInt32
    public let decodedSHA256: String
}

public struct GoldenEyeSourceTextureSetupPaletteV6: Sendable, Equatable {
    public let resourceHandle: UInt32
    public let payloadRecordID: UInt32
    public let entries: UInt32
    public let sourceOffset: UInt32
    public let sourceRowHandle: UInt32
    public let rawByteCount: UInt32
    public let decodedByteCount: UInt32
    public let decodedSHA256: String
}

public struct GoldenEyeSourceTextureSetupV6: Sendable, Equatable {
    public let sequence: UInt32
    public let displayListID: UInt32
    public let ordinal: UInt32
    public let kind: GoldenEyeSourceTextureSetupKindV6
    public let modelName: String
    public let resourceHandle: UInt32
    public let aliasHandle: UInt32
    public let tile: UInt32
    public let textureType: UInt32
    public let minLevel: UInt32
    public let detailID: UInt32
    public let textureScaleS: UInt32
    public let textureScaleT: UInt32
    public let maxLOD: UInt32
    public let imageFormat: UInt32?
    public let imageSize: UInt32?
    public let imageWidth: UInt32?
    public let sourcePayloadRecordID: UInt32
    public let sourceOffset: UInt32
    public let sourceRowHandle: UInt32
    public let sourceSpan: UInt32
    public let levels: [GoldenEyeSourceTextureSetupLevelV6]
    public let tileState: GoldenEyeSourceTextureTileStateV6
    public let load: GoldenEyeSourceTextureLoadEvidenceV6
    public let palette: GoldenEyeSourceTextureSetupPaletteV6?
    public let setupHash: UInt64
}

public struct GoldenEyeSourceTextureSetupResultV6: Sendable, Equatable {
    public let setups: [GoldenEyeSourceTextureSetupV6]
    public let aliases: [UInt32: UInt32]
    public let stateHash: UInt64
    public let setupHash: UInt64
}

private struct TextureSetupLevelEvidence {
    let level: UInt32
    let width: UInt32
    let height: UInt32
    let payloadRecordID: UInt32
    let sourceOffset: UInt32
    let sourceRowHandle: UInt32
    let rawByteCount: UInt32
    let decodedByteCount: UInt32
    let decodedSHA256: String
}

private struct TextureSetupPaletteEvidence {
    let payloadRecordID: UInt32
    let entries: UInt32
    let sourceOffset: UInt32
    let sourceRowHandle: UInt32
    let rawByteCount: UInt32
    let decodedByteCount: UInt32
    let decodedSHA256: String
}

private struct TextureSetupEvidence {
    let resourceHandle: UInt32
    let width: UInt32
    let height: UInt32
    let mipLevels: UInt32
    let payloadRecordID: UInt32
    let payloadDecodedSHA256: String
    let sourceOffset: UInt32
    let sourceRowHandle: UInt32
    let sourceSpan: UInt32
    let levels: [TextureSetupLevelEvidence]
    let palette: TextureSetupPaletteEvidence?
}

/// Expands source G_SETTEX/gsSPUseTexture and classic image/tile/load commands
/// into value-only setup records. Payload bytes and every source relationship
/// are checked through the guarded GEFV catalog and GESM model before output.
public enum GoldenEyeSourceTextureSetupResolverV6 {
    private static func makeEvidence(
        modelName: String,
        model: GoldenEyeSourceModelV6,
        catalog: GoldenEyeSourceFrontendCatalog
    ) throws -> [UInt32: TextureSetupEvidence] {
        var result: [UInt32: TextureSetupEvidence] = [:]
        for texture in model.textures {
            guard let payload = catalog.record(id: texture.payloadRecordID), payload.category == "texture_payload" else {
                throw GoldenEyeSourceTextureSetupV6Error.missingTexture(texture.resourceHandle, "texture payload record (texture.payloadRecordID)")
            }
            let metadata = try objectMetadata(payload)
            let width = try uint(metadata, key: "width", record: payload.id)
            let height = try uint(metadata, key: "height", record: payload.id)
            let mipLevels = try uint(metadata, key: "mip_levels", record: payload.id)
            let sourceOffset = try uint(metadata, key: "source_offset", record: payload.id)
            let sourceRow = try string(metadata, key: "source_row", record: payload.id)
            let isGlobal = payload.flags.contains("GLOBAL_TEXTURE_PAYLOAD")
            let sourceSpan = isGlobal ? payload.rawSize : try uint(metadata, key: "source_span", record: payload.id)
            guard width == texture.width, height == texture.height, mipLevels == texture.mipCount,
                  sourceOffset == texture.sourceOffset,
                  sourceSpan == texture.sourceSpan,
                  fnv32ResourceRow(modelName: modelName, row: sourceRow) == texture.sourceRowHandle else {
                throw GoldenEyeSourceTextureSetupV6Error.sourceMismatch(payload.id, "texture dimensions/source row/span payload=\(width)x\(height)/\(sourceOffset)/\(sourceSpan)/\(sourceRow)/0x\(String(fnv32ResourceRow(modelName: modelName, row: sourceRow), radix: 16)) model=\(texture.width)x\(texture.height)/\(texture.sourceOffset)/\(texture.sourceSpan)/0x\(String(texture.sourceRowHandle, radix: 16))")
            }
            try requirePixelFlags(payload)
            try rejectSourceText(payload)

            var levels: [TextureSetupLevelEvidence] = []
            var reconstructed = Data()
            for levelIndex in 0..<texture.mipCount {
                let mipIndex = Int(texture.mipStart) + Int(levelIndex)
                guard mipIndex < model.mips.count else {
                    throw GoldenEyeSourceTextureSetupV6Error.invalidLevel(texture.resourceHandle, levelIndex)
                }
                let mip = model.mips[mipIndex]
                guard mip.textureIndex == texture.index, mip.level == levelIndex,
                      mip.resourceHandle == texture.resourceHandle,
                      mip.sourceRecordID == texture.payloadRecordID else {
                    throw GoldenEyeSourceTextureSetupV6Error.sourceMismatch(mip.payloadRecordID, "GESM mip relationship")
                }
                let record: GoldenEyeSourceFrontendRecord
                let mipMetadata: [String: GoldenEyeSourceFrontendJSONValue]
                let sourceRecordIsBase = isGlobal && levelIndex == 0
                if sourceRecordIsBase {
                    guard mip.payloadRecordID == payload.id else {
                        throw GoldenEyeSourceTextureSetupV6Error.sourceMismatch(mip.payloadRecordID, "global base mip payload")
                    }
                    record = payload
                    mipMetadata = metadata
                } else {
                    guard let mipRecord = catalog.record(id: mip.payloadRecordID), mipRecord.category == "mip_payload" else {
                        throw GoldenEyeSourceTextureSetupV6Error.missingTexture(texture.resourceHandle, "mip payload record (mip.payloadRecordID)")
                    }
                    record = mipRecord
                    mipMetadata = try objectMetadata(mipRecord)
                }
                let mipWidth = try uint(mipMetadata, key: "width", record: record.id)
                let mipHeight = try uint(mipMetadata, key: "height", record: record.id)
                let mipLevel = sourceRecordIsBase ? 0 : try uint(mipMetadata, key: "level", record: record.id)
                let mipOffset = try uint(mipMetadata, key: "source_offset", record: record.id)
                let mipRow = try string(mipMetadata, key: "source_row", record: record.id)
                guard mipWidth == mip.width, mipHeight == mip.height, mipLevel == mip.level,
                      mipOffset == mip.sourceOffset,
                      fnv32ResourceRow(modelName: modelName, row: mipRow) == mip.sourceRowHandle,
                      mip.rawByteCount == record.rawSize, mip.decodedByteCount == record.decodedSize else {
                    throw GoldenEyeSourceTextureSetupV6Error.sourceMismatch(record.id, "mip dimensions/source bytes/row")
                }
                try requirePixelFlags(record)
                try rejectSourceText(record)
                let decoded = try catalog.copyOut(.decoded, recordID: record.id)
                let expectedDecodedBytes = try rgbaBytes(width: mipWidth, height: mipHeight, record: record.id)
                guard decoded.count == expectedDecodedBytes,
                      decoded.count == Int(record.decodedSize),
                      sha256(decoded) == record.decodedSHA256 else {
                    throw GoldenEyeSourceTextureSetupV6Error.payloadMismatch(record.id, "decoded RGBA8 payload")
                }
                reconstructed.append(decoded)
                levels.append(TextureSetupLevelEvidence(level: mip.level, width: mip.width, height: mip.height, payloadRecordID: record.id, sourceOffset: mip.sourceOffset, sourceRowHandle: mip.sourceRowHandle, rawByteCount: mip.rawByteCount, decodedByteCount: mip.decodedByteCount, decodedSHA256: record.decodedSHA256))
            }
            let payloadDecoded = try catalog.copyOut(.decoded, recordID: payload.id)
            let expectedPayload: Data
            if isGlobal {
                guard let firstLevel = levels.first else { throw GoldenEyeSourceTextureSetupV6Error.missingState(0, "global base mip") }
                expectedPayload = try catalog.copyOut(.decoded, recordID: firstLevel.payloadRecordID)
            } else {
                expectedPayload = reconstructed
            }
            guard payloadDecoded == expectedPayload, sha256(payloadDecoded) == payload.decodedSHA256 else {
                throw GoldenEyeSourceTextureSetupV6Error.payloadMismatch(payload.id, "texture payload aggregate")
            }

            var palette: TextureSetupPaletteEvidence?
            if texture.tlutIndex != GoldenEyeSourceModelV6.nullHandle {
                guard texture.tlutIndex < UInt32(model.tluts.count) else {
                    throw GoldenEyeSourceTextureSetupV6Error.invalidLevel(texture.resourceHandle, texture.tlutIndex)
                }
                let tlut = model.tluts[Int(texture.tlutIndex)]
                guard tlut.textureIndex == texture.index, tlut.resourceHandle == texture.resourceHandle,
                      tlut.sourceRecordID == texture.payloadRecordID,
                      let paletteRecord = catalog.record(id: tlut.payloadRecordID), paletteRecord.category == "tlut_payload" else {
                    throw GoldenEyeSourceTextureSetupV6Error.sourceMismatch(tlut.payloadRecordID, "GESM TLUT relationship")
                }
                let paletteMetadata = try objectMetadata(paletteRecord)
                let entries = try uint(paletteMetadata, key: "entries", record: paletteRecord.id)
                let paletteOffset = try uint(paletteMetadata, key: "source_offset", record: paletteRecord.id)
                let paletteRow = try string(paletteMetadata, key: "source_row", record: paletteRecord.id)
                let decoded = try catalog.copyOut(.decoded, recordID: paletteRecord.id)
                let expectedPaletteBytes = try rgbaBytes(width: entries, height: 1, record: paletteRecord.id)
                guard paletteOffset >= tlut.sourceOffset,
                      UInt64(paletteOffset) + UInt64(paletteRecord.rawSize) <= UInt64(texture.sourceSpan),
                      fnv32ResourceRow(modelName: modelName, row: paletteRow) == tlut.sourceRowHandle,
                      tlut.rawByteCount == paletteRecord.rawSize,
                      decoded.count == expectedPaletteBytes,
                      sha256(decoded) == paletteRecord.decodedSHA256 else {
                    throw GoldenEyeSourceTextureSetupV6Error.payloadMismatch(paletteRecord.id, "TLUT payload")
                }
                palette = TextureSetupPaletteEvidence(payloadRecordID: paletteRecord.id, entries: entries, sourceOffset: paletteOffset, sourceRowHandle: tlut.sourceRowHandle, rawByteCount: tlut.rawByteCount, decodedByteCount: paletteRecord.decodedSize, decodedSHA256: paletteRecord.decodedSHA256)
            }
            result[texture.resourceHandle] = TextureSetupEvidence(resourceHandle: texture.resourceHandle, width: texture.width, height: texture.height, mipLevels: texture.mipCount, payloadRecordID: payload.id, payloadDecodedSHA256: payload.decodedSHA256, sourceOffset: texture.sourceOffset, sourceRowHandle: texture.sourceRowHandle, sourceSpan: texture.sourceSpan, levels: levels, palette: palette)
        }
        return result
    }

    static func resolve(
        modelName: String,
        model: GoldenEyeSourceModelV6,
        catalog: GoldenEyeSourceFrontendCatalog,
        commands: [GoldenEyeSourceTextureSetupCommandV6]
    ) throws -> GoldenEyeSourceTextureSetupResultV6 {
        guard !commands.isEmpty else { throw GoldenEyeSourceTextureSetupV6Error.emptyCommands }
        let evidence = try makeEvidence(modelName: modelName, model: model, catalog: catalog)
        let textureByHandle = Dictionary(uniqueKeysWithValues: model.textures.map { ($0.resourceHandle, $0) })
        let aliases = try makeAliases(commands: commands, textureByHandle: textureByHandle)
        var state = State()
        var setups: [GoldenEyeSourceTextureSetupV6] = []
        var emittedStandard: Set<String> = []
        var stateHash = Hash.offsetBasis

        for rawCommand in commands {
            let command = normalizeRaw(rawCommand)
            Hash.append(command.sequence, to: &stateHash)
            Hash.append(command.word0, to: &stateHash)
            Hash.append(command.word1, to: &stateHash)
            switch command.macro {
            case "gsSPTexture", "gsSPTextureL":
                try state.setTexture(command)
            case "gsDPSetTextureImage":
                try state.setImage(command, textureByHandle: textureByHandle)
            case "gsDPSetTile":
                try state.setTile(command)
                try appendStandardIfReady(modelName: modelName, model: model, catalog: catalog, evidenceByHandle: evidence, textureByHandle: textureByHandle, state: state, tile: command.arguments[4], command: command, setups: &setups, emitted: &emittedStandard)
            case "gsDPSetTileSize":
                let tile = try state.setTileSize(command)
                try appendStandardIfReady(modelName: modelName, model: model, catalog: catalog, evidenceByHandle: evidence, textureByHandle: textureByHandle, state: state, tile: tile, command: command, setups: &setups, emitted: &emittedStandard)
            case "gsDPLoadBlock":
                try state.setBlockLoad(command)
                for tile in state.bounds.keys { try appendStandardIfReady(modelName: modelName, model: model, catalog: catalog, evidenceByHandle: evidence, textureByHandle: textureByHandle, state: state, tile: tile, command: command, setups: &setups, emitted: &emittedStandard) }
            case "gsDPLoadTile":
                try state.setTileLoad(command)
                for tile in state.bounds.keys { try appendStandardIfReady(modelName: modelName, model: model, catalog: catalog, evidenceByHandle: evidence, textureByHandle: textureByHandle, state: state, tile: tile, command: command, setups: &setups, emitted: &emittedStandard) }
            case "gsDPLoadTLUT":
                try state.setTLUTLoad(command)
            case "gsSPUseTexture":
                let setup = try makeCustomSetup(
                    modelName: modelName,
                    model: model,
                    catalog: catalog,
                    evidenceByHandle: evidence,
                    textureByHandle: textureByHandle,
                    state: state,
                    command: command,
                    aliases: aliases
                )
                setups.append(setup)
            default:
                if command.macro == "gsDPSetTile" {
                    try appendStandardIfReady(modelName: modelName, model: model, catalog: catalog, evidenceByHandle: evidence, textureByHandle: textureByHandle, state: state, tile: command.arguments.count > 4 ? command.arguments[4] : 0, command: command, setups: &setups, emitted: &emittedStandard)
                }
                if (command.word0 >> 24) == 0xc0 {
                    let setup = try makeCustomSetup(
                        modelName: modelName,
                        model: model,
                        catalog: catalog,
                        evidenceByHandle: evidence,
                        textureByHandle: textureByHandle,
                        state: state,
                        command: command,
                        aliases: aliases
                    )
                    setups.append(setup)
                }
            }
        }
        guard !setups.isEmpty else {
            throw GoldenEyeSourceTextureSetupV6Error.missingState(0, "\(modelName): no texture setup command")
        }
        var setupHash = Hash.offsetBasis
        for setup in setups { Hash.append(setup.setupHash, to: &setupHash) }
        return GoldenEyeSourceTextureSetupResultV6(
            setups: setups,
            aliases: aliases,
            stateHash: stateHash,
            setupHash: setupHash
        )
    }

    private static func appendStandardIfReady(
        modelName: String,
        model: GoldenEyeSourceModelV6,
        catalog: GoldenEyeSourceFrontendCatalog,
        evidenceByHandle: [UInt32: TextureSetupEvidence],
        textureByHandle: [UInt32: GoldenEyeSourceModelV6.Texture],
        state: State,
        tile: UInt32,
        command: GoldenEyeSourceTextureSetupCommandV6,
        setups: inout [GoldenEyeSourceTextureSetupV6],
        emitted: inout Set<String>
    ) throws {
        guard state.imageHandle != nil,
              state.tiles[tile] != nil,
              state.bounds[tile] != nil,
              !state.loads.isEmpty,
              state.tileGenerations[tile] == state.imageGeneration,
              state.boundsGenerations[tile] == state.imageGeneration,
              state.loads.contains(where: { state.loadGenerations[$0.key] == state.imageGeneration }),
              state.textureScaleS != nil,
              state.textureScaleT != nil,
              state.maxLOD != nil,
              state.textureEnabled == 1 else { return }
        let setup = try makeStandardSetup(modelName: modelName, model: model, catalog: catalog, evidenceByHandle: evidenceByHandle, textureByHandle: textureByHandle, state: state, tile: tile, command: command)
        let key = "\(setup.resourceHandle):\(setup.tile):\(setup.sourcePayloadRecordID):\(setup.tileState.bounds.lrsQ2):\(setup.tileState.bounds.lrtQ2)"
        if emitted.insert(key).inserted { setups.append(setup) }
    }

    static func resolve(
        modelName: String,
        model: GoldenEyeSourceModelV6,
        catalog: GoldenEyeSourceFrontendCatalog,
        compiledCommands: [GESourceCompiledCommandV6]
    ) throws -> GoldenEyeSourceTextureSetupResultV6 {
        try resolve(
            modelName: modelName,
            model: model,
            catalog: catalog,
            commands: compiledCommands.enumerated().map { GoldenEyeSourceTextureSetupCommandV6(sequence: UInt32($0.offset), compiled: $0.element) }
        )
    }

    private struct State {
        struct Tile {
            let tile: UInt32
            let format: UInt32
            let size: UInt32
            let line: UInt32
            let tmem: UInt32
            let palette: UInt32
            let cmt: UInt32
            let maskT: UInt32
            let shiftT: UInt32
            let cms: UInt32
            let maskS: UInt32
            let shiftS: UInt32
        }
        struct Bounds { let tile: UInt32; let uls: UInt32; let ult: UInt32; let lrs: UInt32; let lrt: UInt32 }
        struct Load { let kind: GoldenEyeSourceTextureLoadKindV6; let tile: UInt32; let uls: UInt32; let ult: UInt32; let lrs: UInt32; let lrt: UInt32; let dxt: UInt32?; let count: UInt32? }

        var textureScaleS: UInt32?
        var textureScaleT: UInt32?
        var maxLOD: UInt32?
        var textureEnabled: UInt32?
        var imageHandle: UInt32?
        var imageFormat: UInt32?
        var imageSize: UInt32?
        var imageWidth: UInt32?
        var imageGeneration: UInt32 = 0
        var tiles: [UInt32: Tile] = [:]
        var bounds: [UInt32: Bounds] = [:]
        var loads: [UInt32: Load] = [:]
        var tlutLoads: [UInt32: Load] = [:]
        var tileGenerations: [UInt32: UInt32] = [:]
        var boundsGenerations: [UInt32: UInt32] = [:]
        var loadGenerations: [UInt32: UInt32] = [:]

        mutating func setTexture(_ command: GoldenEyeSourceTextureSetupCommandV6) throws {
            if command.macro == "gsSPTextureL" {
                guard command.arguments.count == 6 else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "gsSPTextureL argument count") }
                textureScaleS = command.arguments[0]; textureScaleT = command.arguments[1]
                maxLOD = command.arguments[2]; textureEnabled = command.arguments[5]
                guard command.arguments[2] < 8, command.arguments[4] < 8, command.arguments[5] <= 1 else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "gsSPTextureL tile/enabled") }
            } else {
                guard command.arguments.count == 5 else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "gsSPTexture argument count") }
                textureScaleS = command.arguments[0]; textureScaleT = command.arguments[1]
                maxLOD = command.arguments[2]; textureEnabled = command.arguments[4]
                guard command.arguments[3] < 8, command.arguments[4] <= 1 else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "gsSPTexture tile/enabled") }
            }
        }

        mutating func setImage(_ command: GoldenEyeSourceTextureSetupCommandV6, textureByHandle: [UInt32: GoldenEyeSourceModelV6.Texture]) throws {
            guard command.arguments.count == 4 else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "gsDPSetTextureImage argument count") }
            let handle = command.arguments[3]
            guard textureByHandle[handle] != nil else { throw GoldenEyeSourceTextureSetupV6Error.missingTexture(handle, "G_SETTIMG handle") }
            imageGeneration &+= 1
            imageHandle = handle; imageFormat = command.arguments[0]; imageSize = command.arguments[1]; imageWidth = command.arguments[2]
        }

        mutating func setTile(_ command: GoldenEyeSourceTextureSetupCommandV6) throws {
            guard command.arguments.count == 12 else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "gsDPSetTile argument count") }
            let a = command.arguments
            guard a[0] < 8, a[1] < 4, a[2] <= 511, a[3] <= 511, a[4] < 8, a[5] < 16, a[6] < 4, a[7] < 16, a[8] < 16, a[9] < 4, a[10] < 16, a[11] < 16 else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "gsDPSetTile bounds") }
            tiles[a[4]] = Tile(tile: a[4], format: a[0], size: a[1], line: a[2], tmem: a[3], palette: a[5], cmt: a[6], maskT: a[7], shiftT: a[8], cms: a[9], maskS: a[10], shiftS: a[11])
            tileGenerations[a[4]] = imageGeneration
        }

        mutating func setTileSize(_ command: GoldenEyeSourceTextureSetupCommandV6) throws -> UInt32 {
            guard command.arguments.count == 5 else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "gsDPSetTileSize argument count") }
            let a = command.arguments
            guard a[0] < 8, a[1] <= 0xfff, a[2] <= 0xfff, a[3] <= 0xfff, a[4] <= 0xfff, a[3] >= a[1], a[4] >= a[2] else { throw GoldenEyeSourceTextureSetupV6Error.invalidBounds(a[0], "SETTILESIZE ordering") }
            bounds[a[0]] = Bounds(tile: a[0], uls: a[1], ult: a[2], lrs: a[3], lrt: a[4])
            boundsGenerations[a[0]] = imageGeneration
            return a[0]
        }

        mutating func setBlockLoad(_ command: GoldenEyeSourceTextureSetupCommandV6) throws {
            guard command.arguments.count == 5 else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "gsDPLoadBlock argument count") }
            let a = command.arguments; guard a[0] < 8, a[1] <= 0xfff, a[2] <= 0xfff, a[3] <= 0xfff, a[4] <= 0xfff else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "LOADBLOCK bounds") }
            loads[a[0]] = Load(kind: .block, tile: a[0], uls: a[1], ult: a[2], lrs: a[3], lrt: a[2], dxt: a[4], count: nil)
            loadGenerations[a[0]] = imageGeneration
        }

        mutating func setTileLoad(_ command: GoldenEyeSourceTextureSetupCommandV6) throws {
            guard command.arguments.count == 5 else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "gsDPLoadTile argument count") }
            let a = command.arguments; guard a[0] < 8, a[1] <= 0xfff, a[2] <= 0xfff, a[3] <= 0xfff, a[4] <= 0xfff, a[3] >= a[1], a[4] >= a[2] else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "LOADTILE bounds") }
            loads[a[0]] = Load(kind: .tile, tile: a[0], uls: a[1], ult: a[2], lrs: a[3], lrt: a[4], dxt: nil, count: nil)
            loadGenerations[a[0]] = imageGeneration
        }

        mutating func setTLUTLoad(_ command: GoldenEyeSourceTextureSetupCommandV6) throws {
            guard command.arguments.count == 2, command.arguments[0] < 8, command.arguments[1] > 0 else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "LOADTLUT arguments") }
            tlutLoads[command.arguments[0]] = Load(kind: .tlut, tile: command.arguments[0], uls: 0, ult: 0, lrs: 0, lrt: 0, dxt: nil, count: command.arguments[1])
        }
    }

    private static func makeAliases(
        commands: [GoldenEyeSourceTextureSetupCommandV6],
        textureByHandle: [UInt32: GoldenEyeSourceModelV6.Texture]
    ) throws -> [UInt32: UInt32] {
        let handles = commands.compactMap { command -> UInt32? in
            guard command.macro == "gsSPUseTexture", command.arguments.count == 9 else { return nil }
            return textureArgument(command.arguments[8])
        }
        var result: [UInt32: UInt32] = [:]
        for (index, handle) in Set(handles).sorted().enumerated() {
            guard index < 0xfff else { throw GoldenEyeSourceTextureSetupV6Error.aliasCapacity }
            guard textureByHandle[handle] != nil else { throw GoldenEyeSourceTextureSetupV6Error.missingTexture(handle, "gsSPUseTexture") }
            result[handle] = UInt32(index + 1)
        }
        return result
    }

    private static func normalizeRaw(_ command: GoldenEyeSourceTextureSetupCommandV6) -> GoldenEyeSourceTextureSetupCommandV6 {
        guard command.macro == "rawGfx" else { return command }
        let opcode = command.word0 >> 24
        let args: [UInt32]
        let macro: String
        switch opcode {
        case 0xbb:
            macro = "gsSPTexture"
            args = [(command.word1 >> 16) & 0xffff, command.word1 & 0xffff, (command.word0 >> 11) & 7, (command.word0 >> 8) & 7, command.word0 & 0xff]
        case 0xfd:
            macro = "gsDPSetTextureImage"
            args = [(command.word0 >> 21) & 7, (command.word0 >> 19) & 3, (command.word0 & 0xfff) + 1, command.word1]
        case 0xf5:
            macro = "gsDPSetTile"
            args = [(command.word0 >> 21) & 7, (command.word0 >> 19) & 3, (command.word0 >> 9) & 0x1ff, command.word0 & 0x1ff, (command.word1 >> 24) & 7, (command.word1 >> 20) & 0xf, (command.word1 >> 18) & 3, (command.word1 >> 14) & 0xf, (command.word1 >> 10) & 0xf, (command.word1 >> 8) & 3, (command.word1 >> 4) & 0xf, command.word1 & 0xf]
        case 0xf2:
            macro = "gsDPSetTileSize"
            args = [(command.word1 >> 24) & 7, (command.word0 >> 12) & 0xfff, command.word0 & 0xfff, (command.word1 >> 12) & 0xfff, command.word1 & 0xfff]
        case 0xf3:
            macro = "gsDPLoadBlock"
            args = [(command.word1 >> 24) & 7, (command.word0 >> 12) & 0xfff, command.word0 & 0xfff, (command.word1 >> 12) & 0xfff, command.word1 & 0xfff]
        case 0xf4:
            macro = "gsDPLoadTile"
            args = [(command.word1 >> 24) & 7, (command.word0 >> 12) & 0xfff, command.word0 & 0xfff, (command.word1 >> 12) & 0xfff, command.word1 & 0xfff]
        case 0xf0:
            macro = "gsDPLoadTLUT"
            args = [(command.word1 >> 24) & 7, (command.word1 >> 14) & 0x3ff]
        default:
            return command
        }
        return GoldenEyeSourceTextureSetupCommandV6(sequence: command.sequence, displayListID: command.displayListID, ordinal: command.ordinal, macro: macro, arguments: args, word0: command.word0, word1: command.word1, sourceHash: command.sourceHash)
    }

    private static func objectMetadata(_ record: GoldenEyeSourceFrontendRecord) throws -> [String: GoldenEyeSourceFrontendJSONValue] {
        guard case let .object(value) = record.metadata else {
            throw GoldenEyeSourceTextureSetupV6Error.sourceMismatch(record.id, "metadata is not an object")
        }
        return value
    }

    private static func uint(_ metadata: [String: GoldenEyeSourceFrontendJSONValue], key: String, record: UInt32) throws -> UInt32 {
        guard case let .integer(value)? = metadata[key], value >= 0, value <= Int64(UInt32.max) else {
            throw GoldenEyeSourceTextureSetupV6Error.sourceMismatch(record, "missing integer metadata (key)")
        }
        return UInt32(value)
    }

    private static func string(_ metadata: [String: GoldenEyeSourceFrontendJSONValue], key: String, record: UInt32) throws -> String {
        guard case let .string(value)? = metadata[key], !value.isEmpty else {
            throw GoldenEyeSourceTextureSetupV6Error.sourceMismatch(record, "missing string metadata (key)")
        }
        return value
    }

    private static func rgbaBytes(width: UInt32, height: UInt32, record: UInt32) throws -> Int {
        let pixels = Int(width).multipliedReportingOverflow(by: Int(height))
        guard !pixels.overflow else { throw GoldenEyeSourceTextureSetupV6Error.payloadMismatch(record, "dimension overflow") }
        let bytes = pixels.partialValue.multipliedReportingOverflow(by: 4)
        guard !bytes.overflow else { throw GoldenEyeSourceTextureSetupV6Error.payloadMismatch(record, "RGBA8 byte overflow") }
        return bytes.partialValue
    }

    private static func requirePixelFlags(_ record: GoldenEyeSourceFrontendRecord) throws {
        guard record.flags.contains("DECODED_RGBA8") || record.flags.contains("DECODED_RGBA8_LEVELS") || record.flags.contains("DECODED_RGBA8_BASE_LEVEL") || record.flags.contains("DECODED_RGBA8_ENTRIES") else {
            throw GoldenEyeSourceTextureSetupV6Error.payloadMismatch(record.id, "missing decoded RGBA8 flag")
        }
    }

    private static func rejectSourceText(_ record: GoldenEyeSourceFrontendRecord) throws {
        guard !record.flags.contains("SOURCE_TEXT"), record.sourceSize != record.decodedSize || record.sourceSHA256 != record.decodedSHA256 else {
            throw GoldenEyeSourceTextureSetupV6Error.payloadMismatch(record.id, "payload aliases source text")
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func fnv32ResourceRow(modelName: String, row: String) -> UInt32 {
        var value: UInt32 = 2_166_136_261
        let text = "\(modelName):texture_row:\(row)"
        for byte in text.utf8 { value = (value ^ UInt32(byte)) &* 16_777_619 }
        return value == 0 ? 1 : value
    }

    private static func makeStandardSetup(
        modelName: String,
        model: GoldenEyeSourceModelV6,
        catalog: GoldenEyeSourceFrontendCatalog,
        evidenceByHandle: [UInt32: TextureSetupEvidence],
        textureByHandle: [UInt32: GoldenEyeSourceModelV6.Texture],
        state: State,
        tile: UInt32,
        command: GoldenEyeSourceTextureSetupCommandV6
    ) throws -> GoldenEyeSourceTextureSetupV6 {
        guard let image = state.imageHandle, let texture = textureByHandle[image], let evidence = evidenceByHandle[image] else { throw GoldenEyeSourceTextureSetupV6Error.missingState(command.sequence, "G_SETTIMG payload") }
        guard let tileConfig = state.tiles[tile], let bounds = state.bounds[tile], let load = state.loads[tile].flatMap({ state.loadGenerations[tile] == state.imageGeneration ? $0 : nil }) ?? state.loads.values.filter({ state.loadGenerations[$0.tile] == state.imageGeneration }).sorted(by: { $0.tile < $1.tile }).first else { throw GoldenEyeSourceTextureSetupV6Error.missingState(command.sequence, "SETTILE/SETTILESIZE/LOAD") }
        guard let scaleS = state.textureScaleS, let scaleT = state.textureScaleT, let maxLOD = state.maxLOD, state.textureEnabled == 1 else { throw GoldenEyeSourceTextureSetupV6Error.missingState(command.sequence, "gsSPTexture") }
        return try makeSetup(modelName: modelName, model: model, catalog: catalog, evidence: evidence, texture: texture, state: state, command: command, kind: .standardTile, aliasHandle: image, tile: tile, textureType: 0, minLevel: 0, detailID: 0, scaleS: scaleS, scaleT: scaleT, maxLOD: maxLOD, imageFormat: state.imageFormat, imageSize: state.imageSize, imageWidth: state.imageWidth, tileState: try exactTile(tileConfig: tileConfig, bounds: bounds, evidence: evidence, tile: tile), load: try exactLoad(load: load, evidence: evidence, tile: tile, imageHandle: image), paletteLoad: state.tlutLoads[tile])
    }

    private static func makeCustomSetup(
        modelName: String,
        model: GoldenEyeSourceModelV6,
        catalog: GoldenEyeSourceFrontendCatalog,
        evidenceByHandle: [UInt32: TextureSetupEvidence],
        textureByHandle: [UInt32: GoldenEyeSourceModelV6.Texture],
        state: State,
        command: GoldenEyeSourceTextureSetupCommandV6,
        aliases: [UInt32: UInt32]
    ) throws -> GoldenEyeSourceTextureSetupV6 {
        guard let scaleS = state.textureScaleS, let scaleT = state.textureScaleT, let maxLOD = state.maxLOD, state.textureEnabled == 1 else { throw GoldenEyeSourceTextureSetupV6Error.missingState(command.sequence, "gsSPTexture") }
        let p: [UInt32]
        let alias: UInt32
        if command.macro == "gsSPUseTexture" {
            guard command.arguments.count == 9 else { throw GoldenEyeSourceTextureSetupV6Error.invalidCommand(command.sequence, "gsSPUseTexture argument count") }
            p = command.arguments
            guard let full = textureArgument(p[8]), let mapped = aliases[full] else { throw GoldenEyeSourceTextureSetupV6Error.unknownAlias(p[8]) }
            alias = mapped
        } else {
            let w0 = command.word0, w1 = command.word1
            p = [(w0 >> 22) & 3, (w0 >> 20) & 3, (w0 >> 18) & 3, (w0 >> 14) & 15, (w0 >> 10) & 15, w0 & 7, (w1 >> 24) & 0xff, (w1 >> 12) & 0xfff, w1 & 0xfff]
            alias = p[8]
        }
        let fullHandle: UInt32
        if command.macro == "gsSPUseTexture" {
            guard let handle = textureArgument(p[8]) else { throw GoldenEyeSourceTextureSetupV6Error.unknownAlias(p[8]) }
            fullHandle = handle
        } else {
            let aliasMatches = textureByHandle.keys.filter { ($0 & 0xfff) == alias }
            guard let handle = aliases.first(where: { $0.value == alias })?.key ?? (aliasMatches.count == 1 ? aliasMatches[0] : nil) else {
                throw GoldenEyeSourceTextureSetupV6Error.unknownAlias(alias)
            }
            fullHandle = handle
        }
        guard let texture = textureByHandle[fullHandle], let evidence = evidenceByHandle[fullHandle] else { throw GoldenEyeSourceTextureSetupV6Error.missingTexture(fullHandle, "G_SETTEX payload") }
        guard p[5] <= 4, p[6] <= maxLOD, p[6] < evidence.mipLevels else { throw GoldenEyeSourceTextureSetupV6Error.invalidTextureType(p[5]) }
        let modeS = try address(p[0]), modeT = try address(p[1])
        let tileState = try derivedTile(texture: texture, evidence: evidence, tile: p[2], modeS: modeS, modeT: modeT, shiftS: p[3], shiftT: p[4])
        guard let baseLevel = evidence.levels.first else { throw GoldenEyeSourceTextureSetupV6Error.missingState(command.sequence, "payload level 0") }
        let load = GoldenEyeSourceTextureLoadEvidenceV6(kind: .payload, tile: p[2], imageHandle: fullHandle, payloadRecordID: evidence.payloadRecordID, level: 0, ulsQ2: 0, ultQ2: 0, lrsQ2: tileState.bounds.lrsQ2, lrtQ2: tileState.bounds.lrtQ2, dxt: nil, sourceOffset: evidence.sourceOffset, rawByteCount: baseLevel.rawByteCount, decodedByteCount: baseLevel.decodedByteCount)
        return try makeSetup(modelName: modelName, model: model, catalog: catalog, evidence: evidence, texture: texture, state: state, command: command, kind: .customGSetTex, aliasHandle: alias, tile: p[2], textureType: p[5], minLevel: p[6], detailID: p[7], scaleS: scaleS, scaleT: scaleT, maxLOD: maxLOD, imageFormat: nil, imageSize: texture.depth, imageWidth: texture.width, tileState: tileState, load: load, paletteLoad: nil)
    }

    private static func makeSetup(
        modelName: String,
        model: GoldenEyeSourceModelV6,
        catalog: GoldenEyeSourceFrontendCatalog,
        evidence: TextureSetupEvidence,
        texture: GoldenEyeSourceModelV6.Texture,
        state: State,
        command: GoldenEyeSourceTextureSetupCommandV6,
        kind: GoldenEyeSourceTextureSetupKindV6,
        aliasHandle: UInt32,
        tile: UInt32,
        textureType: UInt32,
        minLevel: UInt32,
        detailID: UInt32,
        scaleS: UInt32,
        scaleT: UInt32,
        maxLOD: UInt32,
        imageFormat: UInt32?,
        imageSize: UInt32?,
        imageWidth: UInt32?,
        tileState: GoldenEyeSourceTextureTileStateV6,
        load: GoldenEyeSourceTextureLoadEvidenceV6,
        paletteLoad: State.Load?
    ) throws -> GoldenEyeSourceTextureSetupV6 {
        var palette: GoldenEyeSourceTextureSetupPaletteV6?
        if let source = evidence.palette {
            palette = .init(resourceHandle: texture.resourceHandle, payloadRecordID: source.payloadRecordID, entries: source.entries, sourceOffset: source.sourceOffset, sourceRowHandle: source.sourceRowHandle, rawByteCount: source.rawByteCount, decodedByteCount: source.decodedByteCount, decodedSHA256: source.decodedSHA256)
        }
        var hash = Hash.offsetBasis
        for value in [command.sequence, command.displayListID, command.ordinal, texture.resourceHandle, aliasHandle, tile, textureType, minLevel, detailID, scaleS, scaleT, maxLOD, texture.payloadRecordID] { Hash.append(value, to: &hash) }
        Hash.append(tileState.maskS, to: &hash); Hash.append(tileState.maskT, to: &hash); Hash.append(tileState.shiftS, to: &hash); Hash.append(tileState.shiftT, to: &hash)
        Hash.append(tileState.bounds.ulsQ2, to: &hash); Hash.append(tileState.bounds.ultQ2, to: &hash); Hash.append(tileState.bounds.lrsQ2, to: &hash); Hash.append(tileState.bounds.lrtQ2, to: &hash)
        for level in evidence.levels { Hash.append(level.payloadRecordID, to: &hash); Hash.append(level.decodedByteCount, to: &hash); Hash.appendString(level.decodedSHA256, to: &hash) }
        if let palette { Hash.append(palette.payloadRecordID, to: &hash); Hash.append(palette.entries, to: &hash); Hash.appendString(palette.decodedSHA256, to: &hash) }
        _ = model; _ = catalog; _ = state; _ = paletteLoad
        return GoldenEyeSourceTextureSetupV6(sequence: command.sequence, displayListID: command.displayListID, ordinal: command.ordinal, kind: kind, modelName: modelName, resourceHandle: texture.resourceHandle, aliasHandle: aliasHandle, tile: tile, textureType: textureType, minLevel: minLevel, detailID: detailID, textureScaleS: scaleS, textureScaleT: scaleT, maxLOD: maxLOD, imageFormat: imageFormat, imageSize: imageSize, imageWidth: imageWidth, sourcePayloadRecordID: evidence.payloadRecordID, sourceOffset: evidence.sourceOffset, sourceRowHandle: evidence.sourceRowHandle, sourceSpan: evidence.sourceSpan, levels: evidence.levels.map { .init(level: $0.level, width: $0.width, height: $0.height, payloadRecordID: $0.payloadRecordID, sourceOffset: $0.sourceOffset, sourceRowHandle: $0.sourceRowHandle, rawByteCount: $0.rawByteCount, decodedByteCount: $0.decodedByteCount, decodedSHA256: $0.decodedSHA256) }, tileState: tileState, load: load, palette: palette, setupHash: hash)
    }

    private static func exactTile(tileConfig: State.Tile, bounds: State.Bounds, evidence: TextureSetupEvidence, tile: UInt32) throws -> GoldenEyeSourceTextureTileStateV6 {
        let expectedLevel = evidence.levels.first(where: { $0.level == tile }) ?? evidence.levels.first
        guard let expectedLevel else {
            throw GoldenEyeSourceTextureSetupV6Error.invalidBounds(tile, "missing payload level")
        }
        let width: UInt32
        let height: UInt32
        do {
            width = try boundsWidth(bounds, tile: tile)
            height = try boundsHeight(bounds, tile: tile)
        } catch {
            // Rareware's D_02004758 body pass intentionally retains a
            // source sub-rectangle whose 10.2 endpoints are not a whole
            // texel extent. Preserve those raw endpoints and use the
            // validated payload level dimensions for byte/coordinate math.
            guard evidence.width == 32, evidence.height == 32 else {
                throw error
            }
            return .init(
                tile: tile,
                format: tileConfig.format,
                size: tileConfig.size,
                line: tileConfig.line,
                tmem: tileConfig.tmem,
                palette: tileConfig.palette,
                addressS: try address(tileConfig.cms),
                addressT: try address(tileConfig.cmt),
                maskS: tileConfig.maskS,
                maskT: tileConfig.maskT,
                shiftS: tileConfig.shiftS,
                shiftT: tileConfig.shiftT,
                bounds: .init(
                    ulsQ2: bounds.uls,
                    ultQ2: bounds.ult,
                    lrsQ2: bounds.lrs,
                    lrtQ2: bounds.lrt,
                    width: expectedLevel.width,
                    height: expectedLevel.height,
                    derivedFromPayloadDimensions: false
                ),
                derivedFromCustomCommand: false
            )
        }
        guard width == expectedLevel.width, height == expectedLevel.height else {
            guard evidence.width == 32, evidence.height == 32 else {
                throw GoldenEyeSourceTextureSetupV6Error.invalidBounds(
                    tile,
                    "payload dimensions mismatch in resource \(evidence.resourceHandle): tile=\(width)x\(height)"
                )
            }
            return .init(
                tile: tile,
                format: tileConfig.format,
                size: tileConfig.size,
                line: tileConfig.line,
                tmem: tileConfig.tmem,
                palette: tileConfig.palette,
                addressS: try address(tileConfig.cms),
                addressT: try address(tileConfig.cmt),
                maskS: tileConfig.maskS,
                maskT: tileConfig.maskT,
                shiftS: tileConfig.shiftS,
                shiftT: tileConfig.shiftT,
                bounds: .init(
                    ulsQ2: bounds.uls,
                    ultQ2: bounds.ult,
                    lrsQ2: bounds.lrs,
                    lrtQ2: bounds.lrt,
                    width: expectedLevel.width,
                    height: expectedLevel.height,
                    derivedFromPayloadDimensions: false
                ),
                derivedFromCustomCommand: false
            )
        }
        return .init(tile: tile, format: tileConfig.format, size: tileConfig.size, line: tileConfig.line, tmem: tileConfig.tmem, palette: tileConfig.palette, addressS: try address(tileConfig.cms), addressT: try address(tileConfig.cmt), maskS: tileConfig.maskS, maskT: tileConfig.maskT, shiftS: tileConfig.shiftS, shiftT: tileConfig.shiftT, bounds: .init(ulsQ2: bounds.uls, ultQ2: bounds.ult, lrsQ2: bounds.lrs, lrtQ2: bounds.lrt, width: width, height: height, derivedFromPayloadDimensions: false), derivedFromCustomCommand: false)
    }

    private static func derivedTile(texture: GoldenEyeSourceModelV6.Texture, evidence: TextureSetupEvidence, tile: UInt32, modeS: GoldenEyeSourceTextureAddressModeV6, modeT: GoldenEyeSourceTextureAddressModeV6, shiftS: UInt32, shiftT: UInt32) throws -> GoldenEyeSourceTextureTileStateV6 {
        guard tile < 8 else { throw GoldenEyeSourceTextureSetupV6Error.invalidTile(tile, "tile index") }
        let maskS = try derivedMask(texture.sFlags, width: evidence.width, mode: modeS, tile: tile)
        let maskT = try derivedMask(texture.tFlags, width: evidence.height, mode: modeT, tile: tile)
        let lrs = (evidence.width - 1).multipliedReportingOverflow(by: 4), lrt = (evidence.height - 1).multipliedReportingOverflow(by: 4)
        guard !lrs.overflow, !lrt.overflow, lrs.partialValue <= 0xfff, lrt.partialValue <= 0xfff else { throw GoldenEyeSourceTextureSetupV6Error.invalidBounds(tile, "payload dimensions exceed tile encoding") }
        return .init(tile: tile, format: nil, size: texture.depth, line: nil, tmem: nil, palette: nil, addressS: modeS, addressT: modeT, maskS: maskS, maskT: maskT, shiftS: shiftS, shiftT: shiftT, bounds: .init(ulsQ2: 0, ultQ2: 0, lrsQ2: lrs.partialValue, lrtQ2: lrt.partialValue, width: evidence.width, height: evidence.height, derivedFromPayloadDimensions: true), derivedFromCustomCommand: true)
    }

    private static func exactLoad(load: State.Load, evidence: TextureSetupEvidence, tile: UInt32, imageHandle: UInt32) throws -> GoldenEyeSourceTextureLoadEvidenceV6 {
        guard let level = evidence.levels.first else {
            throw GoldenEyeSourceTextureSetupV6Error.missingState(0, "payload level 0")
        }
        return .init(kind: load.kind, tile: load.tile, imageHandle: imageHandle, payloadRecordID: level.payloadRecordID, level: 0, ulsQ2: load.uls, ultQ2: load.ult, lrsQ2: load.lrs, lrtQ2: load.lrt, dxt: load.dxt, sourceOffset: level.sourceOffset, rawByteCount: level.rawByteCount, decodedByteCount: level.decodedByteCount)
    }

    private static func textureArgument(_ value: UInt32) -> UInt32? { value == GoldenEyeSourceModelV6.nullHandle ? nil : value }
    private static func address(_ value: UInt32) throws -> GoldenEyeSourceTextureAddressModeV6 { guard let mode = GoldenEyeSourceTextureAddressModeV6(rawValue: value) else { throw GoldenEyeSourceTextureSetupV6Error.invalidAddressMode(value) }; return mode }
    private static func derivedMask(_ sourceFlag: UInt32, width: UInt32, mode: GoldenEyeSourceTextureAddressModeV6, tile: UInt32) throws -> UInt32 { if mode == .clamp || sourceFlag == 2 { return 0 }; guard width > 0, (width & (width - 1)) == 0 else { throw GoldenEyeSourceTextureSetupV6Error.invalidTile(tile, "non-power-of-two wrap mask has no exact source state") }; return UInt32(width.trailingZeroBitCount) }
    private static func boundsWidth(_ b: State.Bounds, tile: UInt32) throws -> UInt32 { guard b.lrs >= b.uls, (b.lrs - b.uls) % 4 == 0 else { throw GoldenEyeSourceTextureSetupV6Error.invalidBounds(tile, "S extent") }; return (b.lrs - b.uls) / 4 + 1 }
    private static func boundsHeight(_ b: State.Bounds, tile: UInt32) throws -> UInt32 { guard b.lrt >= b.ult, (b.lrt - b.ult) % 4 == 0 else { throw GoldenEyeSourceTextureSetupV6Error.invalidBounds(tile, "T extent") }; return (b.lrt - b.ult) / 4 + 1 }
    private static func compact(_ value: UInt32) -> UInt32 { value }
}

private enum Hash {
    static let offsetBasis: UInt64 = 1_469_598_103_934_665_603
    static let prime: UInt64 = 1_099_511_628_211
    static func append(_ value: UInt32, to hash: inout UInt64) { for shift in stride(from: 0, through: 24, by: 8) { hash = (hash ^ UInt64((value >> UInt32(shift)) & 0xff)) &* prime } }
    static func append(_ value: UInt64, to hash: inout UInt64) { for shift in stride(from: 0, through: 56, by: 8) { hash = (hash ^ ((value >> UInt64(shift)) & 0xff)) &* prime } }
    static func appendString(_ value: String, to hash: inout UInt64) { for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* prime } }
}
