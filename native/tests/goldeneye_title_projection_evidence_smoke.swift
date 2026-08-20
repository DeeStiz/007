import Foundation

@main
struct GoldenEyeTitleProjectionEvidenceSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let names = ["legalpage", "nintendologo", "goldeneyelogo", "walletbond",
                     "headbrosnansuit", "suitbond", "chrwppk", "rarewarelogo"]
        let packets = try names.map {
            try GoldenEyeTitleGeometryPacket.load(from: root.appendingPathComponent("\($0).gepk"))
        }
        guard let canonical = GoldenEyeProjectionV10.ViewportV10(drawableWidth: 440, drawableHeight: 330),
              let widescreen = GoldenEyeProjectionV10.ViewportV10(drawableWidth: 1920, drawableHeight: 1080) else {
            throw NSError(domain: "GoldenEyeTitleProjectionEvidenceSmoke", code: 1)
        }
        let first = GoldenEyeTitleProjectionEvidence.evaluate(
            packets: packets, canonical: canonical, widescreen: widescreen
        )
        let second = GoldenEyeTitleProjectionEvidence.evaluate(
            packets: packets, canonical: canonical, widescreen: widescreen
        )
        precondition(first == second)
        precondition(first.records.count == 8)
        precondition(first.records.allSatisfy { $0.vertexCount > 0 && $0.canonicalHash != 0 && $0.widescreenHash != 0 })
        precondition(first.records.contains { $0.canonicalHash != $0.widescreenHash })
        print("goldeneye_title_projection_evidence_smoke: PASS packets=\(first.records.count) aggregate=\(first.aggregateHash)")
    }
}
