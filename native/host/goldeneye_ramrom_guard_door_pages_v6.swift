import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Prepared source pages for the RAMROM guard/door owner.  The records are
/// copied values only; no setup payload, ROM path, source pointer, or model
/// graph is retained.  A page may describe valid static placement while still
/// remaining sourceReady=false when dynamic authority is not available.
public struct GoldenEyeRamRomGuardDoorPagesV6: @unchecked Sendable {
    public let stageID: UInt32
    public let stageName: String
    public let demoID: UInt8
    public let slotNumber: UInt32
    public let setup: GEGuardDoorOwnerSetupV6
    public let guards: [GEGuardDoorOwnerGuardSourceV6]
    public let doors: [GEGuardDoorOwnerDoorSourceV6]
    public let poses: [GESourceAnimationPoseV6]
    public let attachments: [GEGuardDoorOwnerAttachmentV6]
    public let sourceReady: Bool
    public let missingFields: [String]
    public let sourceHash: UInt64
    public let packetHash: UInt64
    public let modelDependencyHash: UInt64
    public let pageHash: UInt64

    public var guardCount: Int { guards.count }
    public var doorCount: Int { doors.count }
    public var poseCount: Int { poses.count }
    public var attachmentCount: Int { attachments.count }

    public enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case stageMismatch(UInt32, UInt32)
        case routeMismatch(UInt8, UInt32)
        case missingSetupPayload(UInt32)
        case malformedSetup(UInt32, String)
        case missingBoundPad(UInt32, UInt32)
        case missingModel(UInt32, String, UInt32)
        case invalidModelBounds(UInt32, String)
        case capacity(UInt32, String, Int)

