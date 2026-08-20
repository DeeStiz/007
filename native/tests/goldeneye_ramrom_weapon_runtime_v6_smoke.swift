import Foundation

@main
struct GoldenEyeRamRomWeaponRuntimeV6Smoke {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("usage: goldeneye_ramrom_weapon_runtime_v6_smoke stage-assets visible-assets")
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let visibleRoot = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let weaponAssets = try GoldenEyeRamRomWeaponAssetCatalogV6.load(rootURL: visibleRoot)
        precondition(weaponAssets.isComplete)
        precondition(weaponAssets.asset(category: "weapons", symbol: "gun_90_wppk") != nil)
        precondition(weaponAssets.asset(category: "particles", symbol: "IMAGE_2084_SMOKE_0") != nil)
        precondition(weaponAssets.asset(category: "explosions", symbol: "IMAGE_2170_IMPACT3") != nil)
        precondition(weaponAssets.asset(category: "glass", symbol: "prop_104_window") != nil)
        let catalog = try GoldenEyeStageAssetCatalog.load(stageAssetRoot: root)
        let packets = try GoldenEyeStageScenePacket.loadAll(catalog: catalog)
        let sidecars = try GoldenEyeStageModelSidecarCatalogV6.load(stageAssetRoot: root)
        var weaponModels: [String: GoldenEyeSourceModelV6] = [:]
        for row in GoldenEyeRamRomSourceWeaponMappingV6.table {
            guard let alias = row.modelAlias else { continue }
            if let match = sidecars.models.first(where: { $0.key.hasSuffix("_\(alias)") }) {
                weaponModels[alias] = match.value
            }
        }
        let visibleDependencies = try GoldenEyeRamRomVisibleDependencyCatalogV6.load(rootURL: visibleRoot)
        let routeSlots: [(UInt8, UInt32, UInt32)] = [
            (1, 33, 1), (2, 33, 0), (3, 34, 1), (4, 34, 2), (5, 34, 3),
            (6, 35, 1), (7, 35, 2), (8, 9, 0), (9, 9, 2),
            (10, 20, 1), (11, 20, 2), (12, 26, 1), (13, 26, 1), (14, 25, 0)
        ]
        var parsed = 0
        var readinessRows = 0
        var hashes: [UInt8: UInt64] = [:]
        for (demoID, stageID, slot) in routeSlots {
            guard let stage = packets.first(where: { $0.stageID == stageID }),
                  let resource = stage.resources.first(where: { $0.kind == .setup }) else {
                fatalError("missing setup stage (stageID)")
            }
            let first = try GoldenEyeRamRomWeaponIntroParserV6.parse(
                setupPayload: resource.payload, setup: stage.setup, demoSlot: slot
            )
            let second = try GoldenEyeRamRomWeaponIntroParserV6.parse(
                setupPayload: resource.payload, setup: stage.setup, demoSlot: slot
            )
            precondition(first == second)
            let mapping = GoldenEyeRamRomSourceWeaponMappingV6.resolveExact(
                itemIDs: [first.itemRight], stageName: stage.stageName,
                visibleDependencies: visibleDependencies,
                models: weaponModels,
                weaponAssets: weaponAssets
            )
            let readiness = GoldenEyeRamRomWeaponRuntimeV6.readiness(
                demoID: demoID, stageID: stageID, intro: first, mapping: mapping,
                sourcePageAvailable: false, eventTemplatesPresent: false,
                resourceCatalogComplete: weaponAssets.isComplete
            )
            precondition(!readiness.isReady)
            precondition(readiness.fields.contains(where: { $0.contains("source_weapon_page") }))
            if first.itemRight == 4 || first.itemRight == 8 {
                // The stage sidecar names are useful candidates, but their
                // source hashes belong to prop/chr*. Model.c rather than the
                // corresponding gun/*/Model.c payload. Exact resolution must
                // therefore retain the source-model hash blocker.
                precondition(readiness.fields.contains(where: { $0.contains("model_source_hash") }))
            }
            print("readiness demo=\(demoID) stage=\(stageID) missing=\(readiness.fields.joined(separator: ";"))")
            readinessRows += 1
            hashes[demoID] = first.sourceHash
            parsed += 1
        }
        precondition(parsed == 14 && hashes.count == 14 && readinessRows == 14)

        let emptyMapping = GoldenEyeRamRomSourceWeaponMappingResultV6(
            stageName: "Dam", rows: [], missingFields: ["model_mapping"],
            sourceTableHash: 1, mappingHash: 2
        )
        let intro = GoldenEyeRamRomWeaponIntroStateV6(
            demoSlot: 1, itemRight: 4, itemLeft: nil, ammoByType: [:], sourceHash: 3
        )
        do {
            _ = try GoldenEyeRamRomWeaponRuntimeV6(
                demoID: 1, stageID: 33, intro: intro,
                mapping: emptyMapping, mapRows: []
            )
            fatalError("runtime accepted missing source mapping")
        } catch GoldenEyeRamRomWeaponRuntimeErrorV6.missingSource {
            // Expected: production readiness remains false until the guarded
            // prepared model/resource mapping is present.
        }
        print("goldeneye_ramrom_weapon_runtime_v6_smoke: PASS routes=14 parse-twice=14 readiness-matrix=14 mapping-fail-closed=1")
    }
}
