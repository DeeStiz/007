import CryptoKit
import Foundation

/// Source-derived visual work which is not a model display-list draw.  The
/// stage model composer owns props and characters; this sidecar owns the
/// value-only seam for sky, fades, frontend/gameplay HUD, watch overlays, and
/// transient source effects.  It deliberately does not manufacture a visual
/// when the source producer has not supplied state for the current frame.
public enum GoldenEyeRamRomNonModelVisualCategoryV6: String, CaseIterable, Sendable, Equatable, Hashable {
    case sky
    case fades
    case hud
    case watch
    case particles
    case effects
    case glass
    case explosions
    case projectiles

    public var expectedManifestCount: Int {
        switch self {
        case .sky: return 9
        case .fades: return 1
        case .hud: return 81
        case .watch: return 8
        case .particles: return 42
        case .effects: return 1
        case .glass: return 8
        case .explosions: return 14
        case .projectiles: return 14
        }
    }

    var semanticSourceSymbol: String? {
        switch self {
        case .fades: return "screen_fade_to_black/from_black"
        case .effects: return "gunfire_effect_dispatch"
        case .particles: return "particle_effect_dispatch"
        case .explosions: return "explosion_render_dispatch"
        case .sky: return "stage_sky_state"
        default: return nil
        }
    }
}

public struct GoldenEyeRamRomNonModelDependencyV6: Sendable, Equatable {
    public let category: GoldenEyeRamRomNonModelVisualCategoryV6
    public let symbol: String
    public let sourcePath: String
    public let sourceSHA256: String
    public let sourceBytes: UInt32
    public let decodedBytes: UInt32
    public let decodedSHA256: String
    public let rawFile: String?
    public let decodedFile: String?
    public let rawURL: URL?
    public let decodedURL: URL?
    public let demoIDs: [UInt8]
    public let stages: [String]
    public let dependencyKind: String?
    public let renderDependency: String?
    public let semantic: Bool
    public let resourceHandle: UInt32

    public var hasPreparedPayload: Bool { decodedURL != nil && decodedBytes > 0 }
}

public enum GoldenEyeRamRomNonModelCatalogError: Error, Sendable, Equatable, CustomStringConvertible {
    case missingManifest(URL)
    case malformedManifest(String)
    case provenance(String)
    case unknownCategory(String)
    case duplicateSymbol(String)
    case invalidRow(String)
    case pathEscapes(String)
    case missingPayload(String)
    case payloadSize(String, Int, Int)
    case payloadDigest(String, String, String)
    case handleCollision(String)

    public var description: String {
        switch self {
        case let .missingManifest(url): return "non-model manifest is missing: \(url.path)"
        case let .malformedManifest(detail): return "non-model manifest is malformed: \(detail)"
        case let .provenance(detail): return "non-model provenance guard failed: \(detail)"
        case let .unknownCategory(value): return "non-model manifest category is unknown: \(value)"
        case let .duplicateSymbol(value): return "non-model manifest symbol is duplicated: \(value)"
        case let .invalidRow(value): return "non-model manifest row is invalid: \(value)"
        case let .pathEscapes(value): return "non-model payload path escapes its root: \(value)"
        case let .missingPayload(value): return "non-model prepared payload is missing: \(value)"
        case let .payloadSize(name, actual, expected):
            return "non-model payload \(name) size \(actual) != \(expected)"
        case let .payloadDigest(name, expected, actual):
            return "non-model payload \(name) digest \(actual) != \(expected)"
        case let .handleCollision(value): return "non-model resource handle collision: \(value)"
        }
    }
}

/// A strict view of only the nine non-model categories in the guarded
/// 953-row RAMROM manifest.  Payload bytes are checked while loading and are
/// not retained.  Only private prepared-file URLs and fixed-width metadata
/// cross this boundary; the runtime never opens the ROM.
public struct GoldenEyeRamRomNonModelDependencyCatalogV6: Sendable, Equatable {
    public static let manifestFileName = "ramrom-visible-dependencies-v6-manifest.txt"
    public static let expectedManifestDependencyCount = 953
    public static let expectedNonModelDependencyCount = 178

    public let rootURL: URL
    public let manifestURL: URL
    public let manifestSHA256: String
    public let dependencies: [GoldenEyeRamRomNonModelDependencyV6]

    public var isComplete: Bool {
        dependencies.count == Self.expectedNonModelDependencyCount
            && GoldenEyeRamRomNonModelVisualCategoryV6.allCases.allSatisfy { category in
                dependencies.filter { $0.category == category }.count == category.expectedManifestCount
            }
    }

    public var payloadCount: Int { dependencies.filter(\.hasPreparedPayload).count }
    public var semanticCount: Int { dependencies.filter(\.semantic).count }
    public var coveredDemoIDs: Set<UInt8> {
        Set(dependencies.flatMap(\.demoIDs))
    }
    public var coveredStages: Set<String> {
        Set(dependencies.flatMap(\.stages))
    }

