import Foundation

@main
struct GoldenEyeRamRomWeaponEffectOwnerV6Smoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("usage: goldeneye_ramrom_weapon_effect_owner_v6_smoke /absolute/visible-dependency-root")
        }
        precondition(MemoryLayout<GERamRomWeaponEffectSetupV6>.size == 128)
        precondition(MemoryLayout<GERamRomWeaponHandV6>.size == 152)
        precondition(MemoryLayout<GERamRomWeaponEffectEventV6>.size == 160)
        precondition(MemoryLayout<GERamRomWeaponEffectFrameV6>.size == 10_784)
        precondition(MemoryLayout<GERamRomWeaponEffectSnapshotV6>.size == 160)
        precondition(MemoryLayout<GERamRomWeaponEffectEventRecordV6>.size == 104)
        precondition(MemoryLayout<GERamRomWeaponEffectOwnerStateV6>.size == 32_736)
        var frame = GERamRomWeaponEffectFrameV6()
        frame.header.abi_version = GE_NATIVE_ABI_VERSION
        frame.header.struct_size = UInt32(MemoryLayout<GERamRomWeaponEffectFrameV6>.size)
        frame.record_version = 1
        frame.flags = 1 | 4 | 8 | 16 | 32
        frame.demo_id = 1
        frame.stage_id = 33
        frame.native_tick = 2
        frame.reference_tick = 1
        frame.source_anchor = 1
        frame.source_frame = 2
        frame.source_present_mask = (1 << 0) | (1 << 5) | (1 << 6) | (1 << 7) | (1 << 8)
        frame.source_inactive_mask = (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 9)
        frame.hand_count = 1
        frame.event_count = 1
        frame.hud_visible = 1
        frame.view_left_q16 = 0
        frame.view_top_q16 = 0
        frame.view_width_q16 = 440
        frame.view_height_q16 = 330
        frame.right_hud_image_handle = 0xb0002231
        frame.right_hud_width = 5
        frame.right_hud_height = 12
        frame.right_ammo_type = 1
        frame.right_magazine = 7
        frame.right_reserve = 35
        frame.crosshair_x_q16 = 220
        frame.crosshair_y_q16 = 165
        frame.crosshair_image_handle = 0xb0002236
        frame.sight_visible = 1
        frame.watch_visible = 1
        frame.watch_model_handle = 0x90000052
        frame.watch_animate_buttons = 1
        frame.watch_controller_pad = 0
        frame.watch_scale_q16 = 65_536
        frame.fade_visible = 1
        frame.fade_colour_rgba = 0x000000ff
        frame.fade_q16 = 0
        frame.fade_elapsed_q16 = 0
        frame.fade_duration_q16 = 65_536
        frame.source_hash = 0x6400000000000001
        frame.resource_hash = 0x6500000000000001

        var hand = GERamRomWeaponHandV6()
        hand.header.abi_version = GE_NATIVE_ABI_VERSION
        hand.header.struct_size = UInt32(MemoryLayout<GERamRomWeaponHandV6>.size)
        hand.record_version = 1
        hand.hand_index = 0
        hand.flags = 1
        hand.weapon_id = 2
        hand.model_handle = 0x90000090
        hand.ammo_type = 1
        hand.magazine = 7
        hand.reserve = 35
        hand.magazine_capacity = 7
        hand.action_state = 0
        hand.animation_id = 2
        hand.animation_frame_q16 = 2 * 65_536
        hand.animation_rate_q16 = 65_536
        hand.source_weapon_offset = 0x100
        hand.source_stats_offset = 0x300
        hand.source_transform_offset = 0x500
        hand.source_matrix_handle = 0x91000000
        hand.position_q16.0 = 0
        hand.position_q16.1 = -65_536
        hand.position_q16.2 = 0
        hand.scale_q16.0 = 65_536
        hand.scale_q16.1 = 65_536
        hand.scale_q16.2 = 65_536
        hand.muzzle_offset_q16.2 = 65_536
        hand.source_hash = 0x6000000000000001
        hand.resource_hash = 0x6100000000000001
        frame.hands.0 = hand

        var event = GERamRomWeaponEffectEventV6()
        event.header.abi_version = GE_NATIVE_ABI_VERSION
        event.header.struct_size = UInt32(MemoryLayout<GERamRomWeaponEffectEventV6>.size)
        event.record_version = 1
        event.category = 1
        event.flags = 1 | 2 | 4
        event.source_event_id = 101
        event.resource_handle = 0xa0001001
        event.source_resource_id = 0
        event.image_handle = 0xb0002085
        event.source_sfx_id = 301
        event.source_reference_tick = 1
        event.sequence = 1
        event.source_offset = 0x1040
        event.frame_index = 0
        event.frame_count = 6
        event.position_q16.0 = 1
        event.position_q16.1 = 2
        event.position_q16.2 = 3
        event.scale_q16.0 = 65_536
        event.scale_q16.1 = 65_536
        event.scale_q16.2 = 65_536
        event.alpha_q16 = 65_536
        event.lifetime_q16 = 65_536
        event.envelope_q16 = 65_536
        event.source_hash = 0x6200000000000001
        event.resource_hash = 0x6300000000000001
        frame.events.0 = event
        frame.frame_hash = ge_ramrom_weapon_effect_v6_hash_frame(&frame)

        let resources = GoldenEyeRamRomWeaponEffectResourceMapV6(
            sourceSymbolsByID: [:],
            resourceSymbolsByHandle: [
                0xb0002231: "IMAGE_2231_9MMAMMO",
                0xb0002236: "IMAGE_2236_CROSSHAIR1",
                0x90000052: "gun_82_watchcommunicator",
                0xa0001001: "IMAGE_2085_FIRE_0",
            ],
            imageDimensionsByHandle: [
                0xb0002236: (32, 32),
            ]
        )
        let frameValue = try GoldenEyeRamRomWeaponEffectOwnerAdapterV6.makeSourceFrame(
            frame, resources: resources, explicitlyInactive: [.sky]
        )
        precondition(frameValue.stageID == 33 && frameValue.demoID == 1)
        precondition(frameValue.hud?.imageSymbols.contains("IMAGE_2236_CROSSHAIR1") == true)
        precondition(frameValue.transientEvents.count == 1)
        precondition(frameValue.transientEvents[0].sourceSymbol == "gunfire_effect_dispatch")

        let bad = GoldenEyeRamRomWeaponEffectResourceMapV6(
            sourceSymbolsByID: [:], resourceSymbolsByHandle: [:], imageDimensionsByHandle: [:]
        )
        do {
            _ = try GoldenEyeRamRomWeaponEffectOwnerAdapterV6.makeSourceFrame(
                frame, resources: bad, explicitlyInactive: [.sky]
            )
            fatalError("missing source linkage unexpectedly accepted")
        } catch GoldenEyeRamRomWeaponEffectOwnerErrorV6.missingResourceSymbol {
            // Expected fail-closed boundary.
        }
        print("goldeneye_ramrom_weapon_effect_owner_v6_smoke: PASS adapter=1 fail-closed=1")
    }
}
