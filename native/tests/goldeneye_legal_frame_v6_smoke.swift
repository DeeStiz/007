import Foundation

private let root = URL(
    fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/native/source-frontend-v6",
    isDirectory: true
)

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), "goldeneye_legal_frame_v6_smoke: \(message)")
}

@available(macOS 27.0, *)
@main
struct GoldenEyeLegalFrameV6Smoke {
    static func main() throws {
        let frame = try GoldenEyeLegalFrameV6.build(rootURL: root)
        let model = try GoldenEyeSourceModelV6.load(
            from: root.appendingPathComponent("legalpage.gesm")
        )
        check(model.commands.filter { $0.semantic.hasPrefix("rawGfx") }.count == 12, "12 raw Gfx rows")
        check(frame.source.screen == 0, "source screen is Legal")
        check(frame.source.nativeTick == 1 && frame.source.referenceTick == 0, "tick-one paired cadence")
        check(frame.sourceCommandCount == 58, "source GBI command count")
        check(frame.sourceTriangleCount == 12, "source triangle count")
        check(frame.scene.packetCommandCount == 60, "decoder packet command count including bounded root")
        check(frame.scene.packetListCount == 2, "root plus source display list")
        check(frame.scene.packetVertexCount == 24, "source vertex count")
        check(frame.scene.packetImageCount == 5, "source image count")
        check(frame.scene.snapshot.drawCommands.count == 6, "primitive plus five source material draw groups")
        check(frame.scene.snapshot.renderStates.count == 6, "primitive plus five source material states")
        check(frame.scene.stateWordEvidence.count == 6, "material state evidence")
        check(frame.scene.sourceTriangleSlotCount == 12, "source triangle slot count")
        check(frame.scene.snapshot.diagnostics.isEmpty, "zero visible scene diagnostics")
        check(frame.scene.decoderUnsupportedCount == 0, "zero decoder unsupported commands")
        check(frame.scene.unsupportedVisibleCount == 0, "zero unsupported visible commands")
        check(frame.scene.presentable, "scene is presentable")
        check(frame.modelTextureHandles.count == 5, "all five source texture handles")
        check(frame.materialTextureHandles.first == 0, "source primitive material remains first")
        check(Set(frame.materialTextureHandles.dropFirst()).count == 5, "five textured material changes survive lowering")
        check(frame.text.sourceEvents.count == 12, "all twelve source text events")
        check(frame.text.glyphs.count > 100, "source Zurich glyph packet is non-empty")
        check(frame.text.sourceEvents.map(\.textID) == Array(7...18), "text event source order")
        check(Set(frame.text.glyphs.map(\.stringID)) == Set(7...18), "glyph packet string IDs")
        check(frame.text.glyphs.allSatisfy { $0.fontID == 1 }, "Zurich Bold font for Legal")
        check(frame.text.sourceEventHash != 0 && frame.text.glyphPacketHash != 0, "text hashes")
        check(frame.viewport.values == [
            220 << 16, 165 << 16, 65_536, 65_536,
            220 << 16, 165 << 16, 0, 65_536,
        ], "source 440x330 viewport values")
        check(frame.sourceMatrices.count == 4, "model/camera/projection/reflection matrices")
        check(frame.sourceMatrices.contains {
            $0.roleFlags & GoldenEyeSourceMatrixRoleSidecarV6.projection != 0
        }, "source projection matrix")
        check(frame.projectionConsumption.isComplete, "projection consumption closure")
        check(frame.projectionConsumption.consumedDrawCount == frame.projectionConsumption.requiredDrawCount, "all Legal draws consume projection")
        let sourceVertexIDsByDraw = frame.scene.snapshot.drawCommands.map { draw in
            let first = Int(draw.first_vertex)
            let end = first + Int(draw.vertex_count)
            return Array(frame.scene.snapshot.vertices[first..<end]).map(\.source_index)
        }
        check(
            sourceVertexIDsByDraw == [
                [0, 1, 2, 0, 2, 3],
                [4, 5, 6, 4, 6, 7],
                [8, 9, 10, 8, 10, 11],
                [12, 13, 14, 12, 14, 15],
                [16, 17, 18, 16, 18, 19],
                [20, 21, 22, 20, 22, 23],
            ],
            "source G_VTX cache loads preserve both Legal vertex groups"
        )
        check(frame.matrix.values[14] == -4000 << 16, "source look-at translation")
        check(frame.logicalWidth == 440 && frame.logicalHeight == 330, "logical 440x330 canvas")
        check(frame.frameHash != 0, "complete Legal frame hash")

        let renderOrder = frame.source.renderEvents.map { String($0.operation) }.joined(separator: ",")
        let textOrder = frame.text.sourceEvents.map { String($0.textID) }.joined(separator: ",")
        let textCoordinates = frame.text.sourceEvents.map { event in
            "\(event.x),\(event.y)"
        }.joined(separator: ";")
        let sourceTextures = frame.modelTextureHandles.map { handle in
            String(format: "0x%08x", handle)
        }.joined(separator: ",")
        let materialTextures = frame.materialTextureHandles.map { handle in
            String(format: "0x%08x", handle)
        }.joined(separator: ",")
        let stateSignatures = frame.scene.snapshot.renderStates.map { state in
            let color = [
                state.cycle0_color_a, state.cycle0_color_b,
                state.cycle0_color_c, state.cycle0_color_d,
                state.cycle1_color_a, state.cycle1_color_b,
                state.cycle1_color_c, state.cycle1_color_d,
            ].map(String.init).joined(separator: ",")
            let alpha = [
                state.cycle0_alpha_a, state.cycle0_alpha_b,
                state.cycle0_alpha_c, state.cycle0_alpha_d,
                state.cycle1_alpha_a, state.cycle1_alpha_b,
                state.cycle1_alpha_c, state.cycle1_alpha_d,
            ].map(String.init).joined(separator: ",")
            return "state=\(state.state_handle):material=\(state.material_handle):cycle=\(state.combiner_cycle_count):color=\(color):alpha=\(alpha):combine=0x\(String(state.raw_othermode_h, radix: 16))/0x\(String(state.raw_othermode_l, radix: 16))"
        }.joined(separator: ";")
        let manifest = [
            "screen=Legal",
            "native_tick=\(frame.source.nativeTick)",
            "reference_tick=\(frame.source.referenceTick)",
            "source_state_hash=\(frame.source.stateHash)",
            "source_text_hash=\(frame.source.textHash)",
            "source_render_hash=\(frame.source.renderHash)",
            "source_render_order=\(renderOrder)",
            "source_text_order=\(textOrder)",
            "source_text_coordinates=\(textCoordinates)",
            "source_model_packet_sha256=\(GoldenEyeLegalFrameV6.legalModelPacketSHA256)",
            "source_gbi_commands=\(frame.sourceCommandCount)",
            "source_triangles=\(frame.sourceTriangleCount)",
            "source_texture_handles=\(sourceTextures)",
            "lowered_material_handles=\(materialTextures)",
            "source_vertex_ids_by_draw=\(sourceVertexIDsByDraw.map { $0.map(String.init).joined(separator: ",") }.joined(separator: ";"))",
            "state_signatures=\(stateSignatures)",
            "glyph_count=\(frame.text.glyphs.count)",
            "source_text_event_hash=\(frame.text.sourceEventHash)",
            "glyph_packet_hash=\(frame.text.glyphPacketHash)",
            "unsupported_visible_commands=\(frame.scene.unsupportedVisibleCount)",
            "unsupported_decoder_commands=\(frame.scene.decoderUnsupportedCount)",
            "logical_canvas=\(frame.logicalWidth)x\(frame.logicalHeight)",
            "source_viewport=440x330",
            "source_viewport_scale=\(frame.viewport.values[0] >> 16)x\(frame.viewport.values[1] >> 16)",
            "reference_viewport=320x240",
            "projection_handle=0x\(String(frame.projectionConsumption.sourceProjectionHandle, radix: 16))",
            "projection_consumption=\(frame.projectionConsumption.consumedDrawCount)/\(frame.projectionConsumption.requiredDrawCount)",
            "frame_hash=\(frame.frameHash)",
        ].joined(separator: "\n") + "\n"
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().dropFirst().first ?? "build/native/legal-frame-v6/legal-frame-manifest.txt")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manifest.write(to: output, atomically: true, encoding: .utf8)
        print(manifest, terminator: "")
        print("goldeneye_legal_frame_v6_smoke: PASS")
    }
}
