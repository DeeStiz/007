import Foundation

@main
struct GoldenEyeTitleRasterCatalogSmoke {
    static func main() throws {
        let first = try GoldenEyeTitleRasterCatalog()
        let second = try GoldenEyeTitleRasterCatalog()
        precondition(first == second)
        precondition(first.states.count == 8)
        precondition(first.aggregateHash == 11_519_430_422_207_814_888)
        precondition(first.state(for: .legal).cycleType == 0)
        precondition(first.state(for: .goldenEye).cycleType == 1)
        precondition(first.state(for: .rareware).textureLOD == 0)
        precondition(first.state(for: .rareware).loweringFlags != 0)
        print("goldeneye_title_raster_catalog_smoke: PASS states=\(first.states.count) aggregate=\(first.aggregateHash)")
    }
}
