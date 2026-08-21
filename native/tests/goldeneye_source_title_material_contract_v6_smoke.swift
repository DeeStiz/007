import CryptoKit
import Foundation

private struct ExpectedTitleModel: Sendable {
    let name: String
    let textures: Int
    let mips: Int
    let tluts: Int
    let packetSHA256: String
}

private enum ContractError: Error, CustomStringConvertible {
    case mismatch(String)
    case missingPalette(String)

    var description: String {
        switch self {
        case .mismatch(let detail):
            return "source-title-material-contract mismatch: \(detail)"
        case .missingPalette(let detail):
            return "source-title-material-contract missing palette evidence: \(detail)"
        }
    }
}

private struct StableHasher {
    private var bytes = Data()

    mutating func append(_ value: UInt32) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes.append(contentsOf: $0) }
    }

    mutating func append(_ value: UInt64) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { bytes.append(contentsOf: $0) }
    }

    mutating func append(_ value: String) {
        let utf8 = Array(value.utf8)
        append(UInt32(utf8.count))
        bytes.append(contentsOf: utf8)
    }

    var digest: String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

private struct ContractEvidence {
    let aggregateSHA256: String
    let textureCount: Int
    let mipCount: Int
    let paletteCount: Int
}

private let expectedModels = [
    ExpectedTitleModel(
        name: "legalpage",
        textures: 5,
        mips: 5,
        tluts: 0,
        packetSHA256: "da42f17da9654a83a7c0a7ab3fd3233cc6892434c07cd593227932fb2e545f22"
    ),
    ExpectedTitleModel(
        name: "nintendologo",
        textures: 1,
        mips: 1,
        tluts: 0,
        packetSHA256: "a41b43bf4bab4200156296b31b061c858287076ad895abee1e4dcec640693d97"
    ),
    ExpectedTitleModel(
        name: "goldeneyelogo",
        textures: 2,
        mips: 7,
        tluts: 0,
        packetSHA256: "b73bb84432ad1cd2e821ccc339502a5900571643e0b956ca53d581a5abfee6c1"
    ),
    ExpectedTitleModel(
        name: "walletbond",
        textures: 84,
        mips: 186,
        tluts: 2,
        packetSHA256: "20fde4c360df22c814d0e5c9ee15658e60cd2917f7b1b7820e8bf4ecc3bca29e"
    ),
]

private let expectedCatalogPacketSHA256 =
    "b9247beab28b0e101c471c1a94d0d4baebf8a3ea85e306981bef1365d3e485ad"
private let expectedMaterialAggregateSHA256 =
    "4247163796f6616e44965ad3ad846d5de46311005d75984f9a4a7be9c201d848"

private func require(
    _ condition: @autoclosure () -> Bool,
    _ message: @autoclosure () -> String
) throws {
    guard condition() else { throw ContractError.mismatch(message()) }
}

private func metadataObject(
    _ record: GoldenEyeSourceFrontendRecord
) throws -> [String: GoldenEyeSourceFrontendJSONValue] {
    guard case let .object(value) = record.metadata else {
        throw ContractError.mismatch("record \(record.id) metadata is not an object")
    }
    return value
}

private func metadataUInt(
    _ metadata: [String: GoldenEyeSourceFrontendJSONValue],
    key: String,
    recordID: UInt32
) throws -> UInt32 {
    guard case let .integer(value)? = metadata[key],
          value >= 0,
          value <= Int64(UInt32.max) else {
        throw ContractError.mismatch("record \(recordID) missing integer metadata \(key)")
    }
    return UInt32(value)
}

