import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Explicit roles for copied source matrices.  The role is metadata supplied
/// by the frontend matrix provider; it is never derived from a handle prefix.
/// Values are bit flags so a source matrix may deliberately be shared by two
/// source stacks while the provider still records that choice explicitly.
struct GoldenEyeSourceMatrixRoleSidecarV6: Sendable, Equatable, Hashable {
    static let modelView: UInt32 = 1 << 0
    static let projection: UInt32 = 1 << 1
    static let camera: UInt32 = 1 << 2
    static let reflection: UInt32 = 1 << 3
    static let knownMask: UInt32 = modelView | projection | camera | reflection

    let handle: UInt32
    let roleFlags: UInt32

    init(handle: UInt32, roleFlags: UInt32) throws {
        guard handle != 0,
              roleFlags != 0,
              roleFlags & ~Self.knownMask == 0 else {
            throw GoldenEyeSourceProjectionBindingV6Error.invalidRole(handle)
        }
        self.handle = handle
        self.roleFlags = roleFlags
    }

    var isModelView: Bool { roleFlags & Self.modelView != 0 }
    var isProjection: Bool { roleFlags & Self.projection != 0 }
}

/// The exact source inputs used to make one Metal clip transform.  All matrix
/// values are signed Q16.16 values copied from the source matrix provider.
struct GoldenEyeSourceProjectionClipInputsV6: Sendable, Equatable {
    let modelViewHandle: UInt32
    let projectionHandle: UInt32
    let viewportHandle: UInt32
    let modelViewQ16: [Int32]
    let projectionQ16: [Int32]
    let viewportQ16: [Int32]

    init(
        modelViewHandle: UInt32,
        projectionHandle: UInt32,
        viewportHandle: UInt32,
        modelViewQ16: [Int32],
        projectionQ16: [Int32],
        viewportQ16: [Int32]
    ) throws {
        guard modelViewHandle != 0, projectionHandle != 0,
              viewportHandle != 0,
              modelViewQ16.count == 16,
              projectionQ16.count == 16,
              viewportQ16.count == 8 else {
            throw GoldenEyeSourceProjectionBindingV6Error.invalidInputs
        }
        try GoldenEyeSourceProjectionBindingV6.validateViewport(viewportQ16)
        self.modelViewHandle = modelViewHandle
        self.projectionHandle = projectionHandle
        self.viewportHandle = viewportHandle
        self.modelViewQ16 = modelViewQ16
        self.projectionQ16 = projectionQ16
        self.viewportQ16 = viewportQ16
    }
}

/// The result of composing the source modelview and projection matrices for
/// Metal.  ``clipMatrixQ16`` includes the homogeneous depth conversion
/// z'=(z+w)/2 required when source clip space is [-w,+w] and Metal clip space
/// is [0,+w].  The top-left Metal viewport owns the source Y-origin
/// conversion. Viewport records remain separate source evidence and are not
/// folded into this matrix; the renderer owns the drawable viewport state.
struct GoldenEyeSourceProjectionClipResultV6: Sendable, Equatable {
    let clipMatrixQ16: [Int32]
    let modelViewHandle: UInt32
    let projectionHandle: UInt32
    let viewportHandle: UInt32
    let sourceHash: UInt64

    init(inputs: GoldenEyeSourceProjectionClipInputsV6) {
        let combined = GoldenEyeSourceProjectionBindingV6.composeClipMatrix(
            modelViewQ16: inputs.modelViewQ16,
            projectionQ16: inputs.projectionQ16
        )
        self.clipMatrixQ16 = combined
        self.modelViewHandle = inputs.modelViewHandle
        self.projectionHandle = inputs.projectionHandle
        self.viewportHandle = inputs.viewportHandle
        self.sourceHash = GoldenEyeSourceProjectionBindingV6.hashInputs(inputs, clipMatrixQ16: combined)
    }
}

