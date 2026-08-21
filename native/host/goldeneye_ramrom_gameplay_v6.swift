import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Source setup/model pages copied into the portable gameplay owner.  The
/// arrays are borrowed by the C begin call and then copied into its bounded
/// state; this Swift value never retains a ROM path, pointer, or Metal object.
public struct GoldenEyeRamRomGameplaySourcePagesV6: @unchecked Sendable {
    public let stageID: UInt32
    public let stageName: String
    public let demoMask: UInt32
    public let setup: GERamRomGameplaySetupV6
    public let entities: [GERamRomGameplayEntityV6]
    public let attachments: [GERamRomGameplayAttachmentV6]
    public let sourceReady: Bool
    public let missingFields: [String]
    public let slotNumber: UInt32?
    public let sourceHash: UInt64
    public let packetHash: UInt64

    public var entityCount: Int { entities.count }
    public var attachmentCount: Int { attachments.count }

    public enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case stageMismatch(UInt32, UInt32)
        case emptyPads(UInt32)
        case invalidMatrix(UInt32, Int)
        case invalidObject(UInt32, String)
        case capacity(UInt32, Int)

        public var description: String {
            switch self {
            case let .stageMismatch(expected, actual):
                return "gameplay source pages stage mismatch \(actual) != \(expected)"
            case let .emptyPads(stage): return "gameplay source pages have no source pad for stage \(stage)"
            case let .invalidMatrix(index, count):
                return "gameplay source object \(index) matrix has \(count) Q16 words"
            case let .invalidObject(index, detail):
                return "gameplay source object \(index) is invalid: \(detail)"
            case let .capacity(stage, count):
                return "gameplay source stage \(stage) has \(count) entities over bounded capacity"
            }
        }
    }

    private struct PadInfo {
        let index: UInt32
        let sourceRecordOffset: UInt32
        let position: [Int32]
        let up: [Int32]
        let look: [Int32]
    }

    private struct StanSummary {
        let tileCount: UInt32
        let roomCount: UInt32
        let worldMinQ16: [Int32]
        let worldMaxQ16: [Int32]
        let roomBounds: [UInt32: ([Int32], [Int32])]
        let tiles: [(UInt32, [[Int32]])]
        let scale: Double
        let boundsHash: UInt64

        func room(forWorldQ16 position: [Int32]) -> UInt32 {
            guard position.count == 3 else { return UInt32.max }
            let source = position.map { (Double($0) / 65_536.0) * scale }
            var selectedRoom = UInt32.max
            var selectedY = -Double.greatestFiniteMagnitude
            for (room, points) in tiles {
                guard points.count >= 3, Self.pointInsideXZ(points, x: source[0], z: source[2]) else {
                    continue
                }
                let floorY = Self.tilePlaneY(points, x: source[0], z: source[2])
                guard floorY.isFinite, floorY <= source[1] + 0.001, floorY > selectedY else { continue }
                selectedRoom = room
                selectedY = floorY
            }
            return selectedRoom
        }

        private static func pointInsideXZ(_ points: [[Int32]], x: Double, z: Double) -> Bool {
            var allPositive = true
            var allNegative = true
            for index in points.indices {
                let next = (index + 1) % points.count
                let ax = Double(points[index][0]); let az = Double(points[index][2])
                let bx = Double(points[next][0]); let bz = Double(points[next][2])
                let cross = (bx - ax) * (z - az) - (bz - az) * (x - ax)
                allPositive = allPositive && cross >= -0.001
                allNegative = allNegative && cross <= 0.001
            }
            return allPositive || allNegative
        }

        private static func tilePlaneY(_ points: [[Int32]], x: Double, z: Double) -> Double {
            let a = points[0]; let b = points[1]; let c = points[2]
            let ux = Double(b[0] - a[0]); let uy = Double(b[1] - a[1]); let uz = Double(b[2] - a[2])
            let vx = Double(c[0] - a[0]); let vy = Double(c[1] - a[1]); let vz = Double(c[2] - a[2])
            let normalY = uz * vx - ux * vz
            guard abs(normalY) > 0.000_001 else { return Double.nan }
            let normalX = uy * vz - uz * vy
            let normalZ = ux * vy - uy * vx
            return Double(a[1]) - (normalX * (x - Double(a[0])) + normalZ * (z - Double(a[2]))) / normalY
        }
    }

    /// Build the page set from the already guarded source setup and model
    /// catalogs. Missing dynamic animation/head/weapon state remains an
    /// explicit readiness failure; no identity or transform is invented.
    static func make(
        stagePacket: GoldenEyeStageScenePacket,
        dependencies: GoldenEyeStageSetupDependencyCatalogV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6,
        slotNumber: UInt32? = nil
    ) throws -> Self {
        let setupPacket = stagePacket.setup
        guard setupPacket.stageID == stagePacket.stageID else {
            throw Error.stageMismatch(stagePacket.stageID, setupPacket.stageID)
        }
        let modelComplete = sidecars.isComplete && sidecars.models.count == sidecars.expectedModelCount
        let dependencyComplete = dependencies.isReady
        let visibleComplete = visibleDependencies.isComplete
        var missing: [String] = []
        if !dependencyComplete { missing.append("setup_model_dependency_catalog") }
        if !modelComplete { missing.append("complete_stage_model_sidecars") }
        if !visibleComplete { missing.append("ramrom_visible_dependency_catalog") }
        let stan = try Self.parseStan(stagePacket: stagePacket)
        let setupData = try Self.setupPayload(stagePacket: stagePacket)
        guard let stanResource = stagePacket.resources.first(where: { $0.kind == .stan }) else {
            throw Error.invalidObject(stagePacket.stageID, "STAN payload is missing")
        }

        var setup = GERamRomGameplaySetupV6()
        setup.header.abi_version = GE_NATIVE_ABI_VERSION
        setup.header.struct_size = UInt32(MemoryLayout<GERamRomGameplaySetupV6>.size)
        setup.record_version = UInt32(GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION)
        setup.stage_id = setupPacket.stageID
        setup.demo_mask = demoMask(for: setupPacket.stageID)
        setup.source_bytes = setupPacket.sourceBytes
        setup.room_count = stan.roomCount
        setup.portal_count = UInt32(min(setupPacket.portals.count, Int(UInt32.max)))
        setup.stan_count = stan.tileCount
        setup.object_count = UInt32(min(setupPacket.objects.count, Int(UInt32.max)))
        setup.door_count = setupPacket.doorCount
        setup.guard_count = UInt32(setupPacket.objects.reduce(into: 0) { if $1.type == 9 { $0 += 1 } })
        setup.objective_count = UInt32(setupPacket.objects.reduce(into: 0) {
            if (23...34).contains($1.type) { $0 += 1 }
        })
        setup.prop_count = UInt32(setupPacket.objects.reduce(into: 0) {
            if Self.isPropType($1.type) { $0 += 1 }
        })
        setup.waypoint_count = UInt32(min(setupPacket.waypoints.count, Int(UInt32.max)))
        setup.patrol_path_count = UInt32(min(setupPacket.patrolPaths.count, Int(UInt32.max)))
        setup.ai_list_count = UInt32(min(setupPacket.aiLists.count, Int(UInt32.max)))
        setup.tinted_glass_count = setupPacket.tintedGlassCount
        setup.initial_room = UInt32.max
        setup.initial_pad = UInt32.max
        setup.stan_source_bytes = stanResource.decodedBytes
        Self.setInt32Tuple(&setup.initial_position_q16, values: [0, 0, 0])
        Self.setInt32Tuple(&setup.initial_forward_q16, values: [0, 0, 0])
        Self.setInt32Tuple(&setup.world_min_q16, values: stan.worldMinQ16)
        Self.setInt32Tuple(&setup.world_max_q16, values: stan.worldMaxQ16)
        setup.source_hash = setupPacket.sourceHash
        setup.packet_hash = setupPacket.packetHash
        setup.model_dependency_hash = Self.modelDependencyHash(
            stagePacket: stagePacket, dependencies: dependencies, sidecars: sidecars
        )
        setup.stan_source_hash = stanResource.payloadHash
        setup.stan_bounds_hash = stan.boundsHash
        setup.flags = GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_SOURCE_DERIVED
        if stan.roomCount != 0 { setup.flags |= GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_ROOMS }
        if stan.tileCount != 0 { setup.flags |= GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_STAN }
        if !setupPacket.objects.isEmpty { setup.flags |= GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_OBJECTS }
        if !setupPacket.aiLists.isEmpty { setup.flags |= GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_AI }
        if !setupPacket.portals.isEmpty { setup.flags |= GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_PORTALS }
        if modelComplete && dependencyComplete {
            setup.flags |= GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_MODEL_DEPENDENCIES
        } else {
            missing.append("model_dependency_handles")
        }

        if let slotNumber,
           let spawn = Self.spawnPad(setupData: setupData, setup: setupPacket, slotNumber: slotNumber),
           let pad = Self.pad(setup: setupPacket, index: spawn) {
            let position = pad.position
            let look = pad.look
            setup.initial_pad = spawn
            Self.setInt32Tuple(&setup.initial_position_q16, values: position)
            Self.setInt32Tuple(&setup.initial_forward_q16, values: look)
            setup.initial_room = stan.room(forWorldQ16: position)
            setup.spawn_hash = Self.hashWords([UInt64(slotNumber), UInt64(spawn), UInt64(setup.initial_room)])
            if setup.initial_room == UInt32.max { missing.append("spawn_room_for_slot:\(slotNumber)") }
        } else {
            missing.append("player_spawn_pad_for_slot:\(slotNumber.map(String.init) ?? "unknown")")
            setup.spawn_hash = 0
        }
        missing.append("player_runtime_state")
        missing.append("source_camera_state")
        missing.append("guard_animation_state")
        missing.append("head_weapon_attachments")
        missing.append("source_effect_state")

        var entities: [GERamRomGameplayEntityV6] = []
        entities.reserveCapacity(min(Int(GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES), setupPacket.objects.count + 1))
        var player = GERamRomGameplayEntityV6()
        player.header.abi_version = GE_NATIVE_ABI_VERSION
        player.header.struct_size = UInt32(MemoryLayout<GERamRomGameplayEntityV6>.size)
        player.record_version = UInt32(GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION)
        player.entity_id = 1
        player.entity_kind = GE_RAMROM_GAMEPLAY_V6_ENTITY_PLAYER
        player.flags = GE_RAMROM_GAMEPLAY_V6_ENTITY_ACTIVE
        player.room_id = UInt32.max
        player.state = UInt32.max
        player.source_prop_type = UInt32.max
        player.source_record_offset = UInt32.max
        Self.setInt32Tuple(&player.position_q16, values: Self.tupleValues(setup.initial_position_q16))
        Self.setInt32Tuple(&player.source_transform_q16, values: Self.padTransform(
            setup: setupPacket, padIndex: setup.initial_pad
        ) ?? [Int32](repeating: 0, count: 16))
        Self.setInt32Tuple(&player.scale_q16, values: [65536, 65536, 65536])
        player.merge_weight_q16 = 65536
        player.visibility_mask = UInt32.max
        player.health = UInt32.max
        player.max_health = UInt32.max
        entities.append(player)

        for object in setupPacket.objects {
            guard Self.isGameplayObjectType(object.type) else { continue }
            let isObjective = (23...34).contains(object.type)
            let dependency: GoldenEyeStageSetupDependencyCatalogV6.Dependency?
            if object.type == 9 {
                // Type-9 setup key0 is chrnum; corrected setup dependency
                // rows join the source GuardRecord by setup offset and carry
                // the body model index from bodyAI.
                dependency = dependencies.dependencies.first {
                    $0.stage == stagePacket.stageName && $0.kind == "character" &&
                        $0.setupOffset == object.sourceRecordOffset
                }
            } else {
                dependency = dependencies.dependency(kind: "prop", modelIndex: object.key0)
            }
            let modelIndex = dependency?.modelIndex ?? object.key0
            if !isObjective {
                let category = object.type == 9 ? "guards" : "props"
                guard visibleDependencies.dependencies.contains(where: {
                    $0.category == category && $0.modelIndex == modelIndex &&
                        $0.stages.contains(stagePacket.stageName)
                }) else { continue }
            }
            let kind = Self.entityKind(object.type)
            var entity = GERamRomGameplayEntityV6()
            entity.header.abi_version = GE_NATIVE_ABI_VERSION
            entity.header.struct_size = UInt32(MemoryLayout<GERamRomGameplayEntityV6>.size)
            entity.record_version = UInt32(GE_RAMROM_GAMEPLAY_V6_RECORD_VERSION)
            entity.entity_id = object.index + 2
            entity.entity_kind = kind
            entity.flags = GE_RAMROM_GAMEPLAY_V6_ENTITY_ACTIVE
            entity.room_id = UInt32.max
            entity.state = object.state
            entity.action_state = UInt32.max
            entity.death_state = UInt32.max
            entity.target_id = UInt32.max
            entity.source_prop_type = object.type
            entity.source_record_offset = object.sourceRecordOffset
            entity.source_aux0 = object.key0
            entity.source_aux1 = object.key1
            entity.visibility_mask = UInt32.max
            entity.render_flags = UInt32.max
            entity.zbuffer_mode = UInt32.max
            entity.environment_rgba = UInt32.max
            entity.fog_rgba = UInt32.max
            entity.raw_other_mode_h = UInt32.max
            entity.raw_other_mode_l = UInt32.max
            entity.raw_render_mode = UInt32.max
            entity.health = UInt32.max
            entity.max_health = UInt32.max
            Self.setInt32Tuple(&entity.scale_q16, values: [Int32(object.scale8_8 << 8), Int32(object.scale8_8 << 8), Int32(object.scale8_8 << 8)])
            let matrix: [Int32]
            if object.matrixWords.isEmpty {
                if kind == GE_RAMROM_GAMEPLAY_V6_ENTITY_GUARD,
                   let pad = Self.padTransform(setup: setupPacket, padIndex: object.key1) {
                    matrix = pad
                } else if isObjective {
                    matrix = [Int32](repeating: 0, count: 16)
                } else {
                    missing.append("object_transform:\(object.index)")
                    continue
                }
            } else {
                matrix = try Self.matrixQ16(object.matrixWords, objectIndex: object.index)
            }
            Self.setInt32Tuple(&entity.source_transform_q16, values: matrix)
            Self.setInt32Tuple(&entity.position_q16, values: [matrix[12], matrix[13], matrix[14]])

            let dependencyKind = kind == GE_RAMROM_GAMEPLAY_V6_ENTITY_GUARD ? "character" : "prop"
            if isObjective {
                // Objective records are source state, not model placements;
                // their key words remain in source_aux0/source_aux1.
            } else if let dependency {
                let modelName = "stage_\(dependencyKind)_\(String(format: "%03u", dependency.modelIndex))_\(dependency.modelName)"
                if let model = sidecars.models[modelName] {
                    entity.body_model_handle = model.header.modelHandle
                    entity.flags |= GE_RAMROM_GAMEPLAY_V6_ENTITY_VISIBLE
                } else {
                    missing.append("model:\(modelName)")
                }
            } else {
                missing.append("dependency:\(dependencyKind):\(modelIndex)")
            }
            entities.append(entity)
        }

        guard entities.count <= Int(GE_RAMROM_GAMEPLAY_V6_MAX_ENTITIES) else {
            throw Error.capacity(stagePacket.stageID, entities.count)
        }

        let sourceReady = missing.isEmpty &&
            (setup.flags & GE_RAMROM_GAMEPLAY_V6_SETUP_FLAG_MODEL_DEPENDENCIES) != 0 &&
            entities.allSatisfy {
                $0.entity_kind == GE_RAMROM_GAMEPLAY_V6_ENTITY_OBJECTIVE ||
                    $0.body_model_handle != 0
            }
        return Self(
            stageID: stagePacket.stageID, stageName: stagePacket.stageName,
            demoMask: setup.demo_mask, setup: setup, entities: entities,
            attachments: [], sourceReady: sourceReady,
            missingFields: Array(Set(missing)).sorted(),
            slotNumber: slotNumber,
            sourceHash: setup.source_hash, packetHash: setup.packet_hash
        )
    }

    private static func setupPayload(stagePacket: GoldenEyeStageScenePacket) throws -> Data {
        guard let resource = stagePacket.resources.first(where: { $0.kind == .setup }) else {
            throw Error.invalidObject(stagePacket.stageID, "setup payload is missing")
        }
        return resource.payload
    }

    private static func parseStan(stagePacket: GoldenEyeStageScenePacket) throws -> StanSummary {
        guard let resource = stagePacket.resources.first(where: { $0.kind == .stan }) else {
            throw Error.invalidObject(stagePacket.stageID, "STAN payload is missing")
        }
        let data = resource.payload
        guard data.count >= 8, let firstOffset = be32(data, 4), firstOffset >= 8,
              Int(firstOffset) < data.count else {
            throw Error.invalidObject(stagePacket.stageID, "STAN first-tile offset is outside payload")
        }
        let tileSizes = [0x20, 0x20, 0x20, 0x20, 0x28, 0x30, 0x38, 0x40,
                         0x48, 0x50, 0x58, 0]
        /* stanLoadFile() calls setLevelScale(1.0f) before room construction;
           the per-stage background scale table is for model/background
           lowering and must not be applied to STAN collision coordinates. */
        let scale = 1.0
        var offset = Int(firstOffset)
        var tileCount: UInt32 = 0
        var maxRoom: UInt32 = 0
        var roomBounds: [UInt32: ([Int32], [Int32])] = [:]
        var tiles: [(UInt32, [[Int32]])] = []
        var globalMin = [Int32.max, Int32.max, Int32.max]
        var globalMax = [Int32.min, Int32.min, Int32.min]
        while offset + 8 <= data.count {
            guard let idRoom = be32(data, offset), idRoom != 0 else { break }
            guard let tail = be16(data, offset + 6) else {
                throw Error.invalidObject(stagePacket.stageID, "STAN tile tail is truncated")
            }
            let room = idRoom & 0xff
            /* StandTileHeaderTail is a big-endian bit-field in the prepared
               source stream: pointCount occupies the high nibble of the
               16-bit tail word, while the C source accesses the normalized
               host field. */
            let pointCount = Int((tail >> 12) & 0x000f)
            guard pointCount < tileSizes.count, tileSizes[pointCount] != 0,
                  offset + tileSizes[pointCount] <= data.count,
                  offset + 8 + pointCount * 8 <= data.count else {
                throw Error.invalidObject(stagePacket.stageID, "STAN tile bounds are malformed")
            }
            var roomMin = roomBounds[room]?.0 ?? [Int32.max, Int32.max, Int32.max]
            var roomMax = roomBounds[room]?.1 ?? [Int32.min, Int32.min, Int32.min]
            var tilePoints: [[Int32]] = []
            for point in 0..<pointCount {
                let pointOffset = offset + 8 + point * 8
                guard let xWord = be16(data, pointOffset),
                      let yWord = be16(data, pointOffset + 2),
                      let zWord = be16(data, pointOffset + 4) else {
                    throw Error.invalidObject(stagePacket.stageID, "STAN point is truncated")
                }
                let values = [
                    Int32(Int16(bitPattern: xWord)),
                    Int32(Int16(bitPattern: yWord)),
                    Int32(Int16(bitPattern: zWord)),
                ]
                tilePoints.append(values)
                for axis in 0..<3 {
                    roomMin[axis] = min(roomMin[axis], values[axis])
                    roomMax[axis] = max(roomMax[axis], values[axis])
                    globalMin[axis] = min(globalMin[axis], values[axis])
                    globalMax[axis] = max(globalMax[axis], values[axis])
                }
            }
            roomBounds[room] = (roomMin, roomMax)
            tiles.append((room, tilePoints))
            maxRoom = max(maxRoom, room)
            tileCount += 1
            offset += tileSizes[pointCount]
            guard tileCount <= 1_000_000 else {
                throw Error.invalidObject(stagePacket.stageID, "STAN tile count exceeds bound")
            }
        }
        guard tileCount != 0, !roomBounds.isEmpty else {
            throw Error.invalidObject(stagePacket.stageID, "STAN payload has no tiles")
        }
        func worldQ16(_ source: Int32) -> Int32 {
            let value = (Double(source) / scale) * 65_536.0
            return Int32(clamping: Int64(value.rounded(.toNearestOrAwayFromZero)))
        }
        var boundsHash = UInt64(1_469_598_103_934_665_603)
        for (room, bounds) in roomBounds.sorted(by: { $0.key < $1.key }) {
            let values = [UInt64(room)] +
                bounds.0.map { UInt64(bitPattern: Int64($0)) } +
                bounds.1.map { UInt64(bitPattern: Int64($0)) }
            boundsHash = Self.hashWords(values, into: boundsHash)
        }
        return StanSummary(
            tileCount: tileCount, roomCount: maxRoom + 1,
            worldMinQ16: globalMin.map(worldQ16), worldMaxQ16: globalMax.map(worldQ16),
            roomBounds: roomBounds, tiles: tiles, scale: scale, boundsHash: boundsHash
        )
    }

    private static func spawnPad(
        setupData: Data,
        setup: GoldenEyeStageSetupPacket,
        slotNumber: UInt32
    ) -> UInt32? {
        guard let section = setup.sections.first(where: { $0.index == 2 }) else { return nil }
        let start = Int(section.sourceOffset)
        let end = start + Int(section.sourceBytes)
        guard start >= 0, end <= setupData.count else { return nil }
        let sizes = [3, 4, 4, 8, 2, 2, 10, 3, 1, 1]
        var offset = start
        while offset + 4 <= end {
            guard let first = be32(setupData, offset) else { return nil }
            let type = Int(first & 0xff)
            guard type >= 0, type < sizes.count else { return nil }
            let wordCount = sizes[type]
            guard offset + wordCount * 4 <= end else { return nil }
            if type == 9 { return nil }
            if type == 0,
               let pad = be32(setupData, offset + 4),
               let slot = be32(setupData, offset + 8),
               slot == slotNumber {
                return pad
            }
            offset += wordCount * 4
        }
        return nil
    }

    private static func pad(setup: GoldenEyeStageSetupPacket, index: UInt32) -> PadInfo? {
        if let value = setup.pads.first(where: { $0.index == index }) {
            return PadInfo(index: value.index, sourceRecordOffset: value.sourceRecordOffset,
                           position: q16Vector(value.position), up: q16Vector(value.up),
                           look: q16Vector(value.look))
        }
        if let value = setup.boundPads.first(where: { $0.index == index }) {
            return PadInfo(index: value.index, sourceRecordOffset: value.sourceRecordOffset,
                           position: q16Vector(value.position), up: q16Vector(value.up),
                           look: q16Vector(value.look))
        }
        return nil
    }

    private static func be16(_ data: Data, _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 |
            UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }

    private static func tupleValues<T>(_ tuple: T) -> [Int32] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Int32.self)) }
    }

    private static func hashWords(
        _ values: [UInt64], into initial: UInt64 = 1_469_598_103_934_665_603
    ) -> UInt64 {
        values.reduce(initial) { hash, value in
            var result = hash
            for shift in stride(from: 0, to: 64, by: 8) {
                result = (result ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
            }
            return result
        }
    }

    private static func demoMask(for stageID: UInt32) -> UInt32 {
        switch stageID {
        case 33: return (1 << 0) | (1 << 1)
        case 34: return (1 << 2) | (1 << 3) | (1 << 4)
        case 35: return (1 << 5) | (1 << 6)
        case 9: return (1 << 7) | (1 << 8)
        case 20: return (1 << 9) | (1 << 10)
        case 26: return (1 << 11) | (1 << 12)
        case 25: return (1 << 13)
        default: return 0
        }
    }

    private static func isGameplayObjectType(_ type: UInt32) -> Bool {
        isPropType(type) || type == 9 || (23...34).contains(type)
    }

    private static func isPropType(_ type: UInt32) -> Bool {
        switch type {
        case 1, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 17, 20, 21, 36, 39, 40, 41, 42, 43, 45, 47:
            return true
        default: return false
        }
    }

    private static func entityKind(_ type: UInt32) -> UInt32 {
        if type == 1 { return GE_RAMROM_GAMEPLAY_V6_ENTITY_DOOR }
        if type == 9 { return GE_RAMROM_GAMEPLAY_V6_ENTITY_GUARD }
        if (23...34).contains(type) { return GE_RAMROM_GAMEPLAY_V6_ENTITY_OBJECTIVE }
        if type == 47 { return GE_RAMROM_GAMEPLAY_V6_ENTITY_GLASS }
        return GE_RAMROM_GAMEPLAY_V6_ENTITY_PROP
    }

    private static func q16(_ bits: UInt32) -> Int32 {
        let value = Double(Float(bitPattern: bits)) * 65_536.0
        guard value.isFinite, value >= Double(Int32.min), value <= Double(Int32.max) else {
            return 0
        }
        return Int32(value.rounded(.toNearestOrAwayFromZero))
    }

    private static func q16Vector(_ vector: GoldenEyeStageSetupVectorBits) -> [Int32] {
        [q16(vector.x), q16(vector.y), q16(vector.z)]
    }

    private static func matrixQ16(_ words: [UInt32], objectIndex: UInt32) throws -> [Int32] {
        guard words.count == 16 else { throw Error.invalidMatrix(objectIndex, words.count) }
        return words.map(q16)
    }

    private static func padTransform(
        position: [Int32], up: [Int32], look: [Int32]
    ) -> [Int32] {
        guard position.count == 3, up.count == 3, look.count == 3 else {
            return [Int32](repeating: 0, count: 16)
        }
        func cross(_ lhs: [Int32], _ rhs: [Int32]) -> [Int32] {
            let x = (Int64(lhs[1]) * Int64(rhs[2]) - Int64(lhs[2]) * Int64(rhs[1])) >> 16
            let y = (Int64(lhs[2]) * Int64(rhs[0]) - Int64(lhs[0]) * Int64(rhs[2])) >> 16
            let z = (Int64(lhs[0]) * Int64(rhs[1]) - Int64(lhs[1]) * Int64(rhs[0])) >> 16
            return [Int32(clamping: x), Int32(clamping: y), Int32(clamping: z)]
        }
        let right = cross(up, look)
        return [
            right[0], right[1], right[2], 0,
            up[0], up[1], up[2], 0,
            look[0], look[1], look[2], 0,
            position[0], position[1], position[2], 65536,
        ]
    }

    private static func padTransform(
        setup: GoldenEyeStageSetupPacket, padIndex: UInt32
    ) -> [Int32]? {
        if let pad = setup.pads.first(where: { $0.index == padIndex }) {
            return padTransform(
                position: q16Vector(pad.position), up: q16Vector(pad.up), look: q16Vector(pad.look)
            )
        }
        if let pad = setup.boundPads.first(where: { $0.index == padIndex }) {
            return padTransform(
                position: q16Vector(pad.position), up: q16Vector(pad.up), look: q16Vector(pad.look)
            )
        }
        return nil
    }

    private static func setInt32Tuple<T>(_ destination: inout T, values: [Int32]) {
        withUnsafeMutableBytes(of: &destination) { raw in
            let typed = raw.bindMemory(to: Int32.self)
            for index in values.indices where index < typed.count {
                typed[index] = values[index]
            }
        }
    }

    private static func modelDependencyHash(
        stagePacket: GoldenEyeStageScenePacket,
        dependencies: GoldenEyeStageSetupDependencyCatalogV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6
    ) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        func mix(_ value: UInt64) {
            for shift in stride(from: 0, to: 64, by: 8) {
                hash = (hash ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
            }
        }
        mix(UInt64(stagePacket.stageID))
        for dependency in dependencies.dependencies where dependency.stage == stagePacket.stageName {
            mix(UInt64(dependency.objectIndex)); mix(UInt64(dependency.modelIndex))
            let modelName = "stage_\(dependency.kind)_\(String(format: "%03u", dependency.modelIndex))_\(dependency.modelName)"
            mix(Self.digestPrefix(sidecars.models[modelName]?.header.packetHash ?? []))
        }
        return hash == 0 ? 1 : hash
    }

    private static func digestPrefix(_ digest: [UInt8]) -> UInt64 {
        digest.prefix(8).enumerated().reduce(UInt64(0)) { partial, pair in
            partial | (UInt64(pair.element) << UInt64(pair.offset * 8))
        }
    }
}

