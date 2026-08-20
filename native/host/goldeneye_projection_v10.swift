/// Additive M10 projection/modelview contract.
///
/// This file deliberately stays independent of GETP/GETN and of the frozen
/// V1–V4 records.  It is the value-only seam that title and stage packets can
/// attach later: matrices use the source's signed s15.16 representation,
/// viewport mapping is rational and integer-rounded, and clip/cull decisions
/// are recorded as fixed-width flags.  No source pointer, host address,
/// object reference, or Metal object is retained here.
@frozen public enum GoldenEyeProjectionV10 {
    public static let abiVersion: UInt32 = 1
    public static let contractVersion: UInt32 = 10
    public static let q16One: Int64 = 65_536
    public static let canonicalWidth: UInt32 = 440
    public static let canonicalHeight: UInt32 = 330

    public static let cullNone: UInt32 = 0
    public static let cullFront: UInt32 = 1
    public static let cullBack: UInt32 = 2

    public static let clipLeft: UInt32 = 1 << 0
    public static let clipRight: UInt32 = 1 << 1
    public static let clipBottom: UInt32 = 1 << 2
    public static let clipTop: UInt32 = 1 << 3
    public static let clipNear: UInt32 = 1 << 4
    public static let clipFar: UInt32 = 1 << 5
    public static let clipBehind: UInt32 = 1 << 6
    public static let clipInvalidW: UInt32 = 1 << 7

    public static let faceFront: UInt32 = 1 << 0
    public static let faceBack: UInt32 = 1 << 1
    public static let faceDegenerate: UInt32 = 1 << 2
    public static let faceCulled: UInt32 = 1 << 3
    public static let faceClipPartial: UInt32 = 1 << 4
    public static let faceClipRejected: UInt32 = 1 << 5
    public static let faceInvalidW: UInt32 = 1 << 6

    public static let viewportCanonical: UInt32 = 1 << 0
    public static let viewportWidescreen: UInt32 = 1 << 1
    public static let viewportLetterboxed: UInt32 = 1 << 2

    public static let packetSourceMatrixQuantized: UInt32 = 1 << 0
    public static let packetSixPlaneClip: UInt32 = 1 << 1
    public static let packetAdaptiveViewport: UInt32 = 1 << 2
    public static let packetBackfaceCulling: UInt32 = 1 << 3

    /// A signed Q16.16 point.  The type is fixed-width (12 bytes) and has no
    /// reference-backed members, so it is safe to copy into a packet API.
    @frozen public struct PointQ16: Sendable, Equatable {
        public let x: Int32
        public let y: Int32
        public let z: Int32

        public init(x: Int32, y: Int32, z: Int32) {
            self.x = x
            self.y = y
            self.z = z
        }

        public static func fromInteger(_ x: Int32, _ y: Int32, _ z: Int32) -> Self {
            Self(
                x: saturatingInt32(Int64(x) * q16One),
                y: saturatingInt32(Int64(y) * q16One),
                z: saturatingInt32(Int64(z) * q16One)
            )
        }
    }

    /// A row-major matrix with source-compatible Q16.16 elements.  SIMD16 is
    /// a fixed-width standard-library value, not a heap-backed collection.
    @frozen public struct MatrixQ16: Sendable, Equatable {
        public let values: SIMD16<Int32>

        public init(values: SIMD16<Int32>) {
            self.values = values
        }

        public static var identity: Self {
            var values = SIMD16<Int32>(repeating: 0)
            values[0] = 65_536
            values[5] = 65_536
            values[10] = 65_536
            values[15] = 65_536
            return Self(values: values)
        }

        public subscript(row: Int, column: Int) -> Int32 {
            values[row * 4 + column]
        }

        public static func multiplied(_ left: Self, _ right: Self) -> Self {
            var result = SIMD16<Int32>(repeating: 0)
            for row in 0..<4 {
                for column in 0..<4 {
                    var accumulator: Int64 = 0
                    for element in 0..<4 {
                        let product = Int64(left[row, element]) * Int64(right[element, column])
                        accumulator = saturatingAdd(accumulator, product)
                    }
                    result[row * 4 + column] = quantizedProduct(accumulator)
                }
            }
            return Self(values: result)
        }

