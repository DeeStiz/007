import Foundation

@main
struct GoldenEyeFileModeBackgroundV6Smoke {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/native/source-frontend-v6")
        let catalog = try GoldenEyeSourceFrontendCatalog.load(preparedAssetRoot: root)
        let record = try catalog.record(kind: .background, name: "gunbarrel-background", family: "gunbarrel")
        let payload = try catalog.copyOut(.decoded, for: record)
        let background = try GoldenEyeFileModeBackgroundContractV6(encoded: payload)
        precondition(background.rowCount == 299)
        precondition(background.sourceColumn(forCanvasColumn: 0) == 28)
        precondition(background.sourceColumn(forCanvasColumn: 411) == 439)
        precondition(background.sourceColumn(forCanvasColumn: 412) == nil)
        precondition(background.rightBorderWidth == 28)
        precondition(background.primaryColor(row: 0) == 20)
        precondition(background.primaryColor(row: 298) == 49)
        precondition(background.contractHash != 0)
        print("background=440x299 rows=299 xOffset=-28 top=20 bottom=50 envAlpha=20")
        print("background=sourceSHA256=\(background.sourceSHA256) contractHash=\(background.contractHash)")
        print("goldeneye_file_mode_background_v6_smoke: PASS")
    }
}
