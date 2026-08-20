import Foundation
#if !GE_SOURCE_MATRIX_STANDALONE
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
#endif

/// Source-faithful title camera and model matrices.
///
/// The formulas in this file are copied from the portable source rather than
/// from the diagnostic renderer:
///
///   * `src/game/front.c:1515-1537` (Legal)
///   * `src/game/front.c:1714-1731` (Nintendo)
///   * `src/game/front.c:1951-1987` (GoldenEye and look-at reflection)
///   * `src/game/front.c:2239-2254` (folder wallets)
///   * `src/libultra/gu/perspective.c:17-44` (projection)
///   * `src/game/matrixmath.c:423-435,495-511,586-644` (source matrix
///     arithmetic and s15.16 conversion)
///
/// It deliberately emits copied values only.  No source address, ROM offset,
/// model pointer, Metal object, or identity fallback is retained.
#if GE_SOURCE_MATRIX_STANDALONE
/// Test-only copy of the production value boundary.  The focused standalone
/// smoke compiles this file without the Metal product renderer.
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
            throw GoldenEyeSourceFrontendMatricesV6Error.invalidInput
        }
        self.matrices = matrices
        self.viewports = viewports
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
    }
}

struct GoldenEyeGBIMatrixResourceV6: Sendable, Equatable {
    let handle: UInt32
    let values: [Int32]
    let roleFlags: UInt32

    init(handle: UInt32, values: [Int32], roleFlags: UInt32 = 0) throws {
        guard handle != 0, values.count == 16,
              roleFlags & ~UInt32(0x0f) == 0 else {
            throw GoldenEyeSourceFrontendMatricesV6Error.invalidInput
        }
        self.handle = handle
        self.values = values
        self.roleFlags = roleFlags
    }
}

struct GoldenEyeGBIViewportResourceV6: Sendable, Equatable {
    let handle: UInt32
    let values: [Int32]

    init(handle: UInt32, values: [Int32]) throws {
        guard handle != 0, values.count == 8 else {
            throw GoldenEyeSourceFrontendMatricesV6Error.invalidInput
        }
        self.handle = handle
        self.values = values
    }
}
#endif

/// A fixed-width input for callers that already resolved the source display
/// list's matrix handle.  The production frontend overload below copies the
/// same fields from `GoldenEyeSourceFrontendFrameV6`.
struct GoldenEyeSourceFrontendMatrixInputV6: Sendable, Equatable {
    let screen: UInt32
    let nativeTick: UInt64
    let referenceTick: UInt64
    let sourceTimer: UInt32
    let pairPhase: UInt32

    init(
        screen: UInt32,
        nativeTick: UInt64,
        referenceTick: UInt64,
        sourceTimer: UInt32,
        pairPhase: UInt32
    ) throws {
        guard nativeTick > 0, pairPhase <= 1 else {
            throw GoldenEyeSourceFrontendMatricesV6Error.invalidInput
        }
        self.screen = screen
        self.nativeTick = nativeTick
        self.referenceTick = referenceTick
        self.sourceTimer = sourceTimer
        self.pairPhase = pairPhase
    }
}

enum GoldenEyeSourceFrontendMatricesV6Error: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case invalidInput
    case unsupportedScreen(UInt32)
    case invalidSelection(UInt32)
    case modelScreenMismatch(String, UInt32)
    case missingModelMatrixHandle(String)
    case dynamicDependency(String)
    case duplicateHandle(UInt32)

    var description: String {
        switch self {
        case .invalidInput: return "invalid source frontend matrix input"
        case .unsupportedScreen(let screen): return "unsupported source matrix screen \(screen)"
        case .invalidSelection(let selection):
            return "source frontend folder selection is outside 0...3: \(selection)"
        case .modelScreenMismatch(let model, let screen):
            return "source matrix model \(model) does not match screen \(screen)"
        case .missingModelMatrixHandle(let model):
            return "source model \(model) has no gsSPMatrix handle"
        case .dynamicDependency(let detail): return "source matrix dynamic dependency: \(detail)"
        case .duplicateHandle(let handle): return "duplicate source matrix handle 0x\(String(handle, radix: 16))"
        }
    }
}