        public func applying(to point: PointQ16) -> (x: Int32, y: Int32, z: Int32, w: Int32) {
            let input = [point.x, point.y, point.z, Int32(q16One)]
            var output = (x: Int32(0), y: Int32(0), z: Int32(0), w: Int32(0))
            for row in 0..<4 {
                var accumulator: Int64 = 0
                for column in 0..<4 {
                    let product = Int64(self[row, column]) * Int64(input[column])
                    accumulator = saturatingAdd(accumulator, product)
                }
                let value = quantizedProduct(accumulator)
                switch row {
                case 0: output.x = value
                case 1: output.y = value
                case 2: output.z = value
                default: output.w = value
                }
            }
            return output
        }
    }

    /// The source Mtx stores sixteen signed integer halves and sixteen
    /// unsigned fractional halves.  Packing those halves here is the
    /// quantization boundary; runtime code never receives the source address.
    @frozen public struct SourceMatrixV10: Sendable, Equatable {
        public let packedQ16: SIMD16<Int32>

        public init(integerPart: SIMD16<Int16>, fractionPart: SIMD16<UInt16>) {
            var packed = SIMD16<Int32>(repeating: 0)
            for index in 0..<16 {
                let integral = Int32(integerPart[index])
                let fraction = Int32(fractionPart[index])
                packed[index] = (integral << 16) | fraction
            }
            self.packedQ16 = packed
        }

        public init(packedQ16: SIMD16<Int32>) {
            self.packedQ16 = packedQ16
        }

        public func quantizedMatrix() -> MatrixQ16 {
            MatrixQ16(values: packedQ16)
        }
    }

    /// Rational viewport state.  The numerator/denominator fields preserve
    /// the source aspect calculation without a floating-point dependency;
    /// Q16 fields are rounded only at the fixed-width packet boundary.
    @frozen public struct ViewportV10: Sendable, Equatable {
        public let drawableWidth: UInt32
        public let drawableHeight: UInt32
        public let scaleNumerator: UInt32
        public let scaleDenominator: UInt32
        public let logicalWidthQ16: Int32
        public let logicalHeightQ16: Int32
        public let gutterXQ16: Int32
        public let gutterYQ16: Int32
        public let originXQ16: Int32
        public let originYQ16: Int32
        public let flags: UInt32
        public let reserved: UInt32

        public static let fixedMaximumDimension: UInt32 = 16_384

        public init?(drawableWidth: UInt32, drawableHeight: UInt32) {
            guard drawableWidth > 0, drawableHeight > 0,
                  drawableWidth <= Self.fixedMaximumDimension,
                  drawableHeight <= Self.fixedMaximumDimension else {
                return nil
            }

            let sourceCross = Int64(drawableWidth) * Int64(canonicalHeight)
            let targetCross = Int64(drawableHeight) * Int64(canonicalWidth)
            let isWideOrCanonical = sourceCross >= targetCross
            let numerator = isWideOrCanonical ? drawableHeight : drawableWidth
            let denominator = isWideOrCanonical ? canonicalHeight : canonicalWidth
            let logicalWidth: Int32
            let logicalHeight: Int32
            let gutterX: Int32
            let gutterY: Int32

            if isWideOrCanonical {
                logicalWidth = saturatingInt32(roundDivide(
                    Int64(drawableWidth) * Int64(canonicalHeight) * q16One,
                    Int64(drawableHeight)
                ))
                logicalHeight = saturatingInt32(Int64(canonicalHeight) * q16One)
                gutterX = saturatingInt32((Int64(logicalWidth) - Int64(canonicalWidth) * q16One) / 2)
                gutterY = 0
            } else {
                logicalWidth = saturatingInt32(Int64(canonicalWidth) * q16One)
                logicalHeight = saturatingInt32(roundDivide(
                    Int64(drawableHeight) * Int64(canonicalWidth) * q16One,
                    Int64(drawableWidth)
                ))
                gutterX = 0
                gutterY = saturatingInt32((Int64(logicalHeight) - Int64(canonicalHeight) * q16One) / 2)
            }

            var viewportFlags: UInt32 = 0
            if drawableWidth == canonicalWidth && drawableHeight == canonicalHeight {
                viewportFlags |= viewportCanonical
            } else if isWideOrCanonical {
                viewportFlags |= viewportWidescreen
            } else {
                viewportFlags |= viewportLetterboxed
            }

            self.drawableWidth = drawableWidth
            self.drawableHeight = drawableHeight
            self.scaleNumerator = numerator
            self.scaleDenominator = denominator
            self.logicalWidthQ16 = logicalWidth
            self.logicalHeightQ16 = logicalHeight
            self.gutterXQ16 = gutterX
            self.gutterYQ16 = gutterY
            self.originXQ16 = 0
            self.originYQ16 = 0
            self.flags = viewportFlags
            self.reserved = 0
        }

