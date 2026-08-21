#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation
import simd

private enum GoldenEyeCastTitleHash {
    static func fnv1a(_ words: [UInt64]) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for word in words {
            var value = word.littleEndian
            withUnsafeBytes(of: &value) { bytes in
                for byte in bytes {
                    hash ^= UInt64(byte)
                    hash &*= 0x100000001b3
                }
            }
        }
        return hash
    }
}

/// The cast lowerer is deliberately separate from the RAMROM authority.  The
/// authority selects source identity/timing; this file only resolves guarded
/// GESM model packets and composes their immutable scene results.  A missing
/// body/head/weapon packet is an error, never an excuse to draw a proxy.
enum GoldenEyeCastSceneComposerV6Error: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case invalidIdentity(UInt16)
    case missingModel(UInt16, String)
    case missingAnimation(UInt32)
    case missingWeapon(UInt16)
    case missingPose
    case invalidCamera(String)
    case incompleteModel(String, UInt32)
    case emptyScene

    var description: String {
        switch self {
        case .invalidIdentity(let index):
            return "cast identity \(index) is not a valid source row"
        case .missingModel(let index, let role):
            return "cast identity \(index) has no prepared \(role) GESM model"
        case .missingAnimation(let id):
            return "cast animation \(id) has no prepared source pose stream"
        case .missingWeapon(let prop):
            return "cast weapon prop \(prop) has no prepared GESM model"
        case .missingPose:
            return "cast source pose stream is empty"
        case .invalidCamera(let detail):
            return "cast camera resources are invalid: \(detail)"
        case .incompleteModel(let name, let count):
            return "cast model \(name) has \(count) unsupported visible commands"
        case .emptyScene:
            return "cast scene contains no model results"
        }
    }
}

struct GoldenEyeCastPreparedModelBindingV6: Sendable, Equatable {
    let bodyName: String
    let headName: String
    let weaponName: String
    let bodyHandle: UInt32
    let headHandle: UInt32
    let weaponHandle: UInt32
}

/// Source Cast's name/fade overlay packet.  The identity stores the original
/// LTITLE symbol hashes; the 2D source lowerer resolves those hashes against
/// the guarded GETC payload and supplies the Zurich glyph runs.  Keeping this
/// packet beside the 3D composition prevents a renderer from inventing host
/// strings or dropping the authored fade when the actor scene is present.
struct GoldenEyeCastTextFadePacketV6: Sendable, Equatable {
    let sourceTextHashes: [UInt32]
    let textYQ16: [Int32]
    let fadeQ16: Int32
    let fadeAlphaQ8: UInt8
    let colorRGBA: UInt32
    let fullActorIntro: Bool
    let fadeOverlayRequired: Bool
    let sourceOrderHash: UInt64

    var visibleTextHashes: [UInt32] {
        // front.c emits text1 only while full_actor_intro is false; text2
        // and text3 are always emitted.  Keep this source polarity explicit
        // for the downstream 2D lowerer, whose historical parameter name is
        // inverted relative to the C branch.
        fullActorIntro ? Array(sourceTextHashes.dropFirst()) : sourceTextHashes
    }

    var source2DFullActorIntro: Bool { !fullActorIntro }
}

/// Source Cast's value-only camera/matrix setup.  The original constructor
/// uses a 46 degree perspective, a 10..2000 depth range, and a look-at basis
/// whose translation is deliberately not multiplied by the model scale.  The
/// helper is shared by the capture and Release request paths so camera
/// framing cannot silently fall back to the Legal title matrices.
enum GoldenEyeCastCameraResourcesV6 {
    static let viewportHandle: UInt32 = 0x9000_0001
    private static let cameraHandle: UInt32 = 0xF700_0701
    private static let projectionHandle: UInt32 = 0xF700_0702
    private static let reflectionHandle: UInt32 = 0xF700_0703