/// The copied matrix result and deterministic evidence for one source frame.
/// SIMD fields are fixed-width; the resource arrays are copied into the
/// existing bounded product-frame value boundary.
struct GoldenEyeSourceFrontendMatrixFrameV6: Sendable, Equatable {
    let input: GoldenEyeSourceFrontendMatrixInputV6
    let resources: GoldenEyeSourceProductFrameResourcesV6
    let modelMatrixHandles: [UInt32]
    let cameraMatrixHandle: UInt32
    let projectionMatrixHandle: UInt32
    let reflectionMatrixHandle: UInt32
    let modelMatrixQ16: SIMD16<Int32>
    let cameraMatrixQ16: SIMD16<Int32>
    let projectionMatrixQ16: SIMD16<Int32>
    let reflectionMatrixQ16: SIMD16<Int32>
    let reflectionRightQ7: SIMD4<Int32>
    let reflectionUpQ7: SIMD4<Int32>
    let matrixHash: UInt64
    let viewportHash: UInt64
    let frameHash: UInt64

    /// Visible source model handles after the screen-specific constructor has
    /// applied its transforms.  File Select carries four .37 wallet
    /// instances; Mode Select carries the selected-folder .25 instance.
    let visibleModelMatrixHandles: [UInt32]
}

enum GoldenEyeSourceFrontendMatricesV6 {
#if GE_SOURCE_MATRIX_STANDALONE
    static let screenLegal: UInt32 = 0
    static let screenNintendo: UInt32 = 1
    static let screenRareware: UInt32 = 2
    static let screenGunbarrel: UInt32 = 3
    static let screenGoldenEye: UInt32 = 4
    static let screenFileSelect: UInt32 = 5
    static let screenModeSelect: UInt32 = 6
#else
    static let screenLegal: UInt32 = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_LEGAL)
    static let screenNintendo: UInt32 = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_NINTENDO)
    static let screenRareware: UInt32 = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_RAREWARE)
    static let screenGunbarrel: UInt32 = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GUNBARREL)
    static let screenGoldenEye: UInt32 = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_GOLDENEYE)
    static let screenFileSelect: UInt32 = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_FILE_SELECT)
    static let screenModeSelect: UInt32 = UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_SCREEN_MODE_SELECT)
