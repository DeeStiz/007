import Foundation

/// Fixed-width camera/visibility input owned by the portable stage player.
/// The environment lowerer consumes only copied matrices and bounded room
/// indices; it never retains a gameplay object, pointer, portal graph, or
/// source address.
public struct GoldenEyeStageEnvironmentCameraInputV6: Sendable, Equatable {
    public let stageID: UInt32
    public let nativeTick: UInt64
    public let currentRoom: UInt32
    public let visibleRoomIndices: [UInt32]
    public let viewportWidth: UInt32
    public let viewportHeight: UInt32
    public let modelView: GoldenEyeProjectionV10.MatrixQ16
    public let projection: GoldenEyeProjectionV10.MatrixQ16
    public let cameraPositionQ16: SIMD3<Int32>
    /// Source ``room_data_float2`` (Q16.16). Setup pads are multiplied by
    /// this value during the original setup load before camera publication.
    public let roomCoordinateScaleQ16: Int32
    /// The scaled player world position used by bgroomtrans as the room-space
    /// rebase origin. Geometry is emitted as
    /// ``(roomPosition + localPoint) * roomCoordinateScale - origin``.
    public let roomOriginQ16: SIMD3<Int32>
    /// Source ``D_800364CC`` visibility scale applied by the background
    /// camera matrix after the room-space rebase (Dam=0.2).
    public let visibilityScaleQ16: Int32
    /// True only for gameplay-camera frames. Source room triangles are
    /// clipped in homogeneous space before the generic NDC snapshot lowerer;
    /// structural inspection callers retain the complete room packet.
    public let clipToProjection: Bool

    public init(
        stageID: UInt32,
        nativeTick: UInt64,
        currentRoom: UInt32,
        visibleRoomIndices: [UInt32],
        viewportWidth: UInt32 = GoldenEyeProjectionV10.canonicalWidth,
        viewportHeight: UInt32 = GoldenEyeProjectionV10.canonicalHeight,
        modelView: GoldenEyeProjectionV10.MatrixQ16,
        projection: GoldenEyeProjectionV10.MatrixQ16,
        clipToProjection: Bool = false,
        roomCoordinateScaleQ16: Int32 = 65_536,
        cameraPositionQ16: SIMD3<Int32> = .zero,
        roomOriginQ16: SIMD3<Int32> = .zero,
        visibilityScaleQ16: Int32 = 65_536
    ) {
        self.stageID = stageID
        self.nativeTick = nativeTick
        self.currentRoom = currentRoom
        self.visibleRoomIndices = visibleRoomIndices
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.modelView = modelView
        self.projection = projection
        self.cameraPositionQ16 = cameraPositionQ16
        self.roomCoordinateScaleQ16 = roomCoordinateScaleQ16
        self.roomOriginQ16 = roomOriginQ16
        self.visibilityScaleQ16 = visibilityScaleQ16
        self.clipToProjection = clipToProjection
    }
}

/// Copied player-owner camera state. This mirrors only the camera fields the
/// owner publishes; no C owner state or mutable gameplay object crosses into
/// the environment adapter.
public struct GoldenEyeStagePlayerCameraSnapshotInputV6: Sendable, Equatable {
    public let stageID: UInt32
    public let nativeTick: UInt64
    public let currentRoom: UInt32
    public let cameraPositionQ16: SIMD3<Int32>
    public let cameraForwardQ16: SIMD3<Int32>
    public let cameraUpQ16: SIMD3<Int32>
    public let yawQ16: Int32
    public let pitchQ16: Int32

    public init(
        stageID: UInt32,
        nativeTick: UInt64,
        currentRoom: UInt32,
        cameraPositionQ16: SIMD3<Int32>,
        cameraForwardQ16: SIMD3<Int32>,
        cameraUpQ16: SIMD3<Int32>,
        yawQ16: Int32,
        pitchQ16: Int32
    ) {
        self.stageID = stageID
        self.nativeTick = nativeTick
        self.currentRoom = currentRoom
        self.cameraPositionQ16 = cameraPositionQ16
        self.cameraForwardQ16 = cameraForwardQ16
        self.cameraUpQ16 = cameraUpQ16
        self.yawQ16 = yawQ16
        self.pitchQ16 = pitchQ16
    }
}