    public func dependencies(
        category: GoldenEyeRamRomNonModelVisualCategoryV6
    ) -> [GoldenEyeRamRomNonModelDependencyV6] {
        dependencies.filter { $0.category == category }
    }

    public func dependency(
        category: GoldenEyeRamRomNonModelVisualCategoryV6,
        symbol: String
    ) -> GoldenEyeRamRomNonModelDependencyV6? {
        dependencies.first { $0.category == category && $0.symbol == symbol }
    }

    public static func load(rootURL: URL) throws -> Self {
        let root = rootURL.standardizedFileURL
        let manifest = root.appendingPathComponent(Self.manifestFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            throw GoldenEyeRamRomNonModelCatalogError.missingManifest(manifest)
        }
        let data: Data
        do { data = try Data(contentsOf: manifest, options: [.mappedIfSafe]) }
        catch { throw GoldenEyeRamRomNonModelCatalogError.malformedManifest(String(describing: error)) }
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        var values: [String: String] = [:]
        var rows: [(Int, String)] = []
        for line in lines {
            guard let equal = line.firstIndex(of: "=") else {
                throw GoldenEyeRamRomNonModelCatalogError.malformedManifest("missing =")
            }
            let key = String(line[..<equal])
            let payload = String(line[line.index(after: equal)...])
            if key.hasPrefix("dependency_"), let index = Int(key.dropFirst("dependency_".count)) {
                rows.append((index, payload))
            } else if !(key.hasPrefix("demo_") && Int(key.dropFirst("demo_".count)) != nil) {
                values[key] = payload
            }
        }
        let requiredValues = [
            "manifest_version": "6",
            "asset_family": "ramrom_visible_dependencies_v6",
            "manifest_status": "PASS",
            "coverage_status": "PASS",
            "payload_status": "PASS",
            "source_trace_status": "PASS",
            "external_rom_size": "12582912",
            "external_rom_sha1": "abe01e4aeb033b6c0836819f549c791b26cfde83",
            "runtime_opens_rom": "false",
            "runtime_consumes_prepared_payloads_only": "true",
            "emulation_used": "false",
            "demo_count": "14",
            "stage_count": "7",
            "dependency_count": String(Self.expectedManifestDependencyCount),
            "category_count": "16",
        ]
        for (key, expected) in requiredValues where values[key] != expected {
            throw GoldenEyeRamRomNonModelCatalogError.provenance("\(key)=\(values[key] ?? "<missing>") expected \(expected)")
        }
        guard rows.count == Self.expectedManifestDependencyCount else {
            throw GoldenEyeRamRomNonModelCatalogError.provenance("dependency row count \(rows.count)")
        }

        let nonModelCategories = Set(GoldenEyeRamRomNonModelVisualCategoryV6.allCases.map(\.rawValue))
        var parsed: [GoldenEyeRamRomNonModelDependencyV6] = []
        var seenSymbols: Set<String> = []
        var seenHandles: [UInt32: String] = [:]
        for (_, payload) in rows.sorted(by: { $0.0 < $1.0 }) {
            let fields = Dictionary(uniqueKeysWithValues: payload.split(separator: "|").compactMap {
                part -> (String, String)? in
                let pair = part.split(separator: ":", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { return nil }
                return (pair[0], pair[1])
            })
            guard let categoryText = fields["category"], nonModelCategories.contains(categoryText) else {
                continue
            }
            guard let category = GoldenEyeRamRomNonModelVisualCategoryV6(rawValue: categoryText),
                  let symbol = fields["symbol"], !symbol.isEmpty,
                  let sourcePath = fields["source_path"], !sourcePath.isEmpty,
                  let sourceSHA = fields["source_sha256"],
                  let sourceBytes = UInt32(fields["source_bytes"] ?? ""),
                  let decodedBytes = UInt32(fields["decoded_bytes"] ?? ""),
                  let decodedSHA = fields["decoded_sha256"],
                  let demoText = fields["demo_ids"], !demoText.isEmpty,
                  let stagesText = fields["stages"], !stagesText.isEmpty else {
                throw GoldenEyeRamRomNonModelCatalogError.invalidRow(categoryText)
            }
            guard seenSymbols.insert(symbol).inserted else {
                throw GoldenEyeRamRomNonModelCatalogError.duplicateSymbol(symbol)
            }
            let semantic = fields["asset_type"] == "semantic"
            let rawFileText = fields["raw_file"]
            let decodedFileText = fields["decoded_file"]
            let rawFile: String?
            let decodedFile: String?
            if semantic {
                guard rawFileText == "none", decodedFileText == "none",
                      sourceBytes == 0, decodedBytes == 0 else {
                    throw GoldenEyeRamRomNonModelCatalogError.invalidRow("semantic payload \(symbol)")
                }
                rawFile = nil
                decodedFile = nil
            } else {
                guard let raw = rawFileText, let decoded = decodedFileText,
                      raw != "none", decoded != "none" else {
                    throw GoldenEyeRamRomNonModelCatalogError.invalidRow("payload paths \(symbol)")
                }
                rawFile = raw
                decodedFile = decoded
            }
            let rawURL = try payloadURL(root: root, file: rawFile)
            let decodedURL = try payloadURL(root: root, file: decodedFile)
            if let rawURL {
                try validatePayload(root: root, url: rawURL, expectedBytes: Int(sourceBytes), digest: sourceSHA, symbol: symbol)
            }
            if let decodedURL {
                try validatePayload(root: root, url: decodedURL, expectedBytes: Int(decodedBytes), digest: decodedSHA, symbol: symbol)
            }
            let handle = resourceHandle(category: category, symbol: symbol)
            if let prior = seenHandles.updateValue(symbol, forKey: handle), prior != symbol {
                throw GoldenEyeRamRomNonModelCatalogError.handleCollision("\(prior) / \(symbol)")
            }
            let demoIDs = demoText.split(separator: ",").compactMap { UInt8($0) }
            guard !demoIDs.isEmpty, demoIDs.allSatisfy({ (1...14).contains(Int($0)) }) else {
                throw GoldenEyeRamRomNonModelCatalogError.invalidRow("demo route \(symbol)")
            }
            parsed.append(GoldenEyeRamRomNonModelDependencyV6(
                category: category, symbol: symbol, sourcePath: sourcePath,
                sourceSHA256: sourceSHA, sourceBytes: sourceBytes,
                decodedBytes: decodedBytes, decodedSHA256: decodedSHA,
                rawFile: rawFile, decodedFile: decodedFile,
                rawURL: rawURL, decodedURL: decodedURL, demoIDs: demoIDs,
                stages: stagesText.split(separator: ",").map(String.init),
                dependencyKind: fields["dependency_kind"],
                renderDependency: fields["render_dependency"] ?? fields["asset_role"],
                semantic: semantic, resourceHandle: handle
            ))
        }
        for category in GoldenEyeRamRomNonModelVisualCategoryV6.allCases {
            let count = parsed.filter { $0.category == category }.count
            guard count == category.expectedManifestCount else {
                throw GoldenEyeRamRomNonModelCatalogError.provenance(
                    "category \(category.rawValue) count \(count) expected \(category.expectedManifestCount)"
                )
            }
        }
        return Self(
            rootURL: root, manifestURL: manifest,
            manifestSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            dependencies: parsed
        )
    }

    public static func resourceHandle(
        category: GoldenEyeRamRomNonModelVisualCategoryV6,
        symbol: String
    ) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in (category.rawValue + ":" + symbol).utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return 0xD600_0000 | (hash & 0x00FF_FFFF)
    }