#endif

    private static let q16One: Float = 65_536.0
    private static let q16OneI: Int64 = 65_536
    private static let piDegrees: Float = 3.1415926
    private static let roleModelView: UInt32 = 1 << 0
    private static let roleProjection: UInt32 = 1 << 1
    private static let roleCamera: UInt32 = 1 << 2
    private static let roleReflection: UInt32 = 1 << 3

    private static let sourceViewportHandle: UInt32 = 0xF100_0001
    private static let auxiliaryHandlePrefix: UInt32 = 0xF100_0000

    private static let folderPositions: [(Float, Float, Float)] = [
        (-900.0, 800.0, 0.0),
        (1800.0, 800.0, 0.0),
        (-1800.0, -200.0, 0.0),
        (900.0, -200.0, 0.0),
    ]

    /// Build resources when the caller has already copied the source
    /// display-list matrix handle.  This is also the deterministic fixture
    /// entry point used by the focused smoke.
    static func make(
        input: GoldenEyeSourceFrontendMatrixInputV6,
        modelMatrixHandle: UInt32,
        viewportWidth: UInt32 = 440,
        viewportHeight: UInt32 = 330,
        selectedFolder: UInt32 = 0
    ) throws -> GoldenEyeSourceFrontendMatrixFrameV6 {
        guard modelMatrixHandle != 0, viewportWidth > 0, viewportHeight > 0 else {
            throw GoldenEyeSourceFrontendMatricesV6Error.invalidInput
        }
        guard selectedFolder < UInt32(folderPositions.count) else {
            throw GoldenEyeSourceFrontendMatricesV6Error.invalidSelection(selectedFolder)
        }
        guard input.screen <= screenModeSelect else {
            throw GoldenEyeSourceFrontendMatricesV6Error.unsupportedScreen(input.screen)
        }
        var camera: [Float]
        if input.screen == screenRareware {
            camera = sourceLookAtTarget(
                eye: (0, 0, 880), target: (0, 0, 879), up: (0, 1, 0)
            )
        } else if input.screen == screenGunbarrel {
            camera = sourceLookAtTarget(
                eye: (1758.2957, 220.0, 684.28143),
                target: (1757.3257, 220.0, 684.52143),
                up: (0, 1, 0)
            )
        } else {
            camera = sourceLookAtTarget(
                eye: (0, 0, 4000), target: (0, 0, 0), up: (0, 1, 0)
            )
        }
        var reflectionCamera = camera
        let projection = sourcePerspective(
            fovyDegrees: input.screen == screenGunbarrel ? 46.0 : 60.0,
            aspect: 1.3333334,
            near: input.screen == screenGunbarrel ? 10.0 : 100.0,
            far: input.screen == screenRareware ? 5000.0 : 10000.0
        )

        let cameraHandle = auxiliaryHandle(screen: input.screen, role: 1, index: 0)
        let projectionHandle = auxiliaryHandle(screen: input.screen, role: 2, index: 0)
        let reflectionHandle = auxiliaryHandle(screen: input.screen, role: 3, index: 0)

        var modelMatrices: [[Float]] = []
        var modelHandles: [UInt32] = []
        var visibleHandles: [UInt32] = []

        switch input.screen {
        case screenLegal:
            modelMatrices = [camera]
            modelHandles = [modelMatrixHandle]
            visibleHandles = modelHandles

        case screenGunbarrel:
            // insert_bond_eye_intro loads the source 46 degree projection and
            // the title.c Gunbarrel look-at matrix before model traversal.
            // title.c passes this unscaled look-at matrix as
            // ModelRenderData.basemtx. modelSetScale is applied by the model
            // root/header local matrix, not to the camera basis.
            let model = camera
            modelMatrices = [model]
            modelHandles = [modelMatrixHandle]
            visibleHandles = modelHandles

        case screenNintendo:
            let motion = nintendoMotion(sourceTimer: input.sourceTimer, pairPhase: input.pairPhase)
            var model = sourceRotationY(motion.rotationRadians)
            sourceScalarMultiply3(motion.scale, matrix: &model)
            model = sourceMultiply(camera, model)
            modelMatrices = [model]
            modelHandles = [modelMatrixHandle]
            visibleHandles = modelHandles

        case screenRareware:
            // title.c/load_display_rare_logo establishes the outer camera
            // and projection before the dedicated segment is called.  The
            // segment itself intentionally has no gsSPMatrix command, so the
            // provider carries that setup as explicit value-only resources.
            let motion = rarewareMotion(
                sourceTimer: input.sourceTimer,
                pairPhase: input.pairPhase
            )
            var model = sourceRotationY(motion.rotationRadians)
            model = sourceMultiply(camera, model)
            modelMatrices = [model]
            modelHandles = [modelMatrixHandle]
            visibleHandles = modelHandles

        case screenGoldenEye:
            var model = sourceLookAtTarget(
                eye: (0, 0, 3000), target: (0, 0, 0), up: (0, 1, 0)
            )
            // front.c calls matrix_scalar_multiply(1.2f, logoMatrix.m[0]),
            // whose source implementation scales exactly the first 12
            // floats and leaves the translation row untouched.
            sourceScalarMultiply(1.2, matrix: &model)
            modelMatrices = [model]
            modelHandles = [modelMatrixHandle]
            visibleHandles = modelHandles

        case screenFileSelect:
            for (index, position) in folderPositions.enumerated() {
                let wallet = sourceWalletMatrix(
                    camera: camera, position: position, scale: 0.37
                )
                let handle: UInt32 = index == 0
                    ? modelMatrixHandle
                    : auxiliaryHandle(screen: input.screen, role: 4, index: UInt32(index))
                modelMatrices.append(wallet)
                modelHandles.append(handle)
                visibleHandles.append(handle)
            }

        case screenModeSelect:
            // frontSetupMenuBackground (front.c:2833-2881) is called by the
            // mode-select constructor.  It uses the selected folder's
            // camera-space offsets and a .25 wallet scale.
            let position = folderPositions[Int(selectedFolder)]
            let eye: (Float, Float, Float) = (position.0, position.1 + 190.0, 4000.0 - 3300.0)
            camera = sourceLookAtTarget(
                eye: eye,
                target: (eye.0, eye.1, 0),
                up: (0, 1, 0)
            )
            reflectionCamera = camera
            modelMatrices = [sourceWalletMatrix(
                camera: camera,
                position: position,
                scale: 0.25
            )]
            modelHandles = [modelMatrixHandle]
            visibleHandles = modelHandles

        default:
            throw GoldenEyeSourceFrontendMatricesV6Error.unsupportedScreen(input.screen)
        }

        var matrices: [GoldenEyeGBIMatrixResourceV6] = []
        matrices.reserveCapacity(max(4, modelMatrices.count + 3))
        for (handle, matrix) in zip(modelHandles, modelMatrices) {
            try appendUnique(
                &matrices,
                GoldenEyeGBIMatrixResourceV6(
                    handle: handle,
                    values: packSourceMatrix(matrix),
                    roleFlags: roleModelView
                )
            )
        }
        try appendUnique(
            &matrices,
            GoldenEyeGBIMatrixResourceV6(
                handle: cameraHandle,
                values: packSourceMatrix(camera),
                roleFlags: roleCamera
            )
        )
        try appendUnique(
            &matrices,
            GoldenEyeGBIMatrixResourceV6(
                handle: projectionHandle,
                values: packSourceMatrix(projection),
                roleFlags: roleProjection
            )
        )
        try appendUnique(
            &matrices,
            GoldenEyeGBIMatrixResourceV6(
                handle: reflectionHandle,
                values: packSourceMatrix(reflectionCamera),
                roleFlags: roleReflection
            )
        )

        let viewport = try sourceViewport(
            handle: sourceViewportHandle,
            width: viewportWidth,
            height: viewportHeight
        )
        let resources = try GoldenEyeSourceProductFrameResourcesV6(
            matrices: matrices,
            viewports: [viewport],
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight
        )

        let modelQ16 = simdMatrix(packSourceMatrix(modelMatrices.first ?? camera))
        let cameraQ16 = simdMatrix(packSourceMatrix(camera))
        let projectionQ16 = simdMatrix(packSourceMatrix(projection))
        let reflectionQ16 = simdMatrix(packSourceMatrix(reflectionCamera))
        let rightQ7 = SIMD4<Int32>(127, 0, 0, 0)
        let upQ7 = SIMD4<Int32>(0, 127, 0, 0)
        let matrixHash = hashMatrices(matrices)
        let viewportHash = hashViewports([viewport])
        var frameHash = hashU64(matrixHash, viewportHash)
        frameHash = hashU64(frameHash, input.nativeTick)
        frameHash = hashU32(frameHash, input.sourceTimer)
        frameHash = hashU32(frameHash, input.pairPhase)

        return GoldenEyeSourceFrontendMatrixFrameV6(
            input: input,
            resources: resources,
            modelMatrixHandles: modelHandles,
            cameraMatrixHandle: cameraHandle,
            projectionMatrixHandle: projectionHandle,
            reflectionMatrixHandle: reflectionHandle,
            modelMatrixQ16: modelQ16,
            cameraMatrixQ16: cameraQ16,
            projectionMatrixQ16: projectionQ16,
            reflectionMatrixQ16: reflectionQ16,
            reflectionRightQ7: rightQ7,
            reflectionUpQ7: upQ7,
            matrixHash: matrixHash,
            viewportHash: viewportHash,
            frameHash: frameHash,
            visibleModelMatrixHandles: visibleHandles
        )
    }

