import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Copied controller state from one source playback event.  The C event is
/// borrowed only for this initializer; no C array or pointer is retained.
public struct GoldenEyeRamRomRecordedControllerStateV6: Sendable, Equatable {
    public let controllerIndex: UInt32
    public let stickX: Int8
    public let stickY: Int8
    public let buttonLow: UInt8
    public let buttonHigh: UInt8
    public let buttons: UInt32
}

public struct GoldenEyeRamRomPlaybackAuthorityEventV6: Sendable, Equatable {
    public let eventType: UInt32
    public let flags: UInt32
    public let diagnosticCode: UInt32
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let pairPhase: UInt32
    public let demoID: UInt32
    public let stageID: UInt32
    public let packetIndex: UInt32
    public let packetCount: UInt32
    public let frameIndex: UInt32
    public let recordCount: UInt32
    public let controllerCount: UInt32
    public let speedframes: UInt32
    public let rngSeed: UInt32
    public let sampleCount: UInt32
    public let sourceAnchor: UInt32
    public let sourceFrame: UInt32
    public let abortButtons: UInt32
    public let sampleHash: UInt64
    public let stateHash: UInt64
    public let recordingHash: UInt64
    public let rngHash: UInt64
    public let controllers: [GoldenEyeRamRomRecordedControllerStateV6]

    public init(_ event: GERamRomPlaybackEventV5) {
        eventType = UInt32(event.event_type); flags = UInt32(event.flags)
        diagnosticCode = UInt32(event.diagnostic_code); nativeTick = UInt64(event.native_tick)
        referenceTick = UInt64(event.reference_tick); pairPhase = UInt32(event.pair_phase)
        demoID = UInt32(event.demo_id); stageID = UInt32(event.stage_id)
        packetIndex = UInt32(event.packet_index); packetCount = UInt32(event.packet_count)
        frameIndex = UInt32(event.frame_index); recordCount = UInt32(event.record_count)
        controllerCount = UInt32(event.controller_count); speedframes = UInt32(event.speedframes)
        rngSeed = UInt32(event.rng_seed); sampleCount = UInt32(event.sample_count)
        sourceAnchor = UInt32(event.source_anchor); sourceFrame = UInt32(event.source_frame)
        abortButtons = UInt32(event.abort_buttons); sampleHash = UInt64(event.sample_hash)
        stateHash = UInt64(event.state_hash); recordingHash = UInt64(event.recording_hash)
        rngHash = UInt64(event.rng_hash)
        let sticksX = Self.bytes(of: event.stick_x, as: Int8.self)
        let sticksY = Self.bytes(of: event.stick_y, as: Int8.self)
        let lows = Self.bytes(of: event.button_low, as: UInt8.self)
        let highs = Self.bytes(of: event.button_high, as: UInt8.self)
        let words = Self.bytes(of: event.buttons, as: UInt32.self)
        let count = min(Int(controllerCount), min(4, min(sticksX.count, min(sticksY.count, min(lows.count, min(highs.count, words.count))))))
        controllers = (0..<count).map { index in
            GoldenEyeRamRomRecordedControllerStateV6(
                controllerIndex: UInt32(index), stickX: sticksX[index], stickY: sticksY[index],
                buttonLow: lows[index], buttonHigh: highs[index], buttons: words[index]
            )
        }
    }

    private static func bytes<T, V>(of value: T, as: V.Type) -> [V] {
        withUnsafeBytes(of: value) { rawBytes in
            Array(rawBytes.bindMemory(to: V.self))
        }
    }
}

public struct GoldenEyeRamRomSnapshotValueV6: Sendable, Equatable {
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let demoID: UInt32
    public let stageID: UInt32
    public let replayState: UInt32
    public let packetIndex: UInt32
    public let packetCount: UInt32
    public let speedframes: UInt32
    public let rngIndex: UInt32
    public let inputButtons: UInt32
    public let recordingHash: UInt64
    public let rngHash: UInt64
    public let stateHash: UInt64
    public let renderHash: UInt64
    public let audioHash: UInt64
    public let saveGeneration: UInt64