    public static func expectedStageID(for demoID: UInt8) -> UInt32? {
        switch demoID {
        case 1, 2: return 33
        case 3, 4, 5: return 34
        case 6, 7: return 35
        case 8, 9: return 9
        case 10, 11: return 20
        case 12, 13: return 26
        case 14: return 25
        default: return nil
        }
    }

    private static func payloadURL(root: URL, file: String?) throws -> URL? {
        guard let file else { return nil }
        guard !file.isEmpty, !file.hasPrefix("/"), !file.split(separator: "/").contains("..") else {
            throw GoldenEyeRamRomNonModelCatalogError.pathEscapes(file)
        }
        let url = root.appendingPathComponent(file, isDirectory: false).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else {
            throw GoldenEyeRamRomNonModelCatalogError.pathEscapes(file)
        }
        return url
    }

    private static func validatePayload(
        root: URL,
        url: URL,
        expectedBytes: Int,
        digest: String,
        symbol: String
    ) throws {
        guard url.path.hasPrefix(root.path + "/") else {
            throw GoldenEyeRamRomNonModelCatalogError.pathEscapes(url.path)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw GoldenEyeRamRomNonModelCatalogError.missingPayload(symbol)
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == expectedBytes else {
            throw GoldenEyeRamRomNonModelCatalogError.payloadSize(symbol, data.count, expectedBytes)
        }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == digest else {
            throw GoldenEyeRamRomNonModelCatalogError.payloadDigest(symbol, digest, actual)
        }
    }
}

public struct GoldenEyeRamRomQ16Vector3V6: Sendable, Equatable {
    public let x: Int32
    public let y: Int32
    public let z: Int32
    public init(x: Int32, y: Int32, z: Int32) { self.x = x; self.y = y; self.z = z }
}

public struct GoldenEyeRamRomSkyStateV6: Sendable, Equatable {
    public let stageID: UInt32
    public let demoID: UInt8
    public let backgroundSymbol: String
    public let cloudSymbol: String?
    public let cloudOffsetQ16: Int32
    public let environmentRGBA8: UInt32
    public let cloudRGBA8: UInt32
    public let waterRGBA8: UInt32
    public let flags: UInt32

