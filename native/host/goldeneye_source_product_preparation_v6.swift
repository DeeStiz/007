import Foundation

/// The one guarded source-frontend input used by the product renderer.
///
/// Preparation is intentionally separate from Metal construction so a build
/// or test can prove the complete GEFV/GESM set without manufacturing a GPU
/// object.  The loader accepts exactly one explicit root; it never searches
/// for a ROM, walks parent directories, or substitutes a diagnostic asset.
struct GoldenEyeSourceProductPreparationV6: @unchecked Sendable {
    static let requiredModelNames: Set<String> = [
        "chrwppk",
        "goldeneyelogo",
        "headbrosnansuit",
        "legalpage",
        "nintendologo",
        "rarewarelogo",
        "suitbond",
        "walletbond",
    ]

    let rootURL: URL
    let catalog: GoldenEyeSourceFrontendCatalog
    let models: [String: GoldenEyeSourceModelV6]

    static func load(rootURL: URL) throws -> Self {
        let root = rootURL.standardizedFileURL
        guard root.isFileURL, root.path.hasPrefix("/") else {
            throw GoldenEyeSourceProductPreparationV6Error.invalidRoot(
                "an absolute file URL is required"
            )
        }
        let catalog = try GoldenEyeSourceFrontendCatalog.load(preparedAssetRoot: root)
        let sidecarNames = Set(catalog.sidecars.map(\.name))
        guard sidecarNames == requiredModelNames else {
            throw GoldenEyeSourceProductPreparationV6Error.modelSetMismatch(
                expected: requiredModelNames.sorted(),
                actual: sidecarNames.sorted()
            )
        }

        var models: [String: GoldenEyeSourceModelV6] = [:]
        models.reserveCapacity(catalog.sidecars.count)
        for sidecar in catalog.sidecars.sorted(by: { $0.name < $1.name }) {
            let modelURL = root.appendingPathComponent(sidecar.path, isDirectory: false)
                .standardizedFileURL
            guard isWithinRoot(modelURL, root: root) else {
                throw GoldenEyeSourceProductPreparationV6Error.pathEscapesRoot(sidecar.path)
            }
            let data: Data
            do {
                data = try Data(contentsOf: modelURL, options: [.mappedIfSafe])
            } catch {
                throw GoldenEyeSourceProductPreparationV6Error.unreadableModel(
                    sidecar.name,
                    String(describing: error)
                )
            }
            let model: GoldenEyeSourceModelV6
            do {
                model = try GoldenEyeSourceModelV6.load(data: data, modelName: sidecar.name)
            } catch {
                throw GoldenEyeSourceProductPreparationV6Error.invalidModel(
                    sidecar.name,
                    String(describing: error)
                )
            }
            guard model.header.modelHandle > 0,
                  model.header.packetHash.count == 32,
                  model.header.sourceHash.count == 32,
                  model.header.packetHash.contains(where: { $0 != 0 }),
                  model.header.sourceHash.contains(where: { $0 != 0 }) else {
                throw GoldenEyeSourceProductPreparationV6Error.invalidModel(
                    sidecar.name,
                    "empty GESM header digest"
                )
            }
            guard model.header.packetHash == hexBytes(sidecar.packetSHA256),
                  model.header.sourceHash == hexBytes(sidecar.sourceSHA256) else {
                throw GoldenEyeSourceProductPreparationV6Error.modelDigestMismatch(sidecar.name)
            }
            guard models.updateValue(model, forKey: sidecar.name) == nil else {
                throw GoldenEyeSourceProductPreparationV6Error.duplicateModel(sidecar.name)
            }
        }
        guard Set(models.keys) == requiredModelNames else {
            throw GoldenEyeSourceProductPreparationV6Error.modelSetMismatch(
                expected: requiredModelNames.sorted(),
                actual: models.keys.sorted()
            )
        }
        return Self(rootURL: root, catalog: catalog, models: models)
    }

    func model(named name: String) throws -> GoldenEyeSourceModelV6 {
        guard let model = models[name] else {
            throw GoldenEyeSourceProductPreparationV6Error.modelNotFound(name)
        }
        return model
    }

    private static func isWithinRoot(_ candidate: URL, root: URL) -> Bool {
        let rootPath = root.resolvingSymlinksInPath().path
        let candidatePath = candidate.resolvingSymlinksInPath().path
        guard candidatePath != rootPath else { return false }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return candidatePath.hasPrefix(prefix)
    }

    private static func hexBytes(_ value: String) -> [UInt8] {
        guard value.count == 64 else { return [] }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(32)
        var index = value.startIndex
        for _ in 0..<32 {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return [] }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}

enum GoldenEyeSourceProductPreparationV6Error: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidRoot(String)
    case pathEscapesRoot(String)
    case modelSetMismatch(expected: [String], actual: [String])
    case unreadableModel(String, String)
    case invalidModel(String, String)
    case modelDigestMismatch(String)
    case duplicateModel(String)
    case modelNotFound(String)

    var description: String {
        switch self {
        case .invalidRoot(let detail): return "invalid source product root: \(detail)"
        case .pathEscapesRoot(let path): return "GESM path escapes source product root: \(path)"
        case .modelSetMismatch(let expected, let actual):
            return "source product model set mismatch expected=\(expected) actual=\(actual)"
        case .unreadableModel(let name, let detail):
            return "source product model \(name) is unreadable: \(detail)"
        case .invalidModel(let name, let detail):
            return "source product model \(name) is invalid: \(detail)"
        case .modelDigestMismatch(let name): return "source product model \(name) digest mismatch"
        case .duplicateModel(let name): return "duplicate source product model \(name)"
        case .modelNotFound(let name): return "source product model is missing: \(name)"
        }
    }
}
