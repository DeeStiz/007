#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation
import simd

/// Geometry-mode bits used by the classic GE/F3D source producers.  The
/// values are copied from `include/PR/gbi.h`; keeping them here makes this
/// sidecar usable by the standalone ABI fixtures without importing a source
/// display-list pointer or a host renderer object.
enum GoldenEyeSourceSceneGeometryModeV6 {
    static let zBuffer: UInt32 = 0x0000_0001
    static let shade: UInt32 = 0x0000_0004
    static let textureEnable: UInt32 = 0x0000_0002
    static let fog: UInt32 = 0x0001_0000
    static let lighting: UInt32 = 0x0002_0000
    static let textureGen: UInt32 = 0x0004_0000
    static let textureGenLinear: UInt32 = 0x0008_0000
    static let shadingSmooth: UInt32 = 0x0000_0200
    static let cullFront: UInt32 = 0x0000_1000
    static let cullBack: UInt32 = 0x0000_2000

    static let supportedMask: UInt32 =
        zBuffer | shade | textureEnable | fog | lighting |
        textureGen | textureGenLinear | shadingSmooth | cullFront | cullBack
}

/// Bits consumed by the V6 Metal vertex/fragment pair.  The raw geometry
/// mode remains alongside these normalized bits so a future source-state
/// consumer can audit the exact GBI value rather than inferring it from a
/// host-side lighting enum.
enum GoldenEyeSourceSceneLightingFlagsV6 {
    static let lighting: UInt32 = 1 << 0
    static let textureGeneration: UInt32 = 1 << 1
    static let textureGenerationLinear: UInt32 = 1 << 2
    static let reflectionBasis: UInt32 = 1 << 3
    static let supportedMask: UInt32 =
        lighting | textureGeneration | textureGenerationLinear | reflectionBasis
}

enum GoldenEyeSourceSceneLightingV6Error: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case invalidGeometryMode(UInt32)
    case linearTexgenWithoutTexgen(UInt32)
    case unsupportedLinearTexgen(UInt32)
    case missingBinding(UInt32)
    case bindingContextMismatch(UInt32)
    case unsupportedScreen(UInt32)
    case invalidPairPhase(UInt32)
    case invalidVector(String)
    case invalidNormalTransform

    var description: String {
        switch self {
        case .invalidGeometryMode(let mode):
            return "unsupported source geometry mode 0x\(String(mode, radix: 16))"
        case .linearTexgenWithoutTexgen(let mode):
            return "G_TEXTURE_GEN_LINEAR is set without G_TEXTURE_GEN (0x\(String(mode, radix: 16)))"
        case .unsupportedLinearTexgen(let mode):
            return "G_TEXTURE_GEN_LINEAR lowering is not yet source-complete (0x\(String(mode, radix: 16)))"
        case .missingBinding(let handle):
            return "missing source lighting binding for render state \(handle)"
        case .bindingContextMismatch(let handle):
            return "source lighting binding is stale for render state \(handle)"
        case .unsupportedScreen(let screen):
            return "source lighting provider has no screen record \(screen)"
        case .invalidPairPhase(let phase):
            return "invalid source lighting pair phase \(phase)"
        case .invalidVector(let name):
            return "invalid source lighting vector \(name)"
        case .invalidNormalTransform:
            return "invalid source normal transform"
        }
    }
}

/// A fixed-width, value-only source lighting/texgen binding.  This is copied
/// into the per-draw GPU record; no pointer, segmented address, model object,
/// or Metal object crosses the source-scene boundary.
struct GoldenEyeSourceSceneLightingBindingV6: Sendable, Equatable {
    let stateHandle: UInt32
    let rawGeometryMode: UInt32
    let flags: UInt32
    let sourceTimer: UInt32
    let pairPhase: UInt32
    let ambientColor: SIMD4<Float>
    let directionalColor: SIMD4<Float>
    let directionalDirection: SIMD4<Float>
    let reflectionRight: SIMD4<Float>
    let reflectionUp: SIMD4<Float>
    let normalTransform: simd_float4x4
    let evidenceHash: UInt64

