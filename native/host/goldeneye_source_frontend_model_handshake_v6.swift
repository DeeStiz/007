import Foundation

/// The one-tick value handoff between a source model event and the next
/// source-authority step.  It consumes a successful result exactly once; a
/// renderer that did not execute the request leaves the next authority input
/// zero-valued and therefore fail-closed.
struct GoldenEyeSourceFrontendModelResultInputV6: Sendable, Equatable {
    let model: UInt32
    let operation: UInt32
    let flags: UInt32
    let value0: UInt32
    let value1: UInt32

    static let none = Self(model: 0, operation: 0, flags: 0, value0: 0, value1: 0)
}
struct GoldenEyeSourceFrontendModelHandshakeV6: Sendable {
    private var pending: GoldenEyeSourceProductModelExecutionResultV6?

    init() {
        pending = nil
    }

    mutating func takeForAuthority() -> GoldenEyeSourceFrontendModelResultInputV6 {
        guard let result = pending else { return .none }
        pending = nil
        return GoldenEyeSourceFrontendModelResultInputV6(
            model: result.model,
            operation: result.operation,
            flags: result.flags,
            value0: result.value0,
            value1: result.value1
        )
    }

    mutating func retainSuccessfulResult(
        _ result: GoldenEyeSourceProductModelExecutionResultV6?
    ) {
        guard let result, result.isExecuted else {
            pending = nil
            return
        }
        pending = result
    }
}
