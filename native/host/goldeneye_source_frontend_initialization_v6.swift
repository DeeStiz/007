import Foundation
#if canImport(GoldenEyeNative)
import GoldenEyeNative
#endif

/// Tracks the authority's tick-0 lifecycle records independently from the
/// first renderable source frame.  Tick zero is consumed once per owner
/// lifetime; pause/resume does not re-run it, while a newly constructed owner
/// gets a fresh ledger.
struct GoldenEyeSourceFrontendInitializationLedgerV6: Sendable {
    private(set) var consumed = false
    private(set) var pendingModelLoads: Set<UInt32> = []

    @discardableResult
    mutating func consume(
        frame: GoldenEyeSourceFrontendFrameV6
    ) throws -> Bool {
        guard frame.nativeTick == 0 else {
            throw GoldenEyeSourceFrontendInitializationError.nonZeroTick(frame.nativeTick)
        }
        guard !consumed else { return false }
        consumed = true
        pendingModelLoads = Set(
            frame.modelEvents
                .filter { $0.operation == UInt32(GE_SOURCE_FRONTEND_RUNTIME_V6_MODEL_OP_LOAD) }
                .map(\.model)
        )
        return true
    }

    @discardableResult
    mutating func acknowledgeModelLoad(model: UInt32) -> Bool {
        pendingModelLoads.remove(model) != nil
    }
}

enum GoldenEyeSourceFrontendInitializationError: Error, Sendable, Equatable,
    CustomStringConvertible
{
    case nonZeroTick(UInt64)

    var description: String {
        switch self {
        case .nonZeroTick(let tick):
            return "source frontend initialization frame must be tick zero (got \(tick))"
        }
    }
}
