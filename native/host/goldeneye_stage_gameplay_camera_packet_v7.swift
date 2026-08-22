import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Categories that a gameplay-camera packet may explicitly claim as visible.
/// The first production slice is deliberately limited to room triangles and
/// static setup props.  Characters, AI, effects, and other dynamic pages must
/// be named by the caller before a future lowerer can make them presentable.
enum GoldenEyeStageGameplayCameraVisibleCategoryV7: String, Sendable, Equatable, Hashable, CaseIterable {
    case roomGeometry = "room_geometry"
    case staticProps = "static_props"
    case characters = "characters"
    case ai = "ai"
    case effects = "effects"
}

/// A copied demo/stage/player-camera request.  Room and prop visibility are
/// explicit source-facing IDs; no owner object, pointer, ROM offset, or
/// renderer state crosses this boundary.
struct GoldenEyeStageGameplayCameraSnapshotV7: Sendable, Equatable {
    let demoID: UInt8
    let stageID: UInt32
    let nativeTick: UInt64
    let playerCamera: GoldenEyeStagePlayerCameraSnapshotInputV6
    let visibleRoomIndices: [UInt32]
    let visibleStaticPropObjectIndices: [UInt32]
    let dynamicPropTransforms: [GoldenEyeStageGameplayCameraDynamicPropV7]
    let visibleCategories: [GoldenEyeStageGameplayCameraVisibleCategoryV7]
    let viewportWidth: UInt32
    let viewportHeight: UInt32

    init(
        demoID: UInt8,
        stageID: UInt32,
        nativeTick: UInt64,
        playerCamera: GoldenEyeStagePlayerCameraSnapshotInputV6,
        visibleRoomIndices: [UInt32],
        visibleStaticPropObjectIndices: [UInt32],
        dynamicPropTransforms: [GoldenEyeStageGameplayCameraDynamicPropV7] = [],
        visibleCategories: [GoldenEyeStageGameplayCameraVisibleCategoryV7] = [
            .roomGeometry, .staticProps,
        ],
        viewportWidth: UInt32 = GoldenEyeProjectionV10.canonicalWidth,
        viewportHeight: UInt32 = GoldenEyeProjectionV10.canonicalHeight
    ) {
        self.demoID = demoID
        self.stageID = stageID
        self.nativeTick = nativeTick
        self.playerCamera = playerCamera
        self.visibleRoomIndices = visibleRoomIndices
        self.visibleStaticPropObjectIndices = visibleStaticPropObjectIndices
        self.dynamicPropTransforms = dynamicPropTransforms
        self.visibleCategories = visibleCategories
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
    }
}

struct GoldenEyeStageGameplayCameraDynamicPropV7: Sendable, Equatable {
    let objectIndex: UInt32
    let transformQ16: [Int32]
    let sourceHash: UInt64
    let openState: UInt32
    let portalNumber: UInt32

    init(
        objectIndex: UInt32,
        transformQ16: [Int32],
        sourceHash: UInt64,
        openState: UInt32 = 0,
        portalNumber: UInt32 = UInt32.max
    ) {
        self.objectIndex = objectIndex
        self.transformQ16 = transformQ16
        self.sourceHash = sourceHash
        self.openState = openState
        self.portalNumber = portalNumber
    }
}

/// Deterministic evidence for the exact subset that a scoped packet claims.
/// `fullSceneUnsupportedMask` is retained separately so a presentable scoped
/// frame cannot be mistaken for full-stage parity.
struct GoldenEyeStageGameplayCameraSubsetMetadataV7: Sendable, Equatable {
    static let contractVersion: UInt32 = 1

    let contractVersionValue: UInt32
    let visibleCategories: [String]
    let omittedCategories: [String]
    let visibleRoomIndices: [UInt32]
    let visibleStaticPropObjectIndices: [UInt32]
    let roomGeometryCommandCount: UInt32
    let staticPropPlacementCount: UInt32
    let drawableStaticPropPlacementCount: UInt32
    let unsupportedMask: UInt32
    let fullSceneUnsupportedMask: UInt32
    let metadataHash: UInt64

