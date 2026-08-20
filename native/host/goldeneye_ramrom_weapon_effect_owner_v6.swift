import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Resolver input for the source owner.  Handles are supplied by the guarded
/// visible-dependency catalog; this adapter never invents a name from a
/// numeric handle or opens a payload.  Missing linkage is a hard error.
public struct GoldenEyeRamRomWeaponEffectResourceMapV6: Equatable {
    public let sourceSymbolsByID: [UInt32: String]
    public let resourceSymbolsByHandle: [UInt32: String]
    public let imageDimensionsByHandle: [UInt32: (UInt32, UInt32)]

    public init(
        sourceSymbolsByID: [UInt32: String],
        resourceSymbolsByHandle: [UInt32: String],
        imageDimensionsByHandle: [UInt32: (UInt32, UInt32)]
    ) {
        self.sourceSymbolsByID = sourceSymbolsByID
        self.resourceSymbolsByHandle = resourceSymbolsByHandle
        self.imageDimensionsByHandle = imageDimensionsByHandle
    }

    public static func == (
        lhs: GoldenEyeRamRomWeaponEffectResourceMapV6,
        rhs: GoldenEyeRamRomWeaponEffectResourceMapV6
    ) -> Bool {
        lhs.sourceSymbolsByID == rhs.sourceSymbolsByID
            && lhs.resourceSymbolsByHandle == rhs.resourceSymbolsByHandle
            && lhs.imageDimensionsByHandle.keys == rhs.imageDimensionsByHandle.keys
            && lhs.imageDimensionsByHandle.allSatisfy {
                rhs.imageDimensionsByHandle[$0.key]?.0 == $0.value.0
                    && rhs.imageDimensionsByHandle[$0.key]?.1 == $0.value.1
            }
    }
}

public enum GoldenEyeRamRomWeaponEffectOwnerErrorV6: Error, Sendable, Equatable, CustomStringConvertible {
    case cStatus(UInt32)
    case missingSourceSymbol(UInt32)
    case missingResourceSymbol(UInt32)
    case missingImageDimensions(UInt32)
    case unsupportedCategory(UInt32)
    case gameplayRouteMismatch

    public var description: String {
        switch self {
        case let .cStatus(status): return "weapon/effect source owner status \(status)"
        case let .missingSourceSymbol(id): return "weapon/effect source symbol \(id) is not linked"
        case let .missingResourceSymbol(handle): return "weapon/effect resource handle 0x\(String(handle, radix: 16)) is not linked"
        case let .missingImageDimensions(handle): return "weapon/effect image handle 0x\(String(handle, radix: 16)) has no source dimensions"
        case let .unsupportedCategory(category): return "weapon/effect source category \(category) is not lowerable"
        case .gameplayRouteMismatch: return "weapon/effect source frame does not match gameplay V6 route"
        }
    }
}

/// Value-only bridge from the directly compiled weapon/effect owner into the
/// existing non-model composition seam.  It is intentionally not a renderer:
/// the source model/effect lowerer consumes the resulting immutable frame.
public enum GoldenEyeRamRomWeaponEffectOwnerAdapterV6 {
    private static let muzzle = UInt32(1)
    private static let projectile = UInt32(2)
    private static let particle = UInt32(3)
    private static let explosion = UInt32(4)
    private static let glass = UInt32(5)
    private static let fade = UInt32(6)
    private static let watch = UInt32(7)
    private static let hud = UInt32(8)
    private static let sight = UInt32(9)
    private static let sfx = UInt32(10)