        public var isCanonical: Bool { (flags & viewportCanonical) != 0 }
        public var isWidescreen: Bool { (flags & viewportWidescreen) != 0 }
        public var isLetterboxed: Bool { (flags & viewportLetterboxed) != 0 }

        /// Maps canonical source/UI units to backing pixels in Q16.16.
        public func sourceToDrawable(_ point: PointQ16) -> PointQ16 {
            let xLogical = Int64(point.x) + Int64(gutterXQ16)
            let yLogical = Int64(point.y) + Int64(gutterYQ16)
            let x = roundDivide(xLogical * Int64(scaleNumerator), Int64(scaleDenominator))
            let y = roundDivide(yLogical * Int64(scaleNumerator), Int64(scaleDenominator))
            return PointQ16(
                x: saturatingInt32(x + Int64(originXQ16)),
                y: saturatingInt32(y + Int64(originYQ16)),
                z: point.z
            )
        }

        /// Inverse of `sourceToDrawable` using the same rational arithmetic.
        /// The result is within one Q16 unit when the drawable dimensions do
        /// not have an exact integer scale.
        public func drawableToSource(_ point: PointQ16) -> PointQ16 {
            let xDrawable = Int64(point.x) - Int64(originXQ16)
            let yDrawable = Int64(point.y) - Int64(originYQ16)
            let xLogical = roundDivide(xDrawable * Int64(scaleDenominator), Int64(scaleNumerator))
            let yLogical = roundDivide(yDrawable * Int64(scaleDenominator), Int64(scaleNumerator))
            return PointQ16(
                x: saturatingInt32(xLogical - Int64(gutterXQ16)),
                y: saturatingInt32(yLogical - Int64(gutterYQ16)),
                z: point.z
            )
        }

        /// Maps normalized clip coordinates to the full drawable.  This is
        /// intentionally separate from the 4:3 UI transform: native 3D uses
        /// the full aspect while source-authored 2D remains centered.
        public func ndcToDrawable(x: Int32, y: Int32, z: Int32) -> PointQ16 {
            let drawableX = roundDivide((Int64(x) + q16One) * Int64(drawableWidth), 2)
            let drawableY = roundDivide((q16One - Int64(y)) * Int64(drawableHeight), 2)
            return PointQ16(
                x: saturatingInt32(drawableX),
                y: saturatingInt32(drawableY),
                z: z
            )
        }
    }

    @frozen public struct ClipVertexV10: Sendable, Equatable {
        public let clipXQ16: Int32
        public let clipYQ16: Int32
        public let clipZQ16: Int32
        public let clipWQ16: Int32
        public let ndcXQ16: Int32
        public let ndcYQ16: Int32
        public let ndcZQ16: Int32
        public let drawableXQ16: Int32
        public let drawableYQ16: Int32
        public let drawableZQ16: Int32
        public let clipFlags: UInt32
        public let reserved: UInt32
    }

    @frozen public struct TriangleResultV10: Sendable, Equatable {
        public let aClipFlags: UInt32
        public let bClipFlags: UInt32
        public let cClipFlags: UInt32
        public let clipOrFlags: UInt32
        public let clipAndFlags: UInt32
        public let faceFlags: UInt32
        public let cullMode: UInt32
        public let reserved: UInt32
        public let signedAreaQ32: Int64
    }

    /// The fixed-width packet record title/stage packets can carry.  Its
    /// first two words intentionally mirror GEAbiHeaderV1; all remaining
    /// fields are scalar/SIMD values with no retained ownership.
    @frozen public struct PacketV10: Sendable, Equatable {
        public let abiVersion: UInt32
        public let structSize: UInt32
        public let contractVersion: UInt32
        public let flags: UInt32
        public let cullMode: UInt32
        public let clipConvention: UInt32
        public let reserved0: UInt32
        public let reserved1: UInt32
        public let viewport: ViewportV10
        public let modelView: MatrixQ16
        public let projection: MatrixQ16
        public let packetHash: UInt64