private func metadataString(
    _ metadata: [String: GoldenEyeSourceFrontendJSONValue],
    key: String,
    recordID: UInt32
) throws -> String {
    guard case let .string(value)? = metadata[key], !value.isEmpty else {
        throw ContractError.mismatch("record \(recordID) missing string metadata \(key)")
    }
    return value
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func payloadRecord(
    catalog: GoldenEyeSourceFrontendCatalog,
    id: UInt32,
    context: String
) throws -> GoldenEyeSourceFrontendRecord {
    guard let record = catalog.record(id: id) else {
        throw ContractError.mismatch("\(context) payload record \(id) is missing")
    }
    guard record.category == "texture_payload" || record.category == "mip_payload" else {
        throw ContractError.mismatch(
            "\(context) payload record \(id) has category \(record.category)"
        )
    }
    return record
}

private func paletteRecord(
    catalog: GoldenEyeSourceFrontendCatalog,
    id: UInt32,
    context: String
) throws -> GoldenEyeSourceFrontendRecord {
    guard let record = catalog.record(id: id), record.category == "tlut_payload" else {
        throw ContractError.mismatch("\(context) TLUT payload record \(id) is missing or has the wrong category")
    }
    return record
}

private func descriptorWithoutPalette(
    _ descriptor: GoldenEyeSourceTextureDescriptorV6
) -> GoldenEyeSourceTextureDescriptorV6 {
    GoldenEyeSourceTextureDescriptorV6(
        modelName: descriptor.modelName,
        family: descriptor.family,
        resourceHandle: descriptor.resourceHandle,
        width: descriptor.width,
        height: descriptor.height,
        mipLevels: descriptor.mipLevels,
        payloadRecordID: descriptor.payloadRecordID,
        payloadDecodedSHA256: descriptor.payloadDecodedSHA256,
        sourceOffset: descriptor.sourceOffset,
        sourceRowHandle: descriptor.sourceRowHandle,
        sourceSpan: descriptor.sourceSpan,
        levels: descriptor.levels,
        palette: nil,
        mipDimensionMode: descriptor.mipDimensionMode
    )
}

private func validateMaterialContract(
    catalog: GoldenEyeSourceFrontendCatalog,
    models: [(name: String, model: GoldenEyeSourceModelV6)],
    descriptors: [GoldenEyeSourceTextureDescriptorV6]
) throws -> ContractEvidence {
    let expectedByName = Dictionary(uniqueKeysWithValues: expectedModels.map { ($0.name, $0) })
    let descriptorByHandle = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.resourceHandle, $0) })
    var seenMips = Set<String>()
    var seenPalettes = Set<UInt32>()
    var hasher = StableHasher()
    var textureCount = 0
    var mipCount = 0

    for pair in models.sorted(by: { $0.name < $1.name }) {
        guard let expected = expectedByName[pair.name] else {
            throw ContractError.mismatch("unexpected title model \(pair.name)")
        }
        let model = pair.model
        try require(model.header.counts.textures == expected.textures, "\(pair.name) texture count \(model.header.counts.textures) != \(expected.textures)")
        try require(model.header.counts.mips == expected.mips, "\(pair.name) mip count \(model.header.counts.mips) != \(expected.mips)")
        try require(model.header.counts.tluts == expected.tluts, "\(pair.name) TLUT count \(model.header.counts.tluts) != \(expected.tluts)")

        hasher.append(pair.name)
        hasher.append(model.header.packetHash.map { String(format: "%02x", $0) }.joined())
        hasher.append(UInt32(model.textures.count))
        hasher.append(UInt32(model.mips.count))
        hasher.append(UInt32(model.tluts.count))

        for texture in model.textures.sorted(by: { $0.index < $1.index }) {
            guard let descriptor = descriptorByHandle[texture.resourceHandle] else {
                throw ContractError.mismatch("\(pair.name) texture \(texture.index) descriptor is missing")
            }
            textureCount += 1
            try require(descriptor.modelName == pair.name, "descriptor model mismatch for handle \(texture.resourceHandle)")
            try require(descriptor.width == texture.width && descriptor.height == texture.height, "\(pair.name) texture \(texture.index) dimensions")
            try require(descriptor.mipLevels == texture.mipCount, "\(pair.name) texture \(texture.index) mip count")
            try require(descriptor.payloadRecordID == texture.payloadRecordID, "\(pair.name) texture \(texture.index) base payload identity")
            try require(descriptor.sourceOffset == texture.sourceOffset, "\(pair.name) texture \(texture.index) source offset")
            try require(descriptor.sourceRowHandle == texture.sourceRowHandle, "\(pair.name) texture \(texture.index) source row")
            try require(descriptor.sourceSpan == texture.sourceSpan, "\(pair.name) texture \(texture.index) source span")
            try require(descriptor.levels.map(\.level) == Array(0..<texture.mipCount), "\(pair.name) texture \(texture.index) level ordering")

            let baseRecord = try payloadRecord(
                catalog: catalog,
                id: descriptor.payloadRecordID,
                context: "\(pair.name) texture \(texture.index)"
            )
            try require(!descriptor.payloadDecodedSHA256.isEmpty, "\(pair.name) texture \(texture.index) base decoded hash is empty")
            try require(descriptor.payloadDecodedSHA256 == baseRecord.decodedSHA256, "\(pair.name) texture \(texture.index) base decoded hash")

            for level in descriptor.levels.sorted(by: { $0.level < $1.level }) {
                let mipIndex = Int(texture.mipStart) + Int(level.level)
                guard mipIndex >= 0, mipIndex < model.mips.count else {
                    throw ContractError.mismatch("\(pair.name) texture \(texture.index) mip range")
                }
                let mip = model.mips[mipIndex]
                let mipKey = "\(pair.name):\(texture.index):\(level.level)"
                try require(seenMips.insert(mipKey).inserted, "duplicate mip provenance \(mipKey)")
                try require(mip.textureIndex == texture.index && mip.level == level.level, "\(mipKey) GESM mip relationship")
                try require(mip.resourceHandle == texture.resourceHandle, "\(mipKey) resource handle")
                try require(mip.sourceRecordID == texture.payloadRecordID, "\(mipKey) source record")
                try require(level.payloadRecordID == mip.payloadRecordID, "\(mipKey) payload record")
                try require(level.width == mip.width && level.height == mip.height, "\(mipKey) dimensions")
                try require(level.sourceOffset == mip.sourceOffset, "\(mipKey) source offset")
                try require(level.sourceRowHandle == mip.sourceRowHandle, "\(mipKey) source row")
                try require(level.rawByteCount == mip.rawByteCount, "\(mipKey) raw byte count")
                try require(level.decodedByteCount == mip.decodedByteCount, "\(mipKey) decoded byte count")
                try require(level.decoded.count == Int(level.decodedByteCount), "\(mipKey) copied decoded byte count")

                let record = try payloadRecord(catalog: catalog, id: level.payloadRecordID, context: mipKey)
                try require(record.flags.contains(where: {
                    $0 == "DECODED_RGBA8" || $0 == "DECODED_RGBA8_LEVELS" || $0 == "DECODED_RGBA8_BASE_LEVEL"
                }), "\(mipKey) lacks decoded RGBA8 provenance")
                let metadata = try metadataObject(record)
                let metadataWidth = try metadataUInt(metadata, key: "width", recordID: record.id)
                let metadataHeight = try metadataUInt(metadata, key: "height", recordID: record.id)
                let metadataSourceOffset = try metadataUInt(metadata, key: "source_offset", recordID: record.id)
                let metadataSourceRow = try metadataString(metadata, key: "source_row", recordID: record.id)
                try require(metadataWidth == level.width, "\(mipKey) metadata width")
                try require(metadataHeight == level.height, "\(mipKey) metadata height")
                try require(metadataSourceOffset == level.sourceOffset, "\(mipKey) metadata source offset")
                try require(!metadataSourceRow.isEmpty, "\(mipKey) metadata source row")
                if level.level > 0 {
                    let metadataLevel = try metadataUInt(metadata, key: "level", recordID: record.id)
                    try require(metadataLevel == level.level, "\(mipKey) metadata level")
                }

                let decoded = try catalog.copyOut(.decoded, recordID: level.payloadRecordID)
                let decodedHash = sha256(decoded)
                try require(decoded == level.decoded, "\(mipKey) copied payload differs from descriptor")
                try require(decodedHash == record.decodedSHA256, "\(mipKey) catalog decoded hash")
                try require(decodedHash == level.decodedSHA256, "\(mipKey) descriptor decoded hash")

                hasher.append(UInt32(texture.index))
                hasher.append(texture.resourceHandle)
                hasher.append(level.level)
                hasher.append(level.width)
                hasher.append(level.height)
                hasher.append(level.payloadRecordID)
                hasher.append(level.sourceOffset)
                hasher.append(level.sourceRowHandle)
                hasher.append(level.rawByteCount)
                hasher.append(level.decodedByteCount)
                hasher.append(record.category)
                hasher.append(record.decodedSHA256)
                hasher.append(level.decodedSHA256)
                mipCount += 1
            }

            if texture.tlutIndex == GoldenEyeSourceModelV6.nullHandle {
                try require(descriptor.palette == nil, "\(pair.name) texture \(texture.index) has unexpected palette evidence")
            } else {
                let tlutIndex = Int(texture.tlutIndex)
                try require(tlutIndex < model.tluts.count, "\(pair.name) texture \(texture.index) TLUT index")
                guard let palette = descriptor.palette else {
                    throw ContractError.missingPalette("\(pair.name) texture \(texture.index)")
                }
                let tlut = model.tluts[tlutIndex]
                try require(tlut.textureIndex == texture.index, "\(pair.name) texture \(texture.index) TLUT texture index \(tlut.textureIndex)")
                try require(tlut.resourceHandle == texture.resourceHandle, "\(pair.name) texture \(texture.index) TLUT resource handle")
                try require(tlut.sourceRecordID == texture.payloadRecordID, "\(pair.name) texture \(texture.index) TLUT source record")
                try require(palette.resourceHandle == texture.resourceHandle, "\(pair.name) texture \(texture.index) palette handle")
                try require(palette.payloadRecordID == tlut.payloadRecordID, "\(pair.name) texture \(texture.index) palette payload")
                try require(palette.sourceRowHandle == tlut.sourceRowHandle, "\(pair.name) texture \(texture.index) palette source row")
                try require(palette.rawByteCount == tlut.rawByteCount, "\(pair.name) texture \(texture.index) palette raw byte count")
                try require(seenPalettes.insert(palette.resourceHandle).inserted, "duplicate palette provenance for \(pair.name) texture \(texture.index)")

                let record = try paletteRecord(catalog: catalog, id: palette.payloadRecordID, context: "\(pair.name) texture \(texture.index)")
                try require(record.flags.contains("PD_TLUT"), "\(pair.name) texture \(texture.index) lacks PD_TLUT provenance")
                try require(record.flags.contains("DECODED_RGBA8_ENTRIES"), "\(pair.name) texture \(texture.index) lacks decoded TLUT provenance")
                let metadata = try metadataObject(record)
                let entries = try metadataUInt(metadata, key: "entries", recordID: record.id)
                try require(Int(entries) * 4 == Int(record.decodedSize), "\(pair.name) texture \(texture.index) palette decoded size")
                let decoded = try catalog.copyOut(.decoded, recordID: palette.payloadRecordID)
                let decodedHash = sha256(decoded)
                try require(decoded.count == Int(palette.decodedByteCount), "\(pair.name) texture \(texture.index) palette copied size")
                try require(decodedHash == record.decodedSHA256, "\(pair.name) texture \(texture.index) palette decoded hash")
                try require(decodedHash == palette.decodedSHA256, "\(pair.name) texture \(texture.index) descriptor palette hash")

                hasher.append(palette.resourceHandle)
                hasher.append(palette.payloadRecordID)
                hasher.append(palette.sourceRowHandle)
                hasher.append(palette.rawByteCount)
                hasher.append(palette.decodedByteCount)
                hasher.append(entries)
                hasher.append(record.decodedSHA256)
            }
        }
    }

    try require(textureCount == expectedModels.reduce(0) { $0 + $1.textures }, "aggregate texture count \(textureCount)")
    try require(mipCount == expectedModels.reduce(0) { $0 + $1.mips }, "aggregate mip count \(mipCount)")
    try require(seenMips.count == mipCount, "not every GESM mip was visited")
    try require(seenPalettes.count == expectedModels.reduce(0) { $0 + $1.tluts }, "aggregate palette count \(seenPalettes.count)")
    return ContractEvidence(
        aggregateSHA256: hasher.digest,
        textureCount: textureCount,
        mipCount: mipCount,
        paletteCount: seenPalettes.count
    )
}