#if !GE_SOURCE_MATRIX_STANDALONE
    /// Resolve the exact matrix handle from the guarded GESM command stream,
    /// then produce the same copied frame values as the raw-handle entry
    /// point.  Dynamic models fail closed instead of receiving an identity.
    static func make(
        frame: GoldenEyeSourceFrontendFrameV6,
        model: GoldenEyeSourceModelV6,
        modelName: String,
        viewportWidth: UInt32 = 440,
        viewportHeight: UInt32 = 330
    ) throws -> GoldenEyeSourceFrontendMatrixFrameV6 {
        // The legacy runtime snapshot keeps selection at its immutable
        // source default.  File/Mode authority carries the actual selected
        // wallet in its additive value-only sidecar; consume that when
        // present so Mode Select's single-wallet camera follows persistence.
        let selectedFolder = frame.fileModeFrame?.state.selectedFolder
            ?? frame.summary.selection
        guard selectedFolder < 4 else {
            throw GoldenEyeSourceFrontendMatricesV6Error.invalidSelection(selectedFolder)
        }
        let input = try GoldenEyeSourceFrontendMatrixInputV6(
            screen: frame.screen,
            nativeTick: frame.nativeTick,
            referenceTick: frame.referenceTick,
            sourceTimer: frame.sourceTimer,
            pairPhase: frame.nativeTick & 1 == 0 ? 0 : 1
        )
        let expectedModel: String
        switch frame.screen {
        case screenLegal: expectedModel = "legalpage"
        case screenNintendo: expectedModel = "nintendologo"
        case screenGunbarrel: expectedModel = "suitbond"
        case screenGoldenEye: expectedModel = "goldeneyelogo"
        case screenRareware: expectedModel = "rarewarelogo"
        case screenFileSelect, screenModeSelect: expectedModel = "walletbond"
        default:
            throw GoldenEyeSourceFrontendMatricesV6Error.unsupportedScreen(frame.screen)
        }
        guard modelName == expectedModel else {
            throw GoldenEyeSourceFrontendMatricesV6Error.modelScreenMismatch(modelName, frame.screen)
        }
        var handles: [UInt32] = []
        // Resolve the typed matrix token directly from the guarded command
        // row. Matrix resources are value-only handles; compiling every GESM
        // macro here would make the provider depend on unrelated numeric
        // combiner/OtherMode aliases that the scene builder lowers separately.
        for (index, command) in model.commands.enumerated()
            where command.semantic.hasPrefix("gsSPMatrix") {
            guard let first = model.tokens(for: index).first else { continue }
            let handle = first.encodedValue
            if handle != 0, !handles.contains(handle) { handles.append(handle) }
        }
        let handle: UInt32
        if frame.screen == screenRareware, handles.isEmpty {
            // The dedicated segment has no gsSPMatrix command.  This stable
            // value is the copied source setup resource handle used by the
            // dynamic segment resolver; it is not a source address.
            handle = 0xF300_0001
        } else if frame.screen == screenGunbarrel {
            // Gunbarrel's character display-list bodies contain one source
            // matrix load per authored part, not one graph-wide matrix.  The
            // first handle seeds the shared camera/projection frame; the
            // provider appends every remaining guarded handle below before
            // the dynamic scene is built.
            guard let first = handles.first else {
                throw GoldenEyeSourceFrontendMatricesV6Error.missingModelMatrixHandle(modelName)
            }
            handle = first
        } else {
            guard let first = handles.first, handles.count == 1 else {
                throw GoldenEyeSourceFrontendMatricesV6Error.missingModelMatrixHandle(modelName)
            }
            handle = first
        }
        return try make(
            input: input,
            modelMatrixHandle: handle,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight,
            selectedFolder: selectedFolder
        )
    }
