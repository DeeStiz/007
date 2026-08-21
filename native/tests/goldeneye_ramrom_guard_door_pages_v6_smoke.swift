import Foundation

@main
struct GoldenEyeRamRomGuardDoorPagesV6Smoke {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("usage: guard_door_pages_smoke stage-root visible-root")
        }
        let stageRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let visibleRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: stageRoot)
        let packets = try GoldenEyeStageScenePacket.loadAll(catalog: catalog)
        let dependencies = try GoldenEyeStageSetupDependencyCatalogV6.load(stageAssetRoot: stageRoot)
        let sidecars = try GoldenEyeStageModelSidecarCatalogV6.load(stageAssetRoot: stageRoot)
        let visible = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(rootURL: visibleRoot)
        let first = try GoldenEyeRamRomGuardDoorPagesV6.makeAll(
            packets: packets, dependencies: dependencies,
            sidecars: sidecars, visibleDependencies: visible
        )
        let second = try GoldenEyeRamRomGuardDoorPagesV6.makeAll(
            packets: packets, dependencies: dependencies,
            sidecars: sidecars, visibleDependencies: visible
        )
        precondition(!visible.categoryNames.contains("ai"))
        precondition(first.count == 14 && second.count == 14)
        precondition(Set(first.map(\.stageID)).count == 7)
        precondition(first.map(\.pageHash) == second.map(\.pageHash))
        precondition(first.map(\.missingFields) == second.map(\.missingFields))
        precondition(first.allSatisfy { !$0.sourceReady })
        precondition(first.allSatisfy { $0.setup.source_hash != 0 && $0.setup.packet_hash != 0 })
        precondition(first.allSatisfy { $0.setup.guard_count == UInt32($0.guards.count) })
        precondition(first.allSatisfy { $0.setup.door_count == UInt32($0.doors.count) })
        precondition(first.allSatisfy { !$0.missingFields.contains("guard_ai_runtime_state") })
        precondition(first.allSatisfy { $0.missingFields.contains(where: { $0.hasPrefix("guard_ai_") }) })
        precondition(first.allSatisfy { !$0.missingFields.contains("guard_pose_pages") })
        precondition(first.allSatisfy { $0.missingFields.contains(where: { $0.hasPrefix("guard_pose_decoder.") }) })
        precondition(first.allSatisfy { !$0.missingFields.contains("guard_render_context") })
        precondition(first.allSatisfy { !$0.missingFields.contains("guard_render_context.fog_colour.source_chr_shade") })
        let missingGlobalRows = [
            "guard_ai_list_2.canonical_row.src_game_chraidata.c:88:m_StandardGuard",
            "guard_ai_list_5.canonical_row.src_game_chraidata.c:260:m_SimpleGuardDeaf",
            "guard_ai_list_9.canonical_row.src_game_chraidata.c:471:m_SimpleGuardAlarmRaiser",
        ]
        let allMissingFields = first.flatMap(\.missingFields)
        precondition(missingGlobalRows.allSatisfy { allMissingFields.contains($0) })
        let weaponChoiceRows = first.reduce(0) { partial, page in
            partial + page.guards.reduce(0) { $0 + Int($1.weapon_choice_count) }
        }
        precondition(weaponChoiceRows > 0)
        let weaponMissingPages = first.filter { page in
            page.missingFields.contains(where: { $0.hasPrefix("guard_weapon_source_selection") })
        }.count
        let guards = first.reduce(0) { $0 + $1.guardCount }
        let doors = first.reduce(0) { $0 + $1.doorCount }
        let poseRows = first.reduce(0) { $0 + $1.poseCount }
        let renderRows = first.flatMap(\.guards)
        let renderModeRows = renderRows.filter { $0.raw_render_mode == 0xc411_2078 }.count
        let fogRows = renderRows.filter { $0.fog_rgba != UInt32.max }.count
        precondition(renderRows.allSatisfy {
            $0.raw_render_mode == 0xc411_2078 && $0.fog_rgba != UInt32.max
        })
        precondition(poseRows > 0)
        precondition(first.flatMap(\.poses).allSatisfy {
            $0.header.abi_version == GE_NATIVE_ABI_VERSION &&
                $0.header.struct_size == UInt32(MemoryLayout<GESourceAnimationPoseV6>.size) &&
                $0.skeleton_handle != 0 && $0.pose_hash != 0
        })
        let poseEvidence = Array(Set(first.flatMap { page in
            page.missingFields.filter { $0.hasPrefix("guard_pose_decoder.") }
        })).sorted().prefix(3).joined(separator: ",")
        let aiEvidence = Array(Set(first.flatMap { page in
            page.missingFields.filter { $0.hasPrefix("guard_ai_source_") }
        })).sorted().prefix(2).joined(separator: ",")
        let weaponEvidence = Array(Set(first.flatMap { page in
            page.missingFields.filter { $0.hasPrefix("guard_weapon_source_selection") }
        })).sorted().prefix(3).joined(separator: ",")
        let weaponPageEvidence = first.filter { page in
            page.missingFields.contains(where: { $0.hasPrefix("guard_weapon_source_selection") })
        }.map { page in
            "demo\(page.demoID)/stage\(page.stageID):" +
                (page.missingFields.first(where: { $0.hasPrefix("guard_weapon_source_selection") }) ?? "unknown")
        }.prefix(5).joined(separator: ";")
        let transformedDoors = first.reduce(0) { partial, page in
            partial + page.doors.reduce(0) { $0 + hasMatrix($1.base_transform_q16) }
        }
        let resolvedPortalRows = first.reduce(0) { partial, page in
            partial + page.doors.reduce(0) { $0 + ($1.portal_number != UInt32.max ? 1 : 0) }
        }
        let portalNumbers = first.flatMap { $0.doors.map(\.portal_number) }
        let portalHash = portalNumbers.reduce(UInt64(1_469_598_103_934_665_603)) { hash, value in
            stride(from: 0, to: 32, by: 8).reduce(hash) { partial, shift in
                (partial ^ UInt64((value >> UInt32(shift)) & 0xff)) &* 1_099_511_628_211
            }
        }
        print(
            "goldeneye_ramrom_guard_door_pages_v6_smoke: PASS demos=14 runs=2 " +
                "stages=7 guards=\(guards) doors=\(doors) transformedDoors=\(transformedDoors) " +
                "weaponChoices=\(weaponChoiceRows) poseRows=\(poseRows) sourceReady=0 aiEvidence=14 " +
                "poseDecoderEvidence=14 poseEvidence=\(poseEvidence) renderRows=\(renderRows.count) " +
                "renderModeRows=\(renderModeRows) fogRows=\(fogRows) aiSourceEvidence=\(aiEvidence) " +
                "weaponEvidence=\(weaponEvidence) weaponPageEvidence=\(weaponPageEvidence) " +
                "missingWeaponPages=\(weaponMissingPages) resolvedPortalRows=\(resolvedPortalRows) " +
                "uniquePortals=\(Set(portalNumbers).count) portalHash=\(portalHash)"
        )
    }

    private static func hasMatrix<T>(_ tuple: T) -> Int {
        withUnsafeBytes(of: tuple) { raw in
            raw.bindMemory(to: Int32.self).contains { $0 != 0 } ? 1 : 0
        }
    }
}