    init(
        visibleCategories: [GoldenEyeStageGameplayCameraVisibleCategoryV7],
        visibleRoomIndices: [UInt32],
        visibleStaticPropObjectIndices: [UInt32],
        roomGeometryCommandCount: UInt32,
        staticPropPlacementCount: UInt32,
        drawableStaticPropPlacementCount: UInt32,
        unsupportedMask: UInt32,
        fullSceneUnsupportedMask: UInt32
    ) {
        self.contractVersionValue = Self.contractVersion
        self.visibleCategories = visibleCategories.sorted(by: { $0.rawValue < $1.rawValue }).map(\.rawValue)
        self.omittedCategories = GoldenEyeStageGameplayCameraVisibleCategoryV7.allCases
            .filter { !visibleCategories.contains($0) }
            .sorted(by: { $0.rawValue < $1.rawValue })
            .map(\.rawValue)
        self.visibleRoomIndices = visibleRoomIndices.sorted()
        self.visibleStaticPropObjectIndices = visibleStaticPropObjectIndices.sorted()
        self.roomGeometryCommandCount = roomGeometryCommandCount
        self.staticPropPlacementCount = staticPropPlacementCount
        self.drawableStaticPropPlacementCount = drawableStaticPropPlacementCount
        self.unsupportedMask = unsupportedMask
        self.fullSceneUnsupportedMask = fullSceneUnsupportedMask

        var hash = Self.offsetBasis
        hash = Self.mix(hash, UInt64(Self.contractVersion))
        for category in self.visibleCategories {
            for byte in category.utf8 { hash = Self.mix(hash, UInt64(byte)) }
        }
        for room in self.visibleRoomIndices { hash = Self.mix(hash, UInt64(room)) }
        for object in self.visibleStaticPropObjectIndices { hash = Self.mix(hash, UInt64(object)) }
        for value in [
            UInt64(roomGeometryCommandCount), UInt64(staticPropPlacementCount),
            UInt64(drawableStaticPropPlacementCount), UInt64(unsupportedMask),
            UInt64(fullSceneUnsupportedMask),
        ] {
            hash = Self.mix(hash, value)
        }
        metadataHash = hash
    }

    private static let offsetBasis: UInt64 = 1_469_598_103_934_665_603

    private static func mix(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 56, by: 8) {
            result = (result ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
        }
        return result == 0 ? 1 : result
    }
}

/// The bounded result handed to a future owner/render submission seam.  The
/// environment packet and composed snapshot are copied value records; this
/// adapter retains no mutable stage owner or Metal object.
struct GoldenEyeStageGameplayCameraPacketV7: @unchecked Sendable {
    static let expectedFullSceneUnsupportedMask: UInt32 =
        GoldenEyeStageBackgroundDrawPacket.unsupportedCharacters |
        GoldenEyeStageBackgroundDrawPacket.unsupportedAI |
        GoldenEyeStageBackgroundDrawPacket.unsupportedEffects

    let demoID: UInt8
    let stageID: UInt32
    let nativeTick: UInt64
    let cameraInput: GoldenEyeStageEnvironmentCameraInputV6
    let environmentPacket: GoldenEyeStageBackgroundDrawPacket
    let composition: GoldenEyeStageModelSceneCompositionV6.Result
    let subset: GoldenEyeStageGameplayCameraSubsetMetadataV7
    let packetHash: UInt64

    var isPresentable: Bool {
        composition.isPresentable && subset.unsupportedMask == 0
    }
}

enum GoldenEyeStageGameplayCameraPacketV7Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
    case invalidSnapshot
    case stageMismatch(UInt32, UInt32)
    case unsupportedVisibleCategory(GoldenEyeStageGameplayCameraVisibleCategoryV7)
    case missingVisibleCategory(GoldenEyeStageGameplayCameraVisibleCategoryV7)
    case invalidVisibleRoom(UInt32)
    case invalidStaticProp(UInt32)
    case invalidDynamicProp(UInt32)
    case duplicateVisibleIndex(UInt32)
    case fullSceneUnsupportedMask(UInt32)
    case scopedUnsupportedMask(UInt32)
    case scopedComposition(String)

    var description: String {
        switch self {
        case .invalidSnapshot:
            return "gameplay-camera packet snapshot is invalid"
        case let .stageMismatch(expected, actual):
            return "gameplay-camera packet stage \(actual) does not match \(expected)"
        case let .unsupportedVisibleCategory(category):
            return "gameplay-camera packet cannot lower visible category \(category.rawValue)"
        case let .missingVisibleCategory(category):
            return "gameplay-camera packet is missing required visible category \(category.rawValue)"
        case let .invalidVisibleRoom(room):
            return "gameplay-camera packet visible room \(room) is not in the source scene"
        case let .invalidStaticProp(index):
            return "gameplay-camera packet object \(index) is not a static prop"
        case let .invalidDynamicProp(index):
            return "gameplay-camera dynamic prop \(index) is not a valid static prop transform"
        case let .duplicateVisibleIndex(index):
            return "gameplay-camera packet repeats visible source index \(index)"
        case let .fullSceneUnsupportedMask(mask):
            return "full stage composition changed unsupported mask to 0x\(String(mask, radix: 16))"
        case let .scopedUnsupportedMask(mask):
            return "scoped gameplay-camera composition remains unsupported (mask=0x\(String(mask, radix: 16)))"
        case let .scopedComposition(detail):
            return "scoped gameplay-camera composition failed: \(detail)"
        }
    }
}

