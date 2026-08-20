import Foundation

@main
struct GoldenEyeTitleLayoutSmoke {
    static func main() {
        let source = GoldenEyeTitleLayout(drawableWidth: 440, drawableHeight: 330)
        precondition(source.gutter == 0 && source.scale == 1)
        precondition(source.fileSelectHit(.init(x: 110, y: 285)) == .select)
        precondition(source.fileSelectHit(.init(x: 225, y: 285)) == .copy)
        precondition(source.fileSelectHit(.init(x: 335, y: 285)) == .erase)
        precondition(source.modeSelectHit(.init(x: 170, y: 220)) == .solo)
        precondition(source.modeSelectHit(.init(x: 170, y: 252)) == .multiplayer)

        let downscaled = GoldenEyeTitleLayout(drawableWidth: 320, drawableHeight: 240)
        precondition(abs(downscaled.scale - 8.0 / 11.0) < 0.000_001)
        let wide = GoldenEyeTitleLayout(drawableWidth: 1920, drawableHeight: 1080)
        precondition(abs(wide.scale - 1080.0 / 330.0) < 0.000_001)
        precondition(wide.gutter > 0)
        let sourcePoint = GoldenEyeTitleLayout.Point(x: 335, y: 285)
        let roundTrip = wide.drawableToLogical(wide.sourceToDrawable(sourcePoint))
        precondition(abs(roundTrip.x - sourcePoint.x) < 0.000_001)
        precondition(abs(roundTrip.y - sourcePoint.y) < 0.000_001)
        precondition(wide.fileSelectHit(wide.sourceToDrawable(sourcePoint)) == .erase)

        let ultra = GoldenEyeTitleLayout(drawableWidth: 2560, drawableHeight: 1080)
        precondition(ultra.logicalWidth > 440 && ultra.gutter > wide.gutter)
        print("goldeneye_title_layout_smoke: PASS 320x240=8/11 1920x1080-gutter=\(wide.gutter) ultrawide-gutter=\(ultra.gutter)")
    }
}
