import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Source option values needed by Bond's input owner.  The inversion value is
/// intentionally supplied by the save/options owner; RAMROM's `aim_option`
/// word is not the vertical-look option and must not be reused here.
public struct GoldenEyeRamRomSourceOptionStateV6: Sendable, Equatable {
    public let controlStyle: UInt32
    public let invertLook: UInt32
    public let sourceHash: UInt64
    public let provenance: [String]

    public init(
        controlStyle: UInt32, invertLook: UInt32, sourceHash: UInt64,
        provenance: [String]
    ) throws {
        guard controlStyle <= UInt32(GE_PLAYER_CAMERA_OWNER_V6_CONTROL_MAX),
              invertLook <= 1, sourceHash != 0, !provenance.isEmpty else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.missingSourceEvidence(
                "controller style / vertical-look option"
            )
        }
        self.controlStyle = controlStyle
        self.invertLook = invertLook
        self.sourceHash = sourceHash
        self.provenance = provenance
    }

    /// The US source defaults from `src/game/options.c:104` and
    /// `src/game/player.c:55-62`. This is only a valid option source when the
    /// selected save has not supplied another value.
    public static func usSourceDefault(controlStyle: UInt32 = 0) throws -> Self {
        try Self(
            controlStyle: controlStyle, invertLook: 0,
            sourceHash: 0x4f5054494f4e5f55,
            provenance: [
                "src/game/options.c:104 PLAYER_OPTION_LOOK default=0",
                "src/game/player.c:55-62 player_perspective_height default path",
            ]
        )
    }
}

/// Values that are not present in the current setup/model pages are accepted
/// only through this source-evidence record. No field has a fallback value.
/// The default constructor below is deliberately absent.
public struct GoldenEyeRamRomSourcePlayerStateV6: Sendable, Equatable {
    public let cameraEyeHeightQ16: Int32
    public let cameraOffsetQ16: [Int32]
    public let headOffsetQ16: [Int32]
    public let collisionRadiusQ16: Int32
    public let collisionHeightQ16: Int32
    public let floorToleranceQ16: Int32
    public let padSelectRadiusQ16: Int32
    public let initialWeaponItem: UInt32
    public let initialAmmo: UInt32
    public let initialHealthQ16: UInt32
    public let initialAnimation: UInt32
    public let initialPitchQ16: Int32
    public let sourceHash: UInt64
    public let provenance: [String]