@main
struct GoldenEyeSourceTitleMaterialContractV6Smoke {
    static func main() throws {
        let root = URL(
            fileURLWithPath: CommandLine.arguments.dropFirst().first
                ?? ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_SOURCE_FRONTEND_ROOT"]
                ?? "build/native/source-frontend-v6",
            isDirectory: true
        )
        let catalog = try GoldenEyeSourceFrontendCatalog.load(preparedAssetRoot: root)
        try require(catalog.packetSHA256 == expectedCatalogPacketSHA256, "catalog packet hash \(catalog.packetSHA256)")
        try require(catalog.manifest.runtimeROMAccess == false, "catalog permits runtime ROM access")
        try require(catalog.manifest.romCopiedIntoCheckout == false, "ROM copied into checkout")
        try require(catalog.manifest.romCopiedIntoBundle == false, "ROM copied into bundle")

        let models = try expectedModels.map { expected -> (name: String, model: GoldenEyeSourceModelV6) in
            let url = root.appendingPathComponent("\(expected.name).gesm", isDirectory: false)
            let model = try GoldenEyeSourceModelV6.load(
                data: Data(contentsOf: url, options: [.mappedIfSafe]),
                modelName: expected.name
            )
            try require(
                model.header.packetHash.map { String(format: "%02x", $0) }.joined() == expected.packetSHA256,
                "\(expected.name) packet hash"
            )
            return (name: expected.name, model: model)
        }
        let plan = try GoldenEyeSourceTextureUploadPlanV6.make(catalog: catalog, models: models)
        let first = try validateMaterialContract(catalog: catalog, models: models, descriptors: plan.descriptors)
        let second = try validateMaterialContract(catalog: catalog, models: models, descriptors: plan.descriptors)
        try require(first.aggregateSHA256 == second.aggregateSHA256, "material aggregate hash is not deterministic")
        try require(first.aggregateSHA256 == expectedMaterialAggregateSHA256, "material aggregate hash \(first.aggregateSHA256)")

        let descriptorsByName = Dictionary(grouping: plan.descriptors, by: \.modelName)
        for expected in expectedModels {
            try require(descriptorsByName[expected.name]?.count == expected.textures, "\(expected.name) descriptor count")
        }
        try require(plan.descriptors.count == 92, "title descriptor count \(plan.descriptors.count)")
        try require(plan.levelRanges.count == 199, "title level range count \(plan.levelRanges.count)")
        try require(plan.paletteEvidence.count == 2, "title palette evidence count \(plan.paletteEvidence.count)")
        try require(first.textureCount == 92 && first.mipCount == 199 && first.paletteCount == 2, "title aggregate evidence counts")

        var missingPaletteDescriptors = plan.descriptors
        guard let paletteIndex = missingPaletteDescriptors.firstIndex(where: { $0.modelName == "walletbond" && $0.palette != nil }) else {
            throw ContractError.mismatch("Wallet has no palette descriptor to exercise fail-closed validation")
        }
        missingPaletteDescriptors[paletteIndex] = descriptorWithoutPalette(missingPaletteDescriptors[paletteIndex])
        do {
            _ = try validateMaterialContract(
                catalog: catalog,
                models: models,
                descriptors: missingPaletteDescriptors
            )
            throw ContractError.mismatch("missing Wallet palette evidence was accepted")
        } catch ContractError.missingPalette {
            // Expected fail-closed negative path.
        }

        print(
            "goldeneye_source_title_material_contract_v6_smoke: PASS "
                + "textures=\(first.textureCount) mips=\(first.mipCount) "
                + "tluts=\(first.paletteCount) aggregate=\(first.aggregateSHA256) "
                + "gpuTLUTConsumption=not_claimed"
        )
    }
}
