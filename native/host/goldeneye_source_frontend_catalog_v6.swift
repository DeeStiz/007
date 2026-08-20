import CryptoKit
import Foundation

/// A JSON value retained by the source-frontend catalog without exposing
/// Foundation's `Any` across the host boundary.
public indirect enum GoldenEyeSourceFrontendJSONValue: Sendable, Equatable {
    case object([String: GoldenEyeSourceFrontendJSONValue])
    case array([GoldenEyeSourceFrontendJSONValue])
    case string(String)
    case integer(Int64)
    case real(Double)
    case boolean(Bool)
    case null
}

/// The semantic resource groups consumed by the native source renderer. A
/// group may cover more than one on-disk GEFV category (for example, all font
/// payload forms are `.font`, and source-listing/bank/sequence rows are
/// `.audio`).
public enum GoldenEyeSourceFrontendResourceKind: String, CaseIterable, Sendable {
    case model
    case node
    case displayList
    case vertex
    case texture
    case mip
    case tlut
    case image
    case font
    case blood
    case background
    case animation
    case audio

    fileprivate var categories: Set<String> {
        switch self {
        case .model: return ["model", "model_manifest", "rom_asset", "rareware_array_tail"]
        case .node: return ["node", "switch"]
        case .displayList: return ["display_list"]
        case .vertex: return ["vertex_group"]
        case .texture: return ["texture", "texture_payload"]
        case .mip: return ["mip", "mip_payload"]
        case .tlut: return ["tlut", "tlut_payload"]
        case .image: return ["image_stream", "global_image_table"]
        case .font: return ["font", "font_chardata", "font_display_list", "font_packet", "font_payload", "text", "text_catalog"]
        case .blood: return ["blood"]
        case .background: return ["background"]
        case .animation: return ["weapon_animation"]
        case .audio: return ["source_listing", "source_header", "soundbank", "sequence", "bank"]
        }
    }

    fileprivate init?(category: String) {
        guard let kind = Self.allCases.first(where: { $0.categories.contains(category) }) else {
            return nil
        }
        self = kind
    }
}

public enum GoldenEyeSourceFrontendPayloadKind: Sendable {
    case raw
    case decoded
}

public enum GoldenEyeSourceFrontendCatalogError: Error, Sendable, CustomStringConvertible {
    case invalidRoot(String)
    case missingPacket(String)
    case unreadablePacket(String)
    case packetTooLarge(UInt64)
    case truncated(String)
    case malformedManifest(String)
    case unknownField(String)
    case invalidValue(String)
    case invalidCategory(String)
    case missingCategory(String)
    case duplicateRecord(String)
    case digestMismatch(String, expected: String, actual: String)
    case payloadBounds(String)
    case recordNotFound(String)
    case ambiguousRecord(String)

    public var description: String {
        switch self {
        case let .invalidRoot(detail): return "source frontend V6 root is invalid: \(detail)"
        case let .missingPacket(path): return "source frontend V6 packet is missing: \(path)"
        case let .unreadablePacket(detail): return "source frontend V6 packet is unreadable: \(detail)"
        case let .packetTooLarge(bytes): return "source frontend V6 packet is too large: \(bytes) bytes"
        case let .truncated(detail): return "source frontend V6 packet is truncated: \(detail)"
        case let .malformedManifest(detail): return "source frontend V6 manifest is malformed: \(detail)"
        case let .unknownField(path): return "source frontend V6 unknown field: \(path)"
        case let .invalidValue(path): return "source frontend V6 invalid value: \(path)"
        case let .invalidCategory(category): return "source frontend V6 unknown category: \(category)"
        case let .missingCategory(category): return "source frontend V6 required category is missing: \(category)"
        case let .duplicateRecord(key): return "source frontend V6 duplicate record: \(key)"
        case let .digestMismatch(scope, expected, actual):
            return "source frontend V6 \(scope) SHA-256 mismatch: expected \(expected), got \(actual)"
        case let .payloadBounds(detail): return "source frontend V6 payload bounds are invalid: \(detail)"
        case let .recordNotFound(key): return "source frontend V6 record is missing: \(key)"
        case let .ambiguousRecord(key): return "source frontend V6 record is ambiguous: \(key)"
        }
    }
}

/// A copied, pointer-free GEFV record. The catalog keeps the packet bytes
/// privately and exposes payloads only through bounded copy-out methods.
public struct GoldenEyeSourceFrontendRecord: Sendable, Equatable {
    public let id: UInt32
    public let family: String
    public let category: String
    public let kind: GoldenEyeSourceFrontendResourceKind
    public let name: String
    public let sourcePath: String
    public let sourceSHA256: String
    public let rawSHA256: String
    public let decodedSHA256: String
    public let sourceSize: UInt32
    public let rawSize: UInt32
    public let decodedSize: UInt32
    public let rawPayloadOffset: UInt32
    public let decodedPayloadOffset: UInt32
    public let flags: [String]
    public let metadata: GoldenEyeSourceFrontendJSONValue
    public let romOffset: UInt32?
    public let romSize: UInt32?
    public let romRow: String?
    public let compressed: Bool?
    public let privateRow: Bool?

    fileprivate let rawOffset: Int
    fileprivate let decodedOffset: Int

    fileprivate init(
        id: UInt32,
        family: String,
        category: String,
        kind: GoldenEyeSourceFrontendResourceKind,
        name: String,
        sourcePath: String,
        sourceSHA256: String,
        rawSHA256: String,
        decodedSHA256: String,
        sourceSize: UInt32,
        rawSize: UInt32,
        decodedSize: UInt32,
        rawPayloadOffset: UInt32,
        decodedPayloadOffset: UInt32,
        flags: [String],
        metadata: GoldenEyeSourceFrontendJSONValue,
        romOffset: UInt32?,
        romSize: UInt32?,
        romRow: String?,
        compressed: Bool?,
        privateRow: Bool?,
        rawOffset: Int,
        decodedOffset: Int
    ) {
        self.id = id
        self.family = family
        self.category = category
        self.kind = kind
        self.name = name
        self.sourcePath = sourcePath
        self.sourceSHA256 = sourceSHA256
        self.rawSHA256 = rawSHA256
        self.decodedSHA256 = decodedSHA256
        self.sourceSize = sourceSize
        self.rawSize = rawSize
        self.decodedSize = decodedSize
        self.rawPayloadOffset = rawPayloadOffset
        self.decodedPayloadOffset = decodedPayloadOffset
        self.flags = flags
        self.metadata = metadata
        self.romOffset = romOffset
        self.romSize = romSize
        self.romRow = romRow
        self.compressed = compressed
        self.privateRow = privateRow
        self.rawOffset = rawOffset
        self.decodedOffset = decodedOffset
    }
}

public struct GoldenEyeSourceFrontendManifestSummary: Sendable, Equatable {
    public let goal: String
    public let externalROMSHA1: String
    public let counts: [String: UInt32]
    public let runtimeROMAccess: Bool
    public let sourcePathsAreRelative: Bool
    public let romCopiedIntoCheckout: Bool
    public let romCopiedIntoBundle: Bool
    public let privatePayloadsCopiedIntoCheckout: Bool
    public let privatePayloadsCopiedIntoBundle: Bool
}

public struct GoldenEyeSourceFrontendSidecar: Sendable, Equatable {
    public struct HandleAudit: Sendable, Equatable {
        public let declared: UInt32
        public let referenced: UInt32
        public let unused: UInt32
    }

    public let name: String
    public let family: String
    public let path: String
    public let sourceSHA256: String
    public let packetSHA256: String
    public let byteCount: UInt32
    public let recordCount: UInt32
    public let nodes: UInt32
    public let scalars: UInt32
    public let displayLists: UInt32
    public let commands: UInt32
    public let tokens: UInt32
    public let vertices: UInt32
    public let textures: UInt32
    public let mips: UInt32
    public let tluts: UInt32
    public let flags: UInt32
    public let unsupportedMacros: [String]
    public let handleAudit: [String: HandleAudit]
}

/// Strict runtime consumer for the prepared GEFV V6 source catalog.
///
/// The initializer accepts one explicit prepared root and reads exactly one
/// packet named `source-frontend-v6.gefv` beneath that root. It never searches
/// parent directories, consults generated sidecars, or opens a ROM.
public struct GoldenEyeSourceFrontendCatalog: Sendable {
    public static let packetFileName = "source-frontend-v6.gefv"
    public static let expectedMagic = "GEFV"
    public static let expectedVersion: UInt32 = 6
    public static let expectedExternalROMSHA1 = "abe01e4aeb033b6c0836819f549c791b26cfde83"
    public static let maxPacketBytes: UInt64 = 64 * 1024 * 1024
    public static let maxManifestBytes: UInt32 = 8 * 1024 * 1024
    public static let maxPayloadBytes: UInt32 = 56 * 1024 * 1024
    public static let maxSourceBytes: UInt32 = 512 * 1024 * 1024

    public let rootURL: URL
    public let packetURL: URL
    public let records: [GoldenEyeSourceFrontendRecord]
    public let sidecars: [GoldenEyeSourceFrontendSidecar]
    public let manifest: GoldenEyeSourceFrontendManifestSummary
    public let packetSHA256: String
    public let sourceCatalogSHA256: String
    public let payloadSHA256: String
    public let payloadByteCount: UInt32
    public let sourceByteCount: UInt32

    private let packetData: Data
    private let payloadStart: Int

