import Foundation

@main
struct GoldenEyeBootFlowSmoke {
    static func main() {
        var flow = GoldenEyeBootFlow()
        var snapshot = flow.step()
        precondition(snapshot.screen == .legal)

        for _ in 0..<489 { snapshot = flow.step() }
        precondition(snapshot.screen == .nintendo, "legal must preserve the first-boot timeout")

        let confirm = GoldenEyeTitleInput(pressed: 1 << 0)
        snapshot = flow.step(input: confirm)
        for _ in 0..<8 { snapshot = flow.step() }
        precondition(snapshot.screen == .rareware)

        snapshot = flow.step(input: confirm)
        for _ in 0..<8 { snapshot = flow.step() }
        precondition(snapshot.screen == .gunbarrel)
        let odd = flow.step()
        let even = flow.step()
        precondition(odd.pairPhase == 1 && even.pairPhase == 0)
        precondition(odd.renderHash != even.renderHash, "gunbarrel half-step must be visible")

        snapshot = flow.step(input: confirm)
        for _ in 0..<8 { snapshot = flow.step() }
        precondition(snapshot.screen == .goldenEye)
        snapshot = flow.step(input: confirm)
        for _ in 0..<8 { snapshot = flow.step() }
        precondition(snapshot.screen == .fileSelect)
        snapshot = flow.step(input: confirm)
        for _ in 0..<8 { snapshot = flow.step() }
        precondition(snapshot.screen == .modeSelect)

        // Source erase is a two-stage action and defaults to Cancel. Return
        // to File Select, open Erase, verify the first confirm is harmless,
        // then move to Erase and confirm the destructive action.
        snapshot = flow.step(input: GoldenEyeTitleInput(pressed: 1 << 1))
        for _ in 0..<8 { snapshot = flow.step() }
        precondition(snapshot.screen == .fileSelect)
        snapshot = flow.step(input: GoldenEyeTitleInput(stickX: 75))
        snapshot = flow.step(input: GoldenEyeTitleInput(stickX: 75))
        precondition(snapshot.subphase == 2)
        let beforeErase = flow.saveStateSnapshot()
        snapshot = flow.step(input: confirm)
        precondition(snapshot.screen == .fileSelect && snapshot.subphase == 3)
        precondition(flow.saveStateSnapshot() == beforeErase)
        snapshot = flow.step(input: confirm)
        precondition(flow.saveStateSnapshot() == beforeErase)
        snapshot = flow.step(input: GoldenEyeTitleInput(stickX: 75))
        snapshot = flow.step(input: GoldenEyeTitleInput(stickX: 75))
        precondition(snapshot.subphase == 2)
        snapshot = flow.step(input: confirm)
        precondition(snapshot.subphase == 3)
        snapshot = flow.step(input: GoldenEyeTitleInput(stickY: -75))
        precondition(snapshot.subphase == 4)
        _ = flow.step(input: confirm)
        precondition(flow.saveStateSnapshot().folders[0].hasCompletedMission == false)

        print("goldeneye_boot_flow_smoke: PASS")
    }
}
