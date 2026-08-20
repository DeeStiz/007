import Foundation

private let root = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/native/source-frontend-v6",
    isDirectory: true
)

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), "goldeneye_source_projection_consumption_v6_smoke: \(message)")
}

@main
struct GoldenEyeSourceProjectionConsumptionV6Smoke {
    static func main() throws {
        let preparation = try GoldenEyeSourceProductPreparationV6.load(rootURL: root)
        let provider = try GoldenEyeSourceFrontendMatrixProviderV6(
            preparation: preparation,
            viewportWidth: 440,
            viewportHeight: 330
        )
        var authority = try GoldenEyeSourceFrontendAuthorityV6()
        let frame = try authority.step(
            try GoldenEyeSourceFrontendTimelineV6(nativeTick: 1),
            synthetic: true
        )
        let resources = try provider.frameResources(for: frame)
        expect(resources.matrices.count >= 4, "matrix provider projection/camera resources")
        expect(resources.viewports.count == 1, "matrix provider viewport")

        let model = try preparation.model(named: "legalpage")
        let compilation = GESourceModelCompilerV6.compile(model, modelName: "legalpage")
        guard let scene = compilation.scene else {
            preconditionFailure("missing legal source scene")
        }
        let modelHandle = scene.commands.compactMap { command -> UInt32? in
            guard command.macro == "gsSPMatrix", let argument = command.arguments.first else { return nil }
            switch argument {
            case .handle(_, let value): return value
            case .integer(let value): return UInt32(truncatingIfNeeded: value)
            case .constant(_, let value): return value
            case .null: return nil
            case .boolean(let value): return value ? 1 : 0
            }
        }.first ?? 0
        expect(modelHandle != 0, "legal model matrix handle")
        // The provider's copied frame order is explicit source metadata:
        // model, camera, projection, reflection.  Name the projection role
        // here rather than deriving it from a handle prefix.
        expect(resources.matrices.count >= 3, "legal projection matrix resource")
        expect(resources.matrices[0].roleFlags & 1 != 0, "provider modelview role")
        expect(resources.matrices[2].roleFlags & 2 != 0, "provider projection role")
        let sceneFrame = try GoldenEyeGBISceneFrameContextV6(
            nativeTick: frame.nativeTick,
            referenceTick: frame.referenceTick,
            pairPhase: frame.nativeTick & 1 == 0 ? 0 : 1,
            screen: frame.screen,
            subphase: frame.subphase,
            viewportWidth: resources.viewportWidth,
            viewportHeight: resources.viewportHeight
        )
        let result = try GoldenEyeGBISceneBuilderV6.build(
            model: model,
            modelName: "legalpage",
            matrices: resources.matrices,
            viewports: resources.viewports,
            frame: sceneFrame
        )
        expect(result.presentable, "legal builder source-presentable with clip binding")
        expect(result.projectionConsumption.isComplete, "projection consumption is complete")
        expect(result.projectionConsumption.consumedDrawCount == result.projectionConsumption.requiredDrawCount, "all source draws consume clip")
        let projection = String(result.projectionConsumption.sourceProjectionHandle, radix: 16)
        let viewport = String(result.projectionConsumption.sourceViewportHandle, radix: 16)
        let draws = "\(result.projectionConsumption.consumedDrawCount)/\(result.projectionConsumption.requiredDrawCount)"
        print("goldeneye_source_projection_consumption_v6_smoke: PASS projection=0x\(projection) viewport=0x\(viewport) draws=\(draws)")
    }
}
