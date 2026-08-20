import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Source animation decoder for the guard owner.  The two animation tables
/// are prepared, hash-checked payloads; this type never opens a ROM or keeps
/// a source address.  The layout follows ModelAnimation and the packed
/// modelAnimReadBitsAsU16Angle/modelAnimReadRootMotionValue readers.
enum GoldenEyeRamRomGuardPoseSourceV6 {
    struct Result {
        let poses: [GESourceAnimationPoseV6]
        let skeletonHandle: UInt32
        let animationHash: UInt64
        let poseHash: UInt64
        let frameCount: UInt32
        let missing: String?
    }

    private struct Joint {
        let id: UInt32
        let parent: UInt32
        let matrixA: UInt32
        let matrixB: UInt32
    }

    // Source: assets/embedded/skeletons/guard.inc.c, JOINTLIST(guard).
    // This table is copied into the additive source-side decoder so the
    // runtime does not parse a C file or retain an address-bearing record.
    private static let guardJoints: [(UInt32, UInt32, UInt32)] = [
        (0x401, 0x00, 0x00), (0x002, 0x00, 0x00),
        (0x002, 0x03, 0x03), (0x002, 0x06, 0x06),
        (0x002, 0x09, 0x0c), (0x002, 0x0c, 0x09),
        (0x002, 0x0f, 0x12), (0x002, 0x12, 0x0f),
        (0x002, 0x15, 0x18), (0x002, 0x18, 0x15),
        (0x002, 0x1b, 0x1e), (0x002, 0x1e, 0x1b),
        (0x002, 0x21, 0x24), (0x002, 0x24, 0x21),
        (0x002, 0x27, 0x2a), (0x002, 0x2a, 0x27),
    ]

    // These are the source ANIM_DATA rows exercised by setup AI
    // PlayAnimation commands in the seven RAMROM stages.  The values are
    // offsets in the copied animationtable_data payload, not pointers.
    private static let animationDataOffsets: [UInt32: UInt32] = [
        0: 0x01c, 1: 0x144, 2: 0x214, 89: 0x777c, 90: 0x77d4,
        98: 0x7aa8, 99: 0x7c4c, 100: 0x7d04, 101: 0x7dd8,
        102: 0x7f0c, 103: 0x7fb4, 104: 0x8080, 105: 0x8164,
        106: 0x8194, 107: 0x8204, 172: 0xd5e4, 173: 0xd668,
        174: 0xd6f8, 175: 0xd728,
    ]

