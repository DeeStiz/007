import Foundation

/// GPU staging vertex for one source-derived title icon quad.  The record is
/// value-only and mirrors the Metal shader's float2/float2/float4 layout.
struct GoldenEyeTitleIconGPUVertex: Sendable {
    let position: SIMD2<Float>
    let uv: SIMD2<Float>
    let color: SIMD4<Float>
}

enum GoldenEyeTitleIconGeometry {
    static func quad(
        record: GoldenEyeTitleIconPacket.Record,
        center: SIMD2<Float>,
        alpha: Float = 1,
        logicalWidth: Float = 440,
        logicalHeight: Float = 330
    ) -> [GoldenEyeTitleIconGPUVertex] {
        let half = SIMD2<Float>(Float(record.width) * 0.5, Float(record.height) * 0.5)
        let minPoint = center - half
        let maxPoint = center + half
        func clip(_ point: SIMD2<Float>) -> SIMD2<Float> {
            SIMD2<Float>(point.x / logicalWidth * 2 - 1, 1 - point.y / logicalHeight * 2)
        }
        let colour = SIMD4<Float>(1, 1, 1, alpha)
        return [
            GoldenEyeTitleIconGPUVertex(position: clip(SIMD2(minPoint.x, minPoint.y)), uv: SIMD2(0, 0), color: colour),
            GoldenEyeTitleIconGPUVertex(position: clip(SIMD2(maxPoint.x, minPoint.y)), uv: SIMD2(1, 0), color: colour),
            GoldenEyeTitleIconGPUVertex(position: clip(SIMD2(maxPoint.x, maxPoint.y)), uv: SIMD2(1, 1), color: colour),
            GoldenEyeTitleIconGPUVertex(position: clip(SIMD2(minPoint.x, maxPoint.y)), uv: SIMD2(0, 1), color: colour),
        ]
    }
}

private let goldenEyeTitleIconVertexLayoutGuard: Void = {
    precondition(MemoryLayout<GoldenEyeTitleIconGPUVertex>.stride == 32)
}()