        public static var fixedSize: Int { MemoryLayout<Self>.size }
        public static let clipConventionN64Symmetric: UInt32 = 1

        public init?(
            viewport: ViewportV10,
            modelView: MatrixQ16,
            projection: MatrixQ16,
            cullMode: UInt32 = GoldenEyeProjectionV10.cullNone,
            flags: UInt32 = GoldenEyeProjectionV10.packetSourceMatrixQuantized |
                GoldenEyeProjectionV10.packetSixPlaneClip
        ) {
            guard cullMode <= GoldenEyeProjectionV10.cullBack else { return nil }
            let knownFlags = GoldenEyeProjectionV10.packetSourceMatrixQuantized |
                GoldenEyeProjectionV10.packetSixPlaneClip |
                GoldenEyeProjectionV10.packetAdaptiveViewport |
                GoldenEyeProjectionV10.packetBackfaceCulling
            guard flags & ~knownFlags == 0 else { return nil }

            var effectiveFlags = flags
            if viewport.isWidescreen || viewport.isLetterboxed {
                effectiveFlags |= GoldenEyeProjectionV10.packetAdaptiveViewport
            }
            if cullMode != GoldenEyeProjectionV10.cullNone {
                effectiveFlags |= GoldenEyeProjectionV10.packetBackfaceCulling
            }

            self.abiVersion = GoldenEyeProjectionV10.abiVersion
            self.structSize = UInt32(Self.fixedSize)
            self.contractVersion = GoldenEyeProjectionV10.contractVersion
            self.flags = effectiveFlags
            self.cullMode = cullMode
            self.clipConvention = Self.clipConventionN64Symmetric
            self.reserved0 = 0
            self.reserved1 = 0
            self.viewport = viewport
            self.modelView = modelView
            self.projection = projection
            self.packetHash = Self.computeHash(
                viewport: viewport,
                modelView: modelView,
                projection: projection,
                flags: effectiveFlags,
                cullMode: cullMode,
                clipConvention: Self.clipConventionN64Symmetric
            )
        }

        public var isValid: Bool {
            abiVersion == GoldenEyeProjectionV10.abiVersion &&
                structSize == UInt32(Self.fixedSize) &&
                contractVersion == GoldenEyeProjectionV10.contractVersion &&
                reserved0 == 0 && reserved1 == 0 &&
                cullMode <= GoldenEyeProjectionV10.cullBack &&
                packetHash == Self.computeHash(
                    viewport: viewport,
                    modelView: modelView,
                    projection: projection,
                    flags: flags,
                    cullMode: cullMode,
                    clipConvention: clipConvention
                )
        }

        public func transform(_ point: PointQ16) -> ClipVertexV10 {
            let model = modelView.applying(to: point)
            let clip = projection.applying(to: PointQ16(x: model.x, y: model.y, z: model.z))
            var flags: UInt32 = 0
            if Int64(clip.x) < -Int64(clip.w) { flags |= GoldenEyeProjectionV10.clipLeft }
            if Int64(clip.x) > Int64(clip.w) { flags |= GoldenEyeProjectionV10.clipRight }
            if Int64(clip.y) < -Int64(clip.w) { flags |= GoldenEyeProjectionV10.clipBottom }
            if Int64(clip.y) > Int64(clip.w) { flags |= GoldenEyeProjectionV10.clipTop }
            if Int64(clip.z) < -Int64(clip.w) { flags |= GoldenEyeProjectionV10.clipNear }
            if Int64(clip.z) > Int64(clip.w) { flags |= GoldenEyeProjectionV10.clipFar }

            let ndcX: Int32
            let ndcY: Int32
            let ndcZ: Int32
            if clip.w <= 0 {
                flags |= GoldenEyeProjectionV10.clipBehind | GoldenEyeProjectionV10.clipInvalidW
                ndcX = 0
                ndcY = 0
                ndcZ = 0
            } else {
                ndcX = saturatingInt32(roundDivide(Int64(clip.x) * q16One, Int64(clip.w)))
                ndcY = saturatingInt32(roundDivide(Int64(clip.y) * q16One, Int64(clip.w)))
                ndcZ = saturatingInt32(roundDivide(Int64(clip.z) * q16One, Int64(clip.w)))
            }
            let drawable = viewport.ndcToDrawable(x: ndcX, y: ndcY, z: ndcZ)
            return ClipVertexV10(
                clipXQ16: clip.x,
                clipYQ16: clip.y,
                clipZQ16: clip.z,
                clipWQ16: clip.w,
                ndcXQ16: ndcX,
                ndcYQ16: ndcY,
                ndcZQ16: ndcZ,
                drawableXQ16: drawable.x,
                drawableYQ16: drawable.y,
                drawableZQ16: drawable.z,
                clipFlags: flags,
                reserved: 0
            )
        }