    private static let headerSize = 96
    private static let packetDigestRange = 60..<92
    private static let knownFamilies: Set<String> = [
        "audio", "cast", "cast_weapon", "frontend", "goldeneye", "gunbarrel", "legal", "nintendo", "rareware", "wallet"
    ]
    private static let modelPayloadFamilies: Set<String> = [
        "chrwppk", "goldeneyelogo", "headbrosnansuit", "legalpage", "nintendologo", "suitbond", "walletbond"
    ]
    private static let requiredCategories: Set<String> = [
        "background", "bank", "blood", "display_list", "font", "font_chardata",
        "font_display_list", "font_packet", "font_payload", "global_image_table",
        "image_stream", "mip", "mip_payload", "model", "model_manifest", "node", "rareware_array_tail", "rom_asset",
        "sequence", "soundbank", "source_header", "source_listing", "switch", "text",
        "text_catalog", "texture", "texture_payload", "tlut", "tlut_payload", "vertex_group", "weapon_animation"
    ]
    private static let optionalCategories: Set<String> = []
    private static let knownFlags: Set<String> = [
        "AUDIO_SOURCE", "BLOOD_SOURCE", "COUNT_GUARD", "DECODED_BASE_LEVEL",
        "DERIVED_PACKET", "EMBEDDED_MODEL", "EMBEDDED_TEXTURE_ROW", "FONT_PAYLOAD",
        "FONT_RENDER_SOURCE", "FONT_SOURCE", "FRONTEND_AUDIO", "GLOBAL_IMAGE",
        "GLOBAL_IMAGE_TABLE", "HAND_AUTHORED_RAREWARE", "MUZZLE_FLASH_DEPENDENCY",
        "RAREWARE_BINARY", "RAREWARE_DISPLAY_LIST", "RAREWARE_GEOMETRY", "RAREWARE_MIP",
        "RAREWARE_TEXTURE", "RLE_BACKGROUND", "RLE_OR_ENCRYPTED", "ROM_PREPARED",
        "SKELETON_SOURCE", "SOURCE_DISPLAY_LIST", "SOURCE_HIERARCHY", "SOURCE_MIP_LEVEL",
        "SOURCE_RENDER_PATH", "SOURCE_TEXT", "SOURCE_TEXT_CATALOG", "SOURCE_VERTEX_GROUP",
        "TLUT_DEPENDENCY", "EMBEDDED_TEXELS", "DECODED_RGBA8_LEVELS", "EMBEDDED_MIP",
        "DECODED_RGBA8", "GLOBAL_IMAGE_MIP", "DERIVED_FROM_SOURCE_BASE", "RAREWARE_TEXELS",
        "RAREWARE_MIP", "RAREWARE_SOURCE_TAIL", "PD_TLUT", "DECODED_RGBA8_ENTRIES",
        "PROVENANCE_ONLY", "GLOBAL_TEXTURE_PAYLOAD", "DECODED_RGBA8_BASE_LEVEL",
        "SOURCE_ORDER_RGBA8", "SOURCE_AUTHORED_MIP", "SOURCE_GENERATED_MIP"
    ]

    private init(
        rootURL: URL,
        packetURL: URL,
        packetData: Data,
        payloadStart: Int,
        records: [GoldenEyeSourceFrontendRecord],
        sidecars: [GoldenEyeSourceFrontendSidecar],
        manifest: GoldenEyeSourceFrontendManifestSummary,
        packetSHA256: String,
        sourceCatalogSHA256: String,
        payloadSHA256: String,
        payloadByteCount: UInt32,
        sourceByteCount: UInt32
    ) {
        self.rootURL = rootURL
        self.packetURL = packetURL
        self.packetData = packetData
        self.payloadStart = payloadStart
        self.records = records
        self.sidecars = sidecars
        self.manifest = manifest
        self.packetSHA256 = packetSHA256
        self.sourceCatalogSHA256 = sourceCatalogSHA256
        self.payloadSHA256 = payloadSHA256
        self.payloadByteCount = payloadByteCount
        self.sourceByteCount = sourceByteCount
    }

    public static func load(preparedAssetRoot rootURL: URL) throws -> Self {
        try load(preparedAssetRoot: rootURL, allowExtendedSidecars: false)
    }

    /// Cast preparation publishes the same guarded GEFV envelope but includes
    /// the complete character/weapon sidecar set. Existing frontend loading
    /// remains pinned to its eight title sidecars.
    public static func loadCast(preparedAssetRoot rootURL: URL) throws -> Self {
        try load(preparedAssetRoot: rootURL, allowExtendedSidecars: true)
    }