    public init(_ snapshot: GERamRomSnapshotV5) {
        nativeTick = UInt64(snapshot.native_tick); referenceTick = UInt64(snapshot.reference_tick)
        demoID = UInt32(snapshot.demo_id); stageID = UInt32(snapshot.stage_id)
        replayState = UInt32(snapshot.replay_state); packetIndex = UInt32(snapshot.packet_index)
        packetCount = UInt32(snapshot.packet_count); speedframes = UInt32(snapshot.speedframes)
        rngIndex = UInt32(snapshot.rng_index); inputButtons = UInt32(snapshot.input_buttons)
        recordingHash = UInt64(snapshot.recording_hash); rngHash = UInt64(snapshot.rng_hash)
        stateHash = UInt64(snapshot.state_hash); renderHash = UInt64(snapshot.render_hash)
        audioHash = UInt64(snapshot.audio_hash); saveGeneration = UInt64(snapshot.save_generation)
    }
}

/// Join seam for the portable gameplay owner.  The character lane can publish
/// its own V6 pose packet independently; this record carries only the player,
/// camera, room, and hash values needed by HUD/watch/effect lowering.
public struct GoldenEyeRamRomStageVisualStateV6: Sendable, Equatable {
    public let stageID: UInt32
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let currentRoom: UInt32
    public let playerPositionQ16: GoldenEyeRamRomQ16Vector3V6
    public let cameraPositionQ16: GoldenEyeRamRomQ16Vector3V6
    public let cameraForwardQ16: GoldenEyeRamRomQ16Vector3V6
    public let stateHash: UInt64

    public init(
        stageID: UInt32, nativeTick: UInt64, referenceTick: UInt64,
        currentRoom: UInt32, playerPositionQ16: GoldenEyeRamRomQ16Vector3V6,
        cameraPositionQ16: GoldenEyeRamRomQ16Vector3V6,
        cameraForwardQ16: GoldenEyeRamRomQ16Vector3V6, stateHash: UInt64
    ) {
        self.stageID = stageID; self.nativeTick = nativeTick; self.referenceTick = referenceTick
        self.currentRoom = currentRoom; self.playerPositionQ16 = playerPositionQ16
        self.cameraPositionQ16 = cameraPositionQ16; self.cameraForwardQ16 = cameraForwardQ16
        self.stateHash = stateHash
    }
}

public struct GoldenEyeRamRomSourceHUDHandV6: Sendable, Equatable {
    public let visible: Bool
    public let handIndex: UInt32
    public let ammoType: UInt32
    public let magazine: UInt32
    public let reserve: UInt32
    public let iconYOffset: Int32

    public init(
        visible: Bool, handIndex: UInt32, ammoType: UInt32,
        magazine: UInt32, reserve: UInt32, iconYOffset: Int32 = 0
    ) {
        self.visible = visible; self.handIndex = handIndex; self.ammoType = ammoType
        self.magazine = magazine; self.reserve = reserve; self.iconYOffset = iconYOffset
    }
}

public struct GoldenEyeRamRomSourceHUDAuthorityV6: Sendable, Equatable {
    public let viewLeft: Int32
    public let viewTop: Int32
    public let viewWidth: Int32
    public let viewHeight: Int32
    public let rightHand: GoldenEyeRamRomSourceHUDHandV6?
    public let leftHand: GoldenEyeRamRomSourceHUDHandV6?
    public let sightVisible: Bool
    public let crosshairX: Int32
    public let crosshairY: Int32

    public init(
        viewLeft: Int32, viewTop: Int32, viewWidth: Int32, viewHeight: Int32,
        rightHand: GoldenEyeRamRomSourceHUDHandV6? = nil,
        leftHand: GoldenEyeRamRomSourceHUDHandV6? = nil,
        sightVisible: Bool = false, crosshairX: Int32 = 0, crosshairY: Int32 = 0
    ) {
        self.viewLeft = viewLeft; self.viewTop = viewTop; self.viewWidth = viewWidth
        self.viewHeight = viewHeight; self.rightHand = rightHand; self.leftHand = leftHand
        self.sightVisible = sightVisible; self.crosshairX = crosshairX; self.crosshairY = crosshairY
    }
}

public enum GoldenEyeRamRomSourceHUDLoweringV6 {
    private struct Icon {
        let symbol: String
        let width: UInt32
        let height: UInt32
    }

