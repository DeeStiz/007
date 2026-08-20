import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

@main
struct GoldenEyePlayerCameraOwnerV6Smoke {
    private struct Route {
        let demoID: UInt32
        let stageID: UInt32
        let slot: UInt32
        let name: String
    }

    private struct Result: Equatable {
        let demoID: UInt32
        let samples: UInt32
        let recordingHash: UInt64
        let terminalChecksum: UInt32
        let playerHash: UInt64
        let cameraHash: UInt64
        let roomHash: UInt64
        let ownerHash: UInt64
        let aggregate: UInt64
    }

    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError("usage: goldeneye_player_camera_owner_v6_smoke stage-assets boot-assets visible-dependencies")
        }
        let stageRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let bootRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let visibleRoot = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: stageRoot)
        let packets = try GoldenEyeStageScenePacket.loadAll(catalog: catalog)
        let dependencies = try GoldenEyeStageSetupDependencyCatalogV6.load(stageAssetRoot: stageRoot)
        let sidecars = try GoldenEyeStageModelSidecarCatalogV6.load(stageAssetRoot: stageRoot)
        let visible = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(rootURL: visibleRoot)
        let routes: [Route] = [
            .init(demoID: 1, stageID: 33, slot: 1, name: "ramrom_Dam_1.bin"),
            .init(demoID: 2, stageID: 33, slot: 1, name: "ramrom_Dam_2.bin"),
            .init(demoID: 3, stageID: 34, slot: 1, name: "ramrom_Facility_1.bin"),
            .init(demoID: 4, stageID: 34, slot: 1, name: "ramrom_Facility_2.bin"),
            .init(demoID: 5, stageID: 34, slot: 1, name: "ramrom_Facility_3.bin"),
            .init(demoID: 6, stageID: 35, slot: 1, name: "ramrom_Runway_1.bin"),
            .init(demoID: 7, stageID: 35, slot: 1, name: "ramrom_Runway_2.bin"),
            .init(demoID: 8, stageID: 9, slot: 0, name: "ramrom_BunkerI_1.bin"),
            .init(demoID: 9, stageID: 9, slot: 0, name: "ramrom_BunkerI_2.bin"),
            .init(demoID: 10, stageID: 20, slot: 1, name: "ramrom_Silo_1.bin"),
            .init(demoID: 11, stageID: 20, slot: 1, name: "ramrom_Silo_2.bin"),
            .init(demoID: 12, stageID: 26, slot: 1, name: "ramrom_Frigate_1.bin"),
            .init(demoID: 13, stageID: 26, slot: 1, name: "ramrom_Frigate_2.bin"),
            .init(demoID: 14, stageID: 25, slot: 0, name: "ramrom_Train.bin"),
        ]
        var first: [UInt32: Result] = [:]
        var second: [UInt32: Result] = [:]
        for pass in 0..<2 {
            for route in routes {
                guard let packet = packets.first(where: { $0.stageID == route.stageID }) else {
                    throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.invalidStage(route.stageID)
                }
                let pages = try GoldenEyeRamRomGameplaySourcePagesV6.make(
                    stagePacket: packet, dependencies: dependencies, sidecars: sidecars,
                    visibleDependencies: visible, slotNumber: route.slot
                )
                let data = try Data(contentsOf: bootRoot.appendingPathComponent("ramrom", isDirectory: true)
                    .appendingPathComponent(route.name, isDirectory: false), options: [.mappedIfSafe])
                var header = GERamRomHeaderV5()
                var summary = GERamRomParseSummaryV5()
                let parseStatus = data.withUnsafeBytes { raw -> UInt32 in
                    guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return UInt32(GE_STATUS_INVALID_ARGUMENT)
                    }
                    let h = ge_ramrom_v5_read_header(base, UInt32(data.count), &header)
                    guard h == UInt32(GE_STATUS_OK) else { return h }
                    return ge_ramrom_v5_parse(base, UInt32(data.count), &summary)
                }
                guard parseStatus == UInt32(GE_STATUS_OK),
                      summary.checksum_valid_count == summary.packet_count,
                      summary.rng_checkpoint_count > 0 else {
                    throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.invalidRecording(
                        route.demoID, parseStatus
                    )
                }
                let styles = Self.u32Values(header.controller_styles)
                let options = try GoldenEyeRamRomSourceOptionStateV6(
                    controlStyle: styles.first ?? 0, invertLook: 0,
                    sourceHash: 0x4f5054494f4e5f55,
                    provenance: [
                        "RAMROM header controller_styles[0]",
                        "src/game/options.c:104 default vertical-look option",
                    ]
                )
                let pagesWithPlayer = try GoldenEyeRamRomPlayerCameraPageBuilderV6.make(
                    stagePacket: packet, sourcePages: pages, ramromHeader: header,
                    optionState: options, demoID: route.demoID
                )
                let result = try run(
                    route: route, pages: pagesWithPlayer, data: data, summary: summary
                )
                if pass == 0 {
                    first[route.demoID] = result
                } else {
                    guard second[route.demoID] == nil, first[route.demoID] == result else {
                        fatalError("player/camera route (route.demoID) is not deterministic")
                    }
                    second[route.demoID] = result
                }
                print(
                    "player-camera demo=\(route.demoID) stage=\(route.stageID) " +
                        "samples=\(result.samples) roomHash=\(result.roomHash) " +
                        "playerHash=\(result.playerHash) cameraHash=\(result.cameraHash) " +
                        "ownerHash=\(result.ownerHash)"
                )
            }
        }
        guard first.count == 14, second.count == 14 else {
            fatalError("player/camera route count mismatch")
        }
        let aggregate = first.values.sorted { $0.demoID < $1.demoID }.reduce(UInt64(1_469_598_103_934_665_603)) { hash, result in
            Self.mix(hash, [
                UInt64(result.demoID), UInt64(result.samples), result.recordingHash,
                UInt64(result.terminalChecksum), result.playerHash, result.cameraHash,
                result.roomHash, result.ownerHash, result.aggregate,
            ])
        }
        print(
            "goldeneye_player_camera_owner_v6_smoke: PASS demos=14 runs=28 " +
                "aggregate=\(aggregate) dam1Owner=\(first[1]!.ownerHash)"
        )
    }

    private static func run(
        route: Route, pages: GoldenEyeRamRomPlayerCameraPagesV6, data: Data,
        summary: GERamRomParseSummaryV5
    ) throws -> Result {
        do {
            let owner = try GoldenEyeRamRomPlayerCameraOwnerV6(pages: pages)
            return try runOwner(owner, route: route, pages: pages, data: data, summary: summary)
        } catch {
            var setupCopy = pages.setup
            var sourceCopy = pages.source
            let setupStatus = ge_ramrom_gameplay_v6_validate_setup(&setupCopy)
            let sourceStatus = ge_player_camera_owner_validate_source(&sourceCopy)
            let entity = pages.entities.first
            var badEntity: String = "none"
            for (index, candidate) in pages.entities.enumerated() {
                var copy = candidate
                let status = ge_ramrom_gameplay_v6_validate_entity(&copy)
                if status != UInt32(GE_STATUS_OK) {
                    badEntity = "\(index):\(status)"
                    break
                }
            }
            var badTile: String = "none"
            for (index, candidate) in pages.stan.enumerated() {
                var copy = candidate
                let status = ge_player_camera_owner_validate_tile(&copy)
                if status != UInt32(GE_STATUS_OK) {
                    let bytes = withUnsafeBytes(of: copy) { Array($0.prefix(152)) }
                    let byteString = bytes.map { String(format: "%02x", $0) }.joined()
                    badTile = "\(index):\(status):id=\(copy.tile_id):room=\(copy.room_id):flags=\(copy.flags):points=\(copy.point_count):hash=\(copy.source_hash):bytes=\(byteString)"
                    break
                }
            }
            var badPad: String = "none"
            for (index, candidate) in pages.pads.enumerated() {
                var copy = candidate
                let status = ge_player_camera_owner_validate_pad(&copy)
                if status != UInt32(GE_STATUS_OK) {
                    badPad = "\(index):\(status)"
                    break
                }
            }
            let counts = "entities=\(pages.entities.count) stan=\(pages.stan.count) pads=\(pages.pads.count)"
            let firstEntity = "firstEntity=\(entity?.entity_kind ?? 0)/\(entity?.health ?? 0)/\(entity?.weapon_model_handle ?? 0)"
            let sourceValues = "sourceValues=\(pages.source.initial_weapon)/\(pages.source.initial_health)/\(pages.source.initial_animation)"
            let message = "owner-init-debug demo=\(route.demoID) setup=\(setupStatus) source=\(sourceStatus) " +
                counts + " " + firstEntity + " " + sourceValues + " badEntity=\(badEntity) " +
                "badTile=\(badTile) badPad=\(badPad) error=\(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            throw error
        }
    }

    private static func runOwner(
        _ owner: GoldenEyeRamRomPlayerCameraOwnerV6, route: Route,
        pages: GoldenEyeRamRomPlayerCameraPagesV6, data: Data,
        summary: GERamRomParseSummaryV5
    ) throws -> Result {
        var nativeTick: UInt64 = 0
        var sampleCount: UInt32 = 0
        var terminalChecksum: UInt32 = 0
        var aggregate = UInt64(1_469_598_103_934_665_603)
        var lastPublication: GoldenEyeRamRomPlayerCameraPublicationV6?
        for packetIndex in 0..<summary.packet_count {
            var packet = GERamRomPacketV5()
            let packetStatus = data.withUnsafeBytes { raw -> UInt32 in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return UInt32(GE_STATUS_INVALID_ARGUMENT)
                }
                return ge_ramrom_v5_read_packet(base, UInt32(data.count), packetIndex, &packet)
            }
            guard packetStatus == UInt32(GE_STATUS_OK) else {
                throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.ownerStatus(packetStatus)
            }
            for frameIndex in 0..<packet.record_count {
                var sample = GERamRomSampleV5()
                let sampleStatus = data.withUnsafeBytes { raw -> UInt32 in
                    guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return UInt32(GE_STATUS_INVALID_ARGUMENT)
                    }
                    return ge_ramrom_v5_copy_sample(
                        base, UInt32(data.count), packetIndex, frameIndex, 0, &sample
                    )
                }
                guard sampleStatus == UInt32(GE_STATUS_OK) else {
                    throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.ownerStatus(sampleStatus)
                }
                let input = Self.input(sample)
                let publication = try owner.step(nativeTick: nativeTick, input: input)
                nativeTick += 1
                _ = try owner.step(nativeTick: nativeTick, input: Self.noInput())
                nativeTick += 1
                lastPublication = publication
                sampleCount &+= 1
                terminalChecksum = packet.checksum
                aggregate = Self.mix(aggregate, [
                    UInt64(packetIndex), UInt64(frameIndex), UInt64(sample.buttons),
                    UInt64(bitPattern: Int64(sample.stick_x)), UInt64(bitPattern: Int64(sample.stick_y)),
                    UInt64(packet.rng_seed), UInt64(packet.checksum), publication.ownerStateHash,
                ])
            }
        }
        guard let publication = lastPublication else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.invalidRecording(route.demoID, 0)
        }
        return Result(
            demoID: route.demoID, samples: sampleCount,
            recordingHash: UInt64(summary.recording_hash), terminalChecksum: terminalChecksum,
            playerHash: publication.playerHash, cameraHash: publication.cameraHash,
            roomHash: publication.roomHash, ownerHash: publication.ownerStateHash,
            aggregate: aggregate
        )
    }

    private static func input(_ sample: GERamRomSampleV5) -> GERamRomGameplayInputV6 {
        var value = noInput()
        value.stick_x = Int16(sample.stick_x)
        value.stick_y = Int16(sample.stick_y)
        value.pressed_buttons = UInt32(sample.buttons)
        value.held_buttons = UInt32(sample.buttons)
        return value
    }

    private static func noInput() -> GERamRomGameplayInputV6 {
        var value = GERamRomGameplayInputV6()
        value.header.abi_version = GE_NATIVE_ABI_VERSION
        value.header.struct_size = UInt32(MemoryLayout<GERamRomGameplayInputV6>.size)
        value.record_version = UInt32(GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION)
        value.flags = UInt32(GE_RAMROM_GAMEPLAY_V6_INPUT_RECORDED) |
            UInt32(GE_RAMROM_GAMEPLAY_V6_INPUT_FOCUSED) |
            UInt32(GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER)
        value.controller_count = 1
        value.controller_index = 0
        value.source_mask = UInt32(GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER)
        return value
    }

    private static func u32Values<T>(_ tuple: T) -> [UInt32] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: UInt32.self)) }
    }

    private static func mix(_ initial: UInt64, _ values: [UInt64]) -> UInt64 {
        values.reduce(initial) { hash, value in
            var result = hash
            for shift in stride(from: 0, to: 64, by: 8) {
                result = (result ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
            }
            return result
        }
    }
}