    static func make(
        modelMatrixHandles: [UInt32],
        distanceQ16: Int32,
        angleQ16: Int32,
        heightQ16: Int32,
        rootOffsetQ16: SIMD3<Int32> = SIMD3(repeating: 0),
        targetOffsetQ16: SIMD3<Int32> = SIMD3(repeating: 0),
        viewportWidth: UInt32 = 440,
        viewportHeight: UInt32 = 330
    ) throws -> GoldenEyeSourceProductFrameResourcesV6 {
        let handles = Array(Set(modelMatrixHandles.filter { $0 != 0 })).sorted()
        guard !handles.isEmpty, viewportWidth > 0, viewportHeight > 0 else {
            throw GoldenEyeCastSceneComposerV6Error.invalidCamera("matrix handles/viewport")
        }
        let distance = Float(distanceQ16) / 65_536.0
        let angle = Float(angleQ16) / 65_536.0
        let height = Float(heightQ16) / 65_536.0
        let root = SIMD3<Float>(
            Float(rootOffsetQ16.x) / 65_536.0,
            Float(rootOffsetQ16.y) / 65_536.0,
            Float(rootOffsetQ16.z) / 65_536.0
        )
        let targetRoot = SIMD3<Float>(
            Float(targetOffsetQ16.x) / 65_536.0,
            Float(targetOffsetQ16.y) / 65_536.0,
            Float(targetOffsetQ16.z) / 65_536.0
        )
        let cameraX = distance * sin(angle) + cos(angle) * 0.2 * distance + root.x
        let cameraY = height + 52.5 + root.y
        let cameraZ = distance * cos(angle) - sin(angle) * 0.2 * distance + root.z
        let targetX = cos(angle) * 0.2 * distance + targetRoot.x
        let targetY = targetRoot.y
        let targetZ = -sin(angle) * 0.2 * distance + targetRoot.z
        let eye = SIMD3<Float>(cameraX, cameraY, cameraZ)
        let target = SIMD3<Float>(targetX, targetY, targetZ)
        let forward = simd_normalize(target - eye)
        let up = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(forward, up))
        let correctedUp = simd_cross(right, forward)
        let camera: [Float] = [
            right.x, correctedUp.x, -forward.x, 0,
            right.y, correctedUp.y, -forward.y, 0,
            right.z, correctedUp.z, -forward.z, 0,
            -simd_dot(right, eye), -simd_dot(correctedUp, eye), simd_dot(forward, eye), 1,
        ]
        let f = 1.0 / tan(Double(46.0) * .pi / 360.0)
        let aspect = Double(viewportWidth) / Double(viewportHeight)
        let near = 10.0
        let far = 2_000.0
        let projection: [Float] = [
            Float(f / aspect), 0, 0, 0,
            0, Float(f), 0, 0,
            0, 0, Float((far + near) / (near - far)), -1,
            0, 0, Float((2.0 * far * near) / (near - far)), 0,
        ]
        let cameraQ16 = pack(camera)
        let projectionQ16 = pack(projection)
        var matrices: [GoldenEyeGBIMatrixResourceV6] = []
        matrices.reserveCapacity(handles.count + 3)
        for handle in handles {
            try matrices.append(.init(
                handle: handle, values: cameraQ16,
                roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView
            ))
        }
        try matrices.append(.init(
            handle: cameraHandle, values: cameraQ16,
            roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.camera
        ))
        try matrices.append(.init(
            handle: projectionHandle, values: projectionQ16,
            roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.projection
        ))
        try matrices.append(.init(
            handle: reflectionHandle, values: cameraQ16,
            roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.reflection
        ))
        let viewport = try GoldenEyeGBIViewportResourceV6(
            handle: viewportHandle,
            values: [
                Int32(viewportWidth / 2) << 16,
                Int32(viewportHeight / 2) << 16,
                1 << 16, 1 << 16,
                Int32(viewportWidth / 2) << 16,
                Int32(viewportHeight / 2) << 16,
                0, 1 << 16,
            ]
        )
        return try GoldenEyeSourceProductFrameResourcesV6(
            matrices: matrices, viewports: [viewport],
            viewportWidth: viewportWidth, viewportHeight: viewportHeight
        )
    }

    private static func pack(_ values: [Float]) -> [Int32] {
        values.map { value in
            let scaled = (Double(value) * 65_536.0).rounded()
            return Int32(clamping: Int64(scaled))
        }
    }
}