    public init(
        stageID: UInt32, demoID: UInt8, backgroundSymbol: String,
        cloudSymbol: String? = nil, cloudOffsetQ16: Int32,
        environmentRGBA8: UInt32, cloudRGBA8: UInt32,
        waterRGBA8: UInt32, flags: UInt32 = 0
    ) {
        self.stageID = stageID; self.demoID = demoID; self.backgroundSymbol = backgroundSymbol
        self.cloudSymbol = cloudSymbol; self.cloudOffsetQ16 = cloudOffsetQ16
        self.environmentRGBA8 = environmentRGBA8; self.cloudRGBA8 = cloudRGBA8
        self.waterRGBA8 = waterRGBA8; self.flags = flags
    }
}

public struct GoldenEyeRamRomFadeStateV6: Sendable, Equatable {
    public let stageID: UInt32
    public let demoID: UInt8
    public let elapsedQ16: UInt32
    public let durationQ16: UInt32
    public let colourRGBA8: UInt32
    public let fractionQ16: UInt32
    public let flags: UInt32

    public init(
        stageID: UInt32, demoID: UInt8, elapsedQ16: UInt32,
        durationQ16: UInt32, colourRGBA8: UInt32, fractionQ16: UInt32,
        flags: UInt32 = 0
    ) {
        self.stageID = stageID; self.demoID = demoID; self.elapsedQ16 = elapsedQ16
        self.durationQ16 = durationQ16; self.colourRGBA8 = colourRGBA8
        self.fractionQ16 = fractionQ16; self.flags = flags
    }
}

public struct GoldenEyeRamRomHUDImagePlacementV6: Sendable, Equatable {
    public let symbol: String
    public let xQ16: Int32
    public let yQ16: Int32
    public let width: UInt32
    public let height: UInt32
    public let tintRGBA8: UInt32
    public let flags: UInt32

    public init(
        symbol: String, xQ16: Int32, yQ16: Int32,
        width: UInt32, height: UInt32, tintRGBA8: UInt32 = 0xffff_ffff,
        flags: UInt32 = GoldenEyeRamRomNonModelVisualEntryFlagsV6.textured
    ) {
        self.symbol = symbol; self.xQ16 = xQ16; self.yQ16 = yQ16
        self.width = width; self.height = height; self.tintRGBA8 = tintRGBA8
        self.flags = flags
    }
}

public struct GoldenEyeRamRomHUDStateV6: Sendable, Equatable {
    public let visible: Bool
    public let weaponTableIndex: UInt32
    public let ammoType: UInt32
    public let ammoInMagazine: UInt32
    public let ammoReserve: UInt32
    public let crosshairXQ16: Int32
    public let crosshairYQ16: Int32
    public let imageSymbols: [String]
    public let imagePlacements: [GoldenEyeRamRomHUDImagePlacementV6]

    public init(
        visible: Bool, weaponTableIndex: UInt32, ammoType: UInt32,
        ammoInMagazine: UInt32, ammoReserve: UInt32,
        crosshairXQ16: Int32, crosshairYQ16: Int32,
        imageSymbols: [String],
        imagePlacements: [GoldenEyeRamRomHUDImagePlacementV6] = []
    ) {
        self.visible = visible; self.weaponTableIndex = weaponTableIndex; self.ammoType = ammoType
        self.ammoInMagazine = ammoInMagazine; self.ammoReserve = ammoReserve
        self.crosshairXQ16 = crosshairXQ16; self.crosshairYQ16 = crosshairYQ16
        self.imageSymbols = imageSymbols; self.imagePlacements = imagePlacements
    }
}

public struct GoldenEyeRamRomWatchStateV6: Sendable, Equatable {
    public let visible: Bool
    public let sourceSymbol: String
    public let animateButtons: Bool
    public let controllerPad: Int8
    public let imageSymbols: [String]
    public let positionQ16: GoldenEyeRamRomQ16Vector3V6?
    public let scaleQ16: UInt32?

