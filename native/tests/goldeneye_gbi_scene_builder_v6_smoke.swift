#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), "goldeneye_gbi_scene_builder_v6_smoke: \(message)")
}

private let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/native/source-frontend-v6", isDirectory: true)

private func identityMatrix() throws -> GoldenEyeGBIMatrixResourceV6 {
    var values = Array(repeating: Int32(0), count: 16)
    values[0] = 65_536; values[5] = 65_536; values[10] = 65_536; values[15] = 65_536
    return try GoldenEyeGBIMatrixResourceV6(handle: 0, values: values)
}

private func firstMatrixHandle(_ scene: GESourceSceneV6) -> UInt32 {
    for command in scene.commands where command.macro == "gsSPMatrix" {
        if let first = command.arguments.first {
            switch first {
            case .handle(_, let value): return value
            case .integer(let value): return UInt32(truncatingIfNeeded: value)
            case .constant(_, let value): return value
            case .null: continue
            case .boolean(let value): return value ? 1 : 0
            }
        }
    }
    return 0
}

private func makeMatrix(_ handle: UInt32) throws -> GoldenEyeGBIMatrixResourceV6 {
    var values = Array(repeating: Int32(0), count: 16)
    values[0] = 65_536; values[5] = 65_536; values[10] = 65_536; values[15] = 65_536
    return try GoldenEyeGBIMatrixResourceV6(handle: handle, values: values)
}

private func makeProjectionMatrix(_ handle: UInt32) throws -> GoldenEyeGBIMatrixResourceV6 {
    try makeMatrix(handle)
}

private func makeViewport() throws -> GoldenEyeGBIViewportResourceV6 {
    try GoldenEyeGBIViewportResourceV6(
        handle: 0x9000_0001,
        values: [160 << 16, 120 << 16, 1 << 16, 1 << 16, 160 << 16, 120 << 16, 0, 1 << 16]
    )
}

private func fixedArray<T, E>(_ tuple: T, count: Int, as: E.Type) -> [E] {
    var copy = tuple
    return withUnsafeBytes(of: &copy) { raw in
        Array(raw.bindMemory(to: E.self).prefix(count))
    }
}

private func expectError(_ body: () throws -> Void, _ message: String) {
    do {
        try body()
        preconditionFailure("goldeneye_gbi_scene_builder_v6_smoke: expected error: \(message)")
    } catch {
        print("builder-v6 negative \(message): PASS (\(error))")
    }
}

private func floorDivPow2(_ value: Int64, _ shift: UInt32) -> Int64 {
    guard shift > 0 else { return value }
    let divisor = Int64(1) << shift
    if value >= 0 { return value / divisor }
    return -((-value + divisor - 1) / divisor)
}

private func expectedSamplerQ16(
    source: Int32,
    scale: UInt32,
    shift: UInt32,
    originQ2: UInt32,
    dimension: UInt32
) -> Int32 {
    let scaled = floorDivPow2(Int64(source) * Int64(scale), 5)
    let shifted: Int64
    if shift <= 10 {
        shifted = floorDivPow2(scaled, shift)
    } else {
        shifted = scaled << (16 - shift)
    }
    return Int32((shifted - (Int64(originQ2) << 14)) / Int64(dimension))
}

