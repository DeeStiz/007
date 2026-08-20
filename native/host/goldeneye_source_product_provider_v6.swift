import Foundation

/// Source-side matrix/viewport authority.  Kept separate from the Metal
/// renderer so the exact value provider can be tested without GPU objects.
@available(macOS 26.0, *)
protocol GoldenEyeSourceProductFrameResourceProviderV6: AnyObject, Sendable {
    func frameResources(
        for sourceFrame: GoldenEyeSourceFrontendFrameV6
    ) throws -> GoldenEyeSourceProductFrameResourcesV6
}
