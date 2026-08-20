import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// The copied source matrix values consumed by G_MTX.  These are fixed-width
/// values and never retain the source address that produced them.
struct GoldenEyeGBIMatrixResourceV6: Sendable, Equatable {
    let handle: UInt32
    let values: [Int32]
    /// Explicit source stack roles supplied by the frontend matrix provider.
    /// Zero is retained for legacy fixtures; production provider frames must
    /// name every matrix used by the scene builder.
    let roleFlags: UInt32

    init(handle: UInt32, values: [Int32], roleFlags: UInt32 = 0) throws {
        guard handle != 0, values.count == 16,
              roleFlags & ~UInt32(0x0f) == 0 else {
            throw GoldenEyeSourceProductContractV6Error.invalidMatrixResource(handle)
        }
        self.handle = handle
        self.values = values
        self.roleFlags = roleFlags
    }
}

/// The copied source viewport scale/translate tuple.
struct GoldenEyeGBIViewportResourceV6: Sendable, Equatable {
    let handle: UInt32
    let values: [Int32]

    init(handle: UInt32, values: [Int32]) throws {
        guard handle != 0, values.count == 8 else {
            throw GoldenEyeSourceProductContractV6Error.invalidViewportResource(handle)
        }
        self.handle = handle
        self.values = values
    }
}

/// Explicit source-frame matrices/viewports.  This value-only contract is
/// shared by the source matrix provider and the Metal product adapter; no
/// identity or guessed projection may be synthesized at this boundary.
struct GoldenEyeSourceProductFrameResourcesV6: Sendable, Equatable {
    let matrices: [GoldenEyeGBIMatrixResourceV6]
    let viewports: [GoldenEyeGBIViewportResourceV6]
    let viewportWidth: UInt32
    let viewportHeight: UInt32

    init(
        matrices: [GoldenEyeGBIMatrixResourceV6],
        viewports: [GoldenEyeGBIViewportResourceV6],
        viewportWidth: UInt32,
        viewportHeight: UInt32
    ) throws {
        guard !matrices.isEmpty, !viewports.isEmpty,
              viewportWidth > 0, viewportHeight > 0 else {
            throw GoldenEyeSourceProductContractV6Error.missingFrameResources
        }
        self.matrices = matrices
        self.viewports = viewports
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
    }
}

/// Value-only model request copied from a source frontend event.  It is kept
/// independent from the renderer so the owner can carry a request across one
/// authority step without retaining a callback, pointer, or scene object.
struct GoldenEyeSourceProductModelRequestV6: Sendable, Equatable {
    let screen: UInt32
    let model: UInt32
    let operation: UInt32
    let nativeTick: UInt64
    let referenceTick: UInt64
    let sourceTimer: UInt32
    let subphase: UInt32
    let flags: UInt32

    init(
        screen: UInt32,
        model: UInt32,
        operation: UInt32,
        nativeTick: UInt64,
        referenceTick: UInt64,
        sourceTimer: UInt32,
        subphase: UInt32,
        flags: UInt32
    ) throws {
        guard screen <= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_CAST),
              model != UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_NONE),
              operation != 0,
              operation <= UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_BLOOD_TICK),
              nativeTick > 0 else {
            throw GoldenEyeSourceProductContractV6Error.invalidModelRequest
        }
        self.screen = screen
        self.model = model
        self.operation = operation
        self.nativeTick = nativeTick
        self.referenceTick = referenceTick
        self.sourceTimer = sourceTimer
        self.subphase = subphase
        self.flags = flags
    }
}

/// The only result a source model adapter may hand back to the authority.
/// The executed bit is explicit; zero-valued fields mean that no result is
/// available and therefore cannot accidentally advance source state.
struct GoldenEyeSourceProductModelExecutionResultV6: Sendable, Equatable {
    let model: UInt32
    let operation: UInt32
    let flags: UInt32
    let value0: UInt32
    let value1: UInt32

    static func executed(
        model: UInt32,
        operation: UInt32,
        value0: UInt32 = 0,
        value1: UInt32 = 0
    ) -> Self {
        Self(
            model: model,
            operation: operation,
            flags: UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED),
            value0: value0,
            value1: value1
        )
    }

    static func sourceResult(
        model: UInt32,
        operation: UInt32,
        flags: UInt32,
        value0: UInt32 = 0,
        value1: UInt32 = 0
    ) -> Self {
        Self(model: model, operation: operation, flags: flags, value0: value0, value1: value1)
    }

    var isExecuted: Bool {
        flags & UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_RESULT_EXECUTED) != 0
    }
}

/// Source render-event classification used before a scene is built.  A
/// frame-begin marker is metadata; a clear-only frame has at least one real
/// CLEAR_BLACK operation and no model/text event to render.
enum GoldenEyeSourceProductFrameClassifierV6 {
    static func isClearBlackOnly(
        renderOperations: [UInt32],
        modelEventCount: Int,
        textEventCount: Int
    ) -> Bool {
        guard modelEventCount == 0, textEventCount == 0 else { return false }
        let visibleOperations = renderOperations.filter {
            $0 != UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_FRAME_BEGIN)
        }
        guard !visibleOperations.isEmpty else { return false }
        return visibleOperations.allSatisfy {
            $0 == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_RENDER_CLEAR_BLACK)
        }
    }
}

enum GoldenEyeSourceProductContractV6Error: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidModelRequest
    case missingFrameResources
    case invalidMatrixResource(UInt32)
    case invalidViewportResource(UInt32)

    var description: String {
        switch self {
        case .invalidModelRequest: return "invalid source product model request"
        case .missingFrameResources: return "missing source product frame resources"
        case .invalidMatrixResource(let handle): return "invalid source product matrix resource \(handle)"
        case .invalidViewportResource(let handle): return "invalid source product viewport resource \(handle)"
        }
    }
}
