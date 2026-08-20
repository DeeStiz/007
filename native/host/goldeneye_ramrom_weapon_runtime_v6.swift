import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

struct GoldenEyeRamRomWeaponIntroStateV6: Sendable, Equatable {
    let demoSlot: UInt32
    let itemRight: UInt32
    let itemLeft: UInt32?
    let ammoByType: [UInt32: UInt32]
    let sourceHash: UInt64
}

struct GoldenEyeRamRomWeaponRuntimeMissingV6: Sendable, Equatable {
    let demoID: UInt8
    let stageID: UInt32
    let fields: [String]
}

struct GoldenEyeRamRomWeaponRuntimeReadinessV6: Sendable, Equatable {
    let demoID: UInt8
    let stageID: UInt32
    let fields: [String]

    var isReady: Bool { fields.isEmpty }
}

enum GoldenEyeRamRomWeaponRuntimeErrorV6: Error, Sendable, Equatable, CustomStringConvertible {
    case malformedIntro(String)
    case missingSource(String)
    case routeMismatch
    case pageBuilder(GoldenEyeRamRomWeaponSourcePageBuilderErrorV6)

    var description: String {
        switch self {
        case let .malformedIntro(value): return "weapon runtime INTRO is malformed: \(value)"
        case let .missingSource(value): return "weapon runtime source is missing: \(value)"
        case .routeMismatch: return "weapon runtime route mismatch"
        case let .pageBuilder(error): return "weapon runtime page builder failed: \(error)"
        }
    }
}

/// Direct source `bondview_r.c` INTRO parser.  It consumes only the prepared
/// setup payload supplied by the stage owner and preserves the source record
/// sizes/type ordering. It does not search for a model or assign a default.
enum GoldenEyeRamRomWeaponIntroParserV6 {
    static func parse(
        setupPayload: Data,
        setup: GoldenEyeStageSetupPacket,
        demoSlot: UInt32
    ) throws -> GoldenEyeRamRomWeaponIntroStateV6 {
        guard let section = setup.sections.first(where: { $0.index == 2 }) else {
            throw GoldenEyeRamRomWeaponRuntimeErrorV6.malformedIntro("INTRO section missing")
        }
        let start = Int(section.sourceOffset)
        let end = start + Int(section.sourceBytes)
        guard start >= 0, end <= setupPayload.count else {
            throw GoldenEyeRamRomWeaponRuntimeErrorV6.malformedIntro("INTRO bounds")
        }
        // SetupIntroSpawn/Item/Ammo/Swirl/Anim/Cuff/Camera/Watch/Credits.
        let sizes = [3, 4, 4, 8, 2, 2, 10, 3, 1, 1]
        var offset = start
        var right: UInt32?
        var left: UInt32?
        var ammo: [UInt32: UInt32] = [:]
        var hash: UInt64 = 1_469_598_103_934_665_603
        while offset + 4 <= end {
            guard let rawType = be32(setupPayload, offset), rawType < UInt32(sizes.count) else {
                throw GoldenEyeRamRomWeaponRuntimeErrorV6.malformedIntro("type at \(offset)")
            }
            let type = Int(rawType)
            let words = sizes[type]
            guard offset + words * 4 <= end else {
                throw GoldenEyeRamRomWeaponRuntimeErrorV6.malformedIntro("record bounds at \(offset)")
            }
            hash = mix(hash, UInt64(rawType)); hash = mix(hash, UInt64(offset))
            if type == 1 {
                guard let itemRight = beS32(setupPayload, offset + 4),
                      let itemLeft = beS32(setupPayload, offset + 8),
                      let slot = beS32(setupPayload, offset + 12) else {
                    throw GoldenEyeRamRomWeaponRuntimeErrorV6.malformedIntro("item record at \(offset)")
                }
                if UInt32(bitPattern: slot) == demoSlot, right == nil {
                    guard itemRight >= 0 else {
                        throw GoldenEyeRamRomWeaponRuntimeErrorV6.malformedIntro("negative starting item")
                    }
                    right = UInt32(itemRight)
                    left = itemLeft >= 0 ? UInt32(itemLeft) : nil
                }
            } else if type == 2 {
                guard let ammoType = beS32(setupPayload, offset + 4),
                      let amount = beS32(setupPayload, offset + 8),
                      let slot = beS32(setupPayload, offset + 12) else {
                    throw GoldenEyeRamRomWeaponRuntimeErrorV6.malformedIntro("ammo record at \(offset)")
                }
                if UInt32(bitPattern: slot) == demoSlot, ammoType >= 0, amount >= 0 {
                    ammo[UInt32(ammoType), default: 0] &+= UInt32(amount)
                }
            }
            offset += words * 4
            if type == 9 { break }
        }
        guard offset <= end else {
            throw GoldenEyeRamRomWeaponRuntimeErrorV6.malformedIntro("INTRO terminator")
        }
        guard let right else {
            throw GoldenEyeRamRomWeaponRuntimeErrorV6.missingSource("INTRO item for slot \(demoSlot)")
        }
        return GoldenEyeRamRomWeaponIntroStateV6(
            demoSlot: demoSlot, itemRight: right, itemLeft: left,
            ammoByType: ammo, sourceHash: hash == 0 ? 1 : hash
        )
    }

