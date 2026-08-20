import Foundation

@main
struct GoldenEyeRamRomDynamicSceneV6Smoke {
    static func main() throws {
        let matrix = GoldenEyeRamRomDynamicSceneComposerV6.readinessMatrix()
        precondition(matrix.count == 14)
        for demoID in UInt8(1)...UInt8(14) {
            guard let readiness = matrix[demoID] else { fatalError("missing route (demoID)") }
            precondition(!readiness.isComplete)
            precondition(readiness.missingFields.contains("gameplay.snapshot"))
            precondition(readiness.missingFields.contains("weapon_effect.snapshot"))
            precondition(readiness.missingFields.contains("intro.item_to_render_model"))
        }

        let root = URL(fileURLWithPath: "/tmp/dynamic-scene-fixture", isDirectory: true)
        let sidecars = GoldenEyeStageModelSidecarCatalogV6(
            rootURL: root, models: [:], sidecarCount: 0,
            expectedModelCount: 1, status: "FAIL", payloads: [:]
        )
        let dependencies = GoldenEyeStageSetupDependencyCatalogV6(
            rootURL: root, manifestURL: root.appendingPathComponent("none"), dependencies: []
        )
        let visible = GoldenEyeRamRomVisibleDependencyCatalogV6(
            rootURL: root, dependencies: [], categoryNames: []
        )
        let missing = try GoldenEyeRamRomDynamicSceneComposerV6.compose(
            route: GoldenEyeRamRomDynamicSceneComposerV6.routes[0],
            inputs: .init(), sidecars: sidecars, dependencies: dependencies,
            visibleDependencies: visible, nativeTick: 2, strict: false
        )
        precondition(!missing.presentable)
        precondition(missing.missingFields.contains("gameplay.snapshot"))
        precondition(missing.missingFields.contains("stage_model_sidecars.complete"))

        let fixture = GoldenEyeRamRomDynamicSceneComposerV6.fixtureOnly()
        precondition(fixture.fixtureOnly)
        precondition(fixture.fixturePresentable)
        precondition(fixture.elements.count == 9)
        precondition(fixture.elements.map(\.kind.order) == fixture.elements.map(\.kind.order).sorted())
        precondition(fixture.sceneHash != 0)
        print(
            "goldeneye_ramrom_dynamic_scene_v6_smoke: PASS " +
                "routes=14 missing-matrix=14 fixture-only=1 elements=9"
        )
    }
}