    static func decode(
        model: GoldenEyeSourceModelV6,
        modelHandle: UInt32,
        animationID: UInt32,
        frame: UInt32,
        flip: Bool,
        animationData: Data,
        animationEntries: Data
    ) -> Result {
        let skeletonHandle = 0xd601_0000 | (modelHandle & 0x0000_ffff)
        guard let dataOffset = animationDataOffsets[animationID] else {
            return failure(
                skeletonHandle: skeletonHandle,
                reason: "guard_pose_decoder.animationID" + String(animationID) + ".source_offset"
            )
        }
        let base = Int(dataOffset)
        guard let entryOffset = be32(animationData, base),
              let frameWord = be32(animationData, base + 4),
              let strideWord = be32(animationData, base + 12),
              let descriptorOffset = be32(animationData, base + 8),
              let bitStreamOffset = be32(animationData, base + 16) else {
            return failure(skeletonHandle: skeletonHandle, reason: "guard_pose_decoder.animationID" + String(animationID) + ".header")
        }
        let frameCount = UInt32(frameWord >> 16)
        let bitWidth = (frameWord >> 8) & 0xff
        let frameBits = strideWord & 0xffff
        let bitStride = strideWord >> 16
        guard frameCount > 0, bitWidth > 0, bitWidth <= 16,
              frameBits > 0, frameBits % 8 == 0 else {
            return failure(skeletonHandle: skeletonHandle, frameCount: frameCount,
                           reason: "guard_pose_decoder.animationID" + String(animationID) + ".header_fields")
        }
        let frameBytes = Int(frameBits / 8)
        let selectedFrame = min(frame, frameCount - 1)
        let frameStart = Int(entryOffset) + Int(selectedFrame) * frameBytes
        guard frameStart >= 0, frameBytes <= animationEntries.count,
              frameStart <= animationEntries.count - frameBytes else {
            return failure(skeletonHandle: skeletonHandle, frameCount: frameCount,
                           reason: "guard_pose_decoder.animationID" + String(animationID) + ".frame_bounds")
        }

        let decodedRootValues: [UInt16]
        if bitStride == 0 {
            // ANIM_DATA_idle has no root-motion channel.  Its source header
            // deliberately carries a zero stride and the model starts at
            // the authored placement transform.
            decodedRootValues = [0, 0, 0, 0]
        } else {
            guard let descriptors = rootDescriptors(data: animationData, offset: Int(descriptorOffset)) else {
                return failure(skeletonHandle: skeletonHandle, frameCount: frameCount,
                               reason: "guard_pose_decoder.animationID" + String(animationID) + ".root_descriptors")
            }
            let extraBitOffset = Int(bitStride) * Int(selectedFrame)
            guard let values = rootValues(
                data: animationData, streamOffset: Int(bitStreamOffset),
                descriptors: descriptors, extraBitOffset: extraBitOffset
            ) else {
                return failure(skeletonHandle: skeletonHandle, frameCount: frameCount,
                               reason: "guard_pose_decoder.animationID" + String(animationID) + ".root_stream")
            }
            decodedRootValues = values
        }

        guard let joints = sourceJoints(model: model) else {
            return failure(skeletonHandle: skeletonHandle, frameCount: frameCount,
                           reason: "guard_pose_decoder.animationID" + String(animationID) + ".model_skeleton")
        }
        var poses = [GESourceAnimationPoseV6]()
        poses.reserveCapacity(joints.count)
        var poseHash: UInt64 = 1_469_598_103_934_665_603
        for (index, joint) in joints.enumerated() {
            let matrix = flip ? joint.matrixB : joint.matrixA
            let startBit = (frameStart * 8) + Int(matrix) * Int(bitWidth)
            guard let rawX = readBits(animationEntries, bitOffset: startBit, width: Int(bitWidth)),
                  let rawY = readBits(animationEntries, bitOffset: startBit + Int(bitWidth), width: Int(bitWidth)),
                  let rawZ = readBits(animationEntries, bitOffset: startBit + Int(bitWidth) * 2, width: Int(bitWidth)) else {
                return failure(skeletonHandle: skeletonHandle, frameCount: frameCount,
                               reason: "guard_pose_decoder.animationID" + String(animationID) + ".joint" + String(index) + ".bits")
            }
            let x = angleQ16(rawX)
            var y = angleQ16(rawY)
            var z = angleQ16(rawZ)
            if flip {
                if rawY != 0 { y = angleQ16(UInt16(0x1_0000 - UInt32(rawY))) }
                if rawZ != 0 { z = angleQ16(UInt16(0x1_0000 - UInt32(rawZ))) }
            }
            var pose = GESourceAnimationPoseV6()
            pose.header.abi_version = GE_NATIVE_ABI_VERSION
            pose.header.struct_size = UInt32(MemoryLayout<GESourceAnimationPoseV6>.size)
            pose.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
            pose.pose_handle = 0xd700_0000 | UInt32(index + 1)
            pose.skeleton_handle = skeletonHandle
            pose.node_handle = 0xd700_0000 | UInt32(index + 1)
            pose.parent_handle = joint.parent == UInt32.max
                ? 0 : (0xd700_0000 | (joint.parent + 1))
            pose.flags = UInt32(GE_SOURCE_POSE_V6_FLAG_INTERPOLATABLE)
                | (index == 0 ? UInt32(GE_SOURCE_POSE_V6_FLAG_ROOT) : 0)
            pose.animation_tick = selectedFrame
            pose.translation_q16 = index == 0
                ? (q16(decodedRootValues[0]), q16(decodedRootValues[1]), q16(decodedRootValues[2]))
                : (0, 0, 0)
            pose.rotation_q16 = index == 0
                ? (0, angleQ16(decodedRootValues[3]), 0, 65_536)
                : (x, y, z, 65_536)
            pose.scale_q16 = (65_536, 65_536, 65_536)
            pose.pose_hash = mixHashes([
                UInt64(modelHandle), UInt64(animationID), UInt64(selectedFrame),
                UInt64(index), UInt64(rawX), UInt64(rawY), UInt64(rawZ),
                UInt64(bitStride), UInt64(descriptorOffset), UInt64(bitStreamOffset),
            ])
            pose.reserved0 = 0; pose.reserved1 = 0; pose.reserved2 = 0
            poses.append(pose)
            poseHash = mixHashes([poseHash, pose.pose_hash])
        }
        guard !poses.isEmpty else {
            return failure(skeletonHandle: skeletonHandle, frameCount: frameCount,
                           reason: "guard_pose_decoder.animationID" + String(animationID) + ".empty")
        }
        return Result(
            poses: poses, skeletonHandle: skeletonHandle,
            animationHash: mixHashes([UInt64(dataOffset), UInt64(entryOffset), UInt64(frameCount), UInt64(bitWidth), UInt64(bitStride)]),
            poseHash: poseHash, frameCount: frameCount, missing: nil
        )
    }