/// Builds a demo-scoped gameplay-camera packet from the existing source room,
/// material, Projection V10, and static-model contracts.  The full scene is
/// composed first as a guard: it must still report the established `0x38`
/// character/AI/effects gap before the scoped packet can clear anything.
enum GoldenEyeStageGameplayCameraPacketAdapterV7 {
    // Pad-backed static/door/glass records only. Collectables, ammo,
    // monitors, autoguns, gas, vehicles, and other runtime-owned pages stay
    // outside this V7 scope until their authoritative owner snapshots exist.
    private static let staticPropTypes: Set<UInt32> = [
        1, 3, 4, 5, 12, 17, 42, 43, 47,
    ]

    /// Return the source setup rows that this bounded lowerer can actually
    /// submit. The owner uses this copied index list to declare the visible
    /// subset; characters/objectives are never silently reclassified as props.
    static func staticPropObjectIndices(in scene: GoldenEyeStageScenePacket) -> [UInt32] {
        scene.setup.objects
            .filter { staticPropTypes.contains($0.type) }
            .map(\.index)
            .sorted()
    }

    static func staticPropObjectIndices(
        in scene: GoldenEyeStageScenePacket,
        visiblePropModelIndices: Set<UInt32>
    ) -> [UInt32] {
        scene.setup.objects
            .filter {
                staticPropTypes.contains($0.type)
                    && visiblePropModelIndices.contains($0.key0)
            }
            .map(\.index)
            .sorted()
    }