enum GoldenEyeSourceProjectionBindingV6Error: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case invalidRole(UInt32)
    case duplicateRole(UInt32)
    case invalidInputs
    case missingRole(UInt32)
    case invalidViewport
    case invalidViewportOrientation
    case invalidPoint
    case invalidClipW

    var description: String {
        switch self {
        case .invalidRole(let handle): return "invalid source matrix role for 0x\(String(handle, radix: 16))"
        case .duplicateRole(let handle): return "duplicate source matrix role for 0x\(String(handle, radix: 16))"
        case .invalidInputs: return "invalid source projection inputs"
        case .missingRole(let handle): return "source matrix role is missing for 0x\(String(handle, radix: 16))"
        case .invalidViewport: return "invalid source viewport"
        case .invalidViewportOrientation: return "source viewport orientation is not top-left Metal compatible"
        case .invalidPoint: return "invalid source projection point"
        case .invalidClipW: return "source projection point has non-positive clip w"
        }
    }
}

/// Fixed-point source projection/clip lowering shared by the scene builder
/// and headless evidence tests.  It intentionally has no floating-point
/// operations in the matrix product or point transform.
enum GoldenEyeSourceProjectionBindingV6 {
    static let q16One: Int64 = 65_536
    static let q16Half: Int32 = 32_768
    static let clipCompositeFlag: UInt32 = 1 << 3

    /// The provider's role table is a value-only sidecar.  Every supplied
    /// matrix must be named exactly once; an empty table is allowed only for
    /// the legacy source-command role fallback in the builder and never
    /// makes projection consumption complete by itself.
    static func roleMap(
        _ roles: [GoldenEyeSourceMatrixRoleSidecarV6]
    ) throws -> [UInt32: UInt32] {
        var result: [UInt32: UInt32] = [:]
        result.reserveCapacity(roles.count)
        for role in roles {
            guard result[role.handle] == nil else {
                throw GoldenEyeSourceProjectionBindingV6Error.duplicateRole(role.handle)
            }
            result[role.handle] = role.roleFlags
        }
        return result
    }

    /// Column-major Q16.16 matrix product.  The source ``Mtxf.m[column][row]``
    /// order is also the order consumed by ``simd_float4x4(columns:)`` in the
    /// Metal renderer; no handle or address is consulted.
    static func multiply(_ left: [Int32], _ right: [Int32]) -> [Int32] {
        precondition(left.count == 16 && right.count == 16)
        var output = Array(repeating: Int32(0), count: 16)
        for row in 0..<4 {
            for column in 0..<4 {
                var accumulator: Int64 = 0
                for element in 0..<4 {
                    let product = Int64(left[element * 4 + row])
                        * Int64(right[column * 4 + element])
                    accumulator = saturatingAdd(accumulator, product)
                }
                output[column * 4 + row] = quantizedProduct(accumulator)
            }
        }
        return output
    }

    /// Compose ``sourceToMetal * projection * modelview``. N64/OpenGL uses a
    /// symmetric depth interval; Metal uses zero-to-positive-w. The top-left
    /// viewport owns Y orientation, so the clip adapter only applies
    /// z' = 0.5*z + 0.5*w, w' = w.
    static func composeClipMatrix(
        modelViewQ16: [Int32],
        projectionQ16: [Int32]
    ) -> [Int32] {
        precondition(modelViewQ16.count == 16 && projectionQ16.count == 16)
        var depthMap = Array(repeating: Int32(0), count: 16)
        depthMap[0] = Int32(q16One)
        // Metal's top-left viewport already maps its native clip Y orientation
        // to the source framebuffer convention.  Do not apply a second Y flip
        // here: doing so reverses character head/hip ordering in the source
        // scene while the viewport boundary has already handled the origin.
        depthMap[5] = Int32(q16One)
        depthMap[10] = q16Half
        depthMap[14] = q16Half
        depthMap[15] = Int32(q16One)
        return multiply(depthMap, multiply(projectionQ16, modelViewQ16))
    }