    private static func be16(_ data: Data, _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 |
            UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
    }

    private static func beS32(_ data: Data, _ offset: Int) -> Int32? {
        be32(data, offset).map { Int32(bitPattern: $0) }
    }

    private static func mix(_ hash: UInt64, _ value: UInt64) -> UInt64 {
        (hash ^ value) &* 1_099_511_628_211
    }
}

extension GoldenEyeRamRomWeaponRuntimeV6 {
    static func readiness(
        demoID: UInt8,
        stageID: UInt32,
        intro: GoldenEyeRamRomWeaponIntroStateV6,
        mapping: GoldenEyeRamRomSourceWeaponMappingResultV6,
        sourcePageAvailable: Bool,
        eventTemplatesPresent: Bool,
        resourceCatalogComplete: Bool
    ) -> GoldenEyeRamRomWeaponRuntimeReadinessV6 {
        var fields = Set(mapping.missingFields)
        if !mapping.rows.contains(where: { $0.itemID == intro.itemRight }) {
            fields.insert("item:\(intro.itemRight).resolved_model_handle")
        }
        if !sourcePageAvailable {
            fields.insert("item:\(intro.itemRight).source_weapon_page.transforms_offsets")
        }
        if !eventTemplatesPresent {
            fields.insert("effects.source_event_templates")
        }
        if !resourceCatalogComplete {
            fields.insert("weapon_effect_resource_catalog")
        }
        return .init(demoID: demoID, stageID: stageID, fields: fields.sorted())
    }
}

/// Source-page runtime for the exercised first-person weapon path. The
/// source producer supplies exact hand transforms and event templates; this
/// owner applies only source input fire/ammo cadence at even anchors. Odd
/// ticks return nil so the C owner publishes its declared interpolation.
struct GoldenEyeRamRomWeaponRuntimeV6: Sendable {
    let demoID: UInt8
    let stageID: UInt32
    let intro: GoldenEyeRamRomWeaponIntroStateV6
    let mapping: GoldenEyeRamRomSourceWeaponMappingResultV6
    let mapRows: [GERamRomWeaponSourceMapRowV6]
    private(set) var nativeTick: UInt64
    private(set) var sourceFrame: UInt32
    private(set) var magazine: UInt32
    private(set) var oneShotSequence: UInt32
    private(set) var lastFrameHash: UInt64

    init(
        demoID: UInt8,
        stageID: UInt32,
        intro: GoldenEyeRamRomWeaponIntroStateV6,
        mapping: GoldenEyeRamRomSourceWeaponMappingResultV6,
        mapRows: [GERamRomWeaponSourceMapRowV6]
    ) throws {
        guard mapping.rows.contains(where: { $0.itemID == intro.itemRight }),
              mapRows.contains(where: { $0.item_id == intro.itemRight }) else {
            throw GoldenEyeRamRomWeaponRuntimeErrorV6.missingSource("resolved mapping item \(intro.itemRight)")
        }
        guard mapping.missingFields.isEmpty else {
            throw GoldenEyeRamRomWeaponRuntimeErrorV6.missingSource(mapping.missingFields.joined(separator: ","))
        }
        self.demoID = demoID; self.stageID = stageID; self.intro = intro
        self.mapping = mapping; self.mapRows = mapRows
        nativeTick = UInt64.max; sourceFrame = 0; magazine = 0; oneShotSequence = 0; lastFrameHash = 0
    }

