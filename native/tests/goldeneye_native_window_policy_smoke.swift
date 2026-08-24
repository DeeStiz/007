private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError("goldeneye native window policy: \(message)")
    }
}

private func background(
    _ environment: [String: String]
) -> Bool {
    GoldenEyeNativeWindowPolicy.resolve(
        environment: environment
    ).runsInBackground
}

@main
struct GoldenEyeNativeWindowPolicySmoke {
    static func main() {
        require(background(["GOLDENEYE_NATIVE_BACKGROUND": "1"]),
                "explicit background request must be passive")
        require(background([
            "GOLDENEYE_NATIVE_BACKGROUND": "1",
            "GOLDENEYE_CADENCE_PROBE": "1",
        ]), "cadence probe must not override explicit background mode")
require(!background([
    "GOLDENEYE_NATIVE_BACKGROUND": "0",
    "GOLDENEYE_CADENCE_PROBE": "1",
]), "explicit interactive mode must remain available")
        require(background(["GOLDENEYE_CADENCE_PROBE": "1"]),
                "unattended cadence probes must default to passive")
        require(background(["GOLDENEYE_M3_EVENT_PROBE": "1"]),
                "unattended input probes must default to passive")
        require(background(["GOLDENEYE_M5_PAUSE_PROBE": "1"]),
                "unattended pause probes must default to passive")
        require(background(["GOLDENEYE_M27_STAGE_OVERLAY": "1"]),
                "unattended stage probes must default to passive")
        require(background(["GOLDENEYE_NATIVE_TITLE": "1"]),
                "source-title runtime must default to passive")
require(background([:]),
        "an unconfigured launch must default to passive")
require(background(["GOLDENEYE_NATIVE_BACKGROUND": "invalid"]),
        "an invalid background value must fail safe to passive")

        print("goldeneye_native_window_policy_smoke: PASS")
    }
}