    init(
        stateHandle: UInt32,
        rawGeometryMode: UInt32,
        sourceTimer: UInt32,
        pairPhase: UInt32,
        ambientColor: SIMD4<Float>,
        directionalColor: SIMD4<Float>,
        directionalDirection: SIMD4<Float>,
        reflectionRight: SIMD4<Float>,
        reflectionUp: SIMD4<Float>,
        normalTransform: simd_float4x4
    ) throws {
        guard stateHandle != 0 else {
            throw GoldenEyeSourceSceneLightingV6Error.missingBinding(stateHandle)
        }
        guard pairPhase <= 1 else {
            throw GoldenEyeSourceSceneLightingV6Error.invalidPairPhase(pairPhase)
        }
        guard rawGeometryMode & ~GoldenEyeSourceSceneGeometryModeV6.supportedMask == 0 else {
            throw GoldenEyeSourceSceneLightingV6Error.invalidGeometryMode(rawGeometryMode)
        }
        guard rawGeometryMode & GoldenEyeSourceSceneGeometryModeV6.textureGenLinear == 0 ||
            rawGeometryMode & GoldenEyeSourceSceneGeometryModeV6.textureGen != 0 else {
            throw GoldenEyeSourceSceneLightingV6Error.linearTexgenWithoutTexgen(rawGeometryMode)
        }
        guard rawGeometryMode & GoldenEyeSourceSceneGeometryModeV6.textureGenLinear == 0 else {
            throw GoldenEyeSourceSceneLightingV6Error.unsupportedLinearTexgen(rawGeometryMode)
        }
        guard Self.isFinite(ambientColor), Self.isFinite(directionalColor),
              Self.isFinite(directionalDirection), Self.isFinite(reflectionRight),
              Self.isFinite(reflectionUp) else {
            throw GoldenEyeSourceSceneLightingV6Error.invalidVector("color or direction")
        }
        guard Self.isFinite(normalTransform) else {
            throw GoldenEyeSourceSceneLightingV6Error.invalidNormalTransform
        }

        self.stateHandle = stateHandle
        self.rawGeometryMode = rawGeometryMode
        var normalizedFlags: UInt32 = 0
        if rawGeometryMode & GoldenEyeSourceSceneGeometryModeV6.lighting != 0 {
            normalizedFlags |= GoldenEyeSourceSceneLightingFlagsV6.lighting
        }
        if rawGeometryMode & GoldenEyeSourceSceneGeometryModeV6.textureGen != 0 {
            normalizedFlags |= GoldenEyeSourceSceneLightingFlagsV6.textureGeneration
            normalizedFlags |= GoldenEyeSourceSceneLightingFlagsV6.reflectionBasis
        }
        if rawGeometryMode & GoldenEyeSourceSceneGeometryModeV6.textureGenLinear != 0 {
            normalizedFlags |= GoldenEyeSourceSceneLightingFlagsV6.textureGenerationLinear
        }
        self.flags = normalizedFlags
        self.sourceTimer = sourceTimer
        self.pairPhase = pairPhase
        self.ambientColor = ambientColor
        self.directionalColor = directionalColor
        self.directionalDirection = directionalDirection
        self.reflectionRight = reflectionRight
        self.reflectionUp = reflectionUp
        self.normalTransform = normalTransform
        self.evidenceHash = Self.hash(
            stateHandle: stateHandle,
            rawGeometryMode: rawGeometryMode,
            flags: normalizedFlags,
            sourceTimer: sourceTimer,
            pairPhase: pairPhase,
            ambientColor: ambientColor,
            directionalColor: directionalColor,
            directionalDirection: directionalDirection,
            reflectionRight: reflectionRight,
            reflectionUp: reflectionUp,
            normalTransform: normalTransform
        )
    }

    var usesLighting: Bool {
        flags & GoldenEyeSourceSceneLightingFlagsV6.lighting != 0
    }

    var usesTextureGeneration: Bool {
        flags & GoldenEyeSourceSceneLightingFlagsV6.textureGeneration != 0
    }

    var usesLinearTextureGeneration: Bool {
        flags & GoldenEyeSourceSceneLightingFlagsV6.textureGenerationLinear != 0
    }

    private static func isFinite(_ value: SIMD4<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite && value.w.isFinite
    }

