import CryptoKit
import Foundation

struct GoldenEyeRamRomWeaponAssetV6: Sendable, Equatable {
    let category: String
    let symbol: String
    let demoIDs: [UInt8]
    let stages: [String]
    let sourceBytes: UInt32
    let decodedBytes: UInt32
    let sourceSHA256: String
    let decodedSHA256: String
    let rawURL: URL?
    let decodedURL: URL?
    let resourceHandle: UInt32
    let semantic: Bool
}

struct GoldenEyeRamRomWeaponAssetCatalogV6: Sendable, Equatable {
    static let manifestFileName = "ramrom-visible-dependencies-v6-manifest.txt"
    static let expectedAssetCount = 241
    static let categories: Set<String> = [
        "weapons", "projectiles", "particles", "explosions", "glass", "hud", "watch", "fades", "effects"
    ]

    let rootURL: URL
    let manifestSHA256: String
    let assets: [GoldenEyeRamRomWeaponAssetV6]

    var isComplete: Bool { assets.count == Self.expectedAssetCount && assets.allSatisfy { $0.semantic || $0.decodedURL != nil } }

    func asset(category: String, symbol: String) -> GoldenEyeRamRomWeaponAssetV6? {
        assets.first { $0.category == category && $0.symbol == symbol }
    }

    func assets(symbol: String) -> [GoldenEyeRamRomWeaponAssetV6] {
        assets.filter { $0.symbol == symbol }
    }

    static func resourceHandle(category: String, symbol: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in (category + ":" + symbol).utf8 {
            hash ^= UInt32(byte); hash = hash &* 16_777_619
        }
        return 0xD700_0000 | (hash & 0x00FF_FFFF)
    }

    static func load(rootURL: URL, validatePayloads: Bool = true) throws -> Self {
        let root = rootURL.standardizedFileURL
        let manifestURL = root.appendingPathComponent(manifestFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw CatalogError.invalidManifest("missing manifest")
        }
        let data = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        let text = String(decoding: data, as: UTF8.self)
        var values: [String: String] = [:]
        var rows: [(Int, String)] = []
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init) {
            guard let equal = line.firstIndex(of: "=") else { throw CatalogError.invalidManifest("missing =") }
            let key = String(line[..<equal]); let payload = String(line[line.index(after: equal)...])
            if key.hasPrefix("dependency_"), let index = Int(key.dropFirst("dependency_".count)) {
                rows.append((index, payload))
            } else { values[key] = payload }
        }
        guard values["manifest_status"] == "PASS",
              values["runtime_opens_rom"] == "false",
              values["runtime_consumes_prepared_payloads_only"] == "true",
              values["emulation_used"] == "false" else {
                throw CatalogError.provenance
        }
        var assets: [GoldenEyeRamRomWeaponAssetV6] = []
        for (_, payload) in rows.sorted(by: { $0.0 < $1.0 }) {
            let fields = Dictionary(uniqueKeysWithValues: payload.split(separator: "|").compactMap { part -> (String, String)? in
                let pair = part.split(separator: ":", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { return nil }; return (pair[0], pair[1])
            })
            guard let category = fields["category"] else {
                throw CatalogError.invalidManifest("missing category")
            }
            guard categories.contains(category) else { continue }
            guard let symbol = fields["symbol"], let demoText = fields["demo_ids"],
                  let stageText = fields["stages"], let sourceBytes = UInt32(fields["source_bytes"] ?? fields["rom_bytes"] ?? ""),
                  let decodedBytes = UInt32(fields["decoded_bytes"] ?? ""),
                  let sourceSHA = fields["source_sha256"], let decodedSHA = fields["decoded_sha256"] else {
                let category = fields["category"] ?? "?"
                let symbol = fields["symbol"] ?? "?"
                throw CatalogError.invalidManifest("weapon/effect row \(category)/\(symbol)")
            }
            let semantic = fields["asset_type"] == "semantic"
            let rawURL = try payloadURL(root: root, path: fields["raw_file"], semantic: semantic)
            let decodedURL = try payloadURL(root: root, path: fields["decoded_file"], semantic: semantic)
            if validatePayloads && !semantic {
                guard let rawURL, let decodedURL else { throw CatalogError.invalidManifest("payload path") }
                try validate(rawURL, bytes: Int(sourceBytes), sha: sourceSHA)
                try validate(decodedURL, bytes: Int(decodedBytes), sha: decodedSHA)
            }
            assets.append(.init(
                category: category, symbol: symbol,
                demoIDs: demoText.split(separator: ",").compactMap { UInt8($0) },
                stages: stageText.split(separator: ",").map(String.init),
                sourceBytes: sourceBytes, decodedBytes: decodedBytes,
                sourceSHA256: sourceSHA, decodedSHA256: decodedSHA,
                rawURL: rawURL, decodedURL: decodedURL,
                resourceHandle: resourceHandle(category: category, symbol: symbol), semantic: semantic
            ))
        }
        return .init(
            rootURL: root,
            manifestSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            assets: assets
        )
    }

    enum CatalogError: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case invalidManifest(String)
        case provenance
        case payloadMismatch(String)
        var description: String {
            switch self {
            case let .invalidManifest(value): return "weapon asset manifest invalid: \(value)"
            case .provenance: return "weapon asset manifest provenance failed"
            case let .payloadMismatch(value): return "weapon asset payload mismatch: \(value)"
            }
        }
    }

    private static func payloadURL(root: URL, path: String?, semantic: Bool) throws -> URL? {
        guard let path, path != "none" else {
            if semantic { return nil }
            throw CatalogError.invalidManifest("missing payload path")
        }
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
            throw CatalogError.invalidManifest("payload path escapes root")
        }
        let url = root.appendingPathComponent(path, isDirectory: false).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw CatalogError.invalidManifest("payload root") }
        return url
    }

    private static func validate(_ url: URL, bytes: Int, sha: String) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw CatalogError.payloadMismatch(url.path) }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == bytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha else {
            throw CatalogError.payloadMismatch(url.path)
        }
    }
}
