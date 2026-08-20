import CryptoKit
import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Loader for the additive source-command -> IMAGE preparation sidecar.
///
/// The manifest is private build output, not a public ABI record.  This
/// loader immediately copies its bounded metadata and decoded RGBA8 payloads
/// into value-only Swift records.  Runtime never opens the ROM or consults a
/// checked-in source path.  Stage texture handles occupy their own namespace
/// so the title GESM resources and the RAMROM stage resources can share the
/// existing resident Metal texture store without aliasing.
struct GoldenEyeStageTextureCatalogV6: Sendable, Equatable {
    struct Level: Sendable, Equatable {
        let level: UInt32
        let width: UInt32
        let height: UInt32
        let decodedByteCount: UInt32
        let decodedSHA256: String
        let fileName: String
        let inspectionSHA256: String
        let inspectionFileName: String
        let decoded: Data
    }

    struct Palette: Sendable, Equatable {
        let entries: UInt32
        let rawByteCount: UInt32
        let decodedByteCount: UInt32
        let rawSHA256: String
        let decodedSHA256: String
        let sourceOffset: UInt32
        let rawFileName: String
        let decodedFileName: String
        let decoded: Data
    }

    struct Texture: Sendable, Equatable {
        let textureID: UInt32
        let imageName: String
        let declaredBytes: UInt32
        let romOffset: UInt32
        let romBytes: UInt32
        let imageSegmentOffset: UInt32
        let sourceSHA256: String
        let streamFormat: UInt32
        let streamCompression: UInt32
        let visibilityClass: String
        let sourceLevelCount: UInt32
        let sourceRow: String
        let rawFileName: String
        let levels: [Level]
        let palette: Palette?

        var resourceHandle: UInt32 {
            GoldenEyeStageTextureCatalogV6.resourceHandle(textureID: textureID)
        }

        var sourceRowHandle: UInt32 {
            GoldenEyeStageTextureCatalogV6.sourceRowHandle(textureID: textureID)
        }
    }

    enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case missingManifest(URL)
        case invalidManifest(String)
        case invalidRow(String)
        case missingPayload(URL)
        case payloadPathEscapes(URL)
        case payloadSize(String, Int, Int)
        case payloadDigest(String, String, String)
        case unsupportedTextureID(UInt32)
        case duplicateTextureID(UInt32)
        case invalidMipChain(UInt32)
        case invalidPalette(UInt32)
        case invalidResource(UInt32, String)

