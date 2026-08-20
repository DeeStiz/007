import Foundation

/// Loader for the private extended cast preparation root. It does not alter
/// the frozen title preparation contract; only source-linked GESM model rows
/// are exposed to the cast renderer.
struct GoldenEyeCastPreparedAssetCatalogV6: @unchecked Sendable {
    let rootURL: URL
    let catalog: GoldenEyeSourceFrontendCatalog
    let models: [String: GoldenEyeSourceModelV6]

    static func load(rootURL: URL) throws -> Self {
        let root = rootURL.standardizedFileURL
        let catalog = try GoldenEyeSourceFrontendCatalog.loadCast(preparedAssetRoot: root)
        var models: [String: GoldenEyeSourceModelV6] = [:]
        for sidecar in catalog.sidecars where sidecar.name != "rarewarelogo" {
            let url = root.appendingPathComponent(sidecar.path, isDirectory: false).standardizedFileURL
            let model = try GoldenEyeSourceModelV6.load(from: url)
            let sourceHash = model.header.sourceHash.map { String(format: "%02x", $0) }.joined()
            let packetHash = model.header.packetHash.map { String(format: "%02x", $0) }.joined()
            guard sourceHash == sidecar.sourceSHA256,
                  packetHash == sidecar.packetSHA256,
                  models.updateValue(model, forKey: sidecar.name) == nil else {
                throw GoldenEyeSourceProductPreparationV6Error.invalidModel(
                    sidecar.name, "extended cast sidecar digest/linkage mismatch"
                )
            }
        }
        guard GoldenEyeCastSceneComposerV6.requiredPreparedModelNames.isSubset(of: Set(models.keys)) else {
            throw GoldenEyeSourceProductPreparationV6Error.modelSetMismatch(
                expected: GoldenEyeCastSceneComposerV6.requiredPreparedModelNames.sorted(),
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
}