    public static func makeSourceFrame(
        _ source: GERamRomWeaponEffectFrameV6,
        resources: GoldenEyeRamRomWeaponEffectResourceMapV6,
        sky: GoldenEyeRamRomSkyStateV6? = nil,
        explicitlyInactive: Set<GoldenEyeRamRomNonModelVisualCategoryV6> = []
    ) throws -> GoldenEyeRamRomNonModelSourceFrameV6 {
        var sourceCopy = source
        let status = ge_ramrom_weapon_effect_v6_validate_frame(&sourceCopy)
        guard status == 0 else { throw GoldenEyeRamRomWeaponEffectOwnerErrorV6.cStatus(status) }

        let hands = withUnsafeBytes(of: sourceCopy.hands) { raw -> [GERamRomWeaponHandV6] in
            Array(raw.bindMemory(to: GERamRomWeaponHandV6.self).prefix(Int(sourceCopy.hand_count)))
        }
        let events = withUnsafeBytes(of: sourceCopy.events) { raw -> [GERamRomWeaponEffectEventV6] in
            Array(raw.bindMemory(to: GERamRomWeaponEffectEventV6.self).prefix(Int(sourceCopy.event_count)))
        }
        var inactive = explicitlyInactive
        if sourceCopy.source_inactive_mask & (1 << (fade - 1)) != 0 || sourceCopy.fade_visible == 0 {
            inactive.insert(.fades)
        }
        if sourceCopy.source_inactive_mask & (1 << (hud - 1)) != 0 || sourceCopy.hud_visible == 0 {
            inactive.insert(.hud)
        }
        if sourceCopy.source_inactive_mask & (1 << (watch - 1)) != 0 || sourceCopy.watch_visible == 0 {
            inactive.insert(.watch)
        }
        if sourceCopy.source_inactive_mask & (1 << (particle - 1)) != 0 {
            inactive.insert(.particles)
        }
        if sourceCopy.source_inactive_mask & (1 << (explosion - 1)) != 0 {
            inactive.insert(.explosions)
        }
        if sourceCopy.source_inactive_mask & (1 << (glass - 1)) != 0 {
            inactive.insert(.glass)
        }
        if sourceCopy.source_inactive_mask & (1 << (projectile - 1)) != 0 {
            inactive.insert(.projectiles)
        }

        let hudState: GoldenEyeRamRomHUDStateV6?
        if sourceCopy.hud_visible != 0 {
            var symbols: [String] = []
            var placements: [GoldenEyeRamRomHUDImagePlacementV6] = []
            func addHand(
                hand: GERamRomWeaponHandV6,
                imageHandle: UInt32,
                width: UInt32,
                height: UInt32
            ) throws {
                guard imageHandle != 0, let symbol = resources.resourceSymbolsByHandle[imageHandle] else {
                    throw GoldenEyeRamRomWeaponEffectOwnerErrorV6.missingResourceSymbol(imageHandle)
                }
                symbols.append(symbol)
                let handIndex = hand.hand_index
                let x = handIndex == 0
                    ? sourceCopy.view_left_q16 + Int32(sourceCopy.view_width_q16) - 59
                    : sourceCopy.view_left_q16 + 59
                let y = sourceCopy.view_top_q16 + Int32(sourceCopy.view_height_q16) - 20
                placements.append(.init(
                    symbol: symbol, xQ16: x - Int32(width / 2), yQ16: y - Int32(height / 2),
                    width: width, height: height, tintRGBA8: 0xffff_ffff,
                    flags: GoldenEyeRamRomNonModelVisualEntryFlagsV6.textured
                ))
            }
            if sourceCopy.right_hud_image_handle != 0 {
                let dimensions = (sourceCopy.right_hud_width, sourceCopy.right_hud_height)
                guard dimensions.0 > 0, dimensions.1 > 0 else {
                    throw GoldenEyeRamRomWeaponEffectOwnerErrorV6.missingImageDimensions(sourceCopy.right_hud_image_handle)
                }
                guard let hand = hands.first(where: { $0.hand_index == 0 }) else {
                    throw GoldenEyeRamRomWeaponEffectOwnerErrorV6.cStatus(10)
                }
                try addHand(hand: hand, imageHandle: sourceCopy.right_hud_image_handle,
                            width: dimensions.0, height: dimensions.1)
            }
            if sourceCopy.left_hud_image_handle != 0 {
                let dimensions = (sourceCopy.left_hud_width, sourceCopy.left_hud_height)
                guard dimensions.0 > 0, dimensions.1 > 0 else {
                    throw GoldenEyeRamRomWeaponEffectOwnerErrorV6.missingImageDimensions(sourceCopy.left_hud_image_handle)
                }
                guard let hand = hands.first(where: { $0.hand_index == 1 }) else {
                    throw GoldenEyeRamRomWeaponEffectOwnerErrorV6.cStatus(10)
                }
                try addHand(hand: hand, imageHandle: sourceCopy.left_hud_image_handle,
                            width: dimensions.0, height: dimensions.1)
            }
            if sourceCopy.sight_visible != 0 {
                guard sourceCopy.crosshair_image_handle != 0,
                      let symbol = resources.resourceSymbolsByHandle[sourceCopy.crosshair_image_handle],
                      let dimensions = resources.imageDimensionsByHandle[sourceCopy.crosshair_image_handle],
                      dimensions.0 > 0, dimensions.1 > 0 else {
                    throw GoldenEyeRamRomWeaponEffectOwnerErrorV6.missingResourceSymbol(sourceCopy.crosshair_image_handle)
                }
                symbols.append(symbol)
                placements.append(.init(
                    symbol: symbol,
                    xQ16: sourceCopy.crosshair_x_q16 - Int32(dimensions.0 / 2),
                    yQ16: sourceCopy.crosshair_y_q16 - Int32(dimensions.1 / 2),
                    width: dimensions.0, height: dimensions.1,
                    tintRGBA8: 0xffff_ff6e,
                    flags: GoldenEyeRamRomNonModelVisualEntryFlagsV6.textured
                ))
            }
            hudState = .init(
                visible: true, weaponTableIndex: 0,
                ammoType: sourceCopy.right_ammo_type,
                ammoInMagazine: sourceCopy.right_magazine,
                ammoReserve: sourceCopy.right_reserve,
                crosshairXQ16: sourceCopy.crosshair_x_q16,
                crosshairYQ16: sourceCopy.crosshair_y_q16,
                imageSymbols: symbols, imagePlacements: placements
            )
        } else {
            hudState = nil
        }

        let watchState: GoldenEyeRamRomWatchStateV6?
        if sourceCopy.watch_visible != 0 {
            guard let symbol = resources.resourceSymbolsByHandle[sourceCopy.watch_model_handle] else {
                throw GoldenEyeRamRomWeaponEffectOwnerErrorV6.missingResourceSymbol(sourceCopy.watch_model_handle)
            }
            watchState = .init(
                visible: true, sourceSymbol: symbol,
                animateButtons: sourceCopy.watch_animate_buttons != 0,
                controllerPad: Int8(clamping: Int(sourceCopy.watch_controller_pad)),
                positionQ16: .init(
                    x: sourceCopy.watch_position_q16.0,
                    y: sourceCopy.watch_position_q16.1,
                    z: sourceCopy.watch_position_q16.2
                ), scaleQ16: UInt32(sourceCopy.watch_scale_q16)
            )
        } else {
            watchState = nil
        }

        let fadeState: GoldenEyeRamRomFadeStateV6?
        if sourceCopy.fade_visible != 0 {
            fadeState = .init(
                stageID: sourceCopy.stage_id, demoID: UInt8(sourceCopy.demo_id),
                elapsedQ16: sourceCopy.fade_elapsed_q16,
                durationQ16: sourceCopy.fade_duration_q16,
                colourRGBA8: sourceCopy.fade_colour_rgba,
                fractionQ16: sourceCopy.fade_q16,
                flags: GoldenEyeRamRomNonModelVisualEntryFlagsV6.sourceAnchor
            )
        } else {
            fadeState = nil
        }

        var transient: [GoldenEyeRamRomTransientVisualEventV6] = []
        for event in events where event.category != sfx {
            let (category, sourceSymbol): (GoldenEyeRamRomTransientVisualCategoryV6, String)
            switch event.category {
            case muzzle:
                category = .effects; sourceSymbol = "gunfire_effect_dispatch"
            case projectile:
                category = .projectiles
                guard let value = resources.sourceSymbolsByID[event.source_resource_id] else {
                    throw GoldenEyeRamRomWeaponEffectOwnerErrorV6.missingSourceSymbol(event.source_resource_id)
                }
                sourceSymbol = value
            case particle:
                category = .particles; sourceSymbol = "particle_effect_dispatch"
            case explosion:
                category = .explosions; sourceSymbol = "explosion_render_dispatch"
            case glass:
                category = .glass
                guard let value = resources.sourceSymbolsByID[event.source_resource_id] else {
                    throw GoldenEyeRamRomWeaponEffectOwnerErrorV6.missingSourceSymbol(event.source_resource_id)
                }
                sourceSymbol = value
            default:
                throw GoldenEyeRamRomWeaponEffectOwnerErrorV6.unsupportedCategory(event.category)
            }
            guard let resourceSymbol = resources.resourceSymbolsByHandle[event.resource_handle] else {
                throw GoldenEyeRamRomWeaponEffectOwnerErrorV6.missingResourceSymbol(event.resource_handle)
            }
            transient.append(.init(
                category: category, sourceSymbol: sourceSymbol, resourceSymbol: resourceSymbol,
                sourceReferenceTick: event.source_reference_tick, sequence: event.sequence,
                positionQ16: .init(x: event.position_q16.0, y: event.position_q16.1, z: event.position_q16.2),
                scaleQ16: UInt32(event.scale_q16.0), rotationQ16: event.rotation_q16.1,
                frameIndex: event.frame_index, colourRGBA8: event.colour_rgba,
                alphaQ16: event.alpha_q16, flags: event.flags
            ))
        }

        return GoldenEyeRamRomNonModelSourceFrameV6(
            stageID: sourceCopy.stage_id, demoID: UInt8(sourceCopy.demo_id),
            nativeTick: sourceCopy.native_tick, sky: sky, fade: fadeState,
            hud: hudState, watch: watchState, transientEvents: transient,
            explicitlyInactive: inactive
        )
    }

