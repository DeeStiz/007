import Foundation
import GoldenEyeOriginalFrontend

/// Product-link seam for the source oracle.  It is intentionally opt-in: the
/// production target has fail-closed model/platform sinks and must not be
/// mistaken for a complete visual frontend until those services are present.
enum GoldenEyeOriginalFrontendProductionLink {
    static func initialize() -> UInt32 {
        var state = GEOriginalFrontendStateV6()
        return ge_original_frontend_v6_init(&state)
    }
}