    public static func makeState(
        catalog: GoldenEyeRamRomNonModelDependencyCatalogV6,
        source: GoldenEyeRamRomSourceHUDAuthorityV6
    ) throws -> GoldenEyeRamRomHUDStateV6 {
        var symbols: [String] = []
        var placements: [GoldenEyeRamRomHUDImagePlacementV6] = []
        var rightAmmoType: UInt32 = 0
        var rightMagazine: UInt32 = 0
        var rightReserve: UInt32 = 0
        for hand in [source.rightHand, source.leftHand].compactMap({ $0 }) where hand.visible {
            guard let icon = icon(forAmmoType: hand.ammoType) else {
                throw GoldenEyeRamRomNonModelAuthorityErrorV6.unsupportedHUDAmmo(hand.ammoType)
            }
            guard catalog.dependency(category: .hud, symbol: icon.symbol)?.hasPreparedPayload == true else {
                throw GoldenEyeRamRomNonModelAuthorityErrorV6.missingHUDResource(icon.symbol)
            }
            let x = hand.handIndex == 0
                ? source.viewLeft + source.viewWidth - 59
                : source.viewLeft + 59
            let y = source.viewTop + source.viewHeight - 20 + hand.iconYOffset
            symbols.append(icon.symbol)
            placements.append(.init(
                symbol: icon.symbol, xQ16: x - Int32(icon.width / 2),
                yQ16: y - Int32(icon.height / 2), width: icon.width,
                height: icon.height, tintRGBA8: 0xffff_ffff,
                flags: GoldenEyeRamRomNonModelVisualEntryFlagsV6.textured
            ))
            if hand.handIndex == 0 {
                rightAmmoType = hand.ammoType; rightMagazine = hand.magazine; rightReserve = hand.reserve
            }
        }
        if source.sightVisible {
            let symbol = "IMAGE_2236_CROSSHAIR1"
            guard catalog.dependency(category: .hud, symbol: symbol)?.hasPreparedPayload == true else {
                throw GoldenEyeRamRomNonModelAuthorityErrorV6.missingHUDResource(symbol)
            }
            symbols.append(symbol)
            placements.append(.init(
                symbol: symbol, xQ16: source.crosshairX - 16, yQ16: source.crosshairY - 16,
                width: 32, height: 32, tintRGBA8: 0xffff_ff6e,
                flags: GoldenEyeRamRomNonModelVisualEntryFlagsV6.textured
            ))
        }
        return GoldenEyeRamRomHUDStateV6(
            visible: !placements.isEmpty, weaponTableIndex: 0,
            ammoType: rightAmmoType, ammoInMagazine: rightMagazine,
            ammoReserve: rightReserve, crosshairXQ16: source.crosshairX,
            crosshairYQ16: source.crosshairY, imageSymbols: symbols,
            imagePlacements: placements
        )
    }

    private static func icon(forAmmoType ammoType: UInt32) -> Icon? {
        switch ammoType {
        case 1, 2: return Icon(symbol: "IMAGE_2231_9MMAMMO", width: 5, height: 12)
        case 3: return Icon(symbol: "IMAGE_2232_RIFLEAMMO", width: 5, height: 28)
        case 4: return Icon(symbol: "IMAGE_2167_SHOTAMMO", width: 6, height: 20)
        case 5: return Icon(symbol: "IMAGE_2163_GRENADEAMMO", width: 14, height: 18)
        case 6: return Icon(symbol: "IMAGE_2161_ROCKETAMMO", width: 7, height: 22)
        case 7: return Icon(symbol: "IMAGE_2234_MINEAMMO", width: 14, height: 14)
        case 8: return Icon(symbol: "IMAGE_2235_PROXAMMO", width: 14, height: 14)
        case 9: return Icon(symbol: "IMAGE_2238_TIMEAMMO", width: 14, height: 14)
        case 10: return Icon(symbol: "IMAGE_2166_KNIFEAMMO", width: 6, height: 24)
        case 11: return Icon(symbol: "IMAGE_2165_GLAMMO", width: 8, height: 21)
        case 12: return Icon(symbol: "IMAGE_2164_MAGAMMO", width: 5, height: 15)
        case 13: return Icon(symbol: "IMAGE_2233_GGAMMO", width: 5, height: 12)
        default: return nil
        }
    }
}

public struct GoldenEyeRamRomNonModelPlaybackVisualStateV6: Sendable, Equatable {
    public fileprivate(set) var fadeActive: Bool
    public fileprivate(set) var lastNativeTick: UInt64
    public fileprivate(set) var lastReferenceTick: UInt64
    public fileprivate(set) var sourceAnchorCount: UInt64

    public init() {
        fadeActive = false; lastNativeTick = 0; lastReferenceTick = 0; sourceAnchorCount = 0
    }
}

public enum GoldenEyeRamRomNonModelSource2DPrimitiveV6: UInt32, Sendable, Equatable {
    case sourceSceneResource = 1
    case fillRectangle = 2
    case texturedRectangle = 3
}

