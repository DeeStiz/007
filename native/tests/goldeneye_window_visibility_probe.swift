import CoreGraphics
import Foundation

guard let windows = CGWindowListCopyWindowInfo(
    [.optionAll],
    kCGNullWindowID
) as? [[String: Any]] else {
    print("window_count=0")
    exit(1)
}

print("window_count=\(windows.count)")
for window in windows {
    let owner = window[kCGWindowOwnerName as String] as? String ?? ""
    let name = window[kCGWindowName as String] as? String ?? ""
    let onscreen = (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue == true
    let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0
    let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let x = (bounds["X"] as? NSNumber)?.doubleValue ?? 0
    let y = (bounds["Y"] as? NSNumber)?.doubleValue ?? 0
    let width = (bounds["Width"] as? NSNumber)?.doubleValue ?? 0
    let height = (bounds["Height"] as? NSNumber)?.doubleValue ?? 0
    print(
        "owner=\(owner) name=\(name) onscreen=\(onscreen ? 1 : 0) "
            + "alpha=\(alpha) layer=\(layer) "
            + "bounds=x:\(x),y:\(y),width:\(width),height:\(height)"
    )
}
