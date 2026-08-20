import Foundation

/// Source setup-to-model placement records. This is the bounded bridge before
/// a model's GESM graph is lowered into stage draw commands. A placement is
/// never considered renderable unless its source sidecar and transform are
/// both complete; missing guard pad transforms remain explicit failures.
struct GoldenEyeStageModelPlacementV6: Sendable, Equatable {
    let stageID: UInt32
    let objectIndex: UInt32
    let objectType: UInt32
    let modelIndex: UInt32
    let kind: String
    let modelName: String
    let matrixWords: [UInt32]
    let matrixQ16: [Int32]
    let sidecarReady: Bool

    var transformReady: Bool { matrixQ16.count == 16 }
    var isRenderable: Bool { sidecarReady && transformReady }
}

struct GoldenEyeStageModelPlacementCatalogV6: Sendable, Equatable {
    let placements: [GoldenEyeStageModelPlacementV6]

    var readyCount: Int { placements.reduce(into: 0) { if $1.isRenderable { $0 += 1 } } }
    var unsupportedCount: Int { placements.count - readyCount }

    static func make(
        stageID: UInt32,
        setup: GoldenEyeStageSetupPacket,
        dependencies: GoldenEyeStageSetupDependencyCatalogV6,
        sidecars: GoldenEyeStageModelSidecarCatalogV6,
        visibleDependencies: GoldenEyeRamRomVisibleDependencyCatalogV6? = nil
    ) -> Self {
        let stageName: String? = {
            switch stageID {
            case 33: return "Dam"
            case 34: return "Facility"
            case 35: return "Runway"
            case 9: return "Bunker I"
            case 20: return "Silo"
            case 26: return "Frigate"
            case 25: return "Train"
            default: return nil
            }
        }()
        let placements = setup.objects.compactMap { object -> GoldenEyeStageModelPlacementV6? in
            let kind: String
            switch object.type {
            case 1, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 17, 20, 21, 36, 39, 40, 41, 42, 43, 45, 47:
                kind = "prop"
            case 9:
                kind = "character"
            default:
                return nil
            }
            let modelIndex = object.key0
            if let visibleDependencies {
                let category = kind == "prop" ? "props" : "guards"
                guard visibleDependencies.dependencies.contains(where: {
                    $0.category == category && $0.modelIndex == modelIndex
                        && (stageName == nil || $0.stages.contains(stageName!))
                }) else {
                    return nil
                }
            }
            let dependency = dependencies.dependency(kind: kind, modelIndex: modelIndex)
            let modelName = dependency.map {
                "stage_\(kind)_\(String(format: "%03u", $0.modelIndex))_\($0.modelName)"
            } ?? "stage_\(kind)_\(modelIndex)"
            let matrixQ16 = object.matrixWords.compactMap { word -> Int32? in
                let value = Double(Float(bitPattern: word)) * 65_536.0
                guard value.isFinite,
                      value >= Double(Int32.min), value <= Double(Int32.max) else { return nil }
                return Int32(value.rounded(.toNearestOrAwayFromZero))
            }
            return GoldenEyeStageModelPlacementV6(
                stageID: stageID,
                objectIndex: object.index,
                objectType: object.type,
                modelIndex: modelIndex,
                kind: kind,
                modelName: modelName,
                matrixWords: object.matrixWords,
                matrixQ16: matrixQ16,
                sidecarReady: sidecars.models[modelName] != nil
            )
        }
        return Self(placements: placements)
    }
}