    static func make(
        scene: GoldenEyeStageScenePacket,
        snapshot: GoldenEyeStageGameplayCameraSnapshotV7,
        materialPacket: GoldenEyeStageSourceMaterialPacketV6? = nil,
        stageTextures: GoldenEyeStageTextureCatalogV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        setupDependencies: GoldenEyeStageSetupDependencyCatalogV6,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6
    ) throws -> GoldenEyeStageGameplayCameraPacketV7 {
        try validate(snapshot: snapshot, scene: scene)

        let cameraInput = try GoldenEyeStageEnvironmentCameraAdapterV6.input(
            scene: scene,
            snapshot: snapshot.playerCamera,
            visibleRoomIndices: snapshot.visibleRoomIndices,
            viewportWidth: snapshot.viewportWidth,
            viewportHeight: snapshot.viewportHeight
        )
        guard cameraInput.modelView != .identity,
              cameraInput.projection != .identity else {
            throw GoldenEyeStageGameplayCameraPacketV7Error.invalidSnapshot
        }
        let material = try materialPacket ?? GoldenEyeStageSourceMaterialLowererV6.make(scene: scene)
        let frameResources = try makeFrameResources(camera: cameraInput)
        // Keep the full-scene category guard independent of gameplay-camera
        // clipping.  The established 0x38 gap is a visibility-category
        // contract; a world-space prop outside one camera frustum must not
        // turn that guard into a false prop/material failure.
        let fullGuardFrameResources = try makeFrameResources(
            modelView: .identity,
            projection: .identity,
            viewportWidth: cameraInput.viewportWidth,
            viewportHeight: cameraInput.viewportHeight
        )
        let projection = try makeProjection(camera: cameraInput)
        let visibleRooms = Set(cameraInput.visibleRoomIndices)
        let roomOrigin = GoldenEyeProjectionV10.PointQ16(
            x: cameraInput.roomOriginQ16.x,
            y: cameraInput.roomOriginQ16.y,
            z: cameraInput.roomOriginQ16.z
        )
        let roomScale = Double(cameraInput.roomCoordinateScaleQ16) / 65_536.0

        // First compose the complete source setup.  This records the existing
        // full-scene gap and prevents the scoped path from hiding a new
        // unsupported prop/material failure behind a subset claim.
        guard let fullGuardViewport = GoldenEyeProjectionV10.ViewportV10(
            drawableWidth: cameraInput.viewportWidth,
            drawableHeight: cameraInput.viewportHeight
        ), let fullGuardProjection = GoldenEyeProjectionV10.PacketV10(
            viewport: fullGuardViewport,
            modelView: .identity,
            projection: .identity
        ) else {
            throw GoldenEyeStageGameplayCameraPacketV7Error.invalidSnapshot
        }
        let fullEnvironment = try GoldenEyeStageSourceEnvironmentDrawPacketBuilderV6.make(
            scene: scene,
            viewport: fullGuardViewport,
            projection: fullGuardProjection,
            environmentOnlyCapture: false
        )
        let fullComposition = try GoldenEyeStageModelSceneCompositionV6.make(
            stageScene: scene,
            environmentPacket: fullEnvironment,
            materialPacket: material,
            sidecars: sidecars,
            setupDependencies: setupDependencies,
            stageTextures: stageTextures,
            frameResources: fullGuardFrameResources,
            nativeTick: snapshot.nativeTick,
            demoID: snapshot.demoID,
            visibleDependencies: visibleDependencies,
            // Preserve the full-scene category evidence even when a
            // non-presentable prop draw has no exact fog sidecar. The scoped
            // composition below remains strict and fails closed on that gap.
            requireExactFogCoordinates: false
        )
        guard fullComposition.unsupportedMask == GoldenEyeStageGameplayCameraPacketV7.expectedFullSceneUnsupportedMask else {
            throw GoldenEyeStageGameplayCameraPacketV7Error.fullSceneUnsupportedMask(
                fullComposition.unsupportedMask
            )
        }

        let scopedScene = try makeScopedScene(
            scene: scene,
            visibleStaticPropObjectIndices: snapshot.visibleStaticPropObjectIndices,
            dynamicPropTransforms: snapshot.dynamicPropTransforms,
            cameraModelView: cameraInput.modelView,
            setupDependencies: setupDependencies
        )
        // `environmentOnlyCapture` is permitted only after the full-scene
        // guard above and only for the explicit room+static-prop subset.  It
        // does not change the full-scene result or its retained 0x38 evidence.
        let scopedEnvironment = try GoldenEyeStageSourceEnvironmentDrawPacketBuilderV6.make(
            scene: scopedScene,
            viewport: projection.viewport,
            projection: projection,
            environmentOnlyCapture: true,
            visibleRoomIndices: visibleRooms,
            roomCoordinateScale: roomScale,
            roomOrigin: roomOrigin
        )
        let rawScopedComposition = try GoldenEyeStageModelSceneCompositionV6.make(
            stageScene: scopedScene,
            environmentPacket: scopedEnvironment,
            materialPacket: material,
            sidecars: sidecars,
            setupDependencies: setupDependencies,
            stageTextures: stageTextures,
            frameResources: frameResources,
            nativeTick: snapshot.nativeTick,
            demoID: snapshot.demoID,
            visibleDependencies: visibleDependencies,
            requireExactFogCoordinates: true,
            scopedCategoryNames: Set(["props"])
        )
        guard rawScopedComposition.propPlacementCount ==
                UInt32(snapshot.visibleStaticPropObjectIndices.count) else {
            // A dependency manifest that omits one requested source object is
            // not a valid visible subset.  Do not silently shrink the scope
            // and present the remaining props as complete.
            throw GoldenEyeStageGameplayCameraPacketV7Error.scopedComposition(
                "visible dependency catalog omitted a requested static prop"
            )
        }
        let scopedComposition = try scopedPresentableComposition(
            rawScopedComposition,
            visibleCategories: snapshot.visibleCategories
        )
        guard scopedComposition.unsupportedMask == 0,
              scopedComposition.snapshot.summary.unsupported_visible_count == 0,
              !scopedComposition.snapshot.drawCommands.isEmpty else {
            throw GoldenEyeStageGameplayCameraPacketV7Error.scopedUnsupportedMask(
                scopedComposition.unsupportedMask
            )
        }

        let subset = GoldenEyeStageGameplayCameraSubsetMetadataV7(
            visibleCategories: snapshot.visibleCategories,
            visibleRoomIndices: snapshot.visibleRoomIndices,
            visibleStaticPropObjectIndices: snapshot.visibleStaticPropObjectIndices,
            roomGeometryCommandCount: scopedEnvironment.commandCount,
            staticPropPlacementCount: scopedComposition.propPlacementCount,
            drawableStaticPropPlacementCount: scopedComposition.drawablePlacementCount,
            unsupportedMask: scopedComposition.unsupportedMask,
            fullSceneUnsupportedMask: fullComposition.unsupportedMask
        )
        let packetHash = packetHash(
            snapshot: snapshot,
            camera: cameraInput,
            environment: scopedEnvironment,
            composition: scopedComposition,
            subset: subset
        )
        return GoldenEyeStageGameplayCameraPacketV7(
            demoID: snapshot.demoID,
            stageID: snapshot.stageID,
            nativeTick: snapshot.nativeTick,
            cameraInput: cameraInput,
            environmentPacket: scopedEnvironment,
            composition: scopedComposition,
            subset: subset,
            packetHash: packetHash
        )
    }