    private static func sourceJoints(model: GoldenEyeSourceModelV6) -> [Joint]? {
        guard model.nodes.count > 0 else { return nil }
        var parentByJoint: [UInt32: UInt32] = [:]
        var jointByNode: [UInt32: UInt32] = [:]
        for node in model.nodes {
            guard node.scalarStart < UInt32(model.scalars.count) else { continue }
            let scalar = model.scalars[Int(node.scalarStart)]
            guard scalar.kindHandle == 0x2982_ba70,
                  let fields = splitTopLevel(scalar.semantic), fields.count >= 2,
                  let joint = parseUnsigned(fields[1]), joint < 16 else { continue }
            jointByNode[node.id] = joint
        }
        for (nodeID, joint) in jointByNode {
            var parent = model.node(id: nodeID)?.parent ?? UInt32.max
            var seen = Set<UInt32>()
            while parent != UInt32.max, seen.insert(parent).inserted {
                if let parentJoint = jointByNode[parent], parentJoint != joint {
                    parentByJoint[joint] = parentJoint
                    break
                }
                parent = model.node(id: parent)?.parent ?? UInt32.max
            }
        }
        guard Set(jointByNode.values).count >= 15 else { return nil }
        return guardJoints.enumerated().map { index, source in
            Joint(id: UInt32(index), parent: index == 0 ? UInt32.max : (parentByJoint[UInt32(index)] ?? 0),
                  matrixA: source.1, matrixB: source.2)
        }
    }

    private static func rootDescriptors(data: Data, offset: Int) -> [(bitOffset: UInt16, bitCount: UInt8, valueOffset: UInt16)]? {
        guard offset >= 0, offset <= data.count - 24 else { return nil }
        var result: [(UInt16, UInt8, UInt16)] = []
        for index in 0..<4 {
            let cursor = offset + index * 6
            guard let bitOffset = be16(data, cursor),
                  cursor + 3 < data.count,
                  let valueOffset = be16(data, cursor + 4),
                  data[cursor + 3] == 0, data[cursor + 2] <= 16 else { return nil }
            result.append((bitOffset, data[cursor + 2], valueOffset))
        }
        return result
    }

    private static func rootValues(
        data: Data, streamOffset: Int,
        descriptors: [(bitOffset: UInt16, bitCount: UInt8, valueOffset: UInt16)],
        extraBitOffset: Int
    ) -> [UInt16]? {
        guard streamOffset >= 0, streamOffset < data.count else { return nil }
        return descriptors.map { descriptor in
            guard descriptor.bitCount > 0 else { return descriptor.valueOffset }
            let value = readBits(data, bitOffset: streamOffset * 8 + extraBitOffset + Int(descriptor.bitOffset), width: Int(descriptor.bitCount)) ?? 0
            var signed = Int32(value)
            if descriptor.bitCount < 16,
               value & (UInt16(1) << UInt16(descriptor.bitCount - 1)) != 0 {
                signed |= Int32(bitPattern: 0xffff_ffff << UInt32(descriptor.bitCount))
            }
            return UInt16(truncatingIfNeeded: signed + Int32(descriptor.valueOffset))
        }
    }

    private static func readBits(_ data: Data, bitOffset: Int, width: Int) -> UInt16? {
        guard bitOffset >= 0, width > 0, width <= 16,
              bitOffset <= data.count * 8 - width else { return nil }
        var result: UInt32 = 0
        for index in 0..<width {
            let absolute = bitOffset + index
            result = (result << 1) | ((UInt32(data[absolute >> 3]) >> UInt32(7 - (absolute & 7))) & 1)
        }
        return UInt16(result)
    }

    private static func angleQ16(_ raw: UInt16) -> Int32 {
        Int32((Int64(raw) * 411_775) >> 16)
    }

    private static func q16(_ value: UInt16) -> Int32 {
        Int32(Int16(bitPattern: value)) << 16
    }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 |
            UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }

    private static func be16(_ data: Data, _ offset: Int) -> UInt16? {
        guard offset >= 0, offset <= data.count - 2 else { return nil }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func splitTopLevel(_ text: String) -> [String]? {
        var values: [String] = []
        var start = text.startIndex
        var depth = 0
        for index in text.indices {
            switch text[index] {
            case "{", "(": depth += 1
            case "}", ")": depth -= 1
            case "," where depth == 0:
                values.append(text[start..<index].trimmingCharacters(in: .whitespacesAndNewlines))
                start = text.index(after: index)
            default: break
            }
        }
        values.append(text[start...].trimmingCharacters(in: .whitespacesAndNewlines))
        return values
    }

    private static func parseUnsigned(_ text: String) -> UInt32? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("0x") || value.hasPrefix("0X") { return UInt32(value.dropFirst(2), radix: 16) }
        return UInt32(value)
    }

    private static func mixHashes(_ values: [UInt64]) -> UInt64 {
        values.reduce(UInt64(1_469_598_103_934_665_603)) { hash, value in
            stride(from: 0, to: 64, by: 8).reduce(hash) { partial, shift in
                (partial ^ ((value >> UInt64(shift)) & 0xff)) &* 1_099_511_628_211
            }
        }
    }

    private static func failure(skeletonHandle: UInt32, frameCount: UInt32 = 0, reason: String) -> Result {
        Result(poses: [], skeletonHandle: skeletonHandle, animationHash: 0, poseHash: 0, frameCount: frameCount, missing: reason)
    }
}
