import Foundation

/// Checked-in source table identity for ITEM_IDS/gitem_structs.  The order is
/// the order of the original ITEM_IDS enum and gunModelFileRecord table; it is
/// not a runtime fallback list.  A row is renderable only after a guarded
/// prepared GESM model and visible-dependency symbol resolve for the current
/// stage/demo.
struct GoldenEyeRamRomSourceWeaponTableRowV6: Sendable, Equatable {
    let itemID: UInt32
    let sourceName: String
    let modelAlias: String?
    let sourceTableIndex: UInt32?
}

struct GoldenEyeRamRomResolvedWeaponMappingV6: Sendable, Equatable {
    let itemID: UInt32
    let sourceName: String
    let sourceSymbol: String
    let modelName: String
    let modelHandle: UInt32
    let sourceHash: UInt64
}

struct GoldenEyeRamRomSourceWeaponMappingResultV6: Sendable, Equatable {
    let stageName: String
    let rows: [GoldenEyeRamRomResolvedWeaponMappingV6]
    let missingFields: [String]
    let sourceTableHash: UInt64
    let mappingHash: UInt64

    var isComplete: Bool { missingFields.isEmpty && !rows.isEmpty }
}

enum GoldenEyeRamRomSourceWeaponMappingErrorV6: Error, Sendable, Equatable, CustomStringConvertible {
    case unknownItem(UInt32)
    case missingSourceRow(UInt32)
    case missingModel(UInt32, String)

    var description: String {
        switch self {
        case let .unknownItem(item): return "source weapon item \(item) is not in ITEM_IDS table"
        case let .missingSourceRow(item): return "source weapon item \(item) has no visible source-gun row"
        case let .missingModel(item, name): return "source weapon item \(item) model \(name) is not prepared"
        }
    }
}

/// Maps checked-in source item IDs to prepared GESM model handles.  It never
/// derives a handle from an item number, model name spelling, or a missing
/// dependency row.  The incomplete rows are retained in `missingFields` so
/// all fourteen routes can be audited without promoting a guessed weapon.
enum GoldenEyeRamRomSourceWeaponMappingV6 {
    static let sourceTableProvenance = [
        "src/bondconstants.h": "49b021c08523a337ff51e4f8a2c715dcf2b2414deae5da7f9eb7593be543fce3",
        "assets/obseg/gun/gunModelFileRecord.inc.c": "d40734be8be3eba4526c3c1f4df32e8d6f1cb278acd9a3376040fa595ab99f18",
        "src/game/gun.c": "a4d4310941ae5794703068960f8561ca0230d25184aa7f1fd299210774c8de9c",
        "src/game/gunfire.c": "801b77b16bb9ad96c8b8d694f567e30d063476d998aa8774c025471b4c7c357a"
    ]

    /// ITEM_UNARMED through ITEM_TOKEN (ITEM_IDS_MAX excluded).  The 32nd
    /// row is the explicit source TANKSHELLS record between trigger/taser and
    /// bombcase in gunModelFileRecord.inc.c.
    static let table: [GoldenEyeRamRomSourceWeaponTableRowV6] = {
        let names = [
            "unarmed", "fist", "knife", "throwknife", "wppk", "wppksil", "tt33", "skorpion", "ak47", "uzi",
            "mp5k", "mp5ksil", "spectre", "m16", "fnp90", "shotgun", "autoshot", "sniperrifle", "ruger", "goldengun",
            "silverwppk", "goldwppk", "laser", "watchlaser", "grenadelaunch", "rocketlaunch", "grenade", "timedmine", "proximitymine", "remotemine",
            "trigger", "taser", "tankshells", "bombcase", "plastique", "flarepistol", "pitongun", "bungee", "doordecoder", "bombdefuser",
            "camera", "lockexploder", "doorexploder", "briefcase", "weaponcase", "safecrackercase", "keyanalysercase", "bug", "microcamera", "bugdetector",
            "explosivefloppy", "polarizedglasses", "darkglasses", "creditcard", "gaskeyring", "datathief", "watchidentifier", "watchcommunicator", "watchgeigercounter", "watchmagnetrepel",
            "watchmagnetattract", "goldeneyekey", "blackbox", "circuitboard", "clipboard", "stafflist", "dossierred", "plans", "spyfile", "blueprints",
            "map", "audiotape", "videotape", "dattape", "spooltape", "microfilm", "microcode", "lectre", "money", "goldbar",
            "heroin", "keycard", "keyyale", "keybolt", "suit_lf_hand", "joypad", "rocketround", "grenaderound", "token"
        ]
        let modelAliases: [String: String] = [
            "wppk": "chrwppk", "wppksil": "chrwppksil", "tt33": "chrtt33",
            "skorpion": "chrskorpion", "ak47": "chrkalash", "uzi": "chruzi",
            "autoshot": "chrautshot", "sniperrifle": "chrsniperrifle", "ruger": "chrruger",
            "goldengun": "chrgolden", "laser": "chrlaser", "grenadelaunch": "chrgrenadelaunch"
        ]
        return names.enumerated().map { index, name in
            GoldenEyeRamRomSourceWeaponTableRowV6(
                itemID: UInt32(index), sourceName: name,
                modelAlias: modelAliases[name], sourceTableIndex: nil
            )
        }
    }()

    static func row(itemID: UInt32) -> GoldenEyeRamRomSourceWeaponTableRowV6? {
        table.first { $0.itemID == itemID }
    }