    public init(
        visible: Bool, sourceSymbol: String, animateButtons: Bool,
        controllerPad: Int8, imageSymbols: [String] = [],
        positionQ16: GoldenEyeRamRomQ16Vector3V6? = nil,
        scaleQ16: UInt32? = nil
    ) {
        self.visible = visible; self.sourceSymbol = sourceSymbol
        self.animateButtons = animateButtons; self.controllerPad = controllerPad
        self.imageSymbols = imageSymbols; self.positionQ16 = positionQ16; self.scaleQ16 = scaleQ16
    }
}

public enum GoldenEyeRamRomTransientVisualCategoryV6: String, CaseIterable, Sendable, Equatable, Hashable {
    case particles, effects, glass, explosions, projectiles
}

public struct GoldenEyeRamRomTransientVisualEventV6: Sendable, Equatable {
    public let category: GoldenEyeRamRomTransientVisualCategoryV6
    public let sourceSymbol: String
    public let resourceSymbol: String
    public let sourceReferenceTick: UInt64
    public let sequence: UInt32
    public let positionQ16: GoldenEyeRamRomQ16Vector3V6
    public let scaleQ16: UInt32
    public let rotationQ16: Int32
    public let frameIndex: UInt32
    public let colourRGBA8: UInt32
    public let alphaQ16: UInt32
    public let flags: UInt32

    public init(
        category: GoldenEyeRamRomTransientVisualCategoryV6, sourceSymbol: String,
        resourceSymbol: String, sourceReferenceTick: UInt64, sequence: UInt32,
        positionQ16: GoldenEyeRamRomQ16Vector3V6, scaleQ16: UInt32,
        rotationQ16: Int32, frameIndex: UInt32, colourRGBA8: UInt32,
        alphaQ16: UInt32, flags: UInt32 = 0
    ) {
        self.category = category; self.sourceSymbol = sourceSymbol; self.resourceSymbol = resourceSymbol
        self.sourceReferenceTick = sourceReferenceTick; self.sequence = sequence
        self.positionQ16 = positionQ16; self.scaleQ16 = scaleQ16; self.rotationQ16 = rotationQ16
        self.frameIndex = frameIndex; self.colourRGBA8 = colourRGBA8; self.alphaQ16 = alphaQ16
        self.flags = flags
    }
}

public struct GoldenEyeRamRomNonModelSourceFrameV6: Sendable, Equatable {
    public let stageID: UInt32
    public let demoID: UInt8
    public let nativeTick: UInt64
    public let sky: GoldenEyeRamRomSkyStateV6?
    public let fade: GoldenEyeRamRomFadeStateV6?
    public let hud: GoldenEyeRamRomHUDStateV6?
    public let watch: GoldenEyeRamRomWatchStateV6?
    public let transientEvents: [GoldenEyeRamRomTransientVisualEventV6]
    public let explicitlyInactive: Set<GoldenEyeRamRomNonModelVisualCategoryV6>

    public init(
        stageID: UInt32, demoID: UInt8, nativeTick: UInt64,
        sky: GoldenEyeRamRomSkyStateV6? = nil,
        fade: GoldenEyeRamRomFadeStateV6? = nil,
        hud: GoldenEyeRamRomHUDStateV6? = nil,
        watch: GoldenEyeRamRomWatchStateV6? = nil,
        transientEvents: [GoldenEyeRamRomTransientVisualEventV6] = [],
        explicitlyInactive: Set<GoldenEyeRamRomNonModelVisualCategoryV6> = []
    ) {
        self.stageID = stageID; self.demoID = demoID; self.nativeTick = nativeTick
        self.sky = sky; self.fade = fade; self.hud = hud; self.watch = watch
        self.transientEvents = transientEvents; self.explicitlyInactive = explicitlyInactive
    }
}

public enum GoldenEyeRamRomNonModelVisualEntryKindV6: UInt32, Sendable, Equatable {
    case sky = 1, cloud = 2, fade = 3, hud = 4, watch = 5
    case particle = 6, effect = 7, glass = 8, explosion = 9, projectile = 10
}

public enum GoldenEyeRamRomNonModelVisualEntryFlagsV6 {
    public static let fullScreen: UInt32 = 1 << 0
    public static let textured: UInt32 = 1 << 1
    public static let alphaBlend: UInt32 = 1 << 2
    public static let sourceAnchor: UInt32 = 1 << 3
}

public struct GoldenEyeRamRomNonModelVisualEntryV6: Sendable, Equatable {
    public let kind: GoldenEyeRamRomNonModelVisualEntryKindV6
    public let category: GoldenEyeRamRomNonModelVisualCategoryV6
    public let sourceSymbol: String
    public let resourceSymbol: String?
    public let resourceHandle: UInt32
    public let sequence: UInt32
    public let positionQ16: GoldenEyeRamRomQ16Vector3V6
    public let scaleQ16: UInt32
    public let rotationQ16: Int32
    public let frameIndex: UInt32
    public let colourRGBA8: UInt32
    public let alphaQ16: UInt32
    public let flags: UInt32
}

public enum GoldenEyeRamRomNonModelVisualDiagnosticCodeV6: UInt32, Sendable, Equatable {
    case missingSourceState = 1
    case missingDependency = 2
    case invalidState = 3
    case unsupportedSourceProducer = 4
}

public struct GoldenEyeRamRomNonModelVisualDiagnosticV6: Sendable, Equatable {
    public let code: GoldenEyeRamRomNonModelVisualDiagnosticCodeV6
    public let category: GoldenEyeRamRomNonModelVisualCategoryV6
    public let sourceSymbol: String
    public let detail: String
}

public struct GoldenEyeRamRomNonModelVisualCompositionV6: Sendable, Equatable {
    public let stageID: UInt32
    public let demoID: UInt8
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let entries: [GoldenEyeRamRomNonModelVisualEntryV6]
    public let diagnostics: [GoldenEyeRamRomNonModelVisualDiagnosticV6]
    public let sourceManifestSHA256: String
    public let compositionHash: UInt64