/// Swift owner-thread bridge for the directly compiled guard/door owner. It
/// refuses to call the C integration seam until pose, AI, bound-pad, and
/// model readiness have been proved by the source-page builder.
public enum GoldenEyeRamRomGameplayGuardDoorIntegrationV6 {
    public enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case sourceNotReady([String])
        case status(UInt32, String)

        public var description: String {
            switch self {
            case let .sourceNotReady(fields):
                return "guard/door gameplay integration is not source-ready: " + fields.joined(separator: ",")
            case let .status(status, operation):
                return "guard/door gameplay " + operation + " failed with status " + String(status)
            }
        }
    }

    public struct BeginResult: Sendable {
        public let state: GERamRomGameplayStateV6
        public let event: GERamRomGameplayEventV6
    }

    public static func begin(
        recording: Data,
        demoID: UInt32,
        pages: GoldenEyeRamRomGameplaySourcePagesV6,
        owner: inout GEGuardDoorOwnerStateV6
    ) throws -> BeginResult {
        guard pages.sourceReady else { throw Error.sourceNotReady(pages.missingFields) }
        var state = GERamRomGameplayStateV6()
        var event = GERamRomGameplayEventV6()
        let status: UInt32 = pages.entities.withUnsafeBufferPointer { entityBuffer in
            pages.attachments.withUnsafeBufferPointer { attachmentBuffer in
                recording.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return UInt32(GE_STATUS_INVALID_ARGUMENT)
                    }
                    return withUnsafePointer(to: pages.setup) { setupPointer in
                        ge_ramrom_gameplay_v6_begin_with_source_pages_and_guard_door_owner(
                            base, UInt32(recording.count), demoID, setupPointer,
                            entityBuffer.baseAddress, UInt32(entityBuffer.count),
                            attachmentBuffer.baseAddress, UInt32(attachmentBuffer.count),
                            &owner, &state, &event
                        )
                    }
                }
            }
        }
        guard status == UInt32(GE_STATUS_OK) else {
            throw Error.status(status, "begin")
        }
        return BeginResult(state: state, event: event)
    }

    public static func step(
        recording: Data,
        nativeTick: UInt64,
        input: GERamRomGameplayInputV6,
        owner: GEGuardDoorOwnerStateV6,
        state: inout GERamRomGameplayStateV6
    ) throws -> GERamRomGameplayEventV6 {
        var event = GERamRomGameplayEventV6()
        let status: UInt32 = recording.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return UInt32(GE_STATUS_INVALID_ARGUMENT)
            }
            var ownerCopy = owner
            return ge_ramrom_gameplay_v6_step_with_guard_door_owner(
                base, UInt32(recording.count), nativeTick, input,
                &ownerCopy, &state, &event
            )
        }
        guard status == UInt32(GE_STATUS_OK) else {
            throw Error.status(status, "step")
        }
        return event
    }
}
