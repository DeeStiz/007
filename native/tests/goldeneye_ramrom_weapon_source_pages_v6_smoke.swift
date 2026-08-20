import Foundation

@main
struct GoldenEyeRamRomWeaponSourcePagesV6Smoke {
    static func main() throws {
        precondition(GoldenEyeRamRomSourceWeaponMappingV6.table.count == 89)
        precondition(GoldenEyeRamRomSourceWeaponMappingV6.sourceTableProvenance.count == 4)
        let emptyVisible = GoldenEyeRamRomVisibleDependencyCatalogV6(
            rootURL: URL(fileURLWithPath: "/tmp/source-pages"), dependencies: [], categoryNames: []
        )
        let missing = GoldenEyeRamRomSourceWeaponMappingV6.resolve(
            itemIDs: [4, 8, 19], stageName: "Dam", visibleDependencies: emptyVisible, models: [:]
        )
        precondition(!missing.isComplete)
        precondition(missing.missingFields.count >= 3)

        let resolved = GoldenEyeRamRomResolvedWeaponMappingV6(
            itemID: 4, sourceName: "wppk", sourceSymbol: "gun_90_wppk",
            modelName: "chrwppk", modelHandle: 0x9000_0090,
            sourceHash: 0x8100_0001
        )
        let source = GoldenEyeRamRomAuthoritativeWeaponSourceValuesV6(
            itemID: 4, flags: 0, actionState: 0, firingStatus: 0,
            animationID: 2, animationFrameQ16: 2 * 65_536,
            animationRateQ16: 65_536, magazine: 7, reserve: 35,
            positionQ16: [0, -65_536, 0], rotationQ16: [0, 0, 0],
            scaleQ16: [65_536, 65_536, 65_536], muzzleOffsetQ16: [0, 0, 65_536],
            sourceWeaponOffset: 0x100, sourceStatsOffset: 0x200,
            sourceTransformOffset: 0x300, sourceMatrixHandle: 0x9100_0000,
            sourceHash: 0x8200_0001, sourceFrame: 1
        )
        let map = try GoldenEyeRamRomWeaponSourcePageBuilderV6.makeMapRow(
            mapping: resolved, source: source, propModelID: 191, ammoType: 1,
            magazineCapacity: 7, resourceHandle: 0xa000_0090,
            imageHandle: 0xb000_2231, sourceSFXID: 42, resourceHash: 0x8300_0001
        )
        let page = try GoldenEyeRamRomWeaponSourcePageBuilderV6.makePage(source: source)
        var template = GERamRomWeaponEffectFrameV6()
        template.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        template.header.struct_size = UInt32(MemoryLayout<GERamRomWeaponEffectFrameV6>.size)
        template.record_version = UInt32(GE_WEAPON_EFFECT_OWNER_V6_RECORD_VERSION)
        template.flags = UInt32(GE_WEAPON_EFFECT_OWNER_V6_FRAME_SOURCE_ANCHOR)
        template.demo_id = 1; template.stage_id = 33; template.native_tick = 2
        template.reference_tick = 1; template.source_anchor = 1; template.source_frame = 2
        template.source_present_mask = UInt32(GE_WEAPON_EFFECT_OWNER_V6_CATEGORY_MASK)
        template.source_inactive_mask = 0
        template.crosshair_x_q16 = 220; template.crosshair_y_q16 = 165
        template.source_hash = 0x8400_0001; template.resource_hash = 0x8500_0001
        let output = try GoldenEyeRamRomWeaponSourcePageBuilderV6.buildFrame(
            demoID: 1, stageID: 33, nativeTick: 2,
            mapRows: [map], sourcePages: [page], events: [], visualTemplate: template
        )
        precondition(output.hands.0.model_handle == 0x9000_0090)
        precondition(output.hands.0.magazine == 7)
        precondition(output.frame_hash != 0)
        print("goldeneye_ramrom_weapon_source_pages_v6_smoke: PASS table=89 missing=3 frame-hash=1")
    }
}