    public var isPresentable: Bool { diagnostics.isEmpty }
    public var unsupportedCategoryCount: Int {
        Set(diagnostics.map(\.category)).count
    }
}

public enum GoldenEyeRamRomNonModelVisualCompositionError: Error, Sendable, Equatable, CustomStringConvertible {
    case strictDiagnostics([GoldenEyeRamRomNonModelVisualDiagnosticV6])
    case invalidTick
    public var description: String {
        switch self {
        case let .strictDiagnostics(values): return "non-model composition is fail-closed (\(values.count) diagnostics)"
        case .invalidTick: return "non-model source frame native tick must be non-zero"
        }
    }
}

/// Composes source-produced visual state into a bounded ordered packet.  It
/// is intentionally not a renderer: the stage owner can pass the packet to a
/// 2D/GBI lowerer, while missing source gameplay state remains visible as a
/// diagnostic instead of becoming a guessed billboard or HUD.
public enum GoldenEyeRamRomNonModelVisualCompositionAdapterV6 {
    public static func compose(
        catalog: GoldenEyeRamRomNonModelDependencyCatalogV6,
        frame: GoldenEyeRamRomNonModelSourceFrameV6,
        strict: Bool = false
    ) throws -> GoldenEyeRamRomNonModelVisualCompositionV6 {
        var entries: [GoldenEyeRamRomNonModelVisualEntryV6] = []
        var diagnostics: [GoldenEyeRamRomNonModelVisualDiagnosticV6] = []
        if GoldenEyeRamRomNonModelDependencyCatalogV6.expectedStageID(for: frame.demoID) != frame.stageID {
            diagnostics.append(.init(
                code: .invalidState, category: .sky, sourceSymbol: "stage_sky_state",
                detail: "demo/stage route is not one of the seven source RAMROM pairings"
            ))
        }
        func inactive(_ category: GoldenEyeRamRomNonModelVisualCategoryV6) -> Bool {
            frame.explicitlyInactive.contains(category)
        }
        func addMissing(_ category: GoldenEyeRamRomNonModelVisualCategoryV6, _ symbol: String) {
            if !inactive(category) {
                diagnostics.append(.init(code: .missingSourceState, category: category,
                                         sourceSymbol: symbol,
                                         detail: "source producer state was not supplied for this frame"))
            }
        }
        func dependency(
            _ category: GoldenEyeRamRomNonModelVisualCategoryV6,
            _ symbol: String,
            requiredPayload: Bool = false
        ) -> GoldenEyeRamRomNonModelDependencyV6? {
            guard let value = catalog.dependency(category: category, symbol: symbol) else {
                diagnostics.append(.init(code: .missingDependency, category: category,
                                         sourceSymbol: symbol, detail: "manifest dependency is missing"))
                return nil
            }
            if requiredPayload && !value.hasPreparedPayload {
                diagnostics.append(.init(code: .missingDependency, category: category,
                                         sourceSymbol: symbol, detail: "prepared payload is required for visible lowering"))
                return nil
            }
            guard value.demoIDs.contains(frame.demoID) else {
                diagnostics.append(.init(code: .invalidState, category: category,
                                         sourceSymbol: symbol, detail: "dependency is not in this RAMROM route"))
                return nil
            }
            return value
        }
        func appendEntry(
            kind: GoldenEyeRamRomNonModelVisualEntryKindV6,
            category: GoldenEyeRamRomNonModelVisualCategoryV6,
            sourceSymbol: String, resourceSymbol: String?, resourceHandle: UInt32,
            sequence: UInt32 = 0, position: GoldenEyeRamRomQ16Vector3V6 = .init(x: 0, y: 0, z: 0),
            scale: UInt32 = 65_536, rotation: Int32 = 0, frameIndex: UInt32 = 0,
            colour: UInt32 = 0xffff_ffff, alpha: UInt32 = 65_536, flags: UInt32 = 0
        ) {
            entries.append(.init(kind: kind, category: category, sourceSymbol: sourceSymbol,
                                 resourceSymbol: resourceSymbol, resourceHandle: resourceHandle,
                                 sequence: sequence, positionQ16: position, scaleQ16: scale,
                                 rotationQ16: rotation, frameIndex: frameIndex,
                                 colourRGBA8: colour, alphaQ16: alpha, flags: flags))
        }

        if let sky = frame.sky {
            if sky.stageID != frame.stageID || sky.demoID != frame.demoID {
                diagnostics.append(.init(code: .invalidState, category: .sky,
                                         sourceSymbol: sky.backgroundSymbol, detail: "sky stage/demo does not match source frame"))
            }
            if sky.stageID == frame.stageID, sky.demoID == frame.demoID,
               let background = dependency(.sky, sky.backgroundSymbol, requiredPayload: true) {
                appendEntry(kind: .sky, category: .sky, sourceSymbol: "stage_sky_state",
                            resourceSymbol: background.symbol, resourceHandle: background.resourceHandle,
                            colour: sky.environmentRGBA8, flags: sky.flags)
            }
            if let cloudSymbol = sky.cloudSymbol,
               let cloud = dependency(.sky, cloudSymbol, requiredPayload: true) {
                appendEntry(kind: .cloud, category: .sky, sourceSymbol: "stage_sky_state",
                            resourceSymbol: cloud.symbol, resourceHandle: cloud.resourceHandle,
                            position: .init(x: sky.cloudOffsetQ16, y: 0, z: 0),
                            colour: sky.cloudRGBA8, flags: sky.flags)
            }
        } else { addMissing(.sky, "stage_sky_state") }

        if let fade = frame.fade {
            let fadeValid = fade.stageID == frame.stageID && fade.demoID == frame.demoID
                && fade.fractionQ16 <= 65_536
            if !fadeValid {
                diagnostics.append(.init(code: .invalidState, category: .fades,
                                         sourceSymbol: "screen_fade_to_black/from_black", detail: "fade state is out of range"))
            } else if dependency(.fades, "screen_fade_to_black/from_black") != nil {
                appendEntry(kind: .fade, category: .fades,
                            sourceSymbol: "screen_fade_to_black/from_black", resourceSymbol: nil,
                            resourceHandle: 0, colour: fade.colourRGBA8, alpha: fade.fractionQ16,
                            flags: fade.flags | GoldenEyeRamRomNonModelVisualEntryFlagsV6.fullScreen
                                | GoldenEyeRamRomNonModelVisualEntryFlagsV6.alphaBlend
                                | GoldenEyeRamRomNonModelVisualEntryFlagsV6.sourceAnchor)
            }
        } else { addMissing(.fades, "screen_fade_to_black/from_black") }

        if let hud = frame.hud {
            for placement in hud.imagePlacements {
                guard hud.imageSymbols.contains(placement.symbol) else {
                    diagnostics.append(.init(code: .invalidState, category: .hud,
                                             sourceSymbol: placement.symbol,
                                             detail: "HUD placement has no matching source image row"))
                    continue
                }
                if let resource = dependency(.hud, placement.symbol, requiredPayload: true) {
                    appendEntry(kind: .hud, category: .hud, sourceSymbol: "hud_state",
                                resourceSymbol: resource.symbol, resourceHandle: resource.resourceHandle,
                                position: .init(x: placement.xQ16, y: placement.yQ16, z: 0),
                                scale: max(placement.width, placement.height),
                                colour: placement.tintRGBA8,
                                flags: placement.flags | (hud.visible ? 1 : 0))
                }
            }
            if hud.visible && hud.imageSymbols.isEmpty {
                diagnostics.append(.init(code: .invalidState, category: .hud,
                                         sourceSymbol: "hud_state", detail: "visible HUD has no source image rows"))
            } else if hud.visible && hud.imagePlacements.isEmpty {
                diagnostics.append(.init(code: .unsupportedSourceProducer, category: .hud,
                                         sourceSymbol: "hud_state", detail: "source image rows exist but gunfire.c draw coordinates were not supplied"))
            }
        } else { addMissing(.hud, "hud_state") }

        if let watch = frame.watch {
            if watch.visible, let position = watch.positionQ16, let scale = watch.scaleQ16,
               let model = dependency(.watch, watch.sourceSymbol, requiredPayload: true) {
                appendEntry(kind: .watch, category: .watch, sourceSymbol: watch.sourceSymbol,
                            resourceSymbol: model.symbol, resourceHandle: model.resourceHandle,
                            position: position, scale: scale,
                            flags: 1 | (watch.animateButtons ? 2 : 0))
            } else if watch.visible {
                diagnostics.append(.init(code: .unsupportedSourceProducer, category: .watch,
                                         sourceSymbol: watch.sourceSymbol, detail: "watchRenderController transform was not supplied"))
            }
        } else { addMissing(.watch, "watch_state") }

        for event in frame.transientEvents {
            let category = category(for: event.category)
            guard event.sourceReferenceTick == frame.nativeTick >> 1 else {
                diagnostics.append(.init(code: .invalidState, category: category,
                                         sourceSymbol: event.sourceSymbol, detail: "transient event is not at the current source anchor"))
                continue
            }
            guard dependency(category, event.sourceSymbol) != nil else { continue }
            let resource: GoldenEyeRamRomNonModelDependencyV6?
            if let preferred = catalog.dependency(category: category, symbol: event.resourceSymbol),
               preferred.hasPreparedPayload, preferred.demoIDs.contains(frame.demoID) {
                resource = preferred
            } else {
                resource = catalog.dependencies.first {
                    $0.symbol == event.resourceSymbol && $0.hasPreparedPayload
                        && $0.demoIDs.contains(frame.demoID)
                }
            }
            guard let resource else { continue }
            guard event.alphaQ16 <= 65_536, event.scaleQ16 > 0 else {
                diagnostics.append(.init(code: .invalidState, category: category,
                                         sourceSymbol: event.sourceSymbol, detail: "transient event scale/alpha is invalid"))
                continue
            }
            appendEntry(kind: kind(for: event.category), category: category,
                        sourceSymbol: event.sourceSymbol, resourceSymbol: resource.symbol,
                        resourceHandle: resource.resourceHandle, sequence: event.sequence,
                        position: event.positionQ16, scale: event.scaleQ16,
                        rotation: event.rotationQ16, frameIndex: event.frameIndex,
                        colour: event.colourRGBA8, alpha: event.alphaQ16, flags: event.flags)
        }

        let requiredTransient = GoldenEyeRamRomTransientVisualCategoryV6.allCases.map { category(for: $0) }
        for requiredCategory in requiredTransient
            where !frame.transientEvents.contains(where: { category(for: $0.category) == requiredCategory }) {
            addMissing(requiredCategory, requiredCategory.semanticSourceSymbol ?? requiredCategory.rawValue)
        }
        return try finish(catalog: catalog, frame: frame, entries: entries, diagnostics: diagnostics, strict: strict)
    }