        public func classifyTriangle(
            _ a: PointQ16,
            _ b: PointQ16,
            _ c: PointQ16
        ) -> TriangleResultV10 {
            let projectedA = transform(a)
            let projectedB = transform(b)
            let projectedC = transform(c)
            let clipOr = projectedA.clipFlags | projectedB.clipFlags | projectedC.clipFlags
            let clipAnd = projectedA.clipFlags & projectedB.clipFlags & projectedC.clipFlags
            let edgeBX = Int64(projectedB.ndcXQ16) - Int64(projectedA.ndcXQ16)
            let edgeBY = Int64(projectedB.ndcYQ16) - Int64(projectedA.ndcYQ16)
            let edgeCX = Int64(projectedC.ndcXQ16) - Int64(projectedA.ndcXQ16)
            let edgeCY = Int64(projectedC.ndcYQ16) - Int64(projectedA.ndcYQ16)
            let area = saturatingMultiplySubtract(edgeBX, edgeCY, edgeBY, edgeCX)

            var faceFlags: UInt32 = 0
            if area > 0 {
                faceFlags |= GoldenEyeProjectionV10.faceFront
            } else if area < 0 {
                faceFlags |= GoldenEyeProjectionV10.faceBack
            } else {
                faceFlags |= GoldenEyeProjectionV10.faceDegenerate
            }
            if clipOr != 0 && clipAnd == 0 {
                faceFlags |= GoldenEyeProjectionV10.faceClipPartial
            } else if clipAnd != 0 {
                faceFlags |= GoldenEyeProjectionV10.faceClipRejected
            }
            if projectedA.clipFlags & GoldenEyeProjectionV10.clipInvalidW != 0 ||
                projectedB.clipFlags & GoldenEyeProjectionV10.clipInvalidW != 0 ||
                projectedC.clipFlags & GoldenEyeProjectionV10.clipInvalidW != 0 {
                faceFlags |= GoldenEyeProjectionV10.faceInvalidW
            }
            if cullMode == GoldenEyeProjectionV10.cullFront &&
                faceFlags & GoldenEyeProjectionV10.faceFront != 0 {
                faceFlags |= GoldenEyeProjectionV10.faceCulled
            } else if cullMode == GoldenEyeProjectionV10.cullBack &&
                faceFlags & GoldenEyeProjectionV10.faceBack != 0 {
                faceFlags |= GoldenEyeProjectionV10.faceCulled
            }

            return TriangleResultV10(
                aClipFlags: projectedA.clipFlags,
                bClipFlags: projectedB.clipFlags,
                cClipFlags: projectedC.clipFlags,
                clipOrFlags: clipOr,
                clipAndFlags: clipAnd,
                faceFlags: faceFlags,
                cullMode: cullMode,
                reserved: 0,
                signedAreaQ32: area
            )
        }

