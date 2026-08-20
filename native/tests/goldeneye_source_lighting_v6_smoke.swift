import Foundation
import simd

private func identity() -> simd_float4x4 {
    matrix_identity_float4x4
}

@main
struct GoldenEyeSourceLightingV6Smoke {
    static func main() throws {
        let provider = GoldenEyeSourceSceneLightingProviderV6()
        let legalGeometry = GoldenEyeSourceSceneGeometryModeV6.shade |
            GoldenEyeSourceSceneGeometryModeV6.cullBack
        let titleGeometry = legalGeometry |
            GoldenEyeSourceSceneGeometryModeV6.lighting |
            GoldenEyeSourceSceneGeometryModeV6.textureGen |
            GoldenEyeSourceSceneGeometryModeV6.shadingSmooth
        let legal = try provider.binding(for: GoldenEyeSourceSceneLightingContextV6(
            screen: GoldenEyeSourceSceneLightingProviderV6.screenLegal,
            stateHandle: 11,
            nativeTick: 2,
            sourceTimer: 0,
            pairPhase: 0,
            modelView: identity(),
            rawGeometryMode: legalGeometry
        ))
        precondition(!legal.usesLighting)
        precondition(!legal.usesTextureGeneration)
        precondition(legal.rawGeometryMode ==
            GoldenEyeSourceSceneGeometryModeV6.shade |
            GoldenEyeSourceSceneGeometryModeV6.cullBack)

        let nintendoEven = try provider.binding(for: GoldenEyeSourceSceneLightingContextV6(
            screen: GoldenEyeSourceSceneLightingProviderV6.screenNintendo,
            stateHandle: 12,
            nativeTick: 800,
            sourceTimer: 400,
            pairPhase: 0,
            modelView: identity(),
            rawGeometryMode: titleGeometry
        ))
        let nintendoOdd = try provider.binding(for: GoldenEyeSourceSceneLightingContextV6(
            screen: GoldenEyeSourceSceneLightingProviderV6.screenNintendo,
            stateHandle: 12,
            nativeTick: 801,
            sourceTimer: 400,
            pairPhase: 1,
            modelView: identity(),
            rawGeometryMode: titleGeometry
        ))
        precondition(nintendoEven.usesLighting)
        precondition(nintendoEven.usesTextureGeneration)
        precondition(nintendoEven.evidenceHash != nintendoOdd.evidenceHash)
        precondition(nintendoEven.ambientColor.x > nintendoOdd.ambientColor.x)
        precondition(nintendoEven.pairPhase == 0 && nintendoOdd.pairPhase == 1)
        precondition(GoldenEyeSourceSceneLightingProviderV6.nintendoAmbientQ16(
            sourceTimer: 400, pairPhase: 0
        ) == 179 * 65_536)
        precondition(GoldenEyeSourceSceneLightingProviderV6.nintendoAmbientQ16(
            sourceTimer: 400, pairPhase: 1
        ) == (179 + 176) * 32_768)

        let goldenEye = try provider.binding(for: GoldenEyeSourceSceneLightingContextV6(
            screen: GoldenEyeSourceSceneLightingProviderV6.screenGoldenEye,
            stateHandle: 13,
            nativeTick: 2,
            sourceTimer: 1,
            pairPhase: 0,
            modelView: identity(),
            rawGeometryMode: titleGeometry
        ))
        precondition(goldenEye.ambientColor ==
            SIMD4(repeating: 150.0 / 255.0))
        let sourceDirection = simd_normalize(SIMD3<Float>(77, 77, 46))
        precondition(abs(goldenEye.directionalDirection.x - sourceDirection.x) < 0.000_001)
        precondition(abs(goldenEye.directionalDirection.y - sourceDirection.y) < 0.000_001)
        precondition(abs(goldenEye.directionalDirection.z - sourceDirection.z) < 0.000_001)
        precondition(goldenEye.reflectionRight == SIMD4(1, 0, 0, 0))
        precondition(goldenEye.reflectionUp == SIMD4(0, 1, 0, 0))

        do {
            _ = try provider.binding(for: GoldenEyeSourceSceneLightingContextV6(
                screen: GoldenEyeSourceSceneLightingProviderV6.screenNintendo,
                stateHandle: 15,
                nativeTick: 2,
                sourceTimer: 1,
                pairPhase: 0,
                modelView: identity()
            ))
            preconditionFailure("lighting provider guessed missing raw geometry mode")
        } catch GoldenEyeSourceSceneLightingV6Error.missingBinding(15) {
            // Expected fail-closed behavior.
        }

        let rarewareEven = try provider.binding(for: GoldenEyeSourceSceneLightingContextV6(
            screen: GoldenEyeSourceSceneLightingProviderV6.screenRareware,
            stateHandle: 16,
            nativeTick: 40,
            sourceTimer: 20,
            pairPhase: 0,
            modelView: identity(),
            rawGeometryMode: titleGeometry
        ))
        let rarewareOdd = try provider.binding(for: GoldenEyeSourceSceneLightingContextV6(
            screen: GoldenEyeSourceSceneLightingProviderV6.screenRareware,
            stateHandle: 16,
            nativeTick: 41,
            sourceTimer: 20,
            pairPhase: 1,
            modelView: identity(),
            rawGeometryMode: titleGeometry
        ))
        precondition(rarewareEven.usesLighting)
        precondition(rarewareEven.usesTextureGeneration)
        precondition(rarewareEven.directionalDirection == SIMD4(0, 1, 0, 0))
        precondition(rarewareEven.ambientColor.x > 0)
        precondition(rarewareOdd.ambientColor.x > rarewareEven.ambientColor.x)
        precondition(GoldenEyeSourceSceneLightingProviderV6.rarewareFadeQ16(
            sourceTimer: 20, pairPhase: 0
        ) == 72 * 65_536)

        let strictRecord = try GoldenEyeSourceSceneLightingBindingV6(
            stateHandle: 99,
            rawGeometryMode: GoldenEyeSourceSceneGeometryModeV6.shade |
                GoldenEyeSourceSceneGeometryModeV6.lighting,
            sourceTimer: 8,
            pairPhase: 0,
            ambientColor: SIMD4(repeating: 0.5),
            directionalColor: SIMD4(repeating: 0.25),
            directionalDirection: SIMD4(0, 0, 1, 0),
            reflectionRight: SIMD4(1, 0, 0, 0),
            reflectionUp: SIMD4(0, 1, 0, 0),
            normalTransform: identity()
        )
        let strict = GoldenEyeSourceSceneLightingProviderV6(strict: [99: strictRecord])
        let strictResult = try strict.binding(for: GoldenEyeSourceSceneLightingContextV6(
            screen: GoldenEyeSourceSceneLightingProviderV6.screenGoldenEye,
            stateHandle: 99,
            nativeTick: 2,
            sourceTimer: 8,
            pairPhase: 0,
            modelView: identity(),
            rawGeometryMode: strictRecord.rawGeometryMode
        ))
        precondition(strictResult == strictRecord)

        do {
            _ = try strict.binding(for: GoldenEyeSourceSceneLightingContextV6(
                screen: GoldenEyeSourceSceneLightingProviderV6.screenGoldenEye,
                stateHandle: 100,
                nativeTick: 2,
                sourceTimer: 8,
                pairPhase: 0,
                modelView: identity()
            ))
            preconditionFailure("strict provider accepted a missing binding")
        } catch GoldenEyeSourceSceneLightingV6Error.missingBinding(100) {
            // Expected fail-closed behavior.
        }

        do {
            _ = try GoldenEyeSourceSceneLightingBindingV6(
                stateHandle: 101,
                rawGeometryMode: GoldenEyeSourceSceneGeometryModeV6.textureGenLinear,
                sourceTimer: 0,
                pairPhase: 0,
                ambientColor: SIMD4(repeating: 1),
                directionalColor: SIMD4(repeating: 0),
                directionalDirection: SIMD4(0, 0, 1, 0),
                reflectionRight: SIMD4(1, 0, 0, 0),
                reflectionUp: SIMD4(0, 1, 0, 0),
                normalTransform: identity()
            )
            preconditionFailure("linear texgen without G_TEXTURE_GEN accepted")
        } catch GoldenEyeSourceSceneLightingV6Error.linearTexgenWithoutTexgen {
            // Expected fail-closed behavior.
        }

        do {
            _ = try GoldenEyeSourceSceneLightingBindingV6(
                stateHandle: 102,
                rawGeometryMode: GoldenEyeSourceSceneGeometryModeV6.textureGen |
                    GoldenEyeSourceSceneGeometryModeV6.textureGenLinear,
                sourceTimer: 0,
                pairPhase: 0,
                ambientColor: SIMD4(repeating: 1),
                directionalColor: SIMD4(repeating: 0),
                directionalDirection: SIMD4(0, 0, 1, 0),
                reflectionRight: SIMD4(1, 0, 0, 0),
                reflectionUp: SIMD4(0, 1, 0, 0),
                normalTransform: identity()
            )
            preconditionFailure("linear texgen was silently aliased to reflection texgen")
        } catch GoldenEyeSourceSceneLightingV6Error.unsupportedLinearTexgen {
            // Expected typed gap until exact linear angular mapping exists.
        }

        precondition(GoldenEyeSourceSceneLightingSourceFixtureV6.nintendoAmbientLine == 1681)
        precondition(GoldenEyeSourceSceneLightingSourceFixtureV6.goldenEyeLightLine == 317)
        print("goldeneye_source_lighting_v6_smoke: PASS")
    }
}
