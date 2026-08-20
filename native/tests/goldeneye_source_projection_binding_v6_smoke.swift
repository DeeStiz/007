#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif
import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), "goldeneye_source_projection_binding_v6_smoke: (message)")
}

private func identityQ16() -> [Int32] {
    var values = Array(repeating: Int32(0), count: 16)
    values[0] = 65_536
    values[5] = 65_536
    values[10] = 65_536
    values[15] = 65_536
    return values
}

private func viewportQ16() -> [Int32] {
    [160 << 16, 120 << 16, 1 << 16, 1 << 16,
     160 << 16, 120 << 16, 0, 1 << 16]
}

@main
struct GoldenEyeSourceProjectionBindingV6Smoke {
    static func main() throws {
        let modelHandle: UInt32 = 0xF100_0100
        let projectionHandle: UInt32 = 0xF100_0200
        let viewportHandle: UInt32 = 0xF100_0001
        let inputs = try GoldenEyeSourceProjectionClipInputsV6(
            modelViewHandle: modelHandle,
            projectionHandle: projectionHandle,
            viewportHandle: viewportHandle,
            modelViewQ16: identityQ16(),
            projectionQ16: identityQ16(),
            viewportQ16: viewportQ16()
        )
        let result = GoldenEyeSourceProjectionClipResultV6(inputs: inputs)
        let center = try GoldenEyeSourceProjectionBindingV6.apply(
            matrixQ16: result.clipMatrixQ16,
            pointQ16: (0, 0, 0)
        )
        expect(center.x == 0 && center.y == 0, "center xy")
        expect(center.z == 32_768 && center.w == 65_536, "symmetric depth center maps to half")

        let near = try GoldenEyeSourceProjectionBindingV6.apply(
            matrixQ16: result.clipMatrixQ16,
            pointQ16: (0, 0, -65_536)
        )
        let far = try GoldenEyeSourceProjectionBindingV6.apply(
            matrixQ16: result.clipMatrixQ16,
            pointQ16: (0, 0, 65_536)
        )
        expect(near.z == 0 && near.w == 65_536, "near -w maps to Metal zero")
        expect(far.z == 65_536 && far.w == 65_536, "far +w maps to Metal +w")

        // Non-commuting source fixture: column-major translation lives at
        // indices 12...14, and projection scale must be applied before the
        // y/depth adapter.  This catches an accidental row-major transpose.
        var translatedModel = identityQ16()
        translatedModel[12] = 2 * 65_536
        translatedModel[13] = 3 * 65_536
        translatedModel[14] = 4 * 65_536
        var scaledProjection = identityQ16()
        scaledProjection[0] = 2 * 65_536
        scaledProjection[5] = 3 * 65_536
        let translatedInputs = try GoldenEyeSourceProjectionClipInputsV6(
            modelViewHandle: modelHandle,
            projectionHandle: projectionHandle,
            viewportHandle: viewportHandle,
            modelViewQ16: translatedModel,
            projectionQ16: scaledProjection,
            viewportQ16: viewportQ16()
        )
        let translated = try GoldenEyeSourceProjectionBindingV6.apply(
            matrixQ16: GoldenEyeSourceProjectionClipResultV6(inputs: translatedInputs).clipMatrixQ16,
            pointQ16: (0, 0, 0)
        )
        expect(translated.x == 4 * 65_536 && translated.y == 9 * 65_536,
               "column-major source matrix composition")
        expect(translated.z == 5 * 32_768 && translated.w == 65_536,
               "column-major source depth composition")

        let leftBottom = try GoldenEyeSourceProjectionBindingV6.viewportToMetalNDC(
            ndcXQ16: -65_536,
            ndcYQ16: -65_536,
            viewportQ16: viewportQ16()
        )
        let rightTop = try GoldenEyeSourceProjectionBindingV6.viewportToMetalNDC(
            ndcXQ16: 65_536,
            ndcYQ16: 65_536,
            viewportQ16: viewportQ16()
        )
        expect(leftBottom.x == -65_536 && leftBottom.y == 65_536, "source top-left viewport orientation")
        expect(rightTop.x == 65_536 && rightTop.y == -65_536, "source bottom-right viewport orientation")

        // Source Legal triangle order (-1,-1), (+1,-1), (0,+1) remains in
        // the source-declared orientation at the top-left Metal viewport.
        // The renderer must select that front-face convention explicitly; it
        // must not rely on Metal's default.
        let a = try GoldenEyeSourceProjectionBindingV6.apply(
            matrixQ16: result.clipMatrixQ16,
            pointQ16: (-65_536, -65_536, 0)
        )
        let b = try GoldenEyeSourceProjectionBindingV6.apply(
            matrixQ16: result.clipMatrixQ16,
            pointQ16: (65_536, -65_536, 0)
        )
        let c = try GoldenEyeSourceProjectionBindingV6.apply(
            matrixQ16: result.clipMatrixQ16,
            pointQ16: (0, 65_536, 0)
        )
        let area = (Int64(b.x) - Int64(a.x)) * (Int64(c.y) - Int64(a.y))
            - (Int64(b.y) - Int64(a.y)) * (Int64(c.x) - Int64(a.x))
        expect(area > 0, "canonical Legal triangle source orientation")

        let roles = try GoldenEyeSourceProjectionBindingV6.roleMap([
            try GoldenEyeSourceMatrixRoleSidecarV6(
                handle: modelHandle,
                roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.modelView
            ),
            try GoldenEyeSourceMatrixRoleSidecarV6(
                handle: projectionHandle,
                roleFlags: GoldenEyeSourceMatrixRoleSidecarV6.projection
            ),
        ])
        expect(roles[modelHandle] == GoldenEyeSourceMatrixRoleSidecarV6.modelView, "explicit modelview role")
        expect(roles[projectionHandle] == GoldenEyeSourceMatrixRoleSidecarV6.projection, "explicit projection role")

        var transform = try GoldenEyeSourceProjectionBindingV6.makeTransform(
            handle: 0xAA00_0001,
            inputs: inputs
        )
        expect(transform.transform_kind == UInt32(GE_SOURCE_TRANSFORM_V6_CLIP_COMPOSITE), "clip kind")
        expect(transform.flags & UInt32(GE_SOURCE_TRANSFORM_V6_FLAG_CLIP_COMPOSITE) != 0, "clip flag")
        expect(transform.parent_handle == modelHandle, "modelview provenance")
        expect(transform.source_node == projectionHandle, "projection provenance")
        expect(transform.viewport_id == viewportHandle, "viewport provenance")
        expect(ge_source_scene_v6_validate_transform(&transform) == GE_STATUS_OK, "clip transform validation")
        let transformHash = ge_source_scene_v6_hash_transform(&transform)
        expect(transformHash != 0, "clip transform hash")
        var changedTransform = transform
        changedTransform.matrix_q16.0 &+= 1
        expect(ge_source_scene_v6_hash_transform(&changedTransform) != transformHash,
               "clip transform hash includes exact matrix")
        var malformedComposite = transform
        malformedComposite.viewport_id = 0
        expect(ge_source_scene_v6_validate_transform(&malformedComposite) != GE_STATUS_OK,
               "clip transform rejects missing viewport provenance")

        var changedProjection = identityQ16()
        changedProjection[0] = 65_537
        let changedInputs = try GoldenEyeSourceProjectionClipInputsV6(
            modelViewHandle: modelHandle,
            projectionHandle: projectionHandle,
            viewportHandle: viewportHandle,
            modelViewQ16: identityQ16(),
            projectionQ16: changedProjection,
            viewportQ16: viewportQ16()
        )
        let odd = GoldenEyeSourceProjectionClipResultV6(inputs: changedInputs)
        expect(result.sourceHash != odd.sourceHash, "even/odd source matrix hash distinction")
        expect(result.sourceHash == GoldenEyeSourceProjectionClipResultV6(inputs: inputs).sourceHash, "stable source matrix hash")

        var invertedViewport = viewportQ16()
        invertedViewport[1] = -invertedViewport[1]
        do {
            _ = try GoldenEyeSourceProjectionClipInputsV6(
                modelViewHandle: modelHandle,
                projectionHandle: projectionHandle,
                viewportHandle: viewportHandle,
                modelViewQ16: identityQ16(),
                projectionQ16: identityQ16(),
                viewportQ16: invertedViewport
            )
            preconditionFailure("negative source viewport scale must fail closed")
        } catch let error as GoldenEyeSourceProjectionBindingV6Error {
            expect(error == .invalidViewportOrientation, "negative source viewport orientation rejection")
        }

        print("goldeneye_source_projection_binding_v6_smoke: PASS hash=\(String(result.sourceHash, radix: 16)) near=\(near.z) far=\(far.z)")
    }
}