    public init(
        cameraEyeHeightQ16: Int32, cameraOffsetQ16: [Int32], headOffsetQ16: [Int32],
        collisionRadiusQ16: Int32, collisionHeightQ16: Int32,
        floorToleranceQ16: Int32, padSelectRadiusQ16: Int32,
        initialWeaponItem: UInt32, initialAmmo: UInt32, initialHealthQ16: UInt32,
        initialAnimation: UInt32, initialPitchQ16: Int32,
        sourceHash: UInt64, provenance: [String]
    ) throws {
        guard cameraOffsetQ16.count == 3, headOffsetQ16.count == 3,
              cameraEyeHeightQ16 > 0, collisionRadiusQ16 > 0,
              collisionHeightQ16 > 0, floorToleranceQ16 >= 0,
              padSelectRadiusQ16 >= 0, initialHealthQ16 != UInt32.max,
              initialPitchQ16 != Int32.min, sourceHash != 0,
              !provenance.isEmpty else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.missingSourceEvidence(
                "camera/collision/player initialization"
            )
        }
        self.cameraEyeHeightQ16 = cameraEyeHeightQ16
        self.cameraOffsetQ16 = cameraOffsetQ16
        self.headOffsetQ16 = headOffsetQ16
        self.collisionRadiusQ16 = collisionRadiusQ16
        self.collisionHeightQ16 = collisionHeightQ16
        self.floorToleranceQ16 = floorToleranceQ16
        self.padSelectRadiusQ16 = padSelectRadiusQ16
        self.initialWeaponItem = initialWeaponItem
        self.initialAmmo = initialAmmo
        self.initialHealthQ16 = initialHealthQ16
        self.initialAnimation = initialAnimation
        self.initialPitchQ16 = initialPitchQ16
        self.sourceHash = sourceHash
        self.provenance = provenance
    }

    /// Exact US initial values from the directly compiled source. Weapon and
    /// ammo come from the selected setup INTRO records, not a guessed item.
    public static func sourceInitial(
        weaponItem: UInt32, ammo: UInt32, optionHash: UInt64
    ) throws -> Self {
        try Self(
            cameraEyeHeightQ16: 175 * 65_536,
            cameraOffsetQ16: [0, 0, 0],
            headOffsetQ16: [0, 0, 0],
            collisionRadiusQ16: 30 * 65_536,
            collisionHeightQ16: 155 * 65_536,
            floorToleranceQ16: 66,
            padSelectRadiusQ16: 0,
            initialWeaponItem: weaponItem,
            initialAmmo: ammo,
            initialHealthQ16: 65_536,
            initialAnimation: 0,
            initialPitchQ16: -4 * 65_536,
            sourceHash: Self.hashWords([
                UInt64(175 * 65_536), UInt64(30 * 65_536),
                UInt64(155 * 65_536), UInt64(weaponItem), UInt64(ammo), optionHash,
            ]),
            provenance: [
                "src/game/bondview.c:1507 bondviewPlayerBeginLife eyeheight=185*perspective-10",
                "src/game/bondview2.c:1767 change_player_pos_to_target collision_radius=30",
                "src/game/bondview2.c:9619-9625 bondviewGetCollisionRadius height=eyeheight+10-30",
                "src/game/initBondDATA.c:247-259 initial hand/ammo state",
                "src/game/initBondDATAdefaults.c:104-160 head animation defaults",
                "src/game/bondview.c:1430 initial vv_verta=-4",
                "src/game/bondview_r.c:192-236 setup INTRO item/ammo source",
            ]
        )
    }

    private static func hashWords(_ values: [UInt64]) -> UInt64 {
        values.reduce(UInt64(1_469_598_103_934_665_603)) { hash, value in
            var result = hash
            for shift in stride(from: 0, to: 64, by: 8) {
                result = (result ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
            }
            return result
        }
    }
}

public enum GoldenEyeRamRomPlayerCameraOwnerErrorV6: Error, Sendable, Equatable, CustomStringConvertible {
    case missingSourceEvidence(String)
    case malformedSTAN(UInt32, String)
    case missingResource(UInt32, String)
    case missingSpawn(UInt32, UInt32)
    case invalidStage(UInt32)
    case invalidRecording(UInt32, UInt32)
    case ownerStatus(UInt32)
    case unsupportedSource(UInt32, String)

    public var description: String {
        switch self {
        case let .missingSourceEvidence(field): return "missing source player/camera evidence: \(field)"
        case let .malformedSTAN(stage, detail): return "malformed source STAN stage \(stage): \(detail)"
        case let .missingResource(stage, name): return "stage \(stage) is missing source resource \(name)"
        case let .missingSpawn(stage, slot): return "stage \(stage) has no source spawn for slot \(slot)"
        case let .invalidStage(stage): return "invalid player/camera stage \(stage)"
        case let .invalidRecording(demo, status): return "RAMROM demo \(demo) parse status \(status)"
        case let .ownerStatus(status): return "player/camera owner status \(status)"
        case let .unsupportedSource(stage, detail): return "stage \(stage) source player/camera unsupported: \(detail)"
        }
    }
}

public struct GoldenEyeRamRomPlayerCameraPagesV6: Sendable {
    public let stageID: UInt32
    public let demoID: UInt32
    public let slotNumber: UInt32
    public let setup: GERamRomGameplaySetupV6
    public let entities: [GERamRomGameplayEntityV6]
    public let attachments: [GERamRomGameplayAttachmentV6]
    public let source: GEPlayerCameraSourceV6
    public let stan: [GEPlayerCameraStanTileV6]
    public let pads: [GEPlayerCameraPadV6]
    public let provenance: [String]
}

public enum GoldenEyeRamRomPlayerCameraPageBuilderV6 {
    private struct StanData {
        let tiles: [(room: UInt32, points: [[Int32]], offset: UInt32)]
        let minQ16: [Int32]
        let maxQ16: [Int32]
        let roomCount: UInt32