        var description: String {
            switch self {
            case .missingManifest(let url): return "stage texture manifest is missing: \(url.path)"
            case .invalidManifest(let detail): return "stage texture manifest is invalid: \(detail)"
            case .invalidRow(let detail): return "stage texture manifest row is invalid: \(detail)"
            case .missingPayload(let url): return "stage texture payload is missing: \(url.path)"
            case .payloadPathEscapes(let url): return "stage texture payload escapes prepared root: \(url.path)"
            case .payloadSize(let name, let actual, let expected):
                return "stage texture payload \(name) size \(actual) != \(expected)"
            case .payloadDigest(let name, let expected, let actual):
                return "stage texture payload \(name) digest \(actual) != \(expected)"
            case .unsupportedTextureID(let id): return "stage texture ID is outside the source table: \(id)"
            case .duplicateTextureID(let id): return "duplicate stage texture ID \(id)"
            case .invalidMipChain(let id): return "invalid stage texture mip chain \(id)"
            case .invalidPalette(let id): return "invalid stage texture TLUT \(id)"
            case .invalidResource(let id, let detail): return "invalid stage texture resource \(id): \(detail)"
            }
        }
    }

    static let manifestFileName = "stage-texture-dependencies-manifest.txt"
    static let maxTextureID: UInt32 = 2_697
    static let textureHandlePrefix: UInt32 = 0xD500_0000
    // Keep stage palette resources in the same deterministic namespace as the
    // generic source-scene texture binding adapter (0xA900_0000 | texture
    // handle suffix). The previous B9 prefix made a valid TLUT payload
    // invisible to the renderer's strict palette-resource lookup.
    static let paletteHandlePrefix: UInt32 = 0xA900_0000
    static let expectedTextureCount = 436
    static let expectedTLUTCount = 248

    let rootURL: URL
    let manifestURL: URL
    let textures: [Texture]
    let manifestValues: [String: String]
    let parsedBindingCount: Int
    let referencedTextureIDs: Set<UInt32>
    let bindingValidationHash: UInt64

    var bindingCount: Int { Int(manifestValues["binding_count"] ?? "-1") ?? -1 }
    var allBindingsPrepared: Bool {
        parsedBindingCount == bindingCount && bindingCount == 3_575
            && referencedTextureIDs.allSatisfy { texture(textureID: $0) != nil }
    }

    /// The source stores some non-power-of-two mip dimensions with the
    /// source's ceil-halving rule (for example 33 -> 17). Metal texture mip
    /// levels use floor-halving (33 -> 16), so those chains require a later
    /// explicit per-level texture path. They remain copied evidence but do
    /// not silently become presentable in the current resident-MTLTexture
    /// slice.
    var unrepresentableMipTextureCount: Int {
        textures.reduce(into: 0) { count, texture in
            if Self.metalMipPrefix(for: texture.levels).count != texture.levels.count {
                count += 1
            }
        }
    }

    var unclassifiedVisibilityTextureCount: Int {
        textures.reduce(into: 0) { count, texture in
            if texture.visibilityClass.hasPrefix("unclassified-") { count += 1 }
        }
    }

    var isGPURepresentable: Bool {
        unrepresentableMipTextureCount == 0 && unclassifiedVisibilityTextureCount == 0
            && allBindingsPrepared
    }

    static func resourceHandle(textureID: UInt32) -> UInt32 {
        textureHandlePrefix | (textureID & 0x0000_0FFF)
    }

    static func paletteResourceHandle(textureID: UInt32) -> UInt32 {
        paletteHandlePrefix | (textureID & 0x00FF_FFFF)
    }

    static func sourceRowHandle(textureID: UInt32) -> UInt32 {
        fnv32("stage:texture_row:\(textureID)")
    }

    static func load(stageAssetRoot rootURL: URL) throws -> Self {
        let root = rootURL.standardizedFileURL
        let manifestURL = root.appendingPathComponent(manifestFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw Error.missingManifest(manifestURL)
        }
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        } catch {
            throw Error.invalidManifest(String(describing: error))
        }
        let lines = data.split(whereSeparator: { $0 == 10 || $0 == 13 })
            .map { String(decoding: $0, as: UTF8.self) }
            .filter { !$0.isEmpty }
        var values: [String: String] = [:]
        var imageLines: [(UInt32, String)] = []
        var commandLines: [(UInt32, String)] = []
        for line in lines {
            guard let separator = line.firstIndex(of: "=") else {
                throw Error.invalidManifest("line has no separator")
            }
            let key = String(line[..<separator])
            let payload = String(line[line.index(after: separator)...])
            if key.hasPrefix("image_"), let id = UInt32(key.dropFirst("image_".count)) {
                imageLines.append((id, payload))
            } else if key.hasPrefix("command_"), let id = UInt32(key.dropFirst("command_".count)) {
                commandLines.append((id, payload))
            } else {
                values[key] = payload
            }
        }

        guard values["manifest_status"] == "PASS",
              values["source_trace_status"] == "PASS",
              values["payload_status"] == "PASS",
              values["runtime_opens_rom"] == "false",
              values["runtime_consumes_prepared_payloads_only"] == "true",
              values["upload_row_order"] == "source",
              values["inspection_row_order"] == "vertical_flip",
              values["external_rom_sha1"] == "abe01e4aeb033b6c0836819f549c791b26cfde83" else {
            throw Error.invalidManifest("provenance or status guard")
        }
        guard Int(values["unique_texture_count"] ?? "-1") == expectedTextureCount,
              Int(values["unique_tlut_count"] ?? "-1") == expectedTLUTCount,
              imageLines.count == expectedTextureCount else {
            throw Error.invalidManifest("texture/TLUT count guard")
        }

        let payloadRoot = root.appendingPathComponent("textures", isDirectory: true)
        var textures: [Texture] = []
        textures.reserveCapacity(imageLines.count)
        var seen = Set<UInt32>()
        for (textureID, payload) in imageLines.sorted(by: { $0.0 < $1.0 }) {
            guard textureID <= maxTextureID else { throw Error.unsupportedTextureID(textureID) }
            guard seen.insert(textureID).inserted else { throw Error.duplicateTextureID(textureID) }
            let (fields, tlutJSON) = splitTLUT(payload)
            let imageName = try required(fields, "name")
            let declaredBytes = try uint(fields, "declared_bytes")
            let romOffset = try uint(fields, "rom_offset")
            let romBytes = try uint(fields, "rom_bytes")
            let imageSegmentOffset = try uint(fields, "image_segment_offset")
            let sourceSHA256 = try required(fields, "source_sha256")
            let streamFormat = try uint(fields, "stream_format")
            let streamCompression = try uint(fields, "stream_compression")
            let visibilityClass = try required(fields, "visibility")
            let sourceLevelCount = try uint(fields, "source_level_count")
            let sourceRow = try required(fields, "source_row")
            let rawFileName = try required(fields, "raw_file")
            guard try uint(fields, "index") == textureID,
                  romBytes == declaredBytes,
                  sourceSHA256.count == 64 else {
                throw Error.invalidRow("image \(textureID) source metadata")
            }
            let raw = try readPayload(
                payloadRoot: payloadRoot,
                fileName: rawFileName,
                expectedBytes: Int(romBytes),
                expectedSHA256: sourceSHA256,
                context: "image \(textureID) raw"
            )
            _ = raw

            let levelText = try required(fields, "levels")
            let levels = try parseLevels(
                levelText,
                payloadRoot: payloadRoot,
                textureID: textureID
            )
            guard let first = levels.first, first.level == 0 else {
                throw Error.invalidRow("image \(textureID) has no base mip")
            }
            guard sourceLevelCount == UInt32(levels.count) else {
                throw Error.invalidMipChain(textureID)
            }
            for level in levels {
                guard level.level < 32 else { throw Error.invalidMipChain(textureID) }
                let expectedWidth = Self.sourceMipDimension(first.width, level: level.level)
                let expectedHeight = Self.sourceMipDimension(first.height, level: level.level)
                guard level.width == expectedWidth,
                      level.height == expectedHeight else {
                    throw Error.invalidRow("image \(textureID) source mip \(level.level) dimensions \(level.width)x\(level.height), expected source \(expectedWidth)x\(expectedHeight)")
                }
            }
            let palette = try parsePalette(
                tlutJSON,
                payloadRoot: payloadRoot,
                textureID: textureID
            )
            textures.append(Texture(
                textureID: textureID,
                imageName: imageName,
                declaredBytes: declaredBytes,
                romOffset: romOffset,
                romBytes: romBytes,
                imageSegmentOffset: imageSegmentOffset,
                sourceSHA256: sourceSHA256,
                streamFormat: streamFormat,
                streamCompression: streamCompression,
                visibilityClass: visibilityClass,
                sourceLevelCount: sourceLevelCount,
                sourceRow: sourceRow,
                rawFileName: rawFileName,
                levels: levels,
                palette: palette
            ))
        }
        guard textures.count == expectedTextureCount else {
            throw Error.invalidManifest("parsed texture count")
        }
        let expectedBindingCount = Int(values["binding_count"] ?? "-1") ?? -1
        guard expectedBindingCount == 3_575,
              commandLines.count == expectedBindingCount,
              commandLines.map(\.0) == Array(0..<UInt32(expectedBindingCount)) else {
            throw Error.invalidManifest("binding count/order guard")
        }
        var referencedTextureIDs = Set<UInt32>()
        var bindingHash: UInt64 = 1_469_598_103_934_665_603
        for (_, payload) in commandLines.sorted(by: { $0.0 < $1.0 }) {
            let fields = parseFields(payload)
            guard let rawTextureID = fields["texture_id"],
                  let textureID = UInt32(rawTextureID), textureID <= maxTextureID else {
                throw Error.invalidManifest("binding texture id")
            }
            referencedTextureIDs.insert(textureID)
            for byte in payload.utf8 {
                bindingHash = (bindingHash ^ UInt64(byte)) &* 1_099_511_628_211
            }
        }
        guard referencedTextureIDs.count <= expectedTextureCount else {
            throw Error.invalidManifest("binding texture set")
        }
        return Self(
            rootURL: root,
            manifestURL: manifestURL,
            textures: textures,
            manifestValues: values,
            parsedBindingCount: commandLines.count,
            referencedTextureIDs: referencedTextureIDs,
            bindingValidationHash: bindingHash == 0 ? 1 : bindingHash
        )
    }

    func texture(textureID: UInt32) -> Texture? {
        textures.first { $0.textureID == textureID }
    }

    /// Converts the copied stage payloads into the existing resident Metal
    /// upload-plan records.  Every level is validated again by the shared
    /// upload-plan validator before a private Metal allocation is created.
    func uploadDescriptors() -> [GoldenEyeSourceTextureDescriptorV6] {
        textures.map { texture in
            let levels = Self.metalMipPrefix(for: texture.levels).map { level in
                GoldenEyeSourceTextureLevelUploadV6(
                    level: level.level,
                    width: level.width,
                    height: level.height,
                    payloadRecordID: 200_000 + texture.textureID * 64 + level.level + 1,
                    sourceOffset: texture.imageSegmentOffset,
                    sourceRowHandle: texture.sourceRowHandle,
                    rawByteCount: level.decodedByteCount,
                    decodedByteCount: level.decodedByteCount,
                    decodedSHA256: level.decodedSHA256,
                    decoded: level.decoded
                )
            }
            let palette = texture.palette.map { palette in
                GoldenEyeSourceTexturePaletteUploadV6(
                    resourceHandle: texture.resourceHandle,
                    entries: palette.entries,
                    payloadRecordID: 300_000 + texture.textureID + 1,
                    sourceOffset: palette.sourceOffset,
                    sourceRowHandle: texture.sourceRowHandle,
                    rawByteCount: palette.rawByteCount,
                    decodedByteCount: palette.decodedByteCount,
                    decodedSHA256: palette.decodedSHA256,
                    decoded: palette.decoded
                )
            }
            return GoldenEyeSourceTextureDescriptorV6(
                modelName: "stage-textures",
                family: "ramrom-stage",
                resourceHandle: texture.resourceHandle,
                width: levels[0].width,
                height: levels[0].height,
                mipLevels: UInt32(levels.count),
                payloadRecordID: 100_000 + texture.textureID + 1,
                payloadDecodedSHA256: levels[0].decodedSHA256,
                sourceOffset: texture.imageSegmentOffset,
                sourceRowHandle: texture.sourceRowHandle,
                sourceSpan: texture.romBytes,
                levels: levels,
                palette: palette
            )
        }
    }

    func resources(for textureIDs: Set<UInt32>) throws -> [GESourceResourceV6] {
        var resources: [GESourceResourceV6] = []
        for textureID in textureIDs.sorted() {
            guard let texture = texture(textureID: textureID) else {
                throw Error.unsupportedTextureID(textureID)
            }
            let descriptor = try descriptor(for: texture)
            var resource = GESourceResourceV6()
            Self.setHeader(&resource.header, size: MemoryLayout<GESourceResourceV6>.size)
            resource.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
            resource.resource_kind = UInt32(GE_SOURCE_RESOURCE_V6_TEXTURE)
            resource.flags = UInt32(GE_SOURCE_RESOURCE_V6_FLAG_RESIDENT)
                | UInt32(GE_SOURCE_RESOURCE_V6_FLAG_SOURCE_ORDERED)
            if descriptor.mipLevels > 1 {
                resource.flags |= UInt32(GE_SOURCE_RESOURCE_V6_FLAG_MIP_CHAIN)
            }
            resource.handle = descriptor.resourceHandle
            resource.source_id = descriptor.sourceRowHandle
            resource.format = UInt32(GE_SOURCE_RESOURCE_V6_FORMAT_RGBA32)
            resource.width = descriptor.width
            resource.height = descriptor.height
            resource.depth = 1
            resource.mip_count = descriptor.mipLevels
            resource.level_count = descriptor.mipLevels
            resource.byte_size = descriptor.sourceSpan
            resource.content_hash = Self.fnv64(descriptor.levels[0].decoded)
            resource.provenance_hash = UInt64(descriptor.sourceRowHandle) << 32
                | UInt64(descriptor.sourceSpan)
            try Self.validateResource(resource, textureID: textureID)
            resources.append(resource)

            if let palette = descriptor.palette {
                var paletteResource = GESourceResourceV6()
                Self.setHeader(&paletteResource.header, size: MemoryLayout<GESourceResourceV6>.size)
                paletteResource.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
                paletteResource.resource_kind = UInt32(GE_SOURCE_RESOURCE_V6_PALETTE)
                paletteResource.flags = UInt32(GE_SOURCE_RESOURCE_V6_FLAG_RESIDENT)
                    | UInt32(GE_SOURCE_RESOURCE_V6_FLAG_PALETTE)
                    | UInt32(GE_SOURCE_RESOURCE_V6_FLAG_SOURCE_ORDERED)
                paletteResource.handle = Self.paletteResourceHandle(textureID: textureID)
                paletteResource.source_id = palette.sourceRowHandle
                paletteResource.format = UInt32(GE_SOURCE_RESOURCE_V6_FORMAT_RGBA16)
                paletteResource.width = palette.entries
                paletteResource.height = 1
                paletteResource.depth = 1
                paletteResource.mip_count = 1
                paletteResource.level_count = 1
                paletteResource.byte_size = palette.rawByteCount
                paletteResource.content_hash = Self.fnv64(palette.decoded)
                paletteResource.provenance_hash = UInt64(palette.sourceRowHandle) << 32
                    | UInt64(palette.rawByteCount)
                resources.append(paletteResource)
            }
        }
        return resources
    }

    private func descriptor(for texture: Texture) throws -> GoldenEyeSourceTextureDescriptorV6 {
        let levels = Self.metalMipPrefix(for: texture.levels).map { level in
            GoldenEyeSourceTextureLevelUploadV6(
                level: level.level,
                width: level.width,
                height: level.height,
                payloadRecordID: 200_000 + texture.textureID * 64 + level.level + 1,
                sourceOffset: texture.imageSegmentOffset,
                sourceRowHandle: texture.sourceRowHandle,
                rawByteCount: level.decodedByteCount,
                decodedByteCount: level.decodedByteCount,
                decodedSHA256: level.decodedSHA256,
                decoded: level.decoded
            )
        }
        let palette = texture.palette.map { palette in
            GoldenEyeSourceTexturePaletteUploadV6(
                resourceHandle: texture.resourceHandle,
                entries: palette.entries,
                payloadRecordID: 300_000 + texture.textureID + 1,
                sourceOffset: palette.sourceOffset,
                sourceRowHandle: texture.sourceRowHandle,
                rawByteCount: palette.rawByteCount,
                decodedByteCount: palette.decodedByteCount,
                decodedSHA256: palette.decodedSHA256,
                decoded: palette.decoded
            )
        }
        return GoldenEyeSourceTextureDescriptorV6(
            modelName: "stage-textures",
            family: "ramrom-stage",
            resourceHandle: texture.resourceHandle,
            width: levels[0].width,
            height: levels[0].height,
            mipLevels: UInt32(levels.count),
            payloadRecordID: 100_000 + texture.textureID + 1,
            payloadDecodedSHA256: levels[0].decodedSHA256,
            sourceOffset: texture.imageSegmentOffset,
            sourceRowHandle: texture.sourceRowHandle,
            sourceSpan: texture.romBytes,
            levels: levels,
            palette: palette
        )
    }

    private static func splitTLUT(_ payload: String) -> ([String: String], String?) {
        if let range = payload.range(of: "|tlut:") {
            return (parseFields(String(payload[..<range.lowerBound])), String(payload[range.upperBound...]))
        }
        return (parseFields(payload), nil)
    }

    private static func parseFields(_ payload: String) -> [String: String] {
        Dictionary(uniqueKeysWithValues: payload.split(separator: "|").compactMap { field in
            let parts = field.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        })
    }

    private static func required(_ fields: [String: String], _ key: String) throws -> String {
        guard let value = fields[key], !value.isEmpty else {
            throw Error.invalidRow("missing \(key)")
        }
        return value
    }

    private static func uint(_ fields: [String: String], _ key: String) throws -> UInt32 {
        let value = try required(fields, key)
        guard let parsed = UInt32(value) else { throw Error.invalidRow("invalid \(key)=\(value)") }
        return parsed
    }

    private static func parseLevels(
        _ text: String,
        payloadRoot: URL,
        textureID: UInt32
    ) throws -> [Level] {
        let entries = try text.split(separator: ";").map { raw -> Level in
            let fields = raw.split(separator: ":", maxSplits: 7).map(String.init)
            guard fields.count == 8,
                  let level = UInt32(fields[0]),
                  let width = UInt32(fields[1]),
                  let height = UInt32(fields[2]),
                  let byteCount = UInt32(fields[3]) else {
                throw Error.invalidMipChain(textureID)
            }
            let digest = fields[4]
            let fileName = fields[5]
            let inspectionDigest = fields[6]
            let inspectionFileName = fields[7]
            let decoded = try readPayload(
                payloadRoot: payloadRoot,
                fileName: fileName,
                expectedBytes: Int(byteCount),
                expectedSHA256: digest,
                context: "image \(textureID) mip \(level)"
            )
            let inspection = try readPayload(
                payloadRoot: payloadRoot,
                fileName: inspectionFileName,
                expectedBytes: Int(byteCount),
                expectedSHA256: inspectionDigest,
                context: "image \(textureID) mip \(level) inspection"
            )
            _ = inspection
            guard width > 0, height > 0,
                  UInt64(width) * UInt64(height) * 4 == UInt64(byteCount) else {
                throw Error.invalidRow("image \(textureID) mip \(level) RGBA size \(width)x\(height)/\(byteCount)")
            }
            return Level(
                level: level,
                width: width,
                height: height,
                decodedByteCount: byteCount,
                decodedSHA256: digest,
                fileName: fileName,
                inspectionSHA256: inspectionDigest,
                inspectionFileName: inspectionFileName,
                decoded: decoded
            )
        }
        guard !entries.isEmpty,
              entries.map(\.level) == Array(0..<UInt32(entries.count)) else {
            throw Error.invalidRow("image \(textureID) mip levels are not contiguous")
        }
        return entries
    }

    private static func metalMipPrefix(for levels: [Level]) -> [Level] {
        // ``load`` has verified contiguous source-authored dimensions. Keep
        // every level; the upload descriptor infers the source dimension
        // mode and the shared store allocates the authored slices.
        return levels.filter { $0.level < 32 }
    }

    private static func sourceMipDimension(_ base: UInt32, level: UInt32) -> UInt32 {
        guard base > 1 else { return 1 }
        let divisor = UInt64(1) << UInt64(level)
        return UInt32(max(2, (UInt64(base) + divisor - 1) / divisor))
    }

    private static func parsePalette(
        _ text: String?,
        payloadRoot: URL,
        textureID: UInt32
    ) throws -> Palette? {
        guard let text, text != "null" else { return nil }
        guard let jsonData = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData),
              let json = object as? [String: Any],
              let entries = json["entries"] as? Int,
              let rawBytes = json["raw_bytes"] as? Int,
              let decodedBytes = json["decoded_bytes"] as? Int,
              let rawSHA256 = json["raw_sha256"] as? String,
              let decodedSHA256 = json["decoded_sha256"] as? String,
              let sourceOffset = json["source_offset"] as? Int,
              let rawFileName = json["raw_file"] as? String,
              let decodedFileName = json["decoded_file"] as? String,
              entries > 0, rawBytes > 0, decodedBytes == entries * 4,
              sourceOffset >= 0 else {
            throw Error.invalidPalette(textureID)
        }
        let raw = try readPayload(
            payloadRoot: payloadRoot,
            fileName: rawFileName,
            expectedBytes: rawBytes,
            expectedSHA256: rawSHA256,
            context: "image \(textureID) TLUT raw"
        )
        _ = raw
        let decoded = try readPayload(
            payloadRoot: payloadRoot,
            fileName: decodedFileName,
            expectedBytes: decodedBytes,
            expectedSHA256: decodedSHA256,
            context: "image \(textureID) TLUT decoded"
        )
        return Palette(
            entries: UInt32(entries),
            rawByteCount: UInt32(rawBytes),
            decodedByteCount: UInt32(decodedBytes),
            rawSHA256: rawSHA256,
            decodedSHA256: decodedSHA256,
            sourceOffset: UInt32(sourceOffset),
            rawFileName: rawFileName,
            decodedFileName: decodedFileName,
            decoded: decoded
        )
    }

    private static func readPayload(
        payloadRoot: URL,
        fileName: String,
        expectedBytes: Int,
        expectedSHA256: String,
        context: String
    ) throws -> Data {
        guard !fileName.isEmpty,
              !fileName.hasPrefix("/"),
              !fileName.split(separator: "/").contains("..") else {
            throw Error.payloadPathEscapes(payloadRoot.appendingPathComponent(fileName))
        }
        let url = payloadRoot.appendingPathComponent(fileName, isDirectory: false)
        let standardizedRoot = payloadRoot.standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(standardizedRoot + "/") else {
            throw Error.payloadPathEscapes(url)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Error.missingPayload(url)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw Error.invalidManifest("cannot read \(context): \(error)")
        }
        guard data.count == expectedBytes else {
            throw Error.payloadSize(context, data.count, expectedBytes)
        }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expectedSHA256 else {
            throw Error.payloadDigest(context, expectedSHA256, actual)
        }
        return data
    }

    private static func setHeader(_ header: inout GEAbiHeaderV1, size: Int) {
        header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        header.struct_size = UInt32(size)
    }

    private static func validateResource(_ resource: GESourceResourceV6, textureID: UInt32) throws {
        guard resource.handle != 0,
              resource.source_id != 0,
              resource.width > 0,
              resource.height > 0,
              resource.byte_size > 0,
              resource.content_hash != 0,
              resource.provenance_hash != 0 else {
            throw Error.invalidResource(textureID, "zero fixed-width field")
        }
    }

    private static func fnv32(_ text: String) -> UInt32 {
        var value: UInt32 = 2_166_136_261
        for byte in text.utf8 { value = (value ^ UInt32(byte)) &* 16_777_619 }
        return value == 0 ? 1 : value
    }

    private static func fnv64(_ data: Data) -> UInt64 {
        var value: UInt64 = 1_469_598_103_934_665_603
        for byte in data { value = (value ^ UInt64(byte)) &* 1_099_511_628_211 }
        return value == 0 ? 1 : value
    }
}
