import Foundation

#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), "goldeneye_cast_chrfnp90_builder_v6_smoke: \(message)")
}

private func matrixHandles(_ scene: GESourceSceneV6) -> [UInt32] {
    var result = Set<UInt32>()
    for command in scene.commands where command.macro == "gsSPMatrix" {
        guard let argument = command.arguments.first else { continue }
        if case let .handle(_, value) = argument, value != 0 {
            result.insert(value)
        }
    }
    return result.sorted()
}

private func makeMatrix(
    handle: UInt32,
    roleFlags: UInt32
) throws -> GoldenEyeGBIMatrixResourceV6 {
    try GoldenEyeGBIMatrixResourceV6(
        handle: handle,
        values: [
            65_536, 0, 0, 0,
            0, 65_536, 0, 0,
            0, 0, 65_536, 0,
            0, 0, 0, 65_536,
        ],
        roleFlags: roleFlags
    )
}

@main
struct GoldenEyeCastChrfnp90BuilderV6Smoke {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let root = URL(
            fileURLWithPath: args.first
                ?? "build/native/cast-frontend-v6-image-decoder-v6-fullweapons",
            isDirectory: true
        )
        let modelName = args.dropFirst().first ?? "chrfnp90"
        let catalog = try GoldenEyeSourceFrontendCatalog.loadCast(preparedAssetRoot: root)
        let model = try GoldenEyeSourceModelV6.load(
            from: root.appendingPathComponent("\(modelName).gesm")
        )
        let resolver = GESourceModelDynamicResolverV6(
            resolvedModels: [modelName]
        )
        let compilation = GESourceModelCompilerV6.compile(
            model,
            modelName: modelName,
            dynamicResolver: resolver
        )
        expect(compilation.status == .complete, "source compilation status")
        expect(compilation.diagnostics.isEmpty, "source compilation diagnostics")
        guard let scene = compilation.scene else {
            throw Failure("source compilation has no scene")
        }
        let textureSetup = try GoldenEyeSourceTextureSetupResolverV6.resolve(
            modelName: modelName,
            model: model,
            catalog: catalog,
            compiledCommands: scene.commands
        )
        let handles = matrixHandles(scene)
        expect(!handles.isEmpty, "source model-view handles")
        let projectionHandle: UInt32 = 0xF200_0001
        let matrices = try handles.map {
            try makeMatrix(handle: $0, roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView)
        } + [
            try makeMatrix(
                handle: projectionHandle,
                roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.projection
            )
        ]
        let roles = try matrices.map {
            try GoldenEyeSourceMatrixRoleSidecarV6(handle: $0.handle, roleFlags: $0.roleFlags)
        }
        let viewport = try GoldenEyeGBIViewportResourceV6(
            handle: 0x9000_0001,
            values: [
                220 << 16, 165 << 16, 1 << 16, 1 << 16,
                220 << 16, 165 << 16, 0, 1 << 16,
            ]
        )
        let frame = try GoldenEyeGBISceneFrameContextV6(
            nativeTick: 2,
            referenceTick: 1,
            sourceTimer: 0,
            pairPhase: 0,
            screen: UInt32(GE_SOURCE_FRAME_V6_SCREEN_CAST),
            subphase: 0,
            viewportWidth: 440,
            viewportHeight: 330
        )
        let result: GoldenEyeGBISceneBuildResultV6
        do {
            result = try GoldenEyeGBISceneBuilderV6.build(
                model: model,
                modelName: modelName,
                matrices: matrices,
                viewports: [viewport],
                matrixRoles: roles,
                frame: frame,
                dynamicResolver: resolver,
                transformContext: .cast,
                renderSetupContext: .cast(forModel: model, scene: scene),
                textureSetups: textureSetup.setups
            )
        } catch {
            print("goldeneye_cast_chrfnp90_builder_v6_smoke: builderError=\(error)")
            return
        }
        guard result.presentable,
              result.unsupportedVisibleCount == 0,
              result.decoderUnsupportedCount == 0,
              !result.snapshot.drawCommands.isEmpty else {
            print(
                "goldeneye_cast_chrfnp90_builder_v6_smoke: FAIL "
                    + "presentable=\(result.presentable) unsupported=\(result.unsupportedVisibleCount) "
                    + "decoder=\(result.decoderUnsupportedCount) reasons=\(result.unsupportedReasons)"
            )
            return
        }
        print(
            "goldeneye_cast_chrfnp90_builder_v6_smoke: PASS "
                + "model=\(modelName) commands=\(scene.commands.count) "
                + "setups=\(textureSetup.setups.count) "
                + "vertexResources=\(result.vertexResourceTotal) "
                + "draws=\(result.snapshot.drawCommands.count)"
        )
    }
}

private struct Failure: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}