    private static func isFinite(_ value: simd_float4x4) -> Bool {
        value.columns.0.x.isFinite && value.columns.0.y.isFinite &&
            value.columns.0.z.isFinite && value.columns.0.w.isFinite &&
            value.columns.1.x.isFinite && value.columns.1.y.isFinite &&
            value.columns.1.z.isFinite && value.columns.1.w.isFinite &&
            value.columns.2.x.isFinite && value.columns.2.y.isFinite &&
            value.columns.2.z.isFinite && value.columns.2.w.isFinite &&
            value.columns.3.x.isFinite && value.columns.3.y.isFinite &&
            value.columns.3.z.isFinite && value.columns.3.w.isFinite
    }

    private static func hash(
        stateHandle: UInt32,
        rawGeometryMode: UInt32,
        flags: UInt32,
        sourceTimer: UInt32,
        pairPhase: UInt32,
        ambientColor: SIMD4<Float>,
        directionalColor: SIMD4<Float>,
        directionalDirection: SIMD4<Float>,
        reflectionRight: SIMD4<Float>,
        reflectionUp: SIMD4<Float>,
        normalTransform: simd_float4x4
    ) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for word in [stateHandle, rawGeometryMode, flags, sourceTimer, pairPhase] {
            hash = hashU32(hash, word)
        }
        for vector in [ambientColor, directionalColor, directionalDirection,
                       reflectionRight, reflectionUp] {
            for scalar in [vector.x, vector.y, vector.z, vector.w] {
                hash = hashU32(hash, scalar.bitPattern)
            }
        }
        for column in [normalTransform.columns.0, normalTransform.columns.1,
                       normalTransform.columns.2, normalTransform.columns.3] {
            for scalar in [column.x, column.y, column.z, column.w] {
                hash = hashU32(hash, scalar.bitPattern)
            }
        }
        return hash == 0 ? 1 : hash
    }

    private static func hashU32(_ hash: UInt64, _ value: UInt32) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 24, by: 8) {
            result = (result ^ UInt64((value >> UInt32(shift)) & 0xff)) &*
                1_099_511_628_211
        }
        return result
    }
}

/// The value-only context supplied by a scene consumer.  `rawGeometryMode`
/// is optional because older snapshots did not yet carry the sidecar; a
/// strict provider can require an explicit per-state record instead.
struct GoldenEyeSourceSceneLightingContextV6: Sendable, Equatable {
    let screen: UInt32
    let stateHandle: UInt32
    let nativeTick: UInt64
    let sourceTimer: UInt32
    let pairPhase: UInt32
    let modelView: simd_float4x4
    let rawGeometryMode: UInt32?

    init(
        screen: UInt32,
        stateHandle: UInt32,
        nativeTick: UInt64,
        sourceTimer: UInt32,
        pairPhase: UInt32,
        modelView: simd_float4x4,
        rawGeometryMode: UInt32? = nil
    ) throws {
        guard nativeTick > 0 else {
            throw GoldenEyeSourceSceneLightingV6Error.invalidPairPhase(pairPhase)
        }
        guard pairPhase <= 1 else {
            throw GoldenEyeSourceSceneLightingV6Error.invalidPairPhase(pairPhase)
        }
        self.screen = screen
        self.stateHandle = stateHandle
        self.nativeTick = nativeTick
        self.sourceTimer = sourceTimer
        self.pairPhase = pairPhase
        self.modelView = modelView
        self.rawGeometryMode = rawGeometryMode
    }
}

/// Provider for source title light/texgen records. It has deterministic
/// source light records for the currently closed paths and a strict record
/// mode for model/state consumers. Raw geometry mode is never defaulted: it
/// must be supplied by the decoded per-state GBI sidecar. Screen-specific
/// light values live here, never in the shader.
struct GoldenEyeSourceSceneLightingProviderV6: Sendable {
    static let screenLegal: UInt32 = 0
    static let screenNintendo: UInt32 = 1
    static let screenRareware: UInt32 = 2
    static let screenGunbarrel: UInt32 = 3
    static let screenGoldenEye: UInt32 = 4

    private let records: [UInt32: GoldenEyeSourceSceneLightingBindingV6]
    private let useTitleDefaults: Bool

    init(titleDefaults: Bool = true) {
        self.records = [:]
        self.useTitleDefaults = titleDefaults
    }

