import Foundation
import simd

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
    let modelScaleQ16: Int32
    let matrixWords: [UInt32]
    let matrixQ16: [Int32]
    let sidecarReady: Bool

    var transformReady: Bool {
        guard matrixQ16.count == 16 else { return false }
        let values = matrixQ16.map { Double($0) / 65_536.0 }
        guard values.allSatisfy({ $0.isFinite }) else { return false }
        let determinant =
            values[0] * (values[5] * values[10] - values[6] * values[9]) -
            values[1] * (values[4] * values[10] - values[6] * values[8]) +
            values[2] * (values[4] * values[9] - values[5] * values[8])
        return determinant.isFinite && abs(determinant) > 1.0e-9 && values[15] != 0
    }
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
            // Type 7/8 are source ammo/collectable records. Their runtime
            // matrices are populated by item ownership, not setup-pad
            // placement, so they remain outside the V7 static-prop contract;
            // monitors, autoguns, gas, vehicles, and other dynamic pages are
            // excluded by the same allowlist.
            case 1, 3, 4, 5, 12, 17, 42, 43, 47:
                kind = "prop"
            case 9:
                kind = "character"
            default:
                return nil
            }
            let dependency: GoldenEyeStageSetupDependencyCatalogV6.Dependency?
            if kind == "character", let stageName {
                // Type-9 setup key0 is chrnum. The corrected GuardRecord
                // dependency row joins by source offset and carries bodyID.
                dependency = dependencies.dependencies.first {
                    $0.stage == stageName && $0.kind == "character" &&
                        $0.setupOffset == object.sourceRecordOffset
                }
            } else {
                dependency = dependencies.dependency(kind: kind, modelIndex: object.key0)
            }
            let modelIndex = dependency?.modelIndex ?? object.key0
            if let visibleDependencies {
                let category = kind == "prop" ? "props" : "guards"
                guard visibleDependencies.dependencies.contains(where: {
                    $0.category == category && $0.modelIndex == modelIndex
                        && (stageName == nil || $0.stages.contains(stageName!))
                }) else {
                    return nil
                }
            }
            let modelName = dependency.map {
                "stage_\(kind)_\(String(format: "%03u", $0.modelIndex))_\($0.modelName)"
            } ?? "stage_\(kind)_\(modelIndex)"
            let modelScaleQ16 = dependency?.modelScaleQ16 ?? 0
            let sourceMatrixWords = sourcePlacementMatrixWords(
                object: object,
                setup: setup,
                modelScaleQ16: modelScaleQ16
            ) ?? object.matrixWords
            let matrixQ16 = sourceMatrixWords.compactMap { word -> Int32? in
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
                modelScaleQ16: modelScaleQ16,
                matrixWords: sourceMatrixWords,
                matrixQ16: matrixQ16,
                sidecarReady: sidecars.models[modelName] != nil
            )
        }
        return Self(placements: placements)
    }

    /// `ObjectRecord.mtx` is runtime-owned and is zero in the serialized setup
    /// stream. `domakedefaultobj()` reconstructs it from the referenced pad's
    /// look/up basis and the model/extra scale before moving the prop to the
    /// pad position. Reproduce that source basis here; if the pad or scale is
    /// unavailable, retain the copied matrix so the lowerer fails closed.
    static func sourcePlacementMatrixWords(
        object: GoldenEyeStageSetupObjectPacket,
        setup: GoldenEyeStageSetupPacket,
        modelScaleQ16: Int32
    ) -> [UInt32]? {
        guard modelScaleQ16 > 0 else { return nil }
        let rawPad = Int32(Int16(bitPattern: UInt16(truncatingIfNeeded: object.key1)))
        let basis: (position: SIMD3<Double>, up: SIMD3<Double>, look: SIMD3<Double>)?
        if rawPad >= 0, rawPad < Int32(setup.pads.count) {
            let pad = setup.pads[Int(rawPad)]
            basis = vectors(position: pad.position, up: pad.up, look: pad.look)
        } else if rawPad >= 10_000,
                  rawPad - 10_000 < Int32(setup.boundPads.count) {
            let pad = setup.boundPads[Int(rawPad - 10_000)]
            basis = vectors(position: pad.position, up: pad.up, look: pad.look)
        } else {
            basis = nil
        }
        guard let basis,
              let forward = normalized(basis.look),
              let up = normalized(basis.up) else { return nil }
        // Matches matrix_4x4_set_basis_and_position(): target=-look is
        // normalized with a negative factor, yielding +look as the basis.
        guard let right = normalized(cross(up, forward)),
              let correctedUp = normalized(cross(forward, right)) else { return nil }
        let extraScale = Double(object.scale8_8) / 256.0
        let scale = Double(modelScaleQ16) / 65_536.0 * extraScale
        guard scale.isFinite, scale > 0 else { return nil }
        let values: [Double] = [
            right.x * scale, correctedUp.x * scale, forward.x * scale, basis.position.x,
            right.y * scale, correctedUp.y * scale, forward.y * scale, basis.position.y,
            right.z * scale, correctedUp.z * scale, forward.z * scale, basis.position.z,
            0, 0, 0, 1,
        ]
        guard values.allSatisfy({ $0.isFinite }) else { return nil }
        return values.map { Float($0).bitPattern }
    }

    private static func vectors(
        position: GoldenEyeStageSetupVectorBits,
        up: GoldenEyeStageSetupVectorBits,
        look: GoldenEyeStageSetupVectorBits
    ) -> (position: SIMD3<Double>, up: SIMD3<Double>, look: SIMD3<Double>)? {
        func vector(_ bits: GoldenEyeStageSetupVectorBits) -> SIMD3<Double>? {
            let values = SIMD3(
                Double(Float(bitPattern: bits.x)),
                Double(Float(bitPattern: bits.y)),
                Double(Float(bitPattern: bits.z))
            )
            return values.x.isFinite && values.y.isFinite && values.z.isFinite ? values : nil
        }
        guard let position = vector(position), let up = vector(up), let look = vector(look) else {
            return nil
        }
        return (position, up, look)
    }

    private static func normalized(_ value: SIMD3<Double>) -> SIMD3<Double>? {
        let length = simd_length(value)
        guard length.isFinite, length > 1.0e-9 else { return nil }
        return value / length
    }
}
