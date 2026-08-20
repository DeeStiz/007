import Foundation

@main
struct GoldenEyeRamRomNonModelAuthorityV6Smoke {
    private struct Result: Equatable {
        let demoID: UInt32
        let samples: UInt32
        let skyFrames: UInt32
        let fadeFrames: UInt32
        let terminalHash: UInt64
        let authorityHash: UInt64
    }

    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("usage: goldeneye_ramrom_non_model_authority_v6_smoke /absolute/boot-root /absolute/visible-root")
        }
        let bootRoot = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let visibleRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let catalog = try GoldenEyeRamRomNonModelDependencyCatalogV6.load(rootURL: visibleRoot)
        let routes = try GoldenEyeRamRomRouteCatalog.parsed(assetRoot: bootRoot)
        precondition(routes.isComplete)

        var first: [UInt32: Result] = [:]
        var second: [UInt32: Result] = [:]
        for pass in 0..<2 {
            for route in routes.entries {
                let result = try run(route: route, bootRoot: bootRoot, catalog: catalog)
                if pass == 0 {
                    first[UInt32(route.demoID)] = result
                } else {
                    precondition(second[UInt32(route.demoID)] == nil)
                    second[UInt32(route.demoID)] = result
                    precondition(first[UInt32(route.demoID)] == result)
                }
            }
        }
        precondition(first.count == 14)
        precondition(second.count == 14)
        let fadeCount = first.values.reduce(0) { $0 + $1.fadeFrames }
        let skyCount = first.values.reduce(0) { $0 + $1.skyFrames }
        let sampleCount = first.values.reduce(0) { $0 + $1.samples }
        var aggregate: UInt64 = 1_469_598_103_934_665_603
        for value in first.values.sorted(by: { $0.demoID < $1.demoID }) {
            for word in [UInt64(value.demoID), UInt64(value.samples), UInt64(value.skyFrames),
                         UInt64(value.fadeFrames), value.terminalHash, value.authorityHash] {
                aggregate = mix(aggregate, word)
            }
        }
        print(
            "goldeneye_ramrom_non_model_authority_v6_smoke: PASS "
                + "demos=14 runs=28 samples=\(sampleCount) skyFrames=\(skyCount) "
                + "fadeFrames=\(fadeCount) aggregate=\(aggregate)"
        )
    }

    private static func run(
        route: GoldenEyeRamRomDemoRoute,
        bootRoot: URL,
        catalog: GoldenEyeRamRomNonModelDependencyCatalogV6
    ) throws -> Result {
        let url = bootRoot.appendingPathComponent("ramrom", isDirectory: true)
            .appendingPathComponent(route.assetName, isDirectory: false)
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        var state = GERamRomPlaybackStateV5()
        var beginEvent = GERamRomPlaybackEventV5()
        let beginStatus = data.withUnsafeBytes { bytes -> UInt32 in
            guard let base = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return UInt32(GE_STATUS_INVALID_ARGUMENT)
            }
            return UInt32(ge_ramrom_playback_v5_begin(
                base, UInt32(data.count), UInt32(route.demoID), &state, &beginEvent
            ))
        }
        precondition(beginStatus == UInt32(GE_STATUS_OK))
        precondition(beginEvent.event_type == UInt32(GE_RAMROM_PLAYBACK_EVENT_STAGE_LOAD_UNSUPPORTED))

        var visualState = GoldenEyeRamRomNonModelPlaybackVisualStateV6()
        let beginOutput = try GoldenEyeRamRomNonModelPlaybackAuthorityV6.advance(
            catalog: catalog, state: &visualState, playbackEvent: beginEvent, strict: false
        )
        precondition(beginOutput.packet.draws.contains { $0.category == .sky })
        if route.demoID == 1 {
            let hudState = try GoldenEyeRamRomSourceHUDLoweringV6.makeState(
                catalog: catalog,
                source: .init(
                    viewLeft: 0, viewTop: 0, viewWidth: 320, viewHeight: 240,
                    rightHand: .init(visible: true, handIndex: 0, ammoType: 1, magazine: 7, reserve: 35),
                    sightVisible: true, crosshairX: 160, crosshairY: 120
                )
            )
            precondition(hudState.imagePlacements.count == 2)
            precondition(hudState.imageSymbols.contains("IMAGE_2231_9MMAMMO"))
            var completeState = GoldenEyeRamRomNonModelPlaybackVisualStateV6()
            let complete = try GoldenEyeRamRomNonModelPlaybackAuthorityV6.advance(
                catalog: catalog, state: &completeState, playbackEvent: beginEvent,
                sourceFrame: completeSourceFrame(nativeTick: 0), strict: true
            )
            precondition(complete.packet.isPresentable)
            precondition(complete.packet.draws.count == 10)
            precondition(complete.packet.draws.contains { $0.category == .hud && $0.primitive == .texturedRectangle })
            precondition(complete.packet.draws.contains { $0.category == .watch && $0.primitive == .sourceSceneResource })
        }

        var samples: UInt32 = 0
        var skyFrames: UInt32 = 0
        var fadeFrames: UInt32 = 0
        var sawReturn = false
        var terminalHash: UInt64 = 0
        var authorityHash: UInt64 = beginOutput.packet.authorityHash
        for tick in UInt64(0)..<(UInt64(route.recordCount) * 2 + 16) {
            var event = GERamRomPlaybackEventV5()
            let status = data.withUnsafeBytes { bytes -> UInt32 in
                guard let base = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return UInt32(GE_STATUS_INVALID_ARGUMENT)
                }
                return UInt32(ge_ramrom_playback_v5_step(
                    base, UInt32(data.count), tick, noInput(), &state, &event
                ))
            }
            precondition(status == UInt32(GE_STATUS_OK))
            let output = try GoldenEyeRamRomNonModelPlaybackAuthorityV6.advance(
                catalog: catalog, state: &visualState, playbackEvent: event, strict: false
            )
            precondition(output.playback.demoID == UInt32(route.demoID))
            precondition(output.playback.stageID == route.stageID)
            precondition(output.packet.draws.contains { $0.category == .sky })
            skyFrames &+= 1
            if event.event_type == UInt32(GE_RAMROM_PLAYBACK_EVENT_SAMPLE) { samples &+= 1 }
            if event.event_type == UInt32(GE_RAMROM_PLAYBACK_EVENT_FADE_TO_TITLE) {
                fadeFrames &+= 1
                precondition(output.packet.draws.contains { $0.category == .fades && $0.primitive == .fillRectangle })
            }
            if event.event_type == UInt32(GE_RAMROM_PLAYBACK_EVENT_RETURN_TO_TITLE) {
                sawReturn = true
                terminalHash = event.state_hash
                authorityHash = output.packet.authorityHash
                break
            }
            authorityHash = output.packet.authorityHash
        }
        precondition(samples == route.recordCount)
        precondition(fadeFrames == 1)
        precondition(sawReturn)
        return Result(
            demoID: UInt32(route.demoID), samples: samples, skyFrames: skyFrames,
            fadeFrames: fadeFrames, terminalHash: terminalHash, authorityHash: authorityHash
        )
    }

    private static func noInput() -> GERamRomPlaybackInputV5 {
        var input = GERamRomPlaybackInputV5()
        input.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        input.header.struct_size = UInt32(MemoryLayout<GERamRomPlaybackInputV5>.size)
        input.record_version = UInt32(GE_RAMROM_PLAYBACK_V5_RECORD_VERSION)
        input.flags = UInt32(GE_RAMROM_PLAYBACK_INPUT_FOCUSED)
        input.controller_count = 1
        return input
    }

    private static func completeSourceFrame(nativeTick: UInt64) -> GoldenEyeRamRomNonModelSourceFrameV6 {
        let events = [
            GoldenEyeRamRomTransientVisualEventV6(
                category: .particles, sourceSymbol: "particle_effect_dispatch",
                resourceSymbol: "IMAGE_2084_SMOKE_0", sourceReferenceTick: nativeTick >> 1,
                sequence: 1, positionQ16: .init(x: 1, y: 2, z: 3), scaleQ16: 65_536,
                rotationQ16: 0, frameIndex: 0, colourRGBA8: 0xffff_ffff, alphaQ16: 65_536),
            GoldenEyeRamRomTransientVisualEventV6(
                category: .effects, sourceSymbol: "gunfire_effect_dispatch",
                resourceSymbol: "IMAGE_2085_FIRE_0", sourceReferenceTick: nativeTick >> 1,
                sequence: 2, positionQ16: .init(x: 4, y: 5, z: 6), scaleQ16: 65_536,
                rotationQ16: 0, frameIndex: 0, colourRGBA8: 0xffff_ffff, alphaQ16: 65_536),
            GoldenEyeRamRomTransientVisualEventV6(
                category: .glass, sourceSymbol: "prop_104_window",
                resourceSymbol: "IMAGE_155_RAILING_GLASS", sourceReferenceTick: nativeTick >> 1,
                sequence: 3, positionQ16: .init(x: 7, y: 8, z: 9), scaleQ16: 65_536,
                rotationQ16: 0, frameIndex: 0, colourRGBA8: 0xffff_ffff, alphaQ16: 65_536),
            GoldenEyeRamRomTransientVisualEventV6(
                category: .explosions, sourceSymbol: "explosion_render_dispatch",
                resourceSymbol: "IMAGE_206_IMPACTLOTS", sourceReferenceTick: nativeTick >> 1,
                sequence: 4, positionQ16: .init(x: 10, y: 11, z: 12), scaleQ16: 65_536,
                rotationQ16: 0, frameIndex: 0, colourRGBA8: 0xffff_ffff, alphaQ16: 65_536),
            GoldenEyeRamRomTransientVisualEventV6(
                category: .projectiles, sourceSymbol: "gun_5_bombcase",
                resourceSymbol: "gun_5_bombcase", sourceReferenceTick: nativeTick >> 1,
                sequence: 5, positionQ16: .init(x: 13, y: 14, z: 15), scaleQ16: 65_536,
                rotationQ16: 0, frameIndex: 0, colourRGBA8: 0xffff_ffff, alphaQ16: 65_536),
        ]
        return GoldenEyeRamRomNonModelSourceFrameV6(
            stageID: 33, demoID: 1, nativeTick: nativeTick,
            sky: .init(stageID: 33, demoID: 1, backgroundSymbol: "background_Dam",
                       cloudOffsetQ16: 0, environmentRGBA8: 0, cloudRGBA8: 0, waterRGBA8: 0),
            fade: .init(stageID: 33, demoID: 1, elapsedQ16: 0, durationQ16: 65_536,
                        colourRGBA8: 0x000000ff, fractionQ16: 0),
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
    }

    private static func mix(_ initial: UInt64, _ word: UInt64) -> UInt64 {
        var hash = initial
        var value = word
        for _ in 0..<8 {
            hash = (hash ^ (value & 0xff)) &* 1_099_511_628_211
            value >>= 8
        }
        return hash
    }
}
