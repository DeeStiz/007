import Foundation

@main
struct GoldenEyeRamRomGameplayV6Smoke {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            fatalError("usage: goldeneye_ramrom_gameplay_v6_smoke stage-assets boot-assets visible-dependencies")
        }
        let stageRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let bootRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let visibleRoot = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: stageRoot)
        let packets = try GoldenEyeStageScenePacket.loadAll(catalog: catalog)
        let dependencies = try GoldenEyeStageSetupDependencyCatalogV6.load(stageAssetRoot: stageRoot)
        let sidecars = try GoldenEyeStageModelSidecarCatalogV6.load(stageAssetRoot: stageRoot)
        let visibleDependencies = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(rootURL: visibleRoot)
        precondition(MemoryLayout<GERamRomGameplaySetupV6>.size == 192)
        precondition(MemoryLayout<GERamRomGameplayInputV6>.size == 64)
        precondition(MemoryLayout<GERamRomGameplayEntityV6>.size == 276)
        precondition(MemoryLayout<GERamRomGameplayAttachmentV6>.size == 116)
        precondition(MemoryLayout<GERamRomGameplaySnapshotV6>.size == 304)
        precondition(MemoryLayout<GERamRomGameplayEventV6>.size == 184)
        precondition(MemoryLayout<GERamRomGameplayPageV6>.size == 56)
        precondition(MemoryLayout<GERamRomGameplayStateV6>.size == 260816)
        precondition(packets.count == 7)
        precondition(dependencies.isReady)
        precondition(visibleDependencies.isComplete)

        let recordingNames = [
            "ramrom_Dam_1.bin", "ramrom_Dam_2.bin",
            "ramrom_Facility_1.bin", "ramrom_Facility_2.bin", "ramrom_Facility_3.bin",
            "ramrom_Runway_1.bin", "ramrom_Runway_2.bin",
            "ramrom_BunkerI_1.bin", "ramrom_BunkerI_2.bin",
            "ramrom_Silo_1.bin", "ramrom_Silo_2.bin",
            "ramrom_Frigate_1.bin", "ramrom_Frigate_2.bin", "ramrom_Train.bin",
        ]
        var recordingCount = 0
        for name in recordingNames {
            let data = try Data(contentsOf: bootRoot.appendingPathComponent("ramrom", isDirectory: true)
                .appendingPathComponent(name, isDirectory: false), options: [.mappedIfSafe])
            var header = GERamRomHeaderV5()
            var summary = GERamRomParseSummaryV5()
            let status: UInt32 = data.withUnsafeBytes { raw in
                let bytes = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                precondition(ge_ramrom_v5_read_header(bytes, UInt32(data.count), &header) == GE_STATUS_OK)
                return ge_ramrom_v5_parse(bytes, UInt32(data.count), &summary)
            }
            precondition(status == GE_STATUS_OK)
            precondition(summary.flags == UInt32(GE_RAMROM_V5_PARSE_FLAG_MASK))
            precondition(summary.checksum_valid_count == summary.packet_count)
            precondition(summary.rng_checkpoint_count > 0)
            precondition(summary.recording_hash != 0 && header.stage_id != 0)
            precondition(ge_ramrom_gameplay_v6_source_check_ramrom_flags(1, 0, header.slot_number) == header.slot_number)
            precondition(ge_ramrom_gameplay_v6_source_check_ramrom_flags(0, 0, header.slot_number) == 0)
            recordingCount += 1
        }
        var rngA: UInt64 = 0xAB8D_9F77_8128_0783
        let rngFirst = ge_ramrom_gameplay_v6_source_random_next(&rngA)
        var rngB: UInt64 = 0xAB8D_9F77_8128_0783
        let rngSecond = ge_ramrom_gameplay_v6_source_random_next(&rngB)
        precondition(rngA == rngB && rngFirst == rngSecond && rngFirst != 0)

        var pageSets: [UInt32: GoldenEyeRamRomGameplaySourcePagesV6] = [:]
        let sourceSlots: [UInt32: UInt32] = [33: 1, 34: 1, 35: 1, 9: 0, 20: 1, 26: 1, 25: 0]
        for packet in packets {
            let pages = try GoldenEyeRamRomGameplaySourcePagesV6.make(
                stagePacket: packet, dependencies: dependencies, sidecars: sidecars,
                visibleDependencies: visibleDependencies,
                slotNumber: sourceSlots[packet.stageID]
            )
            precondition(!pages.sourceReady, "source pages unexpectedly cleared missing runtime state for \(packet.stageName)")
            precondition(pages.entityCount <= Int(GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES))
            precondition(pages.setup.source_hash != 0 && pages.setup.packet_hash != 0)
            var setup = pages.setup
            if sidecars.isComplete {
                precondition(setup.initial_pad != UInt32.max)
                _ = ge_ramrom_gameplay_v6_validate_setup(&setup)
            } else {
                _ = ge_ramrom_gameplay_v6_validate_setup(&setup)
            }
            pageSets[packet.stageID] = pages
        }
        let routeSlots: [(UInt32, UInt32, UInt32)] = [
            (1, 33, 1), (2, 33, 0),
            (3, 34, 1), (4, 34, 2), (5, 34, 3),
            (6, 35, 1), (7, 35, 2),
            (8, 9, 0), (9, 9, 2),
            (10, 20, 1), (11, 20, 2),
            (12, 26, 1), (13, 26, 1), (14, 25, 0),
        ]
        var routePageCount = 0
        for (_, stageID, slot) in routeSlots {
            let packet = try require(packets.first { $0.stageID == stageID })
            let routePages = try GoldenEyeRamRomGameplaySourcePagesV6.make(
                stagePacket: packet, dependencies: dependencies, sidecars: sidecars,
                visibleDependencies: visibleDependencies, slotNumber: slot
            )
            precondition(routePages.setup.initial_pad != UInt32.max)
            routePageCount += 1
        }

        let dam = try require(packets.first { $0.stageID == 33 })
        let pages = try require(pageSets[33])
        let ramromURL = bootRoot
            .appendingPathComponent("ramrom", isDirectory: true)
            .appendingPathComponent("ramrom_Dam_1.bin", isDirectory: false)
        let recording = try Data(contentsOf: ramromURL, options: [.mappedIfSafe])
        var setup = pages.setup
        var state = GERamRomGameplayStateV6()
        var event = GERamRomGameplayEventV6()
        let beginStatus: UInt32 = pages.entities.withUnsafeBufferPointer { entityBuffer in
            pages.attachments.withUnsafeBufferPointer { attachmentBuffer in
                recording.withUnsafeBytes { bytes in
                    ge_ramrom_gameplay_v6_begin_with_source_pages(
                        bytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        UInt32(recording.count), 1, &setup,
                        entityBuffer.baseAddress!, UInt32(entityBuffer.count),
                        attachmentBuffer.baseAddress, UInt32(attachmentBuffer.count),
                        &state, &event
                    )
                }
            }
        }
        let damSetupValid = ge_ramrom_gameplay_v6_validate_setup(&setup) == GE_STATUS_OK
        if sidecars.isComplete && damSetupValid {
            precondition(beginStatus == GE_STATUS_OK)
            precondition(ge_ramrom_gameplay_v6_validate_event(&event) == GE_STATUS_OK)
            precondition(state.entity_count == UInt32(pages.entityCount))
            var input = GERamRomGameplayInputV6()
            input.header.abi_version = GE_NATIVE_ABI_VERSION
            input.header.struct_size = UInt32(MemoryLayout<GERamRomGameplayInputV6>.size)
            input.record_version = UInt32(GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION)
            input.flags = GE_RAMROM_GAMEPLAY_V6_INPUT_FOCUSED | GE_RAMROM_GAMEPLAY_V6_INPUT_CONTROLLER
            input.controller_count = 1
            input.controller_index = 0
            for tick in UInt64(0)..<UInt64(4) {
                var stepEvent = GERamRomGameplayEventV6()
                let status: UInt32 = recording.withUnsafeBytes { bytes in
                    ge_ramrom_gameplay_v6_step(
                        bytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                        UInt32(recording.count), tick, input, &state, &stepEvent
                    )
                }
                precondition(status == GE_STATUS_OK)
                precondition(stepEvent.native_tick == tick)
                precondition(stepEvent.reference_tick == tick >> 1)
                precondition(stepEvent.pair_phase == UInt32(tick & 1))
                precondition(stepEvent.source_anchor == ((tick & 1) == 0 ? 1 : 0))
                let expectedSourceFrame = (tick >> 1) + 1
                guard stepEvent.source_frame == expectedSourceFrame else {
                    fatalError("paired source frame mismatch tick=\(tick) frame=\(stepEvent.source_frame)")
                }
                precondition(ge_ramrom_gameplay_v6_validate_event(&stepEvent) == GE_STATUS_OK)
            }
            var snapshot = GERamRomGameplaySnapshotV6()
            precondition(ge_ramrom_gameplay_v6_copy_snapshot(&state, &snapshot) == GE_STATUS_OK)
            precondition(snapshot.source_anchor == 0 && snapshot.source_frame == 2)
            var page = GERamRomGameplayPageV6()
            precondition(ge_ramrom_gameplay_v6_copy_page(
                &state, GE_RAMROM_GAMEPLAY_V6_PAGE_ENTITIES, 0, &page
            ) == GE_STATUS_OK)
            precondition(page.item_count == UInt32(GE_RAMROM_GAMEPLAY_V6_MAX_PAGED_ITEMS))
            var copied = UInt32(0)
            var rows = [GERamRomGameplayEntityV6](
                repeating: GERamRomGameplayEntityV6(),
                count: Int(GE_RAMROM_GAMEPLAY_V6_MAX_PAGED_ITEMS)
            )
            let rowCapacity = UInt32(rows.count)
            let copyStatus: UInt32 = rows.withUnsafeMutableBufferPointer { buffer in
                ge_ramrom_gameplay_v6_copy_entities(
                    &state, 0, rowCapacity, buffer.baseAddress, &copied
                )
            }
            precondition(copyStatus == GE_STATUS_OK)
            precondition(copied == page.item_count)
        } else {
            precondition(beginStatus != GE_STATUS_OK, "partial model pages must fail closed")
        }
        print(
                "goldeneye_ramrom_gameplay_v6_smoke: PASS stages=\(pageSets.count) " +
                "recordings=\(recordingCount) " +
                "routePages=\(routePageCount) " +
                "damEntities=\(pages.entityCount) " +
                "sidecarComplete=\(sidecars.isComplete ? 1 : 0) " +
                "sourceReady=\(pageSets.values.filter(\.sourceReady).count) " +
                "runtimeInstall=\(sidecars.isComplete && damSetupValid ? 1 : 0)"
        )
        _ = dam
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "gameplay-v6-smoke", code: 1) }
        return value
    }
}