@main
struct GoldenEyeGBISceneBuilderV6Smoke {
    static func main() throws {
        let catalog = try GoldenEyeSourceFrontendCatalog.load(preparedAssetRoot: root)
        let cases: [(name: String, screen: UInt32, expectedCommands: UInt32, expectedSourceSlots: UInt32, expectedTriangles: UInt32, expectedStates: UInt32, expectedResources: UInt32, expectedVertexLoads: UInt32, expectedVertexResources: UInt32, expectedPages: UInt32)] = [
            ("legalpage", UInt32(GE_SOURCE_FRAME_V6_SCREEN_LEGAL), 60, 12, 12, 6, 6, 2, 2, 0),
            ("nintendologo", UInt32(GE_SOURCE_FRAME_V6_SCREEN_NINTENDO), 845, 1021, 1018, 2, 2, 93, 93, 1),
            ("goldeneyelogo", UInt32(GE_SOURCE_FRAME_V6_SCREEN_GOLDENEYE), 164, 341, 339, 2, 3, 29, 29, 0),
            // Wallet intentionally exercises the compiler-selected default
            // switch route (27 visible nodes, 13 display lists, 390 source
            // commands). Hidden wallet nodes remain in the GESM but are not
            // emitted by the synthetic root; they must not change visible
            // command/state counts.
            ("walletbond", UInt32(GE_SOURCE_FRAME_V6_SCREEN_FILE_SELECT), 404, 246, 242, 23, 22, 68, 68, 1),
        ]

        var results: [String: GoldenEyeGBISceneBuildResultV6] = [:]
        for item in cases {
            let model = try GoldenEyeSourceModelV6.load(
                data: Data(contentsOf: root.appendingPathComponent("\(item.name).gesm")),
                modelName: item.name
            )
            let compiled = GESourceModelCompilerV6.compile(model, modelName: item.name)
            expect(compiled.status == .complete && compiled.diagnostics.isEmpty, "\(item.name) source compile")
            guard let scene = compiled.scene else { preconditionFailure("missing scene \(item.name)") }
            let textureSetups: [GoldenEyeSourceTextureSetupV6]
            if ["legalpage", "nintendologo", "goldeneyelogo", "walletbond"].contains(item.name) {
                let setupResult = try GoldenEyeSourceTextureSetupResolverV6.resolve(
                    modelName: item.name,
                    model: model,
                    catalog: catalog,
                    compiledCommands: scene.commands
                )
                expect(!setupResult.setups.isEmpty, "\(item.name) typed texture setups")
                expect(setupResult.setupHash != 0, "\(item.name) texture setup hash")
                textureSetups = setupResult.setups
                print("builder-v6 \(item.name) texture setups=\(setupResult.setups.count) hash=\(setupResult.setupHash)")
            } else {
                textureSetups = []
            }
            let matrixHandle = firstMatrixHandle(scene)
            expect(matrixHandle != 0, "\(item.name) matrix handle")
            let matrix = try makeMatrix(matrixHandle)
            let projectionHandle: UInt32 = 0xF200_0001
            let projection = try makeProjectionMatrix(projectionHandle)
            let frame = try GoldenEyeGBISceneFrameContextV6(
                nativeTick: 2,
                referenceTick: 1,
                sourceTimer: 1,
                pairPhase: 0,
                screen: item.screen,
                viewportWidth: 640,
                viewportHeight: 480
            )
            let result = try GoldenEyeGBISceneBuilderV6.build(
                model: model,
                modelName: item.name,
                matrices: [matrix, projection],
                viewports: [try makeViewport()],
                matrixRoles: [
                    try GoldenEyeSourceMatrixRoleSidecarV6(
                        handle: matrixHandle,
                        roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView
                    ),
                    try GoldenEyeSourceMatrixRoleSidecarV6(
                        handle: projectionHandle,
                        roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.projection
                    ),
                ],
                frame: frame,
                textureSetups: textureSetups
            )
            let otherModeWords = scene.commands.filter {
                $0.opcode == UInt8(GE_SOURCE_GBI_V6_OP_SETOTHERMODE_H) ||
                    $0.opcode == UInt8(GE_SOURCE_GBI_V6_OP_SETOTHERMODE_L)
            }.prefix(8).map {
                "0x\(String($0.word0, radix: 16))/0x\(String($0.word1, radix: 16))"
            }.joined(separator: ",")
            FileHandle.standardError.write(
                Data("builder-v6 \(item.name) source-othermode=\(otherModeWords)\n".utf8)
            )
            expect(result.packetDialect == UInt32(GE_SOURCE_GBI_V6_DIALECT_CLASSIC_GE_F3D), "\(item.name) classic dialect")
            expect(result.packetCommandWordHash != 0, "\(item.name) packet command hash")
            expect(result.decoderStatus == GE_STATUS_OK, "\(item.name) decoder status")
            expect(result.textureSetups.count == textureSetups.count, "\(item.name) copied texture setup records")
            if item.name == "legalpage" {
                let textures = Dictionary(uniqueKeysWithValues: model.textures.map { ($0.resourceHandle, $0) })
                for texture in model.textures {
                    let materialDraws = result.snapshot.drawCommands.filter {
                        $0.resource_handle == texture.resourceHandle
                    }
                    expect(!materialDraws.isEmpty, "Legal material (String(texture.resourceHandle, radix: 16)) contributes draws")
                    guard let setup = textureSetups.first(where: { $0.resourceHandle == texture.resourceHandle }) else {
                        preconditionFailure("Legal material setup missing (String(texture.resourceHandle, radix: 16))")
                    }
                    var observedS: [Int32] = []
                    var observedT: [Int32] = []
                    var sourceS: [Int32] = []
                    var sourceT: [Int32] = []
                    for draw in materialDraws {
                        let start = Int(draw.first_vertex)
                        let end = start + Int(draw.vertex_count)
                        for vertex in result.snapshot.vertices[start..<end] {
                            guard let source = textures[texture.resourceHandle].flatMap({ _ in
                                model.vertices.first(where: { $0.id == vertex.source_index })
                            }) else {
                                preconditionFailure("Legal source vertex missing (vertex.source_index)")
                            }
                            let expectedS = expectedSamplerQ16(
                                source: source.s,
                                scale: setup.textureScaleS,
                                shift: setup.tileState.shiftS,
                                originQ2: setup.tileState.bounds.ulsQ2,
                                dimension: setup.levels[0].width
                            )
                            let expectedT = expectedSamplerQ16(
                                source: source.t,
                                scale: setup.textureScaleT,
                                shift: setup.tileState.shiftT,
                                originQ2: setup.tileState.bounds.ultQ2,
                                dimension: setup.levels[0].height
                            )
                            expect(vertex.texcoord_q16.0 == expectedS, "Legal material (String(texture.resourceHandle, radix: 16)) exact S UV")
                            expect(vertex.texcoord_q16.1 == expectedT, "Legal material (String(texture.resourceHandle, radix: 16)) exact T UV")
                            observedS.append(vertex.texcoord_q16.0)
                            observedT.append(vertex.texcoord_q16.1)
                            sourceS.append(source.s)
                            sourceT.append(source.t)
                        }
                    }
                    expect(!observedS.isEmpty && !observedT.isEmpty, "Legal material isolated output")
                    if (sourceS.max() ?? 0) != (sourceS.min() ?? 0) {
                        expect((observedS.max() ?? 0) > (observedS.min() ?? 0), "Legal material (String(texture.resourceHandle, radix: 16)) preserves S coverage")
                    }
                    if (sourceT.max() ?? 0) != (sourceT.min() ?? 0) {
                        expect((observedT.max() ?? 0) > (observedT.min() ?? 0), "Legal material (String(texture.resourceHandle, radix: 16)) preserves T coverage")
                    }
                }
            }
            if item.name == "walletbond" {
                let rawStates = result.stateWordEvidence.map {
                    "\($0.stateIndex):0x\(String($0.otherModeL, radix: 16))"
                }.joined(separator: ",")
                FileHandle.standardError.write(Data("builder-v6 walletbond raw-states=\(rawStates)\n".utf8))
            }
            if item.name == "goldeneyelogo" || item.name == "walletbond" {
                let expectedRawW0: UInt32 = 0xfc26_a004
                let expectedRawW1: UInt32 = 0x1f10_93ff
                guard let evidence = result.stateWordEvidence.first(where: {
                    $0.combineW0 == expectedRawW0 && $0.combineW1 == expectedRawW1
                }), let tuple = result.snapshot.renderStates.first(where: {
                    $0.state_handle == (0xA700_0000 | (evidence.stateIndex + 1))
                }) else {
                    preconditionFailure("\(item.name) missing source LERP tuple")
                }
                expect(tuple.cycle1_color_b == UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO), "\(item.name) LERP color B zero")
                expect(tuple.cycle1_color_d == UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO), "\(item.name) LERP color D zero")
                expect(tuple.cycle1_alpha_a == UInt32(GE_SOURCE_COMBINER_V6_KEY_COMBINED), "\(item.name) LERP alpha A combined")
                expect(tuple.cycle1_alpha_b == UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO), "\(item.name) LERP alpha B zero")
                expect(tuple.cycle1_alpha_c == UInt32(GE_SOURCE_COMBINER_V6_KEY_SHADE), "\(item.name) LERP alpha C shade")
                expect(tuple.cycle1_alpha_d == UInt32(GE_SOURCE_COMBINER_V6_KEY_ZERO), "\(item.name) LERP alpha D zero")
                expect(tuple.cycle0_color_a == UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL1), "\(item.name) LERP cycle0 color A texel1")
                expect(tuple.cycle0_color_b == UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0), "\(item.name) LERP cycle0 color B texel0")
                expect(tuple.cycle0_color_c == UInt32(GE_SOURCE_COMBINER_V6_KEY_LOD_FRACTION), "\(item.name) LERP cycle0 color C LOD")
                expect(tuple.cycle0_color_d == UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0), "\(item.name) LERP cycle0 color D texel0")
                expect(tuple.cycle0_alpha_a == UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL1), "\(item.name) LERP cycle0 alpha A texel1")
                expect(tuple.cycle0_alpha_b == UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0), "\(item.name) LERP cycle0 alpha B texel0")
                expect(tuple.cycle0_alpha_c == UInt32(GE_SOURCE_COMBINER_V6_KEY_LOD_FRACTION), "\(item.name) LERP cycle0 alpha C LOD")
                expect(tuple.cycle0_alpha_d == UInt32(GE_SOURCE_COMBINER_V6_KEY_TEXEL0), "\(item.name) LERP cycle0 alpha D texel0")
                expect(evidence.combineW0 == expectedRawW0 && evidence.combineW1 == expectedRawW1, "\(item.name) exact raw LERP words")
            }
            expect(result.decoderUnsupportedCount == 0, "\(item.name) decoder unsupported")
            expect(UInt32(model.commands.filter { $0.semantic.hasPrefix("gsSPVertex") }.count) == item.expectedVertexLoads,
                   "\(item.name) exact source vertex load count")
            let selectedVertexLoads = scene.commands.filter { $0.macro == "gsSPVertex" }.count
            FileHandle.standardError.write(Data("projection-v6 \(item.name): complete=\(result.projectionConsumption.isComplete) projection=0x\(String(result.projectionConsumption.sourceProjectionHandle, radix: 16)) viewport=0x\(String(result.projectionConsumption.sourceViewportHandle, radix: 16)) clip=\(result.projectionConsumption.combinedClipTransformHandles.count) consumed=\(result.projectionConsumption.consumedDrawCount)/\(result.projectionConsumption.requiredDrawCount) unsupported=\(result.unsupportedVisibleCount) reasons=\(result.unsupportedReasons.prefix(2))\n".utf8))
            expect(result.projectionConsumption.isComplete, "\(item.name) projection consumption closure")
            expect(result.projectionConsumption.consumedDrawCount == result.projectionConsumption.requiredDrawCount, "\(item.name) every draw consumes clip")
            expect(!result.projectionConsumption.combinedClipTransformHandles.isEmpty, "\(item.name) clip transform handles")
            expect(result.unsupportedVisibleCount == 0, "\(item.name) visible closure")
            expect(result.presentable, "\(item.name) presentable")
            let packetSourceCommandCount = result.packetCommandCount - result.packetListCount
            FileHandle.standardError.write(Data("builder-v6 \(item.name) observed command=\(result.commandCount) packet=\(result.packetCommandCount) source=\(packetSourceCommandCount) triangles=\(result.triangleCount) states=\(result.decoderStateCount) resources=\(result.resourceCount) vertexLoads=\(item.expectedVertexLoads) selectedVertexLoads=\(selectedVertexLoads) vertexResources=\(result.vertexResourceTotal)/pages=\(result.vertexResourcePageCount)\n".utf8))
            let rawOtherModeEvidence = result.snapshot.renderStates.map {
                "0x\(String($0.raw_othermode_h, radix: 16))/0x\(String($0.raw_othermode_l, radix: 16))"
            }.joined(separator: ",")
            print("builder-v6 \(item.name) othermode=\(rawOtherModeEvidence)")
            expect(result.commandCount == result.packetCommandCount, "\(item.name) packet command count")
            expect(result.triangleCount > 0, "\(item.name) triangle count")
            expect(result.commandCount == item.expectedCommands, "\(item.name) exact command count")
            expect(result.sourceCommandWordHash != 0, "\(item.name) source command words preserved")
            expect(result.packetSourceCommandWordHash != 0, "\(item.name) packet source command words")
            expect(result.sourceTriangleSlotCount == item.expectedSourceSlots, "\(item.name) encoded triangle slots")
            expect(result.triangleCount == item.expectedTriangles, "\(item.name) visible triangle count")
            expect(result.decoderStateCount == item.expectedStates, "\(item.name) state count")
            expect(result.resourceCount == item.expectedResources, "\(item.name) scene resource count")
            expect(result.geometryModesByState.count > 0, "\(item.name) decoded geometry sidecars")
            expect(result.modelViewQ16ByState.count > 0, "\(item.name) source model-view sidecars")
            if let lighting = result.snapshot.lightingFrameContext {
                expect(lighting.screen == item.screen, "\(item.name) source screen context")
                expect(lighting.sourceTimer == 1, "\(item.name) source-local timer")
                for draw in result.snapshot.drawCommands {
                    expect(lighting.geometryModesByState[draw.render_state_handle] != nil,
                           "\(item.name) draw geometry sidecar")
                    expect(lighting.modelViewQ16ByState[draw.render_state_handle]?.count == 16,
                           "\(item.name) draw model-view sidecar")
                }
            } else {
                preconditionFailure("\(item.name) missing lighting frame context")
            }
            expect(result.vertexResourceTotal == item.expectedVertexResources, "\(item.name) vertex resource total")
            expect(result.vertexResourcePageCount == item.expectedPages, "\(item.name) vertex resource page count")
            expect(item.expectedPages == 0 || result.vertexResourceManifestHash != 0, "\(item.name) vertex resource manifest hash")
            expect(result.snapshot.summary.unsupported_visible_count == 0, "\(item.name) summary unsupported")
            expect(result.snapshot.drawCommands.count > 0, "\(item.name) grouped draws")
            if item.name == "walletbond" {
                let emittedTriangles = result.snapshot.drawCommands.reduce(UInt32(0)) { $0 + $1.index_count }
                expect(emittedTriangles == result.projectionConsumption.consumedDrawCount, "\(item.name) emitted draws match supported triangles")
                expect(emittedTriangles == item.expectedTriangles, "\(item.name) all selected triangles emitted")
            }
            expect(result.snapshot.resources.count > 0, "\(item.name) resources")
            results[item.name] = result
            print("builder-v6 \(item.name): commands=\(result.commandCount) sourceSlots=\(result.sourceTriangleSlotCount) triangles=\(result.triangleCount) states=\(result.decoderStateCount) draws=\(result.snapshot.drawCommands.count) resources=\(result.resourceCount) vertexResources=\(result.vertexResourceTotal)/pages=\(result.vertexResourcePageCount) manifest=\(result.vertexResourceManifestHash) event=\(result.eventHash) state=\(result.stateHash) PASS")
        }

        // The exact values are intentionally asserted after the source sidecar
        // is decoded above; replacing these with a procedural fixture would
        // hide a source command/resource drift.
        let observed = cases.compactMap { item -> (String, UInt32, UInt32, UInt32)? in
            guard let result = results[item.name] else { return nil }
            return (item.name, result.commandCount, result.triangleCount, result.resourceCount)
        }
        expect(observed.map(\.0) == cases.compactMap { results[$0.name] == nil ? nil : $0.name }, "stable case ordering")
        print("builder-v6 exact counts: \(observed.map { "\($0.0):\($0.1)/\($0.2)/\($0.3)" }.joined(separator: ","))")

        let legal = results["legalpage"]!
        let repeatModel = try GoldenEyeSourceModelV6.load(
            data: Data(contentsOf: root.appendingPathComponent("legalpage.gesm")),
            modelName: "legalpage"
        )
        let repeatScene = GESourceModelCompilerV6.compile(
            repeatModel,
            modelName: "legalpage"
        ).scene!
        let repeatModelHandle = firstMatrixHandle(repeatScene)
        let repeatProjectionHandle: UInt32 = 0xF200_0001
        let legalRepeat = try GoldenEyeGBISceneBuilderV6.build(
            model: repeatModel,
            modelName: "legalpage",
            matrices: [
                try makeMatrix(repeatModelHandle),
                try makeProjectionMatrix(repeatProjectionHandle),
            ],
            viewports: [try makeViewport()],
            matrixRoles: [
                try GoldenEyeSourceMatrixRoleSidecarV6(
                    handle: repeatModelHandle,
                    roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView
                ),
                try GoldenEyeSourceMatrixRoleSidecarV6(
                    handle: repeatProjectionHandle,
                    roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.projection
                ),
            ],
            frame: try GoldenEyeGBISceneFrameContextV6(
                nativeTick: 2,
                referenceTick: 1,
                pairPhase: 0,
                screen: UInt32(GE_SOURCE_FRAME_V6_SCREEN_LEGAL),
                viewportWidth: 640,
                viewportHeight: 480
            ),
            textureSetups: legal.textureSetups
        )
        expect(legal.eventHash == legalRepeat.eventHash && legal.stateHash == legalRepeat.stateHash, "stable decoder hashes")
        expect(legal.snapshot.summary.frame_hash == legalRepeat.snapshot.summary.frame_hash, "stable frame hash")
        expect(legal.sourceCommandWordHash != 0 && legal.packetSourceCommandWordHash != 0,
               "legal source/packet words preserved before decode")
        expect(legal.sourceCommandWordHash == legalRepeat.sourceCommandWordHash,
               "legal source word hash stable")
        expect(legal.packetSourceCommandWordHash == legalRepeat.packetSourceCommandWordHash,
               "legal packet word hash stable")
        let legalStateWords = legal.snapshot.renderStates.flatMap {
            [$0.raw_othermode_h, $0.raw_othermode_l, $0.cycle0_color_a, $0.cycle0_color_b,
             $0.cycle0_color_c, $0.cycle0_color_d, $0.cycle1_color_a, $0.cycle1_color_b,
             $0.cycle1_color_c, $0.cycle1_color_d]
        }
        expect(!legal.stateWordEvidence.isEmpty, "legal raw state evidence")
        let legalRepeatBuilder: () throws -> GoldenEyeGBISceneBuildResultV6 = {
            try GoldenEyeGBISceneBuilderV6.build(
                model: repeatModel,
                modelName: "legalpage",
                matrices: [
                    try makeMatrix(repeatModelHandle),
                    try makeProjectionMatrix(repeatProjectionHandle),
                ],
                viewports: [try makeViewport()],
                matrixRoles: [
                    try GoldenEyeSourceMatrixRoleSidecarV6(
                        handle: repeatModelHandle,
                        roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView
                    ),
                    try GoldenEyeSourceMatrixRoleSidecarV6(
                        handle: repeatProjectionHandle,
                        roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.projection
                    ),
                ],
                frame: try GoldenEyeGBISceneFrameContextV6(
                    nativeTick: 2,
                    referenceTick: 1,
                    pairPhase: 0,
                    screen: UInt32(GE_SOURCE_FRAME_V6_SCREEN_LEGAL),
                    viewportWidth: 640,
                    viewportHeight: 480
                ),
                textureSetups: legal.textureSetups
            )
        }
        for iteration in 0..<100 {
            let repeated = try legalRepeatBuilder()
            expect(repeated.eventHash == legal.eventHash && repeated.stateHash == legal.stateHash,
                   "legal repeat hash \(iteration)")
            expect(repeated.snapshot.renderStates.flatMap {
                [$0.raw_othermode_h, $0.raw_othermode_l, $0.cycle0_color_a, $0.cycle0_color_b,
                 $0.cycle0_color_c, $0.cycle0_color_d, $0.cycle1_color_a, $0.cycle1_color_b,
                 $0.cycle1_color_c, $0.cycle1_color_d]
            } == legalStateWords, "legal repeat state words \(iteration)")
            expect(repeated.sourceCommandWordHash == legal.sourceCommandWordHash,
                   "legal repeat source words \(iteration)")
            expect(repeated.stateWordEvidence == legal.stateWordEvidence,
                   "legal repeat raw combiner/othermode words \(iteration)")
        }
        print("builder-v6 legal repeat stress: PASS iterations=100")

        // Each decoder draw is copied as three source-indexed vertices.  This
        // catches the classic vertex-cache overwrite hazard: later G_VTX
        // loads may reuse a slot, but earlier triangles must retain their
        // original source vertex values.
        let cacheCase = results["legalpage"]!
        let decoderDraws = cacheCase.decoderDraws
        expect(cacheCase.snapshot.vertices.count == decoderDraws.count * 3, "cache overwrite vertex copies")
        for (index, draw) in decoderDraws.enumerated() {
            let copied = cacheCase.snapshot.vertices[index * 3 ..< index * 3 + 3]
            expect(copied.map(\.source_index) == [draw.source_vertex_a, draw.source_vertex_b, draw.source_vertex_c], "cache overwrite source indices \(index)")
        }
        let legalVertexCoverage = Set(cacheCase.snapshot.vertices.map(\.source_index))
        expect(legalVertexCoverage == Set((0..<24).map(UInt32.init)), "legal split vertex windows cover source indices 0..23")
        expect(cacheCase.snapshot.drawCommands.count <= decoderDraws.count, "consecutive grouping only")
        print("builder-v6 cache-overwrite preservation: PASS triangles=\(decoderDraws.count) groups=\(cacheCase.snapshot.drawCommands.count)")

        let dynamic = try GoldenEyeSourceModelV6.load(data: Data(contentsOf: root.appendingPathComponent("rarewarelogo.gesm")), modelName: "rarewarelogo")
        expectError({
            _ = try GoldenEyeGBISceneBuilderV6.build(
                model: dynamic,
                modelName: "rarewarelogo",
                matrices: [],
                viewports: [],
                frame: try GoldenEyeGBISceneFrameContextV6(nativeTick: 2, referenceTick: 1, pairPhase: 0, screen: UInt32(GE_SOURCE_FRAME_V6_SCREEN_RAREWARE), viewportWidth: 640, viewportHeight: 480)
            )
        }, "dynamic rareware typed gap")

        let resolver = GESourceModelDynamicResolverV6(resolvedModels: ["rarewarelogo"])
        let compilation = GESourceModelCompilerV6.compile(
            dynamic,
            modelName: "rarewarelogo",
            dynamicResolver: resolver
        )
        expect(compilation.status == .complete && compilation.diagnostics.isEmpty,
               "Rareware dynamic source compilation")
        guard let compiledScene = compilation.scene else {
            preconditionFailure("goldeneye_gbi_scene_builder_v6_smoke: missing Rareware scene")
        }
        let setupScene = GoldenEyeGBISceneBuilderV6.rarewareSceneWithOuterSetup(
            model: dynamic,
            scene: compiledScene
        )
        let setupResult = try GoldenEyeSourceTextureSetupResolverV6.resolve(
            modelName: "rarewarelogo",
            model: dynamic,
            catalog: catalog,
            compiledCommands: setupScene.commands
        )
        expect(setupResult.setupHash != 0, "Rareware typed texture setup hash")
            let rarewareModelHandle: UInt32 = 0xF300_0001
            let rarewareProjectionHandle: UInt32 = 0xF102_0200
            let rarewareResolvedScene = GoldenEyeGBIResolvedSceneInputV6(
                scene: setupScene,
                vertexResources: try GoldenEyeGBISceneBuilderV6.vertexResourceOverrides(
                    model: dynamic,
                    scene: setupScene
                ),
                additionalTextureHandles: dynamic.textures.map(\.resourceHandle)
            )
        let rarewareFrame = try GoldenEyeGBISceneFrameContextV6(
            nativeTick: 2,
            referenceTick: 1,
            sourceTimer: 1,
            pairPhase: 0,
            screen: UInt32(GE_SOURCE_FRAME_V6_SCREEN_RAREWARE),
            viewportWidth: 640,
            viewportHeight: 480
        )
        let rarewareResult = try GoldenEyeGBISceneBuilderV6.build(
            model: dynamic,
            modelName: "rarewarelogo",
            matrices: [
                try makeMatrix(rarewareModelHandle),
                try makeProjectionMatrix(rarewareProjectionHandle),
            ],
            viewports: [try makeViewport()],
            matrixRoles: [
                try GoldenEyeSourceMatrixRoleSidecarV6(
                    handle: rarewareModelHandle,
                    roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView
                ),
                try GoldenEyeSourceMatrixRoleSidecarV6(
                    handle: rarewareProjectionHandle,
                    roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.projection
                ),
            ],
                frame: rarewareFrame,
                dynamicResolver: resolver,
                textureSetups: setupResult.setups,
                resolvedScene: rarewareResolvedScene
            )
        expect(rarewareResult.decoderUnsupportedCount == 0,
               "Rareware decoder unsupported")
        expect(rarewareResult.unsupportedVisibleCount == 0,
               "Rareware visible unsupported")
        expect(rarewareResult.projectionConsumption.isComplete,
               "Rareware projection consumption")
        expect(rarewareResult.presentable, "Rareware presentable scene")
        expect(rarewareResult.triangleCount == 268,
               "Rareware source triangle count")
        let rarewareDrawKindMask = UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE) |
            UInt32(GE_SOURCE_DRAW_V6_FLAG_DECAL) |
            UInt32(GE_SOURCE_DRAW_V6_FLAG_TRANSLUCENT)
        expect(rarewareResult.snapshot.drawCommands.allSatisfy {
            ($0.flags & rarewareDrawKindMask) == UInt32(GE_SOURCE_DRAW_V6_FLAG_OPAQUE)
        }, "Rareware PASS/AA opaque draw flags")
        print("builder-v6 rareware: commands=\(rarewareResult.commandCount) triangles=\(rarewareResult.triangleCount) states=\(rarewareResult.decoderStateCount) draws=\(rarewareResult.snapshot.drawCommands.count) resources=\(rarewareResult.resourceCount) unsupported=\(rarewareResult.unsupportedVisibleCount) PASS")

        let legalModel = try GoldenEyeSourceModelV6.load(data: Data(contentsOf: root.appendingPathComponent("legalpage.gesm")), modelName: "legalpage")
        let legalScene = GESourceModelCompilerV6.compile(legalModel, modelName: "legalpage").scene!
        let legalHandle = firstMatrixHandle(legalScene)
        expectError({
            _ = try GoldenEyeGBISceneBuilderV6.build(
                model: legalModel,
                modelName: "legalpage",
                matrices: [try makeMatrix(legalHandle), try makeMatrix(legalHandle)],
                viewports: [],
                frame: try GoldenEyeGBISceneFrameContextV6(nativeTick: 2, referenceTick: 1, pairPhase: 0, screen: UInt32(GE_SOURCE_FRAME_V6_SCREEN_LEGAL), viewportWidth: 640, viewportHeight: 480)
            )
        }, "duplicate matrix handle")
        expectError({
            _ = try GoldenEyeGBISceneBuilderV6.build(
                model: legalModel,
                modelName: "legalpage",
                matrices: [],
                viewports: [],
                frame: try GoldenEyeGBISceneFrameContextV6(nativeTick: 2, referenceTick: 1, pairPhase: 0, screen: UInt32(GE_SOURCE_FRAME_V6_SCREEN_LEGAL), viewportWidth: 640, viewportHeight: 480)
            )
        }, "missing matrix handle")

        var malformedState = GEGBIStateV6()
        malformedState.combine_w0 = 0xfc26_a004
        malformedState.combine_w1 = 0x1f10_93ff
        malformedState.other_mode_h = 1 << 12
        expectError({ try GoldenEyeGBISceneBuilderV6.validateStateForTesting(malformedState) }, "malformed cycle state")

        print("goldeneye_gbi_scene_builder_v6_smoke: PASS")
    }
}