    private static func validate(
        snapshot: GoldenEyeStageGameplayCameraSnapshotV7,
        scene: GoldenEyeStageScenePacket
    ) throws {
        guard snapshot.stageID == scene.stageID,
              snapshot.nativeTick > 0,
              snapshot.playerCamera.stageID == snapshot.stageID,
              snapshot.playerCamera.nativeTick == snapshot.nativeTick,
              !snapshot.visibleRoomIndices.isEmpty,
              !snapshot.visibleStaticPropObjectIndices.isEmpty,
              snapshot.viewportWidth > 0,
              snapshot.viewportHeight > 0 else {
            if snapshot.stageID != scene.stageID {
                throw GoldenEyeStageGameplayCameraPacketV7Error.stageMismatch(
                    scene.stageID, snapshot.stageID
                )
            }
            throw GoldenEyeStageGameplayCameraPacketV7Error.invalidSnapshot
        }

        var categories = Set<GoldenEyeStageGameplayCameraVisibleCategoryV7>()
        for category in snapshot.visibleCategories {
            guard categories.insert(category).inserted else {
                throw GoldenEyeStageGameplayCameraPacketV7Error.invalidSnapshot
            }
            guard category == .roomGeometry || category == .staticProps else {
                throw GoldenEyeStageGameplayCameraPacketV7Error.unsupportedVisibleCategory(category)
            }
        }
        for category in [GoldenEyeStageGameplayCameraVisibleCategoryV7.roomGeometry,
                         .staticProps] where !categories.contains(category) {
            throw GoldenEyeStageGameplayCameraPacketV7Error.missingVisibleCategory(category)
        }

        try validateUnique(snapshot.visibleRoomIndices)
        for room in snapshot.visibleRoomIndices {
            let valid = scene.rooms.contains { $0.roomIndex == room }
                || (room > 0 && scene.rooms.contains { $0.roomIndex == room - 1 })
            guard valid else {
                throw GoldenEyeStageGameplayCameraPacketV7Error.invalidVisibleRoom(room)
            }
        }
        try validateUnique(snapshot.visibleStaticPropObjectIndices)
        for objectIndex in snapshot.visibleStaticPropObjectIndices {
            guard let object = scene.setup.objects.first(where: { $0.index == objectIndex }),
                  staticPropTypes.contains(object.type) else {
                throw GoldenEyeStageGameplayCameraPacketV7Error.invalidStaticProp(objectIndex)
            }
        }
        var dynamicIndices = Set<UInt32>()
        for dynamic in snapshot.dynamicPropTransforms {
            guard dynamicIndices.insert(dynamic.objectIndex).inserted,
                  dynamic.transformQ16.count == 16,
                  snapshot.visibleStaticPropObjectIndices.contains(dynamic.objectIndex),
                  let object = scene.setup.objects.first(where: { $0.index == dynamic.objectIndex }),
                  object.type == 1,
                  dynamic.sourceHash != 0 else {
                throw GoldenEyeStageGameplayCameraPacketV7Error.invalidDynamicProp(dynamic.objectIndex)
            }
        }
    }

    private static func validateUnique(_ values: [UInt32]) throws {
        var seen = Set<UInt32>()
        for value in values where !seen.insert(value).inserted {
            throw GoldenEyeStageGameplayCameraPacketV7Error.duplicateVisibleIndex(value)
        }
    }

    private static func makeProjection(
        camera: GoldenEyeStageEnvironmentCameraInputV6
    ) throws -> GoldenEyeProjectionV10.PacketV10 {
        guard let viewport = GoldenEyeProjectionV10.ViewportV10(
            drawableWidth: camera.viewportWidth,
            drawableHeight: camera.viewportHeight
        ), let projection = GoldenEyeProjectionV10.PacketV10(
            viewport: viewport,
            modelView: camera.modelView,
            projection: camera.projection
        ) else {
            throw GoldenEyeStageGameplayCameraPacketV7Error.invalidSnapshot
        }
        return projection
    }

    private static func makeFrameResources(
        camera: GoldenEyeStageEnvironmentCameraInputV6
    ) throws -> GoldenEyeSourceProductFrameResourcesV6 {
        try makeFrameResources(
            modelView: camera.modelView,
            projection: camera.projection,
            viewportWidth: camera.viewportWidth,
            viewportHeight: camera.viewportHeight
        )
    }