enum GoldenEyeStageEnvironmentCameraAdapterV6 {
    /// Source constants from the directly compiled player/camera owner and
    /// gameplay camera setup: FOV 60, near 10, and stage far range 10,000.
    static let sourceGameplayFOVDegrees: Double = 60.0
    static let sourceGameplayNear: Double = 10.0
    static let sourceGameplayFar: Double = 10_000.0

    enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case invalidTick
        case stageMismatch(UInt32, UInt32)
        case visibleRoomCapacity
        case invalidViewport
        case invalidProjection
        case fogUnavailable(UInt32, UInt32)

        var description: String {
            switch self {
            case .invalidTick: return "stage environment camera input has an invalid native tick"
            case let .stageMismatch(expected, actual):
                return "stage environment camera stage \(actual) does not match \(expected)"
            case .visibleRoomCapacity: return "stage environment visible-room set exceeds bounded capacity"
            case .invalidViewport: return "stage environment camera viewport is invalid"
            case .invalidProjection: return "stage environment camera projection is invalid"
            case let .fogUnavailable(stageID, reason):
                return "stage \(stageID) source fog cannot be represented by the current Metal path (reason=\(reason))"
            }
        }
    }

    static func make(
        scene: GoldenEyeStageScenePacket,
        camera: GoldenEyeStageEnvironmentCameraInputV6,
        materialPacket: GoldenEyeStageSourceMaterialPacketV6? = nil,
        stageTextureCatalog: GoldenEyeStageTextureCatalogV6? = nil,
        environmentOnlyCapture: Bool = false
    ) throws -> GoldenEyeSourceSceneSnapshotV6 {
        guard camera.nativeTick > 0 else { throw Error.invalidTick }
        guard camera.stageID == scene.stageID else {
            throw Error.stageMismatch(scene.stageID, camera.stageID)
        }
        guard camera.visibleRoomIndices.count <= 4_096 else {
            throw Error.visibleRoomCapacity
        }
        let fog = try GoldenEyeStageFogLoweringV6.make(stageID: scene.stageID)
        if !environmentOnlyCapture, fog.requiresRendererBinding {
            throw Error.fogUnavailable(scene.stageID, fog.unsupportedReasonCode)
        }
        guard let viewport = GoldenEyeProjectionV10.ViewportV10(
            drawableWidth: camera.viewportWidth,
            drawableHeight: camera.viewportHeight
        ) else { throw Error.invalidViewport }
        guard let projection = GoldenEyeProjectionV10.PacketV10(
            viewport: viewport,
            modelView: camera.modelView,
            projection: camera.projection,
            cullMode: GoldenEyeProjectionV10.cullNone
        ) else {
            throw Error.invalidProjection
        }
        let visible = camera.visibleRoomIndices.isEmpty
            ? nil
            : Set(camera.visibleRoomIndices)
        let packet = try GoldenEyeStageSourceEnvironmentDrawPacketBuilderV6.make(
            scene: scene,
            viewport: viewport,
            projection: projection,
            environmentOnlyCapture: environmentOnlyCapture,
            visibleRoomIndices: visible,
            roomCoordinateScale: Double(camera.roomCoordinateScaleQ16) / 65_536.0,
            roomOrigin: GoldenEyeProjectionV10.PointQ16(
                x: camera.roomOriginQ16.x,
                y: camera.roomOriginQ16.y,
                z: camera.roomOriginQ16.z
            )
        )
        let renderPacket = camera.clipToProjection
            ? try clipPacket(packet)
            : packet
        return try GoldenEyeStageSourceSceneSnapshotAdapterV6.make(
            packet: renderPacket,
            nativeTick: camera.nativeTick,
            materialPacket: materialPacket,
            stageTextureCatalog: stageTextureCatalog
        )
    }

    /// Derives a source gameplay camera packet from copied player-owner state.
    /// The default visible set is the current room plus its source portal
    /// neighbors; callers may supply the owner's exact visibility set.
    static func input(
        scene: GoldenEyeStageScenePacket,
        snapshot: GoldenEyeStagePlayerCameraSnapshotInputV6,
        visibleRoomIndices: [UInt32]? = nil,
        viewportWidth: UInt32 = GoldenEyeProjectionV10.canonicalWidth,
        viewportHeight: UInt32 = GoldenEyeProjectionV10.canonicalHeight
    ) throws -> GoldenEyeStageEnvironmentCameraInputV6 {
        guard snapshot.stageID == scene.stageID else {
            throw Error.stageMismatch(scene.stageID, snapshot.stageID)
        }
        guard snapshot.nativeTick > 0 else {
            throw Error.invalidTick
        }
        guard let mappedCurrentRoom = sourceRoomIndex(
            scene: scene, sourceRoomID: snapshot.currentRoom
        ) else {
            throw Error.invalidTick
        }
        let visible = visibleRoomIndices.map { values in
            values.compactMap { sourceRoomIndex(scene: scene, sourceRoomID: $0) }
        } ?? oneHopVisibleRooms(scene: scene, currentRoom: snapshot.currentRoom)
        guard !visible.isEmpty, visible.contains(mappedCurrentRoom) else {
            throw Error.invalidTick
        }
        let roomCoordinateScale = sourceRoomCoordinateScale(stageID: snapshot.stageID)
        // prop.c scales setup-pad positions by room_data_float2 before the
        // player/camera owner receives them. bgroomtrans rebases each room
        // against current_model_pos, and bondviewUpdateCameraMatrices applies
        // D_800364CC to the rebased eye for source spC4.
        let roomOrigin = scene.rooms.first(where: { $0.roomIndex == mappedCurrentRoom })
            .flatMap { pointQ16(from: $0.positionBits) } ?? .init(x: 0, y: 0, z: 0)
        let scaledWorldPosition = scaledPosition(
            snapshot.cameraPositionQ16, by: roomCoordinateScale
        )
        let cameraDelta = SIMD3(
            Int32(clamping: Int64(snapshot.cameraPositionQ16.x) - Int64(roomOrigin.x)),
            Int32(clamping: Int64(snapshot.cameraPositionQ16.y) - Int64(roomOrigin.y)),
            Int32(clamping: Int64(snapshot.cameraPositionQ16.z) - Int64(roomOrigin.z))
        )
        let visibilityScale = sourceVisibilityScale(stageID: snapshot.stageID)
        let scaledEye = scaledPosition(
            cameraDelta, by: roomCoordinateScale * visibilityScale
        )
        let modelView = try lookAtMatrix(
            eye: scaledEye,
            forward: snapshot.cameraForwardQ16,
            up: snapshot.cameraUpQ16,
            yawQ16: snapshot.yawQ16
        )
        let aspect = Double(viewportWidth) / Double(viewportHeight)
        let projection = perspectiveMatrix(
            fovDegrees: sourceGameplayFOVDegrees,
            aspect: aspect,
            near: sourceGameplayNear,
            far: sourceGameplayFar
        )
        return GoldenEyeStageEnvironmentCameraInputV6(
            stageID: snapshot.stageID,
            nativeTick: snapshot.nativeTick,
            currentRoom: snapshot.currentRoom,
            visibleRoomIndices: visible,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            modelView: modelView,
            projection: projection,
            clipToProjection: true,
            roomCoordinateScaleQ16: q16(roomCoordinateScale),
            cameraPositionQ16: scaledWorldPosition,
            roomOriginQ16: SIMD3(roomOrigin.x, roomOrigin.y, roomOrigin.z),
            visibilityScaleQ16: q16(visibilityScale)
        )
    }

    /// Source level table values are the setup/background ``levelscale``.
    /// ``bg.c`` stores ``room_data_float2 = 1 / levelscale`` and
    /// ``prop.c:1355-1361`` multiplies setup-pad positions by it before the
    /// player camera is initialized. The camera adapter applies that copied,
    /// stage-authored conversion because the portable owner publishes the
    /// pre-setup-scale pad coordinate.
    private static func sourceRoomCoordinateScale(stageID: UInt32) -> Double {
        switch stageID {
        case 33: return 1.0 / 0.23363999       // Dam
        case 34: return 1.0 / 1.20648          // Facility
        case 35: return 1.0 / 0.089571431      // Runway
        case 9: return 1.0 / 0.53931433        // Bunker I
        case 20: return 1.0 / 0.47256002       // Silo
        case 26: return 1.0 / 0.44757429       // Frigate
        case 25: return 1.0 / 0.15019713       // Train
        default: return 1.0
        }
    }

    private static func sourceVisibilityScale(stageID: UInt32) -> Double {
        switch stageID {
        case 33: return 0.2                 // bg.c levelinfotable Dam
        default: return 1.0
        }
    }

    private static func pointQ16(
        from bits: (UInt32, UInt32, UInt32)
    ) -> GoldenEyeProjectionV10.PointQ16? {
        func convert(_ bits: UInt32) -> Int32? {
            let value = Float(bitPattern: bits)
            guard value.isFinite,
                  abs(value) <= 32_000,
                  Double(value) * 65_536.0 >= Double(Int32.min),
                  Double(value) * 65_536.0 <= Double(Int32.max) else {
                return nil
            }
            return Int32((Double(value) * 65_536.0).rounded(
                .toNearestOrAwayFromZero
            ))
        }
        guard let x = convert(bits.0), let y = convert(bits.1), let z = convert(bits.2) else {
            return nil
        }
        return GoldenEyeProjectionV10.PointQ16(x: x, y: y, z: z)
    }


    private static func scaledPosition(
        _ value: SIMD3<Int32>, by scale: Double
    ) -> SIMD3<Int32> {
        SIMD3(
            q16(Double(value.x) / 65_536.0 * scale),
            q16(Double(value.y) / 65_536.0 * scale),
            q16(Double(value.z) / 65_536.0 * scale)
        )
    }

    /// Clips room triangles in the same homogeneous space used by the
    /// source projection before the generic snapshot converts positions to
    /// NDC. Gameplay visibility includes neighboring rooms and therefore may
    /// legitimately contain triangles behind or crossing the near plane;
    /// dropping those triangles would leave holes, while projecting them with
    /// a non-positive/small W would overflow the fixed-width packet. This
    /// bounded Sutherland-Hodgman pass preserves authored colour and S/T
    /// values and triangulates each resulting convex polygon in source order.
    private static func clipPacket(
        _ packet: GoldenEyeStageBackgroundDrawPacket
    ) throws -> GoldenEyeStageBackgroundDrawPacket {
        var vertices: [GoldenEyeStageBackgroundDrawVertex] = []
        var commands: [GoldenEyeStageBackgroundDrawCommand] = []
        var sourceOrdinalsByRoom: [UInt32: UInt32] = [:]
        vertices.reserveCapacity(packet.vertices.count)
        commands.reserveCapacity(packet.commands.count)

        for command in packet.commands {
            guard command.vertexCount == 3,
                  Int(command.vertexStart) >= 0,
                  Int(command.vertexStart) + 3 <= packet.vertices.count else {
                continue
            }
            let start = Int(command.vertexStart)
            let sourceTriangle = packet.vertices[start..<(start + 3)].map(ClipVertex.init)
            let sourceOrdinal = sourceOrdinalsByRoom[command.sourceIndex, default: 0]
            sourceOrdinalsByRoom[command.sourceIndex] = sourceOrdinal + 1
            let polygon = clipPolygon(sourceTriangle)
            guard polygon.count >= 3 else { continue }
            for fanIndex in 1..<(polygon.count - 1) {
                let triangle = [polygon[0], polygon[fanIndex], polygon[fanIndex + 1]]
                let vertexStart = UInt32(vertices.count)
                vertices.append(contentsOf: triangle.map(Self.backgroundVertex))
                commands.append(.init(
                    primitive: command.primitive,
                    vertexStart: vertexStart,
                    vertexCount: 3,
                    sourceIndex: command.sourceIndex,
                    sourceRecordOffset: command.sourceRecordOffset,
                    metadataHash: command.metadataHash,
                    flags: command.flags,
                    // Preserve the original room-triangle material ordinal
                    // across near/frustum clipping fan expansion. The generic
                    // scene adapter consumes this additive marker only for
                    // gameplay-camera packets.
                    reserved: 0x8000_0000 | sourceOrdinal
                ))
            }
        }
        guard !commands.isEmpty else {
            // The source camera can legitimately have a portal-visible set
            // whose geometry is wholly outside the clip volume at a
            // checkpoint. Preserve that authored black frame without
            // synthesizing diagnostic polygons.
            return packet.replacingGeometry(vertices: [], commands: [])
        }
        return packet.replacingGeometry(vertices: vertices, commands: commands)
    }

    private struct ClipVertex {
        let x: Double
        let y: Double
        let z: Double
        let w: Double
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        let s: Double
        let t: Double
        let hasTextureCoordinates: Bool
        let roomIndex: UInt32

        init(source: GoldenEyeStageBackgroundDrawVertex) {
            x = Double(source.clipXQ16)
            y = Double(source.clipYQ16)
            z = Double(source.clipZQ16)
            w = Double(source.clipWQ16)
            red = Double((source.colorRGBA8 >> 24) & 0xff)
            green = Double((source.colorRGBA8 >> 16) & 0xff)
            blue = Double((source.colorRGBA8 >> 8) & 0xff)
            alpha = Double(source.colorRGBA8 & 0xff)
            s = Double(source.sourceTextureS10_5)
            t = Double(source.sourceTextureT10_5)
            hasTextureCoordinates = source.sourceTextureCoordinatesPresent
            roomIndex = source.roomIndex
        }

        init(
            x: Double, y: Double, z: Double, w: Double,
            red: Double, green: Double, blue: Double, alpha: Double,
            s: Double, t: Double, hasTextureCoordinates: Bool,
            roomIndex: UInt32
        ) {
            self.x = x; self.y = y; self.z = z; self.w = w
            self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
            self.s = s; self.t = t
            self.hasTextureCoordinates = hasTextureCoordinates
            self.roomIndex = roomIndex
        }
    }

    private static func clipPolygon(_ input: [ClipVertex]) -> [ClipVertex] {
        var polygon = input
        // Clip in Q16 homogeneous coordinates. W=1 is one fixed-point unit,
        // far below the authored near-plane distance, and avoids a zero-W
        // divide at the packet boundary.
        for plane in 0..<7 {
            guard !polygon.isEmpty else { break }
            var output: [ClipVertex] = []
            output.reserveCapacity(polygon.count + 1)
            var previous = polygon[polygon.count - 1]
            var previousDistance = clipDistance(previous, plane: plane)
            var previousInside = previousDistance >= 0
            for current in polygon {
                let currentDistance = clipDistance(current, plane: plane)
                let currentInside = currentDistance >= 0
                if currentInside != previousInside {
                    let denominator = previousDistance - currentDistance
                    let factor = abs(denominator) > 1.0e-12
                        ? max(0, min(1, previousDistance / denominator))
                        : 0
                    output.append(interpolate(previous, current, factor: factor))
                }
                if currentInside { output.append(current) }
                previous = current
                previousDistance = currentDistance
                previousInside = currentInside
            }
            polygon = output
        }
        return polygon
    }

    private static func clipDistance(_ value: ClipVertex, plane: Int) -> Double {
        switch plane {
        case 0: return value.w - 1.0       // W >= epsilon
        case 1: return value.x + value.w    // X >= -W
        case 2: return value.w - value.x    // X <= W
        case 3: return value.y + value.w    // Y >= -W
        case 4: return value.w - value.y    // Y <= W
        case 5: return value.z + value.w    // Z >= -W
        default: return value.w - value.z  // Z <= W
        }
    }

    private static func interpolate(
        _ a: ClipVertex, _ b: ClipVertex, factor: Double
    ) -> ClipVertex {
        func mix(_ lhs: Double, _ rhs: Double) -> Double {
            lhs + (rhs - lhs) * factor
        }
        return ClipVertex(
            x: mix(a.x, b.x), y: mix(a.y, b.y), z: mix(a.z, b.z), w: mix(a.w, b.w),
            red: mix(a.red, b.red), green: mix(a.green, b.green),
            blue: mix(a.blue, b.blue), alpha: mix(a.alpha, b.alpha),
            s: mix(a.s, b.s), t: mix(a.t, b.t),
            hasTextureCoordinates: a.hasTextureCoordinates || b.hasTextureCoordinates,
            roomIndex: a.roomIndex
        )
    }

    private static func backgroundVertex(_ value: ClipVertex) -> GoldenEyeStageBackgroundDrawVertex {
        func channel(_ component: Double) -> UInt32 {
            UInt32(clamping: Int64(max(0, min(255, component)).rounded(.toNearestOrAwayFromZero)))
        }
        let color = (channel(value.red) << 24) | (channel(value.green) << 16) |
            (channel(value.blue) << 8) | channel(value.alpha)
        let reserved = value.hasTextureCoordinates
            ? GoldenEyeStageBackgroundDrawVertex.packedSourceTextureCoordinates(
                s10_5: Int32(clamping: Int64(value.s.rounded(.toNearestOrAwayFromZero))),
                t10_5: Int32(clamping: Int64(value.t.rounded(.toNearestOrAwayFromZero)))
            )
            : 0
        return GoldenEyeStageBackgroundDrawVertex(
            clipXQ16: Int32(clamping: Int64(value.x.rounded(.toNearestOrAwayFromZero))),
            clipYQ16: Int32(clamping: Int64(value.y.rounded(.toNearestOrAwayFromZero))),
            clipZQ16: Int32(clamping: Int64(value.z.rounded(.toNearestOrAwayFromZero))),
            clipWQ16: Int32(clamping: Int64(value.w.rounded(.toNearestOrAwayFromZero))),
            colorRGBA8: color,
            roomIndex: value.roomIndex,
            flags: 0,
            reserved: reserved
        )
    }

    private static func oneHopVisibleRooms(
        scene: GoldenEyeStageScenePacket,
        currentRoom: UInt32
    ) -> [UInt32] {
        var sourceIDs: Set<UInt32> = [currentRoom]
        for portal in scene.setup.portals {
            if portal.connectedRoom1 == currentRoom {
                sourceIDs.insert(portal.connectedRoom2)
            } else if portal.connectedRoom2 == currentRoom {
                sourceIDs.insert(portal.connectedRoom1)
            }
        }
        return sourceIDs.compactMap {
            sourceRoomIndex(scene: scene, sourceRoomID: $0)
        }.sorted()
    }

    /// Setup/STAN room IDs are source one-based identifiers. The background
    /// linker has a leading null room-table row and the bounded scene packet
    /// exposes the following rows as zero-based indices. Keep this conversion
    /// at the copied camera/visibility boundary so room geometry and player
    /// current-room state cannot silently diverge.
    private static func sourceRoomIndex(
        scene: GoldenEyeStageScenePacket,
        sourceRoomID: UInt32
    ) -> UInt32? {
        if sourceRoomID > 0 {
            let zeroBased = sourceRoomID - 1
            if scene.rooms.contains(where: { $0.roomIndex == zeroBased }) {
                return zeroBased
            }
        }
        return scene.rooms.contains(where: { $0.roomIndex == sourceRoomID })
            ? sourceRoomID
            : nil
    }

    private static func lookAtMatrix(
        eye: SIMD3<Int32>,
        forward: SIMD3<Int32>,
        up: SIMD3<Int32>,
        yawQ16: Int32
    ) throws -> GoldenEyeProjectionV10.MatrixQ16 {
        let eyeD = SIMD3<Double>(Double(eye.x), Double(eye.y), Double(eye.z)) / 65_536.0
        let forwardD = normalized(SIMD3<Double>(
            Double(forward.x), Double(forward.y), Double(forward.z)
        ))
        let upD = normalized(SIMD3<Double>(Double(up.x), Double(up.y), Double(up.z)))
        let sourceRight = cross(forwardD, upD)
        // The source camera keeps a world-up vector even when the pitch is
        // exactly +/-90 degrees.  At that pole the cross product is
        // necessarily zero; derive the limiting right axis from the copied
        // source yaw so the view basis remains continuous with the authored
        // camera orientation rather than failing or inventing a roll.
        let rightD: SIMD3<Double>
        if length(sourceRight) > 1.0e-9 {
            rightD = normalized(sourceRight)
        } else {
            let yawRadians = Double(yawQ16) / 65_536.0 * .pi / 180.0
            rightD = normalized(SIMD3<Double>(
                -cos(yawRadians), 0, -sin(yawRadians)
            ))
        }
        let correctedUpD = normalized(cross(rightD, forwardD))
        guard length(forwardD) > 0, length(upD) > 0,
              length(rightD) > 0, length(correctedUpD) > 0 else {
            throw Error.invalidProjection
        }
        // GE's Mtxf producer stores its basis vectors as columns.  The V10
        // MatrixQ16 contract is row-major for fixed-point application, so
        // transpose that copied source basis at this boundary.  Keeping the
        // source basis/translation order explicit prevents a column/row
        // reinterpretation from moving the gameplay camera away from its
        // authored room geometry.
        var values = SIMD16<Int32>(repeating: 0)
        let sourceForward = -forwardD
        values[0] = q16(rightD.x)
        values[1] = q16(correctedUpD.x)
        values[2] = q16(sourceForward.x)
        values[3] = q16(-dot(rightD, eyeD))
        values[4] = q16(rightD.y)
        values[5] = q16(correctedUpD.y)
        values[6] = q16(sourceForward.y)
        values[7] = q16(-dot(correctedUpD, eyeD))
        values[8] = q16(rightD.z)
        values[9] = q16(correctedUpD.z)
        values[10] = q16(sourceForward.z)
        values[11] = q16(dot(forwardD, eyeD))
        values[15] = 65_536
        return GoldenEyeProjectionV10.MatrixQ16(values: values)
    }

    private static func perspectiveMatrix(
        fovDegrees: Double,
        aspect: Double,
        near: Double,
        far: Double
    ) -> GoldenEyeProjectionV10.MatrixQ16 {
        let radians = fovDegrees * .pi / 180.0
        let focal = 1.0 / tan(radians * 0.5)
        let a = (far + near) / (near - far)
        let b = (2.0 * far * near) / (near - far)
        var values = SIMD16<Int32>(repeating: 0)
        values[0] = q16(focal / aspect)
        values[5] = q16(focal)
        values[10] = q16(0.5 * a)
        values[11] = q16(0.5 * b + 0.5)
        values[14] = -65_536
        return GoldenEyeProjectionV10.MatrixQ16(values: values)
    }

    private static func q16(_ value: Double) -> Int32 {
        Int32(clamping: Int64((value * 65_536.0).rounded(.toNearestOrAwayFromZero)))
    }

    private static func normalized(_ value: SIMD3<Double>) -> SIMD3<Double> {
        let magnitude = length(value)
        return magnitude > 0 ? value / magnitude : .zero
    }

    private static func length(_ value: SIMD3<Double>) -> Double {
        sqrt(dot(value, value))
    }

    private static func dot(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    private static func cross(_ lhs: SIMD3<Double>, _ rhs: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(
            lhs.y * rhs.z - lhs.z * rhs.y,
            lhs.z * rhs.x - lhs.x * rhs.z,
            lhs.x * rhs.y - lhs.y * rhs.x
        )
    }
}
