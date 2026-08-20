import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

struct GoldenEyeRamRomAuthoritativeWeaponSourceValuesV6: Sendable, Equatable {
    let itemID: UInt32
    let flags: UInt32
    let actionState: UInt32
    let firingStatus: UInt32
    let animationID: UInt32
    let animationFrameQ16: Int32
    let animationRateQ16: Int32
    let magazine: UInt32
    let reserve: UInt32
    let positionQ16: [Int32]
    let rotationQ16: [Int32]
    let scaleQ16: [Int32]
    let muzzleOffsetQ16: [Int32]
    let sourceWeaponOffset: UInt32
    let sourceStatsOffset: UInt32
    let sourceTransformOffset: UInt32
    let sourceMatrixHandle: UInt32
    let sourceHash: UInt64
    let sourceFrame: UInt32

    var isRepresentable: Bool {
        positionQ16.count == 3 && rotationQ16.count == 3 &&
            scaleQ16.count == 3 && muzzleOffsetQ16.count == 3 &&
            scaleQ16.allSatisfy { $0 > 0 } && sourceHash != 0
    }
}

enum GoldenEyeRamRomWeaponSourcePageBuilderErrorV6: Error, Sendable, Equatable, CustomStringConvertible {
    case missingMapping(UInt32)
    case invalidSourceValues(UInt32)
    case cStatus(UInt32)

    var description: String {
        switch self {
        case let .missingMapping(item): return "weapon source page mapping is missing for item \(item)"
        case let .invalidSourceValues(item): return "weapon source values are incomplete for item \(item)"
        case let .cStatus(status): return "weapon source page builder status \(status)"
        }
    }
}

/// Swift owner-thread bridge for the C source-page builder. Every value that
/// enters a page is supplied by the directly compiled source producer; this
/// adapter contributes only guarded model handles and C layout copying.
enum GoldenEyeRamRomWeaponSourcePageBuilderV6 {
    static func makeMapRow(
        mapping: GoldenEyeRamRomResolvedWeaponMappingV6,
        source: GoldenEyeRamRomAuthoritativeWeaponSourceValuesV6,
        propModelID: UInt32 = UInt32.max,
        ammoType: UInt32 = UInt32.max,
        magazineCapacity: UInt32 = UInt32.max,
        resourceHandle: UInt32,
        imageHandle: UInt32,
        sourceSFXID: UInt32,
        resourceHash: UInt64
    ) throws -> GERamRomWeaponSourceMapRowV6 {
        guard source.itemID == mapping.itemID, source.isRepresentable,
              resourceHandle != 0, resourceHash != 0 else {
            throw GoldenEyeRamRomWeaponSourcePageBuilderErrorV6.invalidSourceValues(source.itemID)
        }
        var row = GERamRomWeaponSourceMapRowV6()
        row.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        row.header.struct_size = UInt32(MemoryLayout<GERamRomWeaponSourceMapRowV6>.size)
        row.record_version = UInt32(GE_RAMROM_WEAPON_SOURCE_PAGES_V6_RECORD_VERSION)
        row.item_id = mapping.itemID
        row.prop_model_id = propModelID
        row.model_handle = mapping.modelHandle
        row.ammo_type = ammoType
        row.magazine_capacity = magazineCapacity
        row.source_weapon_offset = source.sourceWeaponOffset
        row.source_stats_offset = source.sourceStatsOffset
        row.source_transform_offset = source.sourceTransformOffset
        row.source_matrix_handle = source.sourceMatrixHandle
        row.resource_handle = resourceHandle
        row.image_handle = imageHandle
        row.source_sfx_id = sourceSFXID
        row.source_hash = source.sourceHash
        row.resource_hash = resourceHash
        row.flags = 0
        return row
    }

    static func makePage(
        source: GoldenEyeRamRomAuthoritativeWeaponSourceValuesV6
    ) throws -> GERamRomWeaponSourcePageV6 {
        guard source.isRepresentable else {
            throw GoldenEyeRamRomWeaponSourcePageBuilderErrorV6.invalidSourceValues(source.itemID)
        }
        var page = GERamRomWeaponSourcePageV6()
        page.header.abi_version = UInt32(GE_NATIVE_ABI_VERSION)
        page.header.struct_size = UInt32(MemoryLayout<GERamRomWeaponSourcePageV6>.size)
        page.record_version = UInt32(GE_RAMROM_WEAPON_SOURCE_PAGES_V6_RECORD_VERSION)
        page.item_id = source.itemID; page.flags = source.flags
        page.action_state = source.actionState; page.firing_status = source.firingStatus
        page.animation_id = source.animationID; page.animation_frame_q16 = source.animationFrameQ16
        page.animation_rate_q16 = source.animationRateQ16; page.magazine = source.magazine
        page.reserve = source.reserve
        Self.setTuple(&page.position_q16, values: source.positionQ16)
        Self.setTuple(&page.rotation_q16, values: source.rotationQ16)
        Self.setTuple(&page.scale_q16, values: source.scaleQ16)
        Self.setTuple(&page.muzzle_offset_q16, values: source.muzzleOffsetQ16)
        page.source_weapon_offset = source.sourceWeaponOffset
        page.source_stats_offset = source.sourceStatsOffset
        page.source_transform_offset = source.sourceTransformOffset
        page.source_matrix_handle = source.sourceMatrixHandle
        page.source_hash = source.sourceHash; page.source_frame = source.sourceFrame
        return page
    }

    static func buildFrame(
        demoID: UInt32,
        stageID: UInt32,
        nativeTick: UInt64,
        mapRows: [GERamRomWeaponSourceMapRowV6],
        sourcePages: [GERamRomWeaponSourcePageV6],
        events: [GERamRomWeaponEffectEventV6],
        visualTemplate: GERamRomWeaponEffectFrameV6
    ) throws -> GERamRomWeaponEffectFrameV6 {
        var template = visualTemplate
        var output = GERamRomWeaponEffectFrameV6()
        let status: UInt32 = mapRows.withUnsafeBufferPointer { maps in
            sourcePages.withUnsafeBufferPointer { pages in
                events.withUnsafeBufferPointer { eventBuffer in
                    ge_ramrom_weapon_source_pages_v6_build_frame(
                        demoID, stageID, nativeTick,
                        maps.baseAddress, UInt32(maps.count),
                        pages.baseAddress, UInt32(pages.count),
                        eventBuffer.baseAddress, UInt32(eventBuffer.count),
                        &template, &output
                    )
                }
            }
        }
        guard status == UInt32(GE_STATUS_OK) else {
            throw GoldenEyeRamRomWeaponSourcePageBuilderErrorV6.cStatus(status)
        }
        return output
    }

    private static func setTuple<T>(_ destination: inout T, values: [Int32]) {
        withUnsafeMutableBytes(of: &destination) { raw in
            let typed = raw.bindMemory(to: Int32.self)
            for index in values.indices where index < typed.count { typed[index] = values[index] }
        }
    }
}