    static func resolve(
        itemIDs: [UInt32],
        stageName: String,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6,
        models: [String: GoldenEyeSourceModelV6]
    ) -> GoldenEyeRamRomSourceWeaponMappingResultV6 {
        var resolved: [GoldenEyeRamRomResolvedWeaponMappingV6] = []
        var missing: Set<String> = []
        let uniqueItems = Array(Set(itemIDs)).sorted()
        for itemID in uniqueItems {
            guard let row = row(itemID: itemID) else {
                missing.insert("item:\(itemID).ITEM_IDS")
                continue
            }
            guard let alias = row.modelAlias else {
                missing.insert("item:\(itemID).source_item_to_render_model")
                continue
            }
            guard let model = models[alias] else {
                missing.insert("item:\(itemID).model:\(alias)")
                continue
            }
            let sourceRows = visibleDependencies.dependencies.filter {
                ($0.category == "weapons" || $0.category == "projectiles" || $0.category == "watch") &&
                    $0.stages.contains(stageName) &&
                    ($0.symbol == alias || $0.symbol.hasSuffix("_\(row.sourceName)"))
            }
            guard let sourceRow = sourceRows.sorted(by: { $0.symbol < $1.symbol }).first else {
                missing.insert("item:\(itemID).visible_source_row:\(row.sourceName)")
                continue
            }
            var hash = UInt64(1_469_598_103_934_665_603)
            for value in [UInt64(itemID), UInt64(model.header.modelHandle), UInt64(sourceRow.modelIndex ?? 0)] {
                hash = (hash ^ value) &* 1_099_511_628_211
            }
            resolved.append(.init(
                itemID: itemID, sourceName: row.sourceName, sourceSymbol: sourceRow.symbol,
                modelName: alias, modelHandle: model.header.modelHandle,
                sourceHash: hash
            ))
        }
        var tableHash = UInt64(1_469_598_103_934_665_603)
        for row in table {
            tableHash = (tableHash ^ UInt64(row.itemID)) &* 1_099_511_628_211
            tableHash = (tableHash ^ row.sourceName.utf8.reduce(0) { ($0 &* 31) &+ UInt64($1) }) &* 1_099_511_628_211
        }
        var mappingHash = tableHash
        for row in resolved {
            mappingHash = (mappingHash ^ UInt64(row.itemID)) &* 1_099_511_628_211
            mappingHash = (mappingHash ^ UInt64(row.modelHandle)) &* 1_099_511_628_211
            mappingHash = (mappingHash ^ row.sourceHash) &* 1_099_511_628_211
        }
        return .init(
            stageName: stageName, rows: resolved,
            missingFields: missing.sorted(), sourceTableHash: tableHash,
            mappingHash: mappingHash == 0 ? 1 : mappingHash
        )
    }

    /// Resolve a weapon only when the prepared model is the exact source
    /// model named by the visible weapon row.  The older `resolve` method is
    /// retained as a diagnostic candidate lookup: it is useful for showing
    /// which alias and visible row were found, but a suffix match alone is
    /// not sufficient for a first-person weapon.  In particular, stage prop
    /// and cast sidecars such as `chrkalash` can have the same display name
    /// while representing a different `assets/obseg/gun/*/Model.c` source.
    ///
    /// The asset catalog carries the prepared source digest.  Comparing it
    /// to the GESM header digest is the only permitted model/resource join;
    /// no model handle is derived from an item number or a filename.
    static func resolveExact(
        itemIDs: [UInt32],
        stageName: String,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6,
        models: [String: GoldenEyeSourceModelV6],
        weaponAssets: GoldenEyeRamRomWeaponAssetCatalogV6
    ) -> GoldenEyeRamRomSourceWeaponMappingResultV6 {
        let candidate = resolve(
            itemIDs: itemIDs, stageName: stageName,
            visibleDependencies: visibleDependencies, models: models
        )
        var rows: [GoldenEyeRamRomResolvedWeaponMappingV6] = []
        var missing = Set(candidate.missingFields)
        for row in candidate.rows {
            guard let asset = weaponAssets.assets(symbol: row.sourceSymbol).first else {
                missing.insert("item:\(row.itemID).source_weapon_payload")
                continue
            }
            guard let model = models[row.modelName] else {
                missing.insert("item:\(row.itemID).resolved_model_handle")
                continue
            }
            let modelSourceHash = model.header.sourceHash
                .map { String(format: "%02x", $0) }.joined()
            guard modelSourceHash == asset.sourceSHA256.lowercased() else {
                missing.insert("item:\(row.itemID).model_source_hash")
                continue
            }
            rows.append(row)
        }

        var mappingHash = candidate.mappingHash
        for row in rows {
            mappingHash = (mappingHash ^ UInt64(row.modelHandle)) &* 1_099_511_628_211
            if let asset = weaponAssets.assets(symbol: row.sourceSymbol).first {
                mappingHash = (mappingHash ^ UInt64(asset.resourceHandle)) &* 1_099_511_628_211
                mappingHash = (mappingHash ^ UInt64(asset.decodedBytes)) &* 1_099_511_628_211
            }
        }
        return .init(
            stageName: candidate.stageName, rows: rows,
            missingFields: missing.sorted(),
            sourceTableHash: candidate.sourceTableHash,
            mappingHash: mappingHash == 0 ? 1 : mappingHash
        )
    }
}