#endif

    private static func sourceWalletMatrix(
        camera: [Float],
        position: (Float, Float, Float),
        scale: Float
    ) -> [Float] {
        var wallet = sourceIdentityAndPosition(position)
        sourceScalarMultiply(scale, matrix: &wallet)
        // This is the exact source matrix_4x4_multiply_in_place(lhs, rhs):
        // the result is written into the rhs wallet matrix.
        return sourceMultiply(camera, wallet)
    }

    private static func nintendoMotion(
        sourceTimer: UInt32,
        pairPhase: UInt32
    ) -> (rotationRadians: Float, scale: Float) {
        let count = Int(sourceTimer)
        let initialRotation = Float(-1.39626348019)
        let rotationStep = Float(0.017453292)
        let initialScale = Float(0.0183333326131)
        let multiplier = Float(1.07977)
        // front.c increments ninLogoRotRate before constructing the current
        // frame matrix (lines 1702-1715).  Scale is multiplied only after the
        // matrix consumes the current value (lines 1717-1724).
        let rotation = initialRotation + rotationStep * Float(count + 1)
        var scale = initialScale
        if count > 0 {
            for _ in 0..<count {
                scale *= multiplier
                if scale > 1.1 { scale = 1.1 }
            }
        }
        guard pairPhase == 1 else { return (rotation, scale) }
        var nextScale = scale * multiplier
        if nextScale > 1.1 { nextScale = 1.1 }
        return (
            rotation + rotationStep * 0.5,
            scale + (nextScale - scale) * 0.5
        )
    }

    private static func rarewareMotion(
        sourceTimer: UInt32,
        pairPhase: UInt32
    ) -> (rotationRadians: Float, rotationDegreesQ16: Int32) {
        // setupRarewareLogoData initializes D_8002A89C to -40 degrees and
        // load_display_rare_logo advances it by 2 degrees after each NTSC
        // source frame.  The paired native odd tick is the exact midpoint.
        let degrees = -40.0 + Float(sourceTimer) * 2.0 +
            (pairPhase == 1 ? 1.0 : 0.0)
        return (
            degrees * piDegrees / 180.0,
            Int32((degrees * q16One).rounded())
        )
    }

    /// Source `matrix_4x4_set_lookat_target`, preserving its column-oriented
    /// `Mtxf.m[row][column]` assignments in the copied flat value order.
    private static func sourceLookAtTarget(
        eye: (Float, Float, Float),
        target: (Float, Float, Float),
        up: (Float, Float, Float)
    ) -> [Float] {
        let forward = (
            target.0 - eye.0,
            target.1 - eye.1,
            target.2 - eye.2
        )
        let length = sqrtf(
            forward.0 * forward.0 + forward.1 * forward.1 + forward.2 * forward.2
        )
        let normForward = -1.0 / length
        let fx = forward.0 * normForward
        let fy = forward.1 * normForward
        let fz = forward.2 * normForward

        var rx = up.1 * fz - up.2 * fy
        var ry = up.2 * fx - up.0 * fz
        var rz = up.0 * fy - up.1 * fx
        let rightLength = sqrtf(rx * rx + ry * ry + rz * rz)
        let normRight = 1.0 / rightLength
        rx *= normRight; ry *= normRight; rz *= normRight

        var ux = fy * rz - fz * ry
        var uy = fz * rx - fx * rz
        var uz = fx * ry - fy * rx
        let upLength = sqrtf(ux * ux + uy * uy + uz * uz)
        let normUp = 1.0 / upLength
        ux *= normUp; uy *= normUp; uz *= normUp

        return [
            rx, ux, fx, 0,
            ry, uy, fy, 0,
            rz, uz, fz, 0,
            -(eye.0 * rx + eye.1 * ry + eye.2 * rz),
            -(eye.0 * ux + eye.1 * uy + eye.2 * uz),
            -(eye.0 * fx + eye.1 * fy + eye.2 * fz),
            1,
        ]
    }

    private static func sourcePerspective(
        fovyDegrees: Float,
        aspect: Float,
        near: Float,
        far: Float
    ) -> [Float] {
        var matrix = Array(repeating: Float(0), count: 16)
        let radians = fovyDegrees * (piDegrees / 180.0)
        let cot = cosf(radians * 0.5) / sinf(radians * 0.5)
        matrix[0] = cot / aspect
        matrix[5] = cot
        matrix[10] = (near + far) / (near - far)
        matrix[11] = -1
        matrix[14] = (2 * near * far) / (near - far)
        return matrix
    }

    private static func sourceRotationY(_ angle: Float) -> [Float] {
        let cosine = cosf(angle)
        let sine = sinf(angle)
        return [
            cosine, 0, -sine, 0,
            0, 1, 0, 0,
            sine, 0, cosine, 0,
            0, 0, 0, 1,
        ]
    }

    private static func sourceIdentityAndPosition(
        _ position: (Float, Float, Float)
    ) -> [Float] {
        [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            position.0, position.1, position.2, 1,
        ]
    }

    private static func sourceMultiply(_ lhs: [Float], _ rhs: [Float]) -> [Float] {
        var result = Array(repeating: Float(0), count: 16)
        for i in 0..<4 {
            for j in 0..<4 {
                result[j * 4 + i] =
                    lhs[i] * rhs[j * 4] +
                    lhs[4 + i] * rhs[j * 4 + 1] +
                    lhs[8 + i] * rhs[j * 4 + 2] +
                    lhs[12 + i] * rhs[j * 4 + 3]
            }
        }
        return result
    }

    /// Source `matrix_scalar_multiply`: only the first twelve floats are
    /// touched when passed `matrix.m[0]`.
    private static func sourceScalarMultiply(_ scalar: Float, matrix: inout [Float]) {
        for index in 0..<12 { matrix[index] *= scalar }
    }

    /// Source `matrix_scalar_multiply_3`: columns 0..2, including their
    /// translation-row elements, are scaled; column 3 is untouched.
    private static func sourceScalarMultiply3(_ scalar: Float, matrix: inout [Float]) {
        for index in [0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14] {
            matrix[index] *= scalar
        }
    }

    private static func packSourceMatrix(_ values: [Float]) -> [Int32] {
        precondition(values.count == 16)
        return values.map {
            Int32(($0 * q16One).rounded(.towardZero))
        }
    }

    private static func simdMatrix(_ values: [Int32]) -> SIMD16<Int32> {
        precondition(values.count == 16)
        var result = SIMD16<Int32>(repeating: 0)
        for index in values.indices { result[index] = values[index] }
        return result
    }

    private static func sourceViewport(
        handle: UInt32,
        width: UInt32,
        height: UInt32
    ) throws -> GoldenEyeGBIViewportResourceV6 {
        guard width > 0, height > 0, width.isMultiple(of: 2), height.isMultiple(of: 2) else {
            throw GoldenEyeSourceFrontendMatricesV6Error.invalidInput
        }
        let halfWidth = Int32(width / 2)
        let halfHeight = Int32(height / 2)
        let values: [Int32] = [
            halfWidth << 16,
            halfHeight << 16,
            Int32(q16OneI),
            Int32(q16OneI),
            halfWidth << 16,
            halfHeight << 16,
            0,
            Int32(q16OneI),
        ]
        return try GoldenEyeGBIViewportResourceV6(handle: handle, values: values)
    }

    private static func auxiliaryHandle(screen: UInt32, role: UInt32, index: UInt32) -> UInt32 {
        auxiliaryHandlePrefix | ((screen & 0xff) << 16) | ((role & 0xff) << 8) | (index & 0xff)
    }

    private static func appendUnique(
        _ array: inout [GoldenEyeGBIMatrixResourceV6],
        _ value: GoldenEyeGBIMatrixResourceV6
    ) throws {
        guard !array.contains(where: { $0.handle == value.handle }) else {
            throw GoldenEyeSourceFrontendMatricesV6Error.duplicateHandle(value.handle)
        }
        array.append(value)
    }

    private static func hashMatrices(_ values: [GoldenEyeGBIMatrixResourceV6]) -> UInt64 {
        var hash = hashOffset
        for value in values {
            hash = hashU32(hash, value.handle)
            for item in value.values { hash = hashI32(hash, item) }
        }
        return hash
    }

    private static func hashViewports(_ values: [GoldenEyeGBIViewportResourceV6]) -> UInt64 {
        var hash = hashOffset
        for value in values {
            hash = hashU32(hash, value.handle)
            for item in value.values { hash = hashI32(hash, item) }
        }
        return hash
    }

    private static let hashOffset: UInt64 = 1_469_598_103_934_665_603
    private static let hashPrime: UInt64 = 1_099_511_628_211

    private static func hashU32(_ hash: UInt64, _ value: UInt32) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 24, by: 8) {
            result = (result ^ UInt64((value >> UInt32(shift)) & 0xff)) &* hashPrime
        }
        return result
    }

    private static func hashI32(_ hash: UInt64, _ value: Int32) -> UInt64 {
        hashU32(hash, UInt32(bitPattern: value))
    }

    private static func hashU64(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        hashU32(hashU32(hash, UInt32(truncatingIfNeeded: value)), UInt32(truncatingIfNeeded: value >> 32))
    }
}