/// Source `constructor_menu18_displaycast` camera/root smoothing.  The
/// frontend keeps root position and target velocity as two damped state
/// accumulators; this value-only adapter preserves that ordering for the
/// native Cast frame producer without importing the N64 model scheduler.
struct GoldenEyeCastCameraStateV6: Sendable, Equatable {
    static let damp: Float = 0.94999999
    static let dampComplement: Float = 0.050000012

    private(set) var rootPosition: SIMD3<Float> = .zero
    private(set) var rootVelocityAccumulator: SIMD3<Float> = .zero
    private(set) var targetAccumulator: SIMD3<Float> = .zero
    private(set) var reset = true

    mutating func update(
        suboffset: SIMD3<Float>,
        transformedVelocity: SIMD3<Float>,
        clockTimer: UInt32 = 1,
        globalTimerDelta: Float = 1
    ) -> (rootOffset: SIMD3<Float>, targetOffset: SIMD3<Float>) {
        precondition(globalTimerDelta > 0)
        precondition(clockTimer <= 4)
        if reset {
            rootPosition.y = suboffset.y
        }
        let velocity = (suboffset - rootPosition) / globalTimerDelta
        if reset {
            rootVelocityAccumulator = velocity / Self.dampComplement
        }
        for _ in 0..<clockTimer {
            rootVelocityAccumulator = velocity + Self.damp * rootVelocityAccumulator
        }
        let rootVelocity = rootVelocityAccumulator * Self.dampComplement
        rootPosition += rootVelocity * globalTimerDelta

        let target = transformedVelocity - rootPosition
        if reset {
            targetAccumulator = target / Self.dampComplement
        }
        for _ in 0..<clockTimer {
            targetAccumulator = target + Self.damp * targetAccumulator
        }
        let targetSmoothed = targetAccumulator * Self.dampComplement
        reset = false
        return (
            rootOffset: rootPosition,
            targetOffset: SIMD3(
                rootPosition.x + targetSmoothed.x,
                rootPosition.y + targetSmoothed.y - 10,
                rootPosition.z + targetSmoothed.z
            )
        )
    }
}

/// Source-randomized cast selection with a bounded copied random word.  The
/// source table contains four sentinel slots after the thirty real entries;
/// those slots are never eligible for production or capture selection.
enum GoldenEyeCastSceneComposerV6 {
    static let validIdentityIndices: [UInt16] = Array(0..<30)

    static func textFadePacket(
        identity: GoldenEyeCastIdentityV6,
        fadeQ16: Int32,
        fullActorIntro: Bool
    ) throws -> GoldenEyeCastTextFadePacketV6 {
        guard (0...65_536).contains(fadeQ16) else {
            throw GoldenEyeCastSceneComposerV6Error.invalidIdentity(identity.sourceIndex)
        }
        let hashes = [
            identity.text1SourceID,
            identity.text2SourceID,
            identity.text3SourceID,
        ]
        guard hashes.count == 3, hashes.allSatisfy({ $0 != 0 }) else {
            throw GoldenEyeCastSceneComposerV6Error.invalidIdentity(identity.sourceIndex)
        }
        let alpha = UInt8(clamping: Int((Int64(fadeQ16) * 255 + 32_768) >> 16))
        let ys = [108, 152, 174].map { Int32($0) << 16 }
        let orderHash = GoldenEyeCastTitleHash.fnv1a(
            hashes.map(UInt64.init) + ys.map { UInt64(bitPattern: Int64($0)) }
        )
        return GoldenEyeCastTextFadePacketV6(
            sourceTextHashes: hashes,
            textYQ16: ys,
            fadeQ16: fadeQ16,
            fadeAlphaQ8: alpha,
            colorRGBA: 0xFFFF_FF00 | UInt32(alpha),
            fullActorIntro: fullActorIntro,
            fadeOverlayRequired: alpha < 255,
            sourceOrderHash: orderHash == 0 ? 1 : orderHash
        )
    }