public struct GoldenEyeRamRomNonModelSource2DDrawV6: Sendable, Equatable {
    public let primitive: GoldenEyeRamRomNonModelSource2DPrimitiveV6
    public let category: GoldenEyeRamRomNonModelVisualCategoryV6
    public let sourceSymbol: String
    public let resourceHandle: UInt32
    public let xQ16: Int32
    public let yQ16: Int32
    public let widthQ16: UInt32
    public let heightQ16: UInt32
    public let colourRGBA8: UInt32
    public let alphaQ16: UInt32
    public let sequence: UInt32
    public let flags: UInt32
}

public struct GoldenEyeRamRomNonModelSource2DPacketV6: Sendable, Equatable {
    public let stageID: UInt32
    public let demoID: UInt8
    public let nativeTick: UInt64
    public let referenceTick: UInt64
    public let logicalWidth: UInt32
    public let logicalHeight: UInt32
    public let draws: [GoldenEyeRamRomNonModelSource2DDrawV6]
    public let unsupportedCategoryCount: UInt32
    public let sourceManifestSHA256: String
    public let authorityHash: UInt64
    public let sourceStateHash: UInt64
    public let playbackHash: UInt64

    public var isPresentable: Bool { unsupportedCategoryCount == 0 }
}

public struct GoldenEyeRamRomNonModelPlaybackAuthorityFrameV6: Sendable, Equatable {
    public let playback: GoldenEyeRamRomPlaybackAuthorityEventV6
    public let snapshot: GoldenEyeRamRomSnapshotValueV6?
    public let state: GoldenEyeRamRomNonModelPlaybackVisualStateV6
    public let composition: GoldenEyeRamRomNonModelVisualCompositionV6
    public let packet: GoldenEyeRamRomNonModelSource2DPacketV6
}

public enum GoldenEyeRamRomNonModelAuthorityErrorV6: Error, Sendable, Equatable, CustomStringConvertible {
    case beginEventHasNoSourceTick
    case eventRouteMismatch
    case eventNotSequential(UInt64, UInt64)
    case unsupportedHUDAmmo(UInt32)
    case missingHUDResource(String)

    public var description: String {
        switch self {
        case .beginEventHasNoSourceTick: return "RAMROM begin event has no source playback tick"
        case .eventRouteMismatch: return "RAMROM playback event route does not match the selected demo"
        case let .eventNotSequential(expected, actual):
            return "RAMROM non-model authority expected native tick \(expected), got \(actual)"
        case let .unsupportedHUDAmmo(ammoType):
            return "source HUD ammo type \(ammoType) has no authored icon row"
        case let .missingHUDResource(symbol):
            return "source HUD resource is missing: \(symbol)"
        }
    }
}