    init(strict records: [UInt32: GoldenEyeSourceSceneLightingBindingV6]) {
        self.records = records
        self.useTitleDefaults = false
    }

    func binding(for context: GoldenEyeSourceSceneLightingContextV6) throws -> GoldenEyeSourceSceneLightingBindingV6 {
        if let record = records[context.stateHandle] {
            guard let raw = context.rawGeometryMode else {
                throw GoldenEyeSourceSceneLightingV6Error.missingBinding(
                    context.stateHandle
                )
            }
            if raw != record.rawGeometryMode {
                throw GoldenEyeSourceSceneLightingV6Error.invalidGeometryMode(raw)
            }
            guard record.sourceTimer == context.sourceTimer,
                  record.pairPhase == context.pairPhase else {
                throw GoldenEyeSourceSceneLightingV6Error.bindingContextMismatch(
                    context.stateHandle
                )
            }
            return record
        }
        guard useTitleDefaults else {
            throw GoldenEyeSourceSceneLightingV6Error.missingBinding(context.stateHandle)
        }
        guard let rawGeometryMode = context.rawGeometryMode else {
            throw GoldenEyeSourceSceneLightingV6Error.missingBinding(context.stateHandle)
        }
        return try makeBinding(
            context: context,
            rawGeometryMode: rawGeometryMode,
            screen: context.screen
        )
    }

    private func makeBinding(
        context: GoldenEyeSourceSceneLightingContextV6,
        rawGeometryMode: UInt32,
        screen: UInt32
    ) throws -> GoldenEyeSourceSceneLightingBindingV6 {
        let lighting = rawGeometryMode & GoldenEyeSourceSceneGeometryModeV6.lighting != 0
        let texgen = rawGeometryMode & GoldenEyeSourceSceneGeometryModeV6.textureGen != 0
        if !lighting && !texgen {
            return try GoldenEyeSourceSceneLightingBindingV6(
                stateHandle: context.stateHandle,
                rawGeometryMode: rawGeometryMode,
                sourceTimer: context.sourceTimer,
                pairPhase: context.pairPhase,
                ambientColor: SIMD4(repeating: 1),
                directionalColor: SIMD4(0, 0, 0, 1),
                directionalDirection: SIMD4(0, 0, 1, 0),
                reflectionRight: SIMD4(1, 0, 0, 0),
                reflectionUp: SIMD4(0, 1, 0, 0),
                normalTransform: Self.normalTransform(from: context.modelView)
            )
        }
        guard screen == Self.screenNintendo || screen == Self.screenGoldenEye ||
            screen == Self.screenRareware else {
            throw GoldenEyeSourceSceneLightingV6Error.unsupportedScreen(screen)
        }
        let ambient: SIMD4<Float>
        let directional: SIMD4<Float>
        let direction: SIMD4<Float>
        if screen == Self.screenNintendo {
            let ambientQ16 = Self.nintendoAmbientQ16(
                sourceTimer: context.sourceTimer,
                pairPhase: context.pairPhase
            )
            let value = Float(ambientQ16) / Float(255 * 65_536)
            // Source `ninlogolight` has a white ambient and black directional
            // light; its changing ambient is the Nintendo logo fade.
            ambient = SIMD4(value, value, value, 1)
            directional = SIMD4(0, 0, 0, 1)
            direction = SIMD4(0, 0, 1, 0)
        } else if screen == Self.screenRareware {
            // title.c's Rareware path reuses gunbarrelLights.  The source
            // writes the fade alpha into both the ambient and directional
            // light colors before the three display-list passes, while the
            // light direction remains (0, 0x7f, 0).  Keep the paired midpoint
            // in Q16 so odd native renders are visibly between source
            // anchors without changing the source comparator boundary.
            let fadeQ16 = Self.rarewareFadeQ16(
                sourceTimer: context.sourceTimer,
                pairPhase: context.pairPhase
            )
            let value = Float(fadeQ16) / Float(255 * 65_536)
            ambient = SIMD4(value, value, value, 1)
            directional = SIMD4(value, value, value, 1)
            direction = SIMD4(0, 1, 0, 0)
        } else {
            ambient = SIMD4(repeating: 150.0 / 255.0)
            directional = SIMD4(1, 1, 1, 1)
            // `src/game/front.c:317-323` / `src/game/bg.c:254-260`.
            direction = Self.normalizedDirection(77, 77, 46)
        }
        // `guLookAtReflect` at `front.c:1951-1959` with eye (0,0,4000),
        // target (0,0,0), up (0,1,0) produces the canonical +X/+Y basis.
        return try GoldenEyeSourceSceneLightingBindingV6(
            stateHandle: context.stateHandle,
            rawGeometryMode: rawGeometryMode,
            sourceTimer: context.sourceTimer,
            pairPhase: context.pairPhase,
            ambientColor: ambient,
            directionalColor: directional,
            directionalDirection: direction,
            reflectionRight: SIMD4(1, 0, 0, 0),
            reflectionUp: SIMD4(0, 1, 0, 0),
            normalTransform: Self.normalTransform(from: context.modelView)
        )
    }

