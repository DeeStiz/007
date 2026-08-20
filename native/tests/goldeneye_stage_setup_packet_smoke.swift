import Foundation

private struct StageSpec {
    let id: UInt32
    let name: String
    let setup: String
    let background: String
}

private let stages: [StageSpec] = [
    StageSpec(id: 33, name: "Dam", setup: "UsetupdamZ", background: "bg_dam_all_p"),
    StageSpec(id: 34, name: "Facility", setup: "UsetuparkZ", background: "bg_ark_all_p"),
    StageSpec(id: 35, name: "Runway", setup: "UsetuprunZ", background: "bg_run_all_p"),
    StageSpec(id: 9, name: "Bunker_I", setup: "UsetupsevbunkerZ", background: "bg_sev_all_p"),
    StageSpec(id: 20, name: "Silo", setup: "UsetupsiloZ", background: "bg_silo_all_p"),
    StageSpec(id: 26, name: "Frigate", setup: "UsetupdestZ", background: "bg_dest_all_p"),
    StageSpec(id: 25, name: "Train", setup: "UsetuptraZ", background: "bg_tra_all_p"),
]

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(
        Data("goldeneye_stage_setup_packet_smoke: FAIL \(message)\n".utf8)
    )
    exit(1)
}

@main
struct GoldenEyeStageSetupPacketSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fail("usage: goldeneye_stage_setup_packet_smoke <stage-assets-root>")
        }

        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var totalObjects: UInt32 = 0
        var totalDoors: UInt32 = 0
        var totalPads: UInt32 = 0
        var totalPortals: UInt32 = 0
        var aggregateHash: UInt64 = 1469598103934665603

        for stage in stages {
            let safeName = stage.name.replacingOccurrences(of: " ", with: "_")
            let setupURL = root
                .appendingPathComponent("setup", isDirectory: true)
                .appendingPathComponent("\(safeName)__setup__\(stage.setup).bin")
            let backgroundURL = root
                .appendingPathComponent("background", isDirectory: true)
                .appendingPathComponent("\(safeName)__background__\(stage.background).bin")
            let setupData: Data
            let backgroundData: Data
            do {
                setupData = try Data(contentsOf: setupURL, options: [.mappedIfSafe])
                backgroundData = try Data(contentsOf: backgroundURL, options: [.mappedIfSafe])
            } catch {
                fail("missing \(stage.name) prepared payload: \(error)")
            }

            let packet: GoldenEyeStageSetupPacket
            let repeatPacket: GoldenEyeStageSetupPacket
            do {
                packet = try GoldenEyeStageSetupPacket.load(
                    stageID: stage.id, setupData: setupData, backgroundData: backgroundData
                )
                repeatPacket = try GoldenEyeStageSetupPacket.load(
                    stageID: stage.id, setupData: setupData, backgroundData: backgroundData
                )
            } catch {
                fail("parse \(stage.name): \(error)")
            }

            guard packet == repeatPacket else { fail("non-deterministic \(stage.name) packet") }
            guard packet.header.offsets.count == 10 else { fail("\(stage.name) header count") }
            guard !packet.pads.isEmpty, !packet.boundPads.isEmpty else {
                fail("\(stage.name) pad sentinel/count")
            }
            guard !packet.objects.isEmpty, !packet.intros.isEmpty else {
                fail("\(stage.name) setup sections")
            }
            // A source setup is allowed to carry an empty main navigation or
            // AI section; the parser still requires each present section's
            // own sentinel and keeps the zero count as semantic data.
            guard !packet.portals.isEmpty else { fail("\(stage.name) portal table") }
            guard packet.objects.allSatisfy({ $0.recordBytes % 4 == 0 }) else {
                fail("\(stage.name) object record alignment")
            }
            guard packet.portals.allSatisfy({
                $0.geometryOffset < UInt32(backgroundData.count) &&
                    $0.connectedRoom1 <= 0xff && $0.connectedRoom2 <= 0xff
            }) else {
                fail("\(stage.name) portal bounds")
            }

            totalObjects += UInt32(packet.objects.count)
            totalDoors += packet.doorCount
            totalPads += UInt32(packet.pads.count + packet.boundPads.count)
            totalPortals += UInt32(packet.portals.count)
            for shift in stride(from: 0, to: 64, by: 8) {
                aggregateHash =
                    (aggregateHash ^ ((packet.packetHash >> UInt64(shift)) & 0xff)) &
                    1099511628211
            }
            print(
                "stage=\(stage.id) name=\(stage.name) bytes=\(packet.sourceBytes) " +
                    "pads=\(packet.pads.count) boundPads=\(packet.boundPads.count) " +
                    "objects=\(packet.objects.count) doors=\(packet.doorCount) " +
                    "tinted=\(packet.tintedGlassCount) portalHints=\(packet.portalHintCount) " +
                    "intros=\(packet.intros.count) waypoints=\(packet.waypoints.count) " +
                    "groups=\(packet.waygroups.count) paths=\(packet.patrolPaths.count) " +
                    "ai=\(packet.aiLists.count) portals=\(packet.portals.count) " +
                    "hash=\(packet.packetHash)"
            )
        }

        print(
            "goldeneye_stage_setup_packet_smoke: PASS stages=\(stages.count) " +
                "objects=\(totalObjects) doors=\(totalDoors) pads=\(totalPads) " +
                "portals=\(totalPortals) aggregateHash=\(aggregateHash)"
        )

        do {
            _ = try GoldenEyeStageSetupPacket.load(
                stageID: 1,
                setupData: Data(repeating: 0, count: 39)
            )
            fail("truncated setup unexpectedly accepted")
        } catch {
            // Expected fail-closed path.
        }

        var invalidHeader = Data(repeating: 0, count: 40)
        invalidHeader[3] = 1
        do {
            _ = try GoldenEyeStageSetupPacket.load(
                stageID: 1,
                setupData: invalidHeader
            )
            fail("invalid setup offset unexpectedly accepted")
        } catch {
            // Expected fail-closed path.
        }

        var invalidPortalHeader = Data(repeating: 0, count: 20)
        invalidPortalHeader[8] = 0x0f
        invalidPortalHeader[9] = 0x00
        invalidPortalHeader[10] = 0x00
        invalidPortalHeader[11] = 0x14
        do {
            _ = try GoldenEyeStageSetupPacket.load(
                stageID: 1,
                setupData: Data(repeating: 0, count: 40),
                backgroundData: invalidPortalHeader
            )
            fail("invalid portal offset unexpectedly accepted")
        } catch {
            // Expected fail-closed path.
        }

        print("goldeneye_stage_setup_packet_smoke: PASS malformed_fail_closed=3")
    }
}