    private static func finish(
        catalog: GoldenEyeRamRomNonModelDependencyCatalogV6,
        frame: GoldenEyeRamRomNonModelSourceFrameV6,
        entries: [GoldenEyeRamRomNonModelVisualEntryV6],
        diagnostics: [GoldenEyeRamRomNonModelVisualDiagnosticV6],
        strict: Bool
    ) throws -> GoldenEyeRamRomNonModelVisualCompositionV6 {
        if strict && !diagnostics.isEmpty {
            throw GoldenEyeRamRomNonModelVisualCompositionError.strictDiagnostics(diagnostics)
        }
        var hash: UInt64 = 1_469_598_103_934_665_603
        func mix(_ value: UInt64) {
            var word = value
            for _ in 0..<8 { hash = (hash ^ (word & 0xff)) &* 1_099_511_628_211; word >>= 8 }
        }
        mix(UInt64(frame.stageID)); mix(UInt64(frame.demoID)); mix(frame.nativeTick)
        for entry in entries.sorted(by: { $0.sequence < $1.sequence }) {
            mix(UInt64(entry.kind.rawValue)); mix(UInt64(entry.resourceHandle)); mix(UInt64(entry.sequence))
            mix(UInt64(bitPattern: Int64(entry.positionQ16.x))); mix(UInt64(entry.frameIndex)); mix(UInt64(entry.alphaQ16))
        }
        for diagnostic in diagnostics {
            mix(UInt64(diagnostic.code.rawValue))
            mix(diagnostic.category.rawValue.utf8.reduce(UInt64(0)) { ($0 &* 31) &+ UInt64($1) })
        }
        return GoldenEyeRamRomNonModelVisualCompositionV6(
            stageID: frame.stageID, demoID: frame.demoID, nativeTick: frame.nativeTick,
            referenceTick: frame.nativeTick >> 1, entries: entries,
            diagnostics: diagnostics, sourceManifestSHA256: catalog.manifestSHA256,
            compositionHash: hash
        )
    }

    private static func category(
        for value: GoldenEyeRamRomTransientVisualCategoryV6
    ) -> GoldenEyeRamRomNonModelVisualCategoryV6 {
        switch value {
        case .particles: return .particles
        case .effects: return .effects
        case .glass: return .glass
        case .explosions: return .explosions
        case .projectiles: return .projectiles
        }
    }

    private static func kind(
        for value: GoldenEyeRamRomTransientVisualCategoryV6
    ) -> GoldenEyeRamRomNonModelVisualEntryKindV6 {
        switch value {
        case .particles: return .particle
        case .effects: return .effect
        case .glass: return .glass
        case .explosions: return .explosion
        case .projectiles: return .projectile
        }
    }
}
