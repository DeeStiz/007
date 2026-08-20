import Foundation

@main
struct GoldenEyeRamRomNonModelVisualsV6Smoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("usage: goldeneye_ramrom_non_model_visuals_v6_smoke /absolute/visible-dependency-root")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let catalog = try GoldenEyeRamRomNonModelDependencyCatalogV6.load(rootURL: root)
        precondition(catalog.isComplete)
        precondition(catalog.dependencies.count == 178)
        precondition(catalog.payloadCount > 150)
        precondition(catalog.semanticCount == 5)
        precondition(catalog.coveredDemoIDs == Set(UInt8(1)...UInt8(14)))
        precondition(catalog.coveredStages == Set(["Dam", "Facility", "Runway", "Bunker I", "Silo", "Frigate", "Train"]))
        precondition(GoldenEyeRamRomNonModelDependencyCatalogV6.expectedStageID(for: 1) == 33)
        precondition(GoldenEyeRamRomNonModelDependencyCatalogV6.expectedStageID(for: 14) == 25)
        precondition(catalog.dependencies(category: .sky).count == 9)
        precondition(catalog.dependencies(category: .fades).count == 1)
        precondition(catalog.dependencies(category: .hud).count == 81)
        precondition(catalog.dependencies(category: .watch).count == 8)
        precondition(catalog.dependencies(category: .particles).count == 42)
        precondition(catalog.dependencies(category: .effects).count == 1)
        precondition(catalog.dependencies(category: .glass).count == 8)
        precondition(catalog.dependencies(category: .explosions).count == 14)
        precondition(catalog.dependencies(category: .projectiles).count == 14)
        precondition(catalog.dependency(category: .sky, symbol: "background_Dam")?.hasPreparedPayload == true)
        precondition(catalog.dependency(category: .fades, symbol: "screen_fade_to_black/from_black")?.semantic == true)

        let tick: UInt64 = 2
        let events = [
            GoldenEyeRamRomTransientVisualEventV6(
                category: .particles, sourceSymbol: "particle_effect_dispatch",
                resourceSymbol: "IMAGE_2084_SMOKE_0", sourceReferenceTick: tick >> 1,
                sequence: 1, positionQ16: .init(x: 1, y: 2, z: 3), scaleQ16: 65_536,
                rotationQ16: 0, frameIndex: 0, colourRGBA8: 0xffff_ffff,
                alphaQ16: 65_536),
            GoldenEyeRamRomTransientVisualEventV6(
                category: .effects, sourceSymbol: "gunfire_effect_dispatch",
                resourceSymbol: "IMAGE_2085_FIRE_0", sourceReferenceTick: tick >> 1,
                sequence: 2, positionQ16: .init(x: 4, y: 5, z: 6), scaleQ16: 65_536,
                rotationQ16: 0, frameIndex: 1, colourRGBA8: 0xffff_ffff,
                alphaQ16: 65_536),
            GoldenEyeRamRomTransientVisualEventV6(
                category: .glass, sourceSymbol: "prop_104_window",
                resourceSymbol: "IMAGE_155_RAILING_GLASS", sourceReferenceTick: tick >> 1,
                sequence: 3, positionQ16: .init(x: 7, y: 8, z: 9), scaleQ16: 65_536,
                rotationQ16: 0, frameIndex: 0, colourRGBA8: 0xffff_ffff,
                alphaQ16: 65_536),
            GoldenEyeRamRomTransientVisualEventV6(
                category: .explosions, sourceSymbol: "explosion_render_dispatch",
                resourceSymbol: "IMAGE_206_IMPACTLOTS", sourceReferenceTick: tick >> 1,
                sequence: 4, positionQ16: .init(x: 10, y: 11, z: 12), scaleQ16: 65_536,
                rotationQ16: 0, frameIndex: 0, colourRGBA8: 0xffff_ffff,
                alphaQ16: 65_536),
            GoldenEyeRamRomTransientVisualEventV6(
                category: .projectiles, sourceSymbol: "gun_5_bombcase",
                resourceSymbol: "gun_5_bombcase", sourceReferenceTick: tick >> 1,
                sequence: 5, positionQ16: .init(x: 13, y: 14, z: 15), scaleQ16: 65_536,
                rotationQ16: 0, frameIndex: 0, colourRGBA8: 0xffff_ffff,
                alphaQ16: 65_536),
        ]
        let frame = GoldenEyeRamRomNonModelSourceFrameV6(
            stageID: 33, demoID: 1, nativeTick: tick,
            sky: .init(
                stageID: 33, demoID: 1, backgroundSymbol: "background_Dam",
                cloudSymbol: "IMAGE_2228_CLOUDS_GRAYSCALE", cloudOffsetQ16: 12,
                environmentRGBA8: 0x203040ff, cloudRGBA8: 0x8090a0ff,
                waterRGBA8: 0x102030ff),
            fade: .init(stageID: 33, demoID: 1, elapsedQ16: 0,
                       durationQ16: 65_536, colourRGBA8: 0x000000ff, fractionQ16: 0),
            hud: .init(visible: true, weaponTableIndex: 1, ammoType: 1,
                       ammoInMagazine: 7, ammoReserve: 35, crosshairXQ16: 220,
                       crosshairYQ16: 165,
                       imageSymbols: ["IMAGE_2236_CROSSHAIR1", "IMAGE_2231_9MMAMMO"],
                       imagePlacements: [
                           .init(symbol: "IMAGE_2236_CROSSHAIR1", xQ16: 220, yQ16: 165, width: 32, height: 32),
                           .init(symbol: "IMAGE_2231_9MMAMMO", xQ16: 261, yQ16: 220, width: 5, height: 12),
                       ]),
            watch: .init(visible: true, sourceSymbol: "gun_82_watchcommunicator",
                         animateButtons: true, controllerPad: 0,
                         positionQ16: .init(x: 200, y: 180, z: 0), scaleQ16: 65_536),
            transientEvents: events
        )
        let composition = try GoldenEyeRamRomNonModelVisualCompositionAdapterV6.compose(
            catalog: catalog, frame: frame, strict: true
        )
        precondition(composition.isPresentable)
        precondition(composition.entries.count == 11)
        precondition(composition.diagnostics.isEmpty)
        precondition(composition.entries.contains { $0.kind == .sky })
        precondition(composition.entries.contains { $0.kind == .cloud })
        precondition(composition.entries.contains { $0.kind == .fade })
        precondition(composition.entries.contains { $0.kind == .hud })
        precondition(composition.entries.contains { $0.kind == .watch })
        precondition(composition.entries.contains { $0.kind == .particle })
        precondition(composition.entries.contains { $0.kind == .effect })
        precondition(composition.entries.contains { $0.kind == .glass })
        precondition(composition.entries.contains { $0.kind == .explosion })
        precondition(composition.entries.contains { $0.kind == .projectile })

        let missing = try GoldenEyeRamRomNonModelVisualCompositionAdapterV6.compose(
            catalog: catalog,
            frame: .init(stageID: 33, demoID: 1, nativeTick: tick),
            strict: false
        )
        precondition(!missing.isPresentable)
        precondition(missing.unsupportedCategoryCount == 9)
        do {
            _ = try GoldenEyeRamRomNonModelVisualCompositionAdapterV6.compose(
                catalog: catalog,
                frame: .init(stageID: 33, demoID: 1, nativeTick: tick),
                strict: true
            )
            fatalError("strict missing-source state unexpectedly composed")
        } catch GoldenEyeRamRomNonModelVisualCompositionError.strictDiagnostics(let diagnostics) {
            precondition(Set(diagnostics.map(\.category)).count == 9)
        }
        print(
            "goldeneye_ramrom_non_model_visuals_v6_smoke: PASS "
                + "dependencies=\(catalog.dependencies.count) payloads=\(catalog.payloadCount) "
                + "semantic=\(catalog.semanticCount) entries=\(composition.entries.count) "
                + "missingCategories=\(missing.unsupportedCategoryCount) "
                + "manifestSHA256=\(catalog.manifestSHA256) compositionHash=\(composition.compositionHash)"
        )
    }
}