    /// The bounded prepared set reachable from the thirty source rows and
    /// their source weapon pools.  Keeping this manifest beside resolution
    /// makes an incomplete extended root fail during preparation rather than
    /// after a production Cast transition.
    static let requiredPreparedModelNames: Set<String> = [
        "greyguard", "oliveguard", "rusguard", "djbond", "boris", "orumov",
        "boilertrev", "valentin", "xenia", "greatguard", "commguard",
        "armourguard", "navyguard", "snowguard", "boilerbond", "techwoman",
        "jeanwoman", "greyman", "blueman", "redman", "cardiman", "techman",
        "pilot", "bluecamguard", "moonguard", "moonfemale", "baronsamedi",
        "jaws", "mayday", "oddjob",
        "headkarl", "headalan", "headpete", "headmartin", "headmark",
        "headduncan", "headshaun", "headdwayne", "headb", "headdave",
        "headgrant", "headdes", "headchris", "headlee", "headneil", "headjim",
        "headrobin", "headsteveh", "headjoel", "headscott", "headjoe", "headken",
        "headjoe2", "headstevee", "headgraham", "headsally", "headmarion",
        "headmandy", "headvivien", "headmishkin", "headbrosnanboiler",
        "headbrosnansuit", "headbrosnan",
        "chrkalash", "chrm16", "chrfnp90", "chrautoshot", "chrgrenadelaunch",
        "chrsniperrifle", "chrwppk", "chrwppksil", "chrskorpion", "chruzi",
        "chrruger", "chrlaser", "chrgolden",
        "spicebond",
    ]

    static func selectIdentity(randomWord: UInt32) throws -> GoldenEyeCastIdentityV6 {
        let index = validIdentityIndices[Int(randomWord % UInt32(validIdentityIndices.count))]
        return try GoldenEyeCastSourceTableV6.identity(sourceIndex: index)
    }

    static func animation(for identity: GoldenEyeCastIdentityV6)
        throws -> GoldenEyeCastAnimationV6
    {
        // front.c selects the authored animation independently from the
        // thirty-row identity table. This identity-derived helper remains a
        // deterministic fixture entry point, so wrap the row rather than
        // treating identities 22...29 as missing animation assets.
        let count = GoldenEyeCastSourceTableV6.animations.count
        guard count > 0 else {
            throw GoldenEyeCastSceneComposerV6Error.missingAnimation(UInt32(identity.sourceIndex))
        }
        return try GoldenEyeCastSourceTableV6.animation(
            sourceIndex: UInt16(Int(identity.sourceIndex) % count)
        )
    }

    static func animation(randomWord: UInt32) throws -> GoldenEyeCastAnimationV6 {
        let index = UInt16(randomWord % UInt32(GoldenEyeCastSourceTableV6.animations.count))
        return try GoldenEyeCastSourceTableV6.animation(sourceIndex: index)
    }

    /// Resolve only packets whose source identity is actually represented by
    /// the prepared catalog.  At this stage the guarded frontend catalog has
    /// Bond's body/head/PP7 packets (the same packets used by the source
    /// Gunbarrel lane); all other cast rows fail closed until their distinct
    /// source GESM packets are prepared.
    static func resolveModels(
        identity: GoldenEyeCastIdentityV6,
        animation: GoldenEyeCastAnimationV6,
        availableModelNames: Set<String>,
        availableHandles: [String: UInt32],
        randomWord: UInt32 = 0,
        requestedWeaponPropID: UInt16? = nil
    ) throws -> GoldenEyeCastPreparedModelBindingV6 {
        guard identity.sourceIndex < 30 else {
            throw GoldenEyeCastSceneComposerV6Error.invalidIdentity(identity.sourceIndex)
        }
        // front.c consumes one additional random word for Natalya's alternate
        // jungle-fatigues body. Keep the roster row immutable while resolving
        // the selected model packet from that same random bit.
        let resolvedBodyID: UInt16 =
            identity.sourceIndex == 2 && identity.bodyID == 16 && (randomWord & 1) != 0
                ? 79
                : identity.bodyID
        guard let body = bodyName(for: resolvedBodyID),
              availableModelNames.contains(body) else {
            throw GoldenEyeCastSceneComposerV6Error.missingModel(identity.sourceIndex, "body")
        }
        let head = try headName(
            for: identity,
            bodyName: body,
            availableModelNames: availableModelNames,
            randomWord: randomWord
        )
        let weapon = try weaponName(
            animation: animation,
            availableModelNames: availableModelNames,
            randomWord: randomWord,
            requestedPropID: requestedWeaponPropID
        )
        let names = (body: body, head: head, weapon: weapon)
        for name in [body, head, weapon] where !name.isEmpty {
            guard availableModelNames.contains(name) else {
                throw GoldenEyeCastSceneComposerV6Error.missingModel(identity.sourceIndex, name)
            }
        }
        guard let bodyHandle = availableHandles[names.body], bodyHandle != 0,
              (head.isEmpty || (availableHandles[head] ?? 0) != 0),
              (weapon.isEmpty || (availableHandles[weapon] ?? 0) != 0) else {
            throw GoldenEyeCastSceneComposerV6Error.missingModel(
                identity.sourceIndex, "model handle"
            )
        }
        return GoldenEyeCastPreparedModelBindingV6(
            bodyName: names.body, headName: names.head, weaponName: names.weapon,
            bodyHandle: bodyHandle, headHandle: availableHandles[head] ?? 0,
            weaponHandle: availableHandles[weapon] ?? 0
        )
    }

