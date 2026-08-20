import Foundation

@main
struct GoldenEyeSourceSceneReferenceCaptureV6Smoke {
    static func main() {
        let evidence = GoldenEyeSourceSceneRenderEvidenceV6(
            frameIndex: 7,
            nativeTick: 14,
            drawCount: 3,
            triangleCount: 12,
            copiedRecordAggregateHash: 0x1234,
            pipelineKeyHashes: [0x55, 0xaa],
            slotIndex: 1,
            signalValue: 8
        )
        let bytes = Data(repeating: 0x5a, count: 320 * 240 * 4)
        let capture = GoldenEyeSourceSceneReferenceCaptureV6(
            width: 320,
            height: 240,
            bytesPerRow: 320 * 4,
            pixelFormat: "bgra8Unorm",
            bytes: bytes,
            evidence: evidence,
            captureURL: nil,
            pngURL: nil,
            rawSHA256: ""
        )
        precondition(capture.width == 320)
        precondition(capture.height == 240)
        precondition(capture.bytesPerRow == 1_280)
        precondition(capture.pixelFormat == "bgra8Unorm")
        precondition(capture.bytes.count == 307_200)
        precondition(capture.evidence.nativeTick == 14)
        precondition(capture.captureURL == nil)

        let twoPixelBGRA = Data([0x11, 0x22, 0x33, 0xff, 0x44, 0x55, 0x66, 0xff])
        let twoPixelPNG = try! GoldenEyeReferenceCaptureCodecV6.encodePNG(
            bgra8: twoPixelBGRA,
            width: 2,
            height: 1,
            bytesPerRow: 8
        )
        let decodedTwoPixel = try! GoldenEyeReferenceCaptureCodecV6.decodePNG(twoPixelPNG)
        precondition(decodedTwoPixel.width == 2)
        precondition(decodedTwoPixel.height == 1)
        precondition(decodedTwoPixel.bgra8 == twoPixelBGRA)

        var referenceBGRA = Data(repeating: 0, count: 320 * 240 * 4)
        for row in 0..<240 {
            for column in 0..<320 {
                let offset = (row * 320 + column) * 4
                referenceBGRA[offset + 0] = 0x10
                referenceBGRA[offset + 1] = 0x20
                referenceBGRA[offset + 2] = 0x30
                referenceBGRA[offset + 3] = 0xff
            }
        }
        let referencePNG = try! GoldenEyeReferenceCaptureCodecV6.encodePNG(
            bgra8: referenceBGRA,
            width: 320,
            height: 240,
            bytesPerRow: 320 * 4
        )
        let decodedReference = try! GoldenEyeReferenceCaptureCodecV6.decodePNG(referencePNG)
        precondition(decodedReference.width == 320)
        precondition(decodedReference.height == 240)
        precondition(decodedReference.bytesPerRow == 320 * 4)
        precondition(decodedReference.bgra8.count == 320 * 240 * 4)
        precondition(decodedReference.bgra8[0] == 0x10)
        precondition(decodedReference.bgra8[1] == 0x20)
        precondition(decodedReference.bgra8[2] == 0x30)
        precondition(decodedReference.bgra8[3] == 0xff)

        let layout = GoldenEyeFidelityLayout(
            mode: .reference320x240,
            drawableWidth: 2_560,
            drawableHeight: 1_440
        )
        precondition(layout.outputWidth == 320)
        precondition(layout.outputHeight == 240)
        precondition(layout.scale == 320.0 / 440.0)
        precondition(layout.sourceToOutput(.init(x: 440, y: 330)) == .init(x: 320, y: 240))
        print("goldeneye_source_scene_reference_capture_v6_smoke: PASS")
    }
}