    /// Apply a Q16 matrix to a source Q16 point, retaining the homogeneous w.
    static func apply(
        matrixQ16: [Int32],
        pointQ16: (x: Int32, y: Int32, z: Int32)
    ) throws -> (x: Int32, y: Int32, z: Int32, w: Int32) {
        guard matrixQ16.count == 16 else {
            throw GoldenEyeSourceProjectionBindingV6Error.invalidPoint
        }
        let input = [pointQ16.x, pointQ16.y, pointQ16.z, Int32(q16One)]
        var output = [Int32](repeating: 0, count: 4)
        for row in 0..<4 {
            var accumulator: Int64 = 0
            for column in 0..<4 {
                let product = Int64(matrixQ16[column * 4 + row])
                    * Int64(input[column])
                accumulator = saturatingAdd(accumulator, product)
            }
            output[row] = quantizedProduct(accumulator)
        }
        return (output[0], output[1], output[2], output[3])
    }

    /// Convert source NDC through the copied N64 viewport and then into Metal
    /// NDC.  This is an evidence helper; actual drawable dimensions remain a
    /// separate renderer concern.  It proves the source viewport's y-down
    /// orientation without changing the source matrix records.
    static func viewportToMetalNDC(
        ndcXQ16: Int32,
        ndcYQ16: Int32,
        viewportQ16: [Int32]
    ) throws -> (x: Int32, y: Int32) {
        try validateViewport(viewportQ16)
        let screenX = quantizedProduct(
            saturatingAdd(
                Int64(ndcXQ16) * Int64(viewportQ16[0]),
                Int64(viewportQ16[4]) * q16One
            )
        )
        let screenY = quantizedProduct(
            saturatingAdd(
                Int64(ndcYQ16) * Int64(viewportQ16[1]),
                Int64(viewportQ16[5]) * q16One
            )
        )
        let widthQ16 = Int64(viewportQ16[0]) * 2
        let heightQ16 = Int64(viewportQ16[1]) * 2
        guard widthQ16 > 0, heightQ16 > 0 else {
            throw GoldenEyeSourceProjectionBindingV6Error.invalidViewport
        }
        let metalX = roundDivide(
            (Int64(screenX) * 2 - widthQ16) * q16One,
            widthQ16
        )
        // Source viewport coordinates increase downward.  Reversing y here
        // yields Metal's upward-positive NDC orientation.
        let metalY = roundDivide(
            (heightQ16 - Int64(screenY) * 2) * q16One,
            heightQ16
        )
        return (saturatingInt32(metalX), saturatingInt32(metalY))
    }

    static func validateViewport(_ values: [Int32]) throws {
        guard values.count == 8,
              values[0] > 0, values[2] > 0,
              values[3] == Int32(q16One),
              values[6] >= 0,
              values[7] == Int32(q16One) else {
            throw GoldenEyeSourceProjectionBindingV6Error.invalidViewport
        }
        // The source frontend's viewport is y-down: positive scale and a
        // positive half-height.  A negative scale is a different source
        // convention and must be represented by an explicit future role.
        guard values[1] > 0 else {
            throw GoldenEyeSourceProjectionBindingV6Error.invalidViewportOrientation
        }
    }

    static func hashInputs(
        _ inputs: GoldenEyeSourceProjectionClipInputsV6,
        clipMatrixQ16: [Int32]
    ) -> UInt64 {
        var hash = UInt64(1_469_598_103_934_665_603)
        for value in [inputs.modelViewHandle, inputs.projectionHandle, inputs.viewportHandle] {
            hash = hashU32(hash, value)
        }
        for value in inputs.modelViewQ16 + inputs.projectionQ16 + inputs.viewportQ16 + clipMatrixQ16 {
            hash = hashU32(hash, UInt32(bitPattern: value))
        }
        return hash == 0 ? 1 : hash
    }