    private static func makeFrameResources(
        modelView: GoldenEyeProjectionV10.MatrixQ16,
        projection: GoldenEyeProjectionV10.MatrixQ16,
        viewportWidth: UInt32,
        viewportHeight: UInt32
    ) throws -> GoldenEyeSourceProductFrameResourcesV6 {
        let cameraHandle: UInt32 = 0xD700_0001
        let projectionHandle: UInt32 = 0xD700_0002
        let reflectionHandle: UInt32 = 0xD700_0003
        let viewportHandle: UInt32 = 0xD700_0004
        let modelValues = matrixValues(modelView)
        let projectionValues = matrixValues(projection)
        let matrices = [
            try GoldenEyeGBIMatrixResourceV6(
                handle: cameraHandle,
                values: modelValues,
                roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.camera
            ),
            try GoldenEyeGBIMatrixResourceV6(
                handle: projectionHandle,
                values: projectionValues,
                roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.projection
            ),
            try GoldenEyeGBIMatrixResourceV6(
                handle: reflectionHandle,
                values: modelValues,
                roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.reflection
            ),
        ]
        let width = Int32(viewportWidth / 2)
        let height = Int32(viewportHeight / 2)
        let viewport = try GoldenEyeGBIViewportResourceV6(
            handle: viewportHandle,
            values: [
                width << 16, height << 16, 1 << 16, 1 << 16,
                width << 16, height << 16, 0, 1 << 16,
            ]
        )
        return try GoldenEyeSourceProductFrameResourcesV6(
            matrices: matrices,
            viewports: [viewport],
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight
        )
    }

    private static func makeScopedScene(
        scene: GoldenEyeStageScenePacket,
        visibleStaticPropObjectIndices: [UInt32],
        dynamicPropTransforms: [GoldenEyeStageGameplayCameraDynamicPropV7],
        cameraModelView: GoldenEyeProjectionV10.MatrixQ16,
        setupDependencies: GoldenEyeStageSetupDependencyCatalogV6
    ) throws -> GoldenEyeStageScenePacket {
        let visible = Set(visibleStaticPropObjectIndices)
        let dynamicByIndex = Dictionary(uniqueKeysWithValues: dynamicPropTransforms.map { ($0.objectIndex, $0) })
        let objects = try scene.setup.objects.compactMap {
            object -> GoldenEyeStageSetupObjectPacket? in
            guard visible.contains(object.index) else { return nil }
            guard staticPropTypes.contains(object.type) else {
                throw GoldenEyeStageGameplayCameraPacketV7Error.invalidStaticProp(object.index)
            }
            let modelScaleQ16 = setupDependencies
                .dependency(kind: "prop", modelIndex: object.key0)?.modelScaleQ16 ?? 0
            let sourceMatrixWords = GoldenEyeStageModelPlacementCatalogV6
                .sourcePlacementMatrixWords(
                    object: object,
                    setup: scene.setup,
                    modelScaleQ16: modelScaleQ16
                )
            return try transformed(
                object: object,
                cameraModelView: cameraModelView,
                dynamicTransformQ16: dynamicByIndex[object.index]?.transformQ16,
                sourceMatrixWords: sourceMatrixWords
            )
        }
        guard !objects.isEmpty else {
            throw GoldenEyeStageGameplayCameraPacketV7Error.invalidSnapshot
        }
        var setupHash = mix(Self.offsetBasis, scene.setup.packetHash)
        for object in objects {
            setupHash = mix(setupHash, UInt64(object.index))
            setupHash = mix(setupHash, UInt64(object.type))
            for word in object.matrixWords { setupHash = mix(setupHash, UInt64(word)) }
        }
        let setup = GoldenEyeStageSetupPacket(
            stageID: scene.setup.stageID,
            sourceBytes: scene.setup.sourceBytes,
            sourceHash: scene.setup.sourceHash,
            header: scene.setup.header,
            sections: scene.setup.sections,
            pads: scene.setup.pads,
            boundPads: scene.setup.boundPads,
            objects: objects,
            intros: scene.setup.intros,
            waypoints: scene.setup.waypoints,
            waygroups: scene.setup.waygroups,
            patrolPaths: scene.setup.patrolPaths,
            aiLists: scene.setup.aiLists,
            padNameCount: scene.setup.padNameCount,
            boundPadNameCount: scene.setup.boundPadNameCount,
            portalTableSegmentedOffset: scene.setup.portalTableSegmentedOffset,
            portalTableOffset: scene.setup.portalTableOffset,
            portals: scene.setup.portals,
            packetHash: setupHash
        )
        return GoldenEyeStageScenePacket(
            stageID: scene.stageID,
            stageName: scene.stageName,
            demoMask: scene.demoMask,
            resources: scene.resources,
            background: scene.background,
            rooms: scene.rooms,
            setup: setup,
            packetHash: mix(scene.packetHash, setupHash)
        )
    }