        private static func computeHash(
            viewport: ViewportV10,
            modelView: MatrixQ16,
            projection: MatrixQ16,
            flags: UInt32,
            cullMode: UInt32,
            clipConvention: UInt32
        ) -> UInt64 {
            var hash: UInt64 = 1_469_598_103_934_665_603
            hash = hashU32(hash, GoldenEyeProjectionV10.abiVersion)
            hash = hashU32(hash, GoldenEyeProjectionV10.contractVersion)
            hash = hashU32(hash, flags)
            hash = hashU32(hash, cullMode)
            hash = hashU32(hash, clipConvention)
            hash = hashU32(hash, viewport.drawableWidth)
            hash = hashU32(hash, viewport.drawableHeight)
            hash = hashU32(hash, viewport.scaleNumerator)
            hash = hashU32(hash, viewport.scaleDenominator)
            hash = hashU32(hash, UInt32(bitPattern: viewport.logicalWidthQ16))
            hash = hashU32(hash, UInt32(bitPattern: viewport.logicalHeightQ16))
            hash = hashU32(hash, UInt32(bitPattern: viewport.gutterXQ16))
            hash = hashU32(hash, UInt32(bitPattern: viewport.gutterYQ16))
            hash = hashU32(hash, UInt32(bitPattern: viewport.originXQ16))
            hash = hashU32(hash, UInt32(bitPattern: viewport.originYQ16))
            hash = hashU32(hash, viewport.flags)
            for index in 0..<16 {
                hash = hashU32(hash, UInt32(bitPattern: modelView.values[index]))
            }
            for index in 0..<16 {
                hash = hashU32(hash, UInt32(bitPattern: projection.values[index]))
            }
            return hash
        }
    }

    @inline(__always)
    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        if rhs > 0 && lhs > Int64.max - rhs { return Int64.max }
        if rhs < 0 && lhs < Int64.min - rhs { return Int64.min }
        return lhs + rhs
    }

    @inline(__always)
    private static func saturatingMultiplySubtract(
        _ leftA: Int64,
        _ leftB: Int64,
        _ rightA: Int64,
        _ rightB: Int64
    ) -> Int64 {
        let lhs: Int64
        let rhs: Int64
        let lhsOverflow = leftA.multipliedReportingOverflow(by: leftB)
        let rhsOverflow = rightA.multipliedReportingOverflow(by: rightB)
        lhs = lhsOverflow.overflow ? (leftA.signum() == leftB.signum() ? Int64.max : Int64.min) : lhsOverflow.partialValue
        rhs = rhsOverflow.overflow ? (rightA.signum() == rightB.signum() ? Int64.max : Int64.min) : rhsOverflow.partialValue
        if rhs > 0 && lhs < Int64.min + rhs { return Int64.min }
        if rhs < 0 && lhs > Int64.max + rhs { return Int64.max }
        return lhs - rhs
    }

    @inline(__always)
    private static func quantizedProduct(_ accumulator: Int64) -> Int32 {
        let rounded: Int64
        if accumulator >= 0 {
            rounded = accumulator > Int64.max - 32_768
                ? Int64.max
                : (accumulator + 32_768) >> 16
        } else {
            let magnitude = accumulator == Int64.min ? Int64.max : -accumulator
            rounded = -((magnitude + 32_768) >> 16)
        }
        return saturatingInt32(rounded)
    }

    @inline(__always)
    private static func roundDivide(_ numerator: Int64, _ denominator: Int64) -> Int64 {
        guard denominator != 0 else { return numerator >= 0 ? Int64.max : Int64.min }
        let positive = (numerator >= 0) == (denominator >= 0)
        let numeratorMagnitude = numerator == Int64.min ? Int64.max : (numerator >= 0 ? numerator : -numerator)
        let denominatorMagnitude = denominator == Int64.min ? Int64.max : (denominator >= 0 ? denominator : -denominator)
        let quotient = numeratorMagnitude / denominatorMagnitude
        let remainder = numeratorMagnitude % denominatorMagnitude
        let rounded = quotient + (remainder >= (denominatorMagnitude + 1) / 2 ? 1 : 0)
        if positive {
            return rounded
        }
        return rounded >= Int64.max ? Int64.min : -rounded
    }

    @inline(__always)
    private static func saturatingInt32(_ value: Int64) -> Int32 {
        if value > Int64(Int32.max) { return Int32.max }
        if value < Int64(Int32.min) { return Int32.min }
        return Int32(value)
    }

    @inline(__always)
    private static func hashU32(_ hash: UInt64, _ value: UInt32) -> UInt64 {
        var result = hash
        for shift in stride(from: 0, through: 24, by: 8) {
            result = (result ^ UInt64((value >> UInt32(shift)) & 0xff)) &* 1_099_511_628_211
        }
        return result
    }
}
