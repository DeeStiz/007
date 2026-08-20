import Foundation
import simd
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Converts the source character GroupRecord joint/matrix selectors and one
/// decoded animation pose into the model-view matrix values consumed by the
/// existing GBI builder.  The source GESM semantic string is only used as a
/// bounded, already-validated value record; no source pointer or ROM address
/// is recovered at runtime.
enum GoldenEyeCastSkeletonTransformV6 {
    struct GroupBinding: Sendable, Equatable {
        let jointID: UInt32
        let matrixIDs: [UInt32]
        let originQ16: SIMD3<Int32>
    }

    enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case malformedGroup(UInt32)
        case missingPose(UInt32)
        case invalidMatrix(UInt32)

        var description: String {
            switch self {
            case .malformedGroup(let node): return "cast group metadata is malformed for node \(node)"
            case .missingPose(let joint): return "cast pose is missing source joint \(joint)"
            case .invalidMatrix(let handle): return "cast skeleton matrix is invalid 0x\(String(handle, radix: 16))"
            }
        }
    }

    /// Return all GroupRecord bindings in source graph order.  GroupRecord's
    /// canonical form is `{x,y,z},joint,matrix0,matrix1,matrix2,child,radius`.
    static func groups(model: GoldenEyeSourceModelV6) throws -> [GroupBinding] {
        var result: [GroupBinding] = []
        for node in model.nodes {
            guard node.opcodeHandle == 0x80E8_9C4D || node.opcodeHandle == 0x0ECA_2814 else {
                continue
            }
            guard node.scalarStart < UInt32(model.scalars.count) else { continue }
            let semantic = model.scalars[Int(node.scalarStart)].semantic
            guard semantic.first == "{" else { continue }
            let fields = splitTopLevel(semantic)
            guard fields.count >= 5,
                  let origin = parseVector(fields[0]),
                  let joint = parseUnsigned(fields[1]),
                  parseUnsigned(fields[2]) != nil,
                  parseUnsigned(fields[3]) != nil,
                  parseUnsigned(fields[4]) != nil else {
                throw Error.malformedGroup(node.id)
            }
            // MatrixIDs are signed 16-bit selectors; 0xFFFF is the source
            // null sentinel and must never become a shared transform handle.
            let matrixIDs = [fields[2], fields[3], fields[4]].compactMap { value -> UInt32? in
                guard let selector = parseUnsigned(value),
                      selector != 0xFFFF, selector != UInt32.max else { return nil }
                return selector
            }
            guard joint < 256, !matrixIDs.isEmpty else {
                throw Error.malformedGroup(node.id)
            }
            result.append(GroupBinding(jointID: joint, matrixIDs: matrixIDs, originQ16: origin))
        }
        return result
    }

    /// Apply decoded source poses to the supplied model matrix resources. The
    /// untouched projection/viewport resources remain byte-for-byte copied.
    static func apply(
        modelName: String,
        model: GoldenEyeSourceModelV6,
        poses: [GESourceAnimationPoseV6],
        matrices: [GoldenEyeGBIMatrixResourceV6]
    ) throws -> [GoldenEyeGBIMatrixResourceV6] {
        guard !poses.isEmpty else { return matrices }
        let groupBindings = try groups(model: model)
        var poseByJoint: [UInt32: GESourceAnimationPoseV6] = [:]
        for pose in poses {
            let encodedJoint = pose.node_handle & 0x0000_ffff
            let joint = encodedJoint == 0 ? 0 : encodedJoint - 1
            poseByJoint[joint] = pose
            poseByJoint[joint & 0x0000_00ff] = pose
        }
        var matrixToJoint: [UInt32: (joint: UInt32, origin: SIMD3<Int32>)] = [:]
        for group in groupBindings {
            for matrixID in group.matrixIDs {
                matrixToJoint[matrixID] = (group.jointID, group.originQ16)
            }
        }
        let matrixHandles = Set(matrixToJoint.keys.map {
            matrixHandle(modelName: modelName, matrixID: $0)
        })
        var output: [GoldenEyeGBIMatrixResourceV6] = []
        output.reserveCapacity(matrices.count)
        for matrix in matrices {
            guard matrix.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.modelView != 0 else {
                output.append(matrix)
                continue
            }
            guard matrixHandles.contains(matrix.handle),
                  let matrixID = matrixToJoint.first(where: {
                      matrixHandle(modelName: modelName, matrixID: $0.key) == matrix.handle
                  })?.key,
                  let binding = matrixToJoint[matrixID],
                  let pose = poseByJoint[binding.joint]
            else {
                output.append(matrix)
                continue
            }
            let joint = poseMatrix(pose: pose, originQ16: binding.origin)
            let base = matrixFromQ16(matrix.values)
            let combined = base * joint
            let values = q16Matrix(combined)
            output.append(try GoldenEyeGBIMatrixResourceV6(
                handle: matrix.handle, values: values, roleFlags: matrix.roleFlags
            ))
        }
        return output
    }

    /// Deterministic source-address handle matching the prep compiler's
    /// `_resource_handle(model, "address", "0x<matrixID*0x40>")` rule.
    static func matrixHandle(modelName: String, matrixID: UInt32) -> UInt32 {
        fnv32("\(modelName):address:0x\(String(matrixID * 0x40, radix: 16))")
    }

    private static func poseMatrix(
        pose: GESourceAnimationPoseV6,
        originQ16: SIMD3<Int32>
    ) -> simd_float4x4 {
        let translation = SIMD3<Float>(
            Float(pose.translation_q16.0) / 65_536,
            Float(pose.translation_q16.1) / 65_536,
            Float(pose.translation_q16.2) / 65_536
        )
        let origin = SIMD3<Float>(
            Float(originQ16.x) / 65_536,
            Float(originQ16.y) / 65_536,
            Float(originQ16.z) / 65_536
        )
        let scale = SIMD3<Float>(
            max(0.0001, Float(pose.scale_q16.0) / 65_536),
            max(0.0001, Float(pose.scale_q16.1) / 65_536),
            max(0.0001, Float(pose.scale_q16.2) / 65_536)
        )
        let rotation = rotationMatrix(
            x: Float(pose.rotation_q16.0) / 65_536,
            y: Float(pose.rotation_q16.1) / 65_536,
            z: Float(pose.rotation_q16.2) / 65_536
        )
        return translationMatrix(translation)
            * translationMatrix(origin)
            * rotation
            * scaleMatrix(scale)
            * translationMatrix(-origin)
    }

    private static func rotationMatrix(x: Float, y: Float, z: Float) -> simd_float4x4 {
        let cx = cos(x), sx = sin(x), cy = cos(y), sy = sin(y), cz = cos(z), sz = sin(z)
        let rx = simd_float4x4(
            SIMD4(1, 0, 0, 0), SIMD4(0, cx, sx, 0),
            SIMD4(0, -sx, cx, 0), SIMD4(0, 0, 0, 1)
        )
        let ry = simd_float4x4(
            SIMD4(cy, 0, -sy, 0), SIMD4(0, 1, 0, 0),
            SIMD4(sy, 0, cy, 0), SIMD4(0, 0, 0, 1)
        )
        let rz = simd_float4x4(
            SIMD4(cz, sz, 0, 0), SIMD4(-sz, cz, 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)
        )
        return rz * ry * rx
    }

    private static func translationMatrix(_ value: SIMD3<Float>) -> simd_float4x4 {
        var result = matrix_identity_float4x4
        result.columns.3 = SIMD4(value, 1)
        return result
    }

    private static func scaleMatrix(_ value: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(
            SIMD4(value.x, 0, 0, 0), SIMD4(0, value.y, 0, 0),
            SIMD4(0, 0, value.z, 0), SIMD4(0, 0, 0, 1)
        )
    }

    private static func matrixFromQ16(_ values: [Int32]) -> simd_float4x4 {
        guard values.count == 16 else { return matrix_identity_float4x4 }
        return simd_float4x4(
            SIMD4(Float(values[0]) / 65_536, Float(values[1]) / 65_536, Float(values[2]) / 65_536, Float(values[3]) / 65_536),
            SIMD4(Float(values[4]) / 65_536, Float(values[5]) / 65_536, Float(values[6]) / 65_536, Float(values[7]) / 65_536),
            SIMD4(Float(values[8]) / 65_536, Float(values[9]) / 65_536, Float(values[10]) / 65_536, Float(values[11]) / 65_536),
            SIMD4(Float(values[12]) / 65_536, Float(values[13]) / 65_536, Float(values[14]) / 65_536, Float(values[15]) / 65_536)
        )
    }

    private static func q16Matrix(_ matrix: simd_float4x4) -> [Int32] {
        let columns = [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3]
        return columns.flatMap { column in
            [column.x, column.y, column.z, column.w].map {
                Int32(max(Float(Int32.min) / 65_536, min(Float(Int32.max) / 65_536, $0)) * 65_536)
            }
        }
    }

    private static func splitTopLevel(_ value: String) -> [String] {
        var result: [String] = []
        var depth = 0
        var start = value.startIndex
        for index in value.indices {
            switch value[index] {
            case "{", "(": depth += 1
            case "}", ")": depth -= 1
            case "," where depth == 0:
                result.append(String(value[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines))
                start = value.index(after: index)
            default: break
            }
        }
        result.append(String(value[start...]).trimmingCharacters(in: .whitespacesAndNewlines))
        return result
    }

    private static func parseVector(_ value: String) -> SIMD3<Int32>? {
        let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "{} "))
        let values = trimmed.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 3 else { return nil }
        return SIMD3(values.map { Int32($0 * 65_536) })
    }

    private static func parseUnsigned(_ value: String) -> UInt32? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("0x") {
            return UInt32(trimmed.dropFirst(2), radix: 16)
        }
        return UInt32(trimmed)
    }

    private static func fnv32(_ value: String) -> UInt32 {
        var result: UInt32 = 2_166_136_261
        for byte in value.utf8 { result = (result ^ UInt32(byte)) &* 16_777_619 }
        return result == 0 ? 1 : result
    }
}