    /// The existing composition contract reports an empty category packet as
    /// an unsupported effects bit.  A scoped frame may omit that category, but
    /// only after the packet proves that the omitted category has no records
    /// for this demo/stage.  This typed reconciliation preserves full-scene
    /// `0x38` evidence and refuses any omitted category that is actually
    /// visible; it is not a blanket unsupported-bit clear.
    private static func scopedPresentableComposition(
        _ raw: GoldenEyeStageModelSceneCompositionV6.Result,
        visibleCategories: [GoldenEyeStageGameplayCameraVisibleCategoryV7]
    ) throws -> GoldenEyeStageModelSceneCompositionV6.Result {
        let visible = Set(visibleCategories)
        var omittedMask: UInt32 = 0
        if !visible.contains(.characters) {
            omittedMask |= GoldenEyeStageBackgroundDrawPacket.unsupportedCharacters
        }
        if !visible.contains(.ai) {
            omittedMask |= GoldenEyeStageBackgroundDrawPacket.unsupportedAI
        }
        if !visible.contains(.effects) {
            omittedMask |= GoldenEyeStageBackgroundDrawPacket.unsupportedEffects
        }
        guard raw.unsupportedMask & ~omittedMask == 0 else {
            throw GoldenEyeStageGameplayCameraPacketV7Error.scopedUnsupportedMask(
                raw.unsupportedMask
            )
        }
        if (try? GoldenEyeStageFogLoweringV6.make(stageID: raw.stageID))?.enabled == true {
            guard let eyeSpaceZQ16 = raw.snapshot.eyeSpaceZQ16,
                  let fogCoordinateQ16 = raw.snapshot.fogCoordinateQ16,
                  eyeSpaceZQ16.count == raw.snapshot.vertices.count,
                  fogCoordinateQ16.count == raw.snapshot.vertices.count else {
                throw GoldenEyeStageGameplayCameraPacketV7Error.scopedComposition(
                    "fog-enabled scoped draw lacks parallel eye-space/fog coordinate arrays"
                )
            }
        }
        // Category packets use the source manifest names (for example
        // `guards`, not the packet enum's `characters`).  Every category
        // other than the explicitly lowerable `props` slice is omitted from
        // this scoped frame and therefore must have no source records.
        let omittedNames = Set(
            raw.categoryPackets.map(\.category).filter { $0 != "props" }
        )
        guard raw.categoryPackets.allSatisfy({ packet in
            !omittedNames.contains(packet.category)
                || (packet.records.isEmpty && packet.unsupportedCount == 0)
        }) else {
            throw GoldenEyeStageGameplayCameraPacketV7Error.scopedComposition(
                "an omitted visible category has source records"
            )
        }

        var summary = raw.snapshot.summary
        summary.unsupported_visible_count = 0
        summary.flags |= UInt32(GE_SOURCE_FRAME_V6_FLAG_PRESENTABLE)
        summary.scene_hash = mix(summary.scene_hash, 0x5343_4f50_545f_5637)
        summary.render_hash = mix(summary.render_hash, 0x5343_4f50_545f_5637)
        summary.state_hash = mix(summary.state_hash, 0x5343_4f50_545f_5637)
        summary.frame_hash = mix(summary.frame_hash, 0x5343_4f50_545f_5637)
        let snapshot = try GoldenEyeSourceSceneSnapshotV6(
            summary: summary,
            resources: raw.snapshot.resources,
            transforms: raw.snapshot.transforms,
            animationPoses: raw.snapshot.animationPoses,
            vertices: raw.snapshot.vertices,
            indices: raw.snapshot.indices,
            renderStates: raw.snapshot.renderStates,
            drawCommands: raw.snapshot.drawCommands,
            textEvents: raw.snapshot.textEvents,
            audioEvents: raw.snapshot.audioEvents,
            diagnostics: raw.snapshot.diagnostics,
            lightingFrameContext: raw.snapshot.lightingFrameContext,
            eyeSpaceZQ16: raw.snapshot.eyeSpaceZQ16,
            fogCoordinateQ16: raw.snapshot.fogCoordinateQ16
        )
        return GoldenEyeStageModelSceneCompositionV6.Result(
            snapshot: snapshot,
            stageID: raw.stageID,
            placementCount: raw.placementCount,
            drawablePlacementCount: raw.drawablePlacementCount,
            unsupportedPlacementCount: raw.unsupportedPlacementCount,
            propPlacementCount: raw.propPlacementCount,
            characterPlacementCount: raw.characterPlacementCount,
            aliasDescriptorCount: raw.aliasDescriptorCount,
            unsupportedMask: 0,
            failureReasons: raw.failureReasons,
            categoryPackets: raw.categoryPackets,
            compositionHash: mix(raw.compositionHash, summary.frame_hash),
            contiguousBatchCount: raw.contiguousBatchCount,
            largestContiguousBatch: raw.largestContiguousBatch
        )
    }