    private static func bodyName(for bodyID: UInt16) -> String? {
        let names: [UInt32: String] = [
            1: "greyguard", 2: "oliveguard", 3: "rusguard", 5: "djbond",
            6: "boris", 7: "orumov", 9: "boilertrev", 10: "valentin",
            11: "xenia", 12: "baronsamedi", 13: "jaws", 14: "mayday",
            15: "oddjob", 16: "natalya", 17: "armourguard", 18: "commguard",
            19: "greatguard", 20: "navyguard", 21: "snowguard", 22: "boilerbond",
            28: "techwoman", 29: "jeanwoman", 30: "greyman", 31: "blueman",
            32: "redman", 33: "cardiman", 35: "techman", 36: "pilot",
            38: "bluecamguard", 39: "moonguard", 40: "moonfemale",
            79: "spicebond",
        ]
        return names[UInt32(bodyID)]
    }

    private static func headName(
        for identity: GoldenEyeCastIdentityV6,
        bodyName: String,
        availableModelNames: Set<String>,
        randomWord: UInt32
    ) throws -> String {
        // hasHead is the source c_item_entries flag. Embedded-head bodies do
        // not receive a second model even when intro_char_table says random.
        let embeddedHeadBodies: Set<String> = [
            "boris", "orumov", "trevelyan", "boilertrev", "valentin", "xenia",
            "baronsamedi", "jaws", "mayday", "oddjob", "natalya", "snowguard",
            "pilot", "spicebond",
        ]
        if embeddedHeadBodies.contains(bodyName) || identity.headID == GoldenEyeCastIdentityV6.headFixed && identity.sourceIndex != 0 && identity.sourceIndex != 1 && identity.sourceIndex != 8 {
            return ""
        }
        let headID: UInt32
        if identity.hasRandomHead {
            let male: [UInt32] = [57, 54, 55, 62, 59, 56, 58, 53, 52, 51, 42, 43, 44, 45, 46, 47, 49, 50, 48, 63, 64, 65, 66, 67, 68]
            let female: [UInt32] = [70, 71, 72, 73]
            let pool = bodyName == "techwoman" || bodyName == "jeanwoman" || bodyName == "moonfemale" ? female : male
            headID = pool[Int(randomWord % UInt32(pool.count))]
        } else {
            headID = identity.headID
        }
        let names: [UInt32: String] = [
            42: "headkarl", 43: "headalan", 44: "headpete", 45: "headmartin", 46: "headmark",
            47: "headduncan", 48: "headb", 49: "headshaun", 50: "headdwayne", 51: "headdave",
            52: "headgrant", 53: "headdes", 54: "headchris", 55: "headlee", 56: "headneil",
            57: "headjim", 58: "headrobin", 59: "headsteveh", 62: "headgraham", 63: "headstevee",
            64: "headjoel", 65: "headscott", 66: "headjoe", 67: "headken", 68: "headjoe2",
            69: "headmishkin", 70: "headsally", 71: "headmarion", 72: "headmandy", 73: "headvivien",
            74: "headbrosnanboiler", 75: "headbrosnansuit", 78: "headbrosnan",
        ]
        guard let name = names[headID], availableModelNames.contains(name) else {
            throw GoldenEyeCastSceneComposerV6Error.missingModel(identity.sourceIndex, "head \(headID)")
        }
        return name
    }