        public var description: String {
            switch self {
            case let .stageMismatch(expected, actual):
                return "guard/door stage mismatch " + String(actual) + " != " + String(expected)
            case let .routeMismatch(demo, stage):
                return "guard/door route " + String(demo) + " does not select stage " + String(stage)
            case let .missingSetupPayload(stage): return "guard/door setup payload missing for stage " + String(stage)
            case let .malformedSetup(stage, detail): return "guard/door setup " + String(stage) + " malformed: " + detail
            case let .missingBoundPad(stage, pad): return "guard/door stage " + String(stage) + " bound pad " + String(pad) + " missing"
            case let .missingModel(stage, kind, index):
                return "guard/door stage " + String(stage) + " " + kind + " model " + String(index) + " is missing"
            case let .invalidModelBounds(stage, name):
                return "guard/door stage " + String(stage) + " model bounds unavailable: " + name
            case let .capacity(stage, kind, count):
                return "guard/door stage " + String(stage) + " " + kind + " count " + String(count) + " exceeds bounded capacity"
            }
        }
    }

    private static let route: [(demo: UInt8, stage: UInt32, slot: UInt32)] = [
        (1, 33, 1), (2, 33, 0),
        (3, 34, 1), (4, 34, 2), (5, 34, 3),
        (6, 35, 1), (7, 35, 2),
        (8, 9, 0), (9, 9, 2),
        (10, 20, 1), (11, 20, 2),
        (12, 26, 1), (13, 26, 1), (14, 25, 0),
    ]

    /// Build one source page from the corrected stage packet and guarded
    /// sidecars.  The source setup words are decoded here, rather than copied
    /// from a guessed object summary, so door q16 parameters and guard IDs
    /// retain their original record offsets and hashes.
    static func make(
        stagePacket: GoldenEyeStageScenePacket,
        dependencies: GoldenEyeStageSetupDependencyCatalogV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6,
        demoID: UInt8,
        slotNumber: UInt32
    ) throws -> Self {
        guard let route = route.first(where: { $0.demo == demoID }) else {
            throw Error.routeMismatch(demoID, stagePacket.stageID)
        }
        guard route.stage == stagePacket.stageID else {
            throw Error.routeMismatch(demoID, stagePacket.stageID)
        }
        guard stagePacket.setup.stageID == stagePacket.stageID else {
            throw Error.stageMismatch(stagePacket.stageID, stagePacket.setup.stageID)
        }
        guard let setupResource = stagePacket.resources.first(where: { $0.kind == .setup }) else {
            throw Error.missingSetupPayload(stagePacket.stageID)
        }
        let setupData = setupResource.payload
        let animationData = loadAnimationTableData(root: visibleDependencies.rootURL)
        let animationEntries = loadAnimationTableEntries(root: visibleDependencies.rootURL)
        let stanData = stagePacket.resources.first(where: { $0.kind == .stan })?.payload
        var missing = [String]()
        var guards = [GEGuardDoorOwnerGuardSourceV6]()
        var doors = [GEGuardDoorOwnerDoorSourceV6]()
        var poses = [GESourceAnimationPoseV6]()
        let attachments = [GEGuardDoorOwnerAttachmentV6]()
        let stage = stagePacket.stageID

        let objectGuardRows = stagePacket.setup.objects.filter { $0.type == 9 }
        let objectDoorRows = stagePacket.setup.objects.filter { $0.type == 1 }
        guard objectGuardRows.count <= Int(GE_GUARD_DOOR_OWNER_V6_MAX_GUARDS) else {
            throw Error.capacity(stage, "guards", objectGuardRows.count)
        }
        guard objectDoorRows.count <= Int(GE_GUARD_DOOR_OWNER_V6_MAX_DOORS) else {
            throw Error.capacity(stage, "doors", objectDoorRows.count)
        }

        for object in objectGuardRows {
            let result = try makeGuard(
                object: object, setup: stagePacket.setup, setupData: setupData,
                dependencies: dependencies, sidecars: sidecars,
                visibleDependencies: visibleDependencies, stageID: stage,
                animationData: animationData,
                animationEntries: animationEntries,
                stanData: stanData,
                poses: &poses,
                missing: &missing
            )
            guards.append(result)
        }
        for object in objectDoorRows {
            let result = try makeDoor(
                object: object, setup: stagePacket.setup, setupData: setupData,
                dependencies: dependencies, sidecars: sidecars,
                visibleDependencies: visibleDependencies, stageID: stage,
                missing: &missing
            )
            doors.append(result)
        }

        let sourceHash = stagePacket.setup.sourceHash
        let packetHash = stagePacket.packetHash
        let modelDependencyHash = mixHashes(
            [sourceHash, packetHash] + guards.flatMap { [$0.source_hash, UInt64($0.body_model_handle)] } +
                doors.flatMap { [$0.source_hash64, UInt64($0.model_handle)] }
        )
        let animationHash = mixHashes([sourceHash, UInt64(poses.count), UInt64(attachments.count)])
        let boundTransformsReady = !doors.isEmpty && doors.allSatisfy { hasMatrix($0.base_transform_q16) }
        let modelReady = guards.allSatisfy {
            $0.body_model_handle != 0 && ($0.head_id == UInt32.max || $0.head_model_handle != 0)
        } && doors.allSatisfy { $0.model_handle != 0 }
        if !boundTransformsReady { missing.append("door_bound_pad_transform") }
        if !modelReady { missing.append("guard_door_model_handles") }
        let hasAI = guards.allSatisfy { $0.ai_state != UInt32.max }
        let hasPoses = !poses.isEmpty && guards.allSatisfy { $0.animation_id != 0 && $0.pose_count != 0 }
        let hasSourceRender = guards.allSatisfy {
            $0.raw_render_mode != UInt32.max && $0.raw_other_mode_h != UInt32.max
        }
        if !hasSourceRender && !guards.isEmpty {
            missing.append("guard_render_context.source_model_render_mode")
        }
        if !dependencies.isReady { missing.append("setup_model_dependency_catalog") }
        if !sidecars.isComplete { missing.append("complete_stage_model_sidecars") }
        if !visibleDependencies.isComplete { missing.append("ramrom_visible_dependency_catalog") }

        let deduplicatedMissing = Array(Set(missing)).sorted()
        var setup = GEGuardDoorOwnerSetupV6()
        setup.header.abi_version = GE_NATIVE_ABI_VERSION
        setup.header.struct_size = UInt32(MemoryLayout<GEGuardDoorOwnerSetupV6>.size)
        setup.record_version = UInt32(GE_GUARD_DOOR_OWNER_V6_RECORD_VERSION)
        setup.demo_id = UInt32(demoID)
        setup.stage_id = stage
        setup.source_bytes = setupResource.decodedBytes
        setup.guard_count = UInt32(guards.count)
        setup.door_count = UInt32(doors.count)
        setup.room_count = UInt32(stagePacket.background.roomCount)
        setup.portal_count = UInt32(stagePacket.setup.portals.count)
        setup.source_hash = sourceHash
        setup.packet_hash = packetHash
        setup.model_dependency_hash = modelDependencyHash
        setup.animation_source_hash = animationHash
        setup.flags = 0
        if hasPoses { setup.flags |= GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_POSES }
        if hasAI { setup.flags |= GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_AI }
        if boundTransformsReady { setup.flags |= GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_BOUND_PAD_TRANSFORMS }
        if modelReady { setup.flags |= GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_MODEL_DEPENDENCIES }
        if deduplicatedMissing.isEmpty { setup.flags |= GE_GUARD_DOOR_OWNER_V6_SETUP_FLAG_SOURCE_READY }

        var pageHash = mixHashes([
            UInt64(stage), UInt64(demoID), UInt64(slotNumber), sourceHash, packetHash,
            modelDependencyHash, animationHash, UInt64(guards.count), UInt64(doors.count),
            UInt64(poses.count), UInt64(attachments.count),
        ])
        for guardRow in guards { pageHash = mixHashes([pageHash, guardRow.source_hash, guardRow.source_event_hash]) }
        for door in doors { pageHash = mixHashes([pageHash, door.source_hash64, door.source_event_hash]) }

        return Self(
            stageID: stage, stageName: stagePacket.stageName, demoID: demoID, slotNumber: slotNumber,
            setup: setup, guards: guards, doors: doors, poses: poses, attachments: attachments,
            sourceReady: deduplicatedMissing.isEmpty, missingFields: deduplicatedMissing,
            sourceHash: sourceHash, packetHash: packetHash, modelDependencyHash: modelDependencyHash,
            pageHash: pageHash
        )
    }

    static func makeAll(
        packets: [GoldenEyeStageScenePacket],
        dependencies: GoldenEyeStageSetupDependencyCatalogV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6
    ) throws -> [Self] {
        let byStage = Dictionary(uniqueKeysWithValues: packets.map { ($0.stageID, $0) })
        return try route.map { route in
            guard let packet = byStage[route.stage] else { throw Error.stageMismatch(route.stage, 0) }
            return try make(
                stagePacket: packet, dependencies: dependencies, sidecars: sidecars,
                visibleDependencies: visibleDependencies, demoID: route.demo, slotNumber: route.slot
            )
        }
    }

    public static func routeTable() -> [(demo: UInt8, stage: UInt32, slot: UInt32)] { route }

    /// Compile the guarded initial pages into the portable owner state.  The
    /// large C state is returned by value so callers can place it in their own
    /// owner-thread storage; this builder never retains a pointer.
    static func makeOwnerState(
        from pages: Self,
        rngSeed: UInt64
    ) throws -> GEGuardDoorOwnerStateV6 {
        guard pages.sourceReady else {
            throw Error.malformedSetup(pages.stageID, pages.missingFields.joined(separator: ","))
        }
        var state = GEGuardDoorOwnerStateV6()
        var event = GEGuardDoorOwnerEventV6()
        let status: UInt32 = pages.guards.withUnsafeBufferPointer { guardBuffer in
            pages.doors.withUnsafeBufferPointer { doorBuffer in
                pages.poses.withUnsafeBufferPointer { poseBuffer in
                    pages.attachments.withUnsafeBufferPointer { attachmentBuffer in
                        withUnsafePointer(to: pages.setup) { setupPointer in
                            ge_guard_door_owner_v6_begin(
                                setupPointer, guardBuffer.baseAddress, UInt32(guardBuffer.count),
                                doorBuffer.baseAddress, UInt32(doorBuffer.count),
                                poseBuffer.baseAddress, UInt32(poseBuffer.count),
                                attachmentBuffer.baseAddress, UInt32(attachmentBuffer.count),
                                rngSeed, &state, &event
                            )
                        }
                    }
                }
            }
        }
        guard status == UInt32(GE_STATUS_OK) else {
            throw Error.malformedSetup(pages.stageID, "owner status " + String(status))
        }
        return state
    }

    private static func makeGuard(
        object: GoldenEyeStageSetupObjectPacket,
        setup: GoldenEyeStageSetupPacket,
        setupData: Data,
        dependencies: GoldenEyeStageSetupDependencyCatalogV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6,
        stageID: UInt32,
        animationData: Data?,
        animationEntries: Data?,
        stanData: Data?,
        poses: inout [GESourceAnimationPoseV6],
        missing: inout [String]
    ) throws -> GEGuardDoorOwnerGuardSourceV6 {
        let offset = Int(object.sourceRecordOffset)
        guard let first = be32(setupData, offset), let second = be32(setupData, offset + 4),
              let bodyAI = be32(setupData, offset + 8), let preset = be32(setupData, offset + 12),
              let healthReaction = be32(setupData, offset + 16), let bitflagsHead = be32(setupData, offset + 20) else {
            throw Error.malformedSetup(stageID, "guard record " + String(object.sourceRecordOffset))
        }
        let bodyID = bodyAI >> 16
        let headWord = bitflagsHead & 0xffff
        let headID = headWord == 0xffff ? UInt32.max : headWord
        let bodyModel = modelHandle(
            kind: "character", index: bodyID, stageID: stageID,
            dependencies: dependencies, sidecars: sidecars,
            visibleDependencies: visibleDependencies, missing: &missing
        )
        let headModel: UInt32
        if headID == UInt32.max {
            headModel = 0
            missing.append("guard_head_selection_gender.object" + String(object.index))
        } else {
            headModel = modelHandle(
                kind: "character", index: headID, stageID: stageID,
                dependencies: dependencies, sidecars: sidecars,
                visibleDependencies: visibleDependencies, visibleCategory: "heads", missing: &missing
            )
        }
        let aiAnalysis = GoldenEyeRamRomGuardAISourceV6.analyze(
            setupData: setupData, aiLists: setup.aiLists, listID: bodyAI & 0xffff
        )
        var animationHash = aiAnalysis.sourceHash
        if let malformed = aiAnalysis.malformed {
            missing.append("guard_ai_source_" + malformed)
            if malformed.contains("is not in setup") {
                let globalID = bodyAI & 0xffff
                missing.append("guard_ai_list_" + String(globalID) + ".source_page")
                if let row = GoldenEyeRamRomGuardAISourceV6.canonicalGlobalSourceRow(for: globalID) {
                    missing.append("guard_ai_list_" + String(globalID) + ".canonical_row." + row.replacingOccurrences(of: "/", with: "_"))
                    missing.append("guard_ai_list_" + String(globalID) + ".prepared_visible_dependency_row")
                }
            }
        }
        for opcode in aiAnalysis.runtimeOpcodes {
            missing.append("guard_ai_runtime_opcode_0x" + String(opcode, radix: 16))
        }
        let matrix = padMatrix(setup: setup, padIndex: second & 0xffff)
        if matrix.isEmpty { missing.append("guard_pad_transform.object" + String(object.index)) }
        let sourceFogColor = stanColor(stanData: stanData, positionMatrix: matrix)
        if sourceFogColor == nil {
            missing.append("guard_render_context.fog_colour.source_stan_tile.object" + String(object.index))
        }
        var value = GEGuardDoorOwnerGuardSourceV6()
        value.header.abi_version = GE_NATIVE_ABI_VERSION
        value.header.struct_size = UInt32(MemoryLayout<GEGuardDoorOwnerGuardSourceV6>.size)
        value.record_version = UInt32(GE_GUARD_DOOR_OWNER_V6_RECORD_VERSION)
        value.source_record_offset = object.sourceRecordOffset
        value.guard_id = (second >> 16) & 0xffff
        value.chr_num = value.guard_id
        value.pad_id = second & 0xffff
        value.body_id = bodyID
        value.head_id = headID
        value.weapon_id = UInt32.max
        value.ai_list_id = bodyAI & 0xffff
        value.preset = preset >> 16
        value.chr_preset = preset & 0xffff
        value.health = healthReaction >> 16
        value.health_current = value.health
        value.reaction_time = healthReaction & 0xffff
        value.source_bitflags = bitflagsHead >> 16
        value.flags = mapGuardFlags(value.source_bitflags)
        value.body_model_handle = bodyModel
        value.head_model_handle = headModel
        value.weapon_model_handle = 0
        value.skeleton_handle = 0
        value.animation_id = 0
        value.animation_frame_count = 0
        value.animation_frame_q16 = 0
        value.animation_next_frame_q16 = 0
        value.animation_speed_q16 = 0
        value.animation_merge_q16 = 0
        value.animation_flip_flags = 0
        let selectedAnimation = aiAnalysis.animationChoices.first ?? (
            aiAnalysis.ended && aiAnalysis.malformed == nil
                ? GoldenEyeRamRomGuardAISourceV6.AnimationChoice(
                    animationID: 0, tableOffset: 0x01c, startFrame: 0,
                    endFrame: -1, flags: 0, interpolation60: 0, sourceOffset: 0
                )
                : nil
        )
        if let animation = selectedAnimation {
            value.animation_id = animation.animationID
            value.animation_flip_flags = animation.flags
            value.animation_frame_q16 = max(0, animation.startFrame) << 16
            value.animation_next_frame_q16 = value.animation_frame_q16
            value.animation_merge_q16 = Int32(animation.interpolation60) << 16
            if animation.tableOffset != UInt32.max,
               let data = animationData,
               let frameCount = be16(data, Int(animation.tableOffset) + 4) {
                value.animation_frame_count = UInt32(frameCount)
                value.animation_next_frame_q16 = value.animation_frame_q16
                value.animation_speed_q16 = 32_768
                value.animation_merge_q16 = 65_536
                value.flags |= (data[Int(animation.tableOffset) + 7] & 1) != 0
                    ? GE_GUARD_DOOR_OWNER_V6_GUARD_FLAG_LOOP_ANIMATION : 0
                animationHash = fnvData(data)
                if let entries = animationEntries,
                   let bodySourceModel = sidecars.models.first(where: { $0.value.header.modelHandle == bodyModel })?.value {
                    let decoded = GoldenEyeRamRomGuardPoseSourceV6.decode(
                        model: bodySourceModel,
                        modelHandle: bodyModel, animationID: animation.animationID,
                        frame: UInt32(max(0, animation.startFrame)),
                        flip: (animation.flags & 1) != 0,
                        animationData: data, animationEntries: entries
                    )
                    if let poseMissing = decoded.missing {
                        missing.append(poseMissing)
                    } else {
                        value.skeleton_handle = decoded.skeletonHandle
                        value.pose_first = UInt32(poses.count)
                        value.pose_count = UInt32(decoded.poses.count)
                        value.pose_next_first = value.pose_first
                        value.pose_next_count = value.pose_count
                        value.pose_hash = decoded.poseHash
                        value.animation_hash = decoded.animationHash
                        poses.append(contentsOf: decoded.poses)
                    }
                } else {
                    missing.append("guard_pose_decoder.animationtable_entries")
                }
            } else {
                missing.append("guard_animationtable_payload.animationID" + String(animation.animationID))
            }
        } else {
            missing.append("guard_animation_source_commands")
            missing.append("guard_pose_decoder.animationtable.ai_list_" + String(value.ai_list_id) + ".initial_animation")
            if aiAnalysis.malformed?.contains("is not in setup") == true {
                missing.append("guard_pose_decoder.ai_list_" + String(value.ai_list_id) + ".source_page")
            }
        }
        value.action_state = aiAnalysis.initialStateReady ? 1 : UInt32.max
        value.death_state = 0
        value.visibility_state = matrix.isEmpty ? 0 : 1
        value.ai_state = aiAnalysis.initialStateReady ? bodyAI & 0xffff : UInt32.max
        // chrRenderProp supplies the Type-4 character state before traversing
        // the model graph.  These words are the source macros from
        // modelApplyRenderModeType4 (primary, opaque, Z-buffered).  The
        // per-guard fog colour is intentionally left unavailable until the
        // source tile-shading owner is present; no neutral colour is invented.
        value.render_flags = 1
        value.zbuffer_mode = 1
        value.environment_rgba = 0x5a00_0000
        value.fog_rgba = sourceFogColor ?? UInt32.max
        value.raw_other_mode_h = 0x0010_0000
        value.raw_other_mode_l = 0
        value.raw_render_mode = 0xc411_2078
        if Self.bodyIsMale(bodyID) { value.flags |= GE_GUARD_DOOR_OWNER_V6_GUARD_FLAG_MALE }
        if headID == UInt32.max {
            let candidates = Self.bodyIsMale(bodyID) ? Self.maleHeadIDs : Self.femaleHeadIDs
            for candidateID in candidates.prefix(Int(GE_GUARD_DOOR_OWNER_V6_MAX_CHOICES)) {
                guard value.head_choice_count < GE_GUARD_DOOR_OWNER_V6_MAX_CHOICES else { break }
                let handle = modelHandle(
                    kind: "character", index: candidateID, stageID: stageID,
                    dependencies: dependencies, sidecars: sidecars,
                    visibleDependencies: visibleDependencies, visibleCategory: "heads", missing: &missing
                )
                guard handle != 0 else { continue }
                let choiceIndex = Int(value.head_choice_count)
                withUnsafeMutableBytes(of: &value.head_choices) { raw in
                    let words = raw.bindMemory(to: UInt32.self)
                    let base = choiceIndex * 4
                    words[base] = candidateID; words[base + 1] = handle; words[base + 2] = handle; words[base + 3] = 0
                }
                value.head_choice_count += 1
            }
            if value.head_choice_count == 0 {
                missing.append("guard_head_choice_payload.object" + String(object.index))
            }
        }
        for weapon in aiAnalysis.weaponChoices.prefix(Int(GE_GUARD_DOOR_OWNER_V6_MAX_CHOICES)) {
            let handle = modelHandle(
                kind: "prop", index: weapon.propID, stageID: stageID,
                dependencies: dependencies, sidecars: sidecars,
                visibleDependencies: visibleDependencies, visibleCategory: "props", missing: &missing
            )
            guard handle != 0, value.weapon_choice_count < GE_GUARD_DOOR_OWNER_V6_MAX_CHOICES else { continue }
            let choiceIndex = Int(value.weapon_choice_count)
            withUnsafeMutableBytes(of: &value.weapon_choices) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                let base = choiceIndex * 4
                words[base] = weapon.itemID; words[base + 1] = handle; words[base + 2] = weapon.propID; words[base + 3] = weapon.propFlags
            }
            value.weapon_choice_count += 1
        }
        if let assignedWeapon = setup.objects.first(where: {
            $0.type == 8 && ($0.flags1 & 0x0000_4000) != 0 && $0.key1 == value.chr_num
        }), let weaponWord = be32(setupData, Int(assignedWeapon.sourceRecordOffset) + 0x80) {
            let handle = modelHandle(
                kind: "prop", index: assignedWeapon.key0, stageID: stageID,
                dependencies: dependencies, sidecars: sidecars,
                visibleDependencies: visibleDependencies, visibleCategory: "props", missing: &missing
            )
            if handle != 0 {
                value.weapon_id = weaponWord >> 24
                value.weapon_model_handle = handle
                value.weapon_choice_count = max(value.weapon_choice_count, 1)
                withUnsafeMutableBytes(of: &value.weapon_choices) { raw in
                    let words = raw.bindMemory(to: UInt32.self)
                    words[0] = value.weapon_id; words[1] = handle; words[2] = assignedWeapon.key0; words[3] = assignedWeapon.flags1
                }
            }
        }
        if value.weapon_choice_count != 0 && value.weapon_model_handle == 0 {
            value.weapon_id = UInt32.max
        }
        let weaponRequiredOpcodes: Set<UInt32> = [17, 18, 19, 20, 21, 22, 26]
        if value.weapon_choice_count == 0,
           !weaponRequiredOpcodes.isDisjoint(with: Set(aiAnalysis.runtimeOpcodes)) {
            let objectEvidence = "guard_weapon_source_selection.stage_" + stageName(stageID) +
                ".object" + String(object.index) +
                ".setup_offset0x" + String(object.sourceRecordOffset, radix: 16) +
                ".assigned_type8_source_row"
            missing.append(objectEvidence)
            if aiAnalysis.malformed?.contains("is not in setup") == true {
                missing.append("guard_weapon_source_ai_list_" + String(value.ai_list_id) + ".source_page")
            }
        }
        setTuple(&value.scale_q16, values: [65536, 65536, 65536])
        setTuple(&value.world_transform_q16, values: matrix)
        setTuple(&value.position_q16, values: matrix.count == 16 ? [matrix[12], matrix[13], matrix[14]] : [0, 0, 0])
        setTuple(&value.next_position_q16, values: matrix.count == 16 ? [matrix[12], matrix[13], matrix[14]] : [0, 0, 0])
        if value.pose_count == 0 {
            value.pose_first = 0; value.pose_next_first = 0; value.pose_next_count = 0
        }
        value.attachment_first = 0; value.attachment_count = 0
        value.source_hash = mixHashes([UInt64(object.sourceRecordOffset), UInt64(first), UInt64(bodyID)])
        if value.animation_hash == 0 { value.animation_hash = animationHash }
        value.source_event_hash = mixHashes([
            value.source_hash, UInt64(value.source_bitflags), UInt64(value.render_flags),
            UInt64(value.zbuffer_mode), UInt64(value.environment_rgba),
            UInt64(value.raw_other_mode_h), UInt64(value.raw_other_mode_l),
            UInt64(value.raw_render_mode), value.animation_hash, value.pose_hash,
        ])
        return value
    }

    private static func makeDoor(
        object: GoldenEyeStageSetupObjectPacket,
        setup: GoldenEyeStageSetupPacket,
        setupData: Data,
        dependencies: GoldenEyeStageSetupDependencyCatalogV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6,
        stageID: UInt32,
        missing: inout [String]
    ) throws -> GEGuardDoorOwnerDoorSourceV6 {
        let offset = Int(object.sourceRecordOffset)
        guard let second = be32(setupData, offset + 4),
              let flags = be32(setupData, offset + 8), let flags2 = be32(setupData, offset + 12),
              let maxFrac = be32(setupData, offset + 0x84), let perim = be32(setupData, offset + 0x88),
              let accel = be32(setupData, offset + 0x8c), let decel = be32(setupData, offset + 0x90),
              let maxSpeed = be32(setupData, offset + 0x94), let doorMode = be32(setupData, offset + 0x98),
              let keyFlags = be32(setupData, offset + 0x9c), let autoClose = be32(setupData, offset + 0xa0),
              let portal = be32(setupData, offset + 0xf0) else {
            throw Error.malformedSetup(stageID, "door record " + String(object.sourceRecordOffset))
        }
        let modelHandleValue = modelHandle(
            kind: "prop", index: object.key0, stageID: stageID,
            dependencies: dependencies, sidecars: sidecars,
            visibleDependencies: visibleDependencies, missing: &missing
        )
        let boundPad = setup.boundPads.first(where: { $0.index == (second & 0xffff) })
        if boundPad == nil { missing.append("door_bound_pad.object" + String(object.index)) }
        let modelValue = sidecars.models.values.first(where: { $0.header.modelHandle == modelHandleValue })
        let bounds = modelValue.flatMap(modelBounds)
        if bounds == nil { missing.append("door_model_bounds.object" + String(object.index)) }
        let transform = doorTransform(boundPad: boundPad, modelBounds: bounds)
        if transform.isEmpty { missing.append("door_transform.object" + String(object.index)) }
        let movement = doorMovement(boundPad: boundPad, doorType: doorMode & 0xffff)
        if movement.isEmpty { missing.append("door_displacement.object" + String(object.index)) }
        let center = doorCenter(boundPad: boundPad)
        if center.isEmpty { missing.append("door_center.object" + String(object.index)) }
        var value = GEGuardDoorOwnerDoorSourceV6()
        value.header.abi_version = GE_NATIVE_ABI_VERSION
        value.header.struct_size = UInt32(MemoryLayout<GEGuardDoorOwnerDoorSourceV6>.size)
        value.record_version = UInt32(GE_GUARD_DOOR_OWNER_V6_RECORD_VERSION)
        value.source_record_offset = object.sourceRecordOffset
        value.door_id = object.index + 1
        value.object_id = object.key0
        value.pad_id = second & 0xffff
        value.source_flags = flags
        value.source_flags2 = flags2
        value.door_flags = doorMode >> 16
        value.door_type = doorMode & 0xffff
        value.key_flags = keyFlags
        value.auto_close_frames = autoClose
        value.portal_number = portal
        value.open_state = GE_GUARD_DOOR_OWNER_V6_DOOR_STATE_STATIONARY
        value.visibility_state = transform.isEmpty ? 0 : 1
        value.model_handle = modelHandleValue
        value.max_frac_q16 = Int32(bitPattern: maxFrac)
        value.perim_frac_q16 = Int32(bitPattern: perim)
        value.accel_q16 = Int32(bitPattern: accel)
        value.decel_q16 = Int32(bitPattern: decel)
        value.max_speed_q16 = Int32(bitPattern: maxSpeed)
        setTuple(&value.frac_q16, values: movement)
        setTuple(&value.runtime_position_q16, values: center)
        setTuple(&value.base_transform_q16, values: transform)
        let openByDefault = (flags & 0x8000_0000) != 0
        value.open_position_q16 = openByDefault ? value.max_frac_q16 : 0
        value.next_open_position_q16 = value.open_position_q16
        value.speed_q16 = 0; value.next_speed_q16 = 0
        value.collision_bottom_q16 = center.isEmpty ? 0 : center[1]
        value.collision_top_q16 = center.isEmpty ? 0 : center[1]
        value.portal_active = openByDefault ? 1 : 0
        value.source_hash = UInt32(truncatingIfNeeded: mixHashes([UInt64(object.sourceRecordOffset), UInt64(firstWord(object, setupData) ?? 0)]))
        value.source_hash64 = mixHashes([UInt64(object.sourceRecordOffset), UInt64(modelHandleValue), UInt64(doorMode)])
        value.source_event_hash = mixHashes([value.source_hash64, UInt64(value.portal_number), UInt64(value.open_state)])
        if (flags & 0x1000_0000) != 0 && portal == UInt32.max { missing.append("door_portal_mapping.object" + String(object.index)) }
        return value
    }

    private static func modelHandle(
        kind: String, index: UInt32, stageID: UInt32,
        dependencies: GoldenEyeStageSetupDependencyCatalogV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6,
        visibleCategory: String? = nil,
        missing: inout [String]
    ) -> UInt32 {
        let category = visibleCategory ?? (kind == "character" ? "guards" : "doors")
        if !visibleDependencies.dependencies.contains(where: {
            $0.category == category && $0.modelIndex == index && $0.stages.contains(stageName(stageID))
        }) {
            missing.append(kind + "_visible_dependency_" + String(index))
        }
        if let dependency = dependencies.dependency(kind: kind, modelIndex: index) {
            let name = "stage_" + kind + "_" + String(format: "%03u", dependency.modelIndex) + "_" + dependency.modelName
            if let model = sidecars.models[name] { return model.header.modelHandle }
        }
        let prefix = "stage_" + kind + "_" + String(format: "%03u", index) + "_"
        if let model = sidecars.models.first(where: { $0.key.hasPrefix(prefix) })?.value {
            return model.header.modelHandle
        }
        missing.append(kind + "_model_handle_" + String(index))
        return 0
    }

    private static func modelBounds(_ model: GoldenEyeSourceModelV6) -> (min: [Double], max: [Double])? {
        guard !model.vertices.isEmpty else { return nil }
        let xs = model.vertices.map { Double($0.x) }, ys = model.vertices.map { Double($0.y) }, zs = model.vertices.map { Double($0.z) }
        let minValues = [xs.min()!, ys.min()!, zs.min()!]
        let maxValues = [xs.max()!, ys.max()!, zs.max()!]
        guard maxValues[0] > minValues[0], maxValues[1] > minValues[1], maxValues[2] > minValues[2] else { return nil }
        return (minValues, maxValues)
    }

    private static func doorTransform(
        boundPad: GoldenEyeStageSetupBoundPadPacket?,
        modelBounds: (min: [Double], max: [Double])?
    ) -> [Int32] {
        guard let pad = boundPad, let bounds = modelBounds else { return [] }
        let xScale = (float(pad.bounds.d) - float(pad.bounds.c)) / (bounds.max[0] - bounds.min[0])
        let yScale = (float(pad.bounds.f) - float(pad.bounds.e)) / (bounds.max[1] - bounds.min[1])
        let zScale = (float(pad.bounds.b) - float(pad.bounds.a)) / (bounds.max[2] - bounds.min[2])
        guard xScale.isFinite, yScale.isFinite, zScale.isFinite,
              abs(xScale) > 0.000001, abs(yScale) > 0.000001, abs(zScale) > 0.000001 else { return [] }
        let halfPi = Double.pi / 2
        let c = cos(halfPi), s = sin(halfPi)
        let matrix: [Double] = [
            xScale, 0, 0, 0,
            0, c * yScale, s * yScale, 0,
            0, -s * zScale, c * zScale, 0,
            0, 0, 0, 1,
        ]
        return matrix.map { q16($0) }
    }

    private static func doorMovement(
        boundPad: GoldenEyeStageSetupBoundPadPacket?, doorType: UInt32
    ) -> [Int32] {
        guard let pad = boundPad, let up = vector(pad.up), let look = vector(pad.look) else { return [] }
        let c = float(pad.bounds.c), d = float(pad.bounds.d), e = float(pad.bounds.e), f = float(pad.bounds.f)
        let delta = doorType == GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_VERTICAL || doorType == GE_GUARD_DOOR_OWNER_V6_DOOR_TYPE_FALLAWAY
            ? look.map { $0 * (f - e) }
            : up.map { $0 * (c - d) }
        return delta.map(q16)
    }

    private static func doorCenter(boundPad: GoldenEyeStageSetupBoundPadPacket?) -> [Int32] {
        guard let pad = boundPad, let position = vector(pad.position), let up = vector(pad.up), let look = vector(pad.look) else { return [] }
        let normalRaw = [up[1] * look[2] - up[2] * look[1], up[2] * look[0] - up[0] * look[2], up[0] * look[1] - up[1] * look[0]]
        let length = sqrt(normalRaw.reduce(0) { $0 + $1 * $1 })
        guard length.isFinite, length > 0 else { return [] }
        let normal = normalRaw.map { $0 / length }
        let a = float(pad.bounds.a), b = float(pad.bounds.b), c = float(pad.bounds.c), d = float(pad.bounds.d), e = float(pad.bounds.e), f = float(pad.bounds.f)
        let center = (0..<3).map { index in
            position[index] + ((a + b) * normal[index] + (c + d) * up[index] + (e + f) * look[index]) * 0.5
        }
        return center.map(q16)
    }

    private static func padMatrix(setup: GoldenEyeStageSetupPacket, padIndex: UInt32) -> [Int32] {
        if let pad = setup.pads.first(where: { $0.index == padIndex }) { return matrix(position: pad.position, up: pad.up, look: pad.look) }
        if let pad = setup.boundPads.first(where: { $0.index == padIndex }) { return matrix(position: pad.position, up: pad.up, look: pad.look) }
        return []
    }

    private static func matrix(position: GoldenEyeStageSetupVectorBits, up: GoldenEyeStageSetupVectorBits, look: GoldenEyeStageSetupVectorBits) -> [Int32] {
        guard let p = vector(position), let u = vector(up), let l = vector(look) else { return [] }
        let basis = [-l[0], -l[1], -l[2]]
        let basisLength = sqrt(basis.reduce(0) { $0 + $1 * $1 }); guard basisLength > 0 else { return [] }
        let bn = basis.map { $0 / basisLength }
        let rightX = u[1] * bn[2] - u[2] * bn[1]
        let rightY = u[2] * bn[0] - u[0] * bn[2]
        let rightZ = u[0] * bn[1] - u[1] * bn[0]
        let rightRaw = [rightX, rightY, rightZ]
        let rightLength = sqrt(rightRaw.reduce(0) { $0 + $1 * $1 }); guard rightLength > 0 else { return [] }
        let right = rightRaw.map { $0 / rightLength }
        let correctedUpX = bn[1] * right[2] - bn[2] * right[1]
        let correctedUpY = bn[2] * right[0] - bn[0] * right[2]
        let correctedUpZ = bn[0] * right[1] - bn[1] * right[0]
        let correctedUpRaw = [correctedUpX, correctedUpY, correctedUpZ]
        let upLength = sqrt(correctedUpRaw.reduce(0) { $0 + $1 * $1 }); guard upLength > 0 else { return [] }
        let correctedUp = correctedUpRaw.map { $0 / upLength }
        // Source matrices are column-major 4x4 values. Keep the homogeneous
        // zero in each basis column; the previous compact 3+3+3+4 form
        // could not carry a valid position into the render/fog owner.
        return [
            right[0], right[1], right[2], 0,
            correctedUp[0], correctedUp[1], correctedUp[2], 0,
            bn[0], bn[1], bn[2], 0,
            p[0], p[1], p[2], 1,
        ].map(q16)
    }

    /// Reproduce copy_tile_RGB_as_24bit + set_color_shading_from_tile for the
    /// source STAN tile containing the guard's authored pad position.  The
    /// decoded STAN bytes remain borrowed for this call; only the packed fog
    /// colour crosses into the value page.
    private static func stanColor(stanData: Data?, positionMatrix: [Int32]) -> UInt32? {
        guard let data = stanData, positionMatrix.count == 16,
              data.count >= 8 else { return nil }
        let position = (
            x: Double(positionMatrix[12]) / 65_536.0,
            z: Double(positionMatrix[14]) / 65_536.0
        )
        guard position.x.isFinite, position.z.isFinite,
              let firstOffset = be32(data, 4), firstOffset >= 8,
              Int(firstOffset) < data.count else { return nil }
        let tileSizes = [0x20, 0x20, 0x20, 0x20, 0x28, 0x30, 0x38, 0x40,
                         0x48, 0x50, 0x58, 0]
        var offset = Int(firstOffset)
        var inspected = 0
        while offset + 8 <= data.count && inspected < 1_000_000 {
            guard let idRoom = be32(data, offset), idRoom != 0,
                  let mid = be16(data, offset + 4),
                  let tail = be16(data, offset + 6) else { return nil }
            let pointCount = Int((tail >> 12) & 0x000f)
            guard pointCount < tileSizes.count, tileSizes[pointCount] != 0,
                  offset <= data.count - tileSizes[pointCount],
                  offset <= data.count - 8 - pointCount * 8 else { return nil }
            var points: [(Double, Double)] = []
            points.reserveCapacity(pointCount)
            for point in 0..<pointCount {
                let pointOffset = offset + 8 + point * 8
                guard let x = be16(data, pointOffset), let z = be16(data, pointOffset + 4) else {
                    return nil
                }
                points.append((Double(Int16(bitPattern: x)), Double(Int16(bitPattern: z))))
            }
            if pointInsidePolygon(position, points: points) {
                return shadeColor(mid: mid)
            }
            offset += tileSizes[pointCount]
            inspected += 1
        }
        return nil
    }

    private static func pointInsidePolygon(
        _ position: (x: Double, z: Double), points: [(x: Double, z: Double)]
    ) -> Bool {
        guard points.count >= 3 else { return false }
        var inside = false
        var previous = points.count - 1
        for current in points.indices {
            let a = points[current], b = points[previous]
            let crosses = (a.z > position.z) != (b.z > position.z)
            if crosses {
                let denominator = b.z - a.z
                if denominator != 0 {
                    let xAtZ = (b.x - a.x) * (position.z - a.z) / denominator + a.x
                    if position.x < xAtZ { inside.toggle() }
                }
            }
            previous = current
        }
        return inside
    }

    private static func shadeColor(mid: UInt16) -> UInt32 {
        var color = [
            Int((mid >> 8) & 0x0f) * 0x11,
            Int((mid >> 4) & 0x0f) * 0x11,
            Int(mid & 0x0f) * 0x11,
        ]
        let luminance = (color[0] * 79 + color[1] * 156 + color[2] * 21) >> 8
        let alpha = Int((Double(max(0, 255 - luminance)) * 0.75).rounded(.towardZero))
        var maxIndex = 0
        var minIndex = 0
        var middleIndex = 0
        if color[1] > color[0] { maxIndex = 1 } else { minIndex = 1 }
        if color[2] > color[maxIndex] {
            middleIndex = maxIndex
            maxIndex = 2
        } else if color[2] > color[minIndex] {
            middleIndex = 2
        } else {
            middleIndex = minIndex
            minIndex = 2
        }
        if color[maxIndex] > 0 {
            let range = color[maxIndex] - color[minIndex]
            let middle = color[middleIndex] * range / color[maxIndex]
            color[minIndex] = 0
            color[middleIndex] = middle
            color[maxIndex] = range
        }
        return (UInt32(color[0] >> 1) << 24) |
            (UInt32(color[1] >> 1) << 16) |
            (UInt32(color[2] >> 1) << 8) |
            UInt32(max(0, min(255, alpha)))
    }

    private static func mapGuardFlags(_ bitflags: UInt32) -> UInt32 {
        var value: UInt32 = 0
        if bitflags & 4 != 0 { value |= GE_GUARD_DOOR_OWNER_V6_GUARD_FLAG_CLONE }
        if bitflags & 8 != 0 { value |= GE_GUARD_DOOR_OWNER_V6_GUARD_FLAG_INVINCIBLE }
        return value
    }

    private static let maleBodyIDs: Set<UInt32> = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 15, 17, 18, 19, 20, 21, 22, 23, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 41]
    private static let femaleBodyIDs: Set<UInt32> = [11, 14, 16, 26, 27, 28, 29, 40]
    private static let maleHeadIDs: [UInt32] = [57, 54, 55, 62, 59, 56, 58, 53, 52, 51, 42, 43, 44, 45, 46, 47, 48, 49, 50, 63, 64, 65, 66, 67, 68]
    private static let femaleHeadIDs: [UInt32] = [70, 71, 72, 73]

    private static func bodyIsMale(_ bodyID: UInt32) -> Bool {
        maleBodyIDs.contains(bodyID)
    }

    private static func firstWord(_ object: GoldenEyeStageSetupObjectPacket, _ data: Data) -> UInt32? {
        be32(data, Int(object.sourceRecordOffset))
    }

    private static func stageName(_ id: UInt32) -> String {
        switch id { case 33: return "Dam"; case 34: return "Facility"; case 35: return "Runway"; case 9: return "Bunker I"; case 20: return "Silo"; case 26: return "Frigate"; case 25: return "Train"; default: return "" }
    }

    private static func vector(_ value: GoldenEyeStageSetupVectorBits) -> [Double]? {
        let values = [Float(bitPattern: value.x), Float(bitPattern: value.y), Float(bitPattern: value.z)].map(Double.init)
        return values.allSatisfy { $0.isFinite } ? values : nil
    }

    private static func float(_ bits: UInt32) -> Double { Double(Float(bitPattern: bits)) }
    private static func q16(_ value: Double) -> Int32 { Int32(clamping: Int64((value * 65_536).rounded(.toNearestOrAwayFromZero))) }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }

    private static func be16(_ data: Data, _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func loadAnimationTableData(root: URL) -> Data? {
        let manifestURL = root.appendingPathComponent(GoldenEyeRamRomVisibleDependencyCatalogV6.manifestFileName)
        guard let text = try? String(contentsOf: manifestURL, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            guard line.contains("source_path:assets/animationtable_data.bin") else { continue }
            let fields = line.split(separator: "|").reduce(into: [String: String]()) { result, field in
                let pair = field.split(separator: ":", maxSplits: 1).map(String.init)
                if pair.count == 2 { result[pair[0]] = pair[1] }
            }
            if let file = fields["decoded_file"], !file.hasPrefix("/"), !file.split(separator: "/").contains("..") {
                let url = root.appendingPathComponent(file).standardizedFileURL
                guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else { return nil }
                return try? Data(contentsOf: url, options: [.mappedIfSafe])
            }
        }
        return nil
    }

    private static func loadAnimationTableEntries(root: URL) -> Data? {
        let manifestURL = root.appendingPathComponent(GoldenEyeRamRomVisibleDependencyCatalogV6.manifestFileName)
        guard let text = try? String(contentsOf: manifestURL, encoding: .utf8) else { return nil }
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            guard line.contains("source_path:assets/animationtable_entries.bin") else { continue }
            let fields = line.split(separator: "|").reduce(into: [String: String]()) { result, field in
                let pair = field.split(separator: ":", maxSplits: 1).map(String.init)
                if pair.count == 2 { result[pair[0]] = pair[1] }
            }
            if let file = fields["decoded_file"], !file.hasPrefix("/"), !file.split(separator: "/").contains("..") {
                let url = root.appendingPathComponent(file).standardizedFileURL
                guard url.path.hasPrefix(root.standardizedFileURL.path + "/") else { return nil }
                return try? Data(contentsOf: url, options: [.mappedIfSafe])
            }
        }
        return nil
    }

    private static func fnvData(_ data: Data) -> UInt64 {
        data.reduce(UInt64(1_469_598_103_934_665_603)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    private static func setTuple<T>(_ destination: inout T, values: [Int32]) {
        withUnsafeMutableBytes(of: &destination) { raw in
            let typed = raw.bindMemory(to: Int32.self)
            for index in values.indices where index < typed.count { typed[index] = values[index] }
        }
    }

    private static func hasMatrix<T>(_ tuple: T) -> Bool {
        withUnsafeBytes(of: tuple) { raw in raw.bindMemory(to: Int32.self).contains { $0 != 0 } }
    }

    private static func mixHashes(_ values: [UInt64]) -> UInt64 {
        values.reduce(UInt64(1_469_598_103_934_665_603)) { hash, value in
            stride(from: 0, to: 64, by: 8).reduce(hash) { partial, shift in
                (partial ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
            }
        }
    }
}