    private static func transformed(
        object: GoldenEyeStageSetupObjectPacket,
        cameraModelView: GoldenEyeProjectionV10.MatrixQ16,
        dynamicTransformQ16: [Int32]? = nil,
        sourceMatrixWords: [UInt32]? = nil
    ) throws -> GoldenEyeStageSetupObjectPacket {
        let serializedMatrixWords = sourceMatrixWords ?? object.matrixWords
        guard serializedMatrixWords.count == 16,
              dynamicTransformQ16 == nil || dynamicTransformQ16?.count == 16 else {
            throw GoldenEyeStageGameplayCameraPacketV7Error.invalidStaticProp(object.index)
        }
        var sourceQ16 = SIMD16<Int32>(repeating: 0)
        if let dynamicTransformQ16 {
            for index in 0..<16 {
                sourceQ16[index] = dynamicTransformQ16[index]
            }
        } else {
            for index in 0..<16 {
                let value = Float(bitPattern: serializedMatrixWords[index])
                guard value.isFinite else {
                    throw GoldenEyeStageGameplayCameraPacketV7Error.invalidStaticProp(object.index)
                }
                let scaled = Double(value) * 65_536.0
                guard scaled >= Double(Int32.min), scaled <= Double(Int32.max) else {
                    throw GoldenEyeStageGameplayCameraPacketV7Error.invalidStaticProp(object.index)
                }
                sourceQ16[index] = Int32(scaled.rounded(.toNearestOrAwayFromZero))
            }
        }
        let combined = GoldenEyeProjectionV10.MatrixQ16.multiplied(
            cameraModelView,
            GoldenEyeProjectionV10.MatrixQ16(values: sourceQ16)
        )
        let words = matrixValues(combined).map { value in
            Float(Double(value) / 65_536.0).bitPattern
        }
        return GoldenEyeStageSetupObjectPacket(
            index: object.index,
            sourceRecordOffset: object.sourceRecordOffset,
            type: object.type,
            scale8_8: object.scale8_8,
            state: object.state,
            key0: object.key0,
            key1: object.key1,
            flags1: object.flags1,
            flags2: object.flags2,
            recordBytes: object.recordBytes,
            matrixWords: words,
            portalHint: object.portalHint
        )
    }

    private static let offsetBasis: UInt64 = 1_469_598_103_934_665_603

    private static func packetHash(
        snapshot: GoldenEyeStageGameplayCameraSnapshotV7,
        camera: GoldenEyeStageEnvironmentCameraInputV6,
        environment: GoldenEyeStageBackgroundDrawPacket,
        composition: GoldenEyeStageModelSceneCompositionV6.Result,
        subset: GoldenEyeStageGameplayCameraSubsetMetadataV7
    ) -> UInt64 {
        var hash = mix(offsetBasis, UInt64(snapshot.demoID))
        hash = mix(hash, UInt64(snapshot.stageID))
        hash = mix(hash, snapshot.nativeTick)
        hash = mix(hash, environment.packetHash)
        hash = mix(hash, composition.compositionHash)
        hash = mix(hash, subset.metadataHash)
        for dynamic in snapshot.dynamicPropTransforms.sorted(by: { $0.objectIndex < $1.objectIndex }) {
            hash = mix(hash, UInt64(dynamic.objectIndex))
            hash = mix(hash, dynamic.sourceHash)
            hash = mix(hash, UInt64(dynamic.openState))
            hash = mix(hash, UInt64(dynamic.portalNumber))
            for value in dynamic.transformQ16 {
                hash = mix(hash, UInt64(bitPattern: Int64(value)))
            }
        }
        hash = mix(hash, matrixValues(camera.modelView).reduce(UInt64(0)) {
            mix($0, UInt64(UInt32(bitPattern: $1)))
        })
        hash = mix(hash, matrixValues(camera.projection).reduce(UInt64(0)) {
            mix($0, UInt64(UInt32(bitPattern: $1)))
        })
        return hash
    }

    private static func mix(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 56, by: 8) {
            result = (result ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
        }
        return result == 0 ? 1 : result
    }

    private static func matrixValues(
        _ matrix: GoldenEyeProjectionV10.MatrixQ16
    ) -> [Int32] {
        (0..<16).map { matrix.values[$0] }
    }
}
