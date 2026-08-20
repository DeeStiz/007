import Foundation
import CryptoKit

/// Bounded loader for the setup-reachable GESM sidecars. It accepts a
/// partial catalog only as diagnostic evidence; ``isComplete`` is the sole
/// gate that could ever clear prop/character category coverage.
struct GoldenEyeStageModelSidecarCatalogV6: @unchecked Sendable {
    struct Payload: @unchecked Sendable, Equatable {
        let id: UInt32
        let category: String
        let name: String
        let rawSize: Int
        let decodedSize: Int
        let rawSHA256: String
        let decodedSHA256: String
        let rawURL: URL
        let decodedURL: URL
        let flags: Set<String>
    }

    let rootURL: URL
    let models: [String: GoldenEyeSourceModelV6]
    let sidecarCount: Int
    let expectedModelCount: Int
    let status: String
    let payloads: [UInt32: Payload]

    var isComplete: Bool {
        status == "PASS" && sidecarCount == expectedModelCount && models.count == expectedModelCount
    }

    var payloadsReady: Bool { !payloads.isEmpty }

    func payload(id: UInt32) -> Payload? { payloads[id] }

    static func load(stageAssetRoot rootURL: URL) throws -> Self {
        let root = rootURL.standardizedFileURL
        let manifestURL = root
            .appendingPathComponent("model-sidecars", isDirectory: true)
            .appendingPathComponent("stage-model-sidecars-manifest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw Error.missingManifest
        }
        let data = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? String,
              let sidecarCount = object["sidecar_count"] as? Int,
              let expectedModelCount = object["model_count"] as? Int,
              let sidecars = object["sidecars"] as? [[String: Any]] else {
            throw Error.invalidManifest
        }
        var models: [String: GoldenEyeSourceModelV6] = [:]
        for sidecar in sidecars {
            guard let name = sidecar["name"] as? String,
                  let path = sidecar["path"] as? String,
                  let packetSHA = sidecar["packet_sha256"] as? String,
                  let sourceSHA = sidecar["source_sha256"] as? String else {
                throw Error.invalidManifest
            }
            let url = root.appendingPathComponent("model-sidecars", isDirectory: true)
                .appendingPathComponent(path, isDirectory: false).standardizedFileURL
            guard url.path.hasPrefix(root.path + "/") else { throw Error.pathEscapes(path) }
            let model = try GoldenEyeSourceModelV6.load(data: Data(contentsOf: url), modelName: name)
            guard hex(packetSHA) == model.header.packetHash,
                  hex(sourceSHA) == model.header.sourceHash,
                  models.updateValue(model, forKey: name) == nil else {
                throw Error.digestMismatch(name)
            }
        }
        let payloads = try loadPayloads(root: root)
        return Self(
            rootURL: root,
            models: models,
            sidecarCount: sidecarCount,
            expectedModelCount: expectedModelCount,
            status: status,
            payloads: payloads
        )
    }

    enum Error: Swift.Error, CustomStringConvertible {
        case missingManifest
        case invalidManifest
        case invalidPayloadManifest
        case pathEscapes(String)
        case digestMismatch(String)
        var description: String {
            switch self {
            case .missingManifest: return "stage model sidecar manifest is missing"
            case .invalidManifest: return "stage model sidecar manifest is invalid"
            case .invalidPayloadManifest: return "stage model sidecar payload manifest is invalid"
            case .pathEscapes(let path): return "stage model sidecar path escapes root: \(path)"
            case .digestMismatch(let name): return "stage model sidecar digest mismatch: \(name)"
            }
        }
    }

    private static func hex(_ value: String) -> [UInt8] {
        guard value.count == 64 else { return [] }
        var bytes: [UInt8] = []
        var index = value.startIndex
        for _ in 0..<32 {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return [] }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    private static func loadPayloads(root: URL) throws -> [UInt32: Payload] {
        let manifestURL = root
            .appendingPathComponent("model-sidecars", isDirectory: true)
            .appendingPathComponent("stage-model-sidecar-payloads-manifest.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return [:] }
        guard let object = try JSONSerialization.jsonObject(
            with: Data(contentsOf: manifestURL, options: [.mappedIfSafe])
        ) as? [String: Any],
              object["status"] as? String == "PASS",
              object["runtime_opens_rom"] as? Bool == false,
              object["runtime_consumes_prepared_payloads_only"] as? Bool == true,
              let rows = object["records"] as? [[String: Any]],
              rows.count == (object["record_count"] as? Int ?? -1) else {
            throw Error.invalidPayloadManifest
        }
        var result: [UInt32: Payload] = [:]
        for row in rows {
            guard let id = row["id"] as? Int, id > 0,
                  let category = row["category"] as? String,
                  let name = row["name"] as? String,
                  let rawSize = row["raw_size"] as? Int,
                  let decodedSize = row["decoded_size"] as? Int,
                  let rawSHA256 = row["raw_sha256"] as? String,
                  let decodedSHA256 = row["decoded_sha256"] as? String,
                  let rawFile = row["raw_file"] as? String,
                  let decodedFile = row["decoded_file"] as? String else {
                throw Error.invalidPayloadManifest
            }
            let rawURL = try payloadURL(root: root, file: rawFile)
            let decodedURL = try payloadURL(root: root, file: decodedFile)
            try validatePayload(rawURL, expected: rawSize, digest: rawSHA256)
            try validatePayload(decodedURL, expected: decodedSize, digest: decodedSHA256)
            let flags = Set((row["flags"] as? [String]) ?? [])
            let payload = Payload(
                id: UInt32(id), category: category, name: name,
                rawSize: rawSize, decodedSize: decodedSize,
                rawSHA256: rawSHA256, decodedSHA256: decodedSHA256,
                rawURL: rawURL, decodedURL: decodedURL, flags: flags
            )
            guard result.updateValue(payload, forKey: UInt32(id)) == nil else {
                throw Error.invalidPayloadManifest
            }
        }
        return result
    }

    private static func payloadURL(root: URL, file: String) throws -> URL {
        guard !file.isEmpty, !file.hasPrefix("/"), !file.split(separator: "/").contains("..") else {
            throw Error.invalidPayloadManifest
        }
        let url = root.appendingPathComponent("model-sidecars", isDirectory: true)
            .appendingPathComponent(file, isDirectory: false).standardizedFileURL
        let modelRoot = root.appendingPathComponent("model-sidecars", isDirectory: true).standardizedFileURL
        guard url.path.hasPrefix(modelRoot.path + "/") else { throw Error.invalidPayloadManifest }
        return url
    }

    private static func validatePayload(_ url: URL, expected: Int, digest: String) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { throw Error.invalidPayloadManifest }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard data.count == expected,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == digest else {
            throw Error.invalidPayloadManifest
        }
    }
}
