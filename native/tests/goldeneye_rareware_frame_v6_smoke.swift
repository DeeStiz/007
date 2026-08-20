import Foundation

private let root = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/native/source-frontend-v6",
    isDirectory: true
)

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), "goldeneye_rareware_frame_v6_smoke: \(message)")
}

@main
struct GoldenEyeRarewareFrameV6Smoke {
    static func main() throws {
        let modelURL = root.appendingPathComponent("rarewarelogo.gesm")
        let model = try GoldenEyeSourceModelV6.load(
            data: Data(contentsOf: modelURL),
            modelName: GoldenEyeRarewareFrameV6.modelName
        )
        let resolvedCompilation = GESourceModelCompilerV6.compile(
            model,
            modelName: GoldenEyeRarewareFrameV6.modelName,
            dynamicResolver: GESourceModelDynamicResolverV6(
                resolvedModels: [GoldenEyeRarewareFrameV6.modelName]
            )
        )
        expect(resolvedCompilation.status == .complete, "resolved Rareware compiler status")
        expect(resolvedCompilation.diagnostics.isEmpty, "resolved Rareware compiler diagnostics")
        expect(resolvedCompilation.scene?.commands.count == GoldenEyeRarewareFrameV6.expectedCommandCount, "resolved Rareware command stream")

        let anchor = try GoldenEyeRarewareFrameV6.make(
            model: model,
            nativeTick: 2,
            referenceTick: 1,
            sourceTimer: 0,
            pairPhase: 0
        )
        expect(anchor.passes.count == 3, "three source passes")
        expect(anchor.sourceCommandCount == GoldenEyeRarewareFrameV6.expectedCommandCount, "command count")
        expect(anchor.sourceCommandHash == GoldenEyeRarewareFrameV6.expectedSourceCommandHash, "source command hash")
        expect(anchor.sourceTriangleCount == GoldenEyeRarewareFrameV6.expectedTriangleCount, "triangle count")
        expect(anchor.textureHandles.count == 6, "six textures")
        expect(anchor.mipLevelsByTexture == [6, 6, 6, 6, 1, 1], "mip chain shape")
        expect(anchor.passes[0].textureIndices == [4], "first body texture")
        expect(anchor.passes[1].textureIndices == [0, 1, 2, 3], "LOD texture sequence")
        expect(anchor.passes[2].textureIndices == [5], "second body texture")
        expect(anchor.passes[0].cycleCount == 1 && anchor.passes[2].cycleCount == 1, "lit one-cycle body passes")
        expect(anchor.passes[1].cycleCount == 2, "two-cycle letter pass")
        expect(!anchor.passes[0].mipLODEnabled && anchor.passes[1].mipLODEnabled, "source LOD mode")
        expect(anchor.passes[1].hasLODGradient, "LOD fraction combiner")
        expect(anchor.passes[0].geometryMode == 0x0006_0000, "first source geometry mode")
        expect(anchor.passes[1].geometryMode == 0, "letter clear geometry mode")
        expect(anchor.passes[2].geometryMode == 0x0006_0000, "second source geometry mode")
        expect(anchor.fadeAlpha == 0, "source fade starts at zero")
        expect(anchor.rotationDegreesQ16 == -40 * 65_536, "source rotation starts at -40 degrees")
        expect(anchor.projection.fovyDegreesQ16 == 60 * 65_536, "source fovy")
        expect(anchor.projection.cameraZQ16 == 880 * 65_536, "source camera z")
        expect(anchor.sourceSFXAssetID == 258, "Rareware SFX binding")
        let captureSpec = try GoldenEyeRarewareCaptureSpecV6(
            frame: anchor,
            root: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        )
        expect(captureSpec.reference320URL.path.contains("build/native/rareware-reference-capture-v6"), "reference capture boundary")
        expect(captureSpec.faithfulHDURL.path.hasSuffix("rareware-faithful-hd.raw"), "HD capture name")

        let geometry = try GoldenEyeRarewareGeometryV6.make(model: model, frame: anchor)
        expect(geometry.triangles.count == 268, "source triangle packet")
        expect(geometry.vertices.count == 804, "source triangle vertex copies")
        expect(geometry.triangles.prefix(18).allSatisfy { $0.passIndex == 0 && $0.textureIndex == 4 }, "first body order")
        expect(geometry.triangles.dropFirst(18).prefix(8).allSatisfy { $0.passIndex == 1 && (0..<4).contains($0.textureIndex) }, "LOD body order")
        expect(geometry.triangles.dropFirst(26).allSatisfy { $0.passIndex == 2 && $0.textureIndex == 5 }, "second body order")
        expect(geometry.vertices[0].sourceIndex == geometry.vertices[3].sourceIndex && geometry.vertices[0] == geometry.vertices[3], "cache-safe copied vertices")
        expect(geometry.geometryHash != 0, "geometry hash")

        let odd = try GoldenEyeRarewareFrameV6.make(
            model: model,
            nativeTick: 3,
            referenceTick: 1,
            sourceTimer: 0,
            pairPhase: 1
        )
        expect(odd.rotationDegreesQ16 == -40 * 65_536 + 65_536, "native half-step rotation")
        expect(odd.frameHash != anchor.frameHash, "odd frame hash differs")
        expect(odd.sourceCommandHash == anchor.sourceCommandHash, "source command hash stable")

        let fullFade = try GoldenEyeRarewareFrameV6.make(
            model: model,
            nativeTick: 142,
            referenceTick: 71,
            sourceTimer: 70,
            pairPhase: 0
        )
        expect(fullFade.fadeAlpha == 255, "fade reaches full opacity")
        let endFade = try GoldenEyeRarewareFrameV6.make(
            model: model,
            nativeTick: 522,
            referenceTick: 261,
            sourceTimer: 260,
            pairPhase: 0
        )
        expect(endFade.fadeAlpha == 0, "fade reaches zero at source exit boundary")
        expect(!endFade.transitionReady, "transition happens after the source's 260 boundary frame")
        let route = try GoldenEyeRarewareFrameV6.make(
            model: model,
            nativeTick: 582,
            referenceTick: 291,
            sourceTimer: 290,
            pairPhase: 0
        )
        expect(route.transitionReady, "source route boundary")

        let repeated = try GoldenEyeRarewareFrameV6.make(
            model: model,
            nativeTick: 2,
            referenceTick: 1,
            sourceTimer: 0,
            pairPhase: 0
        )
        expect(repeated == anchor, "deterministic frame repeat")

        var tampered = try Data(contentsOf: modelURL)
        tampered[GoldenEyeSourceModelV6.headerSize] ^= 0x01
        do {
            _ = try GoldenEyeSourceModelV6.load(data: tampered, modelName: GoldenEyeRarewareFrameV6.modelName)
            preconditionFailure("tampered Rareware GESM accepted")
        } catch {
            print("rareware frame packet tamper guard: PASS")
        }

        print(
            "rareware frame-v6: commands=\(anchor.sourceCommandCount) " +
                "triangles=\(anchor.sourceTriangleCount) " +
                "passes=\(anchor.passes.map(\.triangleCount)) " +
                "sourceHash=\(anchor.sourceCommandHash) frameHash=\(anchor.frameHash) PASS"
        )
        print("goldeneye_rareware_frame_v6_smoke: PASS")
    }
}