/// Owner-thread adapter for source playback events.  It turns the static
/// source sky segment and the source fade events into real scene/fill packets,
/// while accepting optional authoritative HUD/watch/transient state from a
/// future gameplay owner.  It never infers a weapon, watch transform, effect,
/// or projectile from an input button or a packet hash.
public enum GoldenEyeRamRomNonModelPlaybackAuthorityV6 {
    public static func advance(
        catalog: GoldenEyeRamRomNonModelDependencyCatalogV6,
        state: inout GoldenEyeRamRomNonModelPlaybackVisualStateV6,
        playbackEvent: GERamRomPlaybackEventV5,
        snapshot: GERamRomSnapshotV5? = nil,
        stageState: GoldenEyeRamRomStageVisualStateV6? = nil,
        sourceFrame: GoldenEyeRamRomNonModelSourceFrameV6? = nil,
        strict: Bool = false
    ) throws -> GoldenEyeRamRomNonModelPlaybackAuthorityFrameV6 {
        let playback = GoldenEyeRamRomPlaybackAuthorityEventV6(playbackEvent)
        let snapshotValue = snapshot.map(GoldenEyeRamRomSnapshotValueV6.init)
        guard playback.eventType != UInt32(GE_RAMROM_PLAYBACK_EVENT_INSTALL_STATE) || playback.nativeTick != 0 else {
            throw GoldenEyeRamRomNonModelAuthorityErrorV6.beginEventHasNoSourceTick
        }
        guard let expectedStage = GoldenEyeRamRomNonModelDependencyCatalogV6.expectedStageID(
            for: UInt8(playback.demoID)
        ), expectedStage == playback.stageID else {
            throw GoldenEyeRamRomNonModelAuthorityErrorV6.eventRouteMismatch
        }
        if let stageState,
           stageState.stageID != playback.stageID || stageState.nativeTick != playback.nativeTick
                || stageState.referenceTick != playback.referenceTick {
            throw GoldenEyeRamRomNonModelAuthorityErrorV6.eventRouteMismatch
        }
        if state.lastNativeTick != 0, playback.nativeTick < state.lastNativeTick {
            throw GoldenEyeRamRomNonModelAuthorityErrorV6.eventNotSequential(state.lastNativeTick, playback.nativeTick)
        }
        state.lastNativeTick = playback.nativeTick
        state.lastReferenceTick = playback.referenceTick
        if playback.flags & UInt32(GE_RAMROM_PLAYBACK_EVENT_FLAG_SOURCE_ANCHOR) != 0 {
            state.sourceAnchorCount &+= 1
        }
        if playback.eventType == UInt32(GE_RAMROM_PLAYBACK_EVENT_FADE_TO_TITLE) {
            state.fadeActive = true
        }

        let frame = Self.sourceFrame(
            catalog: catalog, playback: playback, state: state, supplied: sourceFrame
        )
        let composition: GoldenEyeRamRomNonModelVisualCompositionV6
        do {
            composition = try GoldenEyeRamRomNonModelVisualCompositionAdapterV6.compose(
                catalog: catalog, frame: frame, strict: strict
            )
        } catch {
            throw error
        }
        let packet = Self.makePacket(
            catalog: catalog, playback: playback, composition: composition,
            sourceFrame: frame, snapshot: snapshotValue, stageState: stageState
        )
        if strict, !packet.isPresentable {
            // `compose(strict:)` already rejects its diagnostics.  This guard
            // protects against an adapter regression that drops a diagnostic
            // while still publishing an unsupported category count.
            throw GoldenEyeRamRomNonModelVisualCompositionError.strictDiagnostics(
                composition.diagnostics
            )
        }
        return GoldenEyeRamRomNonModelPlaybackAuthorityFrameV6(
            playback: playback, snapshot: snapshotValue, state: state,
            composition: composition, packet: packet
        )
    }

    private static func sourceFrame(
        catalog: GoldenEyeRamRomNonModelDependencyCatalogV6,
        playback: GoldenEyeRamRomPlaybackAuthorityEventV6,
        state: GoldenEyeRamRomNonModelPlaybackVisualStateV6,
        supplied: GoldenEyeRamRomNonModelSourceFrameV6?
    ) -> GoldenEyeRamRomNonModelSourceFrameV6 {
        let sky = supplied?.sky ?? staticSky(catalog: catalog, playback: playback)
        let fade = supplied?.fade ?? {
            guard state.fadeActive else { return nil }
            return GoldenEyeRamRomFadeStateV6(
                stageID: playback.stageID, demoID: UInt8(playback.demoID),
                elapsedQ16: 65_536, durationQ16: 65_536,
                colourRGBA8: 0x0000_00ff, fractionQ16: 65_536,
                flags: GoldenEyeRamRomNonModelVisualEntryFlagsV6.sourceAnchor
            )
        }()
        return GoldenEyeRamRomNonModelSourceFrameV6(
            stageID: supplied?.stageID ?? playback.stageID,
            demoID: supplied?.demoID ?? UInt8(playback.demoID),
            nativeTick: playback.nativeTick,
            sky: sky,
            fade: fade,
            hud: supplied?.hud,
            watch: supplied?.watch,
            transientEvents: supplied?.transientEvents ?? [],
            explicitlyInactive: supplied?.explicitlyInactive ?? []
        )
    }

    private static func staticSky(
        catalog: GoldenEyeRamRomNonModelDependencyCatalogV6,
        playback: GoldenEyeRamRomPlaybackAuthorityEventV6
    ) -> GoldenEyeRamRomSkyStateV6? {
        let symbol: String
        switch playback.stageID {
        case 33: symbol = "background_Dam"
        case 34: symbol = "background_Facility"
        case 35: symbol = "background_Runway"
        case 9: symbol = "background_Bunker I"
        case 20: symbol = "background_Silo"
        case 26: symbol = "background_Frigate"
        case 25: symbol = "background_Train"
        default: return nil
        }
        guard catalog.dependency(category: .sky, symbol: symbol)?.hasPreparedPayload == true else {
            return nil
        }
        // The source sky segment is a scene resource.  Fog/cloud colours are
        // intentionally not invented from the static row, so the source scene
        // lowerer treats this colour as metadata only until sky.c's environment
        // producer supplies the per-frame values.
        return GoldenEyeRamRomSkyStateV6(
            stageID: playback.stageID, demoID: UInt8(playback.demoID),
            backgroundSymbol: symbol, cloudSymbol: nil, cloudOffsetQ16: 0,
            environmentRGBA8: 0, cloudRGBA8: 0, waterRGBA8: 0,
            flags: GoldenEyeRamRomNonModelVisualEntryFlagsV6.sourceAnchor
        )
    }

