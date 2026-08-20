@main
struct GoldenEyeProjectionV10Smoke {
    private static let q16 = Int32(65_536)

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            preconditionFailure("goldeneye_projection_v10_smoke: " + message)
        }
    }

    private static func nearlyEqual(_ lhs: Int32, _ rhs: Int32, tolerance: Int32 = 1) -> Bool {
        let difference = Int64(lhs) - Int64(rhs)
        return difference >= -Int64(tolerance) && difference <= Int64(tolerance)
    }

    static func main() {
        expect(MemoryLayout<GoldenEyeProjectionV10.PointQ16>.size == 12, "point fixed width")
        expect(MemoryLayout<GoldenEyeProjectionV10.MatrixQ16>.size == 64, "matrix fixed width")
        expect(MemoryLayout<GoldenEyeProjectionV10.ViewportV10>.size == 48, "viewport fixed width")
        expect(MemoryLayout<GoldenEyeProjectionV10.ClipVertexV10>.size == 48, "clip vertex fixed width")
        expect(MemoryLayout<GoldenEyeProjectionV10.TriangleResultV10>.size == 40, "triangle fixed width")

        guard let canonical = GoldenEyeProjectionV10.ViewportV10(
            drawableWidth: 440, drawableHeight: 330
        ) else {
            preconditionFailure("canonical viewport construction")
        }
        expect(canonical.isCanonical, "canonical viewport flag")
        expect(!canonical.isWidescreen && !canonical.isLetterboxed, "canonical aspect flags")
        expect(canonical.scaleNumerator == 330 && canonical.scaleDenominator == 330,
               "canonical rational scale")
        expect(canonical.logicalWidthQ16 == 440 * q16 && canonical.logicalHeightQ16 == 330 * q16,
               "canonical logical dimensions")
        expect(canonical.gutterXQ16 == 0 && canonical.gutterYQ16 == 0, "canonical gutters")

        let canonicalPoint = GoldenEyeProjectionV10.PointQ16(x: 123 * q16 + 0x4000,
                                                              y: 98 * q16 + 0x8000,
                                                              z: 7 * q16)
        let canonicalDrawable = canonical.sourceToDrawable(canonicalPoint)
        expect(canonicalDrawable == canonicalPoint, "4:3 identity transform")
        expect(canonical.drawableToSource(canonicalDrawable) == canonicalPoint,
               "4:3 inverse transform")

        guard let wide = GoldenEyeProjectionV10.ViewportV10(
            drawableWidth: 1_920, drawableHeight: 1_080
        ) else {
            preconditionFailure("wide viewport construction")
        }
        expect(wide.isWidescreen && !wide.isCanonical, "wide viewport flag")
        let wideLeft = wide.sourceToDrawable(.fromInteger(0, 0, 0))
        let wideRight = wide.sourceToDrawable(.fromInteger(440, 330, 0))
        expect(nearlyEqual(wideLeft.x, 240 * q16), "widescreen left edge")
        expect(nearlyEqual(wideLeft.y, 0), "widescreen top edge")
        expect(nearlyEqual(wideRight.x, 1_680 * q16), "widescreen right edge")
        expect(nearlyEqual(wideRight.y, 1_080 * q16), "widescreen bottom edge")
        let widePoint = GoldenEyeProjectionV10.PointQ16(x: 211 * q16 + 0x1234,
                                                         y: 87 * q16 + 0x3456,
                                                         z: 0)
        let wideRoundTrip = wide.drawableToSource(wide.sourceToDrawable(widePoint))
        expect(nearlyEqual(wideRoundTrip.x, widePoint.x, tolerance: 2),
               "widescreen inverse x")
        expect(nearlyEqual(wideRoundTrip.y, widePoint.y, tolerance: 2),
               "widescreen inverse y")

        guard let narrow = GoldenEyeProjectionV10.ViewportV10(
            drawableWidth: 320, drawableHeight: 260
        ) else {
            preconditionFailure("narrow viewport construction")
        }
        expect(narrow.isLetterboxed, "narrow letterbox flag")
        let narrowTop = narrow.sourceToDrawable(.fromInteger(0, 0, 0))
        expect(nearlyEqual(narrowTop.x, 0), "narrow left edge")
        expect(narrowTop.y > 0, "narrow top letterbox")
        expect(nearlyEqual(narrow.drawableToSource(narrowTop).x, 0), "narrow inverse x")

        var integerPart = SIMD16<Int16>(repeating: 0)
        var fractionPart = SIMD16<UInt16>(repeating: 0)
        integerPart[0] = 1
        integerPart[5] = 1
        integerPart[10] = 1
        integerPart[15] = 1
        integerPart[3] = 2
        integerPart[7] = -3
        fractionPart[3] = 0x8000
        fractionPart[7] = 0x4000
        let sourceMatrix = GoldenEyeProjectionV10.SourceMatrixV10(
            integerPart: integerPart,
            fractionPart: fractionPart
        )
        let quantized = sourceMatrix.quantizedMatrix()
        expect(quantized.values[0] == q16 && quantized.values[5] == q16 &&
               quantized.values[10] == q16 && quantized.values[15] == q16,
               "source identity quantization")
        expect(quantized.values[1] == 0 && quantized.values[2] == 0 &&
               quantized.values[4] == 0 && quantized.values[6] == 0,
               "source matrix zero quantization")
        expect(quantized.values[3] == 2 * q16 + 0x8000, "source positive translation quantization")
        expect(quantized.values[7] == -3 * q16 + 0x4000, "source negative translation quantization")

        guard let packet = GoldenEyeProjectionV10.PacketV10(
            viewport: canonical,
            modelView: .identity,
            projection: .identity,
            cullMode: GoldenEyeProjectionV10.cullBack
        ) else {
            preconditionFailure("packet construction")
        }
        expect(packet.isValid, "packet validity")
        expect(packet.abiVersion == GoldenEyeProjectionV10.abiVersion,
               "packet ABI envelope")
        expect(packet.contractVersion == GoldenEyeProjectionV10.contractVersion,
               "packet contract version")
        expect(packet.reserved0 == 0 && packet.reserved1 == 0, "packet reserved fields")
        expect(packet.flags & GoldenEyeProjectionV10.packetBackfaceCulling != 0,
               "packet culling flag")
        expect(packet.packetHash == 15_192_084_148_729_639_549,
               "packet deterministic hash")

        let visible = packet.transform(.fromInteger(0, 0, 0))
        expect(visible.clipFlags == 0, "visible clip flags")
        expect(visible.drawableXQ16 == 220 * q16 && visible.drawableYQ16 == 165 * q16,
               "canonical viewport center")
        expect(visible.ndcZQ16 == 0, "center depth")

        let outside = packet.transform(.fromInteger(2, 0, 0))
        expect(outside.clipFlags & GoldenEyeProjectionV10.clipRight != 0,
               "right clip flag")

        var translatedValues = GoldenEyeProjectionV10.MatrixQ16.identity.values
        translatedValues[3] = q16
        guard let translatedPacket = GoldenEyeProjectionV10.PacketV10(
            viewport: canonical,
            modelView: GoldenEyeProjectionV10.MatrixQ16(values: translatedValues),
            projection: .identity
        ) else {
            preconditionFailure("translated packet construction")
        }
        let translated = translatedPacket.transform(.fromInteger(0, 0, 0))
        expect(translated.clipXQ16 == q16 && translated.ndcXQ16 == q16,
               "modelview translation")

        var zeroWValues = GoldenEyeProjectionV10.MatrixQ16.identity.values
        zeroWValues[15] = 0
        guard let zeroWPacket = GoldenEyeProjectionV10.PacketV10(
            viewport: canonical,
            modelView: .identity,
            projection: GoldenEyeProjectionV10.MatrixQ16(values: zeroWValues)
        ) else {
            preconditionFailure("zero-W packet construction")
        }
        let invalidW = zeroWPacket.transform(.fromInteger(0, 0, 0))
        expect(invalidW.clipFlags & GoldenEyeProjectionV10.clipBehind != 0 &&
               invalidW.clipFlags & GoldenEyeProjectionV10.clipInvalidW != 0,
               "invalid W clip flags")

        let frontTriangle = packet.classifyTriangle(
            .fromInteger(-1, -1, 0), .fromInteger(1, -1, 0), .fromInteger(0, 1, 0)
        )
        expect(frontTriangle.faceFlags & GoldenEyeProjectionV10.faceFront != 0,
               "front-face classification")
        expect(frontTriangle.faceFlags & GoldenEyeProjectionV10.faceCulled == 0,
               "front face survives back-face culling")
        expect(frontTriangle.clipOrFlags == 0 && frontTriangle.clipAndFlags == 0,
               "front triangle clip state")

        guard let frontCullPacket = GoldenEyeProjectionV10.PacketV10(
            viewport: canonical,
            modelView: .identity,
            projection: .identity,
            cullMode: GoldenEyeProjectionV10.cullFront
        ) else {
            preconditionFailure("front cull packet construction")
        }
        let culled = frontCullPacket.classifyTriangle(
            .fromInteger(-1, -1, 0), .fromInteger(1, -1, 0), .fromInteger(0, 1, 0)
        )
        expect(culled.faceFlags & GoldenEyeProjectionV10.faceCulled != 0,
               "front-face culling")

        let degenerate = packet.classifyTriangle(
            .fromInteger(0, 0, 0), .fromInteger(1, 1, 0), .fromInteger(2, 2, 0)
        )
        expect(degenerate.faceFlags & GoldenEyeProjectionV10.faceDegenerate != 0,
               "degenerate triangle")

        let rejected = packet.classifyTriangle(
            .fromInteger(2, 0, 0), .fromInteger(2, 1, 0), .fromInteger(2, -1, 0)
        )
        expect(rejected.faceFlags & GoldenEyeProjectionV10.faceClipRejected != 0,
               "fully rejected triangle")

        print("goldeneye_projection_v10_smoke: PASS size=\(GoldenEyeProjectionV10.PacketV10.fixedSize) hash=\(packet.packetHash) wideGutter=\(wide.gutterXQ16)")
    }
}