    mutating func begin(
        source: GoldenEyeRamRomAuthoritativeWeaponSourceValuesV6,
        visualTemplate: GERamRomWeaponEffectFrameV6,
        eventTemplates: [GERamRomWeaponEffectEventV6]
    ) throws -> GERamRomWeaponEffectFrameV6 {
        guard source.itemID == intro.itemRight else {
            throw GoldenEyeRamRomWeaponRuntimeErrorV6.routeMismatch
        }
        magazine = source.magazine; sourceFrame = 1; nativeTick = 0; oneShotSequence = 0
        let page = try GoldenEyeRamRomWeaponSourcePageBuilderV6.makePage(source: source)
        var template = visualTemplate
        template.source_frame = sourceFrame
        template.one_shot_sequence = oneShotSequence
        template.right_magazine = magazine
        var events = eventTemplates
        for index in events.indices {
            events[index].source_reference_tick = 0
            events[index].flags |= UInt32(GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR_FLAG)
        }
        return try GoldenEyeRamRomWeaponSourcePageBuilderV6.buildFrame(
            demoID: UInt32(demoID), stageID: stageID, nativeTick: 0,
            mapRows: mapRows, sourcePages: [page], events: events,
            visualTemplate: template
        )
    }

    mutating func step(
        nativeTick: UInt64,
        input: GERamRomGameplayInputV6,
        source: GoldenEyeRamRomAuthoritativeWeaponSourceValuesV6,
        visualTemplate: GERamRomWeaponEffectFrameV6,
        eventTemplates: [GERamRomWeaponEffectEventV6]
    ) throws -> GERamRomWeaponEffectFrameV6? {
        guard nativeTick == self.nativeTick + 1 else {
            throw GoldenEyeRamRomWeaponRuntimeErrorV6.routeMismatch
        }
        guard nativeTick & 1 == 0 else {
            self.nativeTick = nativeTick
            return nil
        }
        guard source.itemID == intro.itemRight else {
            throw GoldenEyeRamRomWeaponRuntimeErrorV6.routeMismatch
        }
        var sourceValue = source
        let fired = (input.pressed_buttons | input.held_buttons) & 0x2000 != 0 && magazine > 0
        if fired {
            magazine -= 1
            sourceValue = GoldenEyeRamRomAuthoritativeWeaponSourceValuesV6(
                itemID: source.itemID, flags: source.flags, actionState: source.actionState,
                firingStatus: 1, animationID: source.animationID,
                animationFrameQ16: source.animationFrameQ16, animationRateQ16: source.animationRateQ16,
                magazine: magazine, reserve: source.reserve,
                positionQ16: source.positionQ16, rotationQ16: source.rotationQ16,
                scaleQ16: source.scaleQ16, muzzleOffsetQ16: source.muzzleOffsetQ16,
                sourceWeaponOffset: source.sourceWeaponOffset, sourceStatsOffset: source.sourceStatsOffset,
                sourceTransformOffset: source.sourceTransformOffset, sourceMatrixHandle: source.sourceMatrixHandle,
                sourceHash: source.sourceHash, sourceFrame: source.sourceFrame
            )
            oneShotSequence &+= 1
        } else {
            sourceValue = GoldenEyeRamRomAuthoritativeWeaponSourceValuesV6(
                itemID: source.itemID, flags: source.flags, actionState: source.actionState,
                firingStatus: 0, animationID: source.animationID,
                animationFrameQ16: source.animationFrameQ16, animationRateQ16: source.animationRateQ16,
                magazine: magazine, reserve: source.reserve,
                positionQ16: source.positionQ16, rotationQ16: source.rotationQ16,
                scaleQ16: source.scaleQ16, muzzleOffsetQ16: source.muzzleOffsetQ16,
                sourceWeaponOffset: source.sourceWeaponOffset, sourceStatsOffset: source.sourceStatsOffset,
                sourceTransformOffset: source.sourceTransformOffset, sourceMatrixHandle: source.sourceMatrixHandle,
                sourceHash: source.sourceHash, sourceFrame: source.sourceFrame
            )
        }
        sourceFrame &+= 1
        self.nativeTick = nativeTick
        let page = try GoldenEyeRamRomWeaponSourcePageBuilderV6.makePage(source: sourceValue)
        var template = visualTemplate
        template.source_frame = sourceFrame
        template.one_shot_sequence = oneShotSequence
        template.right_magazine = magazine
        var events = fired ? eventTemplates : []
        for index in events.indices {
            events[index].source_reference_tick = nativeTick >> 1
            events[index].flags |= UInt32(GE_WEAPON_EFFECT_OWNER_V6_EVENT_SOURCE_ANCHOR_FLAG)
        }
        let frame = try GoldenEyeRamRomWeaponSourcePageBuilderV6.buildFrame(
            demoID: UInt32(demoID), stageID: stageID, nativeTick: nativeTick,
            mapRows: mapRows, sourcePages: [page], events: events,
            visualTemplate: template
        )
        lastFrameHash = frame.frame_hash
        return frame
    }
}