    /// Make an additive clip-composite V6 transform without changing the
    /// existing 112-byte record.  parent_handle/source_node/viewport_id carry
    /// the exact source input handles for audit and hash reconstruction.
    static func makeTransform(
        handle: UInt32,
        inputs: GoldenEyeSourceProjectionClipInputsV6
    ) throws -> GESourceTransformV6 {
        guard handle != 0 else {
            throw GoldenEyeSourceProjectionBindingV6Error.invalidInputs
        }
        let result = GoldenEyeSourceProjectionClipResultV6(inputs: inputs)
        var transform = GESourceTransformV6()
        transform.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        transform.header.struct_size = UInt32(MemoryLayout<GESourceTransformV6>.size)
        transform.record_version = UInt32(GE_SOURCE_SCENE_V6_RECORD_VERSION)
        transform.transform_kind = UInt32(GE_SOURCE_TRANSFORM_V6_CLIP_COMPOSITE)
        transform.flags = UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_SOURCE_QUANTIZED)
            | UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_CLIP_COMPOSITE)
        transform.handle = handle
        transform.parent_handle = inputs.modelViewHandle
        transform.source_node = inputs.projectionHandle
        transform.viewport_id = inputs.viewportHandle
        setInt32Tuple(&transform.matrix_q16, values: result.clipMatrixQ16)
        guard ge_source_scene_v6_validate_transform(&transform) == GE_STATUS_OK else {
            throw GoldenEyeSourceProjectionBindingV6Error.invalidInputs
        }
        return transform
    }

    private static func setInt32Tuple<T>(_ tuple: inout T, values: [Int32]) {
        withUnsafeMutableBytes(of: &tuple) { raw in
            let typed = raw.bindMemory(to: Int32.self)
            for index in values.indices where index < typed.count {
                typed[index] = values[index]
            }
        }
    }
    @inline(__always)
    private static func quantizedProduct(_ accumulator: Int64) -> Int32 {
        let rounded: Int64
        if accumulator >= 0 {
            rounded = accumulator > Int64.max - 32_768
                ? Int64.max
                : (accumulator + 32_768) >> 16
        } else {
            let magnitude = accumulator == Int64.min ? Int64.max : -accumulator
            rounded = -((magnitude + 32_768) >> 16)
        }
        return saturatingInt32(rounded)
    }

    @inline(__always)
    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        if rhs > 0 && lhs > Int64.max - rhs { return Int64.max }
        if rhs < 0 && lhs < Int64.min - rhs { return Int64.min }
        return lhs + rhs
    }

    @inline(__always)
    private static func saturatingInt32(_ value: Int64) -> Int32 {
        if value > Int64(Int32.max) { return Int32.max }
        if value < Int64(Int32.min) { return Int32.min }
        return Int32(value)
    }

    @inline(__always)
    private static func roundDivide(_ numerator: Int64, _ denominator: Int64) -> Int64 {
        guard denominator != 0 else { return numerator >= 0 ? Int64.max : Int64.min }
        let positive = (numerator >= 0) == (denominator >= 0)
        let numeratorMagnitude = numerator == Int64.min ? Int64.max : (numerator >= 0 ? numerator : -numerator)
        let denominatorMagnitude = denominator == Int64.min ? Int64.max : (denominator >= 0 ? denominator : -denominator)
        let quotient = numeratorMagnitude / denominatorMagnitude
        let remainder = numeratorMagnitude % denominatorMagnitude
        let rounded = quotient + (remainder >= (denominatorMagnitude + 1) / 2 ? 1 : 0)
        return positive ? rounded : -rounded
    }

    private static func hashU32(_ hash: UInt64, _ value: UInt32) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 24, by: 8) {
            result = (result ^ UInt64((value >> UInt32(shift)) & 0xff))
                &* 1_099_511_628_211
        }
        return result
    }
}