#if !GE_SOURCE_MATRIX_STANDALONE
/// The renderer-facing provider.  It owns only the guarded copied GESM model
/// values and scalar output dimensions; it never opens a ROM or acquires a
/// drawable.  A caller may construct it from the already-validated product
/// preparation root and hand it to the source product renderer.
@available(macOS 26.0, *)
final class GoldenEyeSourceFrontendMatrixProviderV6:
    GoldenEyeSourceProductFrameResourceProviderV6, @unchecked Sendable
{
    private let models: [String: GoldenEyeSourceModelV6]
    private let viewportWidth: UInt32
    private let viewportHeight: UInt32

    init(
        preparation: GoldenEyeSourceProductPreparationV6,
        viewportWidth: UInt32 = 440,
        viewportHeight: UInt32 = 330
    ) throws {
        guard viewportWidth > 0, viewportHeight > 0 else {
            throw GoldenEyeSourceFrontendMatricesV6Error.invalidInput
        }
        self.models = preparation.models
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
    }

    init(
        models: [String: GoldenEyeSourceModelV6],
        viewportWidth: UInt32 = 440,
        viewportHeight: UInt32 = 330
    ) throws {
        guard viewportWidth > 0, viewportHeight > 0 else {
            throw GoldenEyeSourceFrontendMatricesV6Error.invalidInput
        }
        self.models = models
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
    }

    func frameResources(
        for sourceFrame: GoldenEyeSourceFrontendFrameV6
    ) throws -> GoldenEyeSourceProductFrameResourcesV6 {
        let modelName: String
        switch sourceFrame.screen {
        case GoldenEyeSourceFrontendMatricesV6.screenLegal: modelName = "legalpage"
        case GoldenEyeSourceFrontendMatricesV6.screenNintendo: modelName = "nintendologo"
        case GoldenEyeSourceFrontendMatricesV6.screenGunbarrel: modelName = "suitbond"
        case GoldenEyeSourceFrontendMatricesV6.screenGoldenEye: modelName = "goldeneyelogo"
        case GoldenEyeSourceFrontendMatricesV6.screenFileSelect,
             GoldenEyeSourceFrontendMatricesV6.screenModeSelect:
            modelName = "walletbond"
        case GoldenEyeSourceFrontendMatricesV6.screenRareware:
            modelName = "rarewarelogo"
        default:
            throw GoldenEyeSourceFrontendMatricesV6Error.unsupportedScreen(sourceFrame.screen)
        }
        guard let model = models[modelName] else {
            throw GoldenEyeSourceFrontendMatricesV6Error.dynamicDependency(
                "missing guarded GESM model \(modelName)"
            )
        }
        let primary = try GoldenEyeSourceFrontendMatricesV6.make(
            frame: sourceFrame,
            model: model,
            modelName: modelName,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight
        )
        guard sourceFrame.screen == GoldenEyeSourceFrontendMatricesV6.screenGunbarrel else {
            return primary.resources
        }
        // Gunbarrel composes three guarded GESM models. Keep the shared camera,
        // projection and viewport once, then append each model's copied
        // model-view matrix so every dynamic scene can resolve its own source
        // matrix handle without guessing an identity transform.
        var matrices = primary.resources.matrices
        func appendModelMatrixHandles(
            from model: GoldenEyeSourceModelV6,
            using base: GoldenEyeGBIMatrixResourceV6
        ) throws {
            for (index, command) in model.commands.enumerated()
                where command.semantic.hasPrefix("gsSPMatrix") {
                guard let token = model.tokens(for: index).first,
                      token.encodedValue != 0,
                      !matrices.contains(where: { $0.handle == token.encodedValue }) else {
                    continue
                }
                matrices.append(try GoldenEyeGBIMatrixResourceV6(
                    handle: token.encodedValue,
                    values: base.values,
                    roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView
                ))
            }
        }
        if let modelMatrix = primary.resources.matrices.first(where: {
            $0.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.modelView != 0
        }) {
            try appendModelMatrixHandles(from: model, using: modelMatrix)
        }
        for name in ["headbrosnansuit", "chrwppk"] {
            guard let extraModel = models[name] else {
                throw GoldenEyeSourceFrontendMatricesV6Error.dynamicDependency(
                    "missing guarded GESM model \(name)"
                )
            }
            guard let matrixCommand = extraModel.commands.first(where: {
                $0.semantic.hasPrefix("gsSPMatrix")
            }),
                  let matrixIndex = extraModel.commands.firstIndex(of: matrixCommand),
                  let matrixToken = extraModel.tokens(for: matrixIndex).first,
                  matrixToken.encodedValue != 0 else {
                throw GoldenEyeSourceFrontendMatricesV6Error.missingModelMatrixHandle(name)
            }
            let input = try GoldenEyeSourceFrontendMatrixInputV6(
                screen: sourceFrame.screen,
                nativeTick: sourceFrame.nativeTick,
                referenceTick: sourceFrame.referenceTick,
                sourceTimer: sourceFrame.sourceTimer,
                pairPhase: sourceFrame.nativeTick & 1 == 0 ? 0 : 1
            )
            let extra = try GoldenEyeSourceFrontendMatricesV6.make(
                input: input,
                modelMatrixHandle: matrixToken.encodedValue,
                viewportWidth: viewportWidth,
                viewportHeight: viewportHeight
            )
            for matrix in extra.resources.matrices
                where matrix.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.modelView != 0
                    && !matrices.contains(where: { $0.handle == matrix.handle }) {
                matrices.append(matrix)
            }
            if let modelMatrix = extra.resources.matrices.first(where: {
                $0.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.modelView != 0
            }) {
                try appendModelMatrixHandles(from: extraModel, using: modelMatrix)
            }
        }
        return try GoldenEyeSourceProductFrameResourcesV6(
            matrices: matrices,
            viewports: primary.resources.viewports,
            viewportWidth: primary.resources.viewportWidth,
            viewportHeight: primary.resources.viewportHeight
        )
    }
}
#endif
