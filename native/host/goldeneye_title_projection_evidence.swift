import Foundation

/// M10 consumption seam for source-derived title geometry.  This keeps the
/// projection contract observable without pretending that the partial GETP
/// packets are complete N64 display lists: source bounds are mapped through
/// the same fixed-width canonical/widescreen viewport and the first triangle
/// is classified only for deterministic clip/cull diagnostics.
struct GoldenEyeTitleProjectionEvidence: Sendable, Equatable {
    struct Record: Sendable, Equatable {
        let modelHandle: UInt32
        let vertexCount: Int
        let canonicalMin: GoldenEyeProjectionV10.PointQ16
        let canonicalMax: GoldenEyeProjectionV10.PointQ16
        let widescreenMin: GoldenEyeProjectionV10.PointQ16
        let widescreenMax: GoldenEyeProjectionV10.PointQ16
        let clipOrFlags: UInt32
        let canonicalHash: UInt64
        let widescreenHash: UInt64
    }

    let records: [Record]
    let aggregateHash: UInt64

    static func evaluate(
        packets: [GoldenEyeTitleGeometryPacket],
        canonical: GoldenEyeProjectionV10.ViewportV10,
        widescreen: GoldenEyeProjectionV10.ViewportV10
    ) -> GoldenEyeTitleProjectionEvidence {
        let identityCanonical = GoldenEyeProjectionV10.PacketV10(
            viewport: canonical,
            modelView: .identity,
            projection: .identity,
            cullMode: GoldenEyeProjectionV10.cullNone
        )!
        let identityWide = GoldenEyeProjectionV10.PacketV10(
            viewport: widescreen,
            modelView: .identity,
            projection: .identity,
            cullMode: GoldenEyeProjectionV10.cullNone
        )!
        let records = packets.sorted { $0.modelHandle < $1.modelHandle }.map { packet in
            let minPoint = GoldenEyeProjectionV10.PointQ16.fromInteger(
                packet.boundsMin.x, packet.boundsMin.y, packet.boundsMin.z
            )
            let maxPoint = GoldenEyeProjectionV10.PointQ16.fromInteger(
                packet.boundsMax.x, packet.boundsMax.y, packet.boundsMax.z
            )
            let canonicalMin = canonical.sourceToDrawable(minPoint)
            let canonicalMax = canonical.sourceToDrawable(maxPoint)
            let widescreenMin = widescreen.sourceToDrawable(minPoint)
            let widescreenMax = widescreen.sourceToDrawable(maxPoint)
            let clipOrFlags: UInt32
            if packet.indices.count >= 3 {
                let a = packet.vertices[Int(packet.indices[0])]
                let b = packet.vertices[Int(packet.indices[1])]
                let c = packet.vertices[Int(packet.indices[2])]
                let result = identityCanonical.classifyTriangle(
                    .fromInteger(a.x, a.y, a.z),
                    .fromInteger(b.x, b.y, b.z),
                    .fromInteger(c.x, c.y, c.z)
                )
                clipOrFlags = result.clipOrFlags
            } else {
                clipOrFlags = GoldenEyeProjectionV10.clipInvalidW
            }
            return Record(
                modelHandle: packet.modelHandle,
                vertexCount: packet.vertices.count,
                canonicalMin: canonicalMin,
                canonicalMax: canonicalMax,
                widescreenMin: widescreenMin,
                widescreenMax: widescreenMax,
                clipOrFlags: clipOrFlags,
                canonicalHash: hash(
                    packet: packet, viewport: canonical, projectedMin: canonicalMin,
                    projectedMax: canonicalMax, packetHash: identityCanonical.packetHash
                ),
                widescreenHash: hash(
                    packet: packet, viewport: widescreen, projectedMin: widescreenMin,
                    projectedMax: widescreenMax, packetHash: identityWide.packetHash
                )
            )
        }
        var aggregate = UInt64(1_469_598_103_934_665_603)
        for record in records {
            aggregate = hashU32(aggregate, record.modelHandle)
            aggregate = hashU32(aggregate, UInt32(record.vertexCount))
            aggregate = hashU64(aggregate, record.canonicalHash)
            aggregate = hashU64(aggregate, record.widescreenHash)
            aggregate = hashU32(aggregate, record.clipOrFlags)
        }
        return Self(records: records, aggregateHash: aggregate)
    }

    private static func hash(
        packet: GoldenEyeTitleGeometryPacket,
        viewport: GoldenEyeProjectionV10.ViewportV10,
        projectedMin: GoldenEyeProjectionV10.PointQ16,
        projectedMax: GoldenEyeProjectionV10.PointQ16,
        packetHash: UInt64
    ) -> UInt64 {
        var value = packetHash
        value = hashU32(value, packet.modelHandle)
        value = hashU32(value, viewport.drawableWidth)
        value = hashU32(value, viewport.drawableHeight)
        for point in [projectedMin, projectedMax] {
            value = hashU32(value, UInt32(bitPattern: point.x))
            value = hashU32(value, UInt32(bitPattern: point.y))
            value = hashU32(value, UInt32(bitPattern: point.z))
        }
        return value
    }

    private static func hashU32(_ hash: UInt64, _ value: UInt32) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 24, by: 8) {
            result = (result ^ UInt64((value >> UInt32(shift)) & 0xff)) &* 1_099_511_628_211
        }
        return result
    }

    private static func hashU64(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        hashU32(hashU32(hash, UInt32(truncatingIfNeeded: value)), UInt32(truncatingIfNeeded: value >> 32))
    }
}
