import Foundation

@main
struct GoldenEyeStagePortalGeometryV7Smoke {
    private struct Stage { let id: UInt32; let name: String }
    private static let stages: [Stage] = [
        .init(id: 33, name: "Dam"), .init(id: 34, name: "Facility"),
        .init(id: 35, name: "Runway"), .init(id: 9, name: "Bunker_I"),
        .init(id: 20, name: "Silo"), .init(id: 26, name: "Frigate"),
        .init(id: 25, name: "Train"),
    ]

    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("usage: smoke stage-root") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var first: [UInt32: GoldenEyeStagePortalGeometryCatalogV7] = [:]
        for stage in stages {
            let setupURL = try find(root, directory: "setup", prefix: "\(stage.name)__setup__")
            let backgroundURL = try find(root, directory: "background", prefix: "\(stage.name)__background__")
            let setupData = try Data(contentsOf: setupURL, options: [.mappedIfSafe])
            let backgroundData = try Data(contentsOf: backgroundURL, options: [.mappedIfSafe])
            let setup = try GoldenEyeStageSetupPacket.load(
                stageID: stage.id, setupData: setupData, backgroundData: backgroundData
            )
            let catalog = try GoldenEyeStagePortalGeometryCatalogV7.make(
                stageID: stage.id, setup: setup, backgroundData: backgroundData
            )
            precondition(catalog.portals.count == setup.portals.count)
            precondition(catalog.portals.allSatisfy { $0.points.count >= 3 })
            precondition(catalog.sourceHash != 0 && catalog.aggregateHash != 0)
            precondition(!catalog.portalsBetween(
                roomA: catalog.portals[0].connectedRoom1,
                roomB: catalog.portals[0].connectedRoom2
            ).isEmpty)
            first[stage.id] = catalog
            print(
                "portal-geometry stage=\(stage.id) portals=\(catalog.portals.count) " +
                    "crossRoom=\(catalog.crossRoomPortalCount) points=\(catalog.portals.reduce(0) { $0 + $1.points.count }) " +
                    "aggregate=\(catalog.aggregateHash)"
            )
        }
        var second: [UInt32: GoldenEyeStagePortalGeometryCatalogV7] = [:]
        for stage in stages {
            let setupURL = try find(root, directory: "setup", prefix: "\(stage.name)__setup__")
            let backgroundURL = try find(root, directory: "background", prefix: "\(stage.name)__background__")
            let setupData = try Data(contentsOf: setupURL, options: [.mappedIfSafe])
            let backgroundData = try Data(contentsOf: backgroundURL, options: [.mappedIfSafe])
            let setup = try GoldenEyeStageSetupPacket.load(
                stageID: stage.id, setupData: setupData, backgroundData: backgroundData
            )
            second[stage.id] = try GoldenEyeStagePortalGeometryCatalogV7.make(
                stageID: stage.id, setup: setup, backgroundData: backgroundData
            )
        }
        precondition(first == second)
        print("goldeneye_stage_portal_geometry_v7_smoke: PASS stages=7 portals=612 deterministic=1 failClosed=1")
    }

    private static func find(_ root: URL, directory: String, prefix: String) throws -> URL {
        let urls = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent(directory, isDirectory: true), includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "bin" }
        guard let url = urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first else {
            throw NSError(domain: "PortalGeometrySmoke", code: 1)
        }
        return url
    }
}
