import Foundation

@main
struct GoldenEyeStageAssetCatalogSmoke {
    static func main() throws {
        let rootPath = CommandLine.arguments.dropFirst().first
            ?? ProcessInfo.processInfo.environment["GOLDENEYE_NATIVE_STAGE_ASSET_ROOT"]
            ?? "build/native/stage-assets"
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let expectMalformedFailure = CommandLine.arguments.contains("--expect-malformed")
        let first: GoldenEyeStageAssetCatalog
        do {
            first = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: root)
        } catch {
            if expectMalformedFailure {
                precondition(String(describing: error).contains("manifest guard failed"))
                print("goldeneye_stage_asset_catalog_smoke: PASS malformed_manifest_guard")
                return
            }
            throw error
        }
        precondition(!expectMalformedFailure, "malformed manifest unexpectedly accepted")
        precondition(first.stages.count == 7)
        precondition(first.stages.reduce(0) { $0 + $1.resources.count } == 21)
        precondition(first.bootstrapReport.isAssetReady)
        precondition(first.bootstrapReport.catalogHash != 0)
        precondition(first.bootstrapReport.gameplayStub.milestone == 26)
        precondition(first.bootstrapReport.rendererStub.milestone == 27)
        precondition(first.bootstrapReport.gameplayStub.message.contains("STUB(M26)"))
        precondition(first.bootstrapReport.rendererStub.message.contains("STUB(M27)"))
        for stage in first.bootstrapReport.stages {
            precondition(stage.resourceCount == 3)
            precondition(stage.stageHash != 0)
            precondition(stage.sourceHash != 0)
            precondition(stage.decodedHash != 0)
        }

        let second = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: root)
        precondition(second.bootstrapReport == first.bootstrapReport)
        precondition(second.stages == first.stages)

        let hashes = first.bootstrapReport.stages
            .map { "\($0.stageName)=\($0.stageHash)" }
            .joined(separator: ",")
        print(
            "goldeneye_stage_asset_catalog_smoke: PASS " +
                "stages=\(first.stages.count) resources=21 " +
                "catalog_hash=\(first.catalogHash) stage_hashes=\(hashes) " +
                "STUB(M26)=\(first.bootstrapReport.gameplayStub.status) " +
                "STUB(M27)=\(first.bootstrapReport.rendererStub.status)"
        )
    }
}
