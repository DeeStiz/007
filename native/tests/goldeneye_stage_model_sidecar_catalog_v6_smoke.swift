import Foundation

@main
struct GoldenEyeStageModelSidecarCatalogV6Smoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("usage: smoke stage-root") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let catalog = try GoldenEyeStageModelSidecarCatalogV6.load(stageAssetRoot: root)
        let visible = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(
            rootURL: root.deletingLastPathComponent().appendingPathComponent("ramrom-visible-dependencies-v6", isDirectory: true)
        )
        precondition(visible.isComplete)
        precondition(visible.count(category: "props") == 100)
        precondition(visible.count(category: "guards") == 79)
        precondition(visible.count(category: "effects") > 0)
        precondition(visible.count(category: "hud") > 0)
        precondition(catalog.sidecarCount == 179)
        precondition(catalog.models.count == 179)
        precondition(catalog.isComplete)
        precondition(catalog.payloadsReady)
        precondition(catalog.payloads.count > 1_000)
        precondition(catalog.models.values.allSatisfy { $0.header.packetHash.count == 32 })
        print("goldeneye_stage_model_sidecar_catalog_v6_smoke: PASS sidecars=179 complete=1 payloads=\(catalog.payloads.count) visibleDependencies=953")
    }
}