    static func nintendoAmbientQ16(sourceTimer: UInt32, pairPhase: UInt32) -> Int64 {
        // US source expression at `src/game/front.c:1681-1692`:
        // 0xFF - ((g_MenuTimer * 0xFF - 94350) / 100), clamped to 0...255.
        // Evaluate in Q16 so the odd native half-step is strictly between
        // source anchors while even ticks remain exactly source-valued.
        let current = nintendoAmbientInteger(sourceTimer)
        guard pairPhase != 1 else {
            // The native odd step is the deterministic midpoint between the
            // two adjacent source anchors. This preserves exact C truncation
            // at even anchors while retaining a visible half-step during the
            // fade instead of truncating the Q16 calculation back to an
            // integer source frame.
            let next = nintendoAmbientInteger(sourceTimer == UInt32.max
                ? sourceTimer : sourceTimer &+ 1)
            return (current + next) * 32_768
        }
        return current * 65_536
    }

    static func rarewareFadeQ16(sourceTimer: UInt32, pairPhase: UInt32) -> Int64 {
        let current = rarewareFadeInteger(sourceTimer)
        guard pairPhase == 1, sourceTimer != UInt32.max else {
            return current * 65_536
        }
        let next = rarewareFadeInteger(sourceTimer &+ 1)
        return (current + next) * 32_768
    }

    private static func rarewareFadeInteger(_ sourceTimer: UInt32) -> Int64 {
        let counter = Int64(sourceTimer)
        let fadeIn = min(max((counter * 255) / 70, 0), 255)
        let fadeOut = min(max(255 - ((counter * 255 - 40_800) / 70), 0), 255)
        return (fadeIn * fadeOut) / 255
    }

    private static func nintendoAmbientInteger(_ sourceTimer: UInt32) -> Int64 {
        let numerator = Int64(sourceTimer) * 255 - 94_350
        let quotient = numerator >= 0 ? numerator / 100 : -((-numerator) / 100)
        let value = 255 - quotient
        return min(max(value, 0), 255)
    }

    private static func normalizedDirection(_ x: Float, _ y: Float, _ z: Float) -> SIMD4<Float> {
        let value = simd_normalize(SIMD3(x, y, z))
        return SIMD4(value.x, value.y, value.z, 0)
    }

    private static func normalTransform(from modelView: simd_float4x4) -> simd_float4x4 {
        let inverseTranspose = simd_transpose(simd_inverse(modelView))
        return simd_float4x4(columns: (
            SIMD4(inverseTranspose.columns.0.x, inverseTranspose.columns.0.y, inverseTranspose.columns.0.z, 0),
            SIMD4(inverseTranspose.columns.1.x, inverseTranspose.columns.1.y, inverseTranspose.columns.1.z, 0),
            SIMD4(inverseTranspose.columns.2.x, inverseTranspose.columns.2.y, inverseTranspose.columns.2.z, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }
}

/// Source-line fixtures keep provenance close to the normalized provider
/// values.  They are intentionally data-only and are used by the strict
/// smoke to ensure the US source constants do not drift.
enum GoldenEyeSourceSceneLightingSourceFixtureV6 {
    static let nintendoAmbientLine = 1681
    static let nintendoClampLine = 1688
    static let goldenEyeLightLine = 317
    static let goldenEyeLookAtLine = 1951
}