    private static func load(
        preparedAssetRoot rootURL: URL,
        allowExtendedSidecars: Bool
    ) throws -> Self {
        guard rootURL.isFileURL, rootURL.path.hasPrefix("/") else {
            throw GoldenEyeSourceFrontendCatalogError.invalidRoot("an absolute file URL is required")
        }
        let root = rootURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GoldenEyeSourceFrontendCatalogError.invalidRoot("prepared asset root is not a directory: \(root.path)")
        }
        let packetURL = root.appendingPathComponent(packetFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: packetURL.path) else {
            throw GoldenEyeSourceFrontendCatalogError.missingPacket(packetURL.path)
        }
        guard isWithinPreparedRoot(packetURL, rootURL: root) else {
            throw GoldenEyeSourceFrontendCatalogError.invalidRoot("packet path escapes the prepared asset root")
        }
        let data: Data
        do {
            data = try Data(contentsOf: packetURL, options: [.mappedIfSafe])
        } catch {
            throw GoldenEyeSourceFrontendCatalogError.unreadablePacket(String(describing: error))
        }
        guard UInt64(data.count) <= maxPacketBytes else {
            throw GoldenEyeSourceFrontendCatalogError.packetTooLarge(UInt64(data.count))
        }
        return try parse(
            rootURL: root,
            packetURL: packetURL,
            data: data,
            allowExtendedSidecars: allowExtendedSidecars
        )
    }

    public static func load(from preparedAssetRoot: URL) throws -> Self {
        try load(preparedAssetRoot: preparedAssetRoot)
    }

    public func records(of kind: GoldenEyeSourceFrontendResourceKind) -> [GoldenEyeSourceFrontendRecord] {
        records.filter { $0.kind == kind && Self.isConsumable(kind: kind, category: $0.category) }
    }

    public func record(id: UInt32) -> GoldenEyeSourceFrontendRecord? {
        guard id > 0, id <= UInt32(records.count) else { return nil }
        let record = records[Int(id - 1)]
        return record.id == id ? record : nil
    }

    /// Returns all matching rows. Some source display-list names are reused by
    /// different models, so callers should include `family` when they need a
    /// single deterministic row.
    public func lookup(
        kind: GoldenEyeSourceFrontendResourceKind,
        name: String,
        family: String? = nil
    ) -> [GoldenEyeSourceFrontendRecord] {
        records.filter { record in
            record.kind == kind && Self.isConsumable(kind: kind, category: record.category)
                && record.name == name && (family == nil || record.family == family)
        }
    }

    public func record(
        kind: GoldenEyeSourceFrontendResourceKind,
        name: String,
        family: String? = nil
    ) throws -> GoldenEyeSourceFrontendRecord {
        let allMatches = lookup(kind: kind, name: name, family: family)
        let payloadMatches = allMatches.filter {
            $0.category == "texture_payload" || $0.category == "mip_payload" || $0.category == "tlut_payload"
        }
        let matches = payloadMatches.isEmpty ? allMatches : payloadMatches
        guard !matches.isEmpty else {
            throw GoldenEyeSourceFrontendCatalogError.recordNotFound("\(kind.rawValue):\(family ?? "*"):\(name)")
        }
        guard matches.count == 1 else {
            throw GoldenEyeSourceFrontendCatalogError.ambiguousRecord("\(kind.rawValue):\(name)")
        }
        return matches[0]
    }

    public func copyOut(
        _ payloadKind: GoldenEyeSourceFrontendPayloadKind,
        for record: GoldenEyeSourceFrontendRecord
    ) throws -> Data {
        guard records.contains(where: { $0 == record }) else {
            throw GoldenEyeSourceFrontendCatalogError.recordNotFound("record id \(record.id)")
        }
        if (record.kind == .texture && record.category == "texture")
            || (record.kind == .mip && record.category == "mip")
            || (record.kind == .tlut && record.category == "tlut")
            || (record.category == "image_stream" || record.category == "global_image_table") {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("record id \(record.id) is a descriptor without pixel payload")
        }
        let offset: Int
        let size: Int
        switch payloadKind {
        case .raw:
            offset = record.rawOffset
            size = Int(record.rawSize)
        case .decoded:
            offset = record.decodedOffset
            size = Int(record.decodedSize)
        }
        let end = offset.addingReportingOverflow(size)
        guard offset >= 0, !end.overflow, end.partialValue <= payloadByteCountAsInt else {
            throw GoldenEyeSourceFrontendCatalogError.payloadBounds("record id \(record.id)")
        }
        return Data(packetData[(payloadStart + offset)..<(payloadStart + end.partialValue)])
    }

    public func copyOut(
        _ payloadKind: GoldenEyeSourceFrontendPayloadKind,
        kind: GoldenEyeSourceFrontendResourceKind,
        name: String,
        family: String? = nil
    ) throws -> Data {
        try copyOut(payloadKind, for: record(kind: kind, name: name, family: family))
    }

    public func copyOut(
        _ payloadKind: GoldenEyeSourceFrontendPayloadKind,
        recordID: UInt32
    ) throws -> Data {
        guard let record = record(id: recordID) else {
            throw GoldenEyeSourceFrontendCatalogError.recordNotFound("record id \(recordID)")
        }
        return try copyOut(payloadKind, for: record)
    }

    private var payloadByteCountAsInt: Int { Int(payloadByteCount) }

    private static func isConsumable(kind: GoldenEyeSourceFrontendResourceKind, category: String) -> Bool {
        switch kind {
        case .texture:
            return category == "texture_payload"
        case .mip:
            return category == "mip_payload"
        case .tlut:
            return category == "tlut_payload"
        default:
            return true
        }
    }

    private static func parse(
        rootURL: URL,
        packetURL: URL,
        data: Data,
        allowExtendedSidecars: Bool = false
    ) throws -> Self {
        guard data.count >= headerSize else {
            throw GoldenEyeSourceFrontendCatalogError.truncated("header")
        }
        guard Data(data[0..<4]) == Data(expectedMagic.utf8) else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("header.magic")
        }
        let version = readUInt32(data, at: 4)
        let recordCount = readUInt32(data, at: 8)
        let manifestSize = readUInt32(data, at: 12)
        let payloadSize = readUInt32(data, at: 16)
        let sourceSize = readUInt32(data, at: 20)
        let flags = readUInt32(data, at: 24)
        let sourceDigest = Data(data[28..<60])
        let packetDigest = Data(data[60..<92])
        let reserved = readUInt32(data, at: 92)
        guard version == expectedVersion, flags == 0, reserved == 0 else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("header.version/flags/reserved")
        }
        guard recordCount > 0, recordCount <= 16_384 else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("header.record_count")
        }
        let sourceLimit = allowExtendedSidecars ? UInt32.max : maxSourceBytes
        guard manifestSize > 0, manifestSize <= maxManifestBytes,
              payloadSize > 0, payloadSize <= maxPayloadBytes,
              sourceSize > 0, sourceSize <= sourceLimit else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("header byte counts")
        }
        guard sourceDigest.contains(where: { $0 != 0 }), packetDigest.contains(where: { $0 != 0 }) else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("header digest")
        }

        let manifestStart = headerSize
        let manifestEnd = manifestStart.addingReportingOverflow(Int(manifestSize))
        guard !manifestEnd.overflow else {
            throw GoldenEyeSourceFrontendCatalogError.truncated("manifest size overflow")
        }
        let payloadEnd = manifestEnd.partialValue.addingReportingOverflow(Int(payloadSize))
        guard !payloadEnd.overflow, manifestEnd.partialValue <= data.count,
              payloadEnd.partialValue == data.count else {
            throw GoldenEyeSourceFrontendCatalogError.truncated("manifest/payload bounds")
        }
        let manifestData = Data(data[manifestStart..<manifestEnd.partialValue])

        var canonicalPacket = data
        canonicalPacket.replaceSubrange(packetDigestRange, with: Data(repeating: 0, count: packetDigestRange.count))
        let actualPacketDigest = Data(SHA256.hash(data: canonicalPacket))
        guard actualPacketDigest == packetDigest else {
            throw GoldenEyeSourceFrontendCatalogError.digestMismatch(
                "packet", expected: hex(packetDigest), actual: hex(actualPacketDigest)
            )
        }

        let manifestObject: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: manifestData, options: []) as? [String: Any] else {
                throw GoldenEyeSourceFrontendCatalogError.malformedManifest("root is not an object")
            }
            manifestObject = object
        } catch let error as GoldenEyeSourceFrontendCatalogError {
            throw error
        } catch {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest(String(describing: error))
        }
        let canonicalManifest: Data
        do {
            canonicalManifest = try JSONSerialization.data(withJSONObject: manifestObject, options: [.sortedKeys, .withoutEscapingSlashes])
        } catch {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("manifest cannot be canonicalized")
        }
        guard canonicalManifest == manifestData else {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("manifest is not canonical JSON")
        }

        let rootValue = try jsonValue(manifestObject, path: "manifest")
        guard case let .object(rootFields) = rootValue else {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("root is not an object")
        }
        try requireExactKeys(
            rootFields,
            allowed: ["counts", "external_rom_sha1", "goal", "magic", "manifest_version", "provenance", "records", "runtime_rom_access", "sidecars", "source_catalog_sha256"],
            required: ["counts", "external_rom_sha1", "goal", "magic", "manifest_version", "provenance", "records", "runtime_rom_access", "sidecars", "source_catalog_sha256"],
            path: "manifest"
        )
        guard try requireString(rootFields["magic"], path: "manifest.magic") == expectedMagic,
              try requireUInt(rootFields["manifest_version"], path: "manifest.manifest_version") == UInt64(expectedVersion),
              try requireString(rootFields["goal"], path: "manifest.goal") == "native-boot-menu-attract-120",
              try requireBool(rootFields["runtime_rom_access"], path: "manifest.runtime_rom_access") == false else {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("manifest identity/runtime guard")
        }

        let externalROM = try requireString(rootFields["external_rom_sha1"], path: "manifest.external_rom_sha1")
        guard externalROM == expectedExternalROMSHA1 else {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("external ROM SHA-1 does not match the frozen boundary")
        }
        let sourceCatalog = try requireDigest(rootFields["source_catalog_sha256"], path: "manifest.source_catalog_sha256")
        guard sourceCatalog == sourceDigest else {
            throw GoldenEyeSourceFrontendCatalogError.digestMismatch("source catalog", expected: hex(sourceDigest), actual: hex(sourceCatalog))
        }
        let provenance = try requireObject(rootFields["provenance"], path: "manifest.provenance")
        try requireExactKeys(
            provenance,
            allowed: ["linux_reference_command", "linux_reference_hash_command", "private_payloads_copied_into_bundle", "private_payloads_copied_into_checkout", "rom_copied_into_bundle", "rom_copied_into_checkout", "source_paths_are_relative"],
            required: ["linux_reference_command", "linux_reference_hash_command", "private_payloads_copied_into_bundle", "private_payloads_copied_into_checkout", "rom_copied_into_bundle", "rom_copied_into_checkout", "source_paths_are_relative"],
            path: "manifest.provenance"
        )
        guard try requireString(provenance["linux_reference_command"], path: "manifest.provenance.linux_reference_command") == "make -j8 IDO_RECOMP=NO VERSION=US COMPARE=1 VERBOSE=1",
              try requireString(provenance["linux_reference_hash_command"], path: "manifest.provenance.linux_reference_hash_command") == "sha1sum -c ge007.u.sha1",
              try requireBool(provenance["rom_copied_into_checkout"], path: "manifest.provenance.rom_copied_into_checkout") == false,
              try requireBool(provenance["rom_copied_into_bundle"], path: "manifest.provenance.rom_copied_into_bundle") == false,
              try requireBool(provenance["private_payloads_copied_into_checkout"], path: "manifest.provenance.private_payloads_copied_into_checkout") == false,
              try requireBool(provenance["private_payloads_copied_into_bundle"], path: "manifest.provenance.private_payloads_copied_into_bundle") == false,
              try requireBool(provenance["source_paths_are_relative"], path: "manifest.provenance.source_paths_are_relative") == true else {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("provenance guard")
        }

        let recordsValue = try requireArray(rootFields["records"], path: "manifest.records")
        guard recordsValue.count == Int(recordCount) else {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("record count differs from header")
        }
        let countsObject = try requireObject(rootFields["counts"], path: "manifest.counts")
        let counts = try parseCounts(countsObject)
        let sidecars = try parseSidecars(
            rootFields["sidecars"],
            rootURL: rootURL,
            allowExtendedSidecars: allowExtendedSidecars
        )

        var records: [GoldenEyeSourceFrontendRecord] = []
        records.reserveCapacity(recordsValue.count)
        var seenTypedKeys: Set<String> = []
        var actualCounts: [String: UInt32] = [:]
        var sourceTotal: UInt64 = 0
        let payloadData = Data(data[manifestEnd.partialValue..<payloadEnd.partialValue])
        for (index, value) in recordsValue.enumerated() {
            let record = try parseRecord(value, index: index, payloadByteCount: payloadSize)
            guard record.id == UInt32(index + 1) else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("manifest.records[\(index)].id")
            }
            let typedKey = "\(record.category):\(record.family):\(record.name)"
            guard seenTypedKeys.insert(typedKey).inserted else {
                throw GoldenEyeSourceFrontendCatalogError.duplicateRecord(typedKey)
            }
            actualCounts[record.category, default: 0] += 1
            sourceTotal += UInt64(record.sourceSize)
            guard sourceTotal <= UInt64(UInt32.max) else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("source byte count overflow")
            }
            let rawEnd = record.rawOffset.addingReportingOverflow(Int(record.rawSize))
            let decodedEnd = record.decodedOffset.addingReportingOverflow(Int(record.decodedSize))
            guard !rawEnd.overflow, !decodedEnd.overflow,
                  record.rawOffset >= 0, record.decodedOffset >= 0,
                  rawEnd.partialValue <= payloadData.count,
                  decodedEnd.partialValue <= payloadData.count else {
                throw GoldenEyeSourceFrontendCatalogError.payloadBounds("record \(record.id)")
            }
            let rawData = Data(payloadData[record.rawOffset..<rawEnd.partialValue])
            let decodedData = Data(payloadData[record.decodedOffset..<decodedEnd.partialValue])
            let rawDigest = hex(SHA256.hash(data: rawData))
            let decodedDigest = hex(SHA256.hash(data: decodedData))
            guard rawDigest == record.rawSHA256 else {
                throw GoldenEyeSourceFrontendCatalogError.digestMismatch("record \(record.id) raw payload", expected: record.rawSHA256, actual: rawDigest)
            }
            guard decodedDigest == record.decodedSHA256 else {
                throw GoldenEyeSourceFrontendCatalogError.digestMismatch("record \(record.id) decoded payload", expected: record.decodedSHA256, actual: decodedDigest)
            }
            records.append(record)
        }
        guard sourceTotal == UInt64(sourceSize) else {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("source byte count differs from header")
        }
        guard actualCounts == counts else {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("category counts differ from records")
        }
        guard Set(counts.keys).isSuperset(of: requiredCategories),
              Set(counts.keys).isSubset(of: requiredCategories.union(optionalCategories)) else {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("category set is incomplete")
        }
        for category in requiredCategories {
            guard (counts[category] ?? 0) > 0 else {
                throw GoldenEyeSourceFrontendCatalogError.missingCategory(category)
            }
        }
        try validateCompleteness(records, allowExtendedSidecars: allowExtendedSidecars)
        try validatePayloadLinkage(records)
        try validateSidecarCompleteness(
            sidecars,
            records: records,
            allowExtendedSidecars: allowExtendedSidecars
        )

        let payloadDigest = hex(SHA256.hash(data: payloadData))
        let packetDigestHex = hex(packetDigest)
        let manifestSummary = GoldenEyeSourceFrontendManifestSummary(
            goal: "native-boot-menu-attract-120",
            externalROMSHA1: externalROM,
            counts: counts,
            runtimeROMAccess: false,
            sourcePathsAreRelative: true,
            romCopiedIntoCheckout: false,
            romCopiedIntoBundle: false,
            privatePayloadsCopiedIntoCheckout: false,
            privatePayloadsCopiedIntoBundle: false
        )
        return Self(
            rootURL: rootURL,
            packetURL: packetURL,
            packetData: data,
            payloadStart: manifestEnd.partialValue,
            records: records,
            sidecars: sidecars,
            manifest: manifestSummary,
            packetSHA256: packetDigestHex,
            sourceCatalogSHA256: hex(sourceDigest),
            payloadSHA256: payloadDigest,
            payloadByteCount: payloadSize,
            sourceByteCount: sourceSize
        )
    }

    private static func parseCounts(_ object: [String: GoldenEyeSourceFrontendJSONValue]) throws -> [String: UInt32] {
        try requireExactKeys(
            object,
            allowed: requiredCategories.union(optionalCategories),
            required: requiredCategories,
            path: "manifest.counts"
        )
        var result: [String: UInt32] = [:]
        for category in requiredCategories.union(optionalCategories) where object[category] != nil {
            let value = try requireUInt(object[category], path: "manifest.counts.\(category)")
            guard value > 0, value <= UInt64(UInt32.max) else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("manifest.counts.\(category)")
            }
            result[category] = UInt32(value)
        }
        return result
    }

    private static func parseSidecars(
        _ value: GoldenEyeSourceFrontendJSONValue?,
        rootURL: URL,
        allowExtendedSidecars: Bool = false
    ) throws -> [GoldenEyeSourceFrontendSidecar] {
        let values = try requireArray(value, path: "manifest.sidecars")
        let maxSidecars = allowExtendedSidecars ? 128 : 64
        guard !values.isEmpty, values.count <= maxSidecars else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("manifest.sidecars")
        }
        var result: [GoldenEyeSourceFrontendSidecar] = []
        result.reserveCapacity(values.count)
        var names: Set<String> = []
        var priorName = ""
        for (index, value) in values.enumerated() {
            let path = "manifest.sidecars[\(index)]"
            let object = try requireObject(value, path: path)
            let keys: Set<String> = [
                "bytes", "commands", "display_lists", "family", "flags", "handle_audit", "mips", "model_handle", "name", "nodes", "packet_sha256", "path", "record_count", "scalars", "source_sha256", "textures", "tluts", "tokens", "unsupported_macros", "vertices"
            ]
            try requireExactKeys(object, allowed: keys, required: keys, path: path)
            let name = try requireString(object["name"], path: "\(path).name")
            let family = try requireString(object["family"], path: "\(path).family")
            guard !name.isEmpty,
                  (knownFamilies.contains(family) || family.hasPrefix("cast_")),
                  names.insert(name).inserted,
                  priorName.isEmpty || priorName < name else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).name ordering/duplicate")
            }
            priorName = name
            let relativePath = try requireString(object["path"], path: "\(path).path")
            guard isRelativeSourcePath(relativePath), relativePath.lowercased().hasSuffix(".gesm") else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).path")
            }
            let sourceSHA = try requireDigest(object["source_sha256"], path: "\(path).source_sha256")
            let packetSHA = try requireDigest(object["packet_sha256"], path: "\(path).packet_sha256")
            let byteCount = try requireUInt32(object["bytes"], path: "\(path).bytes")
            guard byteCount > 132, byteCount <= 16 * 1024 * 1024 else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).bytes")
            }
            let recordCount = try requireUInt32(object["record_count"], path: "\(path).record_count")
            let nodes = try requireUInt32(object["nodes"], path: "\(path).nodes")
            let scalars = try requireUInt32(object["scalars"], path: "\(path).scalars")
            let displayLists = try requireUInt32(object["display_lists"], path: "\(path).display_lists")
            let commands = try requireUInt32(object["commands"], path: "\(path).commands")
            let tokens = try requireUInt32(object["tokens"], path: "\(path).tokens")
            let vertices = try requireUInt32(object["vertices"], path: "\(path).vertices")
            let textures = try requireUInt32(object["textures"], path: "\(path).textures")
            let mips = try requireUInt32(object["mips"], path: "\(path).mips")
            let tluts = try requireUInt32(object["tluts"], path: "\(path).tluts")
            let modelHandle = try requireUInt32(object["model_handle"], path: "\(path).model_handle")
            let flags = try requireUInt32(object["flags"], path: "\(path).flags")
            guard modelHandle > 0, recordCount > 0, displayLists > 0, commands > 0,
                  textures > 0, mips > 0, (flags & ~UInt32(3)) == 0 else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue(path)
            }
            let macroValues = try requireArray(object["unsupported_macros"], path: "\(path).unsupported_macros")
            var unsupportedMacros: [String] = []
            unsupportedMacros.reserveCapacity(macroValues.count)
            for (macroIndex, macroValue) in macroValues.enumerated() {
                let macro = try requireString(macroValue, path: "\(path).unsupported_macros[\(macroIndex)]")
                guard !macro.isEmpty, macro.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) else {
                    throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).unsupported_macros[\(macroIndex)]")
                }
                unsupportedMacros.append(macro)
            }
            guard unsupportedMacros == unsupportedMacros.sorted(), Set(unsupportedMacros).count == unsupportedMacros.count else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).unsupported_macros ordering/duplicates")
            }
            let handleAuditObject = try requireObject(object["handle_audit"], path: "\(path).handle_audit")
            let handleKinds: Set<String> = ["display_list", "texture", "vertex_group"]
            try requireExactKeys(handleAuditObject, allowed: handleKinds, required: handleKinds, path: "\(path).handle_audit")
            var handleAudit: [String: GoldenEyeSourceFrontendSidecar.HandleAudit] = [:]
            for kind in handleKinds {
                let auditObject = try requireObject(handleAuditObject[kind], path: "\(path).handle_audit.\(kind)")
                let auditKeys: Set<String> = ["declared", "referenced", "unused"]
                try requireExactKeys(auditObject, allowed: auditKeys, required: auditKeys, path: "\(path).handle_audit.\(kind)")
                let declared = try requireUInt32(auditObject["declared"], path: "\(path).handle_audit.\(kind).declared")
                let referenced = try requireUInt32(auditObject["referenced"], path: "\(path).handle_audit.\(kind).referenced")
                let unused = try requireUInt32(auditObject["unused"], path: "\(path).handle_audit.\(kind).unused")
                guard referenced <= declared, unused == declared - referenced else {
                    throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).handle_audit.\(kind)")
                }
                handleAudit[kind] = GoldenEyeSourceFrontendSidecar.HandleAudit(declared: declared, referenced: referenced, unused: unused)
            }

            let fileURL = rootURL.appendingPathComponent(relativePath, isDirectory: false)
            guard isWithinPreparedRoot(fileURL, rootURL: rootURL) else {
                throw GoldenEyeSourceFrontendCatalogError.invalidRoot("GESM path escapes the prepared asset root: \(relativePath)")
            }
            let sidecarData: Data
            do {
                sidecarData = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            } catch {
                throw GoldenEyeSourceFrontendCatalogError.unreadablePacket("GESM \(relativePath): \(error)")
            }
            guard sidecarData.count == Int(byteCount), sidecarData.count >= 132 else {
                throw GoldenEyeSourceFrontendCatalogError.truncated("GESM \(relativePath)")
            }
            guard Data(sidecarData[0..<4]) == Data("GESM".utf8), readUInt32(sidecarData, at: 4) == 6 else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("GESM \(relativePath).magic/version")
            }
            let sidecarModelHandle = readUInt32(sidecarData, at: 8)
            let sidecarFlags = readUInt32(sidecarData, at: 12)
            let sidecarBytes = readUInt32(sidecarData, at: 16)
            let sidecarRecordCount = readUInt32(sidecarData, at: 20)
            let sidecarNodes = readUInt32(sidecarData, at: 24)
            let sidecarScalars = readUInt32(sidecarData, at: 28)
            let sidecarDisplayLists = readUInt32(sidecarData, at: 32)
            let sidecarCommands = readUInt32(sidecarData, at: 36)
            let sidecarTokens = readUInt32(sidecarData, at: 40)
            let sidecarVertices = readUInt32(sidecarData, at: 44)
            let sidecarTextures = readUInt32(sidecarData, at: 48)
            let sidecarMips = readUInt32(sidecarData, at: 52)
            let sidecarTluts = readUInt32(sidecarData, at: 56)
            let sidecarStringBytes = readUInt32(sidecarData, at: 60)
            let sidecarSourceSHA = Data(sidecarData[64..<96])
            let sidecarPacketSHA = Data(sidecarData[96..<128])
            let sidecarReserved = readUInt32(sidecarData, at: 128)
            guard sidecarModelHandle == modelHandle, sidecarFlags == flags, sidecarBytes == byteCount,
                  sidecarRecordCount == recordCount, sidecarNodes == nodes, sidecarScalars == scalars,
                  sidecarDisplayLists == displayLists, sidecarCommands == commands, sidecarTokens == tokens,
                  sidecarVertices == vertices, sidecarTextures == textures, sidecarMips == mips, sidecarTluts == tluts,
                  sidecarStringBytes <= byteCount, sidecarReserved == 0,
                  sidecarSourceSHA == sourceSHA, sidecarPacketSHA == packetSHA else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("GESM \(relativePath) metadata/header")
            }
            var canonicalSidecar = sidecarData
            canonicalSidecar.replaceSubrange(96..<128, with: Data(repeating: 0, count: 32))
            let actualPacketSHA = Data(SHA256.hash(data: canonicalSidecar))
            guard actualPacketSHA == packetSHA else {
                throw GoldenEyeSourceFrontendCatalogError.digestMismatch("GESM \(relativePath)", expected: hex(packetSHA), actual: hex(actualPacketSHA))
            }
            result.append(GoldenEyeSourceFrontendSidecar(
                name: name, family: family, path: relativePath,
                sourceSHA256: hex(sourceSHA), packetSHA256: hex(packetSHA), byteCount: byteCount,
                recordCount: recordCount, nodes: nodes, scalars: scalars, displayLists: displayLists,
                commands: commands, tokens: tokens, vertices: vertices, textures: textures,
                mips: mips, tluts: tluts, flags: flags, unsupportedMacros: unsupportedMacros, handleAudit: handleAudit
            ))
        }
        return result
    }

    private static func validateSidecarCompleteness(
        _ sidecars: [GoldenEyeSourceFrontendSidecar],
        records: [GoldenEyeSourceFrontendRecord],
        allowExtendedSidecars: Bool = false
    ) throws {
        if allowExtendedSidecars {
            guard sidecars.count > 8,
                  sidecars.allSatisfy({ sidecar in
                      sidecar.name == "rarewarelogo" || records.contains {
                          $0.category == "model" &&
                          $0.name == sidecar.name &&
                          $0.sourceSHA256 == sidecar.sourceSHA256
                      }
                  }) else {
                throw GoldenEyeSourceFrontendCatalogError.malformedManifest(
                    "extended GESM sidecar linkage is incomplete"
                )
            }
            return
        }
        let expectedNames: Set<String> = ["legalpage", "nintendologo", "rarewarelogo", "goldeneyelogo", "walletbond", "headbrosnansuit", "suitbond", "chrwppk"]
        guard Set(sidecars.map(\.name)) == expectedNames else {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("GESM sidecar set is incomplete")
        }
        for sidecar in sidecars {
            let sourceRecord = records.first {
                ($0.category == "model" && $0.name == sidecar.name) ||
                    ($0.category == "source_listing" && $0.family == "rareware" && sidecar.name == "rarewarelogo")
            }
            guard let sourceRecord, sourceRecord.sourceSHA256 == sidecar.sourceSHA256 else {
                throw GoldenEyeSourceFrontendCatalogError.malformedManifest("GESM source linkage is invalid for \(sidecar.name)")
            }
        }
    }

    private static func parseRecord(
        _ value: GoldenEyeSourceFrontendJSONValue,
        index: Int,
        payloadByteCount: UInt32
    ) throws -> GoldenEyeSourceFrontendRecord {
        let path = "manifest.records[\(index)]"
        let object = try requireObject(value, path: path)
        let baseKeys: Set<String> = [
            "category", "decoded_payload_offset", "decoded_sha256", "decoded_size", "family", "flags", "id", "metadata", "name", "raw_payload_offset", "raw_sha256", "raw_size", "source_path", "source_sha256", "source_size"
        ]
        let romKeys: Set<String> = ["compressed", "private_row", "rom_offset", "rom_row", "rom_size"]
        let objectKeys = Set(object.keys)
        guard objectKeys.isSubset(of: baseKeys.union(romKeys)) else {
            if let unknown = objectKeys.subtracting(baseKeys.union(romKeys)).sorted().first {
                throw GoldenEyeSourceFrontendCatalogError.unknownField("\(path).\(unknown)")
            }
            throw GoldenEyeSourceFrontendCatalogError.unknownField(path)
        }
        guard baseKeys.isSubset(of: objectKeys) else {
            if let missing = baseKeys.subtracting(objectKeys).sorted().first {
                throw GoldenEyeSourceFrontendCatalogError.malformedManifest("missing \(path).\(missing)")
            }
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("missing record field")
        }
        let id = try requireUInt32(object["id"], path: "\(path).id")
        let family = try requireString(object["family"], path: "\(path).family")
        let category = try requireString(object["category"], path: "\(path).category")
        guard (knownFamilies.contains(family) || family.hasPrefix("cast_"))
            || (Self.modelPayloadFamilies.contains(family) && (category == "texture_payload" || category == "mip_payload" || category == "tlut_payload")) else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).family")
        }
        guard requiredCategories.union(optionalCategories).contains(category), let kind = GoldenEyeSourceFrontendResourceKind(category: category) else {
            throw GoldenEyeSourceFrontendCatalogError.invalidCategory(category)
        }
        let name = try requireString(object["name"], path: "\(path).name")
        guard !name.isEmpty, name.count <= 512, name.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).name")
        }
        let sourcePath = try requireString(object["source_path"], path: "\(path).source_path")
        guard isRelativeSourcePath(sourcePath) else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).source_path")
        }
        let sourceSHA = try requireDigest(object["source_sha256"], path: "\(path).source_sha256")
        let rawSHA = try requireDigest(object["raw_sha256"], path: "\(path).raw_sha256")
        let decodedSHA = try requireDigest(object["decoded_sha256"], path: "\(path).decoded_sha256")
        let sourceSize = try requireUInt32(object["source_size"], path: "\(path).source_size")
        let rawSize = try requireUInt32(object["raw_size"], path: "\(path).raw_size")
        let decodedSize = try requireUInt32(object["decoded_size"], path: "\(path).decoded_size")
        guard sourceSize > 0, rawSize > 0, decodedSize > 0 else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path) byte size")
        }
        let rawPayloadOffset = try requireUInt32(object["raw_payload_offset"], path: "\(path).raw_payload_offset")
        let decodedPayloadOffset = try requireUInt32(object["decoded_payload_offset"], path: "\(path).decoded_payload_offset")
        guard UInt64(rawPayloadOffset) + UInt64(rawSize) <= UInt64(payloadByteCount),
              UInt64(decodedPayloadOffset) + UInt64(decodedSize) <= UInt64(payloadByteCount) else {
            throw GoldenEyeSourceFrontendCatalogError.payloadBounds("\(path)")
        }
        let flagsValue = try requireArray(object["flags"], path: "\(path).flags")
        var flags: [String] = []
        flags.reserveCapacity(flagsValue.count)
        for (flagIndex, flagValue) in flagsValue.enumerated() {
            let flag = try requireString(flagValue, path: "\(path).flags[\(flagIndex)]")
            guard knownFlags.contains(flag) else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).flags[\(flagIndex)]")
            }
            flags.append(flag)
        }
        guard flags == flags.sorted(), Set(flags).count == flags.count else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).flags ordering/duplicates")
        }
        let metadata = try requireObject(object["metadata"], path: "\(path).metadata")
        try validateMetadata(metadata, category: category, family: family, path: "\(path).metadata")
        try validatePixelPayload(
            category: category,
            family: family,
            metadata: metadata,
            flags: flags,
            sourceSize: sourceSize,
            rawSize: rawSize,
            decodedSize: decodedSize,
            sourceSHA: sourceSHA,
            decodedSHA: decodedSHA,
            path: path
        )

        let hasROMFields = !objectKeys.intersection(romKeys).isEmpty
        let hasROMPreparedFlag = flags.contains("ROM_PREPARED")
        guard hasROMFields == hasROMPreparedFlag else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path) ROM provenance fields")
        }
        var romOffset: UInt32?
        var romSize: UInt32?
        var romRow: String?
        var compressed: Bool?
        var privateRow: Bool?
        if hasROMFields {
            guard romKeys.isSubset(of: objectKeys) else {
                throw GoldenEyeSourceFrontendCatalogError.malformedManifest("missing \(path) ROM provenance field")
            }
            let offset = try requireUInt32(object["rom_offset"], path: "\(path).rom_offset")
            let size = try requireUInt32(object["rom_size"], path: "\(path).rom_size")
            guard size > 0, UInt64(offset) + UInt64(size) <= 12_582_912 else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).rom_offset/rom_size")
            }
            let row = try requireString(object["rom_row"], path: "\(path).rom_row")
            guard isRelativeSourcePath(row) else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).rom_row")
            }
            let isCompressed = try requireBool(object["compressed"], path: "\(path).compressed")
            let isPrivate = try requireUInt32(object["private_row"], path: "\(path).private_row")
            guard isPrivate <= 1, rawSize == size else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).private_row/raw_size")
            }
            romOffset = offset
            romSize = size
            romRow = row
            compressed = isCompressed
            privateRow = isPrivate == 1
        } else {
            romOffset = nil
            romSize = nil
            romRow = nil
            compressed = nil
            privateRow = nil
        }

        return GoldenEyeSourceFrontendRecord(
            id: id,
            family: family,
            category: category,
            kind: kind,
            name: name,
            sourcePath: sourcePath,
            sourceSHA256: hex(sourceSHA),
            rawSHA256: hex(rawSHA),
            decodedSHA256: hex(decodedSHA),
            sourceSize: sourceSize,
            rawSize: rawSize,
            decodedSize: decodedSize,
            rawPayloadOffset: rawPayloadOffset,
            decodedPayloadOffset: decodedPayloadOffset,
            flags: flags,
            metadata: .object(metadata),
            romOffset: romOffset,
            romSize: romSize,
            romRow: romRow,
            compressed: compressed,
            privateRow: privateRow,
            rawOffset: Int(rawPayloadOffset),
            decodedOffset: Int(decodedPayloadOffset)
        )
    }

    private static func validateCompleteness(
        _ records: [GoldenEyeSourceFrontendRecord],
        allowExtendedSidecars: Bool = false
    ) throws {
        let modelNames = Set(records.filter { $0.category == "model" }.map(\.name))
        let requiredModels: Set<String> = ["legalpage", "nintendologo", "goldeneyelogo", "walletbond", "headbrosnansuit", "suitbond", "chrwppk"]
        guard (allowExtendedSidecars ? modelNames.count > requiredModels.count : modelNames == requiredModels) else {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("model category is incomplete")
        }
        let imageNames = Set(records.filter { $0.category == "image_stream" }.map(\.name))
        let requiredImages: Set<String> = ["COPYICON", "DELICON", "SELECTFILE", "CROSSHAIR1", "CHECK", "DOT", "X"]
        guard requiredImages.isSubset(of: imageNames) else {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("global image category is incomplete")
        }
        guard records.contains(where: { $0.category == "blood" && $0.family == "gunbarrel" }),
              records.contains(where: { $0.category == "background" && $0.family == "gunbarrel" }),
              records.contains(where: { $0.category == "weapon_animation" && $0.family == "gunbarrel" }),
              records.contains(where: { $0.category == "sequence" && $0.family == "audio" }),
              records.contains(where: { $0.category == "bank" && $0.family == "audio" }) else {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("frontend dependency categories are incomplete")
        }
    }

    private static func validatePayloadLinkage(_ records: [GoldenEyeSourceFrontendRecord]) throws {
        let imageRecords = records.filter { $0.category == "image_stream" }
        var imageByRow: [String: GoldenEyeSourceFrontendRecord] = [:]
        for image in imageRecords {
            guard case let .object(metadata) = image.metadata,
                  let rowValue = metadata["source_row"],
                  case let .string(row) = rowValue,
                  imageByRow[row] == nil else {
                continue
            }
            imageByRow[row] = image
        }
        for record in records where record.category == "texture_payload" || record.category == "mip_payload" || record.category == "tlut_payload" {
            guard case let .object(metadata) = record.metadata,
                  let rowValue = metadata["source_row"],
                  case let .string(row) = rowValue else {
                continue
            }
            if record.category == "texture_payload",
               let imageIDValue = metadata["image_stream_record_id"],
               case let .integer(imageID) = imageIDValue {
                guard imageID > 0, imageID <= Int64(UInt32.max), let image = records.first(where: { $0.id == UInt32(imageID) && $0.category == "image_stream" }),
                      imageByRow[row]?.id == image.id else {
                    throw GoldenEyeSourceFrontendCatalogError.invalidValue("record id \(record.id) image-stream linkage")
                }
                guard record.decodedSize == image.decodedSize else {
                    throw GoldenEyeSourceFrontendCatalogError.invalidValue("record id \(record.id) base payload size linkage")
                }
            } else if record.family == "frontend" {
                guard imageByRow[row] != nil else {
                    throw GoldenEyeSourceFrontendCatalogError.invalidValue("record id \(record.id) global image linkage")
                }
            }
        }
    }

    private static func validatePixelPayload(
        category: String,
        family: String,
        metadata: [String: GoldenEyeSourceFrontendJSONValue],
        flags: [String],
        sourceSize: UInt32,
        rawSize: UInt32,
        decodedSize: UInt32,
        sourceSHA: Data,
        decodedSHA: Data,
        path: String
    ) throws {
        guard category == "texture_payload" || category == "mip_payload" || category == "tlut_payload" else {
            return
        }
        // A payload record must not alias the Model.c/source-listing bytes.
        // This catches the pre-correction catalog even when its envelope and
        // per-record hashes are internally consistent.
        guard rawSize > 0, decodedSize > 0,
              sourceSize != decodedSize || sourceSHA != decodedSHA else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path) decoded payload aliases source text")
        }
        guard flags.contains("DECODED_RGBA8") || flags.contains("DECODED_RGBA8_LEVELS") || flags.contains("DECODED_RGBA8_ENTRIES") || flags.contains("DECODED_RGBA8_BASE_LEVEL") else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path) lacks decoded RGBA8 payload flag")
        }
        if category == "texture_payload" {
            guard flags.contains("EMBEDDED_TEXELS") || flags.contains("RAREWARE_TEXELS") || flags.contains("GLOBAL_TEXTURE_PAYLOAD") else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path) lacks texture payload provenance flag")
            }
            let width = try requireUInt(metadata["width"], path: "\(path).metadata.width")
            let height = try requireUInt(metadata["height"], path: "\(path).metadata.height")
            let levels = try requireUInt(metadata["mip_levels"], path: "\(path).metadata.mip_levels")
            guard width > 0, height > 0, levels > 0, levels <= 32 else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).metadata dimensions")
            }
            var expected: UInt64 = 0
            if flags.contains("DECODED_RGBA8_BASE_LEVEL") {
                let basePixels = width.multipliedReportingOverflow(by: height)
                guard !basePixels.overflow else { throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).metadata dimensions") }
                let rgbaBytes = basePixels.partialValue.multipliedReportingOverflow(by: 4)
                guard !rgbaBytes.overflow else { throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).metadata dimensions") }
                expected = rgbaBytes.partialValue
            } else {
                for level in 0..<levels {
                    let levelWidth = max(1, width >> level)
                    let levelHeight = max(1, height >> level)
                    let levelBytes = levelWidth.multipliedReportingOverflow(by: levelHeight)
                    guard !levelBytes.overflow else { throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).metadata dimensions") }
                    let rgbaBytes = levelBytes.partialValue.multipliedReportingOverflow(by: 4)
                    guard !rgbaBytes.overflow else { throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).metadata dimensions") }
                    expected += rgbaBytes.partialValue
                }
            }
            guard expected == UInt64(decodedSize) else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path) decoded RGBA8 byte count")
            }
        } else if category == "mip_payload" {
            guard flags.contains("EMBEDDED_MIP") || flags.contains("GLOBAL_IMAGE_MIP") || flags.contains("RAREWARE_MIP") else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path) lacks mip payload provenance flag")
            }
            let width = try requireUInt(metadata["width"], path: "\(path).metadata.width")
            let height = try requireUInt(metadata["height"], path: "\(path).metadata.height")
            let pixels = width.multipliedReportingOverflow(by: height)
            guard !pixels.overflow else { throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).metadata dimensions") }
            let expected = pixels.partialValue.multipliedReportingOverflow(by: 4)
            guard !expected.overflow, expected.partialValue == UInt64(decodedSize) else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path) decoded RGBA8 byte count")
            }
            if family == "frontend" {
                guard metadata["derived_from_base"] != nil || flags.contains("SOURCE_AUTHORED_MIP") || flags.contains("SOURCE_GENERATED_MIP") else {
                    throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path) global mip provenance")
                }
            }
        } else {
            guard let entries = try? requireUInt(metadata["entries"], path: "\(path).metadata.entries"), entries > 0 else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).metadata.entries")
            }
            let expected = entries.multipliedReportingOverflow(by: 4)
            guard !expected.overflow, expected.partialValue == UInt64(decodedSize) else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path) decoded TLUT byte count")
            }
        }
    }

    private static func validateMetadata(
        _ object: [String: GoldenEyeSourceFrontendJSONValue],
        category: String,
        family: String,
        path: String
    ) throws {
        switch category {
        case "background":
            try requireExactKeys(object, allowed: ["rom_asset"], required: [], path: path)
            if let value = object["rom_asset"] { _ = try requireString(value, path: "\(path).rom_asset") }
        case "rareware_array_tail":
            let keys: Set<String> = ["source_offset", "source_row", "source_span"]
            try requireExactKeys(object, allowed: keys, required: keys, path: path)
            _ = try requireUInt(object["source_offset"], path: "\(path).source_offset")
            guard try requireUInt(object["source_span"], path: "\(path).source_span") > 0 else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).source_span")
            }
            _ = try requireString(object["source_row"], path: "\(path).source_row")
        case "blood":
            try requireExactKeys(object, allowed: ["format", "height", "width"], required: ["format", "height", "width"], path: path)
            _ = try requireString(object["format"], path: "\(path).format")
            guard try requireUInt(object["height"], path: "\(path).height") > 0,
                  try requireUInt(object["width"], path: "\(path).width") > 0 else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue(path)
            }
        case "display_list":
            try requireExactKeys(object, allowed: ["reachable"], required: [], path: path)
            if let value = object["reachable"] { _ = try requireBool(value, path: "\(path).reachable") }
        case "font", "font_packet":
            try requireExactKeys(object, allowed: ["glyph_count"], required: [], path: path)
            if let value = object["glyph_count"] { _ = try requireUInt(value, path: "\(path).glyph_count") }
        case "image_stream":
            let optionalKeys: Set<String> = [
                "mip_levels", "source_offset", "source_row", "explicit_lods",
                "encoded_lods", "source_level_count", "source_order",
                "inspection_order", "source_sha256", "derived_level_count", "image_stream_order"
            ]
            try requireExactKeys(object, allowed: Set(["height", "stream_compression", "stream_format", "width"]).union(optionalKeys), required: ["height", "stream_compression", "stream_format", "width"], path: path)
            guard try requireUInt(object["height"], path: "\(path).height") > 0,
                  try requireUInt(object["width"], path: "\(path).width") > 0 else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue(path)
            }
            _ = try requireUInt(object["stream_compression"], path: "\(path).stream_compression")
            _ = try requireUInt(object["stream_format"], path: "\(path).stream_format")
            if let mipLevels = object["mip_levels"] {
                guard try requireUInt(mipLevels, path: "\(path).mip_levels") > 0 else {
                    throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).mip_levels")
                }
            }
            if let sourceOffset = object["source_offset"] {
                _ = try requireUInt(sourceOffset, path: "\(path).source_offset")
            }
            if let sourceRow = object["source_row"] {
                _ = try requireString(sourceRow, path: "\(path).source_row")
            }
            for key in ["encoded_lods", "source_level_count"] where object[key] != nil {
                _ = try requireUInt(object[key], path: "\(path).\(key)")
            }
            if let explicit = object["explicit_lods"] { _ = try requireBool(explicit, path: "\(path).explicit_lods") }
            for key in ["source_order", "inspection_order", "source_sha256"] where object[key] != nil {
                _ = try requireString(object[key], path: "\(path).\(key)")
            }
        case "mip":
            try requireExactKeys(object, allowed: ["level", "texture", "texture_index"], required: ["level"], path: path)
            _ = try requireUInt(object["level"], path: "\(path).level")
            let hasTexture = object["texture"] != nil
            let hasTextureIndex = object["texture_index"] != nil
            guard hasTexture != hasTextureIndex else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).texture/texture_index")
            }
            if hasTexture { _ = try requireString(object["texture"], path: "\(path).texture") }
            if hasTextureIndex { _ = try requireUInt(object["texture_index"], path: "\(path).texture_index") }
        case "model_manifest":
            try requireExactKeys(object, allowed: ["counts"], required: ["counts"], path: path)
            try validateModelCounts(try requireObject(object["counts"], path: "\(path).counts"), path: "\(path).counts")
        case "node", "switch":
            try requireExactKeys(object, allowed: ["offset", "opcode"], required: ["offset", "opcode"], path: path)
            _ = try requireUInt(object["offset"], path: "\(path).offset")
            _ = try requireString(object["opcode"], path: "\(path).opcode")
        case "source_header":
            try requireExactKeys(object, allowed: ["track_count"], required: ["track_count"], path: path)
            _ = try requireUInt(object["track_count"], path: "\(path).track_count")
        case "source_listing":
            if family == "rareware" {
                try requireExactKeys(object, allowed: ["counts"], required: ["counts"], path: path)
                try validateRarewareCounts(try requireObject(object["counts"], path: "\(path).counts"), path: "\(path).counts")
            } else {
                try requireExactKeys(object, allowed: [], required: [], path: path)
            }
        case "text":
            try requireExactKeys(object, allowed: ["string_count"], required: ["string_count"], path: path)
            _ = try requireUInt(object["string_count"], path: "\(path).string_count")
        case "text_catalog":
            try requireExactKeys(object, allowed: ["legal_string_count", "string_count"], required: ["legal_string_count", "string_count"], path: path)
            _ = try requireUInt(object["legal_string_count"], path: "\(path).legal_string_count")
            _ = try requireUInt(object["string_count"], path: "\(path).string_count")
        case "texture_payload":
            let requiredKeys: Set<String> = ["height", "mip_levels", "source_offset", "source_row", "width"]
            let optionalKeys: Set<String> = [
                "image_stream_record_id", "source_span", "stream_compression", "stream_format",
                "explicit_lods", "encoded_lods", "source_level_count", "source_order",
                "inspection_order", "source_sha256", "derived_level_count", "image_stream_order"
            ]
            try requireExactKeys(object, allowed: requiredKeys.union(optionalKeys), required: requiredKeys, path: path)
            for key in ["height", "mip_levels", "width"] {
                guard try requireUInt(object[key], path: "\(path).\(key)") > 0 else {
                    throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).\(key)")
                }
            }
            _ = try requireUInt(object["source_offset"], path: "\(path).source_offset")
            _ = try requireString(object["source_row"], path: "\(path).source_row")
            for key in optionalKeys where object[key] != nil {
                if key == "source_span" {
                    guard try requireUInt(object[key], path: "\(path).\(key)") > 0 else {
                        throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).\(key)")
                    }
                } else if ["explicit_lods"].contains(key) {
                    _ = try requireBool(object[key], path: "\(path).\(key)")
                } else if ["source_order", "inspection_order", "source_sha256", "image_stream_order"].contains(key) {
                    _ = try requireString(object[key], path: "\(path).\(key)")
                } else {
                    _ = try requireUInt(object[key], path: "\(path).\(key)")
                }
            }
        case "mip_payload":
            let baseKeys: Set<String> = ["height", "level", "source_offset", "source_row", "texture_index", "width"]
            let optionalKeys: Set<String> = ["derived_from_base", "source_explicit", "source_generated", "source_order", "inspection_order", "source_storage_sha256"]
            try requireExactKeys(object, allowed: baseKeys.union(optionalKeys), required: baseKeys, path: path)
            for key in ["height", "level", "source_offset", "texture_index", "width"] {
                _ = try requireUInt(object[key], path: "\(path).\(key)")
            }
            _ = try requireString(object["source_row"], path: "\(path).source_row")
            for key in ["derived_from_base", "source_explicit", "source_generated"] {
                if let value = object[key] { _ = try requireBool(value, path: "\(path).\(key)") }
            }
            for key in ["source_order", "inspection_order", "source_storage_sha256"] {
                if let value = object[key] { _ = try requireString(value, path: "\(path).\(key)") }
            }
        case "tlut_payload":
            let baseKeys: Set<String> = ["entries", "format", "source_offset", "source_row"]
            try requireExactKeys(object, allowed: baseKeys, required: baseKeys, path: path)
            guard try requireUInt(object["entries"], path: "\(path).entries") > 0 else {
                throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).entries")
            }
            _ = try requireUInt(object["source_offset"], path: "\(path).source_offset")
            _ = try requireUInt(object["format"], path: "\(path).format")
            _ = try requireString(object["source_row"], path: "\(path).source_row")
        case "texture":
            if family == "rareware" {
                try requireExactKeys(object, allowed: ["format", "levels"], required: ["format", "levels"], path: path)
                _ = try requireString(object["format"], path: "\(path).format")
                _ = try requireUInt(object["levels"], path: "\(path).levels")
            } else {
                let keys: Set<String> = ["depth", "height", "index", "mip_levels", "mip_tiles", "resource", "s_flags", "t_flags", "type", "width"]
                try requireExactKeys(object, allowed: keys, required: keys, path: path)
                for key in keys where key != "format" && key != "resource" {
                    _ = try requireUInt(object[key], path: "\(path).\(key)")
                }
                _ = try requireString(object["resource"], path: "\(path).resource")
            }
        case "tlut":
            try requireExactKeys(object, allowed: ["palette_source", "texture_index"], required: ["palette_source", "texture_index"], path: path)
            _ = try requireString(object["palette_source"], path: "\(path).palette_source")
            _ = try requireUInt(object["texture_index"], path: "\(path).texture_index")
        case "vertex_group":
            if family == "rareware" {
                try requireExactKeys(object, allowed: [], required: [], path: path)
            } else {
                try requireExactKeys(object, allowed: ["count", "name"], required: ["count", "name"], path: path)
                _ = try requireString(object["name"], path: "\(path).name")
                _ = try requireUInt(object["count"], path: "\(path).count")
            }
        case "weapon_animation":
            try requireExactKeys(object, allowed: ["contains_muzzle_nodes"], required: ["contains_muzzle_nodes"], path: path)
            _ = try requireBool(object["contains_muzzle_nodes"], path: "\(path).contains_muzzle_nodes")
        case "model", "font_chardata", "font_display_list", "font_payload", "global_image_table", "rom_asset", "bank", "sequence", "soundbank":
            try requireExactKeys(object, allowed: [], required: [], path: path)
        default:
            throw GoldenEyeSourceFrontendCatalogError.invalidCategory(category)
        }
    }

    private static func validateModelCounts(_ object: [String: GoldenEyeSourceFrontendJSONValue], path: String) throws {
        let keys: Set<String> = ["display_list_count", "display_lists", "image_tokens", "name", "node_count", "nodes", "source_command_count", "switch_nodes", "switch_records", "texture_count", "textures", "tlut_commands", "vertex_groups", "vertex_total"]
        try requireExactKeys(object, allowed: keys, required: keys, path: path)
        _ = try requireUInt(object["display_list_count"], path: "\(path).display_list_count")
        _ = try requireString(object["name"], path: "\(path).name")
        for key in ["node_count", "source_command_count", "switch_nodes", "switch_records", "texture_count", "tlut_commands", "vertex_total"] {
            _ = try requireUInt(object[key], path: "\(path).\(key)")
        }
        try validateStringArray(try requireArray(object["display_lists"], path: "\(path).display_lists"), path: "\(path).display_lists")
        try validateStringArray(try requireArray(object["image_tokens"], path: "\(path).image_tokens"), path: "\(path).image_tokens")
        let vertexGroups = try requireArray(object["vertex_groups"], path: "\(path).vertex_groups")
        for (index, value) in vertexGroups.enumerated() {
            let group = try requireObject(value, path: "\(path).vertex_groups")
            try requireExactKeys(group, allowed: ["count", "name"], required: ["count", "name"], path: "\(path).vertex_groups")
            _ = try requireString(group["name"], path: "\(path).vertex_groups.name")
            _ = try requireUInt(group["count"], path: "\(path).vertex_groups.count")
            _ = index
        }
        for (index, value) in try requireArray(object["nodes"], path: "\(path).nodes").enumerated() {
            let node = try requireObject(value, path: "\(path).nodes[\(index)]")
            try requireExactKeys(node, allowed: ["offset", "opcode"], required: ["offset", "opcode"], path: "\(path).nodes[\(index)]")
            _ = try requireUInt(node["offset"], path: "\(path).nodes[\(index)].offset")
            _ = try requireString(node["opcode"], path: "\(path).nodes[\(index)].opcode")
        }
        for (index, value) in try requireArray(object["textures"], path: "\(path).textures").enumerated() {
            let texture = try requireObject(value, path: "\(path).textures[\(index)]")
            let textureKeys: Set<String> = ["depth", "height", "index", "mip_tiles", "resource", "s_flags", "t_flags", "type", "width"]
            try requireExactKeys(texture, allowed: textureKeys, required: textureKeys, path: "\(path).textures[\(index)]")
            for key in textureKeys where key != "resource" {
                _ = try requireUInt(texture[key], path: "\(path).textures[\(index)].\(key)")
            }
            _ = try requireString(texture["resource"], path: "\(path).textures[\(index)].resource")
        }
    }

    private static func validateRarewareCounts(_ object: [String: GoldenEyeSourceFrontendJSONValue], path: String) throws {
        let keys: Set<String> = ["display_lists", "extra_tile_sizes", "mip_chains", "payload_specs", "texture_arrays", "texture_image_order", "tile_size_commands", "vertex_arrays"]
        try requireExactKeys(object, allowed: keys, required: keys, path: path)
        for key in ["extra_tile_sizes", "tile_size_commands"] {
            _ = try requireUInt(object[key], path: "\(path).\(key)")
        }
        for key in ["display_lists", "texture_arrays", "texture_image_order", "vertex_arrays"] {
            try validateStringArray(try requireArray(object[key], path: "\(path).\(key)"), path: "\(path).\(key)")
        }
        for (index, value) in try requireArray(object["mip_chains"], path: "\(path).mip_chains").enumerated() {
            let chain = try requireObject(value, path: "\(path).mip_chains[\(index)]")
            try requireExactKeys(chain, allowed: ["levels", "texture"], required: ["levels", "texture"], path: "\(path).mip_chains[\(index)]")
            _ = try requireUInt(chain["levels"], path: "\(path).mip_chains[\(index)].levels")
            _ = try requireString(chain["texture"], path: "\(path).mip_chains[\(index)].texture")
        }
        if let payloadValue = object["payload_specs"] {
            let payloadSpecs = try requireObject(payloadValue, path: "\(path).payload_specs")
            for (key, value) in payloadSpecs {
                guard !key.isEmpty, key.allSatisfy({ $0.isNumber }) else {
                    throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).payload_specs.\(key)")
                }
                let spec = try requireObject(value, path: "\(path).payload_specs.\(key)")
                let specKeys: Set<String> = ["depth", "height", "levels", "mip_levels", "resource", "s_flags", "source_offset", "source_row_handle", "source_span", "t_flags", "texture_payload_name", "texture_record_id", "type", "width"]
                try requireExactKeys(spec, allowed: specKeys, required: specKeys, path: "\(path).payload_specs.\(key)")
                for field in ["depth", "height", "mip_levels", "s_flags", "source_offset", "source_row_handle", "source_span", "t_flags", "texture_record_id", "type", "width"] {
                    _ = try requireUInt(spec[field], path: "\(path).payload_specs.\(key).\(field)")
                }
                _ = try requireString(spec["resource"], path: "\(path).payload_specs.\(key).resource")
                _ = try requireString(spec["texture_payload_name"], path: "\(path).payload_specs.\(key).texture_payload_name")
                let levels = try requireArray(spec["levels"], path: "\(path).payload_specs.\(key).levels")
                guard !levels.isEmpty else { throw GoldenEyeSourceFrontendCatalogError.invalidValue("\(path).payload_specs.\(key).levels") }
                for (levelIndex, levelValue) in levels.enumerated() {
                    let level = try requireObject(levelValue, path: "\(path).payload_specs.\(key).levels[\(levelIndex)]")
                    let levelKeys: Set<String> = ["height", "level", "name", "record_id", "source_offset", "width"]
                    try requireExactKeys(level, allowed: levelKeys, required: levelKeys, path: "\(path).payload_specs.\(key).levels[\(levelIndex)]")
                    for field in ["height", "level", "record_id", "source_offset", "width"] {
                        _ = try requireUInt(level[field], path: "\(path).payload_specs.\(key).levels[\(levelIndex)].\(field)")
                    }
                    _ = try requireString(level["name"], path: "\(path).payload_specs.\(key).levels[\(levelIndex)].name")
                }
            }
        }
    }

    private static func validateStringArray(_ values: [GoldenEyeSourceFrontendJSONValue], path: String) throws {
        for (index, value) in values.enumerated() {
            _ = try requireString(value, path: "\(path)[\(index)]")
        }
    }

    private static func requireExactKeys(
        _ object: [String: GoldenEyeSourceFrontendJSONValue],
        allowed: Set<String>,
        required: Set<String>,
        path: String
    ) throws {
        if let unknown = Set(object.keys).subtracting(allowed).sorted().first {
            throw GoldenEyeSourceFrontendCatalogError.unknownField("\(path).\(unknown)")
        }
        if let missing = required.subtracting(Set(object.keys)).sorted().first {
            throw GoldenEyeSourceFrontendCatalogError.malformedManifest("missing \(path).\(missing)")
        }
    }

    private static func jsonValue(_ value: Any, path: String) throws -> GoldenEyeSourceFrontendJSONValue {
        if value is NSNull { return .null }
        if let string = value as? String { return .string(string) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue)
            }
            let double = number.doubleValue
            guard double.isFinite else { throw GoldenEyeSourceFrontendCatalogError.invalidValue(path) }
            if double.rounded() == double, double >= Double(Int64.min), double <= Double(Int64.max) {
                return .integer(Int64(double))
            }
            return .real(double)
        }
        if let array = value as? [Any] {
            return .array(try array.enumerated().map { try jsonValue($0.element, path: "\(path)[\($0.offset)]") })
        }
        if let object = value as? [String: Any] {
            var result: [String: GoldenEyeSourceFrontendJSONValue] = [:]
            for key in object.keys.sorted() {
                result[key] = try jsonValue(object[key] as Any, path: "\(path).\(key)")
            }
            return .object(result)
        }
        throw GoldenEyeSourceFrontendCatalogError.invalidValue(path)
    }

    private static func requireObject(_ value: GoldenEyeSourceFrontendJSONValue?, path: String) throws -> [String: GoldenEyeSourceFrontendJSONValue] {
        guard let value, case let .object(object) = value else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue(path)
        }
        return object
    }

    private static func requireArray(_ value: GoldenEyeSourceFrontendJSONValue?, path: String) throws -> [GoldenEyeSourceFrontendJSONValue] {
        guard let value, case let .array(array) = value else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue(path)
        }
        return array
    }

    private static func requireString(_ value: GoldenEyeSourceFrontendJSONValue?, path: String) throws -> String {
        guard let value, case let .string(string) = value else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue(path)
        }
        return string
    }

    private static func requireBool(_ value: GoldenEyeSourceFrontendJSONValue?, path: String) throws -> Bool {
        guard let value, case let .boolean(bool) = value else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue(path)
        }
        return bool
    }

    private static func requireUInt(_ value: GoldenEyeSourceFrontendJSONValue?, path: String) throws -> UInt64 {
        guard let value, case let .integer(integer) = value, integer >= 0 else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue(path)
        }
        return UInt64(integer)
    }

    private static func requireUInt32(_ value: GoldenEyeSourceFrontendJSONValue?, path: String) throws -> UInt32 {
        let number = try requireUInt(value, path: path)
        guard number <= UInt64(UInt32.max) else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue(path)
        }
        return UInt32(number)
    }

    private static func requireDigest(_ value: GoldenEyeSourceFrontendJSONValue?, path: String) throws -> Data {
        let string = try requireString(value, path: path)
        guard string.count == 64, string.unicodeScalars.allSatisfy({
            ($0.value >= 48 && $0.value <= 57) || ($0.value >= 97 && $0.value <= 102)
        }) else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue(path)
        }
        guard let data = Data(hexString: string), data.count == 32, data.contains(where: { $0 != 0 }) else {
            throw GoldenEyeSourceFrontendCatalogError.invalidValue(path)
        }
        return data
    }

    private static func isRelativeSourcePath(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.contains("\\"), value.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) else { return false }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return false }
        return components.allSatisfy { component in component != "." && component != ".." && !component.isEmpty }
    }

    private static func isWithinPreparedRoot(_ fileURL: URL, rootURL: URL) -> Bool {
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let file = fileURL.resolvingSymlinksInPath().standardizedFileURL.path
        return file == root || file.hasPrefix(root + "/")
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private static func hex(_ digest: Data) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension Data {
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var data = Data()
        data.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        for _ in 0..<(hexString.count / 2) {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