    public static func compose(
        catalog: GoldenEyeRamRomNonModelDependencyCatalogV6,
        source: GERamRomWeaponEffectFrameV6,
        resources: GoldenEyeRamRomWeaponEffectResourceMapV6,
        sky: GoldenEyeRamRomSkyStateV6? = nil,
        explicitlyInactive: Set<GoldenEyeRamRomNonModelVisualCategoryV6> = [],
        strict: Bool = true
    ) throws -> GoldenEyeRamRomNonModelVisualCompositionV6 {
        let frame = try makeSourceFrame(
            source, resources: resources, sky: sky, explicitlyInactive: explicitlyInactive
        )
        return try GoldenEyeRamRomNonModelVisualCompositionAdapterV6.compose(
            catalog: catalog, frame: frame, strict: strict
        )
    }

    /// Route-checked join for the gameplay V6 owner.  The gameplay snapshot
    /// supplies the authoritative demo/stage/native tick; weapon/effect rows
    /// must describe that same source frame before they reach composition.
    public static func makeSourceFrame(
        gameplay: GERamRomGameplaySnapshotV6,
        source: GERamRomWeaponEffectFrameV6,
        resources: GoldenEyeRamRomWeaponEffectResourceMapV6,
        sky: GoldenEyeRamRomSkyStateV6? = nil,
        explicitlyInactive: Set<GoldenEyeRamRomNonModelVisualCategoryV6> = []
    ) throws -> GoldenEyeRamRomNonModelSourceFrameV6 {
        guard gameplay.demo_id == source.demo_id,
              gameplay.stage_id == source.stage_id,
              gameplay.native_tick == source.native_tick else {
            throw GoldenEyeRamRomWeaponEffectOwnerErrorV6.gameplayRouteMismatch
        }
        return try makeSourceFrame(
            source, resources: resources, sky: sky, explicitlyInactive: explicitlyInactive
        )
    }

    public static func compose(
        catalog: GoldenEyeRamRomNonModelDependencyCatalogV6,
        gameplay: GERamRomGameplaySnapshotV6,
        source: GERamRomWeaponEffectFrameV6,
        resources: GoldenEyeRamRomWeaponEffectResourceMapV6,
        sky: GoldenEyeRamRomSkyStateV6? = nil,
        explicitlyInactive: Set<GoldenEyeRamRomNonModelVisualCategoryV6> = [],
        strict: Bool = true
    ) throws -> GoldenEyeRamRomNonModelVisualCompositionV6 {
        let frame = try makeSourceFrame(
            gameplay: gameplay, source: source, resources: resources,
            sky: sky, explicitlyInactive: explicitlyInactive
        )
        return try GoldenEyeRamRomNonModelVisualCompositionAdapterV6.compose(
            catalog: catalog, frame: frame, strict: strict
        )
    }
}
