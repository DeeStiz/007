import Foundation
import simd
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// A source-owned Cast scene request. The request deliberately names the
/// exact source roster row, authored animation row, and selected weapon; the
/// product renderer resolves those values against prepared body/head/weapon
/// GESM packets and never substitutes a diagnostic character.
struct GoldenEyeCastSourceSceneRequestV6: Sendable, Equatable {
    let identity: GoldenEyeCastIdentityV6
    let animation: GoldenEyeCastAnimationV6
    let weapon: GoldenEyeCastWeaponV6?
    let nativeTick: UInt64
    let sourceTimer: UInt32
    let sourceFrameQ16: Int32
    let fadeQ16: Int32
    /// Copied source RNG/camera values.  The authority supplies these when it
    /// has advanced the Cast random stream; defaults retain the old Bond
    /// capture fixture while keeping the renderer independent of RNG state.
    let randomWord: UInt32
    let cameraDistanceQ16: Int32
    let cameraAngleQ16: Int32
    let cameraHeightQ16: Int32
    let rootOffsetQ16: SIMD3<Int32>
    let targetOffsetQ16: SIMD3<Int32>
    let flip: Bool
    let fullActorIntro: Bool

    init(
        identity: GoldenEyeCastIdentityV6,
        animation: GoldenEyeCastAnimationV6,
        weapon: GoldenEyeCastWeaponV6?,
        nativeTick: UInt64,
        sourceTimer: UInt32,
        sourceFrameQ16: Int32,
        fadeQ16: Int32,
        randomWord: UInt32 = 0,
        cameraDistanceQ16: Int32 = 7_208_960,
        cameraAngleQ16: Int32 = 0,
        cameraHeightQ16: Int32 = 0,
        rootOffsetQ16: SIMD3<Int32> = SIMD3(repeating: 0),
        targetOffsetQ16: SIMD3<Int32> = SIMD3(repeating: 0),
        flip: Bool = false,
        fullActorIntro: Bool = false
    ) throws {
        guard nativeTick > 0, sourceTimer < 181,
              fadeQ16 >= 0, fadeQ16 <= 65_536,
              cameraDistanceQ16 >= 4_587_520,
              cameraDistanceQ16 <= 9_830_400,
              cameraHeightQ16 >= -6_553_600,
              cameraHeightQ16 <= 6_553_600 else {
            throw GoldenEyeCastSceneV6Error.authorityMismatch(
                "invalid source Cast request"
            )
        }
        self.identity = identity
        self.animation = animation
        self.weapon = weapon
        self.nativeTick = nativeTick
        self.sourceTimer = sourceTimer
        self.sourceFrameQ16 = sourceFrameQ16
        self.fadeQ16 = fadeQ16
        self.randomWord = randomWord
        self.cameraDistanceQ16 = cameraDistanceQ16
        self.cameraAngleQ16 = cameraAngleQ16
        self.cameraHeightQ16 = cameraHeightQ16
        self.rootOffsetQ16 = rootOffsetQ16
        self.targetOffsetQ16 = targetOffsetQ16
        self.flip = flip
        self.fullActorIntro = fullActorIntro
    }
}

/// Product handoff for a Cast scene that has real prepared geometry. The
/// owner calls this only from an explicit Cast capture/probe until the full
/// source roster preparation is available; no black or procedural fallback is
/// hidden behind this protocol.
@available(macOS 26.0, *)
protocol GoldenEyeCastSourceSceneFrameRendererV6: AnyObject {
    func submit(castSceneRequest: GoldenEyeCastSourceSceneRequestV6) throws
}
