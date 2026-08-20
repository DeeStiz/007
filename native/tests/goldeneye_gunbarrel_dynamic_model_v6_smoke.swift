import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

private let arguments = Array(CommandLine.arguments.dropFirst())
private let root = URL(fileURLWithPath: arguments.first ?? "build/native/source-frontend-v6", isDirectory: true)
private let sidecarURL = URL(fileURLWithPath: arguments.dropFirst().first ?? "build/native/gunbarrel-v6-prepared/gunbarrel.gbar")

@main
struct GoldenEyeGunbarrelDynamicModelV6Smoke {
    static func main() throws {
        let sidecar = try GoldenEyeGunbarrelDynamicSidecarV6(loading: sidecarURL)
        check(sidecar.resolvesGunbarrelModels, "sidecar resolver completeness")
        let resolver = sidecar.dynamicResolver
        check(resolver.resolves(modelName: "headbrosnansuit"), "head resolver")
        check(resolver.resolves(modelName: "suitbond"), "body resolver")
        check(resolver.resolves(modelName: "chrwppk"), "weapon resolver")
        let walkStart = try sidecar.animationPoseSelection(sourceTimer: 0)
        check(walkStart.clipName == "bond_eye_walk" && walkStart.frame == 2, "walk animation source start frame")
        let fireStart = try sidecar.animationPoseSelection(sourceTimer: 137)
        check(fireStart.clipName == "bond_eye_fire" && fireStart.frame == 2, "fire animation source start")
        let speedup = try sidecar.animationPoseSelection(sourceTimer: 212)
        let afterSpeedup = try sidecar.animationPoseSelection(sourceTimer: 213)
        check(speedup.clipName == "bond_eye_fire" && afterSpeedup.clipName == "bond_eye_fire", "fire speedup clip")
        check(speedup.frame != afterSpeedup.frame, "fire speedup changes selected frame")

        var sceneCount = 0
        for name in ["headbrosnansuit", "suitbond", "chrwppk"] {
            let model = try GoldenEyeSourceModelV6.load(from: root.appendingPathComponent("\(name).gesm"))
            let result = GESourceModelCompilerV6.compile(model, modelName: name, dynamicResolver: resolver)
            check(result.status == .complete, "\(name) dynamic status")
            check(result.diagnostics.isEmpty, "\(name) dynamic diagnostics \(result.diagnostics)")
            guard let scene = result.scene else { preconditionFailure("\(name) scene missing") }
            check(scene.unsupportedCount == 0, "\(name) unsupported command count")
            check(!scene.commands.isEmpty && !scene.visibleNodeIDs.isEmpty, "\(name) traversed source graph")
            sceneCount += 1
            print("gunbarrel_dynamic_scene=\(name):nodes=\(scene.visibleNodeIDs.count):commands=\(scene.commands.count):hash=\(scene.semanticHash)")
        }
        check(sceneCount == 3, "dynamic scene count")
        print("goldeneye_gunbarrel_dynamic_model_v6_smoke: PASS")
    }
}
