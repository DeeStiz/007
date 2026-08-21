import CryptoKit
import Foundation

/// Runtime-side value-only view of the setup-reachable prop and guard model
/// sidecar. The loader validates copied payloads but deliberately exposes no
/// model graph or draw fallback; prop/character categories remain unsupported
/// until their source GBI lowerer consumes these records.
struct GoldenEyeStageSetupDependencyCatalogV6: Sendable, Equatable {
    struct Dependency: Sendable, Equatable {
        let stage: String
        let kind: String
        let objectIndex: UInt32
        let objectType: UInt32
        let setupOffset: UInt32
        let modelIndex: UInt32
        let modelName: String
        let sourcePath: String
        let romRow: String
        let romOffset: UInt32
        let romBytes: UInt32
        let compressed: Bool
        let sourceSHA256: String
        let decodedBytes: UInt32
        let decodedSHA256: String
        let rawFile: String
        let decodedFile: String
    }

    enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case missingManifest(URL)
        case invalidManifest(String)
        case missingPayload(URL)
        case pathEscapes(URL)
        case payloadSize(String, Int, Int)
        case payloadDigest(String, String, String)

        var description: String {
            switch self {
            case .missingManifest(let url): return "stage setup dependency manifest is missing: \(url.path)"
            case .invalidManifest(let detail): return "stage setup dependency manifest is invalid: \(detail)"
            case .missingPayload(let url): return "stage setup dependency payload is missing: \(url.path)"
            case .pathEscapes(let url): return "stage setup dependency path escapes root: \(url.path)"
            case .payloadSize(let name, let actual, let expected):
                return "stage setup dependency \(name) size \(actual) != \(expected)"
            case .payloadDigest(let name, let expected, let actual):
                return "stage setup dependency \(name) digest \(actual) != \(expected)"
            }
        }
    }

    static let manifestFileName = "stage-setup-model-dependencies-manifest.txt"
    static let expectedReferenceCount = 1_783
    static let expectedUniqueCount = 141

    let rootURL: URL
    let manifestURL: URL
    let dependencies: [Dependency]

    var propCount: Int { dependencies.reduce(into: 0) { if $1.kind == "prop" { $0 += 1 } } }
    var characterCount: Int { dependencies.reduce(into: 0) { if $1.kind == "character" { $0 += 1 } } }
    var isReady: Bool { dependencies.count == Self.expectedReferenceCount }

    func dependency(kind: String, modelIndex: UInt32) -> Dependency? {
        dependencies.first { $0.kind == kind && $0.modelIndex == modelIndex }
    }

    static func load(stageAssetRoot rootURL: URL) throws -> Self {
        let root = rootURL.standardizedFileURL
        let manifestURL = root.appendingPathComponent(manifestFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw Error.missingManifest(manifestURL)
        }
        let text: String
        do {
            text = try String(contentsOf: manifestURL, encoding: .utf8)
        } catch {
            throw Error.invalidManifest(String(describing: error))
        }
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
        var values: [String: String] = [:]
        var rows: [(UInt32, String)] = []
        for line in lines {
            guard let equal = line.firstIndex(of: "=") else { throw Error.invalidManifest("missing =") }
            let key = String(line[..<equal])
            let payload = String(line[line.index(after: equal)...])
            if key.hasPrefix("dependency_"), let index = UInt32(key.dropFirst("dependency_".count)) {
                rows.append((index, payload))
            } else {
                values[key] = payload
            }
        }
        guard values["manifest_status"] == "PASS",
              values["source_setup_status"] == "PASS",
              values["payload_status"] == "PASS",
              values["runtime_opens_rom"] == "false",
              values["runtime_consumes_prepared_payloads_only"] == "true",
              Int(values["dependency_count"] ?? "-1") == expectedReferenceCount,
              Int(values["unique_dependency_count"] ?? "-1") == expectedUniqueCount,
              rows.count == expectedReferenceCount else {
            throw Error.invalidManifest("status/count/provenance guard")
        }
        let dependencies = try rows.sorted { $0.0 < $1.0 }.map { _, payload in
            let fields = Dictionary(uniqueKeysWithValues: payload.split(separator: "|").compactMap { field -> (String, String)? in
                let parts = field.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2 else { return nil }
                return (parts[0], parts[1])
            })
            func required(_ key: String) throws -> String {
                guard let value = fields[key], !value.isEmpty else { throw Error.invalidManifest("missing \(key)") }
                return value
            }
            func uint(_ key: String) throws -> UInt32 {
                guard let value = UInt32(try required(key)) else { throw Error.invalidManifest("invalid \(key)") }
                return value
            }
            let rawFile = try required("raw_file")
            let decodedFile = try required("decoded_file")
            let raw = try readPayload(root: root, fileName: rawFile, expected: Int(try uint("rom_bytes")), digest: try required("source_sha256"), name: rawFile)
            _ = raw
            let decoded = try readPayload(root: root, fileName: decodedFile, expected: Int(try uint("decoded_bytes")), digest: try required("decoded_sha256"), name: decodedFile)
            _ = decoded
            return Dependency(
                stage: try required("stage"), kind: try required("kind"),
                objectIndex: try uint("object_index"), objectType: try uint("object_type"),
                setupOffset: try uint("setup_offset"), modelIndex: try uint("model_index"),
                modelName: try required("model_name"), sourcePath: try required("source_path"),
                romRow: try required("rom_row"), romOffset: try uint("rom_offset"),
                romBytes: try uint("rom_bytes"), compressed: try uint("compressed") != 0,
                sourceSHA256: try required("source_sha256"), decodedBytes: try uint("decoded_bytes"),
                decodedSHA256: try required("decoded_sha256"), rawFile: rawFile, decodedFile: decodedFile
            )
        }
        return Self(rootURL: root, manifestURL: manifestURL, dependencies: dependencies)
    }

    private static func readPayload(
        root: URL,
        fileName: String,
        expected: Int,
        digest: String,
        name: String
    ) throws -> Data {
        guard !fileName.hasPrefix("/"), !fileName.split(separator: "/").contains("..") else {
            throw Error.pathEscapes(root.appendingPathComponent(fileName))
        }
        let url = root.appendingPathComponent(fileName, isDirectory: false)
        guard url.standardizedFileURL.path.hasPrefix(root.path + "/") else {
            throw Error.pathEscapes(url)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { throw Error.missingPayload(url) }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == expected else { throw Error.payloadSize(name, data.count, expected) }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == digest else { throw Error.payloadDigest(name, digest, actual) }
        return data
    }
}
