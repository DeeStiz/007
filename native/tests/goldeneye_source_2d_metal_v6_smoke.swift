import Foundation

@main
struct GoldenEyeSource2DMetalV6Smoke {
    static func main() {
        do {
            try run()
            print("goldeneye_source_2d_metal_v6_smoke: PASS")
        } catch {
            fputs("goldeneye_source_2d_metal_v6_smoke: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() throws {
        guard CommandLine.arguments.count >= 2 else {
            throw NSError(
                domain: "goldeneye-source-2d-metal-v6",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "prepared asset root is required"]
            )
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let catalog = try GoldenEyeSourceFrontendCatalog.load(preparedAssetRoot: root)
        let assets = try GoldenEyeSource2DAssetsV6(catalog: catalog)
        let lowerer = GoldenEyeSource2DLowererV6(assets: assets)

        let legal = try lowerer.makeLegalFrame(nativeTick: 1, sourceTimer: 0)
        let legal320 = try GoldenEyeSource2DMetalBatchBuilderV6.build(
            frame: legal,
            assets: assets,
            outputWidth: 320,
            outputHeight: 240,
            mode: .reference320x240
        )
        let legal320Again = try GoldenEyeSource2DMetalBatchBuilderV6.build(
            frame: legal,
            assets: assets,
            outputWidth: 320,
            outputHeight: 240,
            mode: .reference320x240
        )
        precondition(legal320 == legal320Again)
        precondition(legal320.resourceHash != 0)
        precondition(legal320.vertices.count == (legal.glyphs.count + legal.fills.count) * 6)
        precondition(legal320.draws.count == legal.glyphs.count + legal.fills.count)
        precondition(legal320.geometryHash != 0)
        precondition(legal320.vertices.first?.position == SIMD2<Float>(0, 0))
        precondition(legal320.vertices[1].position == SIMD2<Float>(440, 0))
        precondition(legal320.vertices[2].position == SIMD2<Float>(440, 330))
        precondition(legal320.draws.allSatisfy { $0.scissor.x >= 0 && $0.scissor.y >= 0 })
        precondition(legal320.draws.allSatisfy { $0.scissor.x + $0.scissor.width <= 320 && $0.scissor.y + $0.scissor.height <= 240 })

        let legalHD = try GoldenEyeSource2DMetalBatchBuilderV6.build(
            frame: legal,
            assets: assets,
            outputWidth: 1920,
            outputHeight: 1080,
            mode: .faithfulHD
        )
        precondition(legalHD.vertices == legal320.vertices)
        // Vertex/source geometry is invariant across output modes; scissor
        // rectangles are intentionally output-pixel values and therefore
        // participate in a mode-specific evidence hash.
        precondition(legalHD.sourceFrameHash == legal320.sourceFrameHash)
        precondition(legalHD.geometryHash != 0)

        let legalWide = try GoldenEyeSource2DMetalBatchBuilderV6.build(
            frame: legal,
            assets: assets,
            outputWidth: 1920,
            outputHeight: 1080,
            mode: .adaptiveWidescreen
        )
        precondition(legalWide.draws[0].scissor.x > 0)
        precondition(legalWide.draws[0].scissor.width < 1920)

        let file = try lowerer.makeFileSelectFrame(nativeTick: 3, sourceTimer: 0, cursorCenter: (220, 165))
        let file320 = try GoldenEyeSource2DMetalBatchBuilderV6.build(
            frame: file,
            assets: assets,
            outputWidth: 320,
            outputHeight: 240,
            mode: .reference320x240
        )
        precondition(file.textureRects.count == 4)
        precondition(file320.draws.filter { $0.primitive == .texture }.count == 4)
        precondition(Set(file320.draws.filter { $0.primitive == .texture }.map(\.resourceID)).count == 4)
        precondition(file.textureRects.allSatisfy { $0.flags & 1 != 0 })
        for draw in file320.draws where draw.primitive == .texture {
            let vertices = file320.vertices[draw.vertexStart..<(draw.vertexStart + 6)]
            // Source front.c uses flipY=1 for each frontend image.  The
            // packet keeps decoded rows unchanged, so the first screen-row
            // vertices address V=1 and the lower row addresses V=0.
            precondition(vertices.first?.uv.y == 1)
            precondition(vertices.dropFirst().first?.uv.y == 1)
            precondition(vertices.dropFirst(2).first?.uv.y == 0)
            precondition(vertices.last?.uv.y == 0)
        }

        let mode = try lowerer.makeModeSelectFrame(nativeTick: 4, sourceTimer: 0, selectedRow: 1)
        let mode320 = try GoldenEyeSource2DMetalBatchBuilderV6.build(
            frame: mode,
            assets: assets,
            outputWidth: 320,
            outputHeight: 240,
            mode: .reference320x240
        )
        precondition(mode320.draws.contains { $0.primitive == .fill })
        precondition(mode320.draws.contains { $0.primitive == .glyph })

        do {
            let badTexture = GoldenEyeSource2DTextureRectV6(
                resourceRecordID: 0xFFFF_FFFF,
                rect: .init(x: 0, y: 0, width: 1, height: 1),
                scissor: .init(),
                u0Q16: 0, v0Q16: 0, u1Q16: 65_536, v1Q16: 65_536,
                tintRGBA: 0xFFFF_FFFF, flags: 0, sequence: 99
            )
            let badFrame = GoldenEyeSource2DFrameV6(
                screen: file.screen,
                nativeTick: file.nativeTick,
                sourceTimer: file.sourceTimer,
                logicalWidth: file.logicalWidth,
                logicalHeight: file.logicalHeight,
                scissor: file.scissor,
                fills: file.fills,
                textureRects: [badTexture],
                glyphs: file.glyphs,
                unsupportedVisibleCount: 0,
                frameHash: file.frameHash
            )
            _ = try GoldenEyeSource2DMetalBatchBuilderV6.build(
                frame: badFrame,
                assets: assets,
                outputWidth: 320,
                outputHeight: 240,
                mode: .reference320x240
            )
            preconditionFailure("missing source texture was accepted")
        } catch let error as GoldenEyeSource2DMetalRendererV6Error {
            guard case .missingResource(0xFFFF_FFFF) = error else {
                throw error
            }
        }

        print("legal320=vertices=\(legal320.vertices.count) draws=\(legal320.draws.count) resourceHash=\(legal320.resourceHash) geometryHash=\(legal320.geometryHash)")
        print("file320=textureDraws=\(file320.draws.filter { $0.primitive == .texture }.count) resourceHash=\(file320.resourceHash) geometryHash=\(file320.geometryHash)")
        print("mode320=draws=\(mode320.draws.count) resourceHash=\(mode320.resourceHash) geometryHash=\(mode320.geometryHash)")
        print("source_frame_hashes=legal:\(legal.frameHash),file:\(file.frameHash),mode:\(mode.frameHash)")
        print("renderer_fallback=false")
        print("runtime_rom_access=false")
    }
}
