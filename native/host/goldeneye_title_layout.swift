import Foundation

/// Canonical frontend layout and inverse hit testing.  Source coordinates stay
/// in 440x330 logical units; only the viewport transform knows about backing
/// pixels, gutters, and letterboxing.
public struct GoldenEyeTitleLayout: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        public let x: Double
        public let y: Double
    }

    public struct Rect: Sendable, Equatable {
        public let minX: Double
        public let minY: Double
        public let maxX: Double
        public let maxY: Double

        public init(_ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double) {
            self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
        }

        public func contains(_ point: Point) -> Bool {
            point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
        }
    }

    public enum FileSelectHit: Sendable, Equatable {
        case wallet(UInt8)
        case select
        case copy
        case erase
        case previousTab
        case none
    }

    public enum ModeSelectHit: Sendable, Equatable {
        case solo
        case multiplayer
        case none
    }

    public let drawableWidth: Double
    public let drawableHeight: Double
    public let scale: Double
    public let logicalWidth: Double
    public let logicalHeight: Double
    public let originX: Double
    public let originY: Double
    public let gutter: Double

    public init(drawableWidth: Double, drawableHeight: Double) {
        precondition(drawableWidth > 0 && drawableHeight > 0)
        self.drawableWidth = drawableWidth
        self.drawableHeight = drawableHeight
        let sourceAspect = 440.0 / 330.0
        let aspect = drawableWidth / drawableHeight
        if aspect >= sourceAspect {
            scale = drawableHeight / 330.0
            logicalWidth = drawableWidth / scale
            logicalHeight = 330.0
            gutter = (logicalWidth - 440.0) * 0.5
            originX = 0
            originY = 0
        } else {
            scale = drawableWidth / 440.0
            logicalWidth = 440.0
            logicalHeight = drawableHeight / scale
            gutter = 0
            originX = 0
            originY = (logicalHeight - 330.0) * 0.5
        }
    }

    public func sourceToDrawable(_ point: Point) -> Point {
        Point(
            x: (point.x + gutter) * scale + originX,
            y: (point.y + originY) * scale
        )
    }

    public func drawableToLogical(_ point: Point) -> Point {
        Point(
            x: (point.x - originX) / scale - gutter,
            y: (point.y / scale) - originY
        )
    }

    public func sourceToDrawableRect(_ rect: Rect) -> Rect {
        let lower = sourceToDrawable(Point(x: rect.minX, y: rect.minY))
        let upper = sourceToDrawable(Point(x: rect.maxX, y: rect.maxY))
        return Rect(lower.x, lower.y, upper.x, upper.y)
    }

    public func fileSelectHit(_ drawablePoint: Point) -> FileSelectHit {
        let point = drawableToLogical(drawablePoint)
        // Four authored wallet slots.  The source wallet model is centered in
        // this same logical core; these bounds are shared by draw and input.
        let walletCenters = [76.0, 172.0, 268.0, 364.0]
        for (index, center) in walletCenters.enumerated() {
            if Rect(center - 40, 112, center + 40, 224).contains(point) {
                return .wallet(UInt8(index))
            }
        }
        if Rect(49, 276, 171, 299).contains(point) { return .select }
        if Rect(209, 271, 241, 299).contains(point) { return .copy }
        if Rect(319, 271, 351, 299).contains(point) { return .erase }
        if Rect(390, 223, 411, 250).contains(point) { return .previousTab }
        return .none
    }

    public func modeSelectHit(_ drawablePoint: Point) -> ModeSelectHit {
        let point = drawableToLogical(drawablePoint)
        if Rect(145, 204, 360, 236).contains(point) { return .solo }
        if Rect(145, 236, 360, 268).contains(point) { return .multiplayer }
        return .none
    }
}