        func floorY(x: Double, z: Double) -> (room: UInt32, y: Double)? {
            var selected: (UInt32, Double)?
            for tile in tiles {
                guard Self.inside(tile.points, x: x, z: z),
                      let y = Self.planeY(tile.points, x: x, z: z) else {
                    continue
                }
                if selected == nil || y > selected!.1 { selected = (tile.room, y) }
            }
            return selected
        }

        private static func inside(_ points: [[Int32]], x: Double, z: Double) -> Bool {
            var positive = true; var negative = true
            for index in points.indices {
                let next = (index + 1) % points.count
                let ax = Double(points[index][0]) / 65_536.0
                let az = Double(points[index][2]) / 65_536.0
                let bx = Double(points[next][0]) / 65_536.0
                let bz = Double(points[next][2]) / 65_536.0
                let cross = (bx - ax) * (z - az) - (bz - az) * (x - ax)
                positive = positive && cross >= -0.001
                negative = negative && cross <= 0.001
            }
            return positive || negative
        }

        private static func planeY(_ points: [[Int32]], x: Double, z: Double) -> Double? {
            guard points.count >= 3 else { return nil }
            let a = points[0].map { Double($0) / 65_536.0 }
            let b = points[1].map { Double($0) / 65_536.0 }
            let c = points[2].map { Double($0) / 65_536.0 }
            let ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2]
            let vx = c[0] - a[0], vy = c[1] - a[1], vz = c[2] - a[2]
            let normalY = uz * vx - ux * vz
            guard abs(normalY) > 0.000001 else { return nil }
            let normalX = uy * vz - uz * vy
            let normalZ = ux * vy - uy * vx
            return a[1] - (normalX * (x - a[0]) + normalZ * (z - a[2])) / normalY
        }
    }

    private struct IntroState {
        var weapon: UInt32 = 1 // ITEM_FIST, source fallback in bondview_r.c
        var ammo: UInt32 = 0
        var sawEnd = false
    }

    public static func make(
        stagePacket: GoldenEyeStageScenePacket,
        sourcePages: GoldenEyeRamRomGameplaySourcePagesV6,
        ramromHeader: GERamRomHeaderV5,
        optionState: GoldenEyeRamRomSourceOptionStateV6,
        demoID: UInt32
    ) throws -> GoldenEyeRamRomPlayerCameraPagesV6 {
        guard stagePacket.stageID == sourcePages.stageID,
              ramromHeader.stage_id == stagePacket.stageID,
              demoID > 0, demoID <= UInt32(GE_RAMROM_V5_DEMO_COUNT) else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.invalidStage(stagePacket.stageID)
        }
        guard let slot = sourcePages.slotNumber else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.missingSpawn(stagePacket.stageID, UInt32.max)
        }
        let stan = try parseSTAN(stagePacket: stagePacket)
        guard let setupResource = stagePacket.resources.first(where: { $0.kind == .setup }) else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.missingResource(stagePacket.stageID, "setup")
        }
        let intro = try parseIntro(
            setupData: setupResource.payload, setup: stagePacket.setup, slot: slot,
            stageID: stagePacket.stageID
        )
        let evidence = try GoldenEyeRamRomSourcePlayerStateV6.sourceInitial(
            weaponItem: intro.weapon, ammo: intro.ammo, optionHash: optionState.sourceHash
        )
        guard let sourcePad = sourcePad(setup: stagePacket.setup, index: sourcePages.setup.initial_pad) else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.missingSpawn(
                stagePacket.stageID, sourcePages.setup.initial_pad
            )
        }
        let padPosition = q16Vector(sourcePad.position)
        let floor = stan.floorY(
            x: Double(padPosition[0]) / 65_536.0,
            z: Double(padPosition[2]) / 65_536.0
        )
        guard let floor else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.unsupportedSource(
                stagePacket.stageID, "spawn pad does not resolve to a source STAN floor"
            )
        }
        let spawnPosition = [
            padPosition[0],
            Int32(clamping: Int64((floor.y * 65_536.0).rounded(.toNearestOrAwayFromZero))) + evidence.cameraEyeHeightQ16,
            padPosition[2],
        ]
        var setup = sourcePages.setup
        setInt32Tuple(&setup.initial_position_q16, values: spawnPosition)
        setInt32Tuple(&setup.initial_forward_q16, values: q16Vector(sourcePad.look))
        setup.initial_room = floor.room
        setup.spawn_hash = hashWords([
            UInt64(slot), UInt64(sourcePages.setup.initial_pad), UInt64(floor.room),
            UInt64(bitPattern: Int64(spawnPosition[0])), UInt64(bitPattern: Int64(spawnPosition[1])),
            UInt64(bitPattern: Int64(spawnPosition[2])),
        ])

        var entities = sourcePages.entities
        guard !entities.isEmpty else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.missingSourceEvidence("player entity page")
        }
        var player = entities[0]
        player.flags |= GE_RAMROM_GAMEPLAY_V6_ENTITY_ACTIVE
        player.room_id = floor.room
        player.weapon_model_handle = evidence.initialWeaponItem
        player.health = evidence.initialHealthQ16
        player.max_health = evidence.initialHealthQ16
        player.animation_id = evidence.initialAnimation
        setInt32Tuple(&player.position_q16, values: spawnPosition)
        entities[0] = player

        var source = GEPlayerCameraSourceV6()
        source.header.abi_version = GE_NATIVE_ABI_VERSION
        source.header.struct_size = UInt32(MemoryLayout<GEPlayerCameraSourceV6>.size)
        source.record_version = UInt32(GE_PLAYER_CAMERA_OWNER_V6_RECORD_VERSION)
        source.stage_id = stagePacket.stageID
        source.demo_mask = sourcePages.demoMask
        source.flags = UInt32(GE_PLAYER_CAMERA_OWNER_V6_SOURCE_SPAWN) |
            UInt32(GE_PLAYER_CAMERA_OWNER_V6_SOURCE_CAMERA) |
            UInt32(GE_PLAYER_CAMERA_OWNER_V6_SOURCE_COLLISION) |
            UInt32(GE_PLAYER_CAMERA_OWNER_V6_SOURCE_STAN) |
            UInt32(GE_PLAYER_CAMERA_OWNER_V6_SOURCE_WEAPON) |
            UInt32(GE_PLAYER_CAMERA_OWNER_V6_SOURCE_HUD) |
            UInt32(GE_PLAYER_CAMERA_OWNER_V6_SOURCE_CONTROL) |
            UInt32(GE_PLAYER_CAMERA_OWNER_V6_SOURCE_PADS)
        source.control_style = optionState.controlStyle
        source.invert_look = optionState.invertLook
        source.source_spawn_offset = sourcePad.sourceRecordOffset
        source.source_camera_offset = 4_564
        source.source_collision_offset = 1_767
        source.initial_pitch_q16 = evidence.initialPitchQ16
        setInt32Tuple(&source.camera_offset_q16, values: evidence.cameraOffsetQ16)
        setInt32Tuple(&source.head_offset_q16, values: evidence.headOffsetQ16)
        source.collision_radius_q16 = evidence.collisionRadiusQ16
        source.collision_height_q16 = evidence.collisionHeightQ16
        source.floor_tolerance_q16 = evidence.floorToleranceQ16
        source.pad_select_radius_q16 = evidence.padSelectRadiusQ16
        source.initial_weapon = evidence.initialWeaponItem
        source.initial_ammo = evidence.initialAmmo
        source.initial_health = evidence.initialHealthQ16
        source.initial_animation = evidence.initialAnimation
        source.source_hash = hashWords([
            stagePacket.setup.sourceHash, stagePacket.packetHash,
            sourcePages.setup.stan_source_hash, evidence.sourceHash,
            optionState.sourceHash,
        ])
        source.setup_hash = sourcePages.setup.source_hash
        source.player_hash = evidence.sourceHash

        let stanRows = stan.tiles.map { tile in
            makeSTANRow(tile: tile, payloadHash: stagePacket.resources.first { $0.kind == .stan }?.payloadHash ?? 0)
        }
        let padRows = try makePadRows(
            setup: stagePacket.setup, spawnPad: setup.initial_pad, stan: stan
        )
        guard !stanRows.isEmpty, !padRows.isEmpty else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.unsupportedSource(
                stagePacket.stageID, "source STAN or pad rows are empty"
            )
        }
        return GoldenEyeRamRomPlayerCameraPagesV6(
            stageID: stagePacket.stageID, demoID: demoID, slotNumber: slot,
            setup: setup, entities: entities, attachments: sourcePages.attachments, source: source,
            stan: stanRows, pads: padRows,
            provenance: evidence.provenance + optionState.provenance + [
                "src/game/bondview_r.c:175-236 selected demo spawn/item/ammo intro records",
                "src/game/bondview_r.c:388-414 pad position/floor/look camera initialization",
            ]
        )
    }

    private static func parseSTAN(stagePacket: GoldenEyeStageScenePacket) throws -> StanData {
        guard let resource = stagePacket.resources.first(where: { $0.kind == .stan }) else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.missingResource(stagePacket.stageID, "STAN")
        }
        let data = resource.payload
        guard let firstOffset = be32(data, 4), firstOffset >= 8, Int(firstOffset) < data.count else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.malformedSTAN(stagePacket.stageID, "invalid first tile offset")
        }
        let tileSizes = [0x20, 0x20, 0x20, 0x20, 0x28, 0x30, 0x38, 0x40, 0x48, 0x50, 0x58, 0]
        var offset = Int(firstOffset)
        var tiles: [(room: UInt32, points: [[Int32]], offset: UInt32)] = []
        var minValues = [Int32.max, Int32.max, Int32.max]
        var maxValues = [Int32.min, Int32.min, Int32.min]
        var maxRoom: UInt32 = 0
        while offset + 8 <= data.count {
            guard let idRoom = be32(data, offset), idRoom != 0 else { break }
            guard let tail = be16(data, offset + 6) else {
                throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.malformedSTAN(stagePacket.stageID, "truncated tail")
            }
            let count = Int((tail >> 12) & 0xf)
            guard count >= 3, count < tileSizes.count, tileSizes[count] != 0,
                  offset + tileSizes[count] <= data.count else {
                throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.malformedSTAN(stagePacket.stageID, "tile bounds")
            }
            var points: [[Int32]] = []
            for point in 0..<count {
                let pointOffset = offset + 8 + point * 8
                guard let x = be16(data, pointOffset), let y = be16(data, pointOffset + 2),
                      let z = be16(data, pointOffset + 4) else {
                    throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.malformedSTAN(stagePacket.stageID, "truncated point")
                }
                let values = [
                    Int32(Int16(bitPattern: x)) * 65_536,
                    Int32(Int16(bitPattern: y)) * 65_536,
                    Int32(Int16(bitPattern: z)) * 65_536,
                ]
                points.append(values)
                for axis in 0..<3 {
                    minValues[axis] = min(minValues[axis], values[axis])
                    maxValues[axis] = max(maxValues[axis], values[axis])
                }
            }
            let room = idRoom & 0xff
            tiles.append((room: room, points: points, offset: UInt32(offset)))
            maxRoom = max(maxRoom, room)
            offset += tileSizes[count]
            guard tiles.count <= Int(GE_PLAYER_CAMERA_OWNER_V6_MAX_STAN_TILES) else {
                throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.malformedSTAN(stagePacket.stageID, "tile capacity")
            }
        }
        guard !tiles.isEmpty else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.malformedSTAN(stagePacket.stageID, "no tiles")
        }
        return StanData(tiles: tiles, minQ16: minValues, maxQ16: maxValues, roomCount: maxRoom + 1)
    }

    private static func parseIntro(
        setupData: Data, setup: GoldenEyeStageSetupPacket, slot: UInt32, stageID: UInt32
    ) throws -> IntroState {
        guard let section = setup.sections.first(where: { $0.index == 2 }) else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.missingResource(stageID, "INTRO")
        }
        let start = Int(section.sourceOffset)
        let end = start + Int(section.sourceBytes)
        guard start >= 0, end <= setupData.count else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.malformedSTAN(stageID, "INTRO section bounds")
        }
        var offset = start
        var result = IntroState()
        var selectedWeapon = false
        while offset + 4 <= end {
            guard let type = be32(setupData, offset) else { break }
            let size: Int
            switch type {
            case 0: size = 12
            case 1, 2: size = 16
            case 3: size = 32
            case 4, 5, 9, 10: size = 8
            case 6: size = 40
            case 7: size = 12
            case 8: size = 12
            default:
                throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.malformedSTAN(stageID, "unknown INTRO type \(type)")
            }
            guard offset + size <= end else {
                throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.malformedSTAN(stageID, "INTRO record bounds")
            }
            if type == 9 {
                result.sawEnd = true
                break
            }
            if type == 1 || type == 2, let demoSlot = be32(setupData, offset + 12), demoSlot == slot {
                if type == 1, !selectedWeapon, let weapon = be32(setupData, offset + 4),
                   let left = be32(setupData, offset + 8) {
                    result.weapon = weapon
                    selectedWeapon = true
                    _ = left
                } else if type == 2, let amount = be32(setupData, offset + 8) {
                    result.ammo &+= amount
                }
            }
            offset += size
        }
        guard result.sawEnd else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.malformedSTAN(stageID, "INTRO end sentinel")
        }
        return result
    }

    private static func sourcePad(setup: GoldenEyeStageSetupPacket, index: UInt32) -> GoldenEyeStageSetupPadPacket? {
        if let pad = setup.pads.first(where: { $0.index == index }) { return pad }
        if let pad = setup.boundPads.first(where: { $0.index == index }) {
            return GoldenEyeStageSetupPadPacket(
                index: pad.index, sourceRecordOffset: pad.sourceRecordOffset,
                position: pad.position, up: pad.up, look: pad.look,
                linkOffset: pad.linkOffset, stanOffset: pad.stanOffset
            )
        }
        return nil
    }

    private static func makePadRows(
        setup: GoldenEyeStageSetupPacket, spawnPad: UInt32, stan: StanData
    ) throws -> [GEPlayerCameraPadV6] {
        var rows: [GEPlayerCameraPadV6] = []
        let standard = setup.pads.map { (pad: $0, bound: false) }
        let bound = setup.boundPads.map { pad in
            (pad: GoldenEyeStageSetupPadPacket(
                index: pad.index, sourceRecordOffset: pad.sourceRecordOffset,
                position: pad.position, up: pad.up, look: pad.look,
                linkOffset: pad.linkOffset, stanOffset: pad.stanOffset
            ), bound: true)
        }
        for item in standard + bound {
            var row = GEPlayerCameraPadV6()
            row.header.abi_version = GE_NATIVE_ABI_VERSION
            row.header.struct_size = UInt32(MemoryLayout<GEPlayerCameraPadV6>.size)
            row.record_version = UInt32(GE_PLAYER_CAMERA_OWNER_V6_RECORD_VERSION)
            row.pad_id = item.pad.index
            let position = q16Vector(item.pad.position)
            guard let floor = stan.floorY(
                x: Double(position[0]) / 65_536.0, z: Double(position[2]) / 65_536.0
            ) else {
                if item.pad.index == spawnPad {
                    throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.unsupportedSource(
                        setup.stageID, "spawn pad \(item.pad.index) does not resolve to a source STAN room"
                    )
                }
                continue
            }
            row.room_id = floor.room
            row.flags = UInt32(GE_PLAYER_CAMERA_OWNER_V6_PAD_FLAG_SOURCE_DERIVED) |
                (item.pad.index == spawnPad ? UInt32(GE_PLAYER_CAMERA_OWNER_V6_PAD_FLAG_SPAWN) : 0)
            setInt32Tuple(&row.position_q16, values: position)
            setInt32Tuple(&row.forward_q16, values: q16Vector(item.pad.look))
            row.source_offset = item.pad.sourceRecordOffset
            rows.append(row)
        }
        return rows
    }

    private static func makeSTANRow(
        tile: (room: UInt32, points: [[Int32]], offset: UInt32), payloadHash: UInt64
    ) -> GEPlayerCameraStanTileV6 {
        var row = GEPlayerCameraStanTileV6()
        row.header.abi_version = GE_NATIVE_ABI_VERSION
        row.header.struct_size = UInt32(MemoryLayout<GEPlayerCameraStanTileV6>.size)
        row.record_version = UInt32(GE_PLAYER_CAMERA_OWNER_V6_RECORD_VERSION)
        row.tile_id = tile.offset
        row.room_id = tile.room
        row.flags = UInt32(GE_PLAYER_CAMERA_OWNER_V6_TILE_FLAG_SOURCE_DERIVED) |
            UInt32(GE_PLAYER_CAMERA_OWNER_V6_TILE_FLAG_FLOOR)
        row.point_count = UInt32(tile.points.count)
        withUnsafeMutableBytes(of: &row) { raw in
            for point in tile.points.indices {
                for axis in 0..<3 {
                    raw.storeBytes(
                        of: tile.points[point][axis],
                        toByteOffset: 28 + (point * 3 + axis) * MemoryLayout<Int32>.size,
                        as: Int32.self
                    )
                }
            }
        }
        row.source_hash = payloadHash
        row.source_offset = tile.offset
        return row
    }

    private static func q16Vector(_ vector: GoldenEyeStageSetupVectorBits) -> [Int32] {
        [q16(vector.x), q16(vector.y), q16(vector.z)]
    }

    private static func q16(_ bits: UInt32) -> Int32 {
        let value = Double(Float(bitPattern: bits)) * 65_536.0
        guard value.isFinite, value >= Double(Int32.min), value <= Double(Int32.max) else { return 0 }
        return Int32(value.rounded(.towardZero))
    }

    private static func setInt32Tuple<T>(_ destination: inout T, values: [Int32]) {
        withUnsafeMutableBytes(of: &destination) { raw in
            let typed = raw.bindMemory(to: Int32.self)
            for index in values.indices where index < typed.count { typed[index] = values[index] }
        }
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

    private static func hashWords(_ values: [UInt64]) -> UInt64 {
        values.reduce(UInt64(1_469_598_103_934_665_603)) { hash, value in
            var result = hash
            for shift in stride(from: 0, to: 64, by: 8) {
                result = (result ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
            }
            return result
        }
    }
}

/// Immutable publication for the non-model visual authority.  The existing
/// V6 stage state carries the visible values; these independent hashes make
/// player, camera, and room changes auditable without altering that frozen
/// record.
public struct GoldenEyeRamRomPlayerCameraPublicationV6 {
    public let sourceSnapshot: GEPlayerCameraSnapshotV6
    public let stageState: GoldenEyeRamRomStageVisualStateV6
    public let playerHash: UInt64
    public let cameraHash: UInt64
    public let roomHash: UInt64
    public let ownerStateHash: UInt64

    public init(snapshot: GEPlayerCameraSnapshotV6, nativeTickOverride: UInt64? = nil) {
        sourceSnapshot = snapshot
        let player = Self.values(snapshot.player_position_q16)
        let camera = Self.values(snapshot.camera_position_q16)
        let forward = Self.values(snapshot.camera_forward_q16)
        stageState = GoldenEyeRamRomStageVisualStateV6(
            stageID: UInt32(snapshot.stage_id), nativeTick: nativeTickOverride ?? UInt64(snapshot.native_tick),
            referenceTick: nativeTickOverride.map { $0 >> 1 } ?? UInt64(snapshot.reference_tick), currentRoom: UInt32(snapshot.current_room),
            playerPositionQ16: .init(x: player[0], y: player[1], z: player[2]),
            cameraPositionQ16: .init(x: camera[0], y: camera[1], z: camera[2]),
            cameraForwardQ16: .init(x: forward[0], y: forward[1], z: forward[2]),
            stateHash: UInt64(snapshot.state_hash)
        )
        playerHash = Self.hashWords([
            UInt64(snapshot.stage_id), UInt64(snapshot.current_room),
            UInt64(bitPattern: Int64(player[0])), UInt64(bitPattern: Int64(player[1])),
            UInt64(bitPattern: Int64(player[2])),
        ])
        cameraHash = Self.hashWords([
            UInt64(snapshot.stage_id), UInt64(bitPattern: Int64(camera[0])),
            UInt64(bitPattern: Int64(camera[1])), UInt64(bitPattern: Int64(camera[2])),
            UInt64(bitPattern: Int64(forward[0])), UInt64(bitPattern: Int64(forward[1])),
            UInt64(bitPattern: Int64(forward[2])), UInt64(bitPattern: Int64(snapshot.yaw_q16)),
            UInt64(bitPattern: Int64(snapshot.pitch_q16)),
        ])
        roomHash = Self.hashWords([UInt64(snapshot.stage_id), UInt64(snapshot.current_room), UInt64(snapshot.current_pad)])
        ownerStateHash = UInt64(snapshot.state_hash)
    }

    private static func values<T>(_ tuple: T) -> [Int32] {
        withUnsafeBytes(of: tuple) { Array($0.bindMemory(to: Int32.self)) }
    }

    private static func hashWords(_ values: [UInt64]) -> UInt64 {
        values.reduce(UInt64(1_469_598_103_934_665_603)) { hash, value in
            var result = hash
            for shift in stride(from: 0, to: 64, by: 8) {
                result = (result ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
            }
            return result
        }
    }
}

/// Owner-thread wrapper around the directly compiled C owner. The C state is
/// retained by value and all C calls borrow it only for the duration of one
/// operation.
public final class GoldenEyeRamRomPlayerCameraOwnerV6: @unchecked Sendable {
    private var state: GEPlayerCameraOwnerStateV6

    public init(pages: GoldenEyeRamRomPlayerCameraPagesV6) throws {
        state = GEPlayerCameraOwnerStateV6()
        var event = GEPlayerCameraEventV6()
        let status = pages.setup.withUnsafePointer { setupPointer in
            pages.entities.withUnsafeBufferPointer { entityBuffer in
                pages.source.withUnsafePointer { sourcePointer in
                    pages.stan.withUnsafeBufferPointer { stanBuffer in
                        pages.pads.withUnsafeBufferPointer { padBuffer in
                            withUnsafeMutablePointer(to: &state) { statePointer in
                                withUnsafeMutablePointer(to: &event) { eventPointer in
                                    ge_player_camera_owner_begin_from_gameplay_pages(
                                        pages.demoID, setupPointer, entityBuffer.baseAddress,
                                        UInt32(entityBuffer.count), sourcePointer,
                                        stanBuffer.baseAddress, UInt32(stanBuffer.count),
                                        padBuffer.baseAddress, UInt32(padBuffer.count),
                                        statePointer, eventPointer
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        guard status == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.ownerStatus(status)
        }
    }

    public var snapshot: GEPlayerCameraSnapshotV6 {
        var value = GEPlayerCameraSnapshotV6()
        _ = withUnsafePointer(to: &state) { ge_player_camera_owner_copy_snapshot($0, &value) }
        return value
    }

    @discardableResult
    public func step(nativeTick: UInt64, input: GERamRomGameplayInputV6) throws -> GoldenEyeRamRomPlayerCameraPublicationV6 {
        var event = GEPlayerCameraEventV6()
        let status = withUnsafeMutablePointer(to: &state) { statePointer in
            withUnsafeMutablePointer(to: &event) { eventPointer in
                ge_player_camera_owner_step(nativeTick, input, statePointer, eventPointer)
            }
        }
        guard status == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.ownerStatus(status)
        }
        return GoldenEyeRamRomPlayerCameraPublicationV6(snapshot: snapshot)
    }

    public func restore(snapshot: GEPlayerCameraSnapshotV6) throws {
        var value = snapshot
        let status = withUnsafeMutablePointer(to: &state) { statePointer in
            ge_player_camera_owner_restore(statePointer, &value)
        }
        guard status == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeRamRomPlayerCameraOwnerErrorV6.ownerStatus(status)
        }
    }
}

private extension GEPlayerCameraSourceV6 {
    func withUnsafePointer<R>(_ body: (UnsafePointer<GEPlayerCameraSourceV6>) throws -> R) rethrows -> R {
        var copy = self
        return try Swift.withUnsafePointer(to: &copy, body)
    }
}

private extension GERamRomGameplaySetupV6 {
    func withUnsafePointer<R>(_ body: (UnsafePointer<GERamRomGameplaySetupV6>) throws -> R) rethrows -> R {
        var copy = self
        return try Swift.withUnsafePointer(to: &copy, body)
    }
}