    private static func weaponName(
        animation: GoldenEyeCastAnimationV6,
        availableModelNames: Set<String>,
        randomWord: UInt32,
        requestedPropID: UInt16? = nil
    ) throws -> String {
        guard animation.usesWeaponCamera else { return "" }
        let rifle = ["chrkalash", "chrm16", "chrfnp90", "chrautoshot", "chrgrenadelaunch", "chrsniperrifle"]
        let pistol = ["chrwppk", "chrwppksil", "chrskorpion", "chruzi", "chrruger", "chrlaser", "chrgolden"]
        let pool = animation.cameraPreset == 2 ? rifle : pistol
        if let requestedPropID {
            let sourcePool = animation.cameraPreset == 2
                ? GoldenEyeCastSourceTableV6.rifleWeapons
                : GoldenEyeCastSourceTableV6.pistolWeapons
            if let index = sourcePool.firstIndex(where: { $0.propID == requestedPropID }),
               pool.indices.contains(index), availableModelNames.contains(pool[index]) {
                return pool[index]
            }
            throw GoldenEyeCastSceneComposerV6Error.missingWeapon(requestedPropID)
        }
        let available = pool.filter(availableModelNames.contains)
        guard !available.isEmpty else { throw GoldenEyeCastSceneComposerV6Error.missingWeapon(0) }
        return available[Int(randomWord % UInt32(available.count))]
    }

    /// Convert the dynamic source pose records into the cast's fixed-width
    /// frame contract.  The records remain the renderer's authoritative pose
    /// payload; this compact copy is only route/state evidence.
    #if canImport(GoldenEyeNative)
    static func pose(from records: [GESourceAnimationPoseV6]) throws -> GoldenEyeCastPoseV6 {
        guard !records.isEmpty else { throw GoldenEyeCastSceneComposerV6Error.missingPose }
        let nodeIndices = Dictionary(uniqueKeysWithValues: records.enumerated().map {
            ($0.element.node_handle, UInt16($0.offset))
        })
        let joints = records.enumerated().map { offset, record in
            GoldenEyeCastJointPoseV6(
                jointIndex: UInt16(offset),
                parentIndex: nodeIndices[record.parent_handle] ?? UInt16.max,
                rotationXQ16: record.rotation_q16.0,
                rotationYQ16: record.rotation_q16.1,
                rotationZQ16: record.rotation_q16.2,
                translationXQ16: record.translation_q16.0,
                translationYQ16: record.translation_q16.1,
                translationZQ16: record.translation_q16.2,
                scaleQ16: record.scale_q16.0
            )
        }
        var sourceHash = GoldenEyeCastSceneV6Hash.offsetBasis
        for record in records {
            sourceHash = GoldenEyeCastSceneV6Hash.mix(sourceHash, record.pose_hash)
        }
        return try GoldenEyeCastPoseV6(sourcePoseHash: sourceHash, joints: joints)
    }
    #endif

    static func compose(
        _ results: [GoldenEyeGBISceneBuildResultV6],
        frame: GoldenEyeGBISceneFrameContextV6
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        guard !results.isEmpty else { throw GoldenEyeCastSceneComposerV6Error.emptyScene }
        for result in results {
            guard result.presentable,
                  result.unsupportedVisibleCount == 0,
                  !result.snapshot.drawCommands.isEmpty else {
                throw GoldenEyeCastSceneComposerV6Error.incompleteModel(
                    "unknown", result.unsupportedVisibleCount
                )
            }
        }
        let snapshot = try GoldenEyeSourceSceneComposerV6.combine(results, frame: frame)
        // The V6 scene screen enum is additive to the frontend screen enum;
        // CAST is the fixed value 7 in ge_source_scene_v6.h.
        guard snapshot.summary.screen == 7,
              snapshot.summary.unsupported_visible_count == 0,
              snapshot.summary.draw_count > 0 else {
            throw GoldenEyeCastSceneComposerV6Error.emptyScene
        }
        return snapshot
    }
}