    private static func makePacket(
        catalog: GoldenEyeRamRomNonModelDependencyCatalogV6,
        playback: GoldenEyeRamRomPlaybackAuthorityEventV6,
        composition: GoldenEyeRamRomNonModelVisualCompositionV6,
        sourceFrame: GoldenEyeRamRomNonModelSourceFrameV6,
        snapshot: GoldenEyeRamRomSnapshotValueV6?,
        stageState: GoldenEyeRamRomStageVisualStateV6?
    ) -> GoldenEyeRamRomNonModelSource2DPacketV6 {
        var draws: [GoldenEyeRamRomNonModelSource2DDrawV6] = []
        var sequence: UInt32 = 0
        for entry in composition.entries {
            let primitive: GoldenEyeRamRomNonModelSource2DPrimitiveV6
            let width: UInt32
            let height: UInt32
            let x: Int32
            let y: Int32
            switch entry.kind {
            case .sky, .cloud:
                primitive = .sourceSceneResource; width = 0; height = 0
                x = entry.positionQ16.x; y = entry.positionQ16.y
            case .fade:
                primitive = .fillRectangle; width = 440 << 16; height = 330 << 16
                x = 0; y = 0
            case .hud:
                primitive = .texturedRectangle
                if let placement = sourceFrame.hud?.imagePlacements.first(where: {
                    $0.symbol == entry.resourceSymbol
                }) {
                    width = placement.width << 16; height = placement.height << 16
                    x = placement.xQ16; y = placement.yQ16
                } else {
                    // Composition may retain metadata for a hidden HUD row;
                    // it is not a visible draw without the source rectangle.
                    continue
                }
            case .watch:
                primitive = .sourceSceneResource; width = 0; height = 0
                x = entry.positionQ16.x; y = entry.positionQ16.y
            case .particle, .effect, .glass, .explosion, .projectile:
                primitive = .sourceSceneResource; width = 0; height = 0
                x = entry.positionQ16.x; y = entry.positionQ16.y
            }
            draws.append(.init(
                primitive: primitive, category: entry.category,
                sourceSymbol: entry.sourceSymbol, resourceHandle: entry.resourceHandle,
                xQ16: x, yQ16: y, widthQ16: width, heightQ16: height,
                colourRGBA8: entry.colourRGBA8, alphaQ16: entry.alphaQ16,
                sequence: sequence, flags: entry.flags
            ))
            sequence &+= 1
        }
        var hash: UInt64 = 1_469_598_103_934_665_603
        func mix(_ value: UInt64) { hash = (hash ^ value) &* 1_099_511_628_211 }
        mix(UInt64(playback.stageID)); mix(UInt64(playback.demoID)); mix(playback.nativeTick)
        mix(playback.recordingHash); mix(playback.rngHash); mix(composition.compositionHash)
        mix(snapshot?.renderHash ?? 0); mix(stageState?.stateHash ?? 0)
        for draw in draws {
            mix(UInt64(draw.primitive.rawValue)); mix(UInt64(draw.resourceHandle))
            mix(UInt64(bitPattern: Int64(draw.xQ16))); mix(UInt64(draw.widthQ16)); mix(UInt64(draw.sequence))
        }
        return GoldenEyeRamRomNonModelSource2DPacketV6(
            stageID: playback.stageID, demoID: UInt8(playback.demoID),
            nativeTick: playback.nativeTick, referenceTick: playback.referenceTick,
            logicalWidth: 440, logicalHeight: 330, draws: draws,
            unsupportedCategoryCount: UInt32(composition.unsupportedCategoryCount),
            sourceManifestSHA256: catalog.manifestSHA256, authorityHash: hash,
            sourceStateHash: stageState?.stateHash ?? snapshot?.stateHash ?? playback.stateHash,
            playbackHash: playback.recordingHash
        )
    }
}
