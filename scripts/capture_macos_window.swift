import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let targetPID = Int32(CommandLine.arguments[1])!
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let windows = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements],
    kCGNullWindowID
) as? [[String: Any]] ?? []

var targetID: CGWindowID?
var largestArea: CGFloat = 0
for window in windows {
    guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32,
          ownerPID == targetPID,
          let number = window[kCGWindowNumber as String] as? CGWindowID,
          let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
          let width = bounds["Width"],
          let height = bounds["Height"] else { continue }
    let area = width * height
    if area > largestArea {
        largestArea = area
        targetID = number
    }
}

guard let targetID,
      let image = CGWindowListCreateImage(.null, .optionIncludingWindow, targetID, [.boundsIgnoreFraming, .bestResolution]),
      let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else {
    fputs("could not capture target macOS window\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
