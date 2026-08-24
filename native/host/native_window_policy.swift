/// Resolves whether the AppKit host is allowed to participate in foreground
/// activation. Background mode is fail-safe: an explicit background request
/// always wins over probe flags, and unattended probes default to passive.
struct GoldenEyeNativeWindowPolicy: Equatable {
    let runsInBackground: Bool

    static func resolve(
        environment: [String: String]
    ) -> GoldenEyeNativeWindowPolicy {
        // Fail safe for an unset, malformed, or future value. A process may
        // take foreground control only when the caller explicitly asks for
        // the documented interactive mode.
        if environment["GOLDENEYE_NATIVE_BACKGROUND"] == "0" {
            return GoldenEyeNativeWindowPolicy(runsInBackground: false)
        }
        return GoldenEyeNativeWindowPolicy(runsInBackground: true)
    }
}
