import Foundation

@main
struct GoldenEyeStageSetupSemanticsSmoke {
    private struct StageSpec {
        let id: UInt32
        let name: String
        let setup: String
        let background: String
    }

    private static let stages = [
        StageSpec(id: 33, name: "Dam", setup: "UsetupdamZ", background: "bg_dam_all_p"),
        StageSpec(id: 34, name: "Facility", setup: "UsetuparkZ", background: "bg_ark_all_p"),
        StageSpec(id: 35, name: "Runway", setup: "UsetuprunZ", background: "bg_run_all_p"),
        StageSpec(id: 9, name: "Bunker_I", setup: "UsetupsevbunkerZ", background: "bg_sev_all_p"),
        StageSpec(id: 20, name: "Silo", setup: "UsetupsiloZ", background: "bg_silo_all_p"),
        StageSpec(id: 26, name: "Frigate", setup: "UsetupdestZ", background: "bg_dest_all_p"),
        StageSpec(id: 25, name: "Train", setup: "UsetuptraZ", background: "bg_tra_all_p"),
    ]

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "stage-setup", code: 2, userInfo: [NSLocalizedDescriptionKey: "stage asset root required"])
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var aggregate: UInt64 = 1469598103934665603
        var objects = 0
        var portals = 0
        var pads = 0
        for stage in stages {
            let safeName = stage.name.replacingOccurrences(of: " ", with: "_")
            let setupURL = root.appendingPathComponent("setup/\(safeName)__setup__\(stage.setup).bin")
            let backgroundURL = root.appendingPathComponent("background/\(safeName)__background__\(stage.background).bin")
            let setup = try Data(contentsOf: setupURL, options: [.mappedIfSafe])
            let background = try Data(contentsOf: backgroundURL, options: [.mappedIfSafe])
            let packet = try GoldenEyeStageSetupPacket.load(stageID: stage.id, setupData: setup, backgroundData: background)
            let repeatPacket = try GoldenEyeStageSetupPacket.load(stageID: stage.id, setupData: setup, backgroundData: background)
            precondition(packet == repeatPacket)
            precondition(packet.header.offsets.count == 10)
            precondition(!packet.objects.isEmpty && !packet.pads.isEmpty && !packet.portals.isEmpty)
            objects += packet.objects.count
            portals += packet.portals.count
            pads += packet.pads.count + packet.boundPads.count
            for shift in stride(from: 0, to: 64, by: 8) {
                aggregate = (aggregate ^ ((packet.packetHash >> UInt64(shift)) & 0xff)) &* 1099511628211
            }
            print("stage=\(stage.id) name=\(stage.name) objects=\(packet.objects.count) pads=\(packet.pads.count + packet.boundPads.count) portals=\(packet.portals.count) intros=\(packet.intros.count) waypoints=\(packet.waypoints.count) ai=\(packet.aiLists.count) hash=\(packet.packetHash)")
        }
        print("goldeneye_stage_setup_semantics_smoke: PASS stages=7 objects=\(objects) pads=\(pads) portals=\(portals) aggregateHash=\(aggregate)")
    }
}
