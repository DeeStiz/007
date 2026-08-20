import Foundation

@main
struct GoldenEyeTitleTextCatalogSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                       ?? "build/native/boot-assets", isDirectory: true)
        let catalog = try GoldenEyeTitleTextCatalog.load(assetRoot: root)
        precondition(catalog.strings.count >= 200)
        precondition(catalog.strings.contains("TWYCROSS BOARD OF GAME CLASSIFICATION"))
        precondition(catalog.strings.contains("Copy"))
        precondition(catalog.strings.contains("Erase"))
        precondition(catalog.sourceSHA256.count == 64)
        print("goldeneye_title_text_catalog_smoke: PASS strings=\(catalog.strings.count) sha256=\(catalog.sourceSHA256)")
    }
}
